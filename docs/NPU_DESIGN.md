# RV32-FullStack NPU — INT8 8×8 Systolic GEMM Accelerator

**Design spec v0.1** — MMIO-attached matrix-multiply accelerator for the RV32 soft-core.
Built on the FPGA area freed by the cache→LUTRAM conversion (Slice 97%→19%, DSP 0/220, BRAM 12/140).

---

## 1. Goals & scope

- **Operation:** `C += A · B` (general matrix multiply, GEMM), INT8 inputs, INT32 accumulate.
- **Core:** 8×8 = 64 PE **output-stationary systolic array**; each PE = one DSP48E1 MAC.
- **Tile:** one invocation computes an **8×8 output tile** over a contraction depth `K` (1…256).
  Larger matrices are tiled by the driving program (CPU loops over 8×8 output tiles, accumulating across K-tiles).
- **Driver:** the **RV32 CPU** programs the NPU through an MMIO window (load A/B tiles → `start` → poll `done` → read C). The PS host can also drive it (same registers, reachable over the existing AXI path).
- **Non-goals (v0.1):** DMA, on-the-fly requantization, weight reuse across tiles, >8×8 arrays. All listed as future work (§10).

## 2. Top-level integration & memory map

The NPU is a new slave on the CPU data bus, decoded as a dedicated window separate from the
existing peripherals (MMIO @ `0x1000_0000`) and the PS control slave (`0x4000_0000`):

| Region | Base | Size | Contents |
|---|---|---|---|
| NPU window | `0x3000_0000` | 8 KiB | control regs + A/B/C scratchpads |

Address decode is added in `rv32_platform` (data-side bridge): `addr[31:24]==0x30` → NPU select.
Inside the window (offset = `addr[12:0]`):

| Offset | R/W | Name | Description |
|---|---|---|---|
| `0x0000` | W/R | `CTRL` | bit0 `start` (1-cycle pulse), bit1 `clr_acc` (clear accumulators before run) |
| `0x0004` | R | `STATUS` | bit0 `busy`, bit1 `done` (latched until next start), bits[15:8] state |
| `0x0008` | W/R | `K_DIM` | contraction depth K (1…256) |
| `0x000C` | W/R | `CFG` | reserved (future: requant shift/scale, accumulate-mode) |
| `0x0800`–`0x0FFF` | W | `A_BUF` | A tile, row-major INT8: byte `i*K + k`, 4×INT8 packed/word (2 KiB) |
| `0x1000`–`0x17FF` | W | `B_BUF` | B tile, row-major INT8: byte `k*8 + j`, 4×INT8 packed/word (2 KiB) |
| `0x1800`–`0x18FF` | R | `C_BUF` | C tile, 8×8 INT32: word `i*8 + j` (256 B) |

Scratchpads are dual-port BRAM (port A = CPU MMIO read/write; port B = systolic feeders/collector).

## 3. Dataflow — output-stationary systolic

Each PE`[i][j]` (i = row 0..7, j = col 0..7) holds the running sum for output element `C[i][j]`.

- **A** streams **left→right**: row *i* of A enters PE`[i][0]`, shifting one PE right per cycle.
- **B** streams **top→bottom**: col *j* of B enters PE`[0][j]`, shifting one PE down per cycle.
- Inputs are **skewed (diagonal)** so the matching operands meet:
  `A[i][k]` enters PE`[i][0]` at cycle `k+i`; `B[k][j]` enters PE`[0][j]` at cycle `k+j`.
  Both then arrive at PE`[i][j]` at cycle `k+i+j`, where they are multiplied and accumulated.
- After the last contraction element, the bottom-right PE finishes at cycle `≈ K + 14`.
  Total run ≈ `K + 2*(8-1) + pipeline` cycles; then C is read out over MMIO.

Skew is produced by the **feeders**: A row *i* is delayed by *i* cycles; B col *j* delayed by *j* cycles
(staggered reads from the scratchpads via small per-lane delay chains).

## 4. PE microarchitecture (DSP48E1)

```
PE[i][j]:
  inputs : a_in (int8, from left), b_in (int8, from top), en
  regs   : a_reg, b_reg (int8 pipeline) ; acc (int32)
  each clk when en:
    if clr_acc: acc <= 0
    else:       acc <= acc + signed(a_in) * signed(b_in)   -- INT8*INT8 -> INT16 -> +INT32
    a_reg <= a_in    -- pass right  (a_out = a_reg -> PE[i][j+1])
    b_reg <= b_in    -- pass down   (b_out = b_reg -> PE[i+1][j])
  output : acc (read by collector)
```

