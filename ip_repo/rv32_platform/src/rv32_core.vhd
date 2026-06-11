-- =====================================================================
-- rv32_core.vhd  -  Integrated IF~WB (register write-back) datapath
-- RV32I 5-stage pipeline top: IF -> ID -> EX -> MEM -> WB.
-- Wires the verified IP blocks (control_unit, imm_gen, register_file,
-- alu, alu_control, bcu, forwarding_unit, hazard_unit, read_aligner,
-- write_strobe_gen, result_mux, pc_reg/pc_adder/next_pc_mux) into a
-- working pipeline with: EX/MEM & MEM/WB forwarding, load-use stall
-- (1 bubble), branch/jump resolved in EX (2-bubble flush, static
-- not-taken). Idealized single-cycle imem/dmem (always hit) so that the
-- IF~WB *write* path can be verified end-to-end. Cache/AXI/CSR/Trap are
-- out of this integration's scope (separately verified).
--
-- Spec: RV32_Pipeline_Spec.md 1/11/12, if_wb_acceptance_tests.md (ATDD).
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rv32_core is
    Generic (
        RESET_ADDR : std_logic_vector(31 downto 0) := x"00000000"
    );
    Port (
        clk          : in  std_logic;
        reset        : in  std_logic;                       -- active-high async
        -- instruction memory (ideal, combinational read = always hit)
        imem_addr    : out std_logic_vector(31 downto 0);
        imem_rdata   : in  std_logic_vector(31 downto 0);
        -- data memory (ideal, combinational read; sync write in TB)
        dmem_addr    : out std_logic_vector(31 downto 0);
        dmem_wdata   : out std_logic_vector(31 downto 0);
        dmem_wstrb   : out std_logic_vector(3 downto 0);
        dmem_we      : out std_logic;
        dmem_re      : out std_logic;
        dmem_rdata   : in  std_logic_vector(31 downto 0);
        -- global memory stall: when '1' the whole pipeline (PC + all 4 boundary
        -- registers) freezes for a cache miss / multi-cycle memory access.
        mem_stall    : in  std_logic;
        -- debug / scoreboard
        dbg_commit   : out std_logic;                       -- WB write committed (rd/=0)
        dbg_rd       : out std_logic_vector(4 downto 0);
        dbg_wdata    : out std_logic_vector(31 downto 0);
        dbg_reg_addr : in  std_logic_vector(4 downto 0);
        dbg_reg_data : out std_logic_vector(31 downto 0);
        -- FENCE.I: 1-cycle invalidate pulse to the instruction cache
        ic_fence_i   : out std_logic
    );
end rv32_core;

