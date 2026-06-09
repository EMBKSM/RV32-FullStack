-- fencei_oneshot : 1-cycle FENCE.I invalidate pulse (from rv32_core.vhd)
--   ic_fence_i = is_fence_i AND (NOT seen); seen <= is_fence_i (1-cycle delayed).
--   is_fence_i = idex_is_fence_i (FENCE.I occupying EX).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity fencei_oneshot is
    Port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        is_fence_i : in  std_logic;
        ic_fence_i : out std_logic
    );
end fencei_oneshot;
architecture rtl of fencei_oneshot is
    signal seen : std_logic := '0';
begin
    process(clk, reset)
    begin
        if reset = '1' then
            seen <= '0';
        elsif rising_edge(clk) then
            seen <= is_fence_i;
        end if;
    end process;
    ic_fence_i <= is_fence_i and (not seen);
end rtl;
