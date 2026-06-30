@echo off
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
echo START-COMPREHENSIVE > comprehensive_log.txt
call xsct jtag_comprehensive.tcl >> comprehensive_log.txt 2>&1
echo [xsct exit=%errorlevel%] >> comprehensive_log.txt
echo COMPREHENSIVE-DONE >> comprehensive_log.txt
