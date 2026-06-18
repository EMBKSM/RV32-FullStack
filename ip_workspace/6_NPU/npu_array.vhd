-- npu_array.vhd - N x N output-stationary systolic mesh of npu_pe (generic N).
-- Edge inputs (flattened to avoid 2-D ports):
--   a_west : N x INT8, row i = bits i*8+7..i*8  (enters PE[i][0], flows right)
--   b_north: N x INT8, col j = bits j*8+7..j*8  (enters PE[0][j], flows down)
-- Output acc_flat: N*N x INT32, PE[i][j] at word (i*N+j).
-- en/clr are broadcast to all PEs. Feeders provide the skewed, zero-padded
-- a_west/b_north streams; outside the data window the inputs are 0, so
-- accumulating 0*0 is harmless and no per-PE clear timing is needed.
-- N defaults to 8 (bit-identical to the original 8x8); set N=16 for scale-up.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity npu_array is
    generic (
        N          : integer := 8;         -- array dimension
        DSP_BUDGET : integer := 256        -- # PEs (row-major) mapped to DSP48E1; rest use LUT MAC
    );
    Port (
        clk      : in  std_logic;
        en       : in  std_logic;
        clr      : in  std_logic;
        a_west   : in  std_logic_vector(N*8-1 downto 0);     -- N x INT8
        b_north  : in  std_logic_vector(N*8-1 downto 0);     -- N x INT8
        acc_flat : out std_logic_vector(N*N*32-1 downto 0)   -- N*N x INT32
    );
end npu_array;

architecture rtl of npu_array is
    type a_wire_t is array (0 to N-1, 0 to N) of std_logic_vector(7 downto 0);
    type b_wire_t is array (0 to N, 0 to N-1) of std_logic_vector(7 downto 0);
    signal aw : a_wire_t;   -- aw(i,j) = a entering PE[i][j]; aw(i,N) = right edge (unused)
    signal bw : b_wire_t;   -- bw(i,j) = b entering PE[i][j]; bw(N,j) = bottom edge (unused)
    function dsp_str(b : boolean) return string is
    begin
        if b then return "yes"; else return "no"; end if;
    end function;
begin
    -- west / north edge inputs from the flattened ports
    gen_west : for i in 0 to N-1 generate
        aw(i,0) <= a_west(i*8+7 downto i*8);
    end generate;
    gen_north : for j in 0 to N-1 generate
        bw(0,j) <= b_north(j*8+7 downto j*8);
    end generate;

    -- N x N PE mesh. The first DSP_BUDGET PEs (row-major p=i*N+j) map to DSP48E1;
    -- any beyond the budget fall back to LUT-fabric MACs (so 16x16=256 MAC fits 220 DSP).
    gen_row : for i in 0 to N-1 generate
        gen_col : for j in 0 to N-1 generate
            constant PIDX : integer := i*N + j;
            constant UD   : string  := dsp_str(PIDX < DSP_BUDGET);
        begin
            u_pe : entity work.npu_pe
                generic map ( DSP_USE => UD )
                port map (
                    clk   => clk,
                    en    => en,
                    clr   => clr,
                    a_in  => aw(i, j),
                    b_in  => bw(i, j),
                    a_out => aw(i, j+1),
                    b_out => bw(i+1, j),
                    acc   => acc_flat((i*N+j)*32+31 downto (i*N+j)*32)
                );
        end generate;
    end generate;
end rtl;
