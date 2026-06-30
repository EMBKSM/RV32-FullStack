@echo off
taskkill /F /IM hw_server.exe /T 2>nul
taskkill /F /IM xsdb.exe /T 2>nul
timeout /t 2 /nobreak >nul
set "PATH=C:\Xilinx\2025.2\Vitis\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\flash
echo START-MONITOR > monitor_log.txt
call xsct load_monitor.tcl >> monitor_log.txt 2>&1
echo [xsct exit=%errorlevel%] >> monitor_log.txt
REM release the FTDI/JTAG so the UART COM is fully free for the GUI
taskkill /F /IM hw_server.exe /T 2>nul
echo MONITOR-DONE >> monitor_log.txt
