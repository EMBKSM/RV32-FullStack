@echo off
REM ====================================================================
REM run_all_xsim.bat - full SystemVerilog regression (all unit + integ TBs)
REM Run from a terminal where Vivado tools are on PATH:
REM   "C:\Xilinx\Vivado\2025.2\settings64.bat"   (adjust version)
REM   cd C:\work\github\RV32-FullStack\verification
REM   run_all_xsim.bat
REM Compiles all RTL once, then elaborate+run each testbench. Each TB
REM prints its own "ALL PASS"/"FAIL" line; scan the output (or *.log).
REM ====================================================================
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set R=C:/work/github/RV32-FullStack/ip_workspace
set V=C:/work/github/RV32-FullStack/verification

echo ============ RV32 full xsim regression ============
where xvhdl >nul 2>&1
if errorlevel 1 (
  echo.
  echo *** Vivado xsim tools ^(xvhdl/xvlog/xelab/xsim^) are NOT on PATH. ***
  echo Open the "Vivado 2025.2 Tcl Shell" / "Vivado HLx Command Prompt"
  echo from the Start menu, OR run this first in a normal cmd:
  echo     call "C:\Xilinx\Vivado\2025.2\settings64.bat"
  echo then:  cd /d "%~dp0"  ^&  run_all_xsim.bat
  echo.
  goto :end
)

echo ============ [1/3] compiling VHDL (leaf-first) ============
xvhdl ^
  %R%/common/pipeline_reg.vhd ^
  %R%/0_IF/0_PC/pc_adder.vhd %R%/0_IF/0_PC/next_pc_mux.vhd %R%/0_IF/0_PC/program_counter.vhd ^
  %R%/0_IF/1_adress_split/address_aligner.vhd %R%/0_IF/1_adress_split/comparator.vhd ^
  %R%/0_IF/1_adress_split/tag_array.vhd %R%/0_IF/1_adress_split/cache_controller.vhd ^
  %R%/0_IF/1_adress_split/icache_data_array.vhd %R%/0_IF/1_adress_split/icache_axi_adapter.vhd ^
  %R%/0_IF/1_adress_split/icache_unit.vhd ^
  %R%/1_ID/control_unit.vhd %R%/1_ID/csr_file.vhd %R%/1_ID/hazard_unit.vhd ^
  %R%/1_ID/imm_gen.vhd %R%/1_ID/register_file.vhd ^
  %R%/2_EX/alu.vhd %R%/2_EX/alu_control.vhd %R%/2_EX/bcu.vhd ^
  %R%/2_EX/forwarding_unit.vhd %R%/2_EX/trap_unit.vhd ^
  %R%/3_Mem/read_aligner.vhd %R%/3_Mem/write_strobe_gen.vhd %R%/3_Mem/dtag_array.vhd ^
  %R%/3_Mem/ddata_array.vhd %R%/3_Mem/dcache_controller.vhd %R%/3_Mem/axi_master.vhd ^
  %R%/3_Mem/axi_slave_mem.vhd %R%/3_Mem/cache_unit.vhd ^
  %R%/4_WB/result_mux.vhd ^
  %R%/rv32_core.vhd %R%/rv32_soc.vhd
if errorlevel 1 ( echo *** VHDL COMPILE FAILED *** & goto :end )

echo ============ [2/3] compiling SystemVerilog TBs ============
xvlog -sv ^
  %R%/0_IF/0_PC/tb_pc_adder.sv %R%/0_IF/0_PC/tb_next_pc_mux.sv %R%/0_IF/0_PC/tb_program_counter.sv ^
  %R%/0_IF/1_adress_split/tb_address_aligner.sv %R%/0_IF/1_adress_split/tb_comparator.sv ^
  %R%/0_IF/1_adress_split/tb_tag_array.sv %R%/0_IF/1_adress_split/tb_cache_controller.sv ^
  %R%/0_IF/1_adress_split/tb_icache_data_array.sv %R%/0_IF/1_adress_split/tb_icache_axi_adapter.sv ^
  %R%/1_ID/tb_control_unit.sv %R%/1_ID/tb_csr_file.sv %R%/1_ID/tb_hazard_unit.sv ^
  %R%/1_ID/tb_imm_gen.sv %R%/1_ID/tb_register_file.sv ^
  %R%/2_EX/tb_alu.sv %R%/2_EX/tb_alu_control.sv %R%/2_EX/tb_bcu.sv ^
  %R%/2_EX/tb_forwarding_unit.sv %R%/2_EX/tb_trap_unit.sv ^
  %R%/3_Mem/tb_read_aligner.sv %R%/3_Mem/tb_write_strobe_gen.sv %R%/3_Mem/tb_dtag_array.sv ^
  %R%/3_Mem/tb_ddata_array.sv %R%/3_Mem/tb_dcache_controller.sv %R%/3_Mem/tb_axi_master.sv ^
  %R%/4_WB/tb_result_mux.sv ^
  %R%/common/tb_pipeline_reg.sv ^
  %V%/tb_rv32_core_if_wb.sv %V%/tb_rv32_soc.sv %V%/tb_icache_unit.sv
if errorlevel 1 ( echo *** SV COMPILE FAILED *** & goto :end )

echo ============ [3/3] running all testbenches ============
for %%T in (
  tb_pc_adder tb_next_pc_mux tb_program_counter
  tb_address_aligner tb_comparator tb_tag_array tb_cache_controller
  tb_icache_data_array tb_icache_axi_adapter
  tb_control_unit tb_csr_file tb_hazard_unit tb_imm_gen tb_register_file
  tb_alu tb_alu_control tb_bcu tb_forwarding_unit tb_trap_unit
  tb_read_aligner tb_write_strobe_gen tb_dtag_array tb_ddata_array
  tb_dcache_controller tb_axi_master
  tb_result_mux tb_pipeline_reg
  tb_rv32_core_if_wb tb_icache_unit tb_rv32_soc
) do (
  echo ---------------------------------------- %%T
  xelab %%T -relax -s s_%%T >nul 2>&1
  if errorlevel 1 ( echo   *** ELAB FAILED: %%T *** ) else ( xsim s_%%T -runall )
)

echo ============ DONE: scan output above for any FAIL / errors^>0 ============
:end
echo.
pause
endlocal
