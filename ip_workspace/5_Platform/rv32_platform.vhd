-- =====================================================================
-- rv32_platform.vhd  -  synthesizable PL top (AXI-Lite controlled rv32 SoC)
-- rv32_core + I$ + D$ + instruction/data RAM + MMIO(LED/SW/BTN) + AXI-Lite
-- control/status slave (rv32_ctrl_axi) for the Zynq PS. Single clock/reset =
-- S_AXI_ACLK / S_AXI_ARESETN. The PS loads memory, controls reset/run/step,
-- and reads back register/PC/commit/data via the AXI-Lite registers.
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity rv32_platform is
    Generic ( LED_W : integer := 4; SW_W : integer := 4; BTN_W : integer := 4 );
    Port (
        -- AXI4-Lite slave (from PS M_AXI_GP0)
        S_AXI_ACLK    : in  std_logic;
        S_AXI_ARESETN : in  std_logic;
        S_AXI_AWADDR  : in  std_logic_vector(7 downto 0);
        S_AXI_AWVALID : in  std_logic;
        S_AXI_AWREADY : out std_logic;
        S_AXI_WDATA   : in  std_logic_vector(31 downto 0);
        S_AXI_WSTRB   : in  std_logic_vector(3 downto 0);
        S_AXI_WVALID  : in  std_logic;
        S_AXI_WREADY  : out std_logic;
        S_AXI_BRESP   : out std_logic_vector(1 downto 0);
        S_AXI_BVALID  : out std_logic;
        S_AXI_BREADY  : in  std_logic;
        S_AXI_ARADDR  : in  std_logic_vector(7 downto 0);
        S_AXI_ARVALID : in  std_logic;
        S_AXI_ARREADY : out std_logic;
        S_AXI_RDATA   : out std_logic_vector(31 downto 0);
        S_AXI_RRESP   : out std_logic_vector(1 downto 0);
        S_AXI_RVALID  : out std_logic;
        S_AXI_RREADY  : in  std_logic;
        -- board GPIO
        led_o : out std_logic_vector(LED_W-1 downto 0);
        sw_i  : in  std_logic_vector(SW_W-1 downto 0);
        btn_i : in  std_logic_vector(BTN_W-1 downto 0)
    );
end rv32_platform;

architecture Behavioral of rv32_platform is
    signal clk, rst, core_rst : std_logic;

    -- core <-> I$
    signal imem_addr, imem_rdata : std_logic_vector(31 downto 0);
    signal ic_fence_i, i_stall   : std_logic;
    -- core data <-> mmio_bridge
    signal dmem_addr, dmem_wdata, dmem_rdata : std_logic_vector(31 downto 0);
    signal dmem_wstrb : std_logic_vector(3 downto 0);
    signal dmem_we, dmem_re, c_stall, mem_stall : std_logic;
    -- mmio_bridge <-> D$
    signal bd_addr, bd_wdata, bd_rdata : std_logic_vector(31 downto 0);
    signal bd_wstrb : std_logic_vector(3 downto 0);
    signal bd_we, bd_re, d_req, d_stall : std_logic;

    -- AXI master buses (cache <-> memory)
    signal i_ARADDR,i_RDATA,i_AWADDR,i_WDATA : std_logic_vector(31 downto 0);
    signal i_WSTRB : std_logic_vector(3 downto 0);
    signal i_ARVALID,i_ARREADY,i_RLAST,i_RVALID,i_RREADY,
           i_AWVALID,i_AWREADY,i_WLAST,i_WVALID,i_WREADY,i_BVALID,i_BREADY : std_logic;
    signal d_ARADDR,d_RDATA,d_AWADDR,d_WDATA : std_logic_vector(31 downto 0);
    signal d_WSTRB : std_logic_vector(3 downto 0);
    signal d_ARVALID,d_ARREADY,d_RLAST,d_RVALID,d_RREADY,
           d_AWVALID,d_AWREADY,d_WLAST,d_WVALID,d_WREADY,d_BVALID,d_BREADY : std_logic;

    -- control <-> rest
    signal cpu_reset, run_en, step : std_logic;
    signal ld_iwe, ld_dwe : std_logic;
    signal ld_iaddr, ld_idata, ld_daddr, ld_ddata : std_logic_vector(31 downto 0);
    signal c_dbg_reg_addr : std_logic_vector(4 downto 0);
    signal c_dbg_reg_data : std_logic_vector(31 downto 0);
    signal dump_raddr, dump_rdata : std_logic_vector(31 downto 0);
    signal dbg_rd : std_logic_vector(4 downto 0);
    signal dbg_wdata : std_logic_vector(31 downto 0);
    signal dbg_commit, halted : std_logic;

    -- step/run control
    signal host_hold, stepping : std_logic := '0';
