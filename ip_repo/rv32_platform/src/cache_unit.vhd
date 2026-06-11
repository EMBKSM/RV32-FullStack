-- =====================================================================
-- cache_unit.vhd  -  Direct-mapped cache wrapper (reuses verified blocks)
-- Wires dtag_array + ddata_array + dcache_controller + axi_master into a
-- single cache that the SoC instantiates twice:
--   * D-cache : load/store, write-back/write-allocate (we may be 1).
--   * I-cache : read-only instruction fetch (tie we='0' -> never dirty,
--               controller only ever takes the ALLOCATE/REFILL path).
-- Core side presents a word interface (req/we/addr/wdata/wstrb -> rword)
-- and a stall; sub-word align is done in the core (read_aligner/wsg).
-- AXI master side connects to a behavioral AXI memory (axi_slave_mem).
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cache_unit is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        -- core side
        req      : in  std_logic;                      -- access valid this cycle
        we       : in  std_logic;                      -- 1=store, 0=load/fetch
        addr     : in  std_logic_vector(31 downto 0);
        st_data  : in  std_logic_vector(31 downto 0);  -- pre-aligned store word
        st_strb  : in  std_logic_vector(3 downto 0);   -- (VHDL is case-insensitive:
                                                       --  must differ from AXI WDATA/WSTRB)
        rword    : out std_logic_vector(31 downto 0);  -- read/instruction word
        stall    : out std_logic;
        -- AXI master (to axi_slave_mem)
        ARADDR   : out std_logic_vector(31 downto 0);
        ARLEN    : out std_logic_vector(7 downto 0);
        ARSIZE   : out std_logic_vector(2 downto 0);
        ARBURST  : out std_logic_vector(1 downto 0);
        ARVALID  : out std_logic;
        ARREADY  : in  std_logic;
        RDATA    : in  std_logic_vector(31 downto 0);
        RLAST    : in  std_logic;
        RVALID   : in  std_logic;
        RREADY   : out std_logic;
        AWADDR   : out std_logic_vector(31 downto 0);
        AWLEN    : out std_logic_vector(7 downto 0);
        AWSIZE   : out std_logic_vector(2 downto 0);
        AWBURST  : out std_logic_vector(1 downto 0);
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
end cache_unit;

architecture Behavioral of cache_unit is
    signal addr_tag           : std_logic_vector(19 downto 0);
    signal idx                : std_logic_vector(7 downto 0);
    signal word_off           : std_logic_vector(1 downto 0);
    signal tag_out            : std_logic_vector(19 downto 0);
    signal valid_out, dirty_out : std_logic;
    signal hit, mem_read, mem_write : std_logic;
    signal we_tag, we_dirty, data_we, line_fill, rd_start, wr_start, wake_up : std_logic;
    signal axi_addr           : std_logic_vector(31 downto 0);
    signal axi_done           : std_logic;
    signal fill_line, wb_line  : std_logic_vector(127 downto 0);
begin
    addr_tag  <= addr(31 downto 12);
    idx       <= addr(11 downto 4);
    word_off  <= addr(3 downto 2);

    mem_read  <= req and (not we);
    mem_write <= req and we;
    hit       <= '1' when (valid_out = '1' and tag_out = addr_tag) else '0';

    u_tag : entity work.dtag_array
        port map (clk => clk, reset => reset, idx => idx,
                  we_tag => we_tag, we_dirty => we_dirty, tag_in => addr_tag,
                  tag_out => tag_out, valid_out => valid_out, dirty_out => dirty_out);

    u_ctrl : entity work.dcache_controller
        port map (clk => clk, reset => reset,
                  mem_read => mem_read, mem_write => mem_write, hit => hit, dirty => dirty_out,
                  req_tag => addr_tag, victim_tag => tag_out, idx => idx,
                  stall => stall, wake_up => wake_up,
                  we_tag => we_tag, we_dirty => we_dirty, data_we => data_we, line_fill => line_fill,
                  rd_start => rd_start, wr_start => wr_start, axi_addr => axi_addr, axi_done => axi_done);

    u_data : entity work.ddata_array
        port map (clk => clk, idx => idx, word_off => word_off,
                  we => data_we, wstrb => st_strb, wdata => st_data,
                  line_fill => line_fill, fill_line => fill_line,
                  word_out => rword, line_out => wb_line);

    u_axi : entity work.axi_master
        port map (clk => clk, reset => reset, rd_start => rd_start, wr_start => wr_start,
                  addr => axi_addr, wb_line => wb_line, rd_line => fill_line, done => axi_done,
                  ARADDR => ARADDR, ARLEN => ARLEN, ARSIZE => ARSIZE, ARBURST => ARBURST,
                  ARVALID => ARVALID, ARREADY => ARREADY, RDATA => RDATA, RLAST => RLAST,
                  RVALID => RVALID, RREADY => RREADY,
                  AWADDR => AWADDR, AWLEN => AWLEN, AWSIZE => AWSIZE, AWBURST => AWBURST,
                  AWVALID => AWVALID, AWREADY => AWREADY, WDATA => WDATA, WSTRB => WSTRB,
                  WLAST => WLAST, WVALID => WVALID, WREADY => WREADY, BVALID => BVALID, BREADY => BREADY);
end Behavioral;
