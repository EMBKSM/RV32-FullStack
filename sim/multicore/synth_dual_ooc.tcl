# OOC synthesis of the dual-core cluster -> resource report
read_vhdl -vhdl2008 [list \
\
  C:/work/github/RV32-FullStack/rtl/core/pc/next_pc_mux.vhd \
  C:/work/github/RV32-FullStack/rtl/core/pc/pc_adder.vhd \
  C:/work/github/RV32-FullStack/rtl/core/pc/program_counter.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/address_aligner.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/cache_controller.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/comparator.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/icache_axi_adapter.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/icache_data_array.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/tag_array.vhd \
  C:/work/github/RV32-FullStack/rtl/core/icache/icache_unit.vhd \
  C:/work/github/RV32-FullStack/rtl/core/id/control_unit.vhd \
  C:/work/github/RV32-FullStack/rtl/core/id/csr_file.vhd \
  C:/work/github/RV32-FullStack/rtl/core/id/hazard_unit.vhd \
  C:/work/github/RV32-FullStack/rtl/core/id/imm_gen.vhd \
  C:/work/github/RV32-FullStack/rtl/core/id/register_file.vhd \
  C:/work/github/RV32-FullStack/rtl/core/ex/alu.vhd \
  C:/work/github/RV32-FullStack/rtl/core/ex/alu_control.vhd \
  C:/work/github/RV32-FullStack/rtl/core/ex/bcu.vhd \
  C:/work/github/RV32-FullStack/rtl/core/ex/forwarding_unit.vhd \
  C:/work/github/RV32-FullStack/rtl/core/ex/trap_unit.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/axi_master.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/axi_slave_mem.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/dtag_array.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/ddata_array.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/dcache_controller.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/cache_unit.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/read_aligner.vhd \
  C:/work/github/RV32-FullStack/rtl/core/mem/write_strobe_gen.vhd \
  C:/work/github/RV32-FullStack/rtl/core/wb/result_mux.vhd \
  C:/work/github/RV32-FullStack/rtl/common/pipeline_reg.vhd \
  C:/work/github/RV32-FullStack/rtl/core/rv32_core.vhd \
  C:/work/github/RV32-FullStack/rtl/soc/rv32_shared.vhd \
  C:/work/github/RV32-FullStack/rtl/soc/rv32_dual.vhd]
synth_design -mode out_of_context -top rv32_dual -part xc7z020clg400-1
report_utilization -file C:/work/github/RV32-FullStack/_dual_util.rpt
puts "=====================  DUAL-CORE OOC UTILIZATION  ====================="
report_utilization
puts "=====================  DUAL-CORE OOC synth DONE  ====================="
