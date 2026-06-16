@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
if exist BOOT.bin del BOOT.bin
if exist make_boot_log.txt del make_boot_log.txt
call bootgen -arch zynq -image boot.bif -w -o BOOT.bin > make_boot_log.txt 2>&1
echo [bootgen exit=%errorlevel%] >> make_boot_log.txt
if exist BOOT.bin ( echo BOOT.bin CREATED >> make_boot_log.txt ) else ( echo BOOT.bin MISSING >> make_boot_log.txt )
