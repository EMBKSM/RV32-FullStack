# =====================================================================
# fix_cache_axi_iface.tcl
# Strip the auto-inferred AXI 'interface_aximm' (and its address space) from
# the icache_unit / cache_unit IPs so their AXI ports become PLAIN pins. This
# lets the BD script connect them pin-by-pin to the behavioral memory
# (axi_slave_mem, a module reference with plain pins). clk/reset stay as
# signal interfaces (fine). Run once, then update_ip_catalog.
#
#   "C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source C:\work\github\RV32-FullStack\fix_cache_axi_iface.tcl
# =====================================================================
foreach xml {
  C:/work/github/RV32-FullStack/ip_repo/icache_unit/component.xml
  C:/work/github/RV32-FullStack/ip_repo/cache_unit/component.xml
} {
  ipx::open_core $xml
  set core [ipx::current_core]
  set nm [get_property name $core]
  foreach bif {interface_aximm} {
    if {[llength [ipx::get_bus_interfaces $bif -of_objects $core -quiet]]} {
      ipx::remove_bus_interface $bif $core
      puts "  $nm: removed bus interface $bif"
    }
  }
  foreach as {interface_aximm} {
    if {[llength [ipx::get_address_spaces $as -of_objects $core -quiet]]} {
      ipx::remove_address_space $as $core
      puts "  $nm: removed address space $as"
    }
  }
  set clkif [ipx::get_bus_interfaces clk -of_objects $core -quiet]
  if {[llength $clkif]} { catch { ipx::remove_bus_parameter ASSOCIATED_BUSIF $clkif } }
  ipx::create_xgui_files $core
  ipx::update_checksums $core
  ipx::save_core $core
  catch {ipx::check_integrity $core} ci
  ipx::unload_core
  puts "  $nm: saved (AXI now plain pins)"
}
puts "DONE. In your project run:  update_ip_catalog -rebuild"
