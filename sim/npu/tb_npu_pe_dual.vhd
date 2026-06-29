-- tb_npu_pe_dual.vhd - prove ONE dual-mode PE does BOTH:
--   (1) NPU systolic INT8 MAC   (gpu_mode=0):  p += a*b
--   (2) GPU lane multiply-add    (gpu_mode=1):  g_y = g_a*g_b + g_c
-- Self-checking; reports PASS/FAIL. Pair with synth_dual_pe.tcl (must be 1 DSP).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_npu_pe_dual is
end tb_npu_pe_dual;

architecture sim of tb_npu_pe_dual is
    signal clk : std_logic := '0';
    signal en, clr, gpu_mode : std_logic := '0';
    signal a_in, b_in : std_logic_vector(7 downto 0) := (others => '0');
    signal a_out, b_out : std_logic_vector(7 downto 0);
    signal acc, g_y : std_logic_vector(31 downto 0);
    signal g_a, g_b : std_logic_vector(15 downto 0) := (others => '0');
    signal g_c : std_logic_vector(31 downto 0) := (others => '0');
    signal errors : integer := 0;

    procedure check(name : string; got, exp : integer; signal errs : inout integer) is
    begin
        if got = exp then
            report "PASS " & name & " = " & integer'image(got);
        else
            report "FAIL " & name & " got=" & integer'image(got) & " exp=" & integer'image(exp) severity error;
            errs <= errs + 1;
        end if;
    end procedure;
begin
    dut : entity work.npu_pe
        generic map (DSP_USE => "yes", GPU_LANE => true)
        port map (clk=>clk, en=>en, clr=>clr, a_in=>a_in, b_in=>b_in,
                  a_out=>a_out, b_out=>b_out, acc=>acc,
                  gpu_mode=>gpu_mode, g_a=>g_a, g_b=>g_b, g_c=>g_c, g_y=>g_y);

    clk <= not clk after 5 ns;

    stim : process
    begin
        ------------------------------------------------------------------
        -- Phase 1: NPU INT8 MAC mode (gpu_mode=0)
        --   clear, then accumulate (2*3) + (4*5) + (-1*7) = 6 + 20 - 7 = 19
        ------------------------------------------------------------------
        gpu_mode <= '0';
        clr <= '1'; en <= '0'; wait until rising_edge(clk); clr <= '0';
        en <= '1';
        a_in <= std_logic_vector(to_signed( 2,8)); b_in <= std_logic_vector(to_signed(3,8));
        wait until rising_edge(clk);
        a_in <= std_logic_vector(to_signed( 4,8)); b_in <= std_logic_vector(to_signed(5,8));
        wait until rising_edge(clk);
        a_in <= std_logic_vector(to_signed(-1,8)); b_in <= std_logic_vector(to_signed(7,8));
        wait until rising_edge(clk);
        en <= '0';
        wait until rising_edge(clk);            -- let last MAC settle
        check("NPU_MAC_acc", to_integer(signed(acc)), 19, errors);

        ------------------------------------------------------------------
        -- Phase 2: GPU multiply-add mode (gpu_mode=1) on the SAME DSP
        --   VMAC: g_y = 100*50 + 7 = 5007
        ------------------------------------------------------------------
        gpu_mode <= '1'; en <= '0'; clr <= '0';
        g_a <= std_logic_vector(to_signed(100,16));
        g_b <= std_logic_vector(to_signed( 50,16));
        g_c <= std_logic_vector(to_signed(  7,32));
        wait until rising_edge(clk);            -- DSP registers the product
        wait until rising_edge(clk);            -- g_y observable
        check("GPU_MAC_y", to_integer(signed(g_y)), 5007, errors);

        --   VMUL: g_y = -3*4 + 0 = -12
        g_a <= std_logic_vector(to_signed(-3,16));
        g_b <= std_logic_vector(to_signed( 4,16));
        g_c <= (others => '0');
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        check("GPU_MUL_y", to_integer(signed(g_y)), -12, errors);

        ------------------------------------------------------------------
        -- Phase 3: back to NPU mode - the DSP still does MAC correctly
        --   clear, (10*10) = 100
        ------------------------------------------------------------------
        gpu_mode <= '0';
        clr <= '1'; en <= '0'; wait until rising_edge(clk); clr <= '0';
        en <= '1';
        a_in <= std_logic_vector(to_signed(10,8)); b_in <= std_logic_vector(to_signed(10,8));
        wait until rising_edge(clk);
        en <= '0';
        wait until rising_edge(clk);
        check("NPU_MAC_again", to_integer(signed(acc)), 100, errors);

        if errors = 0 then
            report "==== tb_npu_pe_dual: ALL PASS (one DSP, both modes) ====";
        else
            report "==== tb_npu_pe_dual: " & integer'image(errors) & " FAIL ====" severity failure;
        end if;
        wait;
    end process;
end sim;
