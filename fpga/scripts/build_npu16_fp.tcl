# build_npu16_fp.tcl - floorplan attempt: compact core Pblock + 125MHz target + retiming.
set FREQ 125
set_param general.maxThreads 8
puts "### FP BUILD START  target=${FREQ} MHz + core Pblock ###"
catch { close_project }
source C:/work/github/RV32-FullStack/fpga/scripts/package_platform_ip.tcl

open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
catch { upgrade_ip [get_ips -filter {IPDEF =~ *:rv32_platform:*}] }

# add the core Pblock constraint (impl-only)
set fp C:/work/github/RV32-FullStack/fpga/flash/pblock_core.xdc
if {[lsearch [get_files -quiet] *pblock_core.xdc] < 0} {
    add_files -fileset constrs_1 -norecurse $fp
}
catch { set_property used_in_synthesis false [get_files pblock_core.xdc] }

open_bd_design [get_files rv32_top.bd]
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $FREQ] [get_bd_cells ps7]
validate_bd_design
save_bd_design
generate_target all [get_files rv32_top.bd]
puts "### FCLK0 ACT=[get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] MHz ###"
close_bd_design [current_bd_design]

catch { set_property strategy Flow_PerfOptimized_high [get_runs synth_1] }
catch { set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1] }
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "### launched; waiting ... ###"
wait_on_run impl_1

set st [get_property STATUS [get_runs impl_1]]
set wns "n/a"; catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
puts "### FP status=$st  WNS @${FREQ}MHz = $wns ###"
catch { open_run impl_1 ; report_timing_summary -max_paths 12 -file C:/work/github/RV32-FullStack/fpga/flash/timing_fp.rpt }
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
if {$bit ne ""} { file copy -force [lindex $bit 0] C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_fp.bit }
puts "### FP-BUILD-COMPLETE freq=${FREQ} WNS=$wns ###"