- `acc <= acc + a*b` with signed operands and `(* use_dsp = "yes" *)` → Vivado maps the multiply+accumulate
  into a single **DSP48E1** (25×18 mult + 48-bit P accumulator); INT8 operands sign-extended into the ports.
- 64 PEs → **64 DSP48E1** (of 220 free). a/b pass-through registers use the DSP input pipeline regs or fabric FFs.
- INT32 accumulator is safe: max |Σ| for K=256, INT8 = 256·127·127 ≈ 4.1M < 2³¹.

## 5. Control FSM & timing

```
IDLE ──start──▶ RUN ──(K+14 cyc)──▶ DONE ──(read C)──▶ IDLE
                 │ stream A/B with skew, accumulate
 clr_acc clears all acc at RUN entry (if set)
```

- `IDLE`: ready; `STATUS.busy=0`. On `CTRL.start`: latch K, optionally clear acc, go `RUN`.
- `RUN`: feeders stream A/B from scratchpads with skew for `K+14` cycles; `busy=1`.
- `DONE`: `busy=0`, `done=1`; C scratchpad holds the 8×8 INT32 tile; CPU reads `C_BUF`. `done` clears on next `start`.

At a 50 MHz PL clock (current design), an 8×8×K=64 tile ≈ 78 compute cycles ≈ 1.6 µs (excludes MMIO load/read).

## 6. Programming model (CPU sequence)

```
1. poll STATUS until !busy
2. write K_DIM = K
3. write A tile  -> A_BUF   (8*K bytes, packed)
4. write B tile  -> B_BUF   (K*8 bytes, packed)
5. write CTRL = start | clr_acc      (clr_acc=1 for a fresh C, 0 to accumulate onto prior C)
6. poll STATUS until done
7. read C_BUF  (64 × INT32)  -> C[i][j]
8. (tiling) repeat over K-tiles with clr_acc=0, and over output tiles
```

## 7. Resource estimate (XC7Z020, post cache→LUTRAM headroom)

| Resource | NPU est. | Free now | Fits |
|---|---|---|---|
| DSP48E1 | 64 | 220 | ✓ (29%) |
| BRAM18 | ~4 (A/B/C scratchpads) | ~256 (128 tiles) | ✓ |
| LUT | ~2–4k (feeders, FSM, MMIO, acc routing) | ~47k | ✓ |
| FF | ~2–3k | ~101k | ✓ |

Comfortable fit; leaves room to later scale to 16×16 (§10).

## 8. Verification plan

1. **PE unit:** random signed INT8 a/b streams; check acc == Σ a·b vs software golden.
2. **Array/GEMM:** random INT8 A(8×K), B(K×8) for K ∈ {1,2,7,8,63,64,255,256}; compare 8×8 C
   against a software INT32 GEMM golden (incl. sign/boundary: all-min `-128`, all-max `127`, mixed).
3. **Skew/timing:** verify the diagonal feed alignment (no off-by-one) across K values.
4. **MMIO:** load via the register map, start, poll, read C; confirm end-to-end through the bus model.
5. **Integration:** after platform wiring, re-run the existing CPU regression (NPU idle must not perturb it),
   then a CPU-driven GEMM program vs golden. Finally board bring-up (#37/#59/#60) with the NPU bitstream.

## 9. RTL module plan

```
npu_pe.vhd          -- single INT8 MAC PE (DSP48E1), a/b pass-through
npu_array.vhd       -- 8×8 PE mesh + accumulator read-out
npu_feeder.vhd      -- A/B skew feeders (per-lane delay) from scratchpads
npu_scratch.vhd     -- dual-port BRAM wrappers (A_BUF, B_BUF, C_BUF)
npu_ctrl.vhd        -- FSM (IDLE/RUN/DONE), K counter, clr_acc
npu_mmio.vhd        -- bus slave: CTRL/STATUS/K_DIM + scratchpad address decode
npu_top.vhd         -- wires the above; one slave port to the CPU data bus
```

## 10. Requantization (done)

`npu_top` carries a `CFG` register (byte offset `0x..0C`: `mult[31:16]`, `shift[13:8]`,
`enable[0]`). When `enable=1`, a C read returns the requantized INT8 instead of raw INT32:
`clip((acc*mult + round) >> shift, -128, 127)`, sign-extended (round = half-up, arithmetic
shift). `enable=0` returns raw INT32 (default, no regression). Verified in
`verification/npu_regress` (axis 5: scale/shift/clip boundary + 30 random + OFF→raw),
10240 checks / 0 errors.

## 11. Scale-up: generic N, 16×16 verified (done — functional)

`npu_array` and `npu_top` now take a generic `N` (default 8). `npu_top16.vhd` fixes `N=16`.
The address map scales with `NBITS = ceil(log2 N)`: for **N=8** it is **bit-identical** to the
original 8 KiB design (so every prior 8×8 result still holds — re-verified: 10240 checks/0 err),
and for **N=16** it is a 16 KiB window (region `addr[13:12]`: A=`0x1000`, B=`0x2000`, C=`0x3000`).

- **Functional verification (xsim):** `verification/npu_scale16/tb_npu_scale16.sv` — GEMM over
  K∈{1,2,63,64}×INT8 extremes, spatial single-element at the **full 16×16 corners {0,15}²+middle**
  (exercises all 256 PEs + the 16-wide row/col decode), accumulate mode, 40 random GEMMs, and
  requant. **18688 checks / 0 errors, ALL PASS.**
- **Throughput:** 16×16 = **256 MACs/cycle** = 4× the 8×8 (64).

### DSP fit on XC7Z020 (220 DSP48E1) — synthesis decision (board-bound)
A spatial 16×16 needs 256 multipliers but the device has **220 DSP**, so naive mapping does not
fit (over by 36). Paths to a board-ready 16×16:

1. **INT8 dual-packing** — 2 INT8 MACs share one DSP48E1 (shared activation) → **128 DSP**. Fits
   with margin; but 7-series DSP48E1 (25×18) packing needs sign-correction and is more delicate
   than UltraScale (27×18). Higher RTL risk.
2. **Hybrid 220 DSP + 36 LUT-MACs** — keep 220 PEs on DSP, map the remaining 36 PEs to LUT
   multipliers (~2.5k LUT, easily covered by the LUTRAM-freed budget). Lowest risk.
3. **14×14 = 196 DSP** — fits cleanly with in-DSP accumulate, no packing; ~3× the MACs of 8×8.
4. **Logical 16×16 on the 8×8 array** — time-fold four quadrants on the verified 64-DSP core; no
   extra DSP, throughput unchanged (problem-size scale, not a spatial speedup).

The generic-N RTL above is the common prefix of options 1–3; the functional datapath is proven, so
the remaining work is purely the synthesis/pack strategy at board bring-up.

### Synthesis result — option 2 (hybrid), OOC on xc7z020clg400-1, 50 MHz
`npu_pe` gained a `DSP_USE` generic (drives the `use_dsp` attribute); `npu_array` gained
`DSP_BUDGET`, routing PEs `p < DSP_BUDGET` (row-major) to DSP48E1 and the rest to LUT-fabric MACs.
`npu_top16` sets `DSP_BUDGET=220`. Out-of-context synthesis (`scripts/ooc_synth_npu16.tcl`):

| Resource | 16×16 hybrid (NPU only) | Avail | % | 8×8 baseline (full design) |
|---|---|---|---|---|
| DSP48E1 | **220** | 220 | **100 %** | 64 |
| Slice LUT | 8096 | 53200 | 15.2 % | 7027 (whole SoC) |
| LUT as Mem | 520 | 17400 | 3.0 % | 1378 |
| Slice Reg | 3140 | 106400 | 3.0 % | 5777 |
| CARRY4 | 934 | — | — | — |

- **Fit:** 220/220 DSP — exact. The RV32 core uses **0 DSP** (confirmed from the implemented 8×8
  design: total = 64 = NPU only), so 220 NPU + 0 core = 220 = the whole DSP column. It fits, with
  **zero DSP margin** (drop `DSP_BUDGET` to e.g. 200 → 56 LUT-MACs if spare DSP is wanted).
- **Timing:** WNS **+8.344 ns** at the 20 ns (50 MHz) target, 0 failing endpoints (post-synth
  estimate ⇒ ~85 MHz headroom). Worst path is a LUT-MAC PE (row 15) → still +8.3 ns slack, so the
  fabric MACs are not the bottleneck.
- **Throughput:** 256 MAC/cycle (4× the 8×8) on the same 50 MHz clock.

This makes a board-ready 16×16 a drop-in for the platform: repackage the IP (the bridge must widen
the NPU address slice to `addr[13:0]` and instantiate `npu_top16`), then synth→impl→bitstream→BOOT.bin
(deferred until board bring-up). Scratchpads currently fall back from distributed-RAM to FF/LUT (the
2-D array confuses RAM inference — same fix as the cache: split into per-lane 1-D arrays) — harmless
for fit/timing, a later area tidy-up.

## 12. Future work

- **DMA / direct memory read** so the NPU pulls A/B from CPU memory instead of MMIO copy.
- **Weight-stationary mode** for conv/inference weight reuse.
- **im2col helper** so CNN conv maps onto the GEMM engine.
