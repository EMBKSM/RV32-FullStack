# =====================================================================
# fix_icache_adapter_ip.tcl
# Vivado mis-inferred an AXI interface ('c') on the icache_axi_adapter IP from
# the ports c_arvalid / c_arready / c_rvalid (name looked like an AXI AR/R
# channel) and merged them with the real master ports -> direction-mismatch
# CRITICAL WARNINGs. Those ports are actually the cache_controller handshake
# (custom, not AXI), so we remove the bogus interface; the ports stay as plain
# conventional ports (correct for this internal sub-block).
#
# Run:  vivado -mode batch -source fix_icache_adapter_ip.tcl
# =====================================================================
set xml C:/work/github/RV32-FullStack/ip_repo/icache_axi_adapter/component.xml
ipx::open_core $xml
set core [ipx::current_core]

# drop the mis-inferred interface 'c'
foreach bif {c} {
  if {[llength [ipx::get_bus_interfaces $bif -of_objects $core -quiet]]} {
    ipx::remove_bus_interface $bif $core
    puts "removed mis-inferred bus interface: $bif"
  }
}

# removing the AXI interface leaves an orphan address space 'c' -> remove it too
foreach as {c} {
  set aso [ipx::get_address_spaces $as -of_objects $core -quiet]
  if {[llength $aso]} {
    ipx::remove_address_space $as $core
    puts "removed orphan address space: $as"
  }
}

# clk's ASSOCIATED_BUSIF may still reference the removed interface -> clear it
set clkif [ipx::get_bus_interfaces clk -of_objects $core -quiet]
if {[llength $clkif]} {
  catch { ipx::remove_bus_parameter ASSOCIATED_BUSIF $clkif }
}

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core
catch {ipx::check_integrity $core} ci
ipx::unload_core
puts "icache_axi_adapter IP cleaned -> $xml"
