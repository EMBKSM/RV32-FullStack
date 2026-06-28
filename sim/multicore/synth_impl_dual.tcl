# OOC synth + impl + timing of the dual-core cluster.
# NOTE: rv32_dual's 1024-word imem/dmem are *ideal combinational* sim memory
# (a test harness, not part of the real multicore). They infer as huge
# distributed-RAM read muxes that dominate area and stall retiming. We shrink
# them to a small tightly-coupled size via generics so the measurement reflects
# the dual-core LOGIC (2x rv32_core + rv32_shared coordination). A real SoC
# would fetch from BRAM/cache (registered), exactly like the single-core build.
set R C:/work/github/RV32-FullStack
read_vhdl -vhdl2008 [list \
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
  $R/rtl/core/rv32_core.vhd $R/rtl/soc/rv32_shared.vhd $R/rtl/soc/rv32_dual.vhd]
read_xdc $R/sim/multicore/dual_ooc.xdc
synth_design -mode out_of_context -top rv32_dual -part xc7z020clg400-1 \
    -directive RuntimeOptimized -generic IMEM_W=64 -generic DMEM_W=64
opt_design
place_design
route_design
report_utilization    -file $R/_dual_util.rpt
report_timing_summary -file $R/_dual_timing.rpt -max_paths 5
puts "================  DUAL-CORE OOC TIMING (post-route)  ================"
puts [report_timing_summary -return_string -no_detailed_paths]
if {[catch {phys_opt_design} pe]} {
    puts "phys_opt_design raised: $pe (keeping post-route report)"
} else {
    report_timing_summary -file $R/_dual_timing.rpt -max_paths 5
    puts "================  DUAL-CORE OOC TIMING (post phys_opt)  ================"
    puts [report_timing_summary -return_string -no_detailed_paths]
}
