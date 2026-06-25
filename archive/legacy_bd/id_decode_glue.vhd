-- id_decode_glue : ID-stage combinational glue that is inline in rv32_core.vhd
--   - instruction field slices (opcode/rd/funct3/rs1/rs2/instr_31_20)
--   - funct7_5 gating (only R-type and I-type SRLI/SRAI; else 0)
--   - jalr detect
--   - zimm (zero-extended rs1 field) for CSR immediate forms
--   - csr_we side-effect rule (CSRRW always; CSRRS/RC only if source field /= 0)
-- csr_wdata itself is a 2:1 mux (id_rs1_data vs zimm, sel=csr_use_imm) wired
-- separately with mux2_32 (needs the register-file value).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
entity id_decode_glue is
    Port (
        instr        : in  std_logic_vector(31 downto 0);   -- ifid_instr
        csr_use_imm  : in  std_logic;                        -- from control_unit
        csr_cmd      : in  std_logic_vector(1 downto 0);     -- from control_unit
        opcode       : out std_logic_vector(6 downto 0);
        rd           : out std_logic_vector(4 downto 0);
        funct3       : out std_logic_vector(2 downto 0);
        rs1          : out std_logic_vector(4 downto 0);
        rs2          : out std_logic_vector(4 downto 0);
        instr_31_20  : out std_logic_vector(11 downto 0);
        funct7_5     : out std_logic;
        jalr         : out std_logic;
        zimm         : out std_logic_vector(31 downto 0);
        csr_we       : out std_logic
    );
end id_decode_glue;
architecture rtl of id_decode_glue is
    signal op  : std_logic_vector(6 downto 0);
    signal f3  : std_logic_vector(2 downto 0);
    signal src_nz : std_logic;
begin
    op <= instr(6 downto 0);
    f3 <= instr(14 downto 12);
    opcode      <= op;
    rd          <= instr(11 downto 7);
    funct3      <= f3;
    rs1         <= instr(19 downto 15);
    rs2         <= instr(24 downto 20);
    instr_31_20 <= instr(31 downto 20);

    funct7_5 <= instr(30) when (op = "0110011" or (op = "0010011" and f3 = "101")) else '0';
    jalr     <= '1' when op = "1100111" else '0';
    zimm     <= std_logic_vector(resize(unsigned(instr(19 downto 15)), 32));

    -- both register and immediate CSR forms use the rs1 field (instr[19:15])
    src_nz <= '1' when instr(19 downto 15) /= "00000" else '0';
    csr_we <= '1' when (csr_cmd = "01"
                    or ((csr_cmd = "10" or csr_cmd = "11") and src_nz = '1')) else '0';
end rtl;
