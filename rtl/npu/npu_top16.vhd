-- npu_top16.vhd - thin wrapper fixing the generic NPU to a 16x16 array (N=16).
-- Exists so a single-language (SV/VHDL) testbench or BD can instantiate the
-- 16x16 variant without passing generics across the language boundary.
-- Address width AW = ceil(log2 16) + 10 = 14 (16 KiB window):
--   region addr[13:12]: 00 CTRL/STATUS/K/CFG, 01 A(0x1000), 10 B(0x2000), 11 C(0x3000)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity npu_top16 is
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        sel    : in  std_logic;
        we     : in  std_logic;
        addr   : in  std_logic_vector(13 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        wstrb  : in  std_logic_vector(3 downto 0);
        re     : in  std_logic := '0';
        rdata  : out std_logic_vector(31 downto 0);
        rd_valid : out std_logic;
        -- GPU shared-lane bus: the GPU borrows the DSPs of 8 row-0 PEs (docs/UNIFIED_NPU_GPU.md)
        gpu_mode : in  std_logic := '0';
        g_a_flat : in  std_logic_vector(8*16-1 downto 0) := (others => '0');
        g_b_flat : in  std_logic_vector(8*16-1 downto 0) := (others => '0');
        g_c_flat : in  std_logic_vector(8*32-1 downto 0) := (others => '0');
        g_y_flat : out std_logic_vector(8*32-1 downto 0)
    );
end npu_top16;

architecture rtl of npu_top16 is
begin
    u_npu : entity work.npu_top
        generic map (N => 16, AW => 14, DSP_BUDGET => 200, NLANE => 8)   -- full 16x16; the GPU SHARES 8 of these PEs' DSPs (docs/UNIFIED_NPU_GPU.md) -> no extra DSP
        port map (clk=>clk, rst=>rst, sel=>sel, we=>we, addr=>addr,
                  wdata=>wdata, wstrb=>wstrb, re=>re, rdata=>rdata, rd_valid=>rd_valid,
                  gpu_mode=>gpu_mode, g_a_flat=>g_a_flat, g_b_flat=>g_b_flat,
                  g_c_flat=>g_c_flat, g_y_flat=>g_y_flat);
end rtl;
