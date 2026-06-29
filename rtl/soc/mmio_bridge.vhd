-- =====================================================================
-- mmio_bridge.vhd  -  data-bus splitter (cached RAM vs uncached MMIO) +
--                     dedicated Pmod peripheral controllers
--
-- Sits between rv32_core's data port and the D-cache. Addresses in the MMIO
-- region (0x1xxx_xxxx) bypass the cache and hit memory-mapped peripherals
-- (single cycle, no stall); everything else goes to the D-cache unchanged.
--
-- MMIO map (within 0x1000_0000, decoded by addr[7:5]=block, addr[4:2]=reg):
--   0x00 blk0 SYS  : 0x00 LED(W/R) 0x04 SW(R) 0x08 BTN(R)
--   0x20 blk1 GPIO : 0x20 DIR 0x24 OUT 0x28 IN            (gpio_port, 22 pins)
--   0x40 blk2 SPI0 : 0x40 CTRL 0x44 STAT 0x48 DIV 0x4C TX 0x50 RX   (Pmod JA)
--   0x60 blk3 SPI1 : 0x60 CTRL 0x64 STAT 0x68 DIV 0x6C TX 0x70 RX   (Pmod JB)
--   0x80 blk4 I2C0 : 0x80 CMD  0x84 STAT 0x88 DIV 0x8C TX 0x90 RX   (Pmod JC)
--   0xA0 blk5 I2C1 : 0xA0 CMD  0xA4 STAT 0xA8 DIV 0xAC TX 0xB0 RX   (Pmod JD)
--   0xC0 blk6 UART : 0xC0 DIV  0xC4 STAT 0xC8 TX  0xCC RX           (Pmod JE)
--   0xE0 blk7 PWM  : 0xE0 CTRL 0xE4 PERIOD 0xE8 DUTY0..0xF4 DUTY3   (Pmod JE)
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mmio_bridge is
    Generic ( LED_W : integer := 4; SW_W : integer := 4; BTN_W : integer := 4;
              GPIO_W : integer := 22 );
    Port (
        clk     : in  std_logic;
        reset   : in  std_logic;
        -- core data side
        c_addr  : in  std_logic_vector(31 downto 0);
        c_wdata : in  std_logic_vector(31 downto 0);
        c_wstrb : in  std_logic_vector(3 downto 0);
        c_we    : in  std_logic;
        c_re    : in  std_logic;
        c_rdata : out std_logic_vector(31 downto 0);
        c_stall : out std_logic;
        -- D-cache side
        d_addr  : out std_logic_vector(31 downto 0);
        d_wdata : out std_logic_vector(31 downto 0);
        d_wstrb : out std_logic_vector(3 downto 0);
        d_we    : out std_logic;
        d_re    : out std_logic;
        d_rdata : in  std_logic_vector(31 downto 0);
        d_stall : in  std_logic;
        -- board GPIO (legacy)
        led_o   : out std_logic_vector(LED_W-1 downto 0);
        sw_i    : in  std_logic_vector(SW_W-1 downto 0);
        btn_i   : in  std_logic_vector(BTN_W-1 downto 0);
        -- Pmod GPIO bank (tri-state pads live in platform top)
        gpio_i  : in  std_logic_vector(GPIO_W-1 downto 0);
        gpio_o  : out std_logic_vector(GPIO_W-1 downto 0);
        gpio_t  : out std_logic_vector(GPIO_W-1 downto 0);
        -- SPI0 / SPI1
        spi0_sclk, spi0_mosi, spi0_ss_n : out std_logic;  spi0_miso : in std_logic;
        spi1_sclk, spi1_mosi, spi1_ss_n : out std_logic;  spi1_miso : in std_logic;
        -- I2C0 / I2C1 (open-drain enables + line sense)
        i2c0_scl_in, i2c0_sda_in : in  std_logic;
        i2c0_scl_oe, i2c0_sda_oe : out std_logic;
        i2c1_scl_in, i2c1_sda_in : in  std_logic;
        i2c1_scl_oe, i2c1_sda_oe : out std_logic;
        -- UART
        uart_tx : out std_logic;  uart_rx : in std_logic;
        -- PWM
        pwm_o   : out std_logic_vector(3 downto 0)
    );
end mmio_bridge;

