# source this from the Vivado Tcl console:  source C:/work/github/RV32-FullStack/sim/multicore/run_dual_xsim.tcl
set R C:/work/github/RV32-FullStack
set LOG $R/_dual_xsim.log
cd $R/sim/multicore
catch {file delete -force xsim.dir dual_sim.wdb}
catch {exec xvhdl -2008 -relax -f $R/sim/multicore/dual_files.f >& $LOG} r
catch {exec xelab -debug typical tb_rv32_dual -s dual_sim >>& $LOG} r
catch {exec xsim dual_sim -runall >>& $LOG} r
puts "=== DUAL-CORE xsim done. log: $LOG ==="
set fh [open $LOG r]; puts [read $fh]; close $fh
