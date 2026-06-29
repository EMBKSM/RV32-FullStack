# Unified NPU / GPU compute fabric — share the DSP array by mode

**Goal.** The XC7Z020 has only 220 DSP. The 16×16 NPU eats ~200; a separate 8-lane
GPU needs +8 → 210 (95 %), which won't route. But **the NPU and the GPU never run at
the same time** (the firmware does a GEMM *or* a vector kernel, not both at once). So
instead of giving the GPU its own DSPs, **let the GPU borrow 8 of the NPU's PEs' DSPs**,
selected by a mode bit. The GPU then adds **0 DSP** → the full 16×16 NPU + GPU fits.

## The shared primitive: one DSP, two modes

Both engines already reduce to the DSP48E1's native `P = A*B + C`:

| | operands | C input | result |
|---|---|---|---|
| NPU PE (systolic MAC) | `a8 * b8` (INT8) | the running accumulator `p` | `p <= p + a8*b8` |
| GPU lane (VMUL/VMAC) | `a16 * b16` | `0` (VMUL) or `Vd` (VMAC) | `y = a16*b16 + c` |

So one DSP can serve **either** by muxing its A/B/C inputs on a `gpu_mode` bit:

```
A = gpu_mode ? sext(ga16) : sext(a8)
B = gpu_mode ? sext(gb16) : sext(b8)
C = gpu_mode ? gc          : p            -- add-C (GPU) vs accumulate (NPU)
P = A*B + C
   NPU mode: p  <= P   (registered accumulate, cleared per GEMM run)
   GPU mode: gy <= P   (one-shot product to the lane)
```

## Architecture

```
            ┌────────────── npu_array (16×16 = 256 PE) ──────────────┐
 NPU 0x3 ──►│  PE(0,0) … PE(0,7)  ← DUAL-MODE (also the 8 GPU MACs)   │
 (systolic) │  PE(0,8) … PE(15,15) ← NPU-only PEs                     │
            └────────────────────────────────────────────────────────┘
                        ▲ a/b operands, ▼ products
 GPU 0x4 ──► gpu_core ──┤  (8 lanes: regs, scratchpad, ALU non-mul)
 (SIMT)        lane k VMUL/VMAC ──► shared PE(0,k).gpu port ──► product back
               lane k other ALU (add/sub/logic/shift/min/max/cmp) ──► LUTs in-lane
```

- **8 dual-mode PEs** = `PE(0,0..7)` (row 0, cols 0–7). They keep doing systolic MAC in
  NPU mode (the NPU is still a full 16×16), and become the GPU's 8 multipliers in GPU mode.
- **gpu_lane loses its own DSP** (`madd`). Each lane exports `(a16,b16,c, is_mul)` to its
  shared PE and reads the product back. Everything else in the lane (the vector regfile,
  the add/sub/and/or/xor/shift/min/max/slt/seq ALU) stays as LUTs — those don't use DSP.
- **Mode select** = which engine is running: NPU `busy` → systolic; GPU `busy` → the 8
  shared PEs take GPU operands. They are mutually exclusive (the CPU launches one, polls
  DONE, then the other), so a simple `gpu_active` mux is race-free.

## Interfaces (RTL deltas)

- `npu_pe`: add generic `GPU_LANE : boolean := false`. When true, add ports
  `gpu_mode, ga(15:0), gb(15:0), gc(31:0), gy(31:0)` and mux the DSP A/B/C as above.
  Non-GPU PEs are unchanged (no extra ports/logic → no area cost on the other 248 PEs).
- `npu_array` / `npu_top16`: instantiate `PE(0,0..7)` with `GPU_LANE=true` and surface
  their gpu ports as a bus to the top.
- `gpu_lane`: drop `madd`; output `mul_a/mul_b/mul_c` + take `mul_p` in for A_MUL/A_MAC.
- `gpu_core` / `mmio_bridge`: route the 8 lanes' `mul_*` to the array's gpu ports;
  drive `gpu_mode` from `gpu busy`.

## Result — VERIFIED (Vivado 2025.2, xc7z020clg400-1)

