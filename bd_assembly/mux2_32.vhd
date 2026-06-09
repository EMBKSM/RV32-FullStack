-- mux2_32 : 2:1 32-bit mux  (y = d1 when sel='1' else d0)
-- rv32_core inline muxes: next_pc redirect, csr_wdata, alu_a, alu_b, exmem CSR-fold.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity mux2_32 is
    Port ( d0  : in  std_logic_vector(31 downto 0);
           d1  : in  std_logic_vector(31 downto 0);
           sel : in  std_logic;
           y   : out std_logic_vector(31 downto 0) );
end mux2_32;
architecture rtl of mux2_32 is
begin
    y <= d1 when sel = '1' else d0;
end rtl;
