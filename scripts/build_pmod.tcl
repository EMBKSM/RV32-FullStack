# =====================================================================
# build_pmod.tcl  -  ONE-FILE PL build for the RV32 Pmod-peripheral platform.
# Replaces the old run_*.bat wrappers + integrate/synth tcl scripts.
#
# Stages (default: all):  package -> bd -> synth
#   package : re-package ip_workspace into the user:rv32:rv32_platform IP
#   bd      : refresh the BD's plat cell + make ja_io..je_io external
#   synth   : add Pmod XDC, GLOBAL-synthesis, impl, write_bitstream
#
# Run from the repo root:
#   "C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts\build_pmod.tcl
#   ... -source scripts\build_pmod.tcl -tclargs bd      ;# a single stage
#
# Pmod BVA simulation (separate, xsim) -- testbench: verification\tb_pmod_bva.vhd
#   cd verification
#   xvhdl -2008 ..\ip_workspace\5_Platform\spi_master.vhd ..\ip_workspace\5_Platform\i2c_master.vhd ^
#         ..\ip_workspace\5_Platform\gpio_port.vhd ..\ip_workspace\5_Platform\uart_lite.vhd ^
#         ..\ip_workspace\5_Platform\pwm_gen.vhd ..\ip_workspace\5_Platform\mmio_bridge.vhd tb_pmod_bva.vhd
#   xelab -debug typical tb_pmod_bva -s bva && xsim bva -runall      ;# expect "FAIL=0"
# =====================================================================
set ROOT C:/work/github/RV32-FullStack
set BD   $ROOT/vivado_zynq/rv32_zynq.srcs/sources_1/bd/rv32_top/rv32_top.bd
if {![info exists argv]} { set argv {} }
set stage [expr {[llength $argv] ? [lindex $argv 0] : "all"}]
puts "### build_pmod: stage = $stage"

# ---------- 1) package the platform IP (reuses package_platform_ip.tcl) ----------
if {$stage in {package all}} {
    source $ROOT/scripts/package_platform_ip.tcl
}

# ---------- 2) BD integration: refresh plat cell + Pmod ports external ----------
if {$stage in {bd all}} {
    open_project $ROOT/vivado_zynq/rv32_zynq.xpr
    set_property ip_repo_paths $ROOT/ip_repo [current_project]
    update_ip_catalog -rebuild
    open_bd_design $BD
    catch { upgrade_ip -quiet [get_ips -quiet *] }
    foreach p {ja_io jb_io jc_io jd_io je_io} {
        if {[llength [get_bd_ports -quiet ${p}_0]] == 0} {
            make_bd_pins_external -name ${p}_0 [get_bd_pins /plat/$p]
            puts "  EXTERN ${p}_0"
        } else { puts "  EXTERN ${p}_0 (already external)" }
    }
    validate_bd_design
    save_bd_design
    generate_target all [get_files $BD]
    close_project
}

# ---------- 3) constraints + GLOBAL synth -> impl -> bitstream ----------
# NB: global synthesis is required -- per-IP OOC synthesis converts the platform's
# 26 inout tri-states to logic (Synth 8-5799) and demotes GPIO/I2C pins to OBUFs.
if {$stage in {synth all}} {
    open_project $ROOT/vivado_zynq/rv32_zynq.xpr
    set xdc $ROOT/constraints/zybo_z7_20_pmod.xdc
    if {[llength [get_files -quiet -of_objects [get_filesets constrs_1] *zybo_z7_20_pmod.xdc]] == 0} {
        add_files -fileset constrs_1 -norecurse $xdc
        puts "  XDC added"
    }
    set_property top rv32_top_wrapper [get_filesets sources_1]
    update_compile_order -fileset sources_1
    set_property synth_checkpoint_mode None [get_files $BD]
    reset_target all [get_files $BD]
    generate_target all [get_files $BD]

    reset_run synth_1
    launch_runs synth_1 -jobs 6
    wait_on_run synth_1
    puts "  SYNTH: [get_property STATUS [get_runs synth_1]] ([get_property PROGRESS [get_runs synth_1]])"
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        puts "  SYNTH did not complete -- aborting"
    } else {
        launch_runs impl_1 -to_step write_bitstream -jobs 6
        wait_on_run impl_1
        puts "  IMPL: [get_property STATUS [get_runs impl_1]] ([get_property PROGRESS [get_runs impl_1]])"
        set bit $ROOT/vivado_zynq/rv32_zynq.runs/impl_1/rv32_top_wrapper.bit
        puts [expr {[file exists $bit] ? "  BITSTREAM OK: $bit" : "  BITSTREAM MISSING"}]
    }
    close_project
}
puts "### build_pmod: done"
