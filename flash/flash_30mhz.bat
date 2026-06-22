@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
del flash_30mhz_log.txt 2>nul
echo === program_flash BOOT_npu16_30mhz.bin (QSPI x4) === > flash_30mhz_log.txt
call program_flash -f BOOT_npu16_30mhz.bin -flash_type qspi-x4-single -fsbl "C:\work\github\RV32-FullStack\flash\ws\fsbl_fix\Debug\fsbl_fix.elf" -verify -url tcp:localhost:3121 >> flash_30mhz_log.txt 2>&1
echo [program_flash exit=%errorlevel%] >> flash_30mhz_log.txt
echo FLASH-30MHZ-DONE >> flash_30mhz_log.txt
