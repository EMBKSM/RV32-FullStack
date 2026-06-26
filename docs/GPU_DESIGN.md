# RV32-FullStack GPU — SIMT-lite Vector Coprocessor

A small data-parallel coprocessor for the RV32 SoC, in the spirit of a GPU's SIMT
execution: **one instruction stream drives N lanes in lockstep**, each lane holding
its own slice of the vector registers, with a **per-lane predicate mask** for
divergence (if-conversion). It is attached to the CPU exactly like the NPU — a
memory-mapped accelerator the RV32 core reaches through ordinary loads/stores.

## 1. Why this shape (resource-driven)

Post-implementation utilization on the XC7Z020 leaves:

| Resource | Used | Free | Note |
|---|---|---|---|
| LUT | 14,851 / 53,200 | ~38,000 | abundant |
| FF | 10,377 / 106,400 | ~96,000 | abundant |
| BRAM36 | 12 / 140 | ~128 | abundant |
| DSP48 | 202 / 220 | **18** | the NPU ate them |

So the design rule is simple: **lanes are LUT-based** (ALU *and* multiplier built
from fabric, `use_dsp = "no"`), keeping all 18 remaining DSPs free. With `N = 8`
lanes the estimate is ~12–15 k LUT / ~4 k FF / a few BRAM / 0 DSP — a comfortable
fit that still leaves room for the multicore stage.

## 2. Execution model

- **Lockstep SIMT.** A single program counter fetches one instruction; the decoder
  broadcasts it to all `N` lanes. Lanes are *not* independent threads with their own
  PC — divergence is handled by **predication**, not by per-lane control flow.
- **Per-lane mask `M[N]`.** A vector compare (`VSLT`, `VSEQ`, …) writes a lane mask.
  Masked-off lanes still issue but commit nothing (their register/memory writes are
  suppressed). `MASKON` clears the mask back to all-active.
- **Uniform branches.** Control flow is scalar: branches test a scalar register or a
  reduction over the mask (`ANY`/`ALL`), so the whole warp branches together — enough
  for counted loops and simple kernels.
- **Lane id.** `VLID Vd` writes each lane its index `0..N-1`, enabling per-lane
  addressing (strided / gather-style access).

## 3. Programmer's model

- **Vector registers** `V0..V7`: each is `N × 32-bit` (one 32-bit element per lane).
- **Scalar registers** `S0..S7`: 32-bit, shared across lanes (addresses, loop counters,
  the `a` in SAXPY).
- **Predicate mask** `M`: `N` bits, 1 = lane active.
- **Data scratchpad**: `N`-bank BRAM, 32-bit words. Bank `k` holds element `k, k+N,
  k+2N, …` so a unit-stride vector access is fully parallel (one word per lane per
  cycle). The CPU sees it as a flat array through the MMIO data window.
- **Instruction memory**: small BRAM (e.g. 256 × 32-bit) the CPU writes the kernel into.

## 4. Instruction set (32-bit, fixed)

```
[31:26] opcode | [25:23] Vd/Sd | [22:20] Va/Sa | [19:17] Vb/Sb | [16:0] imm/addr
```

| Op | Mnemonic | Action (per active lane k) |
|----|----------|----------------------------|
| VLID | `VLID Vd`          | Vd[k] = k |
| VLD  | `VLD Vd, Sa, imm`  | Vd[k] = SP[ Sa + imm + k ]   (unit-stride; banked) |
| VST  | `VST Vb, Sa, imm`  | SP[ Sa + imm + k ] = Vb[k] |
| VMOVI| `VMOVI Vd, imm`    | Vd[k] = sext(imm) |
| VADD/VSUB | `Vd, Va, Vb`  | Vd[k] = Va[k] ± Vb[k] |
| VAND/VOR/VXOR | `Vd,Va,Vb`| bitwise |
| VSLL/VSRL/VSRA | `Vd,Va,Vb`| shift by Vb[k][4:0] |
| VMIN/VMAX | `Vd, Va, Vb`  | signed min / max |
| VMUL | `Vd, Va, Vb`       | Vd[k] = (Va[k]*Vb[k])[31:0]  (LUT multiplier) |
| VMAC | `Vd, Va, Vb`       | Vd[k] += Va[k]*Vb[k]  (SAXPY/dot in one op) |
| VSLT/VSEQ | `Va, Vb`      | M[k] = (Va[k] < / == Vb[k]) |
| MASKON | `MASKON`         | M[k] = 1 for all k |
| SADDI | `Sd, Sa, imm`     | scalar Sd = Sa + imm |
| SBNZ  | `Sa, imm`         | scalar branch: if Sa != 0, PC += imm |
| HALT  | `HALT`            | stop, raise `done` |

A scalar immediate broadcast (`VMOVI`, and `VADD` with `Vb` = a scalar-broadcast reg)
covers SAXPY's `a*X`. `VMAC` makes dot-product / SAXPY a single inner-loop op.

## 5. Microarchitecture

