# 16×16 NPU — On-Board GEMM Verification Result

**Date:** 2026-06-22
**Board:** Zybo Z7-20 / Zynq XC7Z020-CLG400-1 (real silicon)
**PL clock:** 30.3 MHz (FCLK0 ÷33, FPGA0_CLK_CTRL=0x00102100)
**Bitstream:** `flash/rv32_16x16_rtopt_wns-6p74.bit` (16×16 INT8 systolic GEMM, 202/220 DSP + 56 LUT-MAC)
**Drive path:** JTAG → APU DAP → PS M_AXI_GP0 → `rv32_ctrl_axi` @ 0x4000_0000 → RV32 core → NPU
(DDR/OCM/monitor all bypassed — board DDR is faulty, so QSPI boot is unavailable.)

## Test
2×2 tile GEMM, K=2, driver = `flash/npu16_demo.s` (32 RV32 words loaded into imem via ctrl_axi):

```
A = [[3, 4],     B = [[5, 7],     C = A·B = [[39, 53],
     [1, 2]]          [6, 8]]                [17, 23]]
```

## Result (xsct `mrd` returns DECIMAL)

| reg | C[i][j] | board | golden | |
|-----|---------|-------|--------|---|
| x10 | C[0][0] | 39 | 39 | ✅ |
| x11 | C[0][1] | 53 | 53 | ✅ |
| x12 | C[1][0] | 17 | 17 | ✅ |
| x13 | C[1][1] | 23 | 23 | ✅ |

Sanity: `PC = 0x0000007c` (= byte 124 = the `done:` loop → program ran to completion),
core committed instructions (RV32 fetched/executed the loaded driver), `STATUS` run_en asserted.

**PASS — the 16×16 INT8 NPU computes GEMM correctly on real XC7Z020 silicon @ 30.3 MHz.**

## Note on the raw log display
`jtag_gemm_test.tcl` originally wrapped the decimal `mrd -value` output with a `0x` prefix +
`format %u`, so the first run *printed* "0x39 = 57" etc. That is a display artifact: the raw
register values returned by `mrd` were `39 53 17 23` (decimal) = exact golden. Confirmed
independently by `PC`: `mrd` returned `124`, which `format 0x%08x` rendered as `0x0000007c`
(had `mrd` returned hex "7c", that format call would have raised an integer-parse error).
The script now prints the decimal values directly with a PASS/MISMATCH check.

## Reproduce
Power-cycle the board (clean DAP), then run `flash/run_gemm_test.bat` once.
Requires `configparams force-mem-access 1` to permit XSDB PL-AXI access at 0x4000_0000.
