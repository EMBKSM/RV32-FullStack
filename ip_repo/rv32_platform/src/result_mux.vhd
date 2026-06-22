-- result_mux.vhd - WB write-back result select
-- Spec: RV32_Pipeline_Spec.md 10.1, Movement.md 7.1
-- result_src: 00 ALU, 01 ReadData(MEM), 10 PC+4(link). csr_to_reg overrides -> CSR.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity result_mux is
    Port (
        result_src : in  std_logic_vector(1 downto 0);
        csr_to_reg : in  std_logic;
        alu_result : in  std_logic_vector(31 downto 0);
        read_data  : in  std_logic_vector(31 downto 0);
        pc_plus4   : in  std_logic_vector(31 downto 0);
        csr_rdata  : in  std_logic_vector(31 downto 0);
        write_data : out std_logic_vector(31 downto 0)
    );
end result_mux;

architecture Behavioral of result_mux is
begin
    write_data <= csr_rdata  when csr_to_reg = '1'   else
                  alu_result when result_src = "00"  else
                  read_data  when result_src = "01"  else
                  pc_plus4   when result_src = "10"  else
                  alu_result;
end Behavioral;