**1) The shared primitive is one DSP.** OOC synth of the dual-mode `npu_pe`
(`GPU_LANE=true`) → **exactly 1 DSP48E1**, mapped `(C or P)+A*B` (A=16, B=16, C=32,
P=32): the DSP does `A*B+C` for the GPU lane *or* `A*B+P` (accumulate) for the NPU,
selected at runtime. Cell usage: 1×DSP48E1, 2×LUT2, 32×LUT3, 16×FDRE.

**2) The GPU adds 0 DSP.** OOC synth of `unified_top` (full 16×16 NPU + 8-lane GPU
wired through the shared bus):

| | DSP | % of 220 | fits XC7Z020? |
|---|---|---|---|
| 16×16 NPU + **separate** 8-lane GPU | 210 | 95 % | no — routing stalls |
| 16×16 NPU + GPU **sharing 8 PE DSPs** | **202** | **92 %** | **yes** — = the silicon-proven core+NPU point |

The 8 GPU lane multipliers vanish into 8 of the NPU's 200 PE DSPs. 202 ≈ the already
silicon-verified core+NPU build (ran GEMM on the board, WNS −0.118 @106 MHz slow corner)
→ routes + closes timing, now with the GPU available too.

**3) Functional — all GPU kernels pass on the shared NPU DSPs.** `tb_unified` (gpu_top +
npu_top16 wired exactly as `mmio_bridge`, NPU idle) runs the C-golden kernels:

```
vector_add : checked 8 lanes      (non-mul ALU path)
saxpy(VMUL): checked 8 lanes      <- multiply runs on the borrowed NPU DSP
relu       : checked 8 lanes      (min/max path)
vmac(A*B+C): checked 8 lanes      <- accumulate (C=Vd) runs on the borrowed NPU DSP
==== UNIFIED TB: ALL TESTS PASS (GPU mul on shared NPU DSPs) ====
```

**4) Board bitstream — it fits, routes, and (essentially) closes 100 MHz.** Full Zynq
build (PS7 + the unified PL) on xc7z020clg400-1, strategy Performance_ExplorePostRoutePhysOpt:

| metric | result |
|---|---|
| DSP48E1 (whole platform: core + caches + 16×16 NPU + GPU) | **202 / 220 (92 %)** |
| Routing | **0 failed nets, 0 overlaps** (the separate 210-DSP build stalled here) |
| Hold (WHS) | **+0.045 ns — met** |
| Setup (WNS @100 MHz, post-route phys_opt) | **−0.054 ns** (Fmax ≈ 99.5 MHz; better than the silicon-proven core+NPU at −0.118) |
| Bitstream | **`fpga/flash/rv32_unified_100mhz.bit` (3.9 MB) generated** |

Same ~−0.05 ns slow-corner setup as the already-silicon-verified core+NPU build (which
ran GEMM on the board), now carrying the GPU too. Ready to flash + JTAG-test.
(Build: bump the platform-IP version each run so Vivado re-synthesizes from current
source; add `fpga/constraints/zybo_z7_20_{gpio,pmod}.xdc` to the impl constraint set.)

## RTL deltas (as built)

- `npu_pe`: generic `GPU_LANE`; one multiply `mul_a*mul_b + mul_c` with operand muxes
  (`use_gpu` picks GPU 16-bit operands + C, or NPU 8-bit operands + P-accumulate). 1 DSP.
- `npu_array`/`npu_top`/`npu_top16`: `NLANE=8`; PE(0,0..7) built `GPU_LANE=true`, their
  gpu ports surfaced as a flat bus (`gpu_mode`, `g_a/b/c_flat`, `g_y_flat`).
- `gpu_lane`: multiplier removed (A_MUL/A_MAC drive 0; the core overrides from the PE).
- `gpu_core`: drives `g_a/b/c_o` from the registered operands (valid S_EX), reads
  `g_y_i` in S_WB for VMUL/VMAC (aligned with the non-mul `res_r`); `gpu_active`→gpu_mode.
- `gpu_top`: threads the bus to `gpu_core`.
- `mmio_bridge`: connects `gpu_top` ↔ `npu_top16` over the shared bus (`u_g_a/b/c/y`,
  `u_gpu_mode`). NPU and GPU are mutually exclusive at the firmware level → race-free.
