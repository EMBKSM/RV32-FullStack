set R C:/work/github/RV32-FullStack
read_vhdl -vhdl2008 $R/rtl/soc/rv32_shared.vhd
synth_design -mode out_of_context -top rv32_shared -part xc7z020clg400-1 -directive RuntimeOptimized
report_utilization -file $R/_shared_util.rpt
puts "================  rv32_shared OOC UTILIZATION  ================"
puts [report_utilization -return_string]
