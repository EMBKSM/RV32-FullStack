library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity comparator is
    Port (
        addr_tag   : in  std_logic_vector(19 downto 0);
        cache_tag  : in  std_logic_vector(19 downto 0);
        valid_bit  : in  std_logic;
        hit        : out std_logic
    );
end comparator;

architecture Behavioral of comparator is
begin
    process(addr_tag, cache_tag, valid_bit)
    begin
        if (valid_bit = '1') and (addr_tag = cache_tag) then
            hit <= '1';
        else
            hit <= '0';
        end if;
    end process;
end Behavioral;