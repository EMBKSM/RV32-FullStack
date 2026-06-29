-- =====================================================================
-- tb_unified.vhd  -  self-checking testbench for the UNIFIED NPU/GPU fabric.
-- Instantiates gpu_top AND npu_top16 wired through the shared-PE multiply bus
-- exactly like mmio_bridge. The NPU sits idle (sel=0) and simply lends its 8
-- row-0 PE DSPs to the GPU. Runs the GPU kernels (saxpy + a VMAC kernel exercise
-- the SHARED multiplier) and asserts against the C-golden vectors. If saxpy/vmac
-- pass here, VMUL/VMAC are executing correctly on the NPU's DSPs. (docs/UNIFIED_NPU_GPU.md)
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gpu_pkg.all;

entity tb_unified is end entity;

architecture sim of tb_unified is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal sel, we, re : std_logic := '0';
    signal addr     : std_logic_vector(15 downto 0) := (others=>'0');
    signal wdata    : std_logic_vector(31 downto 0) := (others=>'0');
    signal rdata    : std_logic_vector(31 downto 0);
    signal rd_valid : std_logic;
    signal errors   : integer := 0;

    constant N : integer := GPU_LANES;

    -- shared-PE multiply bus (gpu_top <-> npu_top16)
    signal u_gpu_mode   : std_logic;
    signal u_g_a, u_g_b : std_logic_vector(N*16-1 downto 0);
    signal u_g_c, u_g_y : std_logic_vector(N*32-1 downto 0);
    -- NPU idle-slave tie-offs
    signal npu_addr_z : std_logic_vector(13 downto 0) := (others=>'0');
    signal npu_wd_z   : std_logic_vector(31 downto 0) := (others=>'0');
    signal npu_ws_z   : std_logic_vector(3 downto 0)  := (others=>'0');

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
    -- VMAC kernel: V0=3, V1=5, V2=2, V2 += V0*V1 (=2+15=17), store V2 row0
    --   0x08000003 VMOVI V0,#3 | 0x08800005 VMOVI V1,#5 | 0x09000002 VMOVI V2,#2
    --   0x41020000 VMAC V2,V0,V1 (op=010000 d=010 a=000 b=001) | 0x10040000 VST V2,S0 | HALT
    constant K_VMAC : word_array := (
        x"08000003",x"08800005",x"09000002",x"41020000",x"10040000",x"00000000");
    constant G_VMAC : word_array := (
        x"00000011",x"00000011",x"00000011",x"00000011",
        x"00000011",x"00000011",x"00000011",x"00000011");

    -- MMIO byte-address map (GPU window)
    constant A_CTRL : integer := 16#0000#;
    constant A_STAT : integer := 16#0004#;
    constant A_SARG : integer := 16#0010#;
    constant A_IMEM : integer := 16#1000#;
    constant A_SP   : integer := 16#4000#;
begin
    clk <= not clk after 5 ns;

    -- GPU: multiply operands go OUT on g_*_o, products come back on g_y_i
    dut : entity work.gpu_top
        port map (clk=>clk, rst=>rst, sel=>sel, we=>we, re=>re,
                  addr=>addr, wdata=>wdata, rdata=>rdata, rd_valid=>rd_valid,
                  gpu_active=>u_gpu_mode, g_a_o=>u_g_a, g_b_o=>u_g_b,
                  g_c_o=>u_g_c, g_y_i=>u_g_y);

    -- NPU: idle slave, lends its 8 row-0 PE DSPs to the GPU
    u_npu : entity work.npu_top16
        port map (clk=>clk, rst=>rst, sel=>'0', we=>'0',
                  addr=>npu_addr_z, wdata=>npu_wd_z, wstrb=>npu_ws_z,
                  re=>'0', rdata=>open, rd_valid=>open,
                  gpu_mode=>u_gpu_mode, g_a_flat=>u_g_a, g_b_flat=>u_g_b,
                  g_c_flat=>u_g_c, g_y_flat=>u_g_y);

    stim : process
        procedure wr(ba : integer; d : std_logic_vector(31 downto 0)) is
        begin
            sel<='1'; we<='1'; addr<=std_logic_vector(to_unsigned(ba,16)); wdata<=d;
            wait until rising_edge(clk);
            we<='0'; sel<='0';
        end procedure;
        procedure rdv(ba : integer; v : out std_logic_vector(31 downto 0)) is
        begin
            sel<='1'; re<='1'; addr<=std_logic_vector(to_unsigned(ba,16));
            wait until rising_edge(clk);
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
            wr(A_CTRL, x"00000001");
            for guard in 0 to 1000 loop
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

        -- TEST 1: vector_add (non-mul path through unified fabric)
        for k in 0 to N-1 loop
            wr(A_SP + k*4,        std_logic_vector(to_signed(k+1,    32)));
            wr(A_SP + (N+k)*4,    std_logic_vector(to_signed(10*(k+1),32)));
        end loop;
        load_kernel(K_VADD);
        launch_and_wait;
        check("vector_add", A_SP + 2*N*4, G_VADD);

        -- TEST 2: saxpy Y=a*X+Y  -> exercises VMUL on the SHARED PE DSP
        for k in 0 to N-1 loop
            wr(A_SP + k*4,     std_logic_vector(to_signed(k+1,32)));
            wr(A_SP + (N+k)*4, std_logic_vector(to_signed(100, 32)));
        end loop;
        wr(A_SARG + 1*4, std_logic_vector(to_signed(3,32)));
        load_kernel(K_SAXPY);
        launch_and_wait;
        check("saxpy(VMUL)", A_SP + N*4, G_SAXPY);

        -- TEST 3: relu (min/max path)
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

        -- TEST 4: VMAC V2 += V0*V1  -> exercises the DSP accumulate (C=Vd) path
        load_kernel(K_VMAC);
        launch_and_wait;
        check("vmac(A*B+C)", A_SP, G_VMAC);

        wait for 20 ns;
        if errors = 0 then
            report "==== UNIFIED TB: ALL TESTS PASS (GPU mul on shared NPU DSPs) ====" severity note;
        else
            report "==== UNIFIED TB: " & integer'image(errors) & " MISMATCHES ====" severity failure;
        end if;
        std.env.stop;
    end process;
end architecture sim;
