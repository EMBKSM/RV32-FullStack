@echo off
setlocal
cd /d C:\work\github\RV32-FullStack\flash
del build_30mhz_out.txt 2>nul
echo === rebuild FSBL (FCLK0=30.3MHz) === > build_30mhz_out.txt
call "C:\Xilinx\2025.2\Vitis\bin\xsct.bat" build_fsbl_only.tcl >> build_30mhz_out.txt 2>&1
echo [xsct exit=%errorlevel%] >> build_30mhz_out.txt
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
if exist BOOT_npu16_30mhz.bin del BOOT_npu16_30mhz.bin
echo === bootgen BOOT_npu16_30mhz.bin === >> build_30mhz_out.txt
call bootgen -arch zynq -image boot_npu16_30mhz.bif -w -o BOOT_npu16_30mhz.bin >> build_30mhz_out.txt 2>&1
echo [bootgen exit=%errorlevel%] >> build_30mhz_out.txt
if exist BOOT_npu16_30mhz.bin ( echo BOOT_npu16_30mhz.bin CREATED >> build_30mhz_out.txt ) else ( echo BOOT MISSING >> build_30mhz_out.txt )
echo BUILD-30MHZ-DONE >> build_30mhz_out.txt