```
gpu_top  (MMIO slave @ 0x4xxx_xxxx)
 ├─ ctrl/status regs : START, DONE, N_lanes(ro), kernel len, scalar args
 ├─ imem  (BRAM)     : CPU writes kernel here
 ├─ scratchpad       : N-bank BRAM (CPU R/W via data window; lanes R/W parallel)
 └─ gpu_core
      ├─ fetch/decode : 1 PC, 1 instruction -> broadcast bus
      ├─ scalar unit  : S0..S7, branch resolve
      ├─ mask unit    : M[N], ANY/ALL reduction
      └─ N × gpu_lane : 32-bit ALU + LUT multiplier + V-regfile slice (V0..V7)
```

Pipeline: **fetch → decode/broadcast → lane execute → writeback** (single-issue,
in-order). Vector load/store take one extra cycle for the banked BRAM access. A whole
`N`-element vector op retires per cycle → throughput `N` ops/cycle vs the scalar core's
~1 op / several cycles.

## 6. CPU ↔ GPU interface (mirror of the NPU)

`mmio_bridge` already decodes `is_npu when c_addr(31:28)=x"3"`. Add the twin:

```
is_gpu <= '1' when c_addr(31 downto 28) = x"4" else '0';
u_gpu : entity work.gpu_top
    port map (clk, rst, sel=>is_gpu, we=>c_we, re=>c_re,
              addr=>c_addr(N..0), wdata=>c_wdata, rdata=>gpu_rd,
              rd_valid=>gpu_rd_valid);
```

Address sub-map inside the 0x4 window:

| Offset | Meaning |
|--------|---------|
| `0x0000` | CTRL  (bit0 START, write 1 to launch) |
| `0x0004` | STATUS (bit0 DONE, bit1 BUSY) |
| `0x0008` | N_LANES (read-only) |
| `0x000C` | KERNEL_LEN (instruction count) |
| `0x0010..` | SCALAR_ARG[0..7] |
| `0x1000..` | IMEM window (write kernel words) |
| `0x4000..` | SCRATCHPAD window (R/W vector data, flat) |

**Driver flow (RV32 firmware):** write data → IMEM ← kernel → set KERNEL_LEN, scalar
args → write CTRL.START → poll STATUS.DONE → read scratchpad results.

## 7. Demo kernels

- **vector_add**: `C[i] = A[i] + B[i]` — `VLD V0,A; VLD V1,B; VADD V2,V0,V1; VST V2,C`.
- **saxpy**: `Y[i] = a*X[i] + Y[i]` — scalar `a` broadcast, `VMUL` + `VADD` (or `VMAC`).
- **relu / max**: `Y[i] = max(0, X[i])` — `VMOVI V1,0; VMAX V2,V0,V1` (pairs with the NPU).

Each processes `N` elements per pass; a scalar loop (`SADDI`/`SBNZ`) strides over the
array for arbitrary length.

## 8. Verification plan (no board / no Vivado-in-loop here)

1. **C golden model** (`sim/gpu/gpu_model.c`) — executes the same ISA, defines the
   bit-exact expected results, and emits stimulus + golden `.mem` vectors.
2. **Self-checking VHDL testbench** (`sim/gpu/tb_gpu.vhd`) — loads the kernel + data,
   runs, and `assert`s every scratchpad result against the golden vectors.
3. **xsim run script** (`sim/gpu/run_gpu.tcl` / `.f`) for host Vivado, plus a path for
   GHDL if a simulator is later available.
4. **SoC-level**: an RV32 assembly driver (`sw/host/gpu_demo.s`) that launches a kernel
   end-to-end through the MMIO window, mirrored by the existing NPU SoC testbench.
5. Compare GPU vs scalar-core cycle counts to quantify the speedup.

## 9. Synthesis notes (OOC synth_design, xc7z020clg400-1)

Out-of-context synthesis surfaced two places where the single-cycle,
*combinational-read* model (great for simulation) is hostile to synthesis:

- **Multiplier.** A full `32x32` LUT multiply per lane (`use_dsp="no"`, the first
  cut to "preserve DSPs") was impractical: ~16 min synth and ~16 k LUT for the 8
  lanes. Reworked to a **16x16 -> 32 signed multiply on one DSP48E1 per lane**
  (8 lanes -> **8 DSP**, fits the ~18 free after the NPU): "Finished Synthesize"
  drops to **~24 s**. (16-bit operands are exact for the INT8/INT16-range kernels
  this GPU pairs with; the C golden model matches.)
- **Scratchpad / register files.** The async-read banked scratchpad infers as
  registers, not BRAM (`8 banks x 256 x 32 = 65 536` FF), which both bloats area
  and slows optimization. A synthesizable build should back the scratchpad and
  imem with **BRAM (synchronous read)** and pipeline the lanes behind `mem_stall`
  (mirroring how `rv32_core` uses its caches) -- a deliberate next step, kept out
  of this sim-first version for clarity.

Net: the design is functionally correct and simulation-verified (xsim, all three
kernels pass); making it *implementation*-efficient is a memory-architecture
refinement (DSP multiply done; BRAM-backed memories next).

## 10. Parameters

`N_LANES` (default 8), `VREGS` (8), `SREGS` (8), `IMEM_DEPTH` (256), `SP_WORDS_PER_BANK`
(256). All generics on `gpu_top`, so the lane count can be tuned to whatever the
post-place DSP/LUT budget allows without touching the rest of the SoC.
