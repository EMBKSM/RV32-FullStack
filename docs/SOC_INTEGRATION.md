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

### Closing attempt → it's congestion-bound, not logic-bound

Tried to close the −0.220 with the recipe that worked on the standalone GPU
(−0.338 → +0.032): `place/route -directive Explore` + `phys_opt_design`, then a
default `place/route` + 3× `phys_opt_design`. **Both stalled.** At **218/220 DSP
(99 %)** the placer/router/phys-opt have essentially no free fabric to move the
critical cells into, so each pass grinds for tens of minutes with the GPU's
`pc`/`SBNZ` path stuck at −0.220 (route is 69 % of it — pure congestion). The same
GPU `pc` path closes to **+0.032 standalone**, where it has room — so the logic is
fine; the integrated number is a **placement-congestion** artifact of packing the DSPs
to 99 %.

### The clean fix: free DSP headroom

The decisive lever is to **drop the GPU from 16 DSP to 8** — one DSP per lane doing
`A*B` *and* `A*B+C` (the DSP's native multiply-accumulate) instead of two. That takes
the SoC to **210/220 DSP**, giving the router the slack to place the GPU datapath
without the long detours. Cheaper alternatives: a **Pblock floorplan** separating the
NPU array from the GPU, or the **full board-project build** (PS + proper clock +
device constraints place things very differently from this flat OOC run).

Board precedent says the design is silicon-viable regardless: the core+NPU build ran
GEMM on real silicon at **WNS −0.118 @ 106 MHz (slow corner)** — slow-corner negative
slack still met on the actual device. So −0.220 OOC ≈ ~98 MHz worst-case, very likely
fine at 100 MHz on the board.

## Bottom line

The GPU **fits alongside the NPU at 218/220 DSP** and the integrated SoC sits **0.22 ns
from 100 MHz**, limited by **DSP-packing congestion** (not logic). Recommended close:
**GPU 16 → 8 DSP** (shared MAC) for routing headroom, or a Pblock floorplan / full
board build. Repro: `fpga/scripts/synth_platform_ooc.tcl` + `platform_ooc.xdc`.
