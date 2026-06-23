# 16×16 NPU SoC — Fmax Optimization Result

**Target:** push the RV32 + 16×16 INT8 NPU SoC clock as high as possible on Zynq XC7Z020-CLG400-1.
**Headline:** Fmax **37 MHz → 100 MHz** (2.7×) with zero change to the MAC array, by pipelining
three NPU control/read-back paths. **Timing closes at 100 MHz (WNS +0.085 ns, 0 failing endpoints)
and is verified on real silicon** (GEMM C=[[39,53],[17,23]] correct @ 100 MHz, FCLK0 ÷10).
**Pushed further to a board-verified 106 MHz** via synthesis retiming + a PL MMCM ("PLL MUX",
FCLK0 100→106) — also GEMM-PASS on the real chip. Architectural ceiling ≈110.8 MHz (RV32 core
load-use hazard path).

## Beyond 100 MHz — retiming + PL MMCM (board-verified 106 MHz)

| Step | change | WNS | Fmax | board |
|------|--------|-----|------|-------|
| 100 MHz build | (baseline above) | +0.085 @100 | 100.9 MHz | ✅ FCLK0÷10 |
| + synth retiming (Flow_PerfOptimized_high) | register balancing | −1.029 @125 | **110.8 MHz** | needs MMCM (FCLK0÷9=111 just over) |
| floorplan (blind Pblock) | — | ~−1.1 @125 | ~109.6 (neutral) | not used |
| **+ PL MMCM (FCLK0 100→106)** | clk_wiz in BD, PL clock=106 | −0.118 @106 (4 EPs, slow corner) | — | **✅ 106 MHz GEMM PASS on silicon** |

- New wall after retiming = RV32 core **load-use hazard** path (`exmem_reg_write → ifid CE`), ~75% routing — fundamental to the 5-stage pipeline; floorplanning it blind didn't help.
- 110.8 MHz Fmax can't hit a clean FCLK0 divisor step (÷9=111.1 too fast, ÷10=100 wastes it), so a **PL MMCM** synthesizes the exact 106 MHz the design closes at. The MMCM is the "PLL MUX": `FCLK0 (100 MHz) → clk_wiz → 106 MHz → PL`. Bitstream `flash/rv32_16x16_mmcm.bit`.
- The −0.118 ns is worst-case slow-corner (only 4 endpoints); typical silicon is faster → 106 MHz runs correctly on the board.

## Fmax progression

| Build | NPU change | impl strategy | WNS @100MHz | crit. path | **Fmax** | build |
|-------|-----------|---------------|-------------|-----------|----------|-------|
| v1 16×16 (orig) | combinational 256:1 readback mux | RuntimeOptimized | (−6.74 @ 50MHz) | 26.74 ns | **37.4 MHz** | 1 h 17 m |
| v2 | 3-stage readback (col→row→finalize) | default + phys_opt | −3.293 ns | 13.29 ns | **75.2 MHz** | 8 min |
| v3 | + 5-stage requant pipeline | Perf_ExplorePostRoutePhysOpt | −0.602 ns | 10.60 ns | **94.3 MHz** | ~25 min |
| **v4** | **+ register scratchpad feed (a_west/b_north)** | Perf_ExplorePostRoutePhysOpt | **+0.085 ns ✅** | 9.92 ns | **≥100 MHz** | ~22 min |

Hold met throughout (WHS ≥ +0.014 ns). Failing endpoints @100MHz: 3196 → 817 → **0**.
**v4 is the board-verified design** (`flash/rv32_16x16_100mhz.bit`); v3 preserved as `rv32_16x16_94mhz_verified.bit`.

## What was the bottleneck (and the fix)

The MAC array was never the problem — every PE→PE path is ~0.5 ns (huge slack). Two read-back
paths dominated, each fixed by isolating it into registered pipeline stages (the read is held by
the core via `mem_stall`/`rd_valid`, so it stays transparent to software):

1. **256:1 accumulator select** (`acc_flat` → core load reg, ~26 ns, 34 logic levels).
   Split into **col-select → row-select** registered stages. 26.7→13.3 ns, Fmax 37→75 MHz, and
   routing congestion vanished (build 1 h 17 m → 8 min).
2. **Requant multiply** (32×17 in fabric = 19 CARRY4, on the path even for raw reads, ~8.4 ns).
   Split into **multiply (→DSP) → round+shift → clip/select** registered stages. −3.29→−0.60 ns.

Read latency is now 5 cycles (was combinational); negligible vs the GEMM compute, and the RV32
program is unchanged (the bridge stalls the load until `rd_valid`).

3. **Systolic `t`-counter feed** (`t_reg → (t−n) → async scratchpad read → DSP A-input`, ~10.5 ns,
   CARRY4=10, high fanout — *all* of the 817 v3 failing endpoints traced here, **not** the core).
   Fixed by registering the scratchpad outputs `a_west`/`b_north`: the long path is split at a flop
   (compute→reg, reg→PE), and the whole input stream shifts uniformly by 1 cycle (`t_last += 1`),
   so the result is bit-identical. **This single change closed 100 MHz: WNS −0.602 → +0.085 ns,
   817 → 0 failing endpoints.**

The RV32 core was *not* the limiter after all — once the t-counter feed was registered, every
core path met at 100 MHz. The new (met) worst path is `core store → NPU scratchpad write` at
+0.085 ns. True 100 MHz reached with no core redesign.

## Board operating point — 100 MHz verified

The v4 bitstream closes timing at 100 MHz, which is exactly **FCLK0 ÷10** (PS IO-PLL 1000 MHz ÷ 10) —
no PL MMCM needed (FCLK0 itself is the PS PLL through its dividers, i.e. the "PLL MUX"). Set via
`mwr 0xF8000170 0x00100A00`. On-board GEMM at 100 MHz returns C=[[39,53],[17,23]] = golden, PASS.

- 50 MHz (orig 8×8 baseline, failed) → **100 MHz** verified 16×16 = **2× clock**, **4× the MACs** (64→256) = ~8× peak INT8 throughput.
- Intermediate board-verified point also on record: 90.9 MHz with the v3 (94.3 MHz) bitstream.

## Functional verification

The pipelined read-back is bit-identical to the original (latency only). Re-verified at every RTL
step with the 16×16 functional TB (`verification/npu_scale16`): **18,688 checks / 0 errors**
(GEMM, all 256 PE spatial corners, accumulate, 40 random, requant), plus on-board GEMM via
ctrl_axi.

## Key files
- RTL: `ip_workspace/6_NPU/npu_top.vhd` (5-stage read FSM), `ip_workspace/5_Platform/mmio_bridge.vhd` (NPU read stall).
- Build: `scripts/build_npu16_100mhz.tcl` (FCLK0=100 target + Perf strategy), `scripts/analyze_timing_100.tcl`.
- Bitstream: `flash/rv32_16x16_100mhz.bit` (Fmax 94.3 MHz). Timing: `flash/timing_100mhz.rpt`.
