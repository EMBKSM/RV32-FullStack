@echo off
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
echo START-UNIFIED-GPU > unified_gpu_log.txt
call xsct jtag_unified_gpu.tcl >> unified_gpu_log.txt 2>&1
echo [xsct exit=%errorlevel%] >> unified_gpu_log.txt
echo UNIFIED-GPU-DONE >> unified_gpu_log.txt
