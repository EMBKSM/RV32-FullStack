# Inspect the BD clock topology before inserting the MMCM.
catch { close_project }
open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr
open_bd_design [get_files rv32_top.bd]
puts "### BD CELLS ###"
foreach c [get_bd_cells] { puts "  CELL $c : [get_property VLNV $c]" }
puts "### FCLK_CLK0 net + loads ###"
set p [get_bd_pins -quiet ps7/FCLK_CLK0]
set net [get_bd_nets -quiet -of_objects $p]
puts "  net = $net"
foreach pin [get_bd_pins -quiet -of_objects $net] { puts "  LOAD $pin" }
puts "### FCLK_RESET0_N net + loads ###"
set rp [get_bd_pins -quiet ps7/FCLK_RESET0_N]
set rnet [get_bd_nets -quiet -of_objects $rp]
foreach pin [get_bd_pins -quiet -of_objects $rnet] { puts "  RLOAD $pin" }
puts "### reset cell config ###"
foreach c [get_bd_cells -quiet -filter {VLNV =~ *proc_sys_reset*}] {
    puts "  RESET cell = $c"
    foreach pn {slowest_sync_clk ext_reset_in aux_reset_in dcm_locked} {
        puts "    pin $pn : net=[get_bd_nets -quiet -of_objects [get_bd_pins -quiet $c/$pn]]"
    }
}
puts "### M_AXI_GP0_ACLK ###"
puts "  net=[get_bd_nets -quiet -of_objects [get_bd_pins -quiet ps7/M_AXI_GP0_ACLK]]"
puts "### INSPECT-DONE ###"
