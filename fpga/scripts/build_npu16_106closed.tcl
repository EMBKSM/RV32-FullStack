# build_npu16_106closed.tcl
# Goal: CLOSE timing at 106 MHz properly (positive WNS), not just functionally pass.
# Key vs the old MMCM build: retiming synth (Flow_PerfOptimized_high) +
#   impl = Performance_ExplorePostRoutePhysOpt  (adds POST-ROUTE phys_opt, which is
#   what pulled the maxf build to Fmax 110.8 -> at 106 MHz expect ~+0.25..+0.40 ns).
# Run in the Vivado Tcl Console:
#   source C:/work/github/RV32-FullStack/fpga/scripts/build_npu16_106closed.tcl
# or batch:
#   vivado -mode batch -source C:/work/github/RV32-FullStack/fpga/scripts/build_npu16_106closed.tcl

set OUTF 106.000
set_param general.maxThreads 8
puts "### 106-CLOSE BUILD START -> ${OUTF} MHz  (retiming + post-route phys_opt) ###"

catch { close_project }
catch { source C:/work/github/RV32-FullStack/fpga/scripts/package_platform_ip.tcl }

open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
catch { upgrade_ip [get_ips -filter {IPDEF =~ *:rv32_platform:*}] }
catch { remove_files [get_files -quiet pblock_core.xdc] }

open_bd_design [get_files rv32_top.bd]
# FCLK0 = 100 MHz (MMCM input)
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] [get_bd_cells ps7]

# --- ensure the MMCM (clk_wiz_0) is present; insert only if missing (idempotent) ---
if {[llength [get_bd_cells -quiet clk_wiz_0]] == 0} {
    puts "### inserting MMCM clk_wiz_0 (100 -> ${OUTF}) ###"
    create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $OUTF \
        CONFIG.USE_LOCKED {true} \
        CONFIG.USE_RESET {false} ] [get_bd_cells clk_wiz_0]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins clk_wiz_0/clk_in1]
    set fnet [get_bd_nets -of_objects [get_bd_pins ps7/FCLK_CLK0]]
    foreach pin {ps7/M_AXI_GP0_ACLK axi_smc/aclk rst_ps7_50M/slowest_sync_clk plat/S_AXI_ACLK} {
        disconnect_bd_net $fnet [get_bd_pins $pin]
    }
    foreach pin {ps7/M_AXI_GP0_ACLK axi_smc/aclk rst_ps7_50M/slowest_sync_clk plat/S_AXI_ACLK} {
        connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins $pin]
    }
    connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_ps7_50M/dcm_locked]
} else {
    puts "### MMCM already present; reusing, set CLKOUT1=${OUTF} ###"
    set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $OUTF] [get_bd_cells clk_wiz_0]
}

validate_bd_design
save_bd_design
generate_target all [get_files rv32_top.bd]
close_bd_design [current_bd_design]
puts "### MMCM in place; PL clock = ${OUTF} MHz ###"

# --- the fix: retiming synth + aggressive impl WITH post-route phys_opt ---
catch { set_property strategy Flow_PerfOptimized_high            [get_runs synth_1] }
catch { set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1] }

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "### launched -- this takes ~30-40 min; leave it running ... ###"
wait_on_run impl_1

set st  [get_property STATUS [get_runs impl_1]]
set wns "n/a"; catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
set tns "n/a"; catch { set tns [get_property STATS.TNS [get_runs impl_1]] }
puts "### 106-CLOSE status=$st   WNS=$wns   TNS=$tns ###"

catch {
    open_run impl_1
    report_timing_summary -max_paths 10 -file C:/work/github/RV32-FullStack/fpga/flash/timing_106closed.rpt
    report_utilization              -file C:/work/github/RV32-FullStack/fpga/flash/util_106closed.rpt
}
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
if {$bit ne ""} { file copy -force [lindex $bit 0] C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_106closed.bit }

if {$wns ne "n/a" && $wns >= 0} {
    puts "### >>> 106 MHz CLOSED (WNS=$wns >= 0). Headline holds honestly. <<< ###"
} else {
    puts "### >>> 106 still negative (WNS=$wns). Fall back to 100 MHz headline. <<< ###"
}
puts "### 106-CLOSE-BUILD-COMPLETE  WNS=$wns  TNS=$tns ###"
