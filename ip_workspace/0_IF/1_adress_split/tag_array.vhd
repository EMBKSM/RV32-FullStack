library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tag_array is
    Port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        we        : in  std_logic;                            
        idx       : in  std_logic_vector(7 downto 0);         
        tag_in    : in  std_logic_vector(19 downto 0);        
        tag_out   : out std_logic_vector(19 downto 0);        
        valid_out : out std_logic                             
    );
end tag_array;

architecture Behavioral of tag_array is
    type tag_mem_type is array (0 to 255) of std_logic_vector(19 downto 0);
    type valid_mem_type is array (0 to 255) of std_logic;

    signal tag_mem   : tag_mem_type;
    signal valid_mem : valid_mem_type := (others => '0');
    
begin
    tag_out   <= tag_mem(to_integer(unsigned(idx)));
    valid_out <= valid_mem(to_integer(unsigned(idx)));
    process(clk, reset)
    begin
        if reset = '1' then
            valid_mem <= (others => '0');
        elsif rising_edge(clk) then
            if we = '1' then
                tag_mem(to_integer(unsigned(idx)))   <= tag_in;
                valid_mem(to_integer(unsigned(idx))) <= '1';
            end if;
        end if;
    end process;

end Behavioral;