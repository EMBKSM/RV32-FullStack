-- ddata_array.vhd - D-cache data SRAM: 256 lines x 128b (4 words)
-- word load + byte-strobed store-hit + whole-line refill/writeback
--
-- LUTRAM (distributed RAM) implementation: 16 independent byte lanes, each a
-- 256 deep x 8 bit *1-D array of std_logic_vector* (the template Vivado infers
-- as distributed RAM), synchronous write / asynchronous read. Same ports and
-- same-cycle async-read timing as the prior flip-flop array, but the storage
-- maps to LUT distributed RAM instead of FFs + a 256:1 read mux -> large F7/F8
-- (slice) savings. Functionally identical (verified by equivalence simulation).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ddata_array is
    Port (
        clk       : in  std_logic;
        idx       : in  std_logic_vector(7 downto 0);
        word_off  : in  std_logic_vector(1 downto 0);
        we        : in  std_logic;                       -- store hit (byte strobed)
        wstrb     : in  std_logic_vector(3 downto 0);
        wdata     : in  std_logic_vector(31 downto 0);
        line_fill : in  std_logic;                       -- refill whole line
        fill_line : in  std_logic_vector(127 downto 0);
        word_out  : out std_logic_vector(31 downto 0);   -- load
        line_out  : out std_logic_vector(127 downto 0)   -- writeback (whole line)
    );
end ddata_array;

architecture Behavioral of ddata_array is
    attribute ram_style : string;
    signal i      : integer range 0 to 255;
    signal line_r : std_logic_vector(127 downto 0);
begin
    i <= to_integer(unsigned(idx));

    -- One distributed-RAM byte lane per byte of the 128-bit line.
    -- Lane b holds line byte b; word w (= word_off) occupies lanes 4w..4w+3.
    gen_lanes : for b in 0 to 15 generate
        type lane_t is array (0 to 255) of std_logic_vector(7 downto 0);
        signal lane : lane_t;
        attribute ram_style of lane : signal is "distributed";
    begin
        -- asynchronous read of this byte lane
        line_r(b*8+7 downto b*8) <= lane(i);
        -- synchronous write of the whole 8-bit element (clean LUTRAM template)
        process(clk)
        begin
            if rising_edge(clk) then
                if line_fill = '1' then
                    lane(i) <= fill_line(b*8+7 downto b*8);
                elsif (we = '1')
                      and (to_integer(unsigned(word_off)) = b/4)
                      and (wstrb(b mod 4) = '1') then
                    lane(i) <= wdata((b mod 4)*8+7 downto (b mod 4)*8);
                end if;
            end if;
        end process;
    end generate;

    line_out <= line_r;

    -- load word select (4:1 mux), identical to prior word_off decode
    with word_off select word_out <=
        line_r(31 downto 0)   when "00",
        line_r(63 downto 32)  when "01",
        line_r(95 downto 64)  when "10",
        line_r(127 downto 96) when others;
end Behavioral;
