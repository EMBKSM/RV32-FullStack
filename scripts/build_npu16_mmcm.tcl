# build_npu16_mmcm.tcl - insert a PL MMCM (clk_wiz) FCLK0(100)->106MHz, rewire the PL
# clock through it, and build the retiming design at the 106MHz constraint.
set OUTF 106.000
set_param general.maxThreads 8
puts "### MMCM BUILD START -> ${OUTF} MHz ###"
catch { close_project }
source C:/work/github/RV32-FullStack/scripts/package_platform_ip.tcl

open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
catch { upgrade_ip [get_ips -filter {IPDEF =~ *:rv32_platform:*}] }
# remove the harmful floorplan pblock from this build
catch { remove_files [get_files -quiet pblock_core.xdc] }

open_bd_design [get_files rv32_top.bd]
# FCLK0 = 100 MHz (MMCM input)
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] [get_bd_cells ps7]

# --- create the MMCM (clk_wiz) ---
catch { delete_bd_objs [get_bd_cells -quiet clk_wiz_0] }
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $OUTF \
  CONFIG.USE_LOCKED {true} \
  CONFIG.USE_RESET {false} \
] [get_bd_cells clk_wiz_0]

# --- rewire (order matters: add clk_in1 to FCLK0 net BEFORE removing loads) ---
# 1) clk_wiz input <- FCLK0 (add as a load of the existing net)
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins clk_wiz_0/clk_in1]
# 2) move the 4 original loads off FCLK0
set fnet [get_bd_nets -of_objects [get_bd_pins ps7/FCLK_CLK0]]
foreach pin {ps7/M_AXI_GP0_ACLK axi_smc/aclk rst_ps7_50M/slowest_sync_clk plat/S_AXI_ACLK} {
    disconnect_bd_net $fnet [get_bd_pins $pin]
}
# 3) drive them from the MMCM output (106 MHz)
foreach pin {ps7/M_AXI_GP0_ACLK axi_smc/aclk rst_ps7_50M/slowest_sync_clk plat/S_AXI_ACLK} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins $pin]
}
# 4) MMCM locked -> system reset
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_ps7_50M/dcm_locked]

validate_bd_design
save_bd_design
generate_target all [get_files rv32_top.bd]
puts "### MMCM in place; PL clock = ${OUTF} MHz (FCLK0=100->MMCM) ###"
close_bd_design [current_bd_design]

catch { set_property strategy Flow_PerfOptimized_high [get_runs synth_1] }
catch { set_property strategy Performance_Explore [get_runs impl_1] }
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
puts "### launched; waiting ... ###"
wait_on_run impl_1

set st [get_property STATUS [get_runs impl_1]]
set wns "n/a"; catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
puts "### MMCM status=$st  WNS @${OUTF}MHz = $wns ###"
catch { open_run impl_1 ; report_timing_summary -max_paths 10 -file C:/work/github/RV32-FullStack/flash/timing_mmcm.rpt }
set bit [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
if {$bit ne ""} { file copy -force [lindex $bit 0] C:/work/github/RV32-FullStack/flash/rv32_16x16_mmcm.bit }
puts "### MMCM-BUILD-COMPLETE out=${OUTF} WNS=$wns ###"
