# 16×16 NPU SoC — Fmax Optimization Result

**Target:** push the RV32 + 16×16 INT8 NPU SoC clock as high as possible on Zynq XC7Z020-CLG400-1.
**Headline:** Fmax **37 MHz → 94.3 MHz** (≈2.5×) with zero change to the MAC array, by pipelining
the two NPU read-back bottlenecks. Board operating point: **90.9 MHz** (clean, FCLK0 ÷11).

## Fmax progression

| Build | NPU read-back | impl strategy | WNS @100MHz | crit. path | **Fmax** | build time |
|-------|---------------|---------------|-------------|-----------|----------|-----------|
| v1 16×16 (orig) | combinational 256:1 mux | RuntimeOptimized | (−6.74 @ 50MHz) | 26.74 ns | **37.4 MHz** | 1 h 17 m |
| v2 | 3-stage (col→row→finalize) | default + phys_opt | −3.293 ns | 13.29 ns | **75.2 MHz** | 8 min |
| v3 | 5-stage (+ requant pipeline) | Perf_ExplorePostRoutePhysOpt | **−0.602 ns** | 10.60 ns | **94.3 MHz** | ~25 min |

Hold met throughout (WHS ≥ +0.014 ns). Failing endpoints @100MHz: 3196 → **817**.

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

## Remaining path (the last 0.6 ns to 100 MHz)

Worst path @100MHz is now the systolic **`t` counter → PE accumulator** control fan-out
(`t_reg → gen_row[13].gen_col[0].u_pe/p_reg`, 10.46 ns). Closing 100 MHz from here would need
(a) pipelining/replicating that control broadcast, and (b) the RV32 5-stage core itself — a
50 MHz-era design whose ALU/forward/cache paths make up most of the 817 remaining failing
endpoints. That is a core-pipeline redesign (deferred by choice: "achievable max Fmax").

## Board operating point

The v3 bitstream closes timing at any clock ≤ **94.3 MHz**. FCLK0 (from the PS IO-PLL, 1000 MHz)
divides only in integer steps, so the highest clean FCLK0 step is **90.9 MHz (÷11)** → setup
slack +0.40 ns, hold +0.016 ns. To reach the full 94.3 MHz ceiling exactly, instantiate a PL
MMCM/clock-wizard ("PLL MUX") fed by FCLK0 — left as a follow-up.

- 50 MHz (orig 8×8 baseline) → **90.9 MHz** verified 16×16 = **1.8× clock**, **4× the MACs** (64→256).

## Functional verification

The pipelined read-back is bit-identical to the original (latency only). Re-verified at every RTL
step with the 16×16 functional TB (`verification/npu_scale16`): **18,688 checks / 0 errors**
(GEMM, all 256 PE spatial corners, accumulate, 40 random, requant), plus on-board GEMM via
ctrl_axi.

## Key files
- RTL: `ip_workspace/6_NPU/npu_top.vhd` (5-stage read FSM), `ip_workspace/5_Platform/mmio_bridge.vhd` (NPU read stall).
- Build: `scripts/build_npu16_100mhz.tcl` (FCLK0=100 target + Perf strategy), `scripts/analyze_timing_100.tcl`.
- Bitstream: `flash/rv32_16x16_100mhz.bit` (Fmax 94.3 MHz). Timing: `flash/timing_100mhz.rpt`.
