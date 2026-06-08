-- register_file.vhd - 32x32 RV32I register file, 2R/1W, x0=0, write-first bypass
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity register_file is
    Port (
        clk   : in  std_logic;
        we3   : in  std_logic;
        a1    : in  std_logic_vector(4 downto 0);
        a2    : in  std_logic_vector(4 downto 0);
        a3    : in  std_logic_vector(4 downto 0);
        wd3   : in  std_logic_vector(31 downto 0);
        rd1   : out std_logic_vector(31 downto 0);
        rd2   : out std_logic_vector(31 downto 0)
    );
end register_file;

architecture Behavioral of register_file is
    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));
    signal wr   : std_logic;
begin
    wr <= '1' when (we3 = '1' and a3 /= "00000") else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if wr = '1' then
                regs(to_integer(unsigned(a3))) <= wd3;
            end if;
        end if;
    end process;

    -- combinational read with x0=0 and write-first bypass
    rd1 <= (others => '0')               when a1 = "00000" else
           wd3                           when (wr = '1' and a3 = a1) else
           regs(to_integer(unsigned(a1)));
    rd2 <= (others => '0')               when a2 = "00000" else
           wd3                           when (wr = '1' and a3 = a2) else
           regs(to_integer(unsigned(a2)));
end Behavioral;
