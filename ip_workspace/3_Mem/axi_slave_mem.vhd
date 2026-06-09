-- =====================================================================
-- axi_slave_mem.vhd  -  Behavioral AXI4 slave memory (SIMULATION ONLY)
-- Matches axi_master.vhd: 4-beat INCR bursts, 32-bit beats, 128-bit lines.
-- Handles read (AR/R) and write (AW/W/B). A preload write port (prog_*)
-- loads a program/data image; preload is INDEPENDENT of reset (single
-- clocked process, synchronous FSM reset) so the image can be written while
-- the core is held in reset. NOT synthesizable / not for IP packaging.
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi_slave_mem is
    Generic ( WORDS : integer := 4096 );
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        prog_we   : in  std_logic;
        prog_addr : in  std_logic_vector(31 downto 0);
        prog_data : in  std_logic_vector(31 downto 0);
        ARADDR   : in  std_logic_vector(31 downto 0);
        ARVALID  : in  std_logic;
        ARREADY  : out std_logic;
        RDATA    : out std_logic_vector(31 downto 0);
        RLAST    : out std_logic;
        RVALID   : out std_logic;
        RREADY   : in  std_logic;
        AWADDR   : in  std_logic_vector(31 downto 0);
        AWVALID  : in  std_logic;
        AWREADY  : out std_logic;
        WDATA    : in  std_logic_vector(31 downto 0);
        WSTRB    : in  std_logic_vector(3 downto 0);
        WLAST    : in  std_logic;
        WVALID   : in  std_logic;
        WREADY   : out std_logic;
        BVALID   : out std_logic;
        BREADY   : in  std_logic
    );
end axi_slave_mem;

architecture Behavioral of axi_slave_mem is
    type mem_t is array (0 to WORDS-1) of std_logic_vector(31 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    type rst_t is (R_IDLE, R_DATA);
    type wst_t is (W_IDLE, W_DATA, W_RESP);
    signal rst : rst_t := R_IDLE;
    signal wst : wst_t := W_IDLE;
    signal rbase, wbase : integer := 0;
    signal rbeat, wbeat : integer range 0 to 3 := 0;
begin
    ARREADY <= '1' when rst = R_IDLE else '0';
    RVALID  <= '1' when rst = R_DATA else '0';
    RLAST   <= '1' when (rst = R_DATA and rbeat = 3) else '0';
    RDATA   <= mem((rbase + rbeat) mod WORDS) when rst = R_DATA else (others => '0');
    AWREADY <= '1' when wst = W_IDLE else '0';
    WREADY  <= '1' when wst = W_DATA else '0';
    BVALID  <= '1' when wst = W_RESP else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            -- preload (independent of reset; one word per cycle)
            if prog_we = '1' then
                mem(to_integer(unsigned(prog_addr(31 downto 2))) mod WORDS) <= prog_data;
            end if;

            if reset = '1' then
                rst <= R_IDLE; wst <= W_IDLE; rbeat <= 0; wbeat <= 0;
            else
                -- read FSM
                case rst is
                    when R_IDLE =>
                        if ARVALID = '1' then
                            rbase <= to_integer(unsigned(ARADDR(31 downto 2)));
                            rbeat <= 0; rst <= R_DATA;
                        end if;
                    when R_DATA =>
                        if RREADY = '1' then
                            if rbeat = 3 then rst <= R_IDLE; else rbeat <= rbeat + 1; end if;
                        end if;
                end case;

                -- write FSM
                case wst is
                    when W_IDLE =>
                        if AWVALID = '1' then
                            wbase <= to_integer(unsigned(AWADDR(31 downto 2)));
                            wbeat <= 0; wst <= W_DATA;
                        end if;
                    when W_DATA =>
                        if WVALID = '1' then
                            for k in 0 to 3 loop
                                if WSTRB(k) = '1' then
                                    mem((wbase + wbeat) mod WORDS)(8*k+7 downto 8*k)
                                        <= WDATA(8*k+7 downto 8*k);
                                end if;
                            end loop;
                            if WLAST = '1' then wst <= W_RESP; else wbeat <= wbeat + 1; end if;
                        end if;
                    when W_RESP =>
                        if BREADY = '1' then wst <= W_IDLE; end if;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
