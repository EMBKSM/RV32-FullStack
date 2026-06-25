# =====================================================================
# run_bitstream.tcl  -  add GPIO constraints, then synth -> impl -> bitstream
# for the Zynq BD project (vivado_zynq / rv32_zynq).
#   "C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source C:\work\github\RV32-FullStack\run_bitstream.tcl
# =====================================================================
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr

add_files -fileset constrs_1 -norecurse C:/work/github/RV32-FullStack/fpga/constraints/zybo_z7_20_gpio.xdc
update_compile_order -fileset sources_1

# synthesis
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "*** SYNTHESIS FAILED ***"
    error "synth_1 did not complete"
}
puts "=== synthesis done ==="

# implementation + bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "*** IMPLEMENTATION/BITSTREAM FAILED ***"
    error "impl_1 did not complete"
}
puts "=== implementation + bitstream done ==="

# report
open_run impl_1
puts "---- timing summary (WNS) ----"
puts "WNS = [get_property STATS.WNS [get_runs impl_1]]"
puts "---- utilization ----"
report_utilization -hierarchical -file C:/work/github/RV32-FullStack/vivado_zynq/util_impl.rpt
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
puts "BITSTREAM: $bit"
