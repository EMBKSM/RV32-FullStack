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
        btn_i : in  std_logic_vector(BTN_W-1 downto 0);
        -- Pmod headers JA..JE (bidirectional; tri-state pads inferred here)
        ja_io : inout std_logic_vector(7 downto 0);
        jb_io : inout std_logic_vector(7 downto 0);
        jc_io : inout std_logic_vector(7 downto 0);
        jd_io : inout std_logic_vector(7 downto 0);
        je_io : inout std_logic_vector(7 downto 0)
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

    -- LED register tap (mmio drives it; fed to both the board and the ctrl slave)
    signal led_int : std_logic_vector(LED_W-1 downto 0);

    -- Pmod peripheral nets (mmio_bridge <-> tri-state pads at this top level)
    constant GPIO_W : integer := 22;
    signal gpio_o, gpio_t, gpio_i : std_logic_vector(GPIO_W-1 downto 0);
    signal spi0_sclk, spi0_mosi, spi0_ss_n, spi0_miso : std_logic;
    signal spi1_sclk, spi1_mosi, spi1_ss_n, spi1_miso : std_logic;
    signal i2c0_scl_in, i2c0_scl_oe, i2c0_sda_in, i2c0_sda_oe : std_logic;
    signal i2c1_scl_in, i2c1_scl_oe, i2c1_sda_in, i2c1_sda_oe : std_logic;
    signal uart_tx, uart_rx : std_logic;
    signal pwm_o : std_logic_vector(3 downto 0);
