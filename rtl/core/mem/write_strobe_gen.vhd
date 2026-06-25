-- write_strobe_gen.vhd - SB/SH/SW -> wstrb[3:0] + lane-aligned wdata
-- Spec: Movement.md 6.5
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity write_strobe_gen is
    Port (
        funct3        : in  std_logic_vector(2 downto 0);
        byte_off      : in  std_logic_vector(1 downto 0);
        store_data    : in  std_logic_vector(31 downto 0);
        wstrb         : out std_logic_vector(3 downto 0);
        wdata_aligned : out std_logic_vector(31 downto 0)
    );
end write_strobe_gen;

architecture Behavioral of write_strobe_gen is
begin
    process(funct3, byte_off, store_data)
    begin
        wstrb <= "0000";
        wdata_aligned <= store_data;
        case funct3 is
            when "000" =>  -- SB : replicate byte to all lanes; strobe selects
                wdata_aligned <= store_data(7 downto 0) & store_data(7 downto 0) &
                                 store_data(7 downto 0) & store_data(7 downto 0);
                case byte_off is
                    when "00"   => wstrb <= "0001";
                    when "01"   => wstrb <= "0010";
                    when "10"   => wstrb <= "0100";
                    when others => wstrb <= "1000";
                end case;
            when "001" =>  -- SH
                wdata_aligned <= store_data(15 downto 0) & store_data(15 downto 0);
                if byte_off(1) = '0' then wstrb <= "0011"; else wstrb <= "1100"; end if;
            when "010" =>  -- SW
                wdata_aligned <= store_data;
                wstrb <= "1111";
            when others =>
                wstrb <= "0000";
        end case;
    end process;
end Behavioral;
