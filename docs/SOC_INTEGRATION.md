# Full SoC integration — core + NPU16 + GPU (OOC @ 100 MHz)

`rv32_platform` (the board top: `rv32_ctrl_axi` + `rv32_core` + caches +
`mmio_bridge` → **NPU16 + GPU + peripherals**) synthesized and implemented
out-of-context on `xc7z020clg400-1`, 100 MHz (10 ns). This is the first build with
the GPU wired into the live SoC bus alongside the NPU.

## It fits — DSP is the binding resource

| Resource | Used | Avail | % |
|---|---|---|---|
| Slice LUT | 21,368 | 53,200 | 40 % |
| Slice FF | 12,761 | 106,400 | 12 % |
| Block RAM (tiles) | 16 (12×RAMB36 + 8×RAMB18) | 140 | 11 % |
| **DSP48** | **218** | **220** | **99 %** |

The NPU's 16×16 systolic array eats ~202 DSP; the GPU adds **16** (one 16×16 DSP per
lane × {VMUL, VMAC}). **218 / 220 — 2 to spare.** This is exactly why the GPU multiply
was sized to 16×16 on a single DSP/lane: to slot into the ~18 DSP left after the NPU.
Elaboration + synthesis are clean (0 errors) — the GPU is correctly integrated at
`u_mmio/u_gpu`.

## Timing: WNS −0.220 ns (12 of 58,742 endpoints), default flow

| | WNS | TNS | Failing EP | WHS |
|---|---|---|---|---|
| post-route (default place/route) | **−0.220 ns** | −1.163 | 12 / 58,742 | +0.031 (hold OK) |

Critical path: **inside the GPU** — `u_mmio/u_gpu/u_core/pc_reg[0] → pc_reg[1]`
(the `SBNZ` / PC-adder branch path; CARRY4×6 + the imem read, route 69 %).

This run used the **plain** OOC flow — no `synth -retiming`, no `place/route
-directive Explore`, no `phys_opt_design`. The **standalone** GPU closed this very
class of path from −0.338 to **+0.032** using exactly those directives, and the board
core+NPU build closes at 100/106 MHz the same way. So −0.220 with 12 near-paths is the
*un-optimized* integrated number; applying the proven directives is expected to close
the integration to MET. (Left as the next step — the optimized full-SoC impl is the
~20-30 min congested place/route, the GPU was not in the previously board-verified
core+NPU build.)

## Bottom line

The GPU **fits alongside the NPU** (DSP 218/220) and the integrated SoC is **0.22 ns
from 100 MHz on the default flow**, limited by an optimizable GPU-internal branch path.
Repro: `fpga/scripts/synth_platform_ooc.tcl` + `fpga/scripts/platform_ooc.xdc`.
