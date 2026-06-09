-- orgate2 : y = a or b   (core_stall = load_use_stall or mem_stall; redirect_sel)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity orgate2 is
    Port ( a : in std_logic; b : in std_logic; y : out std_logic );
end orgate2;
architecture rtl of orgate2 is
begin
    y <= a or b;
end rtl;
