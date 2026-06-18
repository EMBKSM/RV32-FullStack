# Out-of-context synthesis of the 16x16 hybrid NPU (npu_top16) on the Zybo Z7-20 part.
# Confirms the 256-MAC array fits the 220 DSP48E1 budget (220 DSP + 36 LUT MAC) and
# reports utilization + post-synth timing at the 50 MHz PL clock (20 ns).
set part xc7z020clg400-1
set src  C:/work/github/RV32-FullStack/ip_workspace/6_NPU
set out  C:/work/github/RV32-FullStack/verification/npu_scale16

read_vhdl [list $src/npu_pe.vhd $src/npu_array.vhd $src/npu_top.vhd $src/npu_top16.vhd]
synth_design -top npu_top16 -part $part -mode out_of_context
create_clock -name clk -period 20.000 [get_ports clk]

report_utilization      -file $out/util_npu16.rpt
report_timing_summary -delay_type max -max_paths 8 -file $out/timing_npu16.rpt

# concise console echo for the background log
set dsp [llength [get_cells -hier -filter {PRIMITIVE_GROUP == DSP}]]
puts "OOC-RESULT DSP_cells=$dsp"
puts "OOC-SYNTH-DONE"
