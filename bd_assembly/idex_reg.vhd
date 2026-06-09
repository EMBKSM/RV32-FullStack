-- idex_reg : ID/EX pipeline boundary register (extracted from rv32_core.vhd)
--   freeze on mem_stall; data fields always pass through; control fields are
--   nullified to a NOP bubble when bubble='1'.
--   bubble = load_use_stall OR ex_pc_src OR trap_taken_q (wire with orgate2 x2).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity idex_reg is
    Port (
        clk          : in std_logic;
        reset        : in std_logic;
        mem_stall    : in std_logic;
        bubble       : in std_logic;
        -- data inputs
        pc_in        : in std_logic_vector(31 downto 0);
        pc4_in       : in std_logic_vector(31 downto 0);
        rs1d_in      : in std_logic_vector(31 downto 0);
        rs2d_in      : in std_logic_vector(31 downto 0);
        imm_in       : in std_logic_vector(31 downto 0);
        csr_wdata_in : in std_logic_vector(31 downto 0);
        csr_addr_in  : in std_logic_vector(11 downto 0);
        rs1_in       : in std_logic_vector(4 downto 0);
        rs2_in       : in std_logic_vector(4 downto 0);
        rd_in        : in std_logic_vector(4 downto 0);
        funct3_in    : in std_logic_vector(2 downto 0);
        funct7_5_in  : in std_logic;
        jalr_in      : in std_logic;
        -- control inputs (nullified on bubble)
        reg_write_in : in std_logic;
        mem_read_in  : in std_logic;
        mem_write_in : in std_logic;
        alu_src_in   : in std_logic;
        src_a_sel_in : in std_logic;
        branch_in    : in std_logic;
        jump_in      : in std_logic;
        alu_op_in    : in std_logic_vector(1 downto 0);
        result_src_in: in std_logic_vector(1 downto 0);
        csr_to_reg_in: in std_logic;
        csr_we_in    : in std_logic;
        csr_cmd_in   : in std_logic_vector(1 downto 0);
        illegal_in   : in std_logic;
        is_ecall_in  : in std_logic;
        is_ebreak_in : in std_logic;
        is_mret_in   : in std_logic;
        is_fence_i_in: in std_logic;
        -- registered outputs
        idex_pc        : out std_logic_vector(31 downto 0);
        idex_pc4       : out std_logic_vector(31 downto 0);
        idex_rs1d      : out std_logic_vector(31 downto 0);
        idex_rs2d      : out std_logic_vector(31 downto 0);
        idex_imm       : out std_logic_vector(31 downto 0);
        idex_csr_wdata : out std_logic_vector(31 downto 0);
        idex_csr_addr  : out std_logic_vector(11 downto 0);
        idex_rs1       : out std_logic_vector(4 downto 0);
        idex_rs2       : out std_logic_vector(4 downto 0);
        idex_rd        : out std_logic_vector(4 downto 0);
        idex_funct3    : out std_logic_vector(2 downto 0);
        idex_funct7_5  : out std_logic;
        idex_jalr      : out std_logic;
        idex_reg_write : out std_logic;
        idex_mem_read  : out std_logic;
        idex_mem_write : out std_logic;
        idex_alu_src   : out std_logic;
        idex_src_a_sel : out std_logic;
        idex_branch    : out std_logic;
        idex_jump      : out std_logic;
        idex_alu_op    : out std_logic_vector(1 downto 0);
        idex_result_src: out std_logic_vector(1 downto 0);
        idex_csr_to_reg: out std_logic;
        idex_csr_we    : out std_logic;
        idex_csr_cmd   : out std_logic_vector(1 downto 0);
        idex_illegal   : out std_logic;
        idex_is_ecall  : out std_logic;
        idex_is_ebreak : out std_logic;
        idex_is_mret   : out std_logic;
        idex_is_fence_i: out std_logic
    );
end idex_reg;
architecture rtl of idex_reg is
begin
    process(clk, reset)
    begin
        if reset = '1' then
            idex_pc<=(others=>'0'); idex_pc4<=(others=>'0');
            idex_rs1d<=(others=>'0'); idex_rs2d<=(others=>'0'); idex_imm<=(others=>'0');
            idex_csr_wdata<=(others=>'0'); idex_csr_addr<=(others=>'0');
            idex_rs1<=(others=>'0'); idex_rs2<=(others=>'0'); idex_rd<=(others=>'0');
            idex_funct3<=(others=>'0'); idex_funct7_5<='0'; idex_jalr<='0';
            idex_reg_write<='0'; idex_mem_read<='0'; idex_mem_write<='0';
            idex_alu_src<='0'; idex_src_a_sel<='0'; idex_branch<='0'; idex_jump<='0';
            idex_alu_op<="00"; idex_result_src<="00";
            idex_csr_to_reg<='0'; idex_csr_we<='0'; idex_csr_cmd<="00";
            idex_illegal<='0'; idex_is_ecall<='0'; idex_is_ebreak<='0'; idex_is_mret<='0';
            idex_is_fence_i<='0';
        elsif rising_edge(clk) then
            if mem_stall = '1' then
                null;
            else
                -- data: always pass through
                idex_pc<=pc_in; idex_pc4<=pc4_in;
                idex_rs1d<=rs1d_in; idex_rs2d<=rs2d_in; idex_imm<=imm_in;
                idex_csr_wdata<=csr_wdata_in; idex_csr_addr<=csr_addr_in;
                idex_rs1<=rs1_in; idex_rs2<=rs2_in; idex_rd<=rd_in;
                idex_funct3<=funct3_in; idex_funct7_5<=funct7_5_in; idex_jalr<=jalr_in;
                if bubble = '1' then    -- nullify control -> NOP bubble
                    idex_reg_write<='0'; idex_mem_read<='0'; idex_mem_write<='0';
                    idex_branch<='0'; idex_jump<='0';
                    idex_alu_src<='0'; idex_src_a_sel<='0';
                    idex_alu_op<="00"; idex_result_src<="00";
                    idex_csr_to_reg<='0'; idex_csr_we<='0'; idex_csr_cmd<="00";
                    idex_illegal<='0'; idex_is_ecall<='0'; idex_is_ebreak<='0';
                    idex_is_mret<='0'; idex_is_fence_i<='0';
                else
                    idex_reg_write<=reg_write_in; idex_mem_read<=mem_read_in;
                    idex_mem_write<=mem_write_in; idex_alu_src<=alu_src_in;
                    idex_src_a_sel<=src_a_sel_in; idex_branch<=branch_in; idex_jump<=jump_in;
                    idex_alu_op<=alu_op_in; idex_result_src<=result_src_in;
                    idex_csr_to_reg<=csr_to_reg_in; idex_csr_we<=csr_we_in; idex_csr_cmd<=csr_cmd_in;
                    idex_illegal<=illegal_in; idex_is_ecall<=is_ecall_in;
                    idex_is_ebreak<=is_ebreak_in; idex_is_mret<=is_mret_in;
                    idex_is_fence_i<=is_fence_i_in;
                end if;
            end if;
        end if;
    end process;
end rtl;
