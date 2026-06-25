-- mux3_32 : 3:1 32-bit forwarding mux
--   sel="10" -> d_exmem (EX/MEM forward), "01" -> d_wb (MEM/WB forward), else d_reg.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity mux3_32 is
    Port ( d_reg   : in  std_logic_vector(31 downto 0);
           d_wb    : in  std_logic_vector(31 downto 0);
           d_exmem : in  std_logic_vector(31 downto 0);
           sel     : in  std_logic_vector(1 downto 0);
           y       : out std_logic_vector(31 downto 0) );
end mux3_32;
architecture rtl of mux3_32 is
begin
    y <= d_exmem when sel = "10" else
         d_wb    when sel = "01" else
         d_reg;
end rtl;
