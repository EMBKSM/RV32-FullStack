@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
if exist flash3_log.txt del flash3_log.txt
echo === xsct connect (launch hw_server + detect JTAG cable) === > flash3_log.txt
call "C:\Xilinx\2025.2\Vitis\bin\xsct.bat" _conn.tcl >> flash3_log.txt 2>&1
echo. >> flash3_log.txt
echo === program_flash (BOOT_fixed.bin, new FSBL DQS=0.0) === >> flash3_log.txt
call program_flash -f BOOT_fixed.bin -flash_type qspi-x4-single -fsbl "C:\work\github\RV32-FullStack\flash\ws\fsbl_fix\Debug\fsbl_fix.elf" -verify -url tcp:localhost:3121 >> flash3_log.txt 2>&1
echo [program_flash exit=%errorlevel%] >> flash3_log.txt
