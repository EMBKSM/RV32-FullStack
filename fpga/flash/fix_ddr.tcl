puts "=== DDR DQS fix: set DQS_TO_CLK_DELAY = 0.0, regenerate ps7_init ==="
if {[catch {open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr} e]} {
    puts "OPEN_PROJECT FAILED: $e"
    puts ">>> If the project is LOCKED, close the Vivado GUI and re-run."
    exit 1
}
set bd [get_files *rv32_top.bd]
puts "bd file: $bd"
open_bd_design $bd
set ps [get_bd_cells -filter {VLNV =~ "*processing_system7*"}]
puts "PS7 cell: $ps"
puts "DQS_TO_CLK before: [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 $ps] [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 $ps] [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 $ps] [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 $ps]"
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} ] $ps
puts "DQS_TO_CLK after : [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 $ps] [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 $ps] [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 $ps] [get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 $ps]"
if {[catch {validate_bd_design} e]} { puts "validate warn: $e" }
save_bd_design
if {[catch {generate_target all $bd} e]} { puts "generate_target: $e" }
# locate regenerated ps7_init.tcl
set found [glob -nocomplain C:/work/github/RV32-FullStack/vivado_zynq/*.gen/sources_1/bd/rv32_top/ip/*/ps7_init.tcl]
puts "ps7_init.tcl: $found"
puts "=== DONE ==="
close_project