architecture Behavioral of rv32_core is

    constant NOP : std_logic_vector(31 downto 0) := x"00000013";  -- addi x0,x0,0

    -- ---------------- IF ----------------
    signal pc, pc_plus4, next_pc            : std_logic_vector(31 downto 0);
    signal instr_if                         : std_logic_vector(31 downto 0);

    -- ---------------- IF/ID ----------------
    signal ifid_pc, ifid_pc4, ifid_instr    : std_logic_vector(31 downto 0);

    -- ---------------- ID (combinational) ----------------
    signal id_opcode                        : std_logic_vector(6 downto 0);
    signal id_rs1, id_rs2, id_rd            : std_logic_vector(4 downto 0);
    signal id_funct3                        : std_logic_vector(2 downto 0);
    signal id_funct7_5, id_jalr             : std_logic;
    signal id_rs1_data, id_rs2_data, id_imm : std_logic_vector(31 downto 0);
    -- control
    signal c_reg_write, c_mem_read, c_mem_write, c_alu_src, c_src_a_sel : std_logic;
    signal c_branch, c_jump                 : std_logic;
    signal c_alu_op, c_result_src           : std_logic_vector(1 downto 0);
    -- CSR / Trap control outputs of control_unit
    signal u_csr_to_reg, u_csr_use_imm, u_is_ecall, u_is_ebreak,
           u_is_mret, u_is_fence_i, u_illegal : std_logic;
    signal u_csr_cmd                        : std_logic_vector(1 downto 0);
    -- ID CSR operand build
    signal id_csr_addr                      : std_logic_vector(11 downto 0);
    signal id_zimm, id_csr_wdata            : std_logic_vector(31 downto 0);
    signal id_csr_we, id_src_nonzero        : std_logic;

    -- ---------------- hazard ----------------
    signal load_use_stall, hz_flush         : std_logic;
    signal core_stall                       : std_logic;  -- load-use OR mem_stall

    -- ---------------- ID/EX ----------------
    signal idex_pc, idex_pc4, idex_rs1d, idex_rs2d, idex_imm : std_logic_vector(31 downto 0);
    signal idex_rs1, idex_rs2, idex_rd      : std_logic_vector(4 downto 0);
    signal idex_funct3                      : std_logic_vector(2 downto 0);
    signal idex_funct7_5, idex_jalr         : std_logic;
    signal idex_reg_write, idex_mem_read, idex_mem_write,
           idex_alu_src, idex_src_a_sel, idex_branch, idex_jump : std_logic;
    signal idex_alu_op, idex_result_src     : std_logic_vector(1 downto 0);
    -- CSR / Trap carried into EX
    signal idex_csr_to_reg, idex_csr_we     : std_logic;
    signal idex_csr_cmd                     : std_logic_vector(1 downto 0);
    signal idex_csr_addr                    : std_logic_vector(11 downto 0);
    signal idex_csr_wdata                   : std_logic_vector(31 downto 0);
    signal idex_illegal, idex_is_ecall,
           idex_is_ebreak, idex_is_mret     : std_logic;
    signal idex_is_fence_i                  : std_logic;
    signal fencei_seen                      : std_logic;  -- one-shot tracker

    -- ---------------- EX (combinational) ----------------
    signal forward_a, forward_b             : std_logic_vector(1 downto 0);
    signal fa_val, fb_val                   : std_logic_vector(31 downto 0);
    signal alu_a, alu_b                     : std_logic_vector(31 downto 0);
    signal alu_ctrl                         : std_logic_vector(3 downto 0);
    signal alu_result_ex                    : std_logic_vector(31 downto 0);
    signal alu_zero                         : std_logic;
    signal ex_branch_taken, ex_pc_src       : std_logic;
    signal ex_target_addr                   : std_logic_vector(31 downto 0);
    -- CSR file / trap unit (resolved in EX)
    signal csr_rdata_ex                     : std_logic_vector(31 downto 0);
    signal csr_we_qual, mret_qual           : std_logic;
    signal mtvec_s, mepc_s, mstatus_s       : std_logic_vector(31 downto 0);
    signal trap_taken_s, trap_taken_q, trap_we_s, trap_we_qual, flush_all_s : std_logic;
    signal trap_target_s                    : std_logic_vector(31 downto 0);
    signal trap_mepc_s, trap_mcause_s, trap_mtval_s : std_logic_vector(31 downto 0);
    -- PC redirect (trap has priority over branch)
    signal redirect_sel                     : std_logic;
    signal redirect_target                  : std_logic_vector(31 downto 0);

    -- ---------------- EX/MEM ----------------
    signal exmem_alu_result, exmem_store, exmem_pc4 : std_logic_vector(31 downto 0);
    signal exmem_rd                         : std_logic_vector(4 downto 0);
    signal exmem_funct3                     : std_logic_vector(2 downto 0);
    signal exmem_reg_write, exmem_mem_read, exmem_mem_write : std_logic;
    signal exmem_result_src                 : std_logic_vector(1 downto 0);
    signal exmem_csr_to_reg                 : std_logic;
    signal exmem_csr_rdata                  : std_logic_vector(31 downto 0);

    -- ---------------- MEM (combinational) ----------------
    signal mem_byte_off                     : std_logic_vector(1 downto 0);
    signal mem_read_data, mem_wdata_aligned : std_logic_vector(31 downto 0);
    signal mem_wstrb                        : std_logic_vector(3 downto 0);

    -- ---------------- MEM/WB ----------------
    signal memwb_read_data, memwb_alu_result, memwb_pc4 : std_logic_vector(31 downto 0);
    signal memwb_rd                         : std_logic_vector(4 downto 0);
    signal memwb_reg_write                  : std_logic;
    signal memwb_result_src                 : std_logic_vector(1 downto 0);
    signal memwb_csr_to_reg                 : std_logic;
    signal memwb_csr_rdata                  : std_logic_vector(31 downto 0);

    -- ---------------- WB (combinational) ----------------
    signal wb_write_data                    : std_logic_vector(31 downto 0);

    -- debug shadow register file
    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal shadow : reg_array := (others => (others => '0'));

