-- =====================================================================
-- gpu_lane.vhd  -  one SIMT lane: 32-bit integer ALU (add/sub/logic/shift/
-- min/max/compare).  Purely combinational; the core supplies operands and
-- writes results back under the per-lane mask.
--
-- UNIFIED FABRIC: the lane no longer owns a multiplier. VMUL/VMAC are computed
-- by a SHARED npu_pe DSP (the core routes operands out and reads the product
-- back) -> 0 DSP per lane. See docs/UNIFIED_NPU_GPU.md. A_MUL/A_MAC here just
-- drive 0; the core overrides the writeback with the shared-PE product.
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
        c    : in  std_logic_vector(31 downto 0);  -- old Vd value (unused now: MAC accumulates in the shared PE)
        y    : out std_logic_vector(31 downto 0);
        flag : out std_logic                        -- compare result (SLT/SEQ)
    );
end entity gpu_lane;

architecture rtl of gpu_lane is
begin
    process(op, a, b)
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
            when A_MUL  => res := (others => '0');   -- handled by shared PE (core overrides)
            when A_MAC  => res := (others => '0');   -- handled by shared PE (core overrides)
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
