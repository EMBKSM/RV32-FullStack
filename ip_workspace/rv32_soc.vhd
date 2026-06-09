-- =====================================================================
-- rv32_soc.vhd  -  FULL integration top (SIMULATION / bring-up)
-- rv32_core (pipeline, with mem_stall) + I-cache + D-cache, each backed by
-- a behavioral AXI memory (Harvard: separate instruction/data buses, so no
-- arbiter). Exercises the whole memory hierarchy (cache miss -> AXI burst
-- refill / write-back -> pipeline freeze) together with the pipeline.
--
-- This top is for integration bring-up, NOT for synthesis/IP: it embeds
-- behavioral AXI memories and a program-preload port. Both caches reuse the
-- verified D-cache blocks (dtag_array/ddata_array/dcache_controller/
-- axi_master) via cache_unit; the I-cache ties we='0' (read-only).
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rv32_soc is
    Generic ( RESET_ADDR : std_logic_vector(31 downto 0) := x"00000000" );
    Port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        -- program preload into the instruction memory (sim; before reset deassert)
        prog_we    : in  std_logic;
        prog_addr  : in  std_logic_vector(31 downto 0);
        prog_data  : in  std_logic_vector(31 downto 0);
        -- optional data-memory preload
        dmem_we_pre   : in  std_logic;
        dmem_addr_pre : in  std_logic_vector(31 downto 0);
        dmem_data_pre : in  std_logic_vector(31 downto 0);
        -- debug / scoreboard (architectural register read)
        dbg_commit   : out std_logic;
        dbg_rd       : out std_logic_vector(4 downto 0);
        dbg_wdata    : out std_logic_vector(31 downto 0);
        dbg_reg_addr : in  std_logic_vector(4 downto 0);
        dbg_reg_data : out std_logic_vector(31 downto 0);
        -- debug: fetch observability
        dbg_pc       : out std_logic_vector(31 downto 0);
        dbg_instr    : out std_logic_vector(31 downto 0);
        dbg_mstall   : out std_logic
    );
end rv32_soc;

architecture Behavioral of rv32_soc is
    -- core <-> caches
    signal imem_addr, imem_rdata : std_logic_vector(31 downto 0);
    signal dmem_addr, dmem_wdata, dmem_rdata : std_logic_vector(31 downto 0);
    signal dmem_wstrb : std_logic_vector(3 downto 0);
    signal dmem_we, dmem_re : std_logic;
    signal i_stall, d_stall, mem_stall : std_logic;

    -- I-cache AXI
    signal i_ARADDR, i_AWADDR, i_WDATA, i_RDATA : std_logic_vector(31 downto 0);
    signal i_ARLEN, i_AWLEN : std_logic_vector(7 downto 0);
    signal i_ARSIZE, i_AWSIZE : std_logic_vector(2 downto 0);
    signal i_ARBURST, i_AWBURST : std_logic_vector(1 downto 0);
    signal i_WSTRB : std_logic_vector(3 downto 0);
    signal i_ARVALID,i_ARREADY,i_RLAST,i_RVALID,i_RREADY : std_logic;
    signal i_AWVALID,i_AWREADY,i_WLAST,i_WVALID,i_WREADY,i_BVALID,i_BREADY : std_logic;

    -- D-cache AXI
    signal d_ARADDR, d_AWADDR, d_WDATA, d_RDATA : std_logic_vector(31 downto 0);
    signal d_ARLEN, d_AWLEN : std_logic_vector(7 downto 0);
    signal d_ARSIZE, d_AWSIZE : std_logic_vector(2 downto 0);
    signal d_ARBURST, d_AWBURST : std_logic_vector(1 downto 0);
    signal d_WSTRB : std_logic_vector(3 downto 0);
    signal d_ARVALID,d_ARREADY,d_RLAST,d_RVALID,d_RREADY : std_logic;
    signal d_AWVALID,d_AWREADY,d_WLAST,d_WVALID,d_WREADY,d_BVALID,d_BREADY : std_logic;

    signal i_req : std_logic;
    signal d_req : std_logic;
