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
        -- debug / scoreboard
        dbg_commit   : out std_logic;                       -- WB write committed (rd/=0)
        dbg_rd       : out std_logic_vector(4 downto 0);
        dbg_wdata    : out std_logic_vector(31 downto 0);
        dbg_reg_addr : in  std_logic_vector(4 downto 0);
        dbg_reg_data : out std_logic_vector(31 downto 0)
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
    -- unused-here control outputs of control_unit
    signal u_csr_to_reg, u_csr_use_imm, u_is_ecall, u_is_ebreak,
           u_is_mret, u_is_fence_i, u_illegal : std_logic;
    signal u_csr_cmd                        : std_logic_vector(1 downto 0);

    -- ---------------- hazard ----------------
    signal load_use_stall, hz_flush         : std_logic;

    -- ---------------- ID/EX ----------------
    signal idex_pc, idex_pc4, idex_rs1d, idex_rs2d, idex_imm : std_logic_vector(31 downto 0);
    signal idex_rs1, idex_rs2, idex_rd      : std_logic_vector(4 downto 0);
    signal idex_funct3                      : std_logic_vector(2 downto 0);
    signal idex_funct7_5, idex_jalr         : std_logic;
    signal idex_reg_write, idex_mem_read, idex_mem_write,
           idex_alu_src, idex_src_a_sel, idex_branch, idex_jump : std_logic;
    signal idex_alu_op, idex_result_src     : std_logic_vector(1 downto 0);

    -- ---------------- EX (combinational) ----------------
    signal forward_a, forward_b             : std_logic_vector(1 downto 0);
    signal fa_val, fb_val                   : std_logic_vector(31 downto 0);
    signal alu_a, alu_b                     : std_logic_vector(31 downto 0);
    signal alu_ctrl                         : std_logic_vector(3 downto 0);
    signal alu_result_ex                    : std_logic_vector(31 downto 0);
    signal alu_zero                         : std_logic;
    signal ex_branch_taken, ex_pc_src       : std_logic;
    signal ex_target_addr                   : std_logic_vector(31 downto 0);

    -- ---------------- EX/MEM ----------------
    signal exmem_alu_result, exmem_store, exmem_pc4 : std_logic_vector(31 downto 0);
    signal exmem_rd                         : std_logic_vector(4 downto 0);
    signal exmem_funct3                     : std_logic_vector(2 downto 0);
    signal exmem_reg_write, exmem_mem_read, exmem_mem_write : std_logic;
    signal exmem_result_src                 : std_logic_vector(1 downto 0);

    -- ---------------- MEM (combinational) ----------------
    signal mem_byte_off                     : std_logic_vector(1 downto 0);
    signal mem_read_data, mem_wdata_aligned : std_logic_vector(31 downto 0);
    signal mem_wstrb                        : std_logic_vector(3 downto 0);

    -- ---------------- MEM/WB ----------------
    signal memwb_read_data, memwb_alu_result, memwb_pc4 : std_logic_vector(31 downto 0);
    signal memwb_rd                         : std_logic_vector(4 downto 0);
    signal memwb_reg_write                  : std_logic;
    signal memwb_result_src                 : std_logic_vector(1 downto 0);

    -- ---------------- WB (combinational) ----------------
    signal wb_write_data                    : std_logic_vector(31 downto 0);

    -- debug shadow register file
    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal shadow : reg_array := (others => (others => '0'));

