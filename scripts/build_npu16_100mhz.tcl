# build_npu16_100mhz.tcl - rebuild the 16x16 NPU SoC with the PIPELINED C-readback
# (256:1 mux split into col/row/finalize stages) targeting a 100 MHz PL clock.
# Batch:  vivado -mode batch -source scripts/build_npu16_100mhz.tcl
set_param general.maxThreads 8
puts "### BUILD-100MHZ START ###"
catch { close_project }

# 1) repackage platform IP from edited ip_workspace RTL (npu_top read pipeline + bridge stall)
source C:/work/github/RV32-FullStack/scripts/package_platform_ip.tcl

# 2) reopen Zynq BD project, refresh the platform IP
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
set pip [get_ips -filter {IPDEF =~ *:rv32_platform:*}]
puts "### platform IP = $pip ###"
catch { upgrade_ip $pip }

# 3) set PL clock target = 100 MHz (timing analysis target; FSBL/JTAG sets the real FCLK0)
open_bd_design [get_files rv32_top.bd]
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] [get_bd_cells ps7]
validate_bd_design
save_bd_design
generate_target all [get_files rv32_top.bd]
puts "### FCLK0 requested=100  ACT = [get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] MHz ###"
close_bd_design [current_bd_design]

# 4) aggressive timing strategy (Explore placement + post-route phys_opt) to push Fmax
catch { set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1] }
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "### launched synth->impl->bitstream; waiting ... ###"
wait_on_run impl_1

# 5) report
set st   [get_property STATUS   [get_runs impl_1]]
set prog [get_property PROGRESS [get_runs impl_1]]
puts "### impl_1 status=$st progress=$prog ###"
set wns "n/a"
catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
puts "### WNS (target 10ns / 100MHz) = $wns ###"
catch {
    open_run impl_1
    report_timing_summary -max_paths 8 -file C:/work/github/RV32-FullStack/flash/timing_100mhz.rpt
}
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
puts "### bitstream = $bit ###"
if {$bit ne ""} { file copy -force [lindex $bit 0] C:/work/github/RV32-FullStack/flash/rv32_16x16_100mhz.bit }
puts "### BUILD-100MHZ-COMPLETE WNS=$wns ###"
