# =====================================================================
# package_bd_glue.tcl  -  package the BD glue + pipeline-register modules
# as individual user IPs (into the same ip_repo as the block IPs), so they
# can be dropped into a Block Design and wired to the leaf IPs by hand.
#
# Modules (one entity per file, in bd_assembly/):
#   mux2_32 mux3_32 orgate2 andn2            - datapath/control glue
#   id_decode_glue fencei_oneshot            - ID combinational glue / FENCE.I one-shot
#   ifid_reg idex_reg exmem_reg memwb_reg    - pipeline boundary registers
#
# Run (separate batch invocation; does not touch your open GUI project):
#   "C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source C:\work\github\RV32-FullStack\package_bd_glue.tcl
#
# Then in the design project:  set ip_repo_paths -> update_ip_catalog  (see below)
# =====================================================================
set PART   xc7z020clg400-1
set ROOT   C:/work/github/RV32-FullStack
set GLUE   $ROOT/bd_assembly
set REPO   $ROOT/ip_repo
set BUILD  $ROOT/ip_build
set VENDOR user
set LIB    rv32

file mkdir $REPO
file mkdir $BUILD

# { ip_name == top entity == file basename }
set mods {
  mux2_32 mux3_32 orgate2 andn2
  id_decode_glue fencei_oneshot
  ifid_reg idex_reg exmem_reg memwb_reg
}

proc pkg {name} {
  global PART GLUE REPO BUILD VENDOR LIB
  puts "============================================================"
  puts " packaging glue IP: $name"
  puts "============================================================"
  set pdir $BUILD/$name
  file delete -force $pdir
  create_project -force prj_$name $pdir -part $PART
  add_files -norecurse $GLUE/$name.vhd
  set_property top $name [get_filesets sources_1]
  update_compile_order -fileset sources_1
  set root $REPO/$name
  file delete -force $root
  file mkdir $root
  ipx::package_project -root_dir $root -vendor $VENDOR -library $LIB \
      -taxonomy /UserIP -import_files -force -set_current true
  set core [ipx::current_core]
  set_property name         $name              $core
  set_property version      1.0                $core
  set_property display_name "$name (RV32 BD glue)" $core
  set_property description   "RV32-FullStack BD glue: $name" $core
  set_property vendor_display_name "RV32-FullStack" $core
  ipx::create_xgui_files $core
  ipx::update_checksums  $core
  ipx::save_core         $core
  catch {ipx::check_integrity $core} ci
  close_project
  puts "   -> $root/component.xml"
}

set ok 0
set fail {}
foreach m $mods {
  if {[catch {pkg $m} msg]} {
    puts "   *** FAILED: $m : $msg"; lappend fail $m; catch {close_project}
  } else { incr ok }
}

puts "============================================================"
puts " BD glue packaging done: $ok packaged, [llength $fail] failed"
if {[llength $fail] > 0} { puts " FAILED: $fail" }
puts " IP repository: $REPO   (now holds the 30 block IPs + these glue IPs)"
puts ""
puts " In your design project:"
puts "   set_property ip_repo_paths $REPO \[current_project\]"
puts "   update_ip_catalog"
puts "============================================================"
