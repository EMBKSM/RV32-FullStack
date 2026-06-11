@echo off
REM ====================================================================
REM cleanup.bat - tidy the repo: consolidate scripts -> scripts\, design
REM docs -> docs\, remove the now-merged verification reports and the
REM throwaway bring-up diagnostic TBs. Run from the repo root.
REM   cd C:\work\github\RV32-FullStack  &  cleanup.bat
REM (Original spec docs RV32_Pipeline_Spec.md/Movement.md/... stay in root:
REM  verify_spec.py / verify_docs.py reference them by path.)
REM ====================================================================
setlocal
cd /d C:\work\github\RV32-FullStack

if not exist docs    mkdir docs
if not exist scripts mkdir scripts

echo === move process scripts -^> scripts\ ===
move /Y package_all_ip.tcl        scripts\ 2>nul
move /Y package_bd_glue.tcl       scripts\ 2>nul
move /Y package_platform_ip.tcl   scripts\ 2>nul
move /Y build_rv32_bd.tcl         scripts\ 2>nul
move /Y build_zynq_project.tcl    scripts\ 2>nul
move /Y run_bitstream.tcl         scripts\ 2>nul
move /Y fix_icache_adapter_ip.tcl scripts\ 2>nul
move /Y fix_cache_axi_iface.tcl   scripts\ 2>nul
move /Y verification\run_all_xsim.bat scripts\ 2>nul

echo === move design docs -^> docs\ ===
move /Y SOC_PLATFORM_DESIGN.md        docs\ 2>nul
move /Y bd_assembly\BD_CONNECTIONS.md docs\ 2>nul
move /Y bd_assembly\BD_WIRING_GUIDE.md docs\ 2>nul

echo === delete verification reports (merged into docs\VERIFICATION.md) ===
del /Q verification\VERIFICATION_REPORT.md       2>nul
del /Q verification\VERIFICATION_REPORT_DOCS.md  2>nul
del /Q verification\VERIFICATION_REPORT_SPEC.md  2>nul
del /Q verification\VERIFICATION_REPORT_50.md    2>nul
del /Q verification\VERIFICATION_REPORT_IFWB.md  2>nul
del /Q verification\VERIFICATION_REPORT_FINAL.md 2>nul
del /Q ip_workspace\RTL_IMPLEMENTATION_REPORT.md 2>nul
del /Q ip_workspace\2_EX\VERIFICATION_REPORT_ALU.md 2>nul

echo === delete throwaway bring-up diagnostic TBs ===
del /Q verification\tb_plat_diag.sv  2>nul
del /Q verification\tb_plat_diag2.sv 2>nul
del /Q verification\tb_plat_diag3.sv 2>nul

echo.
echo === cleanup done ===
echo  docs\      : VERIFICATION.md + SOC_PLATFORM_DESIGN.md + BD_*.md
echo  scripts\   : all build/IP/bitstream tcl + run_all_xsim.bat + README.md
echo  (spec docs RV32_Pipeline_Spec.md etc. kept in root for verify_*.py)
endlocal
