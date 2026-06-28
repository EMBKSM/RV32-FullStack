# Dual-core (rv32_dual) — OOC synthesis & timing

OOC results on `xc7z020clg400-1` @ **100 MHz** (10 ns), Vivado 2025.2. Companion to
the GPU closure in `docs/GPU_DESIGN.md` §11.

## Result: cores meet 100 MHz; shared memory needs BRAM backing

`rv32_core` already exposes its instruction/data memory as **ports** (no internal
RAM), so a single-core OOC run measures real core logic + timing cleanly:

| Metric | rv32_core (1 core) |
|---|---|
| Slice LUT | 2,261 (4.25 %) |
| Slice FF | 2,815 (2.65 %) |
| BRAM / DSP | 0 / 0 |
| **WNS @ 100 MHz** | **+0.110 ns — MET** (0 failing EP of 5,182) |
| Critical path | `idex_rs1 → ifid_pc4` (branch / load-use feedback — the 5-stage core's intrinsic limiter) |

So the **dual-core compute fits and closes easily**: 2 × core ≈ **4.5 k LUT / 5.6 k FF /
0 BRAM / 0 DSP**, both cores at 100 MHz. The cores are independent; the only cross-core
logic is `rv32_shared` (hart id + one-shot barrier + a small scratchpad), not a new
critical path.

## Caveat: the sim memories are combinational (not impl-ready)

`rv32_dual`'s 1024-word private imem/dmem and `rv32_shared`'s 256-word scratchpad are
coded as **ideal combinational-read arrays** — perfect for the bring-up testbench, but
hostile to synthesis: they infer huge distributed-RAM read muxes.

- `rv32_dual` whole (1 K memories) → distributed RAM `RAM64M ×352`; synth's timing-opt
  phase stalls on the giant combinational mux.
- `rv32_shared` alone → **40 k LUT / 8.2 k FF** OOC (a 3-port combinational 256-word
  scratchpad + signed `mod`), i.e. the number is dominated by the memory coding, not
  the coordination logic.

This is the **same issue the GPU had** before its scratchpad was moved to BRAM
(`gpu_core` §11). For an implementation-ready multicore the shared scratchpad (and the
cores' instruction/data memory in a real SoC) should be **BRAM-backed (registered
read)** — single-/dual-port for the cores, and a banked or arbitrated dual-port BRAM
for `rv32_shared` (it has 3 access ports, so slightly more involved than the GPU's).

## Bottom line

Functionally verified (xsim, dual-core SPMD vector-add PASS) and the **compute path is
timing-clean at 100 MHz**. Remaining work for a real build = BRAM-back the shared
scratchpad + per-core memory, mirroring the GPU scratchpad refactor.

## Repro

`sim/multicore/synth_impl_core.tcl` (clean single-core OOC + timing),
`sim/multicore/dual_ooc.xdc` (10 ns clock). Run via a headless
`vivado -mode batch -source <tcl>`.
