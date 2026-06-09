library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity next_pc_mux is
    Port (
        pc_plus_4   : in  std_logic_vector(31 downto 0);
        target_addr : in  std_logic_vector(31 downto 0);
        pc_src      : in  std_logic;
        next_pc     : out std_logic_vector(31 downto 0)
    );
end next_pc_mux;

architecture Behavioral of next_pc_mux is
begin
    next_pc <= target_addr when pc_src = '1' else pc_plus_4;
end Behavioral;