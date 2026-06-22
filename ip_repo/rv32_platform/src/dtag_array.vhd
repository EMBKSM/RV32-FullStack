-- dtag_array.vhd - D-cache tag store + valid + dirty (256 x 20b)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dtag_array is
    Port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        idx       : in  std_logic_vector(7 downto 0);
        we_tag    : in  std_logic;                       -- refill: tag<=tag_in, valid<=1, dirty<=0
        we_dirty  : in  std_logic;                       -- store hit: dirty<=1
        tag_in    : in  std_logic_vector(19 downto 0);
        tag_out   : out std_logic_vector(19 downto 0);
        valid_out : out std_logic;
        dirty_out : out std_logic
    );
end dtag_array;

architecture Behavioral of dtag_array is
    type tag_mem_t is array (0 to 255) of std_logic_vector(19 downto 0);
    signal tag_mem   : tag_mem_t;
    signal valid_mem : std_logic_vector(255 downto 0) := (others => '0');
    signal dirty_mem : std_logic_vector(255 downto 0) := (others => '0');
    signal i         : integer range 0 to 255;
begin
    i <= to_integer(unsigned(idx));
    tag_out   <= tag_mem(i);
    valid_out <= valid_mem(i);
    dirty_out <= dirty_mem(i);

    process(clk, reset)
    begin
        if reset = '1' then
            valid_mem <= (others => '0');
            dirty_mem <= (others => '0');
        elsif rising_edge(clk) then
            if we_tag = '1' then
                tag_mem(i)   <= tag_in;
                valid_mem(i) <= '1';
                dirty_mem(i) <= '0';
            elsif we_dirty = '1' then
                dirty_mem(i) <= '1';
            end if;
        end if;
    end process;
end Behavioral;
