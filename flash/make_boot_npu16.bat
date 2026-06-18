@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
if exist BOOT_npu16.bin del BOOT_npu16.bin
if exist make_boot_npu16_log.txt del make_boot_npu16_log.txt
echo === bootgen (FSBL + 16x16 NPU bitstream + rv_firmware) === > make_boot_npu16_log.txt
call bootgen -arch zynq -image boot_fixed.bif -w -o BOOT_npu16.bin >> make_boot_npu16_log.txt 2>&1
echo [bootgen exit=%errorlevel%] >> make_boot_npu16_log.txt
if exist BOOT_npu16.bin ( echo BOOT_npu16.bin CREATED >> make_boot_npu16_log.txt ) else ( echo BOOT_npu16.bin MISSING >> make_boot_npu16_log.txt )
echo ALL-DONE >> make_boot_npu16_log.txt
