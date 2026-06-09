-- =====================================================================
-- icache_unit.vhd  -  Read-only instruction cache (IF-line blocks)
-- Rebuilds the I-cache from the originally-unused IF address-split blocks so
-- the whole design is exercised:
--   addr_aligner  : split fetch address -> tag / idx / offset
--   tag_array     : 256-entry tag+valid store (with single-cycle invalidate)
--   comparator    : hit = valid AND (addr_tag == cache_tag)
--   cache_controller : miss FSM (stall pipeline, request refill, wake)
--   icache_data_array : 256x128b line store (read 1 word / fill whole line)  [new]
--   icache_axi_adapter: simple handshake <-> 4-beat AXI4 read burst          [new]
-- Direct-mapped, 16-byte (4-word) lines, write-allocate-on-fetch, read-only.
-- AXI master side connects to the behavioral axi_slave_mem (same ports it uses
-- for the D-cache memory). FENCE.I / external-invalidate inputs are wired out
-- (tied off by the SoC for now).
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity icache_unit is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        -- core (fetch) side
        addr     : in  std_logic_vector(31 downto 0);   -- PC / fetch address
        rword    : out std_logic_vector(31 downto 0);   -- instruction word
        stall    : out std_logic;                        -- miss -> freeze pipeline
        fence_i  : in  std_logic;                        -- FENCE.I invalidate (pulse)
        ext_inv  : in  std_logic;                        -- host code-load invalidate
        iflush   : out std_logic;                        -- pipeline flush on FENCE.I
        -- AXI4 read master (to axi_slave_mem; write channel tied off: read-only)
        ARADDR   : out std_logic_vector(31 downto 0);
        ARVALID  : out std_logic;
        ARREADY  : in  std_logic;
        RDATA    : in  std_logic_vector(31 downto 0);
        RLAST    : in  std_logic;
        RVALID   : in  std_logic;
        RREADY   : out std_logic;
        AWADDR   : out std_logic_vector(31 downto 0);
        AWVALID  : out std_logic;
        AWREADY  : in  std_logic;
        WDATA    : out std_logic_vector(31 downto 0);
        WSTRB    : out std_logic_vector(3 downto 0);
        WLAST    : out std_logic;
        WVALID   : out std_logic;
        WREADY   : in  std_logic;
        BVALID   : in  std_logic;
        BREADY   : out std_logic
    );
end icache_unit;

architecture Behavioral of icache_unit is
    signal a_tag      : std_logic_vector(19 downto 0);
    signal a_idx      : std_logic_vector(7 downto 0);
    signal a_offset   : std_logic_vector(3 downto 0);
    signal c_tag      : std_logic_vector(19 downto 0);
    signal c_valid    : std_logic;
    signal hit, miss  : std_logic;
    signal cc_we, cc_inv, cc_wake : std_logic;
    signal cc_arvalid, cc_rready  : std_logic;
    signal adp_arready, adp_rvalid : std_logic;
    signal fill_line  : std_logic_vector(127 downto 0);
begin
    -- read-only: tie off the AXI write channel
    AWADDR <= (others => '0'); AWVALID <= '0';
    WDATA  <= (others => '0'); WSTRB <= "0000"; WLAST <= '0'; WVALID <= '0';
    BREADY <= '1';

    -- address split
    u_align : entity work.addr_aligner
        port map (address => addr, tag => a_tag, idx => a_idx, offset => a_offset);

    -- tag/valid store
    u_tag : entity work.tag_array
        port map (clk => clk, reset => reset, we => cc_we, inv => cc_inv,
                  idx => a_idx, tag_in => a_tag, tag_out => c_tag, valid_out => c_valid);

    -- hit detect
    u_cmp : entity work.comparator
        port map (addr_tag => a_tag, cache_tag => c_tag, valid_bit => c_valid, hit => hit);

    -- instruction fetch is a continuous access -> a non-hit is a miss
    miss <= not hit;

    -- miss FSM
    u_ctrl : entity work.cache_controller
        port map (clk => clk, reset => reset,
                  miss => miss, fence_i => fence_i, ext_inv => ext_inv,
                  stall => stall, wake_up => cc_wake, we => cc_we, inv => cc_inv,
                  iflush => iflush,
                  arready => adp_arready, rvalid => adp_rvalid,
                  arvalid => cc_arvalid, rready => cc_rready);

    -- line store: read selected word; whole-line fill on the controller's we pulse
    u_data : entity work.icache_data_array
        port map (clk => clk, idx => a_idx, word_off => a_offset(3 downto 2),
                  line_fill => cc_we, fill_line => fill_line, word_out => rword);

    -- AXI burst adapter
    u_adp : entity work.icache_axi_adapter
        port map (clk => clk, reset => reset,
                  c_arvalid => cc_arvalid, c_arready => adp_arready, c_rvalid => adp_rvalid,
                  line_addr => addr, rd_line => fill_line,
                  ARADDR => ARADDR, ARVALID => ARVALID, ARREADY => ARREADY,
                  RDATA => RDATA, RLAST => RLAST, RVALID => RVALID, RREADY => RREADY);
end Behavioral;
