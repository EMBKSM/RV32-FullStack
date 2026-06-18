# lutram_prep.tcl - repackage platform IP (with LUTRAM cache arrays) and refresh
# it in the Zynq BD project, reset synth/impl strategies to defaults.
# Run from the Vivado Tcl console:  source .../lutram_prep.tcl
puts "### PREP START ###"
# 0) close any open project so the packaging project can be created
catch { close_project }
# 1) repackage rv32_platform from ip_workspace (re-imports edited ddata/icache arrays)
source C:/work/github/RV32-FullStack/scripts/package_platform_ip.tcl
puts "### REPACKAGED rv32_platform ###"
# 2) open the Zynq project and refresh the IP catalog
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
update_ip_catalog -rebuild
# 3) reset strategies (AreaOptimized gave nothing and slowed P&R)
set_property strategy {Vivado Synthesis Defaults}       [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults}  [get_runs impl_1]
# 4) regenerate the BD output products so the new platform RTL repopulates ipshared
set bdf [get_files -quiet *rv32_top.bd]
puts "### regenerating BD targets: $bdf ###"
generate_target all $bdf
puts "### PREP DONE ###"
