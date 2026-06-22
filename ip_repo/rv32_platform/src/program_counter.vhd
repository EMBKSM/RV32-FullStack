library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pc_reg is
    Generic (
        RESET_ADDR : std_logic_vector(31 downto 0) := x"00000000"
    );
    Port (
        clk      : in  std_logic;                      
        reset    : in  std_logic;                      
        stall    : in  std_logic;                      
        next_pc  : in  std_logic_vector(31 downto 0);  
        pc       : out std_logic_vector(31 downto 0)   
    );
end pc_reg;

architecture Behavioral of pc_reg is
    signal pc_internal : std_logic_vector(31 downto 0);
begin
    process(clk, reset)
    begin
        if reset = '1' then
            pc_internal <= RESET_ADDR;
            
        elsif rising_edge(clk) then
            if stall = '0' then
                pc_internal <= next_pc;
            end if;
        end if;
    end process;

    pc <= pc_internal;
    
end Behavioral;
