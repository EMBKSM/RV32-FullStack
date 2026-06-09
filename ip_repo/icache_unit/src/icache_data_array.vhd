-- =====================================================================
-- icache_data_array.vhd  -  Read-only instruction line store (I-cache)
-- 256 lines x 128 bits (four 32-bit words / 16-byte line), matching the
-- tag_array index (addr[11:4]) and the 4-beat AXI refill line. The CPU side
-- reads ONE word combinationally (selected by word_off = addr[3:2]); a miss
-- refill writes the WHOLE 128-bit line in a single cycle (line_fill pulse).
-- No byte writes / no dirty bit (instruction fetch never stores).
-- Counterpart of ddata_array.vhd, but read-only and line-fill only.
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity icache_data_array is
    Port (
        clk       : in  std_logic;
        idx       : in  std_logic_vector(7 downto 0);          -- line index
        word_off  : in  std_logic_vector(1 downto 0);          -- which word in line
        line_fill : in  std_logic;                             -- write whole line
        fill_line : in  std_logic_vector(127 downto 0);        -- refill data (4 words)
        word_out  : out std_logic_vector(31 downto 0)          -- selected instruction word
    );
end icache_data_array;

architecture Behavioral of icache_data_array is
    type line_mem_t is array (0 to 255) of std_logic_vector(127 downto 0);
    signal mem : line_mem_t := (others => (others => '0'));
    signal sel : std_logic_vector(127 downto 0);
begin
    sel <= mem(to_integer(unsigned(idx)));
    with word_off select word_out <=
        sel(31 downto 0)    when "00",
        sel(63 downto 32)   when "01",
        sel(95 downto 64)   when "10",
        sel(127 downto 96)  when others;

    process(clk)
    begin
        if rising_edge(clk) then
            if line_fill = '1' then
                mem(to_integer(unsigned(idx))) <= fill_line;
            end if;
        end if;
    end process;
end Behavioral;
