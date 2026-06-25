-- =====================================================================
-- gpu_lane.vhd  -  one SIMT lane: 32-bit integer ALU + LUT multiplier.
-- Purely combinational; the core supplies operands and writes results back
-- under the per-lane mask. Multiplier forced to fabric (use_dsp="no") so all
-- DSP48 blocks stay available to the NPU.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gpu_pkg.all;

entity gpu_lane is
    port (
        op   : in  aluop_t;
        a    : in  std_logic_vector(31 downto 0);
        b    : in  std_logic_vector(31 downto 0);
        c    : in  std_logic_vector(31 downto 0);  -- old Vd value (for MAC accumulate)
        y    : out std_logic_vector(31 downto 0);
        flag : out std_logic                        -- compare result (SLT/SEQ)
    );
end entity gpu_lane;

architecture rtl of gpu_lane is
    signal prod : signed(63 downto 0);
    attribute use_dsp : string;
    attribute use_dsp of prod : signal is "no";
begin
    prod <= signed(a) * signed(b);

    process(op, a, b, c, prod)
        variable sa, sb : signed(31 downto 0);
        variable sh     : integer range 0 to 31;
        variable res    : std_logic_vector(31 downto 0);
        variable fl     : std_logic;
    begin
        sa  := signed(a);
        sb  := signed(b);
        sh  := to_integer(unsigned(b(4 downto 0)));
        res := (others => '0');
        fl  := '0';
        case op is
            when A_ADD  => res := std_logic_vector(sa + sb);
            when A_SUB  => res := std_logic_vector(sa - sb);
            when A_AND  => res := a and b;
            when A_OR   => res := a or b;
            when A_XOR  => res := a xor b;
            when A_SLL  => res := std_logic_vector(shift_left (unsigned(a), sh));
            when A_SRL  => res := std_logic_vector(shift_right(unsigned(a), sh));
            when A_SRA  => res := std_logic_vector(shift_right(sa, sh));
            when A_MIN  => if sa < sb then res := a; else res := b; end if;
            when A_MAX  => if sa > sb then res := a; else res := b; end if;
            when A_MUL  => res := std_logic_vector(prod(31 downto 0));
            when A_MAC  => res := std_logic_vector(prod(31 downto 0) + signed(c));
            when A_SLT  => if sa <  sb then fl := '1'; end if;
                          res := (0 => fl, others => '0');
            when A_SEQ  => if  a =  b  then fl := '1'; end if;
                          res := (0 => fl, others => '0');
            when A_PASSA => res := a;
            when others  => res := (others => '0');
        end case;
        y    <= res;
        flag <= fl;
    end process;
end architecture rtl;
