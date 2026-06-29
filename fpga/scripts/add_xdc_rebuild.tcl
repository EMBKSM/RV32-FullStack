# add_xdc_rebuild.tcl - the unified design placed+routed (202 DSP, 0 failed nets)
# but write_bitstream hit DRC NSTD-1/UCIO-1: the board pin XDCs weren't in the
# impl constraint set. Add them (correct _0-suffixed port names) and re-run impl
# -> write_bitstream. Synth (202 DSP) is reused; only place/route/bitstream re-run.
set R C:/work/github/RV32-FullStack
open_project $R/vivado_zynq/rv32_zynq.xpr
set cs [current_fileset -constrset]
puts "### constrset = $cs ###"
catch { add_files -fileset $cs -norecurse [list \
        $R/fpga/constraints/zybo_z7_20_gpio.xdc \
        $R/fpga/constraints/zybo_z7_20_pmod.xdc ] }
foreach x {zybo_z7_20_gpio.xdc zybo_z7_20_pmod.xdc} {
    catch { set_property used_in_synthesis     false [get_files $x] }
    catch { set_property used_in_implementation true  [get_files $x] }
}
puts "### impl constraint files = [get_files -of [get_filesets $cs]] ###"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
set wns "n/a"; catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
puts "### impl_1 status=$st WNS=$wns ###"
set bit [glob -nocomplain $R/vivado_zynq/rv32_zynq.runs/impl_1/*.bit]
puts "### bitstream = $bit ###"
if {$bit ne ""} {
    file copy -force [lindex $bit 0] $R/fpga/flash/rv32_unified_100mhz.bit
    puts "### COPIED -> fpga/flash/rv32_unified_100mhz.bit ###"
}
puts "### REBUILD DONE ###"
exit
