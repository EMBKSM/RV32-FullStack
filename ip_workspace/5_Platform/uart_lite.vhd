-- =====================================================================
-- uart_lite.vhd  -  MMIO UART (8-N-1, polled) for a Pmod serial port
--
-- Independent of the PS console UART; this is a PL UART the RV32 program drives
-- directly. TX: write a byte, poll STATUS.tx_busy. RX: poll STATUS.rx_valid,
-- read RX (a read clears rx_valid). BAUD = clk / DIV.
--
-- Register block (word offsets, reg = addr[4:2]):
--   0x0 DIV    (RW) baud divisor = clk/baud; reset = DIV_DEFAULT
--   0x4 STATUS (R)  b0 TX_BUSY  b1 RX_VALID  b2 RX_OVERRUN  b3 TX_READY(!busy)
--   0x8 TX     (W)  write byte -> transmit (ignored while TX_BUSY)
--   0xC RX     (R)  received byte; the read clears RX_VALID/OVERRUN
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_lite is
    generic ( DIV_DEFAULT : integer := 434 );      -- 115200 baud @ 50 MHz
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        sel    : in  std_logic;
        we     : in  std_logic;
        re     : in  std_logic;
        reg    : in  std_logic_vector(2 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        tx     : out std_logic;
        rx     : in  std_logic
    );
end uart_lite;

architecture rtl of uart_lite is
    signal div_reg : unsigned(15 downto 0) := to_unsigned(DIV_DEFAULT,16);
    -- transmit
    signal tx_sh   : std_logic_vector(9 downto 0) := (others=>'1');
    signal tx_cnt  : unsigned(15 downto 0) := (others=>'0');
    signal tx_bits : integer range 0 to 10 := 0;
    signal tx_busy : std_logic := '0';
    -- receive
    signal rx_m, rx_s, rx_s2 : std_logic := '1';
    signal rx_cnt  : unsigned(15 downto 0) := (others=>'0');
    signal rx_bits : integer range 0 to 9 := 0;
    signal rx_sh   : std_logic_vector(7 downto 0) := (others=>'0');
    signal rx_data : std_logic_vector(7 downto 0) := (others=>'0');
    signal rx_busy, rx_valid, rx_ovr : std_logic := '0';
begin
    tx <= tx_sh(0);

    with reg select rdata <=
        std_logic_vector(resize(div_reg,32))                      when "000",
        (0=>tx_busy,1=>rx_valid,2=>rx_ovr,3=>not tx_busy, others=>'0') when "001",
        (others=>'0')                                             when "010",
        std_logic_vector(resize(unsigned(rx_data),32))            when "011",
        (others=>'0')                                             when others;

    process(clk)
    begin
        if rising_edge(clk) then
            rx_m <= rx;  rx_s <= rx_m;  rx_s2 <= rx_s;     -- sync + delayed copy for edge detect

            if rst='1' then
                div_reg<=to_unsigned(DIV_DEFAULT,16);
                tx_sh<=(others=>'1'); tx_cnt<=(others=>'0'); tx_bits<=0; tx_busy<='0';
                rx_cnt<=(others=>'0'); rx_bits<=0; rx_sh<=(others=>'0'); rx_data<=(others=>'0');
                rx_busy<='0'; rx_valid<='0'; rx_ovr<='0';
            else
                -- ---------- register access ----------
                if (sel='1' and we='1') then
                    case reg is
                        when "000" => div_reg <= unsigned(wdata(15 downto 0));
                        when "010" =>                          -- TX -> start frame
                            if tx_busy='0' then
                                tx_sh   <= '1' & wdata(7 downto 0) & '0';  -- stop,data,start
                                tx_bits <= 10;
                                tx_cnt  <= div_reg - 1;
                                tx_busy <= '1';
                            end if;
                        when others => null;
                    end case;
                end if;
                if (sel='1' and re='1' and reg="011") then     -- RX read clears flags
                    rx_valid <= '0';  rx_ovr <= '0';
                end if;

                -- ---------- transmitter ----------
                if tx_busy='1' then
                    if tx_cnt = 0 then
                        tx_cnt <= div_reg - 1;
                        tx_sh  <= '1' & tx_sh(9 downto 1);     -- shift right, idle-fill '1'
                        if tx_bits = 1 then tx_busy<='0'; tx_bits<=0;
                        else tx_bits <= tx_bits - 1; end if;
                    else
                        tx_cnt <= tx_cnt - 1;
                    end if;
                end if;

                -- ---------- receiver ----------
                if rx_busy='0' then
                    if (rx_s2='1' and rx_s='0') then            -- start-bit falling edge
                        rx_busy <= '1';
                        rx_bits <= 0;
                        rx_cnt  <= ('0' & div_reg(15 downto 1));-- half bit -> sample mid start
                    end if;
                else
                    if rx_cnt = 0 then
                        rx_cnt <= div_reg - 1;
                        if rx_bits = 0 then                     -- mid start bit
                            if rx_s='1' then rx_busy<='0';      -- false start, abort
                            else rx_bits <= 1; end if;
                        elsif rx_bits <= 8 then                 -- data bits 1..8 (LSB first)
                            rx_sh <= rx_s & rx_sh(7 downto 1);
                            rx_bits <= rx_bits + 1;
                        else                                    -- stop bit
                            rx_busy <= '0';
                            if rx_s='1' then                    -- valid stop
                                rx_data <= rx_sh;
                                if rx_valid='1' then rx_ovr<='1'; end if;
                                rx_valid <= '1';
                            end if;
                        end if;
                    else
                        rx_cnt <= rx_cnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end rtl;
