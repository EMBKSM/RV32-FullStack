@echo off
setlocal
set "PATH=C:\Xilinx\2025.2\Vivado\bin;%PATH%"
cd /d C:\work\github\RV32-FullStack\verification\npu_soc_sim2
del soc_npu_log.txt 2>nul
echo === xvhdl (dependency-ordered) === > soc_npu_log.txt
call xvhdl --work work -f vhdl_ordered.f > nul 2>&1
call xvhdl --work work -f vhdl_ordered.f >> soc_npu_log.txt 2>&1
echo [xvhdl exit=%errorlevel%] >> soc_npu_log.txt
echo === xvlog === >> soc_npu_log.txt
call xvlog -sv tb_rv32_soc_npu.sv >> soc_npu_log.txt 2>&1
echo [xvlog exit=%errorlevel%] >> soc_npu_log.txt
echo === xelab === >> soc_npu_log.txt
call xelab tb_rv32_soc_npu -s socnpu >> soc_npu_log.txt 2>&1
echo [xelab exit=%errorlevel%] >> soc_npu_log.txt
echo === xsim === >> soc_npu_log.txt
call xsim socnpu -runall >> soc_npu_log.txt 2>&1
echo [xsim exit=%errorlevel%] >> soc_npu_log.txt
echo ALL-DONE >> soc_npu_log.txt
