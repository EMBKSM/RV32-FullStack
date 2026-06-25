# =====================================================================
# package_platform_ip.tcl  -  package rv32_platform (whole PL subsystem) as a
# user IP with an inferred AXI4-Lite slave (S_AXI_*) + clk/reset, plus LED/SW/BTN
# as plain ports (made external in the block design). For the Zynq PS BD.
#
# Run in BATCH (does not disturb your open GUI project):
#   "C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source C:\work\github\RV32-FullStack\package_platform_ip.tcl
# Then in the BD project: set_property ip_repo_paths .../ip_repo; update_ip_catalog
# =====================================================================
set PART  xc7z020clg400-1
set RTL   C:/work/github/RV32-FullStack/rtl
set REPO  C:/work/github/RV32-FullStack/ip_repo
set BUILD C:/work/github/RV32-FullStack/ip_build

create_project -force prj_rv32_platform $BUILD/rv32_platform -part $PART

# all PL RTL (platform pulls in core + I$/D$ + memories + mmio + ctrl)
add_files -norecurse [glob $RTL/*.vhd $RTL/*/*.vhd $RTL/*/*/*.vhd]
# rv32_soc is the sim-only top (embeds prog ports) - not needed in this IP
remove_files [get_files -quiet *rv32_soc.vhd]
set_property top rv32_platform [get_filesets sources_1]
update_compile_order -fileset sources_1

set root $REPO/rv32_platform
file delete -force $root
file mkdir $root
ipx::package_project -root_dir $root -vendor user -library rv32 \
    -taxonomy /UserIP -import_files -force -set_current true
set core [ipx::current_core]
set_property name         rv32_platform $core
set_property version      1.0 $core
set_property display_name "rv32_platform (RV32 host-controlled SoC)" $core
set_property description   "RV32I CPU + I\$/D\$ + MMIO(LED/SW/BTN) + AXI-Lite control slave" $core
set_property vendor_display_name "RV32-FullStack" $core
ipx::create_xgui_files $core
ipx::update_checksums  $core
ipx::save_core         $core
catch {ipx::check_integrity $core} ci
close_project
puts "DONE: rv32_platform IP -> $root/component.xml"
puts " Check log: S_AXI_* should be inferred as an aximm slave interface."
