-- =====================================================================
-- i2c_master.vhd  -  MMIO I2C master controller (open-drain, clock-stretch aware)
--
-- Single-clock memory-mapped peripheral driven by the RV32 core via mmio_bridge.
-- The controller speaks I2C one *command* at a time; each command is atomic and
-- guarded by STATUS.busy. SDA/SCL are open-drain: the module emits *_oe outputs
-- ('1' = pull the line low, '0' = release to the external pull-up) and reads the
-- live line back through *_in. The platform top instantiates the tri-state pads.
--
-- Register block (word offsets, reg = addr[4:2]):
--   0x0 CMD    (W) b0 START  b1 STOP  b2 WRITE  b3 READ  b4 ACK(0=ack,1=nack after READ)
--                  combos allowed: START|WRITE (send addr), READ|STOP, etc.
--   0x4 STATUS (R) b0 BUSY   b1 RXACK(ack bit from slave on last WRITE; 0=ACK)
--   0x8 DIV    (RW) prescale; SCL period = 4*(DIV+1) clk; reset = DIV_DEFAULT
--   0xC TX     (W) byte to transmit (address+R/W or data)   (R: last byte)
--   0x10 RX    (R) byte received by the last READ
--
-- Bit timing: 4 phase ticks per SCL period. SCL-high phase waits for the line to
-- actually rise (clock stretching). A new command only starts on (we & !busy).
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2c_master is
    generic ( DIV_DEFAULT : integer := 124 );     -- ~100 kHz SCL @ 50 MHz (4*(124+1)=500)
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        -- MMIO register bus
        sel    : in  std_logic;
        we     : in  std_logic;
        reg    : in  std_logic_vector(2 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        -- open-drain line control (tri-state pads live in the platform top)
        scl_in : in  std_logic;
        scl_oe : out std_logic;                    -- '1' => drive SCL low
        sda_in : in  std_logic;
        sda_oe : out std_logic                     -- '1' => drive SDA low
    );
end i2c_master;

architecture rtl of i2c_master is
    type state_t is (S_IDLE, S_STA, S_TX, S_TXACK, S_RX, S_RXACK, S_STO, S_FIN);
    signal st : state_t := S_IDLE;

    signal div_reg : unsigned(15 downto 0) := to_unsigned(DIV_DEFAULT,16);
    signal divcnt  : unsigned(15 downto 0) := (others=>'0');
    signal tick    : std_logic;
    signal ph      : integer range 0 to 3 := 0;
    signal bcnt    : integer range 0 to 7 := 0;

    signal c_sta, c_sto, c_wr, c_rd, c_ack : std_logic := '0';
    signal started : std_logic := '0';            -- inside a transaction (after START)

    signal tx_reg, rx_sh, shift : std_logic_vector(7 downto 0) := (others=>'0');
    signal rxack, busy : std_logic := '0';
    signal scl_d, sda_d : std_logic := '0';        -- open-drain enables (registered)

    -- input synchronizers
    signal scl_m, scl_s, sda_m, sda_s : std_logic := '1';
