@echo off
REM ---------------------------------------------------------------
REM run_gpu.bat  -  compile + run the SIMT-lite GPU testbench in xsim.
REM Run from a Vivado command prompt (xvhdl/xelab/xsim on PATH).
REM Expected tail of output:  "==== GPU TB: ALL TESTS PASS ===="
REM ---------------------------------------------------------------
cd /d C:\work\github\RV32-FullStack\sim\gpu
call xvhdl -2008 -relax ^
  ..\..\rtl\gpu\gpu_pkg.vhd ^
  ..\..\rtl\gpu\gpu_lane.vhd ^
  ..\..\rtl\gpu\gpu_core.vhd ^
  ..\..\rtl\gpu\gpu_top.vhd ^
  tb_gpu.vhd
if errorlevel 1 goto :err
call xelab -debug typical tb_gpu -s gpu_sim
if errorlevel 1 goto :err
call xsim gpu_sim -runall
goto :eof
:err
echo COMPILE/ELAB FAILED
exit /b 1
