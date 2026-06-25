# Analyze current placement to design a core Pblock (route-dominated hazard path).
open_checkpoint C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/rv32_top_wrapper_routed.dcp
puts "### CLOCK REGIONS (name : rect) ###"
foreach cr [lsort [get_clock_regions]] {
    puts "  $cr"
}
puts "### device SLICE/DSP extent ###"
set sl [get_sites -filter {SITE_TYPE==SLICEL || SITE_TYPE==SLICEM}]
puts "  #SLICE sites = [llength $sl]"
set ds [get_sites -filter {SITE_TYPE=~DSP*}]
puts "  #DSP sites = [llength $ds]"
# core placement spread
set ccells [get_cells -hier -filter {NAME =~ *plat/U0/u_core* && IS_PRIMITIVE}]
puts "### u_core primitives = [llength $ccells] ###"
set csites [get_sites -quiet -of $ccells]
set xs {}; set ys {}
foreach s $csites { regexp {X(\d+)Y(\d+)} $s -> x y; lappend xs $x; lappend ys $y }
if {[llength $xs]} {
  set xs [lsort -integer $xs]; set ys [lsort -integer $ys]
  puts "  u_core sites span: X[lindex $xs 0]..[lindex $xs end]  Y[lindex $ys 0]..[lindex $ys end]  (n=[llength $csites])"
}
# NPU DSP spread (where the array forces placement)
set ncells [get_cells -hier -filter {NAME =~ *u_npu* && PRIMITIVE_TYPE =~ DSP*}]
set nsites [get_sites -quiet -of $ncells]
set nxs {}; set nys {}
foreach s $nsites { regexp {X(\d+)Y(\d+)} $s -> x y; lappend nxs $x; lappend nys $y }
if {[llength $nxs]} {
  set nxs [lsort -integer $nxs]; set nys [lsort -integer $nys]
  puts "  NPU DSP span: X[lindex $nxs 0]..[lindex $nxs end]  Y[lindex $nys 0]..[lindex $nys end]  (n=[llength $nsites])"
}
puts "### ANALYZE-PLACE-DONE ###"
