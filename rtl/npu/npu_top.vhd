-- npu_top.vhd - INT8 N x N systolic GEMM accelerator (uncached MMIO slave), generic N.
-- Integrates: A(N row) + B(N col) async-read distributed-RAM scratchpads, the
-- skew feeder, the control FSM, the MMIO register/decode, and the N x N npu_array.
-- One invocation computes C[N][N] += A[N][K]*B[K][N] over contraction depth K
-- (1..64; deeper K is tiled by the driving program).
--
-- Generics:
--   N   array dimension (default 8; set 16 for scale-up). NBITS = ceil(log2 N).
--   AW  address-port width = NBITS + 10 (8 for N=8 -> 13; for N=16 -> 14). The
--       wrapper picks AW so a CPU `sw`/`lw` addresses the whole map.
--
-- Writes are WORD-aligned with the INT8 in wdata[7:0] (so a CPU `sw` is
-- unambiguous regardless of byte-lane strobing). MMIO map (byte offset = addr):
--   region = addr[AW-1:AW-2] : 00 CTRL/STATUS/K/CFG, 01 A_BUF, 10 B_BUF, 11 C_BUF
--   0x.000  CTRL   (W) bit0 start (pulse), bit1 clr_acc          [region 00, addr[3:2]=00]
--   0x.004  STATUS (R) bit0 busy, bit1 done                      [region 00, addr[3:2]=01]
--   0x.008  K_DIM  (W) contraction depth K (1..64)               [region 00, addr[3:2]=10]
--   0x.00C  CFG    (W) requantize: mult[31:16] (uint), shift[13:8], enable[0] [addr[3:2]=11]
--   A_BUF   (W word) row=addr[NBITS+7:8], k=addr[7:2] -> A[row][k] = wdata[7:0]
--   B_BUF   (W word) col=addr[NBITS+7:8], k=addr[7:2] -> B[k][col] = wdata[7:0]
--   C_BUF   (R word) idx=addr[2*NBITS+1:2]=i*N+j -> C[i][j]: raw INT32, or (CFG.en=1)
--             requantized INT8 = clip((C*mult + round) >> shift, -128, 127), sign-ext
--
-- For N=8 the layout is bit-identical to the original 8 KiB design (region at
-- addr[12:11]; A=0x800, B=0x1000, C=0x1800). For N=16 the window is 16 KiB
-- (region at addr[13:12]; A=0x1000, B=0x2000, C=0x3000).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity npu_top is
    generic (
        N          : integer := 8;     -- array dimension
        AW         : integer := 13;    -- address width = ceil(log2 N) + 10
        DSP_BUDGET : integer := 256;   -- # PEs mapped to DSP48E1 (rest = LUT MAC)
        NLANE      : integer := 8      -- # row-0 PEs shared as GPU lanes (shared DSP)
    );
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;                          -- sync, active-high
        sel    : in  std_logic;                          -- access in NPU window this cycle
        we     : in  std_logic;                          -- 1=write 0=read
        addr   : in  std_logic_vector(AW-1 downto 0);    -- byte offset within window
        wdata  : in  std_logic_vector(31 downto 0);
        wstrb  : in  std_logic_vector(3 downto 0);        -- (unused: word-aligned writes)
        re     : in  std_logic := '0';                    -- read strobe (pipelined readback)
        rdata  : out std_logic_vector(31 downto 0);
        rd_valid : out std_logic;                         -- '1' when rdata holds the requested word
        -- GPU shared-lane bus (passes straight through to the npu_array row-0 PEs)
        gpu_mode : in  std_logic := '0';
        g_a_flat : in  std_logic_vector(NLANE*16-1 downto 0) := (others => '0');
        g_b_flat : in  std_logic_vector(NLANE*16-1 downto 0) := (others => '0');
        g_c_flat : in  std_logic_vector(NLANE*32-1 downto 0) := (others => '0');
        g_y_flat : out std_logic_vector(NLANE*32-1 downto 0)
    );
