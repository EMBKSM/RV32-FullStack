# run_unified_proof.tcl - one Vivado batch session that PROVES the unified fabric:
#   (1) OOC-synthesize unified_top (16x16 NPU + GPU sharing 8 DSPs) -> DSP count
#       must be ~ the NPU-alone count (GPU adds 0 DSP).
#   (2) functionally simulate tb_unified (vadd/saxpy/relu/vmac); saxpy+vmac run
#       VMUL/VMAC on the SHARED NPU DSPs -> must match the C-golden vectors.
# Uses the proven `exec xvhdl/xelab/xsim` flow (xsim -runall works under vivado).
set R    C:/work/github/RV32-FullStack
set PART xc7z020clg400-1

# ---------- (1) DSP-count synth ----------
puts "### UNIFIED SYNTH (DSP count) ###"
create_project -in_memory -part $PART
read_vhdl -vhdl2008 [list \
  $R/rtl/gpu/gpu_pkg.vhd  $R/rtl/gpu/gpu_lane.vhd $R/rtl/gpu/gpu_core.vhd $R/rtl/gpu/gpu_top.vhd \
  $R/rtl/npu/npu_pe.vhd   $R/rtl/npu/npu_array.vhd $R/rtl/npu/npu_top.vhd  $R/rtl/npu/npu_top16.vhd \
  $R/sim/soc/unified_top.vhd ]
synth_design -top unified_top -part $PART -mode out_of_context
report_utilization -file $R/fpga/flash/unified_util.rpt
set dsp [llength [get_cells -hier -filter {REF_NAME =~ DSP48*}]]
puts "### UNIFIED NPU+GPU DSP48 count = $dsp ###"
close_project

# ---------- (2) functional sim (proven exec flow) ----------
puts "### UNIFIED XSIM (vadd / saxpy[VMUL] / relu / vmac[A*B+C]) ###"
set LOG $R/_unified_xsim.log
cd $R/sim/soc
catch {file delete -force xsim.dir}
catch {exec xvhdl -2008 -relax \
    $R/rtl/gpu/gpu_pkg.vhd  $R/rtl/gpu/gpu_lane.vhd $R/rtl/gpu/gpu_core.vhd $R/rtl/gpu/gpu_top.vhd \
    $R/rtl/npu/npu_pe.vhd   $R/rtl/npu/npu_array.vhd $R/rtl/npu/npu_top.vhd  $R/rtl/npu/npu_top16.vhd \
    $R/sim/soc/tb_unified.vhd >& $LOG} r
catch {exec xelab -debug typical tb_unified -s unif_sim >>& $LOG} r
catch {exec xsim unif_sim -runall >>& $LOG} r
set fh [open $LOG r]; puts [read $fh]; close $fh
puts "### UNIFIED PROOF DONE ###"
exit
