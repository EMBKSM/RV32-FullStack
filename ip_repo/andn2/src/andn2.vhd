-- andn2 : y = a and (not b)  (commit guards: x AND not mem_stall)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity andn2 is
    Port ( a : in std_logic; b : in std_logic; y : out std_logic );
end andn2;
architecture rtl of andn2 is
begin
    y <= a and (not b);
end rtl;