end npu_top;

architecture rtl of npu_top is
    function clog2(x : integer) return integer is
        variable r : integer := 0;
        variable v : integer := 1;
    begin
        while v < x loop v := v*2; r := r+1; end loop;
        return r;
    end function;

    constant KMAX  : integer := 64;
    constant NBITS : integer := clog2(N);     -- 3 for N=8, 4 for N=16
    -- field positions inside the byte address
    constant RHI : integer := AW-1;           -- region MSB  (NBITS+9)
    constant RLO : integer := AW-2;           -- region LSB  (NBITS+8)
    constant XHI : integer := NBITS+7;        -- row/col MSB
    constant XLO : integer := 8;              -- row/col LSB
    constant CHI : integer := 2*NBITS+1;      -- C-index MSB
    -- scratchpads: N A-rows + N B-cols, each KMAX deep x 8 bit, async read.
    type memk8  is array (0 to KMAX-1)  of std_logic_vector(7 downto 0);
    type bank_t is array (0 to N-1)     of memk8;
    signal amem : bank_t;
    signal bmem : bank_t;
    attribute ram_style : string;
    attribute ram_style of amem : signal is "distributed";
    attribute ram_style of bmem : signal is "distributed";

    type state_t is (S_IDLE, S_CLEAR, S_RUN, S_DONE);
    signal st       : state_t := S_IDLE;
    signal k_dim    : unsigned(6 downto 0) := (others => '0');   -- 1..64
    signal clr_acc  : std_logic := '1';
    signal t        : unsigned(9 downto 0) := (others => '0');
    signal t_last   : unsigned(9 downto 0);
    signal busy, done_l : std_logic := '0';
    signal cfg          : std_logic_vector(31 downto 0) := (others => '0'); -- requant: mult[31:16] shift[13:8] en[0]

    signal arr_en, arr_clr : std_logic;
    signal a_west, b_north : std_logic_vector(N*8-1 downto 0);
    signal a_west_q, b_north_q : std_logic_vector(N*8-1 downto 0) := (others=>'0'); -- registered feed (breaks t->PE path)
    signal acc_flat        : std_logic_vector(N*N*32-1 downto 0);

    signal wr : std_logic;
    signal region : std_logic_vector(1 downto 0);
    signal is_ctrl, is_a, is_b, is_c : std_logic;

    -- pipelined C read-back (splits the 256:1 acc_flat select into staged muxes so
    -- the path PE-acc -> core no longer fails timing).  3-cycle latency, handshaked
    -- with rd_valid; the core's mem_stall holds the load until rd_valid.
    type word_arr is array (0 to N-1) of std_logic_vector(31 downto 0);
    signal row_words : word_arr;                          -- stage1: per-row col-selected word
    signal acc_sel   : std_logic_vector(31 downto 0);     -- stage2: row-selected accumulator
    signal prod_q    : signed(63 downto 0);               -- stage3: requant multiply (-> DSP)
    signal shf_q     : signed(63 downto 0);               -- stage4: rounded + shifted
    signal rdata_q   : std_logic_vector(31 downto 0);     -- stage5: finalized (raw/requant/status)
    signal rd_cnt    : integer range 0 to 5 := 0;
    signal row_idx_q : integer range 0 to N-1 := 0;
    signal is_c_q, is_ctrl_q : std_logic := '0';
    signal addr32_q  : std_logic_vector(1 downto 0) := "00";
    signal col_idx   : integer range 0 to N-1;
    signal row_idx   : integer range 0 to N-1;
    signal rd_req    : std_logic;
