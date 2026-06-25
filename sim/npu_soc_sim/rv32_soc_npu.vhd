-- rv32_soc_npu.vhd - SIMULATION top = rv32_soc + mmio_bridge(+NPU) on the data path.
-- Same prog-preload + dbg-register-read interface as rv32_soc, but the core's
-- data port now goes through mmio_bridge (which owns MMIO @0x1xxx_xxxx and the
-- NPU @0x3xxx_xxxx); everything else falls through to the real D-cache. This lets
-- a CPU program drive the *actual* CPU+bridge+NPU RTL end-to-end in xsim.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rv32_soc_npu is
    Generic ( RESET_ADDR : std_logic_vector(31 downto 0) := x"00000000" );
    Port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        prog_we    : in  std_logic;
        prog_addr  : in  std_logic_vector(31 downto 0);
        prog_data  : in  std_logic_vector(31 downto 0);
        dmem_we_pre   : in  std_logic;
        dmem_addr_pre : in  std_logic_vector(31 downto 0);
        dmem_data_pre : in  std_logic_vector(31 downto 0);
        dbg_commit   : out std_logic;
        dbg_rd       : out std_logic_vector(4 downto 0);
        dbg_wdata    : out std_logic_vector(31 downto 0);
        dbg_reg_addr : in  std_logic_vector(4 downto 0);
        dbg_reg_data : out std_logic_vector(31 downto 0);
        dbg_pc       : out std_logic_vector(31 downto 0);
        dbg_instr    : out std_logic_vector(31 downto 0);
        dbg_mstall   : out std_logic
    );
end rv32_soc_npu;

architecture Behavioral of rv32_soc_npu is
    signal imem_addr, imem_rdata : std_logic_vector(31 downto 0);
    -- core data port <-> bridge (c_*) ; bridge <-> D-cache (dc_*)
    signal c_addr, c_wdata, c_rdata : std_logic_vector(31 downto 0);
    signal c_wstrb : std_logic_vector(3 downto 0);
    signal c_we, c_re, c_stall : std_logic;
    signal dc_addr, dc_wdata, dc_rdata : std_logic_vector(31 downto 0);
    signal dc_wstrb : std_logic_vector(3 downto 0);
    signal dc_we, dc_re, dc_stall, dc_req : std_logic;
    signal i_stall, mem_stall, ic_fence_i : std_logic;
    signal zero22 : std_logic_vector(21 downto 0) := (others=>'0');

    -- I-cache AXI
    signal i_ARADDR, i_AWADDR, i_WDATA, i_RDATA : std_logic_vector(31 downto 0);
    signal i_WSTRB : std_logic_vector(3 downto 0);
    signal i_ARVALID,i_ARREADY,i_RLAST,i_RVALID,i_RREADY : std_logic;
    signal i_AWVALID,i_AWREADY,i_WLAST,i_WVALID,i_WREADY,i_BVALID,i_BREADY : std_logic;
    -- D-cache AXI
    signal d_ARADDR, d_AWADDR, d_WDATA, d_RDATA : std_logic_vector(31 downto 0);
    signal d_ARLEN, d_AWLEN : std_logic_vector(7 downto 0);
    signal d_ARSIZE, d_AWSIZE : std_logic_vector(2 downto 0);
    signal d_ARBURST, d_AWBURST : std_logic_vector(1 downto 0);
    signal d_WSTRB : std_logic_vector(3 downto 0);
    signal d_ARVALID,d_ARREADY,d_RLAST,d_RVALID,d_RREADY : std_logic;
    signal d_AWVALID,d_AWREADY,d_WLAST,d_WVALID,d_WREADY,d_BVALID,d_BREADY : std_logic;
