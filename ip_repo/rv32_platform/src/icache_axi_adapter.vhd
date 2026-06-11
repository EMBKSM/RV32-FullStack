-- =====================================================================
-- icache_axi_adapter.vhd  -  bridge cache_controller <-> AXI4 read burst
-- The IF-line cache_controller speaks a SIMPLE handshake (one arvalid/arready
-- then one rvalid pulse to commit the refill).  The behavioral memory
-- (axi_slave_mem) speaks AXI4: a 4-beat INCR read burst (RLAST on beat 3).
-- This adapter accepts the controller's single request, runs the 4-beat
-- burst against the memory, assembles the 128-bit line, and raises a single
-- rvalid (holding the assembled line) so the controller's one 'we' pulse
-- writes the whole line.  Read-only: the AXI write channel is tied off.
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity icache_axi_adapter is
    Port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        -- cache_controller side (simple handshake)
        c_arvalid  : in  std_logic;
        c_arready  : out std_logic;
        c_rvalid   : out std_logic;   -- 1-cycle "line ready" pulse
        -- refill address (line base derived inside); held by the core during stall
        line_addr  : in  std_logic_vector(31 downto 0);
        rd_line    : out std_logic_vector(127 downto 0);
        -- AXI4 read master (to axi_slave_mem)
        ARADDR     : out std_logic_vector(31 downto 0);
        ARVALID    : out std_logic;
        ARREADY    : in  std_logic;
        RDATA      : in  std_logic_vector(31 downto 0);
        RLAST      : in  std_logic;
        RVALID     : in  std_logic;
        RREADY     : out std_logic
    );
end icache_axi_adapter;

architecture Behavioral of icache_axi_adapter is
    type st_t is (ADP_IDLE, ADP_AR, ADP_R, ADP_DONE);
    signal st       : st_t := ADP_IDLE;
    signal beat     : integer range 0 to 3 := 0;
    signal buf      : std_logic_vector(127 downto 0) := (others => '0');
    signal araddr_q : std_logic_vector(31 downto 0) := (others => '0');
begin
    ARADDR  <= araddr_q;
    rd_line <= buf;

    -- combinational handshake outputs
    c_arready <= '1' when (st = ADP_IDLE and c_arvalid = '1') else '0';
    c_rvalid  <= '1' when (st = ADP_DONE) else '0';
    ARVALID   <= '1' when (st = ADP_AR) else '0';
    RREADY    <= '1' when (st = ADP_R) else '0';

    process(clk, reset)
    begin
        if reset = '1' then
            st <= ADP_IDLE; beat <= 0; buf <= (others => '0');
            araddr_q <= (others => '0');
        elsif rising_edge(clk) then
            case st is
                when ADP_IDLE =>
                    if c_arvalid = '1' then
                        araddr_q <= line_addr(31 downto 4) & "0000";  -- 16-byte aligned
                        beat <= 0;
                        st   <= ADP_AR;
                    end if;
                when ADP_AR =>
                    if ARREADY = '1' then
                        st <= ADP_R;
                    end if;
                when ADP_R =>
                    if RVALID = '1' then
                        case beat is
                            when 0 => buf(31 downto 0)    <= RDATA;
                            when 1 => buf(63 downto 32)   <= RDATA;
                            when 2 => buf(95 downto 64)   <= RDATA;
                            when others => buf(127 downto 96) <= RDATA;
                        end case;
                        if RLAST = '1' then
                            st <= ADP_DONE;
                        else
                            beat <= beat + 1;
                        end if;
                    end if;
                when ADP_DONE =>
                    st <= ADP_IDLE;
            end case;
        end if;
    end process;
end Behavioral;
