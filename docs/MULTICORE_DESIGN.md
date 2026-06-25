# RV32-FullStack Multicore — Dual-Core RV32 Cluster

A two-core cluster built from **unmodified `rv32_core` instances**, sharing one
small coordination block (`rv32_shared`) for hart identity, a barrier, and a
shared scratchpad. It demonstrates SPMD execution: the **same program** runs on
both cores, each steering its half of the work by reading its hart id.

## 1. Why this shape

`rv32_core` already exposes an **ideal-memory interface** — combinational
`imem`/`dmem` reads with a single `mem_stall` freeze — and is verified against
exactly that interface in the existing `rv32_soc` testbenches. So a cluster can
instantiate it as-is, give each core private combinational imem/dmem, tie
`mem_stall='0'`, and route only a shared *window* to a common block. No change
to the core, the pipeline, or the caches. `mhartid` stays 0 in the core; the
hart id is instead provided **per port** by the shared block (no core edit).

Resource fit is comfortable: each core is ~7.4 k LUT (0 DSP), so two cores plus
the GPU still sit well inside the ~38 k free LUT / 18 free DSP on the XC7Z020
(this cluster is a simulation/bring-up top, like `rv32_soc`; a synthesis build
would back the memories with BRAM + `mem_stall`).

## 2. Topology

```
            prog (both imems)          sp (preload/readback, port T)
                  │                         │
   ┌──────────────┴──────────┐   ┌──────────┴───────────┐
   │ rv32_core 0 (hart 0)    │   │     rv32_shared      │
   │  imem0  dmem0(private)  │   │  HARTID  BARRIER  SP │
   │     dmem bit31=1 ───────┼──►│ port A          port B◄─┐
   └─────────────────────────┘   └──────────────────────┘ │
   ┌─────────────────────────┐                             │
   │ rv32_core 1 (hart 1)    │   dmem bit31=1 ─────────────┘
   │  imem1  dmem1(private)  │
   └─────────────────────────┘
```

- **Private memory** (`bit31 = 0`): each core's own 4 KiB ideal imem + dmem.
- **Shared window** (`bit31 = 1`, i.e. `0x8000_0000+`): routed to `rv32_shared`,
  port A for core 0, port B for core 1. Reads are combinational (same cycle).

## 3. Shared block (`rv32_shared`)

| Byte offset | Name | Semantics |
|---|---|---|
| `0x000` | HARTID | read-only; **port A → 0, port B → 1** (this is how a core learns its id) |
| `0x004` | BARRIER | write → set this hart's *arrived* bit; read → 1 once **both** arrived (one-shot) |
| `0x100+` | SCRATCHPAD | shared words; two combinational core read ports; writes prioritized **A > B > T** |

A third **port T** lets the testbench preload inputs and read back results; it is
live regardless of reset so data can be staged while the cores are held reset.

## 4. SPMD demo — split vector-add

Both cores run `sim/multicore/spmd.s` (19 instructions, assembled by the project
assembler). Each core:

1. reads its hart id from `0x8000_0000`;
2. computes its element range — hart0 → `[0,4)`, hart1 → `[4,8)`;
3. loops: `C[i] = A[i] + B[i]` using shared-scratchpad loads/stores;
4. writes the barrier (`arrive`), then halts.

Scratchpad layout (`0x8000_0100` base): `A[0..7]`, then `B[0..7]`, then `C[0..7]`.
With `A[i]=i+1`, `B[i]=10(i+1)` the result is `C=[11,22,33,44,55,66,77,88]`,
with **hart0 producing C[0..3] and hart1 producing C[4..7]** — proving two cores
ran concurrently, were distinguishable by id, and shared memory coherently.

## 5. Verification

- **C golden model** `sim/multicore/mc_model.c` (PASSES) models `rv32_shared`'s
  port semantics (hart id, one-shot barrier, A>B>T write priority) and replays
  the exact accesses both cores make — emitting the golden `C`.
- **Self-checking TB** `sim/multicore/tb_rv32_dual.vhd`: loads the program into
  both imems, preloads A/B, runs, reads back `C`, asserts against golden.
- **Static review** (independent): instantiation, routing (bit31), combinational
  read-before-write timing, and single-driver checks all clear; two preload/range
  bugs found in review were fixed.
- **Host sim**: `sim/multicore/run_dual.bat` (xsim) → `==== DUAL-CORE TB: ALL PASS ====`.

## 6. Notes / extensions

- The barrier here is *one-shot* (single sync). The demo exercises **arrive**;
  a reduction kernel (hart0 sums all of `C` after the barrier *release*) would
  exercise the spin-on-release path, which the C model already checks.
- A synthesis-oriented version would replace the ideal combinational memories
  with BRAM + cache (reusing `cache_unit`/`icache_unit`) and assert `mem_stall`,
  and add a real arbiter if the cores ever share a single memory port.
