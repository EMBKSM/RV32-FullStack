# =====================================================================
# build_zynq_project.tcl  -  fresh Vivado project + Zynq PS block design that
# drives the rv32_platform IP over AXI4-Lite. Clean (only the IP + PS), so no
# duplicate-entity clash with the sim project's loose RTL.
#
# PREREQ: package_platform_ip.tcl already run (rv32_platform IP in ip_repo).
# RUN in BATCH:
#   "C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source C:\work\github\RV32-FullStack\build_zynq_project.tcl
# =====================================================================
set ROOT C:/work/github/RV32-FullStack
set REPO $ROOT/ip_repo
set PROJ $ROOT/vivado_zynq
set BD   rv32_top
set PART xc7z020clg400-1
set BRD  digilentinc.com:zybo-z7-20:part0:1.0

create_project -force rv32_zynq $PROJ -part $PART
catch { set_property board_part $BRD [current_project] }   ;# board preset (if installed)
set_property ip_repo_paths $REPO [current_project]
update_ip_catalog

create_bd_design $BD
current_bd_design [get_bd_designs $BD]

# ---- Zynq PS (apply Zybo board preset: DDR/MIO/clocks) ----
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]
# ensure a general-purpose AXI master + a fabric clock are enabled
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1}] [get_bd_cells ps7]

# ---- our PL subsystem IP ----
create_bd_cell -type ip -vlnv user:rv32:rv32_platform:1.0 plat

# ---- auto-connect PS M_AXI_GP0 -> plat S_AXI (adds SmartConnect + reset) ----
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Clk_master "Auto" Clk_slave "Auto" Clk_xbar "Auto" \
             Master "/ps7/M_AXI_GP0" Slave "/plat/S_AXI" \
             intc_ip "New AXI SmartConnect" master_apm "0"} \
    [get_bd_intf_pins plat/S_AXI]

# ---- board GPIO to external ports ----
make_bd_pins_external  [get_bd_pins plat/led_o]
make_bd_pins_external  [get_bd_pins plat/sw_i]
make_bd_pins_external  [get_bd_pins plat/btn_i]

assign_bd_address
regenerate_bd_layout
save_bd_design
validate_bd_design

# ---- HDL wrapper + set top ----
set wrap [make_wrapper -files [get_files $BD.bd] -top -force]
add_files -norecurse $wrap
update_compile_order -fileset sources_1
puts "DONE: project=$PROJ  BD=$BD  wrapper added & set as top (check validate result above)."
puts "Next: add XDC for led_o/sw_i/btn_i pins, then Run Synthesis -> Implementation -> Bitstream."
