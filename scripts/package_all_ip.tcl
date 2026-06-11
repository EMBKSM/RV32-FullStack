# =====================================================================
# package_all_ip.tcl  -  batch-package every RV32-FullStack block as an IP
# Creates one user IP per block in an IP repository (ip_repo/<name>), so each
# component can be reused / dropped into IP Integrator. Leaf blocks are packaged
# standalone; the three wrappers (icache_unit, cache_unit, rv32_core) are
# packaged together with their sub-sources.
#
# EXCLUDED:
#   axi_slave_mem  - behavioral simulation memory (not synthesizable)
#   rv32_soc       - sim top (embeds axi_slave_mem + preload ports)
#
# HOW TO RUN (recommended: a separate batch invocation so your open GUI
# project is not disturbed). From a Vivado command prompt:
#     cd C:\work\github\RV32-FullStack
#     vivado -mode batch -source package_all_ip.tcl
#
# Afterwards, point a project at the repo to use the IPs:
#     set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
#     update_ip_catalog
# =====================================================================

# ---------------- configuration ----------------
set PART   xc7z020clg400-1
set ROOT   C:/work/github/RV32-FullStack
set RTL    $ROOT/ip_workspace
set REPO   $ROOT/ip_repo
set BUILD  $ROOT/ip_build
set VENDOR user
set LIB    rv32

file mkdir $REPO
file mkdir $BUILD

# ---------------- block table: { ip_name  top_entity  {src files (rel to RTL)} } ----------------
# (ip_name == top_entity; note program_counter.vhd's entity is pc_reg)
set blocks {
  { pc_adder           pc_adder           {0_IF/0_PC/pc_adder.vhd} }
  { next_pc_mux        next_pc_mux        {0_IF/0_PC/next_pc_mux.vhd} }
  { pc_reg             pc_reg             {0_IF/0_PC/program_counter.vhd} }
  { addr_aligner       addr_aligner       {0_IF/1_adress_split/address_aligner.vhd} }
  { comparator         comparator         {0_IF/1_adress_split/comparator.vhd} }
  { tag_array          tag_array          {0_IF/1_adress_split/tag_array.vhd} }
  { cache_controller   cache_controller   {0_IF/1_adress_split/cache_controller.vhd} }
  { icache_data_array  icache_data_array  {0_IF/1_adress_split/icache_data_array.vhd} }
  { icache_axi_adapter icache_axi_adapter {0_IF/1_adress_split/icache_axi_adapter.vhd} }
  { control_unit       control_unit       {1_ID/control_unit.vhd} }
  { csr_file           csr_file           {1_ID/csr_file.vhd} }
  { hazard_unit        hazard_unit        {1_ID/hazard_unit.vhd} }
  { imm_gen            imm_gen            {1_ID/imm_gen.vhd} }
  { register_file      register_file      {1_ID/register_file.vhd} }
  { alu                alu                {2_EX/alu.vhd} }
  { alu_control        alu_control        {2_EX/alu_control.vhd} }
  { bcu                bcu                {2_EX/bcu.vhd} }
  { forwarding_unit    forwarding_unit    {2_EX/forwarding_unit.vhd} }
  { trap_unit          trap_unit          {2_EX/trap_unit.vhd} }
  { read_aligner       read_aligner       {3_Mem/read_aligner.vhd} }
  { write_strobe_gen   write_strobe_gen   {3_Mem/write_strobe_gen.vhd} }
  { dtag_array         dtag_array         {3_Mem/dtag_array.vhd} }
  { ddata_array        ddata_array        {3_Mem/ddata_array.vhd} }
  { dcache_controller  dcache_controller  {3_Mem/dcache_controller.vhd} }
  { axi_master         axi_master         {3_Mem/axi_master.vhd} }
  { result_mux         result_mux         {4_WB/result_mux.vhd} }
  { pipeline_reg       pipeline_reg       {common/pipeline_reg.vhd} }

  { icache_unit        icache_unit        {
      0_IF/1_adress_split/icache_unit.vhd
      0_IF/1_adress_split/address_aligner.vhd
      0_IF/1_adress_split/tag_array.vhd
      0_IF/1_adress_split/comparator.vhd
      0_IF/1_adress_split/cache_controller.vhd
      0_IF/1_adress_split/icache_data_array.vhd
      0_IF/1_adress_split/icache_axi_adapter.vhd } }

  { cache_unit         cache_unit         {
      3_Mem/cache_unit.vhd
      3_Mem/dtag_array.vhd
      3_Mem/ddata_array.vhd
      3_Mem/dcache_controller.vhd
      3_Mem/axi_master.vhd } }

  { rv32_core          rv32_core          {
      rv32_core.vhd
      0_IF/0_PC/program_counter.vhd
      0_IF/0_PC/pc_adder.vhd
      0_IF/0_PC/next_pc_mux.vhd
      1_ID/control_unit.vhd
      1_ID/imm_gen.vhd
      1_ID/register_file.vhd
      1_ID/hazard_unit.vhd
      1_ID/csr_file.vhd
      2_EX/alu.vhd
      2_EX/alu_control.vhd
      2_EX/bcu.vhd
      2_EX/forwarding_unit.vhd
      2_EX/trap_unit.vhd
      3_Mem/read_aligner.vhd
      3_Mem/write_strobe_gen.vhd
      4_WB/result_mux.vhd } }
}

# ---------------- packaging proc ----------------
proc pkg {ip_name top files} {
  global PART RTL REPO BUILD VENDOR LIB
  puts "============================================================"
  puts " packaging IP: $ip_name   (top entity = $top)"
  puts "============================================================"

  set abs {}
  foreach f $files { lappend abs $RTL/$f }

  set pdir $BUILD/$ip_name
  file delete -force $pdir
  create_project -force prj_$ip_name $pdir -part $PART

  add_files -norecurse $abs
  set_property top $top [get_filesets sources_1]
  update_compile_order -fileset sources_1

  set root $REPO/$ip_name
  file delete -force $root
  file mkdir $root

  ipx::package_project -root_dir $root -vendor $VENDOR -library $LIB \
      -taxonomy /UserIP -import_files -force -set_current true

  set core [ipx::current_core]
  set_property name         $ip_name              $core
  set_property version      1.0                   $core
  set_property display_name "$ip_name (RV32)"     $core
  set_property description   "RV32-FullStack block: $ip_name" $core
  set_property vendor_display_name "RV32-FullStack" $core

  ipx::create_xgui_files $core
  ipx::update_checksums  $core
  ipx::save_core         $core
  catch {ipx::check_integrity $core} ci   ;# advisory only; never block saving

  close_project
  puts "   -> $root/component.xml"
}

# ---------------- run ----------------
set ok 0
set fail {}
foreach b $blocks {
  set nm  [lindex $b 0]
  set top [lindex $b 1]
  set fs  [lindex $b 2]
  if {[catch {pkg $nm $top $fs} msg]} {
    puts "   *** FAILED: $nm : $msg"
    lappend fail $nm
    catch {close_project}
  } else {
    incr ok
  }
}

puts "============================================================"
puts " IP packaging done: $ok packaged, [llength $fail] failed"
if {[llength $fail] > 0} { puts " FAILED: $fail" }
puts " IP repository: $REPO"
puts ""
puts " To use these IPs in a project:"
puts "   set_property ip_repo_paths $REPO \[current_project\]"
puts "   update_ip_catalog"
puts "============================================================"
