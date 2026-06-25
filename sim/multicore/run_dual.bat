@echo off
REM Compile + run the dual-core testbench in xsim (Vivado command prompt).
REM Expect tail: "==== DUAL-CORE TB: ALL PASS ..."
cd /d C:\work\github\RV32-FullStack\sim\multicore
call xvhdl -2008 -relax -f dual_files.f
if errorlevel 1 goto :err
call xelab -debug typical tb_rv32_dual -s dual_sim
if errorlevel 1 goto :err
call xsim dual_sim -runall
goto :eof
:err
echo COMPILE/ELAB FAILED & exit /b 1
