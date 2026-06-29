# build_npu16_100mhz.tcl - rebuild the 16x16 NPU SoC with the PIPELINED C-readback
# (256:1 mux split into col/row/finalize stages) targeting a 100 MHz PL clock.
# Batch:  vivado -mode batch -source scripts/build_npu16_100mhz.tcl
set_param general.maxThreads 8
puts "### BUILD-100MHZ START ###"
catch { close_project }

# 1) repackage platform IP from edited ip_workspace RTL (npu_top read pipeline + bridge stall)
source C:/work/github/RV32-FullStack/fpga/scripts/package_platform_ip.tcl

# 2) reopen Zynq BD project, refresh the platform IP
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
set pip [get_ips -filter {IPDEF =~ *:rv32_platform:*}]
puts "### platform IP = $pip ###"
catch { upgrade_ip $pip }
# A same-version IP re-package otherwise reuses the CACHED netlist, so an edited
# NPU size / GPU lane count silently does NOT take (build keeps making 16x16).
# NUKE the project IP cache + the platform IP's generated products so the fresh
# 12x12 source is forced through synthesis.
set R C:/work/github/RV32-FullStack/vivado_zynq
catch { config_ip_cache -disable_cache }
catch { config_ip_cache -clear_output_repo }
catch { config_ip_cache -clear_local_cache }
catch { foreach f [glob -nocomplain $R/rv32_zynq.cache/ip/*] { file delete -force $f } }
catch { file delete -force $R/rv32_zynq.gen/sources_1/bd/rv32_top/ip/rv32_top_plat_0 }
catch { file delete -force $R/rv32_zynq.srcs/sources_1/bd/rv32_top/ip/rv32_top_plat_0/rv32_top_plat_0.dcp }
catch { reset_target all [get_files rv32_top.bd] }
catch { foreach rr [get_runs] { if {[string match *plat* $rr]} { catch { reset_run $rr } } } }
puts "### NUKED IP cache + regenerating platform IP from 12x12 source ###"

# 3) set PL clock target = 100 MHz (timing analysis target; FSBL/JTAG sets the real FCLK0)
open_bd_design [get_files rv32_top.bd]
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] [get_bd_cells ps7]
validate_bd_design
save_bd_design
generate_target all [get_files rv32_top.bd]
puts "### FCLK0 requested=100  ACT = [get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] MHz ###"
close_bd_design [current_bd_design]

# 3b) force the synthesis/impl top back to the BD wrapper (a stray module such as
#     gpu_top can get left as 'top' after manual RTL probing -> builds the wrong thing)
set_property top rv32_top_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "### top = [get_property top [get_filesets sources_1]] ###"

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
    report_timing_summary -max_paths 8 -file C:/work/github/RV32-FullStack/fpga/flash/timing_100mhz.rpt
}
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
puts "### bitstream = $bit ###"
if {$bit ne ""} { file copy -force [lindex $bit 0] C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_100mhz.bit }
puts "### BUILD-100MHZ-COMPLETE WNS=$wns ###"