begin
    -- =================================================================
    -- IF stage
    -- =================================================================
    u_pc : entity work.pc_reg
        generic map (RESET_ADDR => RESET_ADDR)
        port map (clk => clk, reset => reset, stall => load_use_stall,
                  next_pc => next_pc, pc => pc);

    u_pcadd : entity work.pc_adder
        port map (pc_in => pc, pc_out => pc_plus4);

    u_npc : entity work.next_pc_mux
        port map (pc_plus_4 => pc_plus4, target_addr => ex_target_addr,
                  pc_src => ex_pc_src, next_pc => next_pc);

    imem_addr <= pc;
    instr_if  <= imem_rdata;

    -- IF/ID pipeline register (flush=branch taken -> squash to NOP; stall=hold)
    process(clk, reset)
    begin
        if reset = '1' then
            ifid_pc <= (others => '0'); ifid_pc4 <= (others => '0'); ifid_instr <= NOP;
        elsif rising_edge(clk) then
            if ex_pc_src = '1' then
                ifid_instr <= NOP;                 -- control-flow squash (younger fetch)
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
        port map (clk => clk, we3 => memwb_reg_write,
                  a1 => id_rs1, a2 => id_rs2, a3 => memwb_rd, wd3 => wb_write_data,
                  rd1 => id_rs1_data, rd2 => id_rs2_data);

    u_haz : entity work.hazard_unit
        port map (id_ex_mem_read => idex_mem_read, id_ex_rd => idex_rd,
                  if_id_rs1 => id_rs1, if_id_rs2 => id_rs2,
                  stall => load_use_stall, flush => hz_flush);

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
        elsif rising_edge(clk) then
            bubble := load_use_stall or ex_pc_src;
            -- data path (don't-care on bubble; pass through is fine)
            idex_pc   <= ifid_pc;   idex_pc4 <= ifid_pc4;
            idex_rs1d <= id_rs1_data; idex_rs2d <= id_rs2_data; idex_imm <= id_imm;
            idex_rs1  <= id_rs1;    idex_rs2 <= id_rs2; idex_rd <= id_rd;
            idex_funct3 <= id_funct3; idex_funct7_5 <= id_funct7_5; idex_jalr <= id_jalr;
            if bubble = '1' then           -- nullify control -> NOP bubble
                idex_reg_write <= '0'; idex_mem_read <= '0'; idex_mem_write <= '0';
                idex_branch <= '0'; idex_jump <= '0';
                idex_alu_src <= '0'; idex_src_a_sel <= '0';
                idex_alu_op <= "00"; idex_result_src <= "00";
            else
                idex_reg_write <= c_reg_write; idex_mem_read <= c_mem_read;
                idex_mem_write <= c_mem_write; idex_alu_src <= c_alu_src;
                idex_src_a_sel <= c_src_a_sel; idex_branch <= c_branch; idex_jump <= c_jump;
                idex_alu_op <= c_alu_op; idex_result_src <= c_result_src;
            end if;
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

    -- EX/MEM pipeline register
    process(clk, reset)
    begin
        if reset = '1' then
            exmem_alu_result <= (others=>'0'); exmem_store <= (others=>'0');
            exmem_pc4 <= (others=>'0'); exmem_rd <= (others=>'0');
            exmem_funct3 <= (others=>'0');
            exmem_reg_write <= '0'; exmem_mem_read <= '0'; exmem_mem_write <= '0';
            exmem_result_src <= "00";
        elsif rising_edge(clk) then
            exmem_alu_result <= alu_result_ex;
            exmem_store      <= fb_val;          -- forwarded rs2 = store data
            exmem_pc4        <= idex_pc4;
            exmem_rd         <= idex_rd;
            exmem_funct3     <= idex_funct3;
            exmem_reg_write  <= idex_reg_write;
            exmem_mem_read   <= idex_mem_read;
            exmem_mem_write  <= idex_mem_write;
            exmem_result_src <= idex_result_src;
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
        elsif rising_edge(clk) then
            memwb_read_data  <= mem_read_data;
            memwb_alu_result <= exmem_alu_result;
            memwb_pc4        <= exmem_pc4;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_result_src <= exmem_result_src;
        end if;
    end process;

    -- =================================================================
    -- WB stage
    -- =================================================================
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
            if memwb_reg_write = '1' and memwb_rd /= "00000" then
                shadow(to_integer(unsigned(memwb_rd))) <= wb_write_data;
            end if;
        end if;
    end process;

    dbg_reg_data <= (others => '0') when dbg_reg_addr = "00000"
                    else shadow(to_integer(unsigned(dbg_reg_addr)));
    dbg_commit <= '1' when (memwb_reg_write = '1' and memwb_rd /= "00000") else '0';
    dbg_rd     <= memwb_rd;
    dbg_wdata  <= wb_write_data;

end Behavioral;
