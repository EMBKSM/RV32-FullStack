# On-board GPU test of the UNIFIED NPU/GPU bitstream @ 100 MHz, via ctrl_axi.
# Proves the SHARED-DSP GPU runs on real silicon: the RV32 core loads a GPU kernel
# (VMOVI V1=6, VMOVI V2=7, VMUL V3=V1*V2 -> 42 on a borrowed NPU DSP, VLID V4=k,
#  VADD V3=V3+V4 -> 42+k) into the GPU, runs it, reads scratchpad lanes 0..3 into
# x10..x13. Driver assembled from sw/host/gpu_board_demo.s. Golden: 42,43,44,45.
connect
source C:/work/github/RV32-FullStack/flash/ps7_init.tcl
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
configparams force-mem-access 1
rst -processor
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_peripherals_init_data_3_0
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000170 0x00100A00
mwr 0xF8000004 0x0000767B
fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_unified_100mhz.bit
ps7_post_config
memmap -addr 0x40000000 -size 0x00010000 -flags 3
puts "### UNIFIED bitstream @ 100 MHz; loading RV32 GPU-driver via ctrl_axi ###"

set B 0x40000000
mwr [expr {$B + 0x00}] 0x1
set prog {
   0 0x40000237   4 0x400010b7   8 0x40004137  12 0x088002b7
  16 0x00628293  20 0x0050a023  24 0x090002b7  28 0x00728293
  32 0x0050a223  36 0x3d9402b7  40 0x0050a423  44 0x060002b7
  48 0x0050a623  52 0x15b802b7  56 0x0050a823  60 0x100602b7
  64 0x0050aa23  68 0x0000ac23  72 0x00100293  76 0x00522023
  80 0x00422303  84 0x00137313  88 0xfe030ce3  92 0x00012503
  96 0x00012503 100 0x00412583 104 0x00412583 108 0x00812603
 112 0x00812603 116 0x00c12683 120 0x00c12683 124 0x0000006f
}
foreach {a w} $prog { mwr [expr {$B + 0x08}] $a ; mwr [expr {$B + 0x0C}] $w }
puts "### GPU-driver imem loaded (32 words, incl. VST); releasing RV32 ###"
mwr [expr {$B + 0x00}] 0x2
after 300
puts "PC      = [format 0x%08x [lindex [mrd -value [expr {$B + 0x20}]] 0]]"
puts "STATUS  = [format 0x%08x [lindex [mrd -value [expr {$B + 0x04}]] 0]]"
proc rdreg {B n} { mwr [expr {$B + 0x18}] $n ; return [lindex [mrd -value [expr {$B + 0x1C}]] 0] }
set v0 [rdreg $B 10] ; set v1 [rdreg $B 11] ; set v2 [rdreg $B 12] ; set v3 [rdreg $B 13]
puts "BOARD  UNIFIED GPU (VMUL 6*7=42 + lane k):  L0=$v0  L1=$v1  L2=$v2  L3=$v3"
puts "GOLDEN (42+k)                            :  L0=42   L1=43   L2=44   L3=45"
if {$v0==42 && $v1==43 && $v2==44 && $v3==45} {
    puts ">>> BOARD-UNIFIED-GPU: PASS  (GPU VMUL/VADD on shared NPU DSPs, real XC7Z020 @100MHz) <<<"
} else {
    puts ">>> BOARD-UNIFIED-GPU: MISMATCH <<<"
}
disconnect
puts "UNIFIED-GPU-TEST-COMPLETE"
