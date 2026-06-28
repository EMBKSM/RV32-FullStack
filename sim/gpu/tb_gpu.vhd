-- =====================================================================
-- tb_gpu.vhd  -  self-checking testbench for the SIMT-lite coprocessor.
-- Plays the role of the CPU/mmio_bridge: loads data + kernel through the
-- MMIO window, launches, polls DONE, reads results, and asserts them
-- against the C-golden vectors (gpu_model.c). Kernels/goldens are the exact
-- words emitted by that model. Run with any VHDL-2008 simulator (xsim/GHDL).
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gpu_pkg.all;

entity tb_gpu is end entity;

architecture sim of tb_gpu is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal sel, we, re : std_logic := '0';
    signal addr     : std_logic_vector(15 downto 0) := (others=>'0');
    signal wdata    : std_logic_vector(31 downto 0) := (others=>'0');
    signal rdata    : std_logic_vector(31 downto 0);
    signal rd_valid : std_logic;
    signal errors   : integer := 0;

    constant N : integer := GPU_LANES;

    -- kernels (from gpu_model.c) ----------------------------------------
    constant K_VADD : word_array := (
        x"0C000000", x"0C800008", x"15020000", x"10040010", x"00000000");
    constant G_VADD : word_array := (
        x"0000000B",x"00000016",x"00000021",x"0000002C",
        x"00000037",x"00000042",x"0000004D",x"00000058");
    constant K_SAXPY : word_array := (
        x"51900000",x"0C000000",x"0C800008",x"3D300000",
        x"14940000",x"10020008",x"00000000");
    constant G_SAXPY : word_array := (
        x"00000067",x"0000006A",x"0000006D",x"00000070",
        x"00000073",x"00000076",x"00000079",x"0000007C");
    constant K_RELU : word_array := (
        x"0C000000",x"08800000",x"39020000",x"10040008",x"00000000");
    constant G_RELU : word_array := (
        x"00000001",x"00000000",x"00000003",x"00000000",
        x"00000005",x"00000000",x"00000007",x"00000000");

    -- MMIO byte-address map
    constant A_CTRL : integer := 16#0000#;
    constant A_STAT : integer := 16#0004#;
    constant A_SARG : integer := 16#0010#;
    constant A_IMEM : integer := 16#1000#;
    constant A_SP   : integer := 16#4000#;
begin
    clk <= not clk after 5 ns;

    dut : entity work.gpu_top
        port map (clk=>clk, rst=>rst, sel=>sel, we=>we, re=>re,
                  addr=>addr, wdata=>wdata, rdata=>rdata, rd_valid=>rd_valid);

    stim : process
        -- write one MMIO word
        procedure wr(ba : integer; d : std_logic_vector(31 downto 0)) is
        begin
            sel<='1'; we<='1'; addr<=std_logic_vector(to_unsigned(ba,16)); wdata<=d;
            wait until rising_edge(clk);
            we<='0'; sel<='0';
        end procedure;
        -- read one MMIO word (combinational slave)
        procedure rdv(ba : integer; v : out std_logic_vector(31 downto 0)) is
        begin
            sel<='1'; re<='1'; addr<=std_logic_vector(to_unsigned(ba,16));
            wait until rising_edge(clk);   -- scratchpad read is registered (1-cycle BRAM latency)
            wait for 1 ns;
            v := rdata;
            re<='0'; sel<='0';
        end procedure;

        procedure load_kernel(k : word_array) is
        begin
            for i in k'range loop wr(A_IMEM + i*4, k(i)); end loop;
        end procedure;

        procedure launch_and_wait is
            variable st : std_logic_vector(31 downto 0);
        begin
            wr(A_CTRL, x"00000001");          -- START
            for guard in 0 to 1000 loop       -- poll DONE
                rdv(A_STAT, st);
                exit when st(0) = '1';
            end loop;
            assert st(0)='1' report "GPU did not finish (timeout)" severity error;
        end procedure;

        procedure check(name : string; ba : integer; g : word_array) is
            variable got : std_logic_vector(31 downto 0);
        begin
            for k in 0 to N-1 loop
                rdv(ba + k*4, got);
                if got /= g(k) then
                    report name & " lane " & integer'image(k) & " : got 0x" &
                        to_hstring(got) & " exp 0x" & to_hstring(g(k)) severity error;
                    errors <= errors + 1;
                end if;
            end loop;
            report name & " : checked " & integer'image(N) & " lanes";
        end procedure;
    begin
        rst <= '1'; wait for 40 ns; wait until rising_edge(clk); rst <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------------
        -- TEST 1: vector_add  C = A + B    (A row0, B row1, C row2)
        --------------------------------------------------------------
        for k in 0 to N-1 loop
            wr(A_SP + k*4,        std_logic_vector(to_signed(k+1,    32)));  -- A
            wr(A_SP + (N+k)*4,    std_logic_vector(to_signed(10*(k+1),32))); -- B
        end loop;
        load_kernel(K_VADD);
        launch_and_wait;
        check("vector_add", A_SP + 2*N*4, G_VADD);

        --------------------------------------------------------------
        -- TEST 2: saxpy  Y = a*X + Y,  a=3 in SARG[1]   (X row0, Y row1)
        --------------------------------------------------------------
        for k in 0 to N-1 loop
            wr(A_SP + k*4,     std_logic_vector(to_signed(k+1,32)));  -- X
            wr(A_SP + (N+k)*4, std_logic_vector(to_signed(100, 32))); -- Y
        end loop;
        wr(A_SARG + 1*4, std_logic_vector(to_signed(3,32)));          -- a -> S1
        load_kernel(K_SAXPY);
        launch_and_wait;
        check("saxpy", A_SP + N*4, G_SAXPY);

        --------------------------------------------------------------
        -- TEST 3: relu  Y = max(0,X)        (X row0, Y row1)
        --------------------------------------------------------------
        for k in 0 to N-1 loop
            if (k mod 2) = 0 then
                wr(A_SP + k*4, std_logic_vector(to_signed(k+1,32)));
            else
                wr(A_SP + k*4, std_logic_vector(to_signed(-(k+1),32)));
            end if;
        end loop;
        load_kernel(K_RELU);
        launch_and_wait;
        check("relu", A_SP + N*4, G_RELU);

        --------------------------------------------------------------
        wait for 20 ns;
        if errors = 0 then
            report "==== GPU TB: ALL TESTS PASS ====" severity note;
        else
            report "==== GPU TB: " & integer'image(errors) & " MISMATCHES ====" severity failure;
        end if;
        std.env.stop;
    end process;
end architecture sim;
