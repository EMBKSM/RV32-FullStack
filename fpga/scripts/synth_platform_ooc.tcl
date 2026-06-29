# Full integrated SoC (rv32_platform = core + caches + mmio_bridge -> NPU16 + GPU
# + peripherals) OOC synth + impl @ 100 MHz, to confirm the GPU fits alongside
# the NPU (DSP is the tight resource) and the integration closes timing.
set R C:/work/github/RV32-FullStack
read_vhdl -vhdl2008 [list \
  $R/rtl/gpu/gpu_pkg.vhd \
  $R/rtl/core/pc/next_pc_mux.vhd $R/rtl/core/pc/pc_adder.vhd \
  $R/rtl/core/pc/program_counter.vhd \
  $R/rtl/core/icache/address_aligner.vhd $R/rtl/core/icache/cache_controller.vhd \
  $R/rtl/core/icache/comparator.vhd $R/rtl/core/icache/icache_axi_adapter.vhd \
  $R/rtl/core/icache/icache_data_array.vhd $R/rtl/core/icache/tag_array.vhd \
  $R/rtl/core/icache/icache_unit.vhd \
  $R/rtl/core/id/control_unit.vhd $R/rtl/core/id/csr_file.vhd \
  $R/rtl/core/id/hazard_unit.vhd $R/rtl/core/id/imm_gen.vhd \
  $R/rtl/core/id/register_file.vhd \
  $R/rtl/core/ex/alu.vhd $R/rtl/core/ex/alu_control.vhd $R/rtl/core/ex/bcu.vhd \
  $R/rtl/core/ex/forwarding_unit.vhd $R/rtl/core/ex/trap_unit.vhd \
  $R/rtl/core/mem/axi_master.vhd $R/rtl/core/mem/axi_slave_mem.vhd \
  $R/rtl/core/mem/dtag_array.vhd $R/rtl/core/mem/ddata_array.vhd \
  $R/rtl/core/mem/dcache_controller.vhd $R/rtl/core/mem/cache_unit.vhd \
  $R/rtl/core/mem/read_aligner.vhd $R/rtl/core/mem/write_strobe_gen.vhd \
  $R/rtl/core/wb/result_mux.vhd $R/rtl/common/pipeline_reg.vhd \
  $R/rtl/core/rv32_core.vhd \
  $R/rtl/soc/gpio_port.vhd $R/rtl/soc/i2c_master.vhd $R/rtl/soc/spi_master.vhd \
  $R/rtl/soc/pwm_gen.vhd $R/rtl/soc/uart_lite.vhd \
  $R/rtl/npu/npu_pe.vhd $R/rtl/npu/npu_array.vhd $R/rtl/npu/npu_top.vhd \
  $R/rtl/npu/npu_top16.vhd \
  $R/rtl/gpu/gpu_lane.vhd $R/rtl/gpu/gpu_core.vhd $R/rtl/gpu/gpu_top.vhd \
  $R/rtl/soc/mmio_bridge.vhd $R/rtl/soc/rv32_ctrl_axi.vhd \
  $R/rtl/soc/rv32_platform.vhd]
read_xdc $R/fpga/scripts/platform_ooc.xdc
synth_design -mode out_of_context -top rv32_platform -part xc7z020clg400-1
# resources after synth -- written first so they survive even if impl is slow
report_utilization -file $R/_soc_util.rpt
puts "================  FULL SoC POST-SYNTH UTILIZATION  ================"
puts [report_utilization -return_string]
opt_design
place_design
phys_opt_design
route_design
report_utilization    -file $R/_soc_util.rpt
report_timing_summary -file $R/_soc_timing.rpt -max_paths 10
puts "================  FULL SoC TIMING (post-route)  ================"
puts [report_timing_summary -return_string -no_detailed_paths]
# close the last slack with physical optimization (default = stable; Aggressive
# crashed the tool on the GPU run)
if {[catch {phys_opt_design} pe]} {
    puts "phys_opt_design raised: $pe (keeping post-route report)"
} else {
    report_timing_summary -file $R/_soc_timing.rpt -max_paths 10
    puts "================  FULL SoC TIMING (post phys_opt)  ================"
    puts [report_timing_summary -return_string -no_detailed_paths]
}
# a second phys_opt pass often recovers a bit more on congested designs
if {[catch {phys_opt_design} pe2]} {
    puts "phys_opt pass2 raised: $pe2"
} else {
    report_timing_summary -file $R/_soc_timing.rpt -max_paths 10
    puts "================  FULL SoC TIMING (post phys_opt x2)  ================"
    puts [report_timing_summary -return_string -no_detailed_paths]
}
