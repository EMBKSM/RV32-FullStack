-- hazard_unit.vhd - load-use hazard detection (1-bubble)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hazard_unit is
    Port (
        id_ex_mem_read : in  std_logic;
        id_ex_rd       : in  std_logic_vector(4 downto 0);
        if_id_rs1      : in  std_logic_vector(4 downto 0);
        if_id_rs2      : in  std_logic_vector(4 downto 0);
        stall          : out std_logic;
        flush          : out std_logic
    );
end hazard_unit;

architecture Behavioral of hazard_unit is
    signal lu : std_logic;
begin
    lu <= '1' when (id_ex_mem_read = '1' and id_ex_rd /= "00000" and
                    (id_ex_rd = if_id_rs1 or id_ex_rd = if_id_rs2)) else '0';
    stall <= lu;
    flush <= lu;
end Behavioral;