begin
    mem_stall <= i_stall or d_stall;
    i_req     <= '1';                          -- always fetching
    d_req     <= dmem_re or dmem_we;

    dbg_pc     <= imem_addr;                    -- fetch observability
    dbg_instr  <= imem_rdata;
    dbg_mstall <= mem_stall;

    -- ================= pipeline core =================
    u_core : entity work.rv32_core
        generic map (RESET_ADDR => RESET_ADDR)
        port map (clk => clk, reset => reset,
                  imem_addr => imem_addr, imem_rdata => imem_rdata,
                  dmem_addr => dmem_addr, dmem_wdata => dmem_wdata, dmem_wstrb => dmem_wstrb,
                  dmem_we => dmem_we, dmem_re => dmem_re, dmem_rdata => dmem_rdata,
                  mem_stall => mem_stall,
                  dbg_commit => dbg_commit, dbg_rd => dbg_rd, dbg_wdata => dbg_wdata,
                  dbg_reg_addr => dbg_reg_addr, dbg_reg_data => dbg_reg_data);

    -- ================= I-cache (read-only) =================
    u_icache : entity work.cache_unit
        port map (clk => clk, reset => reset,
                  req => i_req, we => '0', addr => imem_addr,
                  st_data => x"00000000", st_strb => "0000",
                  rword => imem_rdata, stall => i_stall,
                  ARADDR=>i_ARADDR,ARLEN=>i_ARLEN,ARSIZE=>i_ARSIZE,ARBURST=>i_ARBURST,
                  ARVALID=>i_ARVALID,ARREADY=>i_ARREADY,RDATA=>i_RDATA,RLAST=>i_RLAST,
                  RVALID=>i_RVALID,RREADY=>i_RREADY,
                  AWADDR=>i_AWADDR,AWLEN=>i_AWLEN,AWSIZE=>i_AWSIZE,AWBURST=>i_AWBURST,
                  AWVALID=>i_AWVALID,AWREADY=>i_AWREADY,WDATA=>i_WDATA,WSTRB=>i_WSTRB,
                  WLAST=>i_WLAST,WVALID=>i_WVALID,WREADY=>i_WREADY,BVALID=>i_BVALID,BREADY=>i_BREADY);

    u_imem : entity work.axi_slave_mem
        generic map (WORDS => 4096)
        port map (clk => clk, reset => reset,
                  prog_we => prog_we, prog_addr => prog_addr, prog_data => prog_data,
                  ARADDR=>i_ARADDR,ARVALID=>i_ARVALID,ARREADY=>i_ARREADY,
                  RDATA=>i_RDATA,RLAST=>i_RLAST,RVALID=>i_RVALID,RREADY=>i_RREADY,
                  AWADDR=>i_AWADDR,AWVALID=>i_AWVALID,AWREADY=>i_AWREADY,
                  WDATA=>i_WDATA,WSTRB=>i_WSTRB,WLAST=>i_WLAST,WVALID=>i_WVALID,WREADY=>i_WREADY,
                  BVALID=>i_BVALID,BREADY=>i_BREADY);

    -- ================= D-cache (read/write) =================
    u_dcache : entity work.cache_unit
        port map (clk => clk, reset => reset,
                  req => d_req, we => dmem_we, addr => dmem_addr,
                  st_data => dmem_wdata, st_strb => dmem_wstrb,
                  rword => dmem_rdata, stall => d_stall,
                  ARADDR=>d_ARADDR,ARLEN=>d_ARLEN,ARSIZE=>d_ARSIZE,ARBURST=>d_ARBURST,
                  ARVALID=>d_ARVALID,ARREADY=>d_ARREADY,RDATA=>d_RDATA,RLAST=>d_RLAST,
                  RVALID=>d_RVALID,RREADY=>d_RREADY,
                  AWADDR=>d_AWADDR,AWLEN=>d_AWLEN,AWSIZE=>d_AWSIZE,AWBURST=>d_AWBURST,
                  AWVALID=>d_AWVALID,AWREADY=>d_AWREADY,WDATA=>d_WDATA,WSTRB=>d_WSTRB,
                  WLAST=>d_WLAST,WVALID=>d_WVALID,WREADY=>d_WREADY,BVALID=>d_BVALID,BREADY=>d_BREADY);

    u_dmem : entity work.axi_slave_mem
        generic map (WORDS => 4096)
        port map (clk => clk, reset => reset,
                  prog_we => dmem_we_pre, prog_addr => dmem_addr_pre, prog_data => dmem_data_pre,
                  ARADDR=>d_ARADDR,ARVALID=>d_ARVALID,ARREADY=>d_ARREADY,
                  RDATA=>d_RDATA,RLAST=>d_RLAST,RVALID=>d_RVALID,RREADY=>d_RREADY,
                  AWADDR=>d_AWADDR,AWVALID=>d_AWVALID,AWREADY=>d_AWREADY,
                  WDATA=>d_WDATA,WSTRB=>d_WSTRB,WLAST=>d_WLAST,WVALID=>d_WVALID,WREADY=>d_WREADY,
                  BVALID=>d_BVALID,BREADY=>d_BREADY);
end Behavioral;
