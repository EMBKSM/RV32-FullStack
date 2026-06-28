-- =====================================================================
-- gpu_core.vhd  -  SIMT-lite engine: one PC, lockstep N-lane datapath,
-- per-lane predicate mask.  Implementation/timing-ready.
--
-- Memory: scratchpad = 8 synchronous-read/write banks -> block RAM (1-cycle
-- read latency absorbed by S_VLD2). imem/vreg = small register/distributed
-- arrays (combinational read).
--
-- Datapath pipeline (to close timing): the long path
--   imem -> operand -> DSP multiply -> result-mux -> vreg
-- is split so the DSP sits in its own clock cycle. Vector ALU ops take 3
-- cycles -- S_RUN (decode, latch operands) -> S_EX (lane ALU/DSP -> result
-- reg) -> S_WB (write vreg/mask). Simple ops (move/scalar/mask/branch/VST)
-- stay 1 cycle; VLD is 3 / VST is 2 -- the scratchpad
-- row index is registered (ld_row_r) so the BRAM address port sits off the
-- fetch->decode->scalar-adder path (the post-pipeline critical path).
-- See docs/GPU_DESIGN.md.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gpu_pkg.all;

entity gpu_core is
    generic (
        LANES  : integer := GPU_LANES;
        VREGS  : integer := GPU_VREGS;
        SREGS  : integer := GPU_SREGS;
        IMEM_D : integer := GPU_IMEM;
        BANK_D : integer := GPU_BANKD
    );
    port (
        clk, rst  : in  std_logic;
        start     : in  std_logic;
        busy      : out std_logic;
        done      : out std_logic;
        imem_we   : in  std_logic;
        imem_addr : in  std_logic_vector(15 downto 0);
        imem_wd   : in  std_logic_vector(31 downto 0);
        sarg_we   : in  std_logic;
        sarg_idx  : in  std_logic_vector(2 downto 0);
        sarg_data : in  std_logic_vector(31 downto 0);
        sp_we     : in  std_logic;
        sp_addr   : in  std_logic_vector(15 downto 0);
        sp_wd     : in  std_logic_vector(31 downto 0);
        sp_rd     : out std_logic_vector(31 downto 0)
    );
end entity gpu_core;

architecture rtl of gpu_core is

    type vregfile_t is array (0 to VREGS-1) of word_array(0 to LANES-1);

    signal vreg : vregfile_t := (others => (others => (others => '0')));
    signal sreg : word_array(0 to SREGS-1) := (others => (others => '0'));
    signal imem : word_array(0 to IMEM_D-1) := (others => (others => '0'));
    signal bdin : word_array(0 to LANES-1);
    signal mask : std_logic_vector(0 to LANES-1) := (others => '1');

    type state_t is (S_IDLE, S_RUN, S_EX, S_WB, S_VLD2, S_VLD3, S_VST2, S_DONE);
    signal state : state_t := S_IDLE;
    signal pc    : integer range 0 to IMEM_D-1 := 0;

    -- decode (combinational from imem(pc))
    signal instr : std_logic_vector(31 downto 0);
    signal op    : opcode_t;
    signal di, ai, bi : integer range 0 to 7;
    signal imm_s : signed(31 downto 0);
    signal lane_op : aluop_t;

    -- pipeline registers (operands + control captured in S_RUN, used in S_EX/S_WB)
    signal opa_r, opb_r, opc_r, res_r : word_array(0 to LANES-1);
    signal ly    : word_array(0 to LANES-1);
    signal lflag, flag_r, mask_r : std_logic_vector(0 to LANES-1);
    signal lane_op_r : aluop_t := A_ADD;
    signal op_r  : opcode_t := OP_HALT;
    signal di_r  : integer range 0 to 7 := 0;

    -- scratchpad (BRAM) access
    signal bank_dout   : word_array(0 to LANES-1);
    signal cpu_bank, cpu_row : integer range 0 to 65535;
    signal cpu_bank_r  : integer range 0 to LANES-1 := 0;
    signal ld_row      : integer range 0 to BANK_D-1;
    signal ld_row_r    : integer range 0 to BANK_D-1 := 0;  -- registered BRAM row index
    signal b_raddr, b_waddr : integer range 0 to BANK_D-1;
    signal b_we        : std_logic_vector(0 to LANES-1);
    signal running     : std_logic;
