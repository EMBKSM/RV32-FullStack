-- read_aligner.vhd - load extract + sign/zero extend (funct3, byte_off)
-- Spec: Movement.md 6.4. Input is the already word-selected 32-bit word.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity read_aligner is
    Port (
        word_data : in  std_logic_vector(31 downto 0);
        byte_off  : in  std_logic_vector(1 downto 0);
        funct3    : in  std_logic_vector(2 downto 0);
        read_data : out std_logic_vector(31 downto 0)
    );
end read_aligner;

architecture Behavioral of read_aligner is
begin
    process(word_data, byte_off, funct3)
        variable b : std_logic_vector(7 downto 0);
        variable h : std_logic_vector(15 downto 0);
    begin
        case byte_off is
            when "00"   => b := word_data(7 downto 0);
            when "01"   => b := word_data(15 downto 8);
            when "10"   => b := word_data(23 downto 16);
            when others => b := word_data(31 downto 24);
        end case;
        if byte_off(1) = '0' then h := word_data(15 downto 0);
        else                      h := word_data(31 downto 16); end if;

        case funct3 is
            when "000"  => read_data <= std_logic_vector(resize(signed(b), 32));    -- LB
            when "001"  => read_data <= std_logic_vector(resize(signed(h), 32));    -- LH
            when "010"  => read_data <= word_data;                                  -- LW
            when "100"  => read_data <= std_logic_vector(resize(unsigned(b), 32));  -- LBU
            when "101"  => read_data <= std_logic_vector(resize(unsigned(h), 32));  -- LHU
            when others => read_data <= word_data;
        end case;
    end process;
end Behavioral;
