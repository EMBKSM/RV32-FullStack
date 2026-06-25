# On-board 16x16 NPU GEMM test via ctrl_axi (PS-AXI @ 0x4000_0000) -- no DDR/OCM/monitor.
# Driver computes a 2x2 tile (K=2): A=[[3,4],[1,2]] B=[[5,7],[6,8]] -> C=[[39,53],[17,23]].
connect
source C:/work/github/RV32-FullStack/fpga/flash/ps7_init.tcl
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
configparams force-mem-access 1
rst -processor
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_peripherals_init_data_3_0
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000170 0x00102100
mwr 0xF8000004 0x0000767B
fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_rtopt_wns-6p74.bit
ps7_post_config
# register the PL AXI-GP0 region so XSDB allows ctrl_axi accesses
memmap -addr 0x40000000 -size 0x00010000 -flags 3
puts "### bitstream @30.3MHz ready; driving RV32 via ctrl_axi ###"

set B 0x40000000
# hold RV32 in reset
mwr [expr {$B + 0x00}] 0x1
# load driver into imem (byte addr, word)
set prog {
  0 0x30000237   4 0x300010b7   8 0x30002137  12 0x300031b7
  16 0x00200293  20 0x00522423  24 0x00300313  28 0x0060a023
  32 0x00400313  36 0x0060a223  40 0x00100313  44 0x1060a023
  48 0x00200313  52 0x1060a223  56 0x00500393  60 0x00712023
  64 0x00600393  68 0x00712223  72 0x00700393  76 0x10712023
  80 0x00800393  84 0x10712223  88 0x00300413  92 0x00822023
  96 0x00422483 100 0x0024f493 104 0xfe048ce3 108 0x0001a503
 112 0x0041a583 116 0x0401a603 120 0x0441a683 124 0x0000006f
}
foreach {a w} $prog { mwr [expr {$B + 0x08}] $a ; mwr [expr {$B + 0x0C}] $w }
puts "### imem loaded (32 words); releasing RV32 ###"
# release reset + run
mwr [expr {$B + 0x00}] 0x2
after 300
# sanity
puts "PC      = [format 0x%08x [lindex [mrd -value [expr {$B + 0x20}]] 0]]"
puts "STATUS  = [format 0x%08x [lindex [mrd -value [expr {$B + 0x04}]] 0]]"
puts "COMMITS = [format %u 0x[lindex [mrd -value [expr {$B + 0x2C}]] 0]]"
# read result registers x10..x13
proc rdreg {B n} { mwr [expr {$B + 0x18}] $n ; return [lindex [mrd -value [expr {$B + 0x1C}]] 0] }
set c00 [rdreg $B 10] ; set c01 [rdreg $B 11] ; set c10 [rdreg $B 12] ; set c11 [rdreg $B 13]
puts "BOARD  16x16 NPU GEMM:  C00=$c00  C01=$c01  C10=$c10  C11=$c11"
puts "GOLDEN (sim/ISS)     :  C00=39   C01=53   C10=17   C11=23"
if {$c00==39 && $c01==53 && $c10==17 && $c11==23} {
    puts ">>> BOARD-GEMM: PASS  (16x16 NPU on real XC7Z020 @ 30.3 MHz matches golden) <<<"
} else {
    puts ">>> BOARD-GEMM: MISMATCH <<<"
}
disconnect
puts "GEMM-TEST-COMPLETE"
