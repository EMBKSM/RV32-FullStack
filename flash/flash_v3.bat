@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vivado\bin;C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
echo START-FLASH-V3 > flash_v3_log.txt
program_flash -f BOOT_npu16_30mhz.bin -flash_type qspi-x4-single -fsbl "C:\work\github\RV32-FullStack\flash\ws\fsbl_fix\Debug\fsbl_fix.elf" -verify -url tcp:localhost:3121 >> flash_v3_log.txt 2>&1
echo [program_flash exit=%errorlevel%] >> flash_v3_log.txt
echo FLASH-V3-DONE >> flash_v3_log.txt
