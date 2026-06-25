# build_npu16.tcl - integrate the 16x16 hybrid NPU into the platform and build a bitstream.
# Repackages rv32_platform (now: bridge -> npu_top16, + parameterized NPU RTL), refreshes the
# IP in the Zynq BD, then launches synth -> impl -> write_bitstream (non-blocking).
# Source from the open Vivado Tcl console:  source C:/work/github/RV32-FullStack/fpga/scripts/build_npu16.tcl
puts "### BUILD-NPU16 START ###"
catch { close_design }
catch { close_project }

# 1) repackage the platform IP from the edited RTL (creates its own project, closes it)
source C:/work/github/RV32-FullStack/fpga/scripts/package_platform_ip.tcl

# 2) reopen the Zynq BD project and refresh the platform IP
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
set pip [get_ips -filter {IPDEF =~ *:rv32_platform:*}]
puts "### platform IP = $pip ###"
catch { upgrade_ip $pip }
generate_target all [get_files -quiet *rv32_top.bd]

# 3) rebuild from scratch: reset synth, launch impl through bitstream
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
puts "### LAUNCHED: synth_1 -> impl_1 -> write_bitstream (16x16, 220 DSP) ###"
puts "### BUILD-NPU16 LAUNCH DONE ###"