begin
    ----------------------------------------------------------------------------
    -- decode  (region = top two used address bits)
    ----------------------------------------------------------------------------
    wr      <= sel and we;
    region  <= addr(RHI downto RLO);
    is_ctrl <= '1' when (sel='1' and region="00") else '0';
    is_a    <= '1' when (sel='1' and region="01") else '0';
    is_b    <= '1' when (sel='1' and region="10") else '0';
    is_c    <= '1' when (sel='1' and region="11") else '0';

    ----------------------------------------------------------------------------
    -- scratchpad writes (word-aligned, INT8 in wdata[7:0]) + async skew reads
    ----------------------------------------------------------------------------
    gen_bank : for n in 0 to N-1 generate
        process(clk)
        begin
            if rising_edge(clk) then
                if (wr='1' and is_a='1' and to_integer(unsigned(addr(XHI downto XLO)))=n) then
                    amem(n)(to_integer(unsigned(addr(7 downto 2)))) <= wdata(7 downto 0);
                end if;
                if (wr='1' and is_b='1' and to_integer(unsigned(addr(XHI downto XLO)))=n) then
                    bmem(n)(to_integer(unsigned(addr(7 downto 2)))) <= wdata(7 downto 0);
                end if;
            end if;
        end process;
    end generate;

    -- row i reads A[i][t-i], col j reads B[t-j][j]; 0 outside [0,K-1].
    gen_feed : for n in 0 to N-1 generate
        process(t, st, k_dim, amem, bmem)
            variable ra : integer;
        begin
            ra := to_integer(t) - n;
            if (st=S_RUN and ra >= 0 and ra < to_integer(k_dim)) then
                a_west(n*8+7 downto n*8)  <= amem(n)(ra);
                b_north(n*8+7 downto n*8) <= bmem(n)(ra);
            else
                a_west(n*8+7 downto n*8)  <= (others => '0');
                b_north(n*8+7 downto n*8) <= (others => '0');
            end if;
        end process;
    end generate;

    -- register the skewed feed so the long t -> (t-n) -> scratchpad -> PE path is
    -- broken at a flop.  Delays the whole input stream uniformly by 1 cycle (relative
    -- skew preserved) => bit-identical result, one extra run cycle (t_last+1).
    process(clk)
    begin
        if rising_edge(clk) then
            a_west_q  <= a_west;
            b_north_q <= b_north;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- control FSM
    ----------------------------------------------------------------------------
    arr_en  <= '1' when st=S_RUN else '0';
    arr_clr <= '1' when (st=S_CLEAR and clr_acc='1') else '0';
    t_last  <= resize(k_dim, 10) + (2*N-2);  -- +1 vs before: feed pipeline reg adds 1 cycle

    process(clk)
    begin
        if rising_edge(clk) then
            if rst='1' then
                st <= S_IDLE; busy <= '0'; done_l <= '0'; t <= (others=>'0');
            else
                case st is
                    when S_IDLE =>
                        busy <= '0';
                        if (wr='1' and is_ctrl='1' and addr(3 downto 2)="00" and wdata(0)='1') then
                            clr_acc <= wdata(1);
                            done_l  <= '0'; busy <= '1';
                            t       <= (others=>'0');
                            st      <= S_CLEAR;
                        end if;
                    when S_CLEAR =>
                        t  <= (others=>'0');
                        st <= S_RUN;
                    when S_RUN =>
                        if t >= t_last then
                            st <= S_DONE; busy <= '0'; done_l <= '1';
                        else
                            t <= t + 1;
                        end if;
                    when S_DONE =>
                        st <= S_IDLE;
                end case;
                if (wr='1' and is_ctrl='1' and addr(3 downto 2)="10") then
                    k_dim <= unsigned(wdata(6 downto 0));
                end if;
                if (wr='1' and is_ctrl='1' and addr(3 downto 2)="11") then
                    cfg <= wdata;          -- CFG: requant mult[31:16] / shift[13:8] / enable[0]
                end if;
            end if;
        end if;
    end process;

    u_array : entity work.npu_array
        generic map (N => N, DSP_BUDGET => DSP_BUDGET, NLANE => NLANE)
        port map (clk=>clk, en=>arr_en, clr=>arr_clr,
                  a_west=>a_west_q, b_north=>b_north_q, acc_flat=>acc_flat,
                  gpu_mode=>gpu_mode, g_a_flat=>g_a_flat, g_b_flat=>g_b_flat,
                  g_c_flat=>g_c_flat, g_y_flat=>g_y_flat);

    ----------------------------------------------------------------------------
    -- pipelined read-back (5 stages) -- closes timing toward 100 MHz
    ----------------------------------------------------------------------------
    --  s0 col-select (per row)   s1 row-select   s2 requant multiply (->DSP)
    --  s3 round+arith-shift       s4 clip + select raw/requant/status
    -- The 256:1 accumulator mux AND the requant multiply (32x17, was 19 CARRY4
    -- in one combinational cloud -> the -3.3..-5.4 ns path) are each isolated in
    -- their own registered stage.  Read held by core (re=1,we=0); rd_valid pulses
    -- when rdata_q is valid (5-clk latency, transparent via mem_stall). MAC array
    -- untouched.
    rd_req  <= sel and re and (not we);
    col_idx <= to_integer(unsigned(addr(NBITS+1 downto 2)));      -- cw mod N  (column)
    row_idx <= to_integer(unsigned(addr(CHI downto NBITS+2)));    -- cw / N    (row)

    process(clk)
        variable mult_s : signed(16 downto 0);
        variable sh     : integer range 0 to 63;
        variable rnd    : signed(63 downto 0);
        variable q8     : signed(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst='1' then
                rd_cnt <= 0;
            elsif rd_req='1' then
                case rd_cnt is
                    when 0 =>                                    -- s0: column select per row
                        for r in 0 to N-1 loop
                            row_words(r) <= acc_flat((r*N+col_idx)*32+31 downto (r*N+col_idx)*32);
                        end loop;
                        row_idx_q <= row_idx;
                        is_c_q    <= is_c;
                        is_ctrl_q <= is_ctrl;
                        addr32_q  <= addr(3 downto 2);
                        rd_cnt    <= 1;
                    when 1 =>                                    -- s1: row select
                        acc_sel <= row_words(row_idx_q);
                        rd_cnt  <= 2;
                    when 2 =>                                    -- s2: requant multiply (registered -> DSP)
                        mult_s := signed('0' & cfg(31 downto 16));
                        prod_q <= resize(signed(acc_sel) * mult_s, 64);
                        rd_cnt <= 3;
                    when 3 =>                                    -- s3: round + arithmetic shift (registered)
                        sh := to_integer(unsigned(cfg(13 downto 8)));
                        if sh > 0 then
                            rnd := prod_q + shift_left(to_signed(1, 64), sh-1);
                        else
                            rnd := prod_q;
                        end if;
                        shf_q <= shift_right(rnd, sh);
                        rd_cnt <= 4;
                    when 4 =>                                    -- s4: clip + select raw/requant/status
                        if    shf_q > 127  then q8 := to_signed(127, 8);
                        elsif shf_q < -128 then q8 := to_signed(-128, 8);
                        else  q8 := resize(shf_q, 8);
                        end if;
                        if is_c_q='1' then
                            if cfg(0)='1' then
                                rdata_q <= std_logic_vector(resize(q8, 32));  -- requant INT8 (sign-ext)
                            else
                                rdata_q <= acc_sel;                           -- raw INT32
                            end if;
                        elsif is_ctrl_q='1' and addr32_q="01" then
                            rdata_q <= (1 => done_l, 0 => busy, others => '0');
                        else
                            rdata_q <= (others => '0');
                        end if;
                        rd_cnt <= 5;
                    when others =>                               -- 5: valid 1 clk, then rearm
                        rd_cnt <= 0;
                end case;
            else
                rd_cnt <= 0;                                     -- no access -> rearm
            end if;
        end if;
    end process;

    rdata    <= rdata_q;
    rd_valid <= '1' when rd_cnt = 5 else '0';
end rtl;
