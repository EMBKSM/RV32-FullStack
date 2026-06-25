-- =====================================================================
-- gpu_core.vhd  -  SIMT-lite engine: one PC, lockstep N-lane datapath,
-- per-lane predicate mask. Single-issue, single-cycle execute (combinational
-- regfile / scratchpad reads, registered writes) -> 1 instruction/cycle,
-- N elements retired per vector op. See docs/GPU_DESIGN.md.
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
        start     : in  std_logic;                       -- 1-cycle launch pulse
        busy      : out std_logic;
        done      : out std_logic;
        -- instruction memory write (CPU, only while idle)
        imem_we   : in  std_logic;
        imem_addr : in  std_logic_vector(15 downto 0);
        imem_wd   : in  std_logic_vector(31 downto 0);
        -- scalar-argument preset (CPU)
        sarg_we   : in  std_logic;
        sarg_idx  : in  std_logic_vector(2 downto 0);
        sarg_data : in  std_logic_vector(31 downto 0);
        -- scratchpad flat access (CPU, only while idle)
        sp_we     : in  std_logic;
        sp_addr   : in  std_logic_vector(15 downto 0);   -- flat element index
        sp_wd     : in  std_logic_vector(31 downto 0);
        sp_rd     : out std_logic_vector(31 downto 0)
    );
end entity gpu_core;

architecture rtl of gpu_core is

    type vregfile_t is array (0 to VREGS-1) of word_array(0 to LANES-1);
    type bankmem_t  is array (0 to LANES-1) of word_array(0 to BANK_D-1);

    signal vreg : vregfile_t := (others => (others => (others => '0')));
    signal sreg : word_array(0 to SREGS-1) := (others => (others => '0'));
    signal imem : word_array(0 to IMEM_D-1) := (others => (others => '0'));
    signal bank : bankmem_t := (others => (others => (others => '0')));
    signal mask : std_logic_vector(0 to LANES-1) := (others => '1');

    type state_t is (S_IDLE, S_RUN, S_DONE);
    signal state : state_t := S_IDLE;
    signal pc    : integer range 0 to IMEM_D-1 := 0;

    -- decoded current instruction (combinational)
    signal instr : std_logic_vector(31 downto 0);
    signal op    : opcode_t;
    signal di, ai, bi : integer range 0 to 7;
    signal imm_s : signed(31 downto 0);

    -- lane datapath
    signal lane_op : aluop_t;
    signal opa, opb, opc, ly : word_array(0 to LANES-1);
    signal lflag : std_logic_vector(0 to LANES-1);

    -- scratchpad addressing
    signal cpu_bank, cpu_row : integer range 0 to 65535;
    signal ld_row : integer range 0 to BANK_D-1;
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

    gen_lanes : for k in 0 to LANES-1 generate
        opa(k) <= vreg(ai)(k);
        opb(k) <= vreg(bi)(k);
        opc(k) <= vreg(di)(k);           -- old Vd (MAC accumulator)
        u_lane : entity work.gpu_lane
            port map (op => lane_op, a => opa(k), b => opb(k),
                      c => opc(k), y => ly(k), flag => lflag(k));
    end generate;

    -- CPU scratchpad flat address split (LANES assumed power-of-two friendly via mod/div)
    cpu_bank <= to_integer(unsigned(sp_addr)) mod LANES;
    cpu_row  <= to_integer(unsigned(sp_addr)) /  LANES;
    sp_rd    <= bank(cpu_bank)(cpu_row) when cpu_row < BANK_D else (others => '0');

    -- VLD/VST base row : element base = sreg(ai)+imm (N-aligned) -> row = base/LANES
    ld_row <= (to_integer(signed(sreg(ai))) + to_integer(imm_s)) / LANES
              mod BANK_D;

    busy <= '1' when state = S_RUN  else '0';
    done <= '1' when state = S_DONE else '0';

    ----------------------------------------------------------------
    -- sequential engine
    ----------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE; pc <= 0; mask <= (others => '1');
            else
                -- CPU writes (imem / scalar args / scratchpad) only while not running
                if state /= S_RUN then
                    if imem_we = '1' and to_integer(unsigned(imem_addr)) < IMEM_D then
                        imem(to_integer(unsigned(imem_addr))) <= imem_wd;
                    end if;
                    if sarg_we = '1' then
                        sreg(to_integer(unsigned(sarg_idx))) <= sarg_data;
                    end if;
                    if sp_we = '1' and (to_integer(unsigned(sp_addr)) / LANES) < BANK_D then
                        bank(to_integer(unsigned(sp_addr)) mod LANES)
                            (to_integer(unsigned(sp_addr)) / LANES) <= sp_wd;
                    end if;
                end if;

                case state is
                    ----------------------------------------------------
                    when S_IDLE =>
                        if start = '1' then
                            pc <= 0; mask <= (others => '1'); state <= S_RUN;
                        end if;
                    ----------------------------------------------------
                    when S_RUN =>
                        case op is
                            when OP_HALT =>
                                state <= S_DONE;

                            when OP_VLID =>
                                for k in 0 to LANES-1 loop
                                    if mask(k) = '1' then
                                        vreg(di)(k) <= std_logic_vector(to_unsigned(k, 32));
                                    end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VMOVI =>
                                for k in 0 to LANES-1 loop
                                    if mask(k) = '1' then
                                        vreg(di)(k) <= std_logic_vector(imm_s);
                                    end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VBCAST =>
                                for k in 0 to LANES-1 loop
                                    if mask(k) = '1' then vreg(di)(k) <= sreg(ai); end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VLD =>
                                for k in 0 to LANES-1 loop
                                    if mask(k) = '1' then vreg(di)(k) <= bank(k)(ld_row); end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VST =>
                                for k in 0 to LANES-1 loop
                                    if mask(k) = '1' then bank(k)(ld_row) <= vreg(bi)(k); end if;
                                end loop;
                                pc <= pc + 1;

                            when OP_VSLT | OP_VSEQ =>
                                for k in 0 to LANES-1 loop
                                    mask(k) <= lflag(k);
                                end loop;
                                pc <= pc + 1;

                            when OP_MASKON =>
                                mask <= (others => '1');
                                pc <= pc + 1;

                            when OP_SADDI =>
                                sreg(di) <= std_logic_vector(signed(sreg(ai)) + imm_s);
                                pc <= pc + 1;

                            when OP_SBNZ =>
                                if signed(sreg(ai)) /= 0
                                   and (pc + to_integer(imm_s)) >= 0
                                   and (pc + to_integer(imm_s)) <= IMEM_D-1 then
                                    pc <= pc + to_integer(imm_s);   -- taken branch (bounds-safe)
                                else
                                    pc <= pc + 1;
                                end if;

                            when others =>   -- vector ALU class (VADD..VMAX,VMUL,VMAC)
                                for k in 0 to LANES-1 loop
                                    if mask(k) = '1' then vreg(di)(k) <= ly(k); end if;
                                end loop;
                                pc <= pc + 1;
                        end case;
                    ----------------------------------------------------
                    when S_DONE =>
                        if start = '1' then           -- relaunch
                            pc <= 0; mask <= (others => '1'); state <= S_RUN;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;