begin
    mem_stall <= i_stall or c_stall;
    dc_req    <= dc_we or dc_re;
    dbg_pc <= imem_addr; dbg_instr <= imem_rdata; dbg_mstall <= mem_stall;

    u_core : entity work.rv32_core
        generic map (RESET_ADDR => RESET_ADDR)
        port map (clk=>clk, reset=>reset,
                  imem_addr=>imem_addr, imem_rdata=>imem_rdata,
                  dmem_addr=>c_addr, dmem_wdata=>c_wdata, dmem_wstrb=>c_wstrb,
                  dmem_we=>c_we, dmem_re=>c_re, dmem_rdata=>c_rdata,
                  mem_stall=>mem_stall,
                  dbg_commit=>dbg_commit, dbg_rd=>dbg_rd, dbg_wdata=>dbg_wdata,
                  dbg_reg_addr=>dbg_reg_addr, dbg_reg_data=>dbg_reg_data,
                  ic_fence_i=>ic_fence_i);

    -- data bus splitter + MMIO + NPU (the unit under test for this sim)
    u_bridge : entity work.mmio_bridge
        port map (clk=>clk, reset=>reset,
                  c_addr=>c_addr, c_wdata=>c_wdata, c_wstrb=>c_wstrb,
                  c_we=>c_we, c_re=>c_re, c_rdata=>c_rdata, c_stall=>c_stall,
                  d_addr=>dc_addr, d_wdata=>dc_wdata, d_wstrb=>dc_wstrb,
                  d_we=>dc_we, d_re=>dc_re, d_rdata=>dc_rdata, d_stall=>dc_stall,
                  led_o=>open, sw_i=>"0000", btn_i=>"0000",
                  gpio_i=>zero22, gpio_o=>open, gpio_t=>open,
                  spi0_sclk=>open, spi0_mosi=>open, spi0_ss_n=>open, spi0_miso=>'0',
                  spi1_sclk=>open, spi1_mosi=>open, spi1_ss_n=>open, spi1_miso=>'0',
                  i2c0_scl_in=>'1', i2c0_sda_in=>'1', i2c0_scl_oe=>open, i2c0_sda_oe=>open,
                  i2c1_scl_in=>'1', i2c1_sda_in=>'1', i2c1_scl_oe=>open, i2c1_sda_oe=>open,
                  uart_tx=>open, uart_rx=>'1', pwm_o=>open);

    -- I-cache + instruction memory (program preloaded via prog_*)
    u_icache : entity work.icache_unit
        port map (clk=>clk, reset=>reset, addr=>imem_addr, rword=>imem_rdata, stall=>i_stall,
                  fence_i=>ic_fence_i, ext_inv=>'0', iflush=>open,
                  ARADDR=>i_ARADDR,ARVALID=>i_ARVALID,ARREADY=>i_ARREADY,
                  RDATA=>i_RDATA,RLAST=>i_RLAST,RVALID=>i_RVALID,RREADY=>i_RREADY,
                  AWADDR=>i_AWADDR,AWVALID=>i_AWVALID,AWREADY=>i_AWREADY,
                  WDATA=>i_WDATA,WSTRB=>i_WSTRB,WLAST=>i_WLAST,WVALID=>i_WVALID,WREADY=>i_WREADY,
                  BVALID=>i_BVALID,BREADY=>i_BREADY);
    u_imem : entity work.axi_slave_mem
        generic map (WORDS => 4096)
        port map (clk=>clk, reset=>reset,
                  prog_we=>prog_we, prog_addr=>prog_addr, prog_data=>prog_data,
                  ARADDR=>i_ARADDR,ARVALID=>i_ARVALID,ARREADY=>i_ARREADY,
                  RDATA=>i_RDATA,RLAST=>i_RLAST,RVALID=>i_RVALID,RREADY=>i_RREADY,
                  AWADDR=>i_AWADDR,AWVALID=>i_AWVALID,AWREADY=>i_AWREADY,
                  WDATA=>i_WDATA,WSTRB=>i_WSTRB,WLAST=>i_WLAST,WVALID=>i_WVALID,WREADY=>i_WREADY,
                  BVALID=>i_BVALID,BREADY=>i_BREADY);

    -- D-cache + data memory (bridge routes non-MMIO/non-NPU here)
    u_dcache : entity work.cache_unit
        port map (clk=>clk, reset=>reset, req=>dc_req, we=>dc_we, addr=>dc_addr,
                  st_data=>dc_wdata, st_strb=>dc_wstrb, rword=>dc_rdata, stall=>dc_stall,
                  ARADDR=>d_ARADDR,ARLEN=>d_ARLEN,ARSIZE=>d_ARSIZE,ARBURST=>d_ARBURST,
                  ARVALID=>d_ARVALID,ARREADY=>d_ARREADY,RDATA=>d_RDATA,RLAST=>d_RLAST,
                  RVALID=>d_RVALID,RREADY=>d_RREADY,
                  AWADDR=>d_AWADDR,AWLEN=>d_AWLEN,AWSIZE=>d_AWSIZE,AWBURST=>d_AWBURST,
                  AWVALID=>d_AWVALID,AWREADY=>d_AWREADY,WDATA=>d_WDATA,WSTRB=>d_WSTRB,
                  WLAST=>d_WLAST,WVALID=>d_WVALID,WREADY=>d_WREADY,BVALID=>d_BVALID,BREADY=>d_BREADY);
    u_dmem : entity work.axi_slave_mem
        generic map (WORDS => 4096)
        port map (clk=>clk, reset=>reset,
                  prog_we=>dmem_we_pre, prog_addr=>dmem_addr_pre, prog_data=>dmem_data_pre,
                  ARADDR=>d_ARADDR,ARVALID=>d_ARVALID,ARREADY=>d_ARREADY,
                  RDATA=>d_RDATA,RLAST=>d_RLAST,RVALID=>d_RVALID,RREADY=>d_RREADY,
                  AWADDR=>d_AWADDR,AWVALID=>d_AWVALID,AWREADY=>d_AWREADY,
                  WDATA=>d_WDATA,WSTRB=>d_WSTRB,WLAST=>d_WLAST,WVALID=>d_WVALID,WREADY=>d_WREADY,
                  BVALID=>d_BVALID,BREADY=>d_BREADY);
end Behavioral;
