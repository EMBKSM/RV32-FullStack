-- =====================================================================
-- rv32_dual.vhd  -  dual-core RV32 cluster (SIMULATION / bring-up).
-- Two unmodified rv32_core instances, each with private ideal imem/dmem
-- (combinational, like rv32_soc's TB memory), sharing one rv32_shared
-- block for hart id + barrier + a shared scratchpad. Cores reach the
-- shared block at data addresses with bit31=1 (0x8000_0000+); bit31=0 is
-- the core's private 4 KiB dmem. mem_stall is tied 0 (ideal memory).
--
-- SPMD model: the SAME program is loaded into both imems; each core reads
-- its hart id (0/1) from 0x8000_0000 and steers its half of the work.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv32_dual is
    generic (
        IMEM_W   : integer := 1024;   -- words of private instruction memory (per core)
        DMEM_W   : integer := 1024;   -- words of private data memory (per core)
        SP_WORDS : integer := 256     -- shared scratchpad words
    );
    port (
        clk, rst : in  std_logic;
        -- program preload (written into BOTH cores' imem)
        prog_we   : in  std_logic;
        prog_addr : in  std_logic_vector(31 downto 0);
        prog_data : in  std_logic_vector(31 downto 0);
        -- shared scratchpad preload / readback (testbench)
        sp_we     : in  std_logic;
        sp_addr   : in  std_logic_vector(31 downto 0);
        sp_wdata  : in  std_logic_vector(31 downto 0);
        sp_rdata  : out std_logic_vector(31 downto 0);
        -- per-core architectural register read (observe results)
        dbg_reg_addr : in  std_logic_vector(4 downto 0);
        dbg0_reg_data: out std_logic_vector(31 downto 0);
        dbg1_reg_data: out std_logic_vector(31 downto 0);
        -- per-core fetch PC (liveness)
        dbg0_pc, dbg1_pc : out std_logic_vector(31 downto 0)
    );
end entity rv32_dual;

architecture Behavioral of rv32_dual is
    type imem_t is array (0 to IMEM_W-1) of std_logic_vector(31 downto 0);
    type dmem_t is array (0 to DMEM_W-1) of std_logic_vector(31 downto 0);
    signal imem0, imem1 : imem_t := (others => (others => '0'));
    signal dmem0, dmem1 : dmem_t := (others => (others => '0'));

    -- core 0 buses
    signal ia0, ird0, da0, dwd0, drd0 : std_logic_vector(31 downto 0);
    signal dwstrb0 : std_logic_vector(3 downto 0);
    signal dwe0, dre0 : std_logic;
    -- core 1 buses
    signal ia1, ird1, da1, dwd1, drd1 : std_logic_vector(31 downto 0);
    signal dwstrb1 : std_logic_vector(3 downto 0);
    signal dwe1, dre1 : std_logic;
    -- shared block read data
    signal sh_a, sh_b : std_logic_vector(31 downto 0);

    function widx(a : std_logic_vector(31 downto 0); n : integer) return integer is
    begin
        return to_integer(unsigned(a(31 downto 2))) mod n;   -- word index, wrap to size
    end function;
begin
    dbg0_pc <= ia0;  dbg1_pc <= ia1;

    -- ---------------- cores (unmodified) ----------------
    u_core0 : entity work.rv32_core
        generic map (RESET_ADDR => x"00000000")
        port map (clk=>clk, reset=>rst,
                  imem_addr=>ia0, imem_rdata=>ird0,
                  dmem_addr=>da0, dmem_wdata=>dwd0, dmem_wstrb=>dwstrb0,
                  dmem_we=>dwe0, dmem_re=>dre0, dmem_rdata=>drd0,
                  mem_stall=>'0',
                  dbg_commit=>open, dbg_rd=>open, dbg_wdata=>open,
                  dbg_reg_addr=>dbg_reg_addr, dbg_reg_data=>dbg0_reg_data,
                  ic_fence_i=>open);

    u_core1 : entity work.rv32_core
        generic map (RESET_ADDR => x"00000000")
        port map (clk=>clk, reset=>rst,
                  imem_addr=>ia1, imem_rdata=>ird1,
                  dmem_addr=>da1, dmem_wdata=>dwd1, dmem_wstrb=>dwstrb1,
                  dmem_we=>dwe1, dmem_re=>dre1, dmem_rdata=>drd1,
                  mem_stall=>'0',
                  dbg_commit=>open, dbg_rd=>open, dbg_wdata=>open,
                  dbg_reg_addr=>dbg_reg_addr, dbg_reg_data=>dbg1_reg_data,
                  ic_fence_i=>open);

    -- ---------------- private instruction memory (combinational read) -------
    ird0 <= imem0(widx(ia0, IMEM_W));
    ird1 <= imem1(widx(ia1, IMEM_W));

    -- ---------------- private data memory + shared routing (bit31) ----------
    drd0 <= sh_a when da0(31) = '1' else dmem0(widx(da0, DMEM_W));
    drd1 <= sh_b when da1(31) = '1' else dmem1(widx(da1, DMEM_W));

    process(clk)
    begin
        if rising_edge(clk) then
            -- program load into both imems
            if prog_we = '1' then
                imem0(widx(prog_addr, IMEM_W)) <= prog_data;
                imem1(widx(prog_addr, IMEM_W)) <= prog_data;
            end if;
            -- private dmem writes (bit31=0 only; shared writes go to rv32_shared)
            if dwe0 = '1' and da0(31) = '0' then dmem0(widx(da0, DMEM_W)) <= dwd0; end if;
            if dwe1 = '1' and da1(31) = '0' then dmem1(widx(da1, DMEM_W)) <= dwd1; end if;
        end if;
    end process;

    -- ---------------- shared coordination block ----------------
    u_shared : entity work.rv32_shared
        generic map (SP_WORDS => SP_WORDS)
        port map (clk=>clk, rst=>rst,
                  a_addr=>da0, a_wdata=>dwd0, a_we=>(dwe0 and da0(31)), a_rdata=>sh_a,
                  b_addr=>da1, b_wdata=>dwd1, b_we=>(dwe1 and da1(31)), b_rdata=>sh_b,
                  t_we=>sp_we, t_addr=>sp_addr, t_wdata=>sp_wdata, t_rdata=>sp_rdata);
end architecture Behavioral;
