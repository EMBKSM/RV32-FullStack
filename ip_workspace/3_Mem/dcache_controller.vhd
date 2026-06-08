-- dcache_controller.vhd - D-cache write-back/write-allocate FSM
-- Orchestrates dtag_array + ddata_array + axi_master.
-- Spec: RV32_Pipeline_Spec.md 8.x, Movement.md 6.6
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity dcache_controller is
    Port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        -- CPU side
        mem_read   : in  std_logic;
        mem_write  : in  std_logic;
        hit        : in  std_logic;
        dirty      : in  std_logic;
        req_tag    : in  std_logic_vector(19 downto 0);
        victim_tag : in  std_logic_vector(19 downto 0);
        idx        : in  std_logic_vector(7 downto 0);
        stall      : out std_logic;
        wake_up    : out std_logic;
        -- array control
        we_tag     : out std_logic;   -- refill: write tag/valid, clear dirty
        we_dirty   : out std_logic;   -- store hit: set dirty
        data_we    : out std_logic;   -- store hit: byte-strobed word write
        line_fill  : out std_logic;   -- refill: write whole line
        -- axi_master side
        rd_start   : out std_logic;
        wr_start   : out std_logic;
        axi_addr   : out std_logic_vector(31 downto 0);
        axi_done   : in  std_logic
    );
end dcache_controller;

architecture Behavioral of dcache_controller is
    type st_t is (D_IDLE, D_WB, D_ALLOC, D_REFILL, D_WAKE);
    signal st     : st_t := D_IDLE;
    signal access_v, miss : std_logic;
begin
    access_v <= mem_read or mem_write;
    miss     <= '1' when (access_v = '1' and hit = '0') else '0';

    -- writeback uses victim tag; allocate/refill uses requested tag
    axi_addr <= victim_tag & idx & "0000" when st = D_WB
                else req_tag & idx & "0000";

    process(st, access_v, miss, dirty, mem_write, hit)
    begin
        stall <= '0'; wake_up <= '0';
        we_tag <= '0'; we_dirty <= '0'; data_we <= '0'; line_fill <= '0';
        rd_start <= '0'; wr_start <= '0';
        case st is
            when D_IDLE =>
                if miss = '1' then
                    stall <= '1';
                elsif (access_v = '1' and hit = '1' and mem_write = '1') then
                    data_we  <= '1';     -- store hit: write word
                    we_dirty <= '1';     -- mark dirty
                end if;
            when D_WB =>
                stall <= '1'; wr_start <= '1';      -- write back dirty line
            when D_ALLOC =>
                stall <= '1'; rd_start <= '1';      -- fetch new line
            when D_REFILL =>
                stall <= '1'; line_fill <= '1'; we_tag <= '1';
            when D_WAKE =>
                wake_up <= '1';
        end case;
    end process;

    process(clk, reset)
    begin
        if reset = '1' then
            st <= D_IDLE;
        elsif rising_edge(clk) then
            case st is
                when D_IDLE =>
                    if miss = '1' then
                        if dirty = '1' then st <= D_WB; else st <= D_ALLOC; end if;
                    end if;
                when D_WB =>
                    if axi_done = '1' then st <= D_ALLOC; end if;
                when D_ALLOC =>
                    if axi_done = '1' then st <= D_REFILL; end if;
                when D_REFILL =>
                    st <= D_WAKE;
                when D_WAKE =>
                    st <= D_IDLE;
            end case;
        end if;
    end process;
end Behavioral;
