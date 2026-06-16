@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
if exist flash_log.txt del flash_log.txt
call program_flash -f BOOT.bin -flash_type qspi-x4-single -fsbl "C:\work\github\RV32-FullStack\rv_ps\rv_platform\zynq_fsbl\build\fsbl.elf" -verify -url tcp:localhost:3121 > flash_log.txt 2>&1
echo [program_flash exit=%errorlevel%] >> flash_log.txt