begin
    scl_oe <= scl_d;
    sda_oe <= sda_d;
    tick   <= '1' when divcnt = 0 else '0';

    with reg select rdata <=
        (others=>'0')                              when "000",   -- CMD (wo)
        (0=>busy, 1=>rxack, others=>'0')           when "001",   -- STATUS
        std_logic_vector(resize(div_reg,32))       when "010",   -- DIV
        std_logic_vector(resize(unsigned(tx_reg),32)) when "011",-- TX
        std_logic_vector(resize(unsigned(rx_sh),32))  when "100",-- RX
        (others=>'0')                              when others;

    process(clk)
        -- advance/load the next command stage after START/byte/stop completes
        procedure go_next is
        begin
            if    c_wr='1' and (st=S_STA)               then shift<=tx_reg; bcnt<=0; ph<=0; st<=S_TX;
            elsif c_rd='1' and (st=S_STA)               then bcnt<=0; ph<=0; st<=S_RX;
            elsif c_sto='1' and (st=S_STA or st=S_TXACK or st=S_RXACK) then ph<=0; st<=S_STO;
            else  busy<='0'; st<=S_FIN;
            end if;
        end procedure;
    begin
        if rising_edge(clk) then
            -- synchronizers
            scl_m<=scl_in; scl_s<=scl_m;
            sda_m<=sda_in; sda_s<=sda_m;

            if rst='1' then
                st<=S_IDLE; div_reg<=to_unsigned(DIV_DEFAULT,16); divcnt<=(others=>'0');
                ph<=0; bcnt<=0; c_sta<='0'; c_sto<='0'; c_wr<='0'; c_rd<='0'; c_ack<='0';
                started<='0'; tx_reg<=(others=>'0'); rx_sh<=(others=>'0'); shift<=(others=>'0');
                rxack<='0'; busy<='0'; scl_d<='0'; sda_d<='0';
            else
                -- prescale counter
                if divcnt = 0 then divcnt <= div_reg; else divcnt <= divcnt - 1; end if;

                -- ---------- bit-level engine (advances on tick) ----------
                if tick='1' then
                  case st is
                    -- ----- START / repeated-START -----
                    when S_STA =>
                        case ph is
                            when 0 => sda_d<='0';                       -- release SDA (high)
                                      if started='0' then scl_d<='0'; else scl_d<='1'; end if;
                                      ph<=1;
                            when 1 => scl_d<='0'; ph<=2;                -- release SCL (high)
                            when 2 => if scl_s='1' then sda_d<='1'; ph<=3; end if;  -- SDA low (START)
                            when others => scl_d<='1'; started<='1'; go_next;       -- SCL low
                        end case;

                    -- ----- transmit 8 data bits -----
                    when S_TX =>
                        case ph is
                            when 0 => scl_d<='1'; sda_d<= not shift(7); ph<=1;   -- SCL low, drive MSB
                            when 1 => scl_d<='0'; ph<=2;     -- release SCL high (then wait/sample)
                            when 2 => if scl_s='1' then ph<=3; end if;           -- SCL high (slave samples)
                            when others =>
                                scl_d<='1';                                      -- SCL low
                                shift<=shift(6 downto 0) & '0';
                                if bcnt=7 then ph<=0; st<=S_TXACK;
                                else bcnt<=bcnt+1; ph<=0; end if;
                        end case;

                    -- ----- receive ACK from slave -----
                    when S_TXACK =>
                        case ph is
                            when 0 => scl_d<='1'; sda_d<='0'; ph<=1;             -- release SDA for ack
                            when 1 => scl_d<='0'; ph<=2;     -- release SCL high (then wait/sample)
                            when 2 => if scl_s='1' then rxack<=sda_s; ph<=3; end if;
                            when others => scl_d<='1'; go_next;
                        end case;

                    -- ----- receive 8 data bits -----
                    when S_RX =>
                        case ph is
                            when 0 => scl_d<='1'; sda_d<='0'; ph<=1;             -- SCL low, release SDA
                            when 1 => scl_d<='0'; ph<=2;     -- release SCL high (then wait/sample)
                            when 2 => if scl_s='1' then rx_sh<=rx_sh(6 downto 0)&sda_s; ph<=3; end if;
                            when others =>
                                scl_d<='1';
                                if bcnt=7 then ph<=0; st<=S_RXACK;
                                else bcnt<=bcnt+1; ph<=0; end if;
                        end case;

                    -- ----- send ACK/NACK to slave -----
                    when S_RXACK =>
                        case ph is
                            when 0 => scl_d<='1'; sda_d<= not c_ack; ph<=1;      -- ack=0 => drive low
                            when 1 => scl_d<='0'; ph<=2;     -- release SCL high (then wait/sample)
                            when 2 => if scl_s='1' then ph<=3; end if;
                            when others => scl_d<='1'; go_next;
                        end case;

                    -- ----- STOP -----
                    when S_STO =>
                        case ph is
                            when 0 => scl_d<='1'; sda_d<='1'; ph<=1;             -- SCL low, SDA low
                            when 1 => scl_d<='0'; ph<=2;                         -- SCL high
                            when 2 => if scl_s='1' then sda_d<='0'; ph<=3; end if; -- SDA high (STOP)
                            when others => started<='0'; busy<='0'; st<=S_FIN;
                        end case;

                    when others => busy<='0'; st<=S_IDLE;                        -- S_FIN/S_IDLE
                  end case;
                end if;

                -- ---------- register writes (placed after the engine so a launch
                --            issued on the same cycle as a tick always wins) ----------
                if (sel='1' and we='1') then
                    case reg is
                        when "010" => div_reg <= unsigned(wdata(15 downto 0));
                        when "011" => tx_reg  <= wdata(7 downto 0);
                        when "000" =>                          -- CMD -> launch if idle
                            if busy='0' then
                                c_sta<=wdata(0); c_sto<=wdata(1);
                                c_wr <=wdata(2); c_rd <=wdata(3); c_ack<=wdata(4);
                                busy<='1'; ph<=0; bcnt<=0; divcnt<=div_reg;
                                if    wdata(0)='1' then st<=S_STA;
                                elsif wdata(2)='1' then shift<=tx_reg; st<=S_TX;
                                elsif wdata(3)='1' then st<=S_RX;
                                elsif wdata(1)='1' then st<=S_STO;
                                else  busy<='0'; st<=S_FIN; end if;
                            end if;
                        when others => null;
                    end case;
                end if;

                if st=S_FIN then st<=S_IDLE; end if;
            end if;
        end if;
    end process;
end rtl;
