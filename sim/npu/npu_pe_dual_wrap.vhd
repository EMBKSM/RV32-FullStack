-- npu_pe_dual_wrap.vhd - OOC synth wrapper: forces GPU_LANE=true so synthesis
-- builds the dual-mode PE (NPU MAC + GPU multiply-add). Used to prove the whole
-- thing maps to exactly ONE DSP48E1. All ports pass through (no logic stripped).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity npu_pe_dual_wrap is
    Port (
        clk   : in  std_logic;
        en    : in  std_logic;
        clr   : in  std_logic;
        a_in  : in  std_logic_vector(7 downto 0);
        b_in  : in  std_logic_vector(7 downto 0);
        a_out : out std_logic_vector(7 downto 0);
        b_out : out std_logic_vector(7 downto 0);
        acc   : out std_logic_vector(31 downto 0);
        gpu_mode : in  std_logic;
        g_a   : in  std_logic_vector(15 downto 0);
        g_b   : in  std_logic_vector(15 downto 0);
        g_c   : in  std_logic_vector(31 downto 0);
        g_y   : out std_logic_vector(31 downto 0)
    );
end npu_pe_dual_wrap;

architecture rtl of npu_pe_dual_wrap is
begin
    u : entity work.npu_pe
        generic map (DSP_USE => "yes", GPU_LANE => true)
        port map (clk=>clk, en=>en, clr=>clr, a_in=>a_in, b_in=>b_in,
                  a_out=>a_out, b_out=>b_out, acc=>acc,
                  gpu_mode=>gpu_mode, g_a=>g_a, g_b=>g_b, g_c=>g_c, g_y=>g_y);
end rtl;
