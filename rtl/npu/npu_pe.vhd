-- npu_pe.vhd - INT8 MAC processing element for the systolic GEMM array.
-- Output-stationary: accumulates C[i][j] += a_in*b_in each enabled cycle, and
-- passes a_in to the right and b_in downward (one-cycle registered hops).
-- The multiply+accumulate maps to one DSP48E1 (use_dsp); pass-through regs are FFs.
--
-- DUAL-MODE (GPU_LANE=true): the SAME DSP can instead serve one GPU vector lane,
-- computing A*B + C (16x16 signed multiply-add) when gpu_mode='1'. Because there
-- is exactly ONE multiply expression (mul_a*mul_b) with MUXED operands, synthesis
-- maps both modes onto a SINGLE DSP48E1 -> the GPU adds 0 DSP. The NPU and GPU
-- never run at once, so time-sharing the multiplier is safe.
-- See docs/UNIFIED_NPU_GPU.md. GPU_LANE=false PEs are functionally identical to before.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity npu_pe is
    generic (
        DSP_USE  : string  := "yes";    -- "yes"=DSP48E1, "no"=LUT-fabric multiplier
        GPU_LANE : boolean := false      -- true => this PE's DSP is also a GPU lane multiplier
    );
    Port (
        clk   : in  std_logic;
        en    : in  std_logic;                       -- stream/advance enable
        clr   : in  std_logic;                       -- clear accumulator (1 cycle before a run)
        a_in  : in  std_logic_vector(7 downto 0);    -- from left  (signed INT8)
        b_in  : in  std_logic_vector(7 downto 0);    -- from top   (signed INT8)
        a_out : out std_logic_vector(7 downto 0);    -- to right
        b_out : out std_logic_vector(7 downto 0);    -- to below
        acc   : out std_logic_vector(31 downto 0);   -- INT32 accumulator
        -- shared-DSP GPU-lane port (only meaningful when GPU_LANE=true)
        gpu_mode : in  std_logic := '0';                                  -- 1 = DSP serves the GPU lane
        g_a      : in  std_logic_vector(15 downto 0) := (others => '0');  -- GPU operand A
        g_b      : in  std_logic_vector(15 downto 0) := (others => '0');  -- GPU operand B
        g_c      : in  std_logic_vector(31 downto 0) := (others => '0');  -- GPU addend (Vd / 0)
        g_y      : out std_logic_vector(31 downto 0)                      -- GPU product A*B + C
    );
end npu_pe;

architecture rtl of npu_pe is
    attribute use_dsp : string;
    signal a_r, b_r : signed(7 downto 0)  := (others => '0');
    signal p        : signed(31 downto 0) := (others => '0');  -- shared DSP result/accumulator
    attribute use_dsp of p : signal is DSP_USE;      -- ONE DSP48E1 serves both modes
    -- muxed operands feeding the SINGLE multiply (this is what forces 1 DSP)
    signal use_gpu      : boolean;
    signal mul_a, mul_b : signed(15 downto 0);
    signal mul_c        : signed(31 downto 0);
begin
    use_gpu <= GPU_LANE and (gpu_mode = '1');
    mul_a   <= signed(g_a)               when use_gpu else resize(signed(a_in), 16);
    mul_b   <= signed(g_b)               when use_gpu else resize(signed(b_in), 16);
    mul_c   <= signed(g_c)               when use_gpu else p;   -- GPU: add C ; NPU: accumulate

    process(clk)
    begin
        if rising_edge(clk) then
            if (not use_gpu) and clr = '1' then
                p <= (others => '0');                       -- NPU pre-run clear (priority)
            elsif use_gpu or en = '1' then
                p <= resize(mul_a * mul_b, 32) + mul_c;     -- the ONE shared multiply-add
            end if;
            if en = '1' then                                -- systolic pass-through
                a_r <= signed(a_in);
                b_r <= signed(b_in);
            end if;
        end if;
    end process;

    a_out <= std_logic_vector(a_r);
    b_out <= std_logic_vector(b_r);
    acc   <= std_logic_vector(p);
    g_y   <= std_logic_vector(p);                    -- GPU reads the same shared register
end rtl;
