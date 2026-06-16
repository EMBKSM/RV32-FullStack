@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
if exist flash2_log.txt del flash2_log.txt
if exist BOOT_fixed.bin del BOOT_fixed.bin
echo === bootgen (new FSBL with DQS=0.0) === > flash2_log.txt
call bootgen -arch zynq -image boot_fixed.bif -w -o BOOT_fixed.bin >> flash2_log.txt 2>&1
echo [bootgen exit=%errorlevel%] >> flash2_log.txt
if not exist BOOT_fixed.bin ( echo BOOT_fixed.bin MISSING - aborting >> flash2_log.txt & goto end )
echo BOOT_fixed.bin created, programming QSPI... >> flash2_log.txt
echo === program_flash === >> flash2_log.txt
call program_flash -f BOOT_fixed.bin -flash_type qspi-x4-single -fsbl "C:\work\github\RV32-FullStack\flash\ws\fsbl_fix\Debug\fsbl_fix.elf" -verify -url tcp:localhost:3121 >> flash2_log.txt 2>&1
echo [program_flash exit=%errorlevel%] >> flash2_log.txt
:end
