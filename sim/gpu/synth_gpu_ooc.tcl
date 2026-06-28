# OOC synthesis of the SIMT-lite GPU -> resource report
set R C:/work/github/RV32-FullStack
read_vhdl -vhdl2008 [list \
  $R/rtl/gpu/gpu_pkg.vhd $R/rtl/gpu/gpu_lane.vhd \
  $R/rtl/gpu/gpu_core.vhd $R/rtl/gpu/gpu_top.vhd]
synth_design -mode out_of_context -top gpu_top -part xc7z020clg400-1
report_utilization -file $R/_gpu_util.rpt
puts "=====================  GPU OOC UTILIZATION  ====================="
report_utilization
puts "=====================  GPU OOC synth DONE  ====================="
