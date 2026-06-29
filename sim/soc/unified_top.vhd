-- unified_top.vhd - OOC synth wrapper: npu_top16 (full 16x16) + gpu_top wired
-- through the shared-PE multiply bus, exactly as mmio_bridge connects them.
-- Synthesize this to count DSPs: the GPU borrows 8 NPU PE DSPs, so the total
-- must be ~the NPU-alone count (the 8 lanes add 0 DSP). See docs/UNIFIED_NPU_GPU.md.
library ieee;
use ieee.std_logic_1164.all;
use work.gpu_pkg.all;

entity unified_top is
    port (
        clk, rst : in  std_logic;
        -- NPU slave (0x3 window)
        npu_sel, npu_we, npu_re : in std_logic;
        npu_addr   : in  std_logic_vector(13 downto 0);
        npu_wdata  : in  std_logic_vector(31 downto 0);
        npu_wstrb  : in  std_logic_vector(3 downto 0);
        npu_rdata  : out std_logic_vector(31 downto 0);
        npu_rd_valid : out std_logic;
        -- GPU slave (0x4 window)
        gpu_sel, gpu_we, gpu_re : in std_logic;
        gpu_addr   : in  std_logic_vector(15 downto 0);
        gpu_wdata  : in  std_logic_vector(31 downto 0);
        gpu_rdata  : out std_logic_vector(31 downto 0);
        gpu_rd_valid : out std_logic
    );
end entity unified_top;

architecture rtl of unified_top is
    signal u_gpu_mode   : std_logic;
    signal u_g_a, u_g_b : std_logic_vector(GPU_LANES*16-1 downto 0);
    signal u_g_c, u_g_y : std_logic_vector(GPU_LANES*32-1 downto 0);
begin
    u_npu : entity work.npu_top16
        port map (clk=>clk, rst=>rst, sel=>npu_sel, we=>npu_we, addr=>npu_addr,
                  wdata=>npu_wdata, wstrb=>npu_wstrb, re=>npu_re,
                  rdata=>npu_rdata, rd_valid=>npu_rd_valid,
                  gpu_mode=>u_gpu_mode, g_a_flat=>u_g_a, g_b_flat=>u_g_b,
                  g_c_flat=>u_g_c, g_y_flat=>u_g_y);

    u_gpu : entity work.gpu_top
        port map (clk=>clk, rst=>rst, sel=>gpu_sel, we=>gpu_we, re=>gpu_re,
                  addr=>gpu_addr, wdata=>gpu_wdata,
                  rdata=>gpu_rdata, rd_valid=>gpu_rd_valid,
                  gpu_active=>u_gpu_mode, g_a_o=>u_g_a, g_b_o=>u_g_b,
                  g_c_o=>u_g_c, g_y_i=>u_g_y);
end architecture rtl;