architecture Behavioral of mmio_bridge is
    signal is_mmio : std_logic;
    signal blk     : std_logic_vector(2 downto 0);
    signal regw    : std_logic_vector(2 downto 0);
    signal led_reg : std_logic_vector(LED_W-1 downto 0) := (others => '0');
    signal mmio_rd : std_logic_vector(31 downto 0);
    signal sys_rd  : std_logic_vector(31 downto 0);

    -- per-block selects and per-peripheral read data
    signal sel_sys, sel_gpio, sel_spi0, sel_spi1,
           sel_i2c0, sel_i2c1, sel_uart, sel_pwm : std_logic;
    signal gpio_rd, spi0_rd, spi1_rd, i2c0_rd, i2c1_rd, uart_rd, pwm_rd
           : std_logic_vector(31 downto 0);
    -- NPU (uncached accelerator window @ 0x3xxx_xxxx)
    signal is_npu       : std_logic;
    signal npu_rd       : std_logic_vector(31 downto 0);
    signal npu_rd_valid : std_logic;
    signal npu_stall    : std_logic;
    -- GPU (SIMT-lite vector coprocessor window @ 0x4xxx_xxxx)
    signal is_gpu       : std_logic;
    signal gpu_rd       : std_logic_vector(31 downto 0);
    signal gpu_rd_valid : std_logic;
    -- UNIFIED shared-PE multiply bus: the GPU borrows 8 NPU DSPs (docs/UNIFIED_NPU_GPU.md).
    -- gpu_top drives operands/active; npu_top16's row-0 PEs return the products.
    signal u_gpu_mode   : std_logic;
    signal u_g_a, u_g_b : std_logic_vector(8*16-1 downto 0);
    signal u_g_c, u_g_y : std_logic_vector(8*32-1 downto 0);
