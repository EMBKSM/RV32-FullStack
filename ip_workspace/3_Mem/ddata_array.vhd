-- ddata_array.vhd - D-cache data SRAM: 256 lines x 128b (4 words)
-- word load + byte-strobed store-hit + whole-line refill/writeback
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
    type mem_t is array (0 to 255) of std_logic_vector(127 downto 0);
    signal mem : mem_t;
    signal i   : integer range 0 to 255;
begin
    i <= to_integer(unsigned(idx));
    line_out <= mem(i);

    process(mem, i, word_off)
    begin
        case word_off is
            when "00"   => word_out <= mem(i)(31 downto 0);
            when "01"   => word_out <= mem(i)(63 downto 32);
            when "10"   => word_out <= mem(i)(95 downto 64);
            when others => word_out <= mem(i)(127 downto 96);
        end case;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if line_fill = '1' then
                mem(i) <= fill_line;
            elsif we = '1' then
                case word_off is
                    when "00" =>
                        if wstrb(0)='1' then mem(i)(7 downto 0)    <= wdata(7 downto 0);   end if;
                        if wstrb(1)='1' then mem(i)(15 downto 8)   <= wdata(15 downto 8);  end if;
                        if wstrb(2)='1' then mem(i)(23 downto 16)  <= wdata(23 downto 16); end if;
                        if wstrb(3)='1' then mem(i)(31 downto 24)  <= wdata(31 downto 24); end if;
                    when "01" =>
                        if wstrb(0)='1' then mem(i)(39 downto 32)  <= wdata(7 downto 0);   end if;
                        if wstrb(1)='1' then mem(i)(47 downto 40)  <= wdata(15 downto 8);  end if;
                        if wstrb(2)='1' then mem(i)(55 downto 48)  <= wdata(23 downto 16); end if;
                        if wstrb(3)='1' then mem(i)(63 downto 56)  <= wdata(31 downto 24); end if;
                    when "10" =>
                        if wstrb(0)='1' then mem(i)(71 downto 64)  <= wdata(7 downto 0);   end if;
                        if wstrb(1)='1' then mem(i)(79 downto 72)  <= wdata(15 downto 8);  end if;
                        if wstrb(2)='1' then mem(i)(87 downto 80)  <= wdata(23 downto 16); end if;
                        if wstrb(3)='1' then mem(i)(95 downto 88)  <= wdata(31 downto 24); end if;
                    when others =>
                        if wstrb(0)='1' then mem(i)(103 downto 96) <= wdata(7 downto 0);   end if;
                        if wstrb(1)='1' then mem(i)(111 downto 104)<= wdata(15 downto 8);  end if;
                        if wstrb(2)='1' then mem(i)(119 downto 112)<= wdata(23 downto 16); end if;
                        if wstrb(3)='1' then mem(i)(127 downto 120)<= wdata(31 downto 24); end if;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
