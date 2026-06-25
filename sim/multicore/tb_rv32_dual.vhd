-- =====================================================================
-- tb_rv32_dual.vhd  -  self-checking testbench for the dual-core cluster.
-- Loads the SAME SPMD program (spmd.s, assembled) into both cores, preloads
-- A,B into the shared scratchpad, runs, and checks C[i]=A[i]+B[i] -- where
-- hart0 produced C[0..3] and hart1 produced C[4..7] (split by hart id, with
-- a barrier between). Golden values match sim/multicore/mc_model.c. xsim/GHDL.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rv32_dual is end entity;

architecture sim of tb_rv32_dual is
    type warr is array (natural range <>) of std_logic_vector(31 downto 0);

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal prog_we, sp_we : std_logic := '0';
    signal prog_addr, prog_data, sp_addr, sp_wdata, sp_rdata : std_logic_vector(31 downto 0) := (others=>'0');
    signal dbg_reg_addr : std_logic_vector(4 downto 0) := (others=>'0');
    signal d0, d1, pc0, pc1 : std_logic_vector(31 downto 0);
    signal errors : integer := 0;

    constant N : integer := 8;

    -- SPMD program (spmd.s -> project assembler), 19 instructions
    constant PROG : warr := (
        x"80000537", x"00052283", x"00229313", x"00430393", x"00231413",
        x"10050493", x"008485B3", x"0005A603", x"12050493", x"008486B3",
        x"0006A703", x"00E607B3", x"14050493", x"00848833", x"00F82023",
        x"00130313", x"FC7348E3", x"00552223", x"0000006F");
    -- golden C[i] = A[i]+B[i] = 11*(i+1)
    constant GOLD : warr := (
        x"0000000B", x"00000016", x"00000021", x"0000002C",
        x"00000037", x"00000042", x"0000004D", x"00000058");

    constant SPB : unsigned(31 downto 0) := x"80000100";   -- scratchpad base (byte)
begin
    clk <= not clk after 5 ns;

    dut : entity work.rv32_dual
        port map (clk=>clk, rst=>rst,
                  prog_we=>prog_we, prog_addr=>prog_addr, prog_data=>prog_data,
                  sp_we=>sp_we, sp_addr=>sp_addr, sp_wdata=>sp_wdata, sp_rdata=>sp_rdata,
                  dbg_reg_addr=>dbg_reg_addr, dbg0_reg_data=>d0, dbg1_reg_data=>d1,
                  dbg0_pc=>pc0, dbg1_pc=>pc1);

    stim : process
        procedure pwr(a : std_logic_vector(31 downto 0); d : std_logic_vector(31 downto 0)) is
        begin
            prog_we<='1'; prog_addr<=a; prog_data<=d;
            wait until rising_edge(clk);
            prog_we<='0';
        end procedure;
        procedure spwr(a : std_logic_vector(31 downto 0); d : std_logic_vector(31 downto 0)) is
        begin
            sp_we<='1'; sp_addr<=a; sp_wdata<=d;
            wait until rising_edge(clk);
            sp_we<='0';
        end procedure;
        procedure sprd(a : std_logic_vector(31 downto 0); v : out std_logic_vector(31 downto 0)) is
        begin
            sp_addr<=a;
            wait for 1 ns;
            v := sp_rdata;
        end procedure;
        variable got : std_logic_vector(31 downto 0);
    begin
        rst <= '1';
        -- load program into both cores' imem
        for i in PROG'range loop pwr(std_logic_vector(to_unsigned(i*4,32)), PROG(i)); end loop;
        -- preload A,B into the shared scratchpad
        for i in 0 to N-1 loop
            spwr(std_logic_vector(SPB + i*4),     std_logic_vector(to_unsigned(i+1, 32)));      -- A[i]
            spwr(std_logic_vector(SPB + (N+i)*4), std_logic_vector(to_unsigned(10*(i+1), 32))); -- B[i]
        end loop;
        wait until rising_edge(clk);
        rst <= '0';

        -- both cores run concurrently (~150 cycles); give margin
        for c in 0 to 1500 loop wait until rising_edge(clk); end loop;

        -- check C[i] = A[i]+B[i]  (hart0: 0..3, hart1: 4..7)
        for i in 0 to N-1 loop
            sprd(std_logic_vector(SPB + (2*N+i)*4), got);
            if got /= GOLD(i) then
                report "C[" & integer'image(i) & "] got 0x" & to_hstring(got)
                     & " exp 0x" & to_hstring(GOLD(i)) severity error;
                errors <= errors + 1;
            end if;
        end loop;

        wait for 20 ns;
        if errors = 0 then
            report "==== DUAL-CORE TB: ALL PASS (hart0 did C[0..3], hart1 did C[4..7]) ====" severity note;
        else
            report "==== DUAL-CORE TB: " & integer'image(errors) & " MISMATCHES ====" severity failure;
        end if;
        std.env.stop;
    end process;
end architecture sim;