begin
    -- MMIO region = 0x1xxx_xxxx
    is_mmio <= '1' when c_addr(31 downto 28) = x"1" else '0';
    is_npu  <= '1' when c_addr(31 downto 28) = x"3" else '0';
    is_gpu  <= '1' when c_addr(31 downto 28) = x"4" else '0';
    blk     <= c_addr(7 downto 5);
    regw    <= c_addr(4 downto 2);

    -- to D-cache: addr/wdata/wstrb pass through; only enable on non-MMIO access
    d_addr  <= c_addr;
    d_wdata <= c_wdata;
    d_wstrb <= c_wstrb;
    d_we    <= c_we and not is_mmio and not is_npu and not is_gpu;
    d_re    <= c_re and not is_mmio and not is_npu and not is_gpu;

    -- block selects
    sel_sys  <= '1' when is_mmio='1' and blk="000" else '0';
    sel_gpio <= '1' when is_mmio='1' and blk="001" else '0';
    sel_spi0 <= '1' when is_mmio='1' and blk="010" else '0';
    sel_spi1 <= '1' when is_mmio='1' and blk="011" else '0';
    sel_i2c0 <= '1' when is_mmio='1' and blk="100" else '0';
    sel_i2c1 <= '1' when is_mmio='1' and blk="101" else '0';
    sel_uart <= '1' when is_mmio='1' and blk="110" else '0';
    sel_pwm  <= '1' when is_mmio='1' and blk="111" else '0';

    -- legacy SYS read (LED/SW/BTN)
    with regw select sys_rd <=
        std_logic_vector(resize(unsigned(led_reg), 32)) when "000",
        std_logic_vector(resize(unsigned(sw_i),    32)) when "001",
        std_logic_vector(resize(unsigned(btn_i),   32)) when "010",
        (others => '0')                                 when others;

    -- top-level MMIO read mux (by block)
    with blk select mmio_rd <=
        sys_rd   when "000",
        gpio_rd  when "001",
        spi0_rd  when "010",
        spi1_rd  when "011",
        i2c0_rd  when "100",
        i2c1_rd  when "101",
        uart_rd  when "110",
        pwm_rd   when "111",
        (others=>'0') when others;

    -- LED output register (store to 0x1000_0000)
    process(clk, reset)
    begin
        if reset = '1' then
            led_reg <= (others => '0');
        elsif rising_edge(clk) then
            if (sel_sys='1' and c_we='1' and regw="000") then
                led_reg <= c_wdata(LED_W-1 downto 0);
            end if;
        end if;
    end process;
    led_o <= led_reg;

    -- ===================== peripheral controllers =====================
    u_gpio : entity work.gpio_port
        generic map (WIDTH=>GPIO_W)
        port map (clk=>clk, rst=>reset, sel=>sel_gpio, we=>c_we, reg=>regw,
                  wdata=>c_wdata, rdata=>gpio_rd,
                  gpio_i=>gpio_i, gpio_o=>gpio_o, gpio_t=>gpio_t);

    u_spi0 : entity work.spi_master
        port map (clk=>clk, rst=>reset, sel=>sel_spi0, we=>c_we, reg=>regw,
                  wdata=>c_wdata, rdata=>spi0_rd,
                  sclk=>spi0_sclk, mosi=>spi0_mosi, miso=>spi0_miso, ss_n=>spi0_ss_n);

    u_spi1 : entity work.spi_master
        port map (clk=>clk, rst=>reset, sel=>sel_spi1, we=>c_we, reg=>regw,
                  wdata=>c_wdata, rdata=>spi1_rd,
                  sclk=>spi1_sclk, mosi=>spi1_mosi, miso=>spi1_miso, ss_n=>spi1_ss_n);

    u_i2c0 : entity work.i2c_master
        port map (clk=>clk, rst=>reset, sel=>sel_i2c0, we=>c_we, reg=>regw,
                  wdata=>c_wdata, rdata=>i2c0_rd,
                  scl_in=>i2c0_scl_in, scl_oe=>i2c0_scl_oe,
                  sda_in=>i2c0_sda_in, sda_oe=>i2c0_sda_oe);

    u_i2c1 : entity work.i2c_master
        port map (clk=>clk, rst=>reset, sel=>sel_i2c1, we=>c_we, reg=>regw,
                  wdata=>c_wdata, rdata=>i2c1_rd,
                  scl_in=>i2c1_scl_in, scl_oe=>i2c1_scl_oe,
                  sda_in=>i2c1_sda_in, sda_oe=>i2c1_sda_oe);

    u_uart : entity work.uart_lite
        port map (clk=>clk, rst=>reset, sel=>sel_uart, we=>c_we, re=>c_re, reg=>regw,
                  wdata=>c_wdata, rdata=>uart_rd, tx=>uart_tx, rx=>uart_rx);

    u_pwm : entity work.pwm_gen
        generic map (NCH=>4, CW=>24)
        port map (clk=>clk, rst=>reset, sel=>sel_pwm, we=>c_we, reg=>regw,
                  wdata=>c_wdata, rdata=>pwm_rd, pwm_o=>pwm_o);

    -- NPU accelerator (uncached, single-cycle MMIO slave @ 0x3000_0000)
    -- 16x16 hybrid array (220 DSP48E1 + 36 LUT MAC), 16 KiB window -> addr[13:0].
    u_npu : entity work.npu_top16
        port map (clk=>clk, rst=>reset, sel=>is_npu, we=>c_we,
                  addr=>c_addr(13 downto 0), wdata=>c_wdata, wstrb=>c_wstrb,
                  re=>c_re, rdata=>npu_rd, rd_valid=>npu_rd_valid,
                  -- shared-PE lane bus (GPU borrows 8 row-0 DSPs)
                  gpu_mode=>u_gpu_mode, g_a_flat=>u_g_a, g_b_flat=>u_g_b,
                  g_c_flat=>u_g_c, g_y_flat=>u_g_y);

    -- GPU SIMT-lite coprocessor (uncached, single-cycle slave @ 0x4000_0000)
    -- 8-lane vector engine; 64 KiB window -> addr[15:0]. VMUL/VMAC execute on 8
    -- SHARED NPU DSPs (unified fabric) so the GPU adds 0 DSP -> full 16x16 NPU fits.
    u_gpu : entity work.gpu_top
        port map (clk=>clk, rst=>reset, sel=>is_gpu, we=>c_we, re=>c_re,
                  addr=>c_addr(15 downto 0), wdata=>c_wdata,
                  rdata=>gpu_rd, rd_valid=>gpu_rd_valid,
                  -- shared-PE multiply bus (operands out, products in)
                  gpu_active=>u_gpu_mode, g_a_o=>u_g_a, g_b_o=>u_g_b,
                  g_c_o=>u_g_c, g_y_i=>u_g_y);

    -- NPU reads are now pipelined (3-cycle): stall the core until rd_valid.
    -- (The 256:1 accumulator read mux was split into registered stages to close
    --  timing; writes and MMIO stay single-cycle.)
    npu_stall <= is_npu and c_re and (not npu_rd_valid);

    -- back to core: MMIO single-cycle; NPU follows its read handshake; else cache
    c_rdata <= npu_rd   when is_npu  = '1' else
               gpu_rd   when is_gpu  = '1' else
               mmio_rd  when is_mmio = '1' else d_rdata;
    c_stall <= npu_stall when is_npu  = '1' else
               '0'       when is_gpu  = '1' else
               '0'       when is_mmio = '1' else d_stall;
end Behavioral;
