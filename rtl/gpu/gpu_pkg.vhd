-- =====================================================================
-- gpu_pkg.vhd  -  SIMT-lite vector coprocessor: ISA + shared types
-- One instruction stream drives N_LANES in lockstep; per-lane predicate
-- mask handles divergence. See docs/GPU_DESIGN.md.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gpu_pkg is

    -- ---- machine parameters (overridable on gpu_top generics) ----
    constant GPU_LANES   : integer := 8;     -- N lanes (data-parallel width)
    constant GPU_VREGS   : integer := 8;     -- vector registers V0..V7
    constant GPU_SREGS   : integer := 8;     -- scalar registers S0..S7
    constant GPU_IMEM    : integer := 256;   -- instruction words
    constant GPU_BANKD   : integer := 256;   -- scratchpad words per bank

    -- ---- instruction layout : [31:26]=op [25:23]=d [22:20]=a [19:17]=b [16:0]=imm ----
    subtype  opcode_t is std_logic_vector(5 downto 0);
    constant OP_HALT  : opcode_t := "000000";
    constant OP_VLID  : opcode_t := "000001";  -- Vd[k] = k
    constant OP_VMOVI : opcode_t := "000010";  -- Vd[k] = sext(imm)
    constant OP_VLD   : opcode_t := "000011";  -- Vd[k] = SP[bank k][ (Sa+imm)/N ]
    constant OP_VST   : opcode_t := "000100";  -- SP[bank k][ (Sa+imm)/N ] = Vb[k]
    constant OP_VADD  : opcode_t := "000101";
    constant OP_VSUB  : opcode_t := "000110";
    constant OP_VAND  : opcode_t := "000111";
    constant OP_VOR   : opcode_t := "001000";
    constant OP_VXOR  : opcode_t := "001001";
    constant OP_VSLL  : opcode_t := "001010";
    constant OP_VSRL  : opcode_t := "001011";
    constant OP_VSRA  : opcode_t := "001100";
    constant OP_VMIN  : opcode_t := "001101";  -- signed
    constant OP_VMAX  : opcode_t := "001110";  -- signed
    constant OP_VMUL  : opcode_t := "001111";  -- low 32 bits, LUT multiplier
    constant OP_VMAC  : opcode_t := "010000";  -- Vd[k] += Va[k]*Vb[k]
    constant OP_VSLT  : opcode_t := "010001";  -- mask: M[k] = Va[k] <s Vb[k]
    constant OP_VSEQ  : opcode_t := "010010";  -- mask: M[k] = Va[k] == Vb[k]
    constant OP_MASKON: opcode_t := "010011";  -- M[k] = 1 for all k
    constant OP_VBCAST: opcode_t := "010100";  -- Vd[k] = Sa (scalar -> vector)
    constant OP_SADDI : opcode_t := "010101";  -- Sd = Sa + sext(imm)
    constant OP_SBNZ  : opcode_t := "010110";  -- if Sa /= 0 : PC = PC + sext(imm)

    -- ALU sub-function passed to a lane (decoded subset that the lane computes)
    subtype  aluop_t is std_logic_vector(3 downto 0);
    constant A_ADD : aluop_t := "0000";
    constant A_SUB : aluop_t := "0001";
    constant A_AND : aluop_t := "0010";
    constant A_OR  : aluop_t := "0011";
    constant A_XOR : aluop_t := "0100";
    constant A_SLL : aluop_t := "0101";
    constant A_SRL : aluop_t := "0110";
    constant A_SRA : aluop_t := "0111";
    constant A_MIN : aluop_t := "1000";
    constant A_MAX : aluop_t := "1001";
    constant A_MUL : aluop_t := "1010";
    constant A_MAC : aluop_t := "1011";   -- a*b + d_old (acc passed in as 'c')
    constant A_SLT : aluop_t := "1100";   -- result(0) = a <s b
    constant A_SEQ : aluop_t := "1101";   -- result(0) = (a == b)
    constant A_PASSA : aluop_t := "1110"; -- result = a (used for moves/broadcast)

    -- vector of 32-bit words, one per lane
    type word_array is array (natural range <>) of std_logic_vector(31 downto 0);

end package gpu_pkg;
