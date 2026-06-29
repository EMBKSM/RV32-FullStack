# proof_dual_pe.tcl - OOC-synthesize the dual-mode PE and count DSP48E1s.
# The whole point of the unified design: this must be exactly 1 DSP (the same
# physical multiplier serves NPU MAC and the GPU lane), not 2.
set PART xc7z020clg400-1
set OUT  C:/work/github/RV32-FullStack/fpga/flash
create_project -in_memory -part $PART
read_vhdl -vhdl2008 C:/work/github/RV32-FullStack/rtl/npu/npu_pe.vhd
read_vhdl -vhdl2008 C:/work/github/RV32-FullStack/sim/npu/npu_pe_dual_wrap.vhd
synth_design -top npu_pe_dual_wrap -part $PART -mode out_of_context
report_utilization -file $OUT/dual_pe_util.rpt
set dsp [llength [get_cells -hier -filter {REF_NAME =~ DSP48*}]]
puts "### DUAL-PE DSP48 count = $dsp  (expect 1 -> shared multiplier proven) ###"
puts "### DUAL-PE PROOF DONE ###"
exit
