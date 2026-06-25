-- tb_npu.vhd - self-checking testbench for npu_top (INT8 8x8 systolic GEMM).
-- Drives the MMIO slave (load A/B, set K, start, poll done, read C) and compares
-- the 8x8 INT32 result against a software GEMM golden. Deterministic stimuli
-- spanning the signed INT8 range + a boundary case (127 x -128).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_npu is end tb_npu;

architecture sim of tb_npu is
    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal sel   : std_logic := '0';
    signal we    : std_logic := '0';
    signal addr  : std_logic_vector(12 downto 0) := (others=>'0');
    signal wdata : std_logic_vector(31 downto 0) := (others=>'0');
    signal wstrb : std_logic_vector(3 downto 0)  := (others=>'0');
    signal rdata : std_logic_vector(31 downto 0);
    constant TCLK : time := 10 ns;
    signal done_sim : boolean := false;
    signal errors   : integer := 0;
begin
    dut : entity work.npu_top
        port map (clk=>clk, rst=>rst, sel=>sel, we=>we, addr=>addr,
                  wdata=>wdata, wstrb=>wstrb, rdata=>rdata);

    clkgen : process begin
        while not done_sim loop
            clk <= '0'; wait for TCLK/2; clk <= '1'; wait for TCLK/2;
        end loop; wait;
    end process;

    stim : process
        type amat is array (0 to 7, 0 to 255) of integer;
        type bmat is array (0 to 255, 0 to 7) of integer;
        variable A : amat;
        variable B : bmat;
        variable g : integer;
        variable rd : integer;
        variable nerr : integer := 0;

        procedure busw(a : integer; d : integer; s : std_logic_vector(3 downto 0)) is
        begin
            addr<=std_logic_vector(to_unsigned(a,13));
            wdata<=std_logic_vector(to_signed(d,32)); wstrb<=s; sel<='1'; we<='1';
            wait until rising_edge(clk);
            sel<='0'; we<='0'; wstrb<="0000";
        end procedure;

        procedure busr(a : integer; result : out integer) is
        begin
            addr<=std_logic_vector(to_unsigned(a,13)); sel<='1'; we<='0';
            wait for 2 ns;                      -- settle combinational read
            result := to_integer(signed(rdata));
            wait until rising_edge(clk); sel<='0';
        end procedure;

        procedure run_test(K : integer; mode : integer) is
            variable pc : integer := 0;
        begin
            -- build A, B per mode
            for i in 0 to 7 loop
                for k in 0 to K-1 loop
                    if mode=0 then A(i,k) := ((i*7 + k*3) mod 256) - 128;
                    elsif mode=1 then A(i,k) := ((i*13 + k*7 + 5) mod 256) - 128;
                    else A(i,k) := 127; end if;
                end loop;
            end loop;
            for k in 0 to K-1 loop
                for j in 0 to 7 loop
                    if mode=0 then B(k,j) := ((k*5 + j*11) mod 256) - 128;
                    elsif mode=1 then B(k,j) := ((k*3 + j*17) mod 256) - 128;
                    else B(k,j) := -128; end if;
                end loop;
            end loop;
            -- program K
            busw(16#0008#, K, "1111");
            -- load A  (A_BUF[i*256+k] = A[i][k], byte)
            for i in 0 to 7 loop
                for k in 0 to K-1 loop
                    busw(16#0800# + i*256 + k*4, A(i,k), "1111");
                end loop;
            end loop;
            -- load B  (B_BUF[j*256+k] = B[k][j], byte)
            for j in 0 to 7 loop
                for k in 0 to K-1 loop
                    busw(16#1000# + j*256 + k*4, B(k,j), "1111");
                end loop;
            end loop;
            -- start (bit0) + clr_acc (bit1)
            busw(16#0000#, 3, "1111");
            -- poll STATUS.done (bit1), with a timeout guard
            pc := 0;
            loop
                busr(16#0004#, rd);
                pc := pc + 1;
                exit when (rd mod 4) >= 2 or pc > 4000;
            end loop;
            if pc > 4000 then
                report "TIMEOUT waiting done K="&integer'image(K) severity warning;
                nerr := nerr + 1;
            end if;
            -- read C and compare to golden
            for i in 0 to 7 loop
                for j in 0 to 7 loop
                    g := 0;
                    for k in 0 to K-1 loop g := g + A(i,k)*B(k,j); end loop;
                    busr(16#1800# + (i*8+j)*4, rd);
                    if rd /= g then
                        nerr := nerr + 1;
                        report "MISMATCH K="&integer'image(K)&" mode="&integer'image(mode)
                             &" C["&integer'image(i)&"]["&integer'image(j)&"]="
                             &integer'image(rd)&" exp="&integer'image(g) severity warning;
                    end if;
                end loop;
            end loop;
            report "test K="&integer'image(K)&" mode="&integer'image(mode)&" done" severity note;
        end procedure;
    begin
        rst<='1'; wait for 5*TCLK; wait until rising_edge(clk); rst<='0';
        wait until rising_edge(clk);
        run_test(8, 0);
        run_test(16, 1);
        run_test(4, 2);     -- boundary 127 x -128
        errors <= nerr;
        if nerr=0 then report "==== NPU SIM PASS : all C match GEMM golden ====" severity note;
        else            report "==== NPU SIM FAIL : "&integer'image(nerr)&" mismatches ====" severity error; end if;
        done_sim <= true;
        wait;
    end process;
end sim;
