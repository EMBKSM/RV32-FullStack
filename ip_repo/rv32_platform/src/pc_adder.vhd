library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pc_adder is
    Port (
        pc_in  : in  std_logic_vector(31 downto 0);
        pc_out : out std_logic_vector(31 downto 0)
    );
end pc_adder;

architecture Behavioral of pc_adder is
begin
    pc_out <= std_logic_vector(unsigned(pc_in) + 4);
end Behavioral;