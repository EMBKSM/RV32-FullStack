-- =====================================================================
-- spi_master.vhd  -  MMIO SPI master controller (full-duplex, 8-bit, modes 0-3)
--
-- Single-clock (S_AXI_ACLK / FCLK) memory-mapped peripheral driven by the RV32
-- core through mmio_bridge. The CPU writes a byte to TX (which launches a
-- transfer), polls STATUS.busy, then reads RX. Slave-select can be automatic
-- (asserted for the duration of one byte) or held manually for multi-byte
-- bursts. SCLK = clk / (2*(DIV+1)).
--
-- Register block (word offsets, reg = addr[4:2]):
--   0x0 CTRL   (RW) b0 CPOL  b1 CPHA  b2 SS_MANUAL  b3 SS_LEVEL(manual,0=asserted)
--   0x4 STATUS (R)  b0 BUSY  b1 DONE(set at end of xfer, cleared by next TX write)
--   0x8 DIV    (RW) clock divider, SCLK = clk/(2*(DIV+1)); reset = DIV_DEFAULT
--   0xC TX     (W)  write data[7:0] -> start a transfer   (R: last byte written)
--   0x10 RX    (R)  received byte from the last transfer
--
-- Multi-cycle write-enable is safe: a new transfer only starts on (we & !busy).
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_master is
    generic ( DIV_DEFAULT : integer := 24 );      -- ~1 MHz SCLK @ 50 MHz
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;                   -- active high
        -- MMIO register bus (from mmio_bridge)
        sel    : in  std_logic;                   -- this peripheral selected
        we     : in  std_logic;                   -- write strobe (qualified by sel upstream)
        reg    : in  std_logic_vector(2 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        -- SPI pins
        sclk   : out std_logic;
        mosi   : out std_logic;
        miso   : in  std_logic;
        ss_n   : out std_logic
    );
end spi_master;

architecture rtl of spi_master is
    -- config registers
    signal cpol, cpha, ss_manual, ss_level : std_logic := '0';
    signal div_reg : unsigned(15 downto 0) := to_unsigned(DIV_DEFAULT,16);
    signal tx_reg  : std_logic_vector(7 downto 0) := (others=>'0');
    signal rx_reg  : std_logic_vector(7 downto 0) := (others=>'0');
    -- engine
    signal busy, done, half : std_logic := '0';
    signal sck_i, ss_auto_n : std_logic := '1';
    signal idx     : integer range 0 to 7 := 7;
    signal bitcnt  : integer range 0 to 8 := 0;
    signal divcnt  : unsigned(15 downto 0) := (others=>'0');
    signal shreg   : std_logic_vector(7 downto 0) := (others=>'0');
    -- input synchronizer
    signal miso_m, miso_s : std_logic := '0';

    function w2reg(s : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin return std_logic_vector(resize(unsigned(s),32)); end function;
begin
    -- ss_auto_n starts high (deasserted)
    sclk <= sck_i;
    mosi <= shreg(idx);
    ss_n <= ss_level when ss_manual='1' else ss_auto_n;

    -- combinational read mux
    with reg select rdata <=
        (0=>cpol,1=>cpha,2=>ss_manual,3=>ss_level, others=>'0') when "000", -- CTRL
        (0=>busy,1=>done,            others=>'0')               when "001", -- STATUS
        std_logic_vector(resize(div_reg,32))                    when "010", -- DIV
        w2reg(tx_reg)                                           when "011", -- TX
        w2reg(rx_reg)                                           when "100", -- RX
        (others=>'0')                                           when others;

    process(clk)
    begin
        if rising_edge(clk) then
            -- 2-FF synchronizer on MISO
            miso_m <= miso;  miso_s <= miso_m;

            if rst='1' then
                cpol<='0'; cpha<='0'; ss_manual<='0'; ss_level<='0';
                div_reg <= to_unsigned(DIV_DEFAULT,16);
                busy<='0'; done<='0'; half<='0'; sck_i<='0'; ss_auto_n<='1';
                idx<=7; bitcnt<=0; divcnt<=(others=>'0');
                tx_reg<=(others=>'0'); rx_reg<=(others=>'0'); shreg<=(others=>'0');
            else
                -- ---------- register writes ----------
                if (sel='1' and we='1') then
                    case reg is
                        when "000" =>                      -- CTRL
                            cpol<=wdata(0); cpha<=wdata(1);
                            ss_manual<=wdata(2); ss_level<=wdata(3);
                        when "010" =>                      -- DIV
                            div_reg <= unsigned(wdata(15 downto 0));
                        when "011" =>                      -- TX -> start if idle
                            tx_reg <= wdata(7 downto 0);
                            if busy='0' then
                                shreg  <= wdata(7 downto 0);
                                idx    <= 7;
                                bitcnt <= 8;
                                busy   <= '1';
                                done   <= '0';
                                half   <= '0';
                                sck_i  <= cpol;            -- idle level before 1st edge
                                ss_auto_n <= '0';          -- assert SS (auto mode)
                                divcnt <= div_reg;
                            end if;
                        when others => null;
                    end case;
                end if;

                -- ---------- transfer engine ----------
                if busy='1' then
                    if divcnt = 0 then
                        divcnt <= div_reg;
                        if half='0' then
                            -- LEADING edge
                            sck_i <= not cpol;
                            if cpha='0' then rx_reg(idx) <= miso_s; end if; -- sample
                            half <= '1';
                        else
                            -- TRAILING edge
                            sck_i <= cpol;
                            if cpha='1' then rx_reg(idx) <= miso_s; end if; -- sample
                            if bitcnt = 1 then
                                busy <= '0';
                                done <= '1';
                                ss_auto_n <= '1';          -- release SS (auto mode)
                            else
                                idx <= idx - 1;
                            end if;
                            bitcnt <= bitcnt - 1;
                            half <= '0';
                        end if;
                    else
                        divcnt <= divcnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end rtl;
