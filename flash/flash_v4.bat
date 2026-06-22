@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vivado\bin;C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
echo START-FLASH-V4 (50MHz programming FSBL) > flash_v4_log.txt
program_flash -f BOOT_npu16_30mhz.bin -flash_type qspi-x4-single -fsbl "C:\work\github\RV32-FullStack\rv_ps\rv_platform\zynq_fsbl\build\fsbl.elf" -verify -url tcp:localhost:3121 >> flash_v4_log.txt 2>&1
echo [program_flash exit=%errorlevel%] >> flash_v4_log.txt
echo FLASH-V4-DONE >> flash_v4_log.txt
