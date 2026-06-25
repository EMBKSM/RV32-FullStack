# build_npu16_maxf.tcl - push Fmax beyond 100 MHz. Set FREQ, enable synth retiming
# (Flow_PerfOptimized_high) + aggressive impl. Batch: vivado -mode batch -source this.tcl
set FREQ 125
set_param general.maxThreads 8
puts "### MAXF BUILD START  target=${FREQ} MHz ###"
catch { close_project }

source C:/work/github/RV32-FullStack/fpga/scripts/package_platform_ip.tcl

open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
catch { upgrade_ip [get_ips -filter {IPDEF =~ *:rv32_platform:*}] }

open_bd_design [get_files rv32_top.bd]
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $FREQ] [get_bd_cells ps7]
validate_bd_design
save_bd_design
generate_target all [get_files rv32_top.bd]
puts "### FCLK0 req=${FREQ}  ACT=[get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] MHz ###"
close_bd_design [current_bd_design]

# synth with retiming + perf; impl explore + post-route phys_opt
catch { set_property strategy Flow_PerfOptimized_high [get_runs synth_1] }
catch { set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1] }
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "### launched; waiting ... ###"
wait_on_run impl_1

set st [get_property STATUS [get_runs impl_1]]
set wns "n/a"; catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
puts "### MAXF status=$st  WNS @${FREQ}MHz = $wns ###"
catch { open_run impl_1 ; report_timing_summary -max_paths 15 -file C:/work/github/RV32-FullStack/fpga/flash/timing_maxf.rpt }
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
if {$bit ne ""} { file copy -force [lindex $bit 0] C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_maxf.bit }
puts "### MAXF-BUILD-COMPLETE freq=${FREQ} WNS=$wns ###"
