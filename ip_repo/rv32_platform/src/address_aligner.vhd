library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity addr_aligner is
    Port (
        address : in  std_logic_vector(31 downto 0);
        tag     : out std_logic_vector(19 downto 0);
        idx     : out std_logic_vector(7 downto 0);  
        offset  : out std_logic_vector(3 downto 0)   
    );
end addr_aligner;

architecture Behavioral of addr_aligner is
begin
    tag    <= address(31 downto 12);
    idx    <= address(11 downto 4);
    offset <= address(3 downto 0);
end Behavioral;