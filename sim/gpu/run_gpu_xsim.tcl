# source this from the Vivado Tcl console:  source C:/work/github/RV32-FullStack/sim/gpu/run_gpu_xsim.tcl
set R C:/work/github/RV32-FullStack
set LOG $R/_gpu_xsim.log
cd $R/sim/gpu
catch {file delete -force xsim.dir gpu_sim.wdb}
catch {exec xvhdl -2008 -relax \
    $R/rtl/gpu/gpu_pkg.vhd $R/rtl/gpu/gpu_lane.vhd \
    $R/rtl/gpu/gpu_core.vhd $R/rtl/gpu/gpu_top.vhd \
    $R/sim/gpu/tb_gpu.vhd >& $LOG} r
catch {exec xelab -debug typical tb_gpu -s gpu_sim >>& $LOG} r
catch {exec xsim gpu_sim -runall >>& $LOG} r
puts "=== GPU xsim done. log: $LOG ==="
set fh [open $LOG r]; puts [read $fh]; close $fh