begin
    -- =================================================================
    -- IF stage
    -- =================================================================
    -- global freeze: load-use bubble OR a memory miss holds the PC
    core_stall <= load_use_stall or mem_stall;

    u_pc : entity work.pc_reg
        generic map (RESET_ADDR => RESET_ADDR)
        port map (clk => clk, reset => reset, stall => core_stall,
                  next_pc => next_pc, pc => pc);

    u_pcadd : entity work.pc_adder
        port map (pc_in => pc, pc_out => pc_plus4);

    -- redirect: trap (EX) overrides branch/jump (EX)
    redirect_target <= trap_target_s when trap_taken_q = '1' else ex_target_addr;
    redirect_sel    <= trap_taken_q or ex_pc_src;

    u_npc : entity work.next_pc_mux
        port map (pc_plus_4 => pc_plus4, target_addr => redirect_target,
                  pc_src => redirect_sel, next_pc => next_pc);

    imem_addr <= pc;
    instr_if  <= imem_rdata;

    -- IF/ID pipeline register (flush=branch taken -> squash to NOP; stall=hold)
    process(clk, reset)
    begin
        if reset = '1' then
            ifid_pc <= (others => '0'); ifid_pc4 <= (others => '0'); ifid_instr <= NOP;
        elsif rising_edge(clk) then
            if mem_stall = '1' then
                null;                              -- memory miss: freeze (highest priority)
            elsif (ex_pc_src = '1' or trap_taken_q = '1') then
                ifid_instr <= NOP;                 -- control-flow / trap squash (younger fetch)
                ifid_pc    <= pc;  ifid_pc4 <= pc_plus4;
            elsif load_use_stall = '1' then
                null;                              -- hold
            else
                ifid_pc <= pc; ifid_pc4 <= pc_plus4; ifid_instr <= instr_if;
            end if;
        end if;
    end process;

    -- =================================================================
    -- ID stage
    -- =================================================================
    id_opcode   <= ifid_instr(6 downto 0);
    id_rd       <= ifid_instr(11 downto 7);
    id_funct3   <= ifid_instr(14 downto 12);
    id_rs1      <= ifid_instr(19 downto 15);
    id_rs2      <= ifid_instr(24 downto 20);
    -- funct7[5] (=instr[30]) gating: only R-type, and I-type SRLI/SRAI
    -- (funct3=101), actually encode this bit. For ADDI (I, funct3=000) the
    -- bit is part of the immediate and MUST be forced 0 (else ADDI->SUB bug).
    id_funct7_5 <= ifid_instr(30) when (id_opcode = "0110011" or
                       (id_opcode = "0010011" and id_funct3 = "101")) else '0';
    id_jalr     <= '1' when id_opcode = "1100111" else '0';

    u_ctrl : entity work.control_unit
        port map (opcode => id_opcode, funct3 => id_funct3,
                  instr_31_20 => ifid_instr(31 downto 20),
                  reg_write => c_reg_write, mem_read => c_mem_read, mem_write => c_mem_write,
                  alu_src => c_alu_src, src_a_sel => c_src_a_sel, branch => c_branch, jump => c_jump,
                  alu_op => c_alu_op, result_src => c_result_src,
                  csr_to_reg => u_csr_to_reg, csr_use_imm => u_csr_use_imm, csr_cmd => u_csr_cmd,
                  is_ecall => u_is_ecall, is_ebreak => u_is_ebreak, is_mret => u_is_mret,
                  is_fence_i => u_is_fence_i, illegal => u_illegal);

    u_imm : entity work.imm_gen
        port map (instr => ifid_instr, opcode => id_opcode, imm => id_imm);

    u_rf : entity work.register_file
        port map (clk => clk, reset => reset, we3 => memwb_reg_write,
                  a1 => id_rs1, a2 => id_rs2, a3 => memwb_rd, wd3 => wb_write_data,
                  rd1 => id_rs1_data, rd2 => id_rs2_data);

    u_haz : entity work.hazard_unit
        port map (id_ex_mem_read => idex_mem_read, id_ex_rd => idex_rd,
                  if_id_rs1 => id_rs1, if_id_rs2 => id_rs2,
                  stall => load_use_stall, flush => hz_flush);

    -- CSR operand build (Zicsr): addr = instr[31:20], zimm = zero-ext rs1 field.
    id_csr_addr  <= ifid_instr(31 downto 20);
    id_zimm      <= std_logic_vector(resize(unsigned(ifid_instr(19 downto 15)), 32));
    id_csr_wdata <= id_zimm when u_csr_use_imm = '1' else id_rs1_data;
    -- side-effect rule: CSRRW always writes; CSRRS/RC write only if source /= 0
    id_src_nonzero <= '1' when ((u_csr_use_imm = '1' and ifid_instr(19 downto 15) /= "00000")
                            or  (u_csr_use_imm = '0' and id_rs1 /= "00000")) else '0';
    id_csr_we    <= '1' when (u_csr_cmd = "01"
                          or ((u_csr_cmd = "10" or u_csr_cmd = "11") and id_src_nonzero = '1'))
                    else '0';

    -- ID/EX pipeline register (flush bubble on load-use OR branch taken)
    process(clk, reset)
        variable bubble : std_logic;
    begin
        if reset = '1' then
            idex_pc <= (others=>'0'); idex_pc4 <= (others=>'0');
            idex_rs1d <= (others=>'0'); idex_rs2d <= (others=>'0'); idex_imm <= (others=>'0');
            idex_rs1 <= (others=>'0'); idex_rs2 <= (others=>'0'); idex_rd <= (others=>'0');
            idex_funct3 <= (others=>'0'); idex_funct7_5 <= '0'; idex_jalr <= '0';
            idex_reg_write <= '0'; idex_mem_read <= '0'; idex_mem_write <= '0';
            idex_alu_src <= '0'; idex_src_a_sel <= '0'; idex_branch <= '0'; idex_jump <= '0';
            idex_alu_op <= "00"; idex_result_src <= "00";
            idex_csr_to_reg <= '0'; idex_csr_we <= '0'; idex_csr_cmd <= "00";
            idex_csr_addr <= (others=>'0'); idex_csr_wdata <= (others=>'0');
            idex_illegal <= '0'; idex_is_ecall <= '0'; idex_is_ebreak <= '0'; idex_is_mret <= '0';
            idex_is_fence_i <= '0';
        elsif rising_edge(clk) then
          if mem_stall = '1' then
            null;                                  -- memory miss: freeze ID/EX
          else
            -- a trap in EX squashes the instruction currently in ID, just like a branch
            bubble := load_use_stall or ex_pc_src or trap_taken_q;
            -- data path (don't-care on bubble; pass through is fine)
            idex_pc   <= ifid_pc;   idex_pc4 <= ifid_pc4;
            idex_rs1d <= id_rs1_data; idex_rs2d <= id_rs2_data; idex_imm <= id_imm;
            idex_rs1  <= id_rs1;    idex_rs2 <= id_rs2; idex_rd <= id_rd;
            idex_funct3 <= id_funct3; idex_funct7_5 <= id_funct7_5; idex_jalr <= id_jalr;
            -- CSR data operands (don't-care when nullified below)
            idex_csr_addr  <= id_csr_addr;
            idex_csr_wdata <= id_csr_wdata;
            if bubble = '1' then           -- nullify control -> NOP bubble
                idex_reg_write <= '0'; idex_mem_read <= '0'; idex_mem_write <= '0';
                idex_branch <= '0'; idex_jump <= '0';
                idex_alu_src <= '0'; idex_src_a_sel <= '0';
                idex_alu_op <= "00"; idex_result_src <= "00";
                idex_csr_to_reg <= '0'; idex_csr_we <= '0'; idex_csr_cmd <= "00";
                idex_illegal <= '0'; idex_is_ecall <= '0';
                idex_is_ebreak <= '0'; idex_is_mret <= '0';
                idex_is_fence_i <= '0';
            else
                idex_reg_write <= c_reg_write; idex_mem_read <= c_mem_read;
                idex_mem_write <= c_mem_write; idex_alu_src <= c_alu_src;
                idex_src_a_sel <= c_src_a_sel; idex_branch <= c_branch; idex_jump <= c_jump;
                idex_alu_op <= c_alu_op; idex_result_src <= c_result_src;
                idex_csr_to_reg <= u_csr_to_reg; idex_csr_we <= id_csr_we;
                idex_csr_cmd <= u_csr_cmd;
                idex_illegal <= u_illegal; idex_is_ecall <= u_is_ecall;
                idex_is_ebreak <= u_is_ebreak; idex_is_mret <= u_is_mret;
                idex_is_fence_i <= u_is_fence_i;
            end if;
          end if;   -- mem_stall freeze
        end if;
    end process;

    -- =================================================================
    -- EX stage
    -- =================================================================
    u_fwd : entity work.forwarding_unit
        port map (id_ex_rs1 => idex_rs1, id_ex_rs2 => idex_rs2,
                  ex_mem_rd => exmem_rd, ex_mem_reg_write => exmem_reg_write,
                  mem_wb_rd => memwb_rd, mem_wb_reg_write => memwb_reg_write,
                  forward_a => forward_a, forward_b => forward_b);

    fa_val <= exmem_alu_result when forward_a = "10" else
              wb_write_data    when forward_a = "01" else
              idex_rs1d;
    fb_val <= exmem_alu_result when forward_b = "10" else
              wb_write_data    when forward_b = "01" else
              idex_rs2d;

    alu_a <= idex_pc  when idex_src_a_sel = '1' else fa_val;
    alu_b <= idex_imm when idex_alu_src   = '1' else fb_val;

    u_aluc : entity work.alu_control
        port map (alu_op => idex_alu_op, funct3 => idex_funct3,
                  funct7_5 => idex_funct7_5, alu_ctrl => alu_ctrl);

    u_alu : entity work.alu
        port map (a => alu_a, b => alu_b, alu_ctrl => alu_ctrl,
                  result => alu_result_ex, zero => alu_zero);

    u_bcu : entity work.bcu
        port map (a_fwd => fa_val, b_fwd => fb_val, rs1_fwd => fa_val,
                  pc => idex_pc, imm => idex_imm, funct3 => idex_funct3,
                  branch => idex_branch, jump => idex_jump, is_jalr => idex_jalr,
                  branch_taken => ex_branch_taken, pc_src => ex_pc_src,
                  target_addr => ex_target_addr);

    -- ---------------- CSR / Trap (resolved in EX) ----------------
    -- Commit guards: only act when the stage is actually advancing (a memory
    -- stall freezes ID/EX, so idex_* persists -> must not re-commit each cycle).
    csr_we_qual  <= idex_csr_we   and not mem_stall;
    mret_qual    <= idex_is_mret  and not mem_stall;
    trap_we_qual <= trap_we_s     and not mem_stall;
    trap_taken_q <= trap_taken_s  and not mem_stall;

    u_csr : entity work.csr_file
        port map (clk => clk, reset => reset,
                  csr_addr => idex_csr_addr, csr_cmd => idex_csr_cmd,
                  csr_wdata => idex_csr_wdata, csr_we => csr_we_qual,
                  csr_rdata => csr_rdata_ex,
                  trap_we => trap_we_qual, trap_mepc => trap_mepc_s,
                  trap_mcause => trap_mcause_s, trap_mtval => trap_mtval_s,
                  is_mret => mret_qual,
                  mstatus_o => mstatus_s, mtvec_o => mtvec_s, mepc_o => mepc_s);

    u_trap : entity work.trap_unit
        port map (illegal_instr => idex_illegal, instr_misalign => '0',
                  load_misalign => '0', store_misalign => '0',
                  is_ecall => idex_is_ecall, is_ebreak => idex_is_ebreak,
                  is_mret => idex_is_mret,
                  instr_pc => idex_pc, fault_addr => idex_pc,
                  mtvec => mtvec_s, mepc => mepc_s,
                  trap_taken => trap_taken_s, trap_target => trap_target_s,
                  flush_all => flush_all_s, trap_we => trap_we_s,
                  trap_mepc => trap_mepc_s, trap_mcause => trap_mcause_s,
                  trap_mtval => trap_mtval_s);

    -- FENCE.I: emit a single-cycle invalidate pulse to the I-cache when a
    -- FENCE.I instruction occupies EX. One-shot (edge on entry), independent of
    -- mem_stall so the I-cache's own invalidate stall cannot re-trigger / lock.
    -- Harvard bring-up SoC (static i-mem): no PC redirect/flush needed -- the
    -- instructions already latched in IF/ID are valid; the invalidate only
    -- affects subsequent fetches (which re-refill from memory).
    process(clk, reset)
    begin
        if reset = '1' then
            fencei_seen <= '0';
        elsif rising_edge(clk) then
            fencei_seen <= idex_is_fence_i;     -- 1-cycle delayed copy
        end if;
    end process;
    ic_fence_i <= idex_is_fence_i and not fencei_seen;

    -- EX/MEM pipeline register
    process(clk, reset)
    begin
        if reset = '1' then
            exmem_alu_result <= (others=>'0'); exmem_store <= (others=>'0');
            exmem_pc4 <= (others=>'0'); exmem_rd <= (others=>'0');
            exmem_funct3 <= (others=>'0');
            exmem_reg_write <= '0'; exmem_mem_read <= '0'; exmem_mem_write <= '0';
            exmem_result_src <= "00";
            exmem_csr_to_reg <= '0'; exmem_csr_rdata <= (others=>'0');
        elsif rising_edge(clk) then
          if mem_stall = '1' then
            null;                                  -- memory miss: freeze EX/MEM
          else
            -- fold CSR read value into the result path for a CSR op
            if idex_csr_to_reg = '1' then
                exmem_alu_result <= csr_rdata_ex;
            else
                exmem_alu_result <= alu_result_ex;
            end if;
            exmem_csr_to_reg <= idex_csr_to_reg;
            exmem_csr_rdata  <= csr_rdata_ex;
            exmem_store      <= fb_val;          -- forwarded rs2 = store data
            exmem_pc4        <= idex_pc4;
            exmem_rd         <= idex_rd;
            exmem_funct3     <= idex_funct3;
            exmem_reg_write  <= idex_reg_write;
            exmem_mem_read   <= idex_mem_read;
            exmem_mem_write  <= idex_mem_write;
            exmem_result_src <= idex_result_src;
          end if;   -- mem_stall freeze
        end if;
    end process;

    -- =================================================================
    -- MEM stage
    -- =================================================================
    dmem_addr   <= exmem_alu_result;
    mem_byte_off <= exmem_alu_result(1 downto 0);
    dmem_re     <= exmem_mem_read;
    dmem_we     <= exmem_mem_write;

    u_ra : entity work.read_aligner
        port map (word_data => dmem_rdata, byte_off => mem_byte_off,
                  funct3 => exmem_funct3, read_data => mem_read_data);

    u_wsg : entity work.write_strobe_gen
        port map (funct3 => exmem_funct3, byte_off => mem_byte_off,
                  store_data => exmem_store, wstrb => mem_wstrb,
                  wdata_aligned => mem_wdata_aligned);

    dmem_wstrb <= mem_wstrb;
    dmem_wdata <= mem_wdata_aligned;

    -- MEM/WB pipeline register
    process(clk, reset)
    begin
        if reset = '1' then
            memwb_read_data <= (others=>'0'); memwb_alu_result <= (others=>'0');
            memwb_pc4 <= (others=>'0'); memwb_rd <= (others=>'0');
            memwb_reg_write <= '0'; memwb_result_src <= "00";
            memwb_csr_to_reg <= '0'; memwb_csr_rdata <= (others=>'0');
        elsif rising_edge(clk) then
          if mem_stall = '1' then
            null;                                  -- memory miss: freeze MEM/WB
          else
            memwb_read_data  <= mem_read_data;
            memwb_alu_result <= exmem_alu_result;
            memwb_pc4        <= exmem_pc4;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_result_src <= exmem_result_src;
            memwb_csr_to_reg <= exmem_csr_to_reg;
            memwb_csr_rdata  <= exmem_csr_rdata;
          end if;   -- mem_stall freeze
        end if;
    end process;

    -- =================================================================
    -- WB stage
    -- =================================================================
    -- CSR result is folded into the ALU-result path at EX/MEM (so the existing
    -- EX/MEM & MEM/WB forwarding works unchanged); result_src for CSR ops = "00".
    u_rmux : entity work.result_mux
        port map (result_src => memwb_result_src, csr_to_reg => '0',
                  alu_result => memwb_alu_result, read_data => memwb_read_data,
                  pc_plus4 => memwb_pc4, csr_rdata => x"00000000",
                  write_data => wb_write_data);

    -- debug shadow regfile (mirrors RF write port; sim observability)
    process(clk, reset)
    begin
        if reset = '1' then
            shadow <= (others => (others => '0'));
        elsif rising_edge(clk) then
            -- mirror RF writes (idempotent during a freeze: MEM/WB holds, so the
            -- same rd<=value is rewritten each stalled cycle -- harmless).
            if memwb_reg_write = '1' and memwb_rd /= "00000" then
                shadow(to_integer(unsigned(memwb_rd))) <= wb_write_data;
            end if;
        end if;
    end process;

    dbg_reg_data <= (others => '0') when dbg_reg_addr = "00000"
                    else shadow(to_integer(unsigned(dbg_reg_addr)));
    dbg_commit <= '1' when (mem_stall = '0' and memwb_reg_write = '1' and memwb_rd /= "00000") else '0';
    dbg_rd     <= memwb_rd;
    dbg_wdata  <= wb_write_data;

end Behavioral;