begin
    clk      <= S_AXI_ACLK;
    rst      <= not S_AXI_ARESETN;
    core_rst <= rst or cpu_reset;                 -- PS can hold/invalidate the CPU+caches

    -- global memory stall = I$ miss OR D$/MMIO stall OR host freeze
    mem_stall <= i_stall or c_stall or host_hold;
    d_req     <= bd_re or bd_we;

    -- ===================== control slave =====================
    u_ctrl : entity work.rv32_ctrl_axi
        port map (
            S_AXI_ACLK=>S_AXI_ACLK, S_AXI_ARESETN=>S_AXI_ARESETN,
            S_AXI_AWADDR=>S_AXI_AWADDR, S_AXI_AWVALID=>S_AXI_AWVALID, S_AXI_AWREADY=>S_AXI_AWREADY,
            S_AXI_WDATA=>S_AXI_WDATA, S_AXI_WSTRB=>S_AXI_WSTRB, S_AXI_WVALID=>S_AXI_WVALID, S_AXI_WREADY=>S_AXI_WREADY,
            S_AXI_BRESP=>S_AXI_BRESP, S_AXI_BVALID=>S_AXI_BVALID, S_AXI_BREADY=>S_AXI_BREADY,
            S_AXI_ARADDR=>S_AXI_ARADDR, S_AXI_ARVALID=>S_AXI_ARVALID, S_AXI_ARREADY=>S_AXI_ARREADY,
            S_AXI_RDATA=>S_AXI_RDATA, S_AXI_RRESP=>S_AXI_RRESP, S_AXI_RVALID=>S_AXI_RVALID, S_AXI_RREADY=>S_AXI_RREADY,
            cpu_reset=>cpu_reset, run_en=>run_en, step=>step,
            imem_we=>ld_iwe, imem_addr=>ld_iaddr, imem_data=>ld_idata,
            dmem_we=>ld_dwe, dmem_addr=>ld_daddr, dmem_data=>ld_ddata,
            dbg_reg_addr=>c_dbg_reg_addr, dbg_reg_data=>c_dbg_reg_data,
            dmem_raddr=>dump_raddr, dmem_rdata=>dump_rdata,
            pc_in=>imem_addr, dbg_rd=>dbg_rd, dbg_wdata=>dbg_wdata, dbg_commit=>dbg_commit,
            halted=>halted);

    -- ===================== CPU core =====================
    u_core : entity work.rv32_core
        port map (clk=>clk, reset=>core_rst,
                  imem_addr=>imem_addr, imem_rdata=>imem_rdata,
                  dmem_addr=>dmem_addr, dmem_wdata=>dmem_wdata, dmem_wstrb=>dmem_wstrb,
                  dmem_we=>dmem_we, dmem_re=>dmem_re, dmem_rdata=>dmem_rdata,
                  mem_stall=>mem_stall,
                  dbg_commit=>dbg_commit, dbg_rd=>dbg_rd, dbg_wdata=>dbg_wdata,
                  dbg_reg_addr=>c_dbg_reg_addr, dbg_reg_data=>c_dbg_reg_data,
                  ic_fence_i=>ic_fence_i);

    -- ===================== MMIO bridge (data bus) =====================
    u_mmio : entity work.mmio_bridge
        generic map (LED_W=>LED_W, SW_W=>SW_W, BTN_W=>BTN_W)
        port map (clk=>clk, reset=>rst,
                  c_addr=>dmem_addr, c_wdata=>dmem_wdata, c_wstrb=>dmem_wstrb,
                  c_we=>dmem_we, c_re=>dmem_re, c_rdata=>dmem_rdata, c_stall=>c_stall,
                  d_addr=>bd_addr, d_wdata=>bd_wdata, d_wstrb=>bd_wstrb,
                  d_we=>bd_we, d_re=>bd_re, d_rdata=>bd_rdata, d_stall=>d_stall,
                  led_o=>led_o, sw_i=>sw_i, btn_i=>btn_i);

    -- ===================== I-cache + instruction RAM =====================
    u_icache : entity work.icache_unit
        port map (clk=>clk, reset=>core_rst, addr=>imem_addr, rword=>imem_rdata, stall=>i_stall,
                  fence_i=>ic_fence_i, ext_inv=>'0', iflush=>open,
                  ARADDR=>i_ARADDR,ARVALID=>i_ARVALID,ARREADY=>i_ARREADY,
                  RDATA=>i_RDATA,RLAST=>i_RLAST,RVALID=>i_RVALID,RREADY=>i_RREADY,
                  AWADDR=>i_AWADDR,AWVALID=>i_AWVALID,AWREADY=>i_AWREADY,
                  WDATA=>i_WDATA,WSTRB=>i_WSTRB,WLAST=>i_WLAST,WVALID=>i_WVALID,WREADY=>i_WREADY,
                  BVALID=>i_BVALID,BREADY=>i_BREADY);

    -- NOTE: memory AXI FSM resets with core_rst (NOT plain rst) so it stays
    -- synchronized with the cache's adapter -- otherwise a cpu_reset mid-burst
    -- leaves the memory dangling in R_DATA and the cache deadlocks. prog_* load
    -- is reset-independent, so the loaded image is preserved across cpu_reset.
    u_imem : entity work.axi_slave_mem
        generic map (WORDS=>4096)
        port map (clk=>clk, reset=>core_rst,
                  prog_we=>ld_iwe, prog_addr=>ld_iaddr, prog_data=>ld_idata,
                  ARADDR=>i_ARADDR,ARVALID=>i_ARVALID,ARREADY=>i_ARREADY,
                  RDATA=>i_RDATA,RLAST=>i_RLAST,RVALID=>i_RVALID,RREADY=>i_RREADY,
                  AWADDR=>i_AWADDR,AWVALID=>i_AWVALID,AWREADY=>i_AWREADY,
                  WDATA=>i_WDATA,WSTRB=>i_WSTRB,WLAST=>i_WLAST,WVALID=>i_WVALID,WREADY=>i_WREADY,
                  BVALID=>i_BVALID,BREADY=>i_BREADY);

    -- ===================== D-cache + data RAM (with dump port) =====================
    u_dcache : entity work.cache_unit
        port map (clk=>clk, reset=>core_rst, req=>d_req, we=>bd_we, addr=>bd_addr,
                  st_data=>bd_wdata, st_strb=>bd_wstrb, rword=>bd_rdata, stall=>d_stall,
                  ARADDR=>d_ARADDR,ARLEN=>open,ARSIZE=>open,ARBURST=>open,
                  ARVALID=>d_ARVALID,ARREADY=>d_ARREADY,RDATA=>d_RDATA,RLAST=>d_RLAST,
                  RVALID=>d_RVALID,RREADY=>d_RREADY,
                  AWADDR=>d_AWADDR,AWLEN=>open,AWSIZE=>open,AWBURST=>open,
                  AWVALID=>d_AWVALID,AWREADY=>d_AWREADY,WDATA=>d_WDATA,WSTRB=>d_WSTRB,
                  WLAST=>d_WLAST,WVALID=>d_WVALID,WREADY=>d_WREADY,BVALID=>d_BVALID,BREADY=>d_BREADY);

    u_dmem : entity work.axi_slave_mem
        generic map (WORDS=>4096)
        port map (clk=>clk, reset=>core_rst,
                  prog_we=>ld_dwe, prog_addr=>ld_daddr, prog_data=>ld_ddata,
                  dbg_raddr=>dump_raddr, dbg_rdata=>dump_rdata,
                  ARADDR=>d_ARADDR,ARVALID=>d_ARVALID,ARREADY=>d_ARREADY,
                  RDATA=>d_RDATA,RLAST=>d_RLAST,RVALID=>d_RVALID,RREADY=>d_RREADY,
                  AWADDR=>d_AWADDR,AWVALID=>d_AWVALID,AWREADY=>d_AWREADY,
                  WDATA=>d_WDATA,WSTRB=>d_WSTRB,WLAST=>d_WLAST,WVALID=>d_WVALID,WREADY=>d_WREADY,
                  BVALID=>d_BVALID,BREADY=>d_BREADY);

    -- ===================== step / run / halt control =====================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stepping <= '0';
            elsif step = '1' then
                stepping <= '1';                    -- begin a single-step
            elsif (stepping = '1' and dbg_commit = '1') then
                stepping <= '0';                    -- one instruction retired -> stop
            end if;
        end if;
    end process;
    host_hold <= '0' when (run_en = '1' or stepping = '1') else '1';

    -- halted = fetching the halt instruction (jal x0,0 = 0x0000006F)
    halted <= '1' when imem_rdata = x"0000006F" else '0';
end Behavioral;
