-- =====================================================================
-- rv32_shared.vhd  -  dual-core coordination block (the only shared state
-- in the rv32_dual cluster). Two symmetric core ports (A=hart0, B=hart1)
-- plus a testbench port (T) for preload/readback of the scratchpad.
-- Combinational read (ideal-memory model the cores expect, mem_stall=0).
--
--   offset 0x000  HARTID   (read-only)  port A -> 0, port B -> 1
--   offset 0x004  BARRIER  write any -> set this hart's arrived bit;
--                          read -> 1 once BOTH harts arrived (one-shot)
--   offset 0x100+ SCRATCH  shared words (2 core read ports; A-priority write)
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv32_shared is
    generic ( SP_WORDS : integer := 256 );
    port (
        clk, rst : in  std_logic;
        -- port A  (core 0 / hart 0)
        a_addr   : in  std_logic_vector(31 downto 0);
        a_wdata  : in  std_logic_vector(31 downto 0);
        a_we     : in  std_logic;
        a_rdata  : out std_logic_vector(31 downto 0);
        -- port B  (core 1 / hart 1)
        b_addr   : in  std_logic_vector(31 downto 0);
        b_wdata  : in  std_logic_vector(31 downto 0);
        b_we     : in  std_logic;
        b_rdata  : out std_logic_vector(31 downto 0);
        -- port T  (testbench scratchpad preload / readback)
        t_we     : in  std_logic;
        t_addr   : in  std_logic_vector(31 downto 0);
        t_wdata  : in  std_logic_vector(31 downto 0);
        t_rdata  : out std_logic_vector(31 downto 0)
    );
end entity rv32_shared;

architecture rtl of rv32_shared is
    type sp_t is array (0 to SP_WORDS-1) of std_logic_vector(31 downto 0);
    signal sp      : sp_t := (others => (others => '0'));
    signal arrived : std_logic_vector(1 downto 0) := "00";   -- bit0=A, bit1=B

    constant OFF_HARTID  : integer := 0;     -- word offset 0  (byte 0x000)
    constant OFF_BARRIER : integer := 1;     -- word offset 1  (byte 0x004)
    constant SP_BASE     : integer := 64;    -- word offset 64 (byte 0x100)

    -- word offset within the 4 KiB block
    function woff(a : std_logic_vector(31 downto 0)) return integer is
    begin
        return to_integer(unsigned(a(11 downto 2)));
    end function;
    function sp_idx(a : std_logic_vector(31 downto 0)) return integer is
    begin
        return (woff(a) - SP_BASE) mod SP_WORDS;
    end function;
    function is_sp(a : std_logic_vector(31 downto 0)) return boolean is
    begin
        return woff(a) >= SP_BASE;
    end function;
begin
    ------------------------------------------------------------------
    -- combinational reads (ideal memory: data valid same cycle)
    ------------------------------------------------------------------
    a_rdata <= std_logic_vector(to_unsigned(0, 32))        when woff(a_addr)=OFF_HARTID  else
               (0 => (arrived(0) and arrived(1)), others=>'0') when woff(a_addr)=OFF_BARRIER else
               sp(sp_idx(a_addr))                          when is_sp(a_addr)            else
               (others => '0');

    b_rdata <= std_logic_vector(to_unsigned(1, 32))        when woff(b_addr)=OFF_HARTID  else
               (0 => (arrived(0) and arrived(1)), others=>'0') when woff(b_addr)=OFF_BARRIER else
               sp(sp_idx(b_addr))                          when is_sp(b_addr)            else
               (others => '0');

    t_rdata <= sp(sp_idx(t_addr)) when is_sp(t_addr) else (others => '0');

    ------------------------------------------------------------------
    -- writes: barrier arrive bits + scratchpad (A-priority, then B, then T)
    ------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- T-port scratchpad access is ALWAYS live (outside reset gating) so the
            -- testbench can preload the scratchpad while the cores are held in reset.
            if t_we = '1' and is_sp(t_addr) then
                sp(sp_idx(t_addr)) <= t_wdata;
            end if;

            if rst = '1' then
                arrived <= "00";
            else
                if a_we = '1' and woff(a_addr) = OFF_BARRIER then arrived(0) <= '1'; end if;
                if b_we = '1' and woff(b_addr) = OFF_BARRIER then arrived(1) <= '1'; end if;
                -- core scratchpad writes; A is assigned last -> A wins same-cycle ties
                if b_we = '1' and is_sp(b_addr) then sp(sp_idx(b_addr)) <= b_wdata; end if;
                if a_we = '1' and is_sp(a_addr) then sp(sp_idx(a_addr)) <= a_wdata; end if;
            end if;
        end if;
    end process;
end architecture rtl;
