-- =====================================================================
-- gpio_port.vhd  -  MMIO general-purpose I/O (per-bit direction + tri-state)
--
-- Collects all Pmod pins that are not claimed by a dedicated controller into one
-- bidirectional GPIO bank. Outputs o/t triplets (t='1' => Hi-Z/input); the tri-
-- state pads live in the platform top. Inputs are 2-FF synchronized.
--
-- Register block (word offsets, reg = addr[4:2]):
--   0x0 DIR (RW) bit=1 -> output (drives), bit=0 -> input (Hi-Z)
--   0x4 OUT (RW) output value (only bits with DIR=1 are driven)
--   0x8 IN  (R)  synchronized live pin value
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gpio_port is
    generic ( WIDTH : integer := 22 );
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        sel    : in  std_logic;
        we     : in  std_logic;
        reg    : in  std_logic_vector(2 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        gpio_i : in  std_logic_vector(WIDTH-1 downto 0);
        gpio_o : out std_logic_vector(WIDTH-1 downto 0);
        gpio_t : out std_logic_vector(WIDTH-1 downto 0)   -- '1' = Hi-Z (input)
    );
end gpio_port;

architecture rtl of gpio_port is
    signal dir_reg, out_reg : std_logic_vector(WIDTH-1 downto 0) := (others=>'0');
    signal in_m, in_s       : std_logic_vector(WIDTH-1 downto 0) := (others=>'0');
begin
    gpio_o <= out_reg;
    gpio_t <= not dir_reg;                         -- DIR=1 output -> t=0 (drive)

    with reg select rdata <=
        std_logic_vector(resize(unsigned(dir_reg),32)) when "000",
        std_logic_vector(resize(unsigned(out_reg),32)) when "001",
        std_logic_vector(resize(unsigned(in_s),  32))  when "010",
        (others=>'0')                                  when others;

    process(clk)
    begin
        if rising_edge(clk) then
            in_m <= gpio_i;  in_s <= in_m;          -- 2-FF synchronizer
            if rst='1' then
                dir_reg <= (others=>'0');
                out_reg <= (others=>'0');
            elsif (sel='1' and we='1') then
                case reg is
                    when "000" => dir_reg <= wdata(WIDTH-1 downto 0);
                    when "001" => out_reg <= wdata(WIDTH-1 downto 0);
                    when others => null;
                end case;
            end if;
        end if;
    end process;
end rtl;
