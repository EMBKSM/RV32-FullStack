-- npu_pe.vhd - INT8 MAC processing element for the systolic GEMM array.
-- Output-stationary: accumulates C[i][j] += a_in*b_in each enabled cycle, and
-- passes a_in to the right and b_in downward (one-cycle registered hops).
-- The multiply+accumulate maps to one DSP48E1 (use_dsp); pass-through regs are FFs.
-- Mirrors the cycle-accurate model validated against a GEMM golden (2412 tests, 0 fail).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity npu_pe is
    generic ( DSP_USE : string := "yes" );   -- "yes"=DSP48E1 MAC, "no"=LUT-fabric MAC (distinct name from the use_dsp attribute)
    Port (
        clk   : in  std_logic;
        en    : in  std_logic;                       -- stream/advance enable
        clr   : in  std_logic;                       -- clear accumulator (1 cycle before a run)
        a_in  : in  std_logic_vector(7 downto 0);    -- from left  (signed INT8)
        b_in  : in  std_logic_vector(7 downto 0);    -- from top   (signed INT8)
        a_out : out std_logic_vector(7 downto 0);    -- to right
        b_out : out std_logic_vector(7 downto 0);    -- to below
        acc   : out std_logic_vector(31 downto 0)    -- INT32 accumulator
    );
end npu_pe;

architecture rtl of npu_pe is
    attribute use_dsp : string;
    signal a_r, b_r : signed(7 downto 0)  := (others => '0');
    signal p        : signed(31 downto 0) := (others => '0');
    attribute use_dsp of p : signal is DSP_USE;      -- DSP48E1 mult+accumulate, or LUT fabric
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if clr = '1' then
                p <= (others => '0');               -- clear has priority (pre-run clear cycle)
            elsif en = '1' then
                p <= p + signed(a_in) * signed(b_in);
            end if;
            if en = '1' then                         -- pass-through advances with the stream
                a_r <= signed(a_in);
                b_r <= signed(b_in);
            end if;
        end if;
    end process;

    a_out <= std_logic_vector(a_r);
    b_out <= std_logic_vector(b_r);
    acc   <= std_logic_vector(p);
end rtl;
