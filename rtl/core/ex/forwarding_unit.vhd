-- forwarding_unit.vhd - EX bypass select (EX/MEM > MEM/WB > RF)
-- Spec: RV32_Pipeline_Spec.md 6.5, Movement.md 5.7
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity forwarding_unit is
    Port (
        id_ex_rs1        : in  std_logic_vector(4 downto 0);
        id_ex_rs2        : in  std_logic_vector(4 downto 0);
        ex_mem_rd        : in  std_logic_vector(4 downto 0);
        ex_mem_reg_write : in  std_logic;
        mem_wb_rd        : in  std_logic_vector(4 downto 0);
        mem_wb_reg_write : in  std_logic;
        forward_a        : out std_logic_vector(1 downto 0); -- 00 RF,10 EX/MEM,01 MEM/WB
        forward_b        : out std_logic_vector(1 downto 0)
    );
end forwarding_unit;

architecture Behavioral of forwarding_unit is
begin
    forward_a <=
        "10" when (ex_mem_reg_write = '1' and ex_mem_rd /= "00000" and ex_mem_rd = id_ex_rs1) else
        "01" when (mem_wb_reg_write = '1' and mem_wb_rd /= "00000" and mem_wb_rd = id_ex_rs1) else
        "00";
    forward_b <=
        "10" when (ex_mem_reg_write = '1' and ex_mem_rd /= "00000" and ex_mem_rd = id_ex_rs2) else
        "01" when (mem_wb_reg_write = '1' and mem_wb_rd /= "00000" and mem_wb_rd = id_ex_rs2) else
        "00";
end Behavioral;
