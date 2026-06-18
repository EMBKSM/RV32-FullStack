# npu_integ.tcl - repackage rv32_platform (now incl. 6_NPU + NPU-wired mmio_bridge)
# and refresh it in the Zynq BD, then leave ready to synth.
puts "### NPU-INTEG PREP START ###"
catch { close_hw_target }
catch { disconnect_hw_server }
catch { close_project }
source C:/work/github/RV32-FullStack/scripts/package_platform_ip.tcl
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
set_property strategy {Vivado Synthesis Defaults}       [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults}  [get_runs impl_1]
set pip [get_ips -filter {IPDEF =~ *:rv32_platform:*}]
puts "### platform IP = $pip ###"
catch { upgrade_ip $pip }
generate_target all [get_files -quiet *rv32_top.bd]
puts "### NPU-INTEG PREP DONE ###"
