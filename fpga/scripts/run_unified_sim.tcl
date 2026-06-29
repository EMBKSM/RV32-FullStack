# run_unified_sim.tcl - functional sim of the unified fabric (DSP count already
# proven = 202 by run_unified_proof.tcl). xsim tb_unified: vadd / saxpy(VMUL) /
# relu / vmac(A*B+C). saxpy+vmac run the multiply on the SHARED NPU DSPs.
set R   C:/work/github/RV32-FullStack
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
puts "UNIFIED SIM DONE"
exit
