-- =====================================================================
-- mmio_bridge.vhd  -  data-bus splitter: cached RAM vs uncached MMIO
-- Sits between rv32_core's data port and the D-cache. Addresses in the MMIO
-- region (0x1xxx_xxxx) bypass the cache and hit memory-mapped peripherals
-- (single cycle, no stall); everything else goes to the D-cache unchanged.
--   0x1000_0000  W  LED   (low LED_W bits drive board LEDs; also read-back)
--   0x1000_0004  R  SW    (board switches, zero-extended)
--   0x1000_0008  R  BTN   (board buttons, zero-extended)
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mmio_bridge is
    Generic ( LED_W : integer := 4; SW_W : integer := 4; BTN_W : integer := 4 );
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
        -- board GPIO
        led_o   : out std_logic_vector(LED_W-1 downto 0);
        sw_i    : in  std_logic_vector(SW_W-1 downto 0);
        btn_i   : in  std_logic_vector(BTN_W-1 downto 0)
    );
end mmio_bridge;

architecture Behavioral of mmio_bridge is
    signal is_mmio   : std_logic;
    signal led_reg   : std_logic_vector(LED_W-1 downto 0) := (others => '0');
    signal mmio_rd   : std_logic_vector(31 downto 0);
begin
    -- MMIO region = 0x1xxx_xxxx
    is_mmio <= '1' when c_addr(31 downto 28) = x"1" else '0';

    -- to D-cache: addr/wdata/wstrb pass through; only enable on non-MMIO access
    d_addr  <= c_addr;
    d_wdata <= c_wdata;
    d_wstrb <= c_wstrb;
    d_we    <= c_we and not is_mmio;
    d_re    <= c_re and not is_mmio;

    -- MMIO read mux (by word offset)
    with c_addr(7 downto 0) select mmio_rd <=
        std_logic_vector(resize(unsigned(led_reg), 32)) when x"00",
        std_logic_vector(resize(unsigned(sw_i),    32)) when x"04",
        std_logic_vector(resize(unsigned(btn_i),   32)) when x"08",
        (others => '0')                                 when others;

    -- LED output register (written by a store to 0x1000_0000)
    process(clk, reset)
    begin
        if reset = '1' then
            led_reg <= (others => '0');
        elsif rising_edge(clk) then
            if (is_mmio = '1' and c_we = '1' and c_addr(7 downto 0) = x"00") then
                led_reg <= c_wdata(LED_W-1 downto 0);
            end if;
        end if;
    end process;
    led_o <= led_reg;

    -- back to core: MMIO is single-cycle (no stall); else follow the cache
    c_rdata <= mmio_rd  when is_mmio = '1' else d_rdata;
    c_stall <= '0'      when is_mmio = '1' else d_stall;
end Behavioral;
