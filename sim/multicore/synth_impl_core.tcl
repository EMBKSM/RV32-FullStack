# Clean per-core OOC: rv32_core already exposes its memory as PORTS (no internal
# ideal RAM), so this measures real core logic + timing. The dual cluster is
# ~2x this core + the small rv32_shared block. Also synth rv32_shared for its size.
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
  $R/rtl/core/rv32_core.vhd $R/rtl/soc/rv32_shared.vhd]
read_xdc $R/sim/multicore/dual_ooc.xdc
# ---------- single core: full impl + timing ----------
synth_design -mode out_of_context -top rv32_core -part xc7z020clg400-1
opt_design
place_design -directive Explore
route_design -directive Explore
report_utilization    -file $R/_core_util.rpt
report_timing_summary -file $R/_core_timing.rpt -max_paths 5
puts "================  rv32_core OOC TIMING  ================"
puts [report_timing_summary -return_string -no_detailed_paths]
catch {phys_opt_design}
report_timing_summary -file $R/_core_timing.rpt -max_paths 5
puts [report_timing_summary -return_string -no_detailed_paths]
# ---------- shared coordination block: size only ----------
synth_design -mode out_of_context -top rv32_shared -part xc7z020clg400-1
report_utilization -file $R/_shared_util.rpt
puts "================  rv32_shared OOC UTILIZATION  ================"
puts [report_utilization -return_string]
