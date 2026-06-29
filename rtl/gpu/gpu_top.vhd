-- =====================================================================
-- gpu_top.vhd  -  MMIO slave wrapper for the SIMT-lite coprocessor.
-- Presents the same single-cycle slave shape as npu_top16 so mmio_bridge
-- instantiates it like the NPU (window @ 0x4xxx_xxxx). Sub-map:
--   0x0000 CTRL(w: bit0=START)  0x0004 STATUS(r: b0=DONE b1=BUSY)
--   0x0008 N_LANES(r)           0x0010+4*i SCALAR_ARG[i] (i=0..7)
--   0x1000+4*i IMEM[i]          0x4000+4*i SCRATCHPAD[i]
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gpu_pkg.all;

entity gpu_top is
    generic (
        LANES  : integer := GPU_LANES;
        VREGS  : integer := GPU_VREGS;
        SREGS  : integer := GPU_SREGS;
        IMEM_D : integer := GPU_IMEM;
        BANK_D : integer := GPU_BANKD
    );
    port (
        clk, rst : in  std_logic;
        sel      : in  std_logic;                       -- address-window hit (is_gpu)
        we       : in  std_logic;
        re       : in  std_logic;
        addr     : in  std_logic_vector(15 downto 0);   -- byte address within window
        wdata    : in  std_logic_vector(31 downto 0);
        rdata    : out std_logic_vector(31 downto 0);
        rd_valid : out std_logic;
        -- shared-PE multiply bus to the NPU (VMUL/VMAC run on 8 NPU DSPs; docs/UNIFIED_NPU_GPU.md)
        gpu_active : out std_logic;
        g_a_o      : out std_logic_vector(LANES*16-1 downto 0);
        g_b_o      : out std_logic_vector(LANES*16-1 downto 0);
        g_c_o      : out std_logic_vector(LANES*32-1 downto 0);
        g_y_i      : in  std_logic_vector(LANES*32-1 downto 0) := (others => '0')
    );
end entity gpu_top;

architecture rtl of gpu_top is
    signal start, busy, done       : std_logic;
    signal imem_we, sarg_we, sp_we : std_logic;
    signal sp_rd                   : std_logic_vector(31 downto 0);
    signal sarg_idx_i              : integer range 0 to 7;
    signal regoff                  : integer range 0 to 1023;
    signal is_reg, is_imem, is_sp  : std_logic;
begin
    is_reg  <= '1' when addr(15 downto 12) = "0000" else '0';   -- 0x0000-0x0FFF
    is_imem <= '1' when addr(15 downto 12) = "0001" else '0';   -- 0x1000-0x1FFF
    is_sp   <= '1' when addr(15 downto 14) = "01"   else '0';   -- 0x4000-0x7FFF
    regoff  <= to_integer(unsigned(addr(11 downto 2)));

    -- write strobes
    start   <= '1' when sel='1' and we='1' and is_reg='1' and regoff = 0
                       and wdata(0) = '1' else '0';
    sarg_we <= '1' when sel='1' and we='1' and is_reg='1'
                       and regoff >= 4 and regoff <= 11 else '0';
    imem_we <= sel and we and is_imem;
    sp_we   <= sel and we and is_sp;
    sarg_idx_i <= regoff - 4 when (regoff >= 4 and regoff <= 11) else 0;

    u_core : entity work.gpu_core
        generic map (LANES=>LANES, VREGS=>VREGS, SREGS=>SREGS,
                     IMEM_D=>IMEM_D, BANK_D=>BANK_D)
        port map (
            clk=>clk, rst=>rst, start=>start, busy=>busy, done=>done,
            imem_we   => imem_we,
            imem_addr => "000000" & addr(11 downto 2),         -- word index in imem
            imem_wd   => wdata,
            sarg_we   => sarg_we,
            sarg_idx  => std_logic_vector(to_unsigned(sarg_idx_i, 3)),
            sarg_data => wdata,
            sp_we     => sp_we,
            sp_addr   => "0000" & addr(13 downto 2),           -- element index in scratchpad
            sp_wd     => wdata,
            sp_rd     => sp_rd,
            gpu_active => gpu_active,
            g_a_o => g_a_o, g_b_o => g_b_o, g_c_o => g_c_o, g_y_i => g_y_i);

    -- read mux (single-cycle)
    process(all)
    begin
        if is_sp = '1' then
            rdata <= sp_rd;
        elsif is_reg = '1' and regoff = 1 then
            rdata <= (1 => busy, 0 => done, others => '0');     -- STATUS
        elsif is_reg = '1' and regoff = 2 then
            rdata <= std_logic_vector(to_unsigned(LANES, 32));  -- N_LANES
        else
            rdata <= (others => '0');
        end if;
    end process;

    rd_valid <= sel and re;   -- combinational read -> ready same cycle, no stall
end architecture rtl;