begin
    ----------------------------------------------------------------
    -- decode (combinational)
    ----------------------------------------------------------------
    instr <= imem(pc);
    op    <= instr(31 downto 26);
    di    <= to_integer(unsigned(instr(25 downto 23)));
    ai    <= to_integer(unsigned(instr(22 downto 20)));
    bi    <= to_integer(unsigned(instr(19 downto 17)));
    imm_s <= resize(signed(instr(16 downto 0)), 32);

    with op select lane_op <=
        A_ADD when OP_VADD, A_SUB when OP_VSUB, A_AND when OP_VAND,
        A_OR  when OP_VOR,  A_XOR when OP_VXOR, A_SLL when OP_VSLL,
        A_SRL when OP_VSRL, A_SRA when OP_VSRA, A_MIN when OP_VMIN,
        A_MAX when OP_VMAX, A_MUL when OP_VMUL, A_MAC when OP_VMAC,
        A_SLT when OP_VSLT, A_SEQ when OP_VSEQ, A_ADD when others;

    -- lanes operate on the *registered* operands -> the DSP multiply is isolated
    -- between the S_RUN and S_EX register stages.
    gen_lanes : for k in 0 to LANES-1 generate
        u_lane : entity work.gpu_lane
            port map (op => lane_op_r, a => opa_r(k), b => opb_r(k),
                      c => opc_r(k), y => ly(k), flag => lflag(k));
    end generate;

    cpu_bank <= to_integer(unsigned(sp_addr)) mod LANES;
    cpu_row  <= to_integer(unsigned(sp_addr)) /  LANES;
    ld_row   <= (to_integer(signed(sreg(ai))) + to_integer(imm_s)) / LANES mod BANK_D;

    running  <= '1' when state /= S_IDLE and state /= S_DONE else '0';
    busy     <= running;
    done     <= '1' when state = S_DONE else '0';
    sp_rd    <= bank_dout(cpu_bank_r);

    ----------------------------------------------------------------
    -- scratchpad address / write-enable selects
    ----------------------------------------------------------------
    b_raddr <= ld_row_r when state = S_VLD2 else (cpu_row mod BANK_D);
    b_waddr <= ld_row_r when state = S_VST2 else (cpu_row mod BANK_D);
    gen_bwe : for k in 0 to LANES-1 generate
        b_we(k) <= '1' when (state = S_VST2 and mask(k) = '1')
                         or (running = '0' and sp_we = '1' and k = cpu_bank
                             and cpu_row < BANK_D)
                   else '0';
        bdin(k) <= vreg(bi)(k) when state = S_VST2 else sp_wd;
    end generate;

    cpu_rd_sel : process(clk)
    begin
        if rising_edge(clk) then cpu_bank_r <= cpu_bank; end if;
    end process;

    -- scratchpad = 8 independent single-port synchronous RAMs -> block RAM
    gen_banks : for k in 0 to LANES-1 generate
        signal bmem : word_array(0 to BANK_D-1) := (others => (others => '0'));
        attribute ram_style : string;
        attribute ram_style of bmem : signal is "block";
    begin
        ram_proc : process(clk)
        begin
            if rising_edge(clk) then
                if b_we(k) = '1' then bmem(b_waddr) <= bdin(k); end if;
                bank_dout(k) <= bmem(b_raddr);
            end if;
        end process;
    end generate;

    ----------------------------------------------------------------
    -- control + datapath
    ----------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE; pc <= 0; mask <= (others => '1');
            else
                if running = '0' then            -- CPU register writes (imem / scalars)
                    if imem_we = '1' and to_integer(unsigned(imem_addr)) < IMEM_D then
                        imem(to_integer(unsigned(imem_addr))) <= imem_wd;
                    end if;
                    if sarg_we = '1' then
                        sreg(to_integer(unsigned(sarg_idx))) <= sarg_data;
                    end if;
                end if;

                case state is
                    when S_IDLE =>
                        if start = '1' then
                            pc <= 0; mask <= (others => '1'); state <= S_RUN;
                        end if;

                    when S_RUN =>
                        case op is
                            when OP_HALT  => state <= S_DONE;

                            when OP_VLID  =>
                                for k in 0 to LANES-1 loop
                                    if mask(k)='1' then vreg(di)(k) <= std_logic_vector(to_unsigned(k,32)); end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VMOVI =>
                                for k in 0 to LANES-1 loop
                                    if mask(k)='1' then vreg(di)(k) <= std_logic_vector(imm_s); end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VBCAST =>
                                for k in 0 to LANES-1 loop
                                    if mask(k)='1' then vreg(di)(k) <= sreg(ai); end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VLD   =>            -- register row, read next cycle
                                ld_row_r <= ld_row;
                                state    <= S_VLD2;

                            when OP_VST   =>            -- register row, write next cycle
                                ld_row_r <= ld_row;
                                state    <= S_VST2;

                            when OP_MASKON => mask <= (others => '1'); pc <= pc + 1;

                            when OP_SADDI =>
                                sreg(di) <= std_logic_vector(signed(sreg(ai)) + imm_s);
                                pc <= pc + 1;

                            when OP_SBNZ =>
                                if signed(sreg(ai)) /= 0
                                   and (pc + to_integer(imm_s)) >= 0
                                   and (pc + to_integer(imm_s)) <= IMEM_D-1 then
                                    pc <= pc + to_integer(imm_s);
                                else
                                    pc <= pc + 1;
                                end if;

                            when others =>      -- vector ALU class -> latch operands, pipeline
                                for k in 0 to LANES-1 loop
                                    opa_r(k) <= vreg(ai)(k);
                                    opb_r(k) <= vreg(bi)(k);
                                    opc_r(k) <= vreg(di)(k);
                                end loop;
                                lane_op_r <= lane_op;
                                op_r      <= op;
                                di_r      <= di;
                                mask_r    <= mask;
                                state     <= S_EX;
                        end case;

                    when S_EX =>                 -- lane ALU / DSP -> result register
                        res_r  <= ly;
                        flag_r <= lflag;
                        state  <= S_WB;

                    when S_WB =>                 -- write back the registered result
                        if op_r = OP_VSLT or op_r = OP_VSEQ then
                            mask <= flag_r;
                        else
                            for k in 0 to LANES-1 loop
                                if mask_r(k)='1' then vreg(di_r)(k) <= res_r(k); end if;
                            end loop;
                        end if;
                        pc    <= pc + 1;
                        state <= S_RUN;

                    when S_VLD2 =>               -- BRAM read issued with registered addr
                        state <= S_VLD3;

                    when S_VLD3 =>               -- bank_dout valid (1-cycle BRAM read)
                        for k in 0 to LANES-1 loop
                            if mask(k)='1' then vreg(di)(k) <= bank_dout(k); end if;
                        end loop;
                        pc    <= pc + 1;
                        state <= S_RUN;

                    when S_VST2 =>               -- write committed via b_we this cycle
                        pc    <= pc + 1;
                        state <= S_RUN;

                    when S_DONE =>
                        if start = '1' then
                            pc <= 0; mask <= (others => '1'); state <= S_RUN;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;