begin
    led_o <= led_int;
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
            halted=>halted,
            led_in=>led_int, sw_in=>sw_i, btn_in=>btn_i);

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
        generic map (LED_W=>LED_W, SW_W=>SW_W, BTN_W=>BTN_W, GPIO_W=>GPIO_W)
        port map (clk=>clk, reset=>rst,
                  c_addr=>dmem_addr, c_wdata=>dmem_wdata, c_wstrb=>dmem_wstrb,
                  c_we=>dmem_we, c_re=>dmem_re, c_rdata=>dmem_rdata, c_stall=>c_stall,
                  d_addr=>bd_addr, d_wdata=>bd_wdata, d_wstrb=>bd_wstrb,
                  d_we=>bd_we, d_re=>bd_re, d_rdata=>bd_rdata, d_stall=>d_stall,
                  led_o=>led_int, sw_i=>sw_i, btn_i=>btn_i,
                  gpio_i=>gpio_i, gpio_o=>gpio_o, gpio_t=>gpio_t,
                  spi0_sclk=>spi0_sclk, spi0_mosi=>spi0_mosi, spi0_ss_n=>spi0_ss_n, spi0_miso=>spi0_miso,
                  spi1_sclk=>spi1_sclk, spi1_mosi=>spi1_mosi, spi1_ss_n=>spi1_ss_n, spi1_miso=>spi1_miso,
                  i2c0_scl_in=>i2c0_scl_in, i2c0_sda_in=>i2c0_sda_in,
                  i2c0_scl_oe=>i2c0_scl_oe, i2c0_sda_oe=>i2c0_sda_oe,
                  i2c1_scl_in=>i2c1_scl_in, i2c1_sda_in=>i2c1_sda_in,
                  i2c1_scl_oe=>i2c1_scl_oe, i2c1_sda_oe=>i2c1_sda_oe,
                  uart_tx=>uart_tx, uart_rx=>uart_rx, pwm_o=>pwm_o);

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

    -- ===================== Pmod pad mapping (tri-state pads) =====================
    -- Output pins are driven directly; input pins are only read (IBUF); GPIO and
    -- I2C pins are tri-stated. Pin index = jX_io(n), n = top row 0..3 / bottom 4..7.

    -- JA -> SPI0 (Pmod Type 2A): 0=SS_n 1=MOSI 2=MISO 3=SCLK ; 4..7 = GPIO[0..3]
    ja_io(0) <= spi0_ss_n;
    ja_io(1) <= spi0_mosi;
    spi0_miso <= ja_io(2);
    ja_io(3) <= spi0_sclk;
    ja_io(4) <= gpio_o(0) when gpio_t(0)='0' else 'Z';   gpio_i(0) <= ja_io(4);
    ja_io(5) <= gpio_o(1) when gpio_t(1)='0' else 'Z';   gpio_i(1) <= ja_io(5);
    ja_io(6) <= gpio_o(2) when gpio_t(2)='0' else 'Z';   gpio_i(2) <= ja_io(6);
    ja_io(7) <= gpio_o(3) when gpio_t(3)='0' else 'Z';   gpio_i(3) <= ja_io(7);

    -- JB -> SPI1 : 0=SS_n 1=MOSI 2=MISO 3=SCLK ; 4..7 = GPIO[4..7]
    jb_io(0) <= spi1_ss_n;
    jb_io(1) <= spi1_mosi;
    spi1_miso <= jb_io(2);
    jb_io(3) <= spi1_sclk;
    jb_io(4) <= gpio_o(4) when gpio_t(4)='0' else 'Z';   gpio_i(4) <= jb_io(4);
    jb_io(5) <= gpio_o(5) when gpio_t(5)='0' else 'Z';   gpio_i(5) <= jb_io(5);
    jb_io(6) <= gpio_o(6) when gpio_t(6)='0' else 'Z';   gpio_i(6) <= jb_io(6);
    jb_io(7) <= gpio_o(7) when gpio_t(7)='0' else 'Z';   gpio_i(7) <= jb_io(7);

    -- JC -> I2C0 (Pmod Type 6A): 2=SCL 3=SDA (open-drain) ; 0,1,4..7 = GPIO[8..13]
    jc_io(2) <= '0' when i2c0_scl_oe='1' else 'Z';   i2c0_scl_in <= jc_io(2);
    jc_io(3) <= '0' when i2c0_sda_oe='1' else 'Z';   i2c0_sda_in <= jc_io(3);
    jc_io(0) <= gpio_o(8)  when gpio_t(8)='0'  else 'Z';  gpio_i(8)  <= jc_io(0);
    jc_io(1) <= gpio_o(9)  when gpio_t(9)='0'  else 'Z';  gpio_i(9)  <= jc_io(1);
    jc_io(4) <= gpio_o(10) when gpio_t(10)='0' else 'Z';  gpio_i(10) <= jc_io(4);
    jc_io(5) <= gpio_o(11) when gpio_t(11)='0' else 'Z';  gpio_i(11) <= jc_io(5);
    jc_io(6) <= gpio_o(12) when gpio_t(12)='0' else 'Z';  gpio_i(12) <= jc_io(6);
    jc_io(7) <= gpio_o(13) when gpio_t(13)='0' else 'Z';  gpio_i(13) <= jc_io(7);

    -- JD -> I2C1 : 2=SCL 3=SDA ; 0,1,4..7 = GPIO[14..19]
    jd_io(2) <= '0' when i2c1_scl_oe='1' else 'Z';   i2c1_scl_in <= jd_io(2);
    jd_io(3) <= '0' when i2c1_sda_oe='1' else 'Z';   i2c1_sda_in <= jd_io(3);
    jd_io(0) <= gpio_o(14) when gpio_t(14)='0' else 'Z';  gpio_i(14) <= jd_io(0);
    jd_io(1) <= gpio_o(15) when gpio_t(15)='0' else 'Z';  gpio_i(15) <= jd_io(1);
    jd_io(4) <= gpio_o(16) when gpio_t(16)='0' else 'Z';  gpio_i(16) <= jd_io(4);
    jd_io(5) <= gpio_o(17) when gpio_t(17)='0' else 'Z';  gpio_i(17) <= jd_io(5);
    jd_io(6) <= gpio_o(18) when gpio_t(18)='0' else 'Z';  gpio_i(18) <= jd_io(6);
    jd_io(7) <= gpio_o(19) when gpio_t(19)='0' else 'Z';  gpio_i(19) <= jd_io(7);

    -- JE -> UART (1=TXD out, 2=RXD in) + PWM (4..7) + GPIO[20,21] on je0,je3
    je_io(1) <= uart_tx;
    uart_rx  <= je_io(2);
    je_io(4) <= pwm_o(0);
    je_io(5) <= pwm_o(1);
    je_io(6) <= pwm_o(2);
    je_io(7) <= pwm_o(3);
    je_io(0) <= gpio_o(20) when gpio_t(20)='0' else 'Z';  gpio_i(20) <= je_io(0);
    je_io(3) <= gpio_o(21) when gpio_t(21)='0' else 'Z';  gpio_i(21) <= je_io(3);
end Behavioral;
