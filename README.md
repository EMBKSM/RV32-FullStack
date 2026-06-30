# RV32-FullStack

A from-scratch **RISC-V SoC on real silicon** (Zybo Z7-20 / Zynq XC7Z020): a 5-stage
**RV32I** core with I$/D$, a **16×16 INT8 systolic NPU**, an **8-lane SIMT-lite GPU**, and a
**unified compute fabric that lets the GPU borrow the NPU's DSPs** — so the full accelerator
suite fits in one small FPGA. You write RISC-V assembly on the PC, it streams to the core over
UART, runs on the board, and the registers update **live**.

> **Headline:** the NPU and GPU never run at the same time, so the 8 GPU multiply-lanes are
> *time-shared* onto 8 of the NPU's processing-element DSPs. The GPU therefore costs **0 extra
> DSP** — the whole SoC is **202/220 DSP (92 %)** instead of 210 (which would not route), and it
> is **verified on real silicon** (14/14 on-board tests pass @ 100 MHz). See
> [`docs/UNIFIED_NPU_GPU.md`](docs/UNIFIED_NPU_GPU.md).

```
 PC  ── rv32_gui.py / rv32_console.py  (assembler + UART console, live register view)
  │   USB-UART 115200 8N1
  ▼
 Zynq PS (ARM Cortex-A9) ── rv32_monitor.c   (command parser → AXI-Lite driver)
  │   AXI4-Lite  M_AXI_GP0 @ 0x4000_0000
  ▼
 Zynq PL  =  rv32_platform
  ┌───────────────────────────────────────────────────────────────────────┐
  │  rv32_ctrl_axi   (load imem/dmem, run/step/reset, read regs/PC/commit)  │
  │       │                                                                 │
  │   RV32I core (5-stage, I$/D$, Zicsr/trap/FENCE.I)                        │
  │       │ data bus → mmio_bridge ─┬─ 0x1xxx  Pmod MMIO (SPI/I2C/UART/PWM)  │
  │       │                         ├─ 0x3xxx  NPU  (16×16 INT8 GEMM)        │
  │       │                         └─ 0x4xxx  GPU  (8-lane SIMT vector)     │
  │                                                                         │
  │   ▟ UNIFIED FABRIC: 8 of the NPU's PEs are dual-mode — one DSP48E1 does  │
  │     NPU INT8 MAC (A*B+P)  OR  a GPU lane multiply-add (A*B+C), by mode.  │
  └───────────────────────────────────────────────────────────────────────┘
```

---

## 1. SoC architecture

The design is a single source of truth in **VHDL** under `rtl/`. Everything below is real RTL,
synthesized, and (where noted) verified on the board.

### 1.1 RV32I core — `rtl/core/`
Classic **5-stage pipeline** (`pc · icache · id · ex · mem · wb`, top = `rv32_core.vhd`):
- **RV32I** base ISA + **Zicsr**, trap/exception unit, and **FENCE.I**.
- Hazard unit + forwarding unit (full EX/MEM/WB bypass), branch-compare unit in EX.
- **I-cache and D-cache** (`core/icache`, `core/mem`) with an **AXI4 master** to backing memory;
  caches infer block RAM (synchronous read).
- Verified against an instruction-set simulator bit-for-bit (see `docs/VERIFICATION.md`).

### 1.2 NPU — 16×16 INT8 systolic GEMM — `rtl/npu/`
An **output-stationary systolic array** of `N×N` processing elements (`npu_pe.vhd`), wrapped by
`npu_top.vhd` / `npu_top16.vhd` (N=16) as an uncached MMIO slave at **0x3xxx_xxxx**:
- Each PE accumulates `C[i][j] += a*b` on **INT8** operands; the multiply-accumulate maps to one
  **DSP48E1**. A skew feeder streams the A-rows / B-cols; contraction depth K = 1…64 (tiled by SW).
- 16×16 = 256 MACs; the first `DSP_BUDGET` (200) map to DSP, the rest to LUT fabric.
- A **5-stage pipelined read-back** isolates the 256:1 accumulator mux and the requantize
  multiply (INT32 → INT8: `clip((C*mult + round) >> shift)`), closing timing toward 100 MHz.
- Map: `0x.000` CTRL/STATUS/K/CFG, `0x.1000` A, `0x.2000` B, `0x.3000` C. See `docs/NPU_DESIGN.md`.

### 1.3 GPU — 8-lane SIMT-lite vector coprocessor — `rtl/gpu/`
A **single-instruction, multiple-thread** engine: one PC drives **8 lanes** in lockstep with a
per-lane predicate mask (`gpu_core.vhd`, `gpu_lane.vhd`, `gpu_pkg.vhd`), MMIO slave at **0x4xxx_xxxx**:
- 8 vector regs (V0–V7) × 8 lanes, 8 scalar regs, 256-word instruction memory, and an
  8-bank **block-RAM scratchpad**.
- Vector ISA: `VADD/VSUB/VAND/VOR/VXOR/VSLL/VSRL/VSRA/VMIN/VMAX` (LUT ALU), `VMUL/VMAC`
  (DSP multiply-add), `VSLT/VSEQ` (predicate), `VLID/VMOVI/VBCAST/VLD/VST`, scalar `SADDI/SBNZ`
  for loops, `MASKON`, `HALT`.
- 3-cycle vector-ALU pipeline isolates the DSP multiply; the scratchpad read is BRAM-latency-aware.
  See `docs/GPU_DESIGN.md`.

### 1.4 Unified fabric — the GPU shares the NPU's DSPs — `docs/UNIFIED_NPU_GPU.md`
The XC7Z020 has only 220 DSP. A 16×16 NPU eats ~200; a *separate* 8-lane GPU adds 8 → 210, which
won't route. **But the NPU and GPU never run simultaneously**, so the multipliers are time-shared:
- `npu_pe` gains a `GPU_LANE` mode. There is exactly **one** multiply expression
  `mul_a*mul_b + mul_c` with **muxed operands**, so synthesis maps both modes onto a **single
  DSP48E1** — Vivado reports mode `(C or P)+A*B` (C-input for the GPU add, P-feedback for the NPU
  accumulate). **Proven: 1 DSP per dual-mode PE.**
- The 8 GPU lanes drop their own multipliers and borrow `PE(0,0..7)`. The bus is threaded
  `gpu_core → gpu_top  ↔  mmio_bridge  ↔  npu_top16 → npu_array`; `gpu_active` drives the PE mode.
- Result: full 16×16 NPU **+** GPU = **202 DSP**, same footprint as the silicon-proven core+NPU.

### 1.5 Pmod peripherals — `rtl/soc/`
`mmio_bridge.vhd` exposes the four Pmod headers **JA–JE (40 pins)** as memory-mapped peripherals
at **0x1xxx_xxxx**, controllable directly from assembly with `sw`/`lw` (no firmware change):
2× SPI (`spi_master`), 2× I2C (`i2c_master`), UART (`uart_lite`), PWM (`pwm_gen`), and a 22-pin
GPIO bank (`gpio_port`), plus the legacy LED/SW/BTN. See `docs/PMOD_PERIPHERALS_DESIGN.md`.

### 1.6 Multicore — `rtl/soc/rv32_dual.vhd`, `rv32_shared.vhd`
Dual-core RV32 variants (independent + shared-memory SPMD) exist and pass their testbenches;
OOC-synthesized and timing-closed. See `docs/MULTICORE_DESIGN.md` / `docs/MULTICORE_TIMING.md`.

### 1.7 Zynq integration — `rtl/soc/rv32_platform.vhd` + `rv_ps/`
`rv32_platform` is the whole PL subsystem packaged as a Vivado IP with an AXI-Lite control slave
(`rv32_ctrl_axi.vhd`). The **ARM PS** runs a bare-metal monitor (`sw/firmware/rv32_monitor.c`,
built for the Cortex-A9 in Vitis → `rv_firmware.elf`) that turns one-line UART commands into
AXI-Lite transactions on the core — so the host can load, run, single-step, and read back the
RV32 over the board's USB-UART, with **no DDR** (the board's DDR is faulty; everything goes
JTAG/PS-AXI).

### 1.8 Memory map
| window | what |
|---|---|
| `0x0000_0000…` | instruction / data RAM (cached, Harvard) |
| `0x1000_0000` | Pmod MMIO — LED/SW/BTN, GPIO `+0x20`, SPI0/1 `+0x40/0x60`, I2C0/1 `+0x80/0xA0`, UART `+0xC0`, PWM `+0xE0` |
| `0x3000_0000` | NPU 16×16 (CTRL/STATUS/K/CFG, A/B/C buffers) |
| `0x4000_0000` | GPU 8-lane (CTRL/STATUS, IMEM `+0x1000`, scratchpad `+0x4000`) |

(The PS↔core control slave `rv32_ctrl_axi` lives at `0x4000_0000` in **PS** address space — a
different bus from the core's own `0x4` GPU window.)

---

## 2. Repository layout
```
rtl/                VHDL — single source of truth
  core/             5-stage pipeline: pc·icache·id·ex·mem·wb + rv32_core.vhd
  npu/              16×16 INT8 systolic GEMM (npu_pe is the dual-mode shared-DSP cell)
  gpu/              SIMT-lite vector coprocessor (gpu_core/lane/top + gpu_pkg)
  soc/              mmio_bridge, Pmod peripherals, rv32_platform, rv32_ctrl_axi, multicore
sim/                testbenches + C/Python golden models
  gpu/  npu/  soc/  multicore/
fpga/
  scripts/          IP packaging, BD build, bitstream, proofs (see fpga/scripts/README.md)
  constraints/      zybo_z7_20_gpio.xdc / zybo_z7_20_pmod.xdc
flash/              on-board bring-up: ps7_init.tcl, jtag_*.tcl, run_*.bat, bitstreams
sw/
  host/             PC tools — rv32_gui.py (PySide6), rv32_console.py (CLI), assembler
  firmware/         RV32 monitor source notes
rv_ps/rv_firmware/  ARM PS monitor (rv32_monitor.c) + prebuilt rv_firmware.elf
docs/               design + verification docs, diagrams
(gitignored)        ip_repo/ ip_build/ vivado_zynq/   — regenerated by the build scripts
```

---

## 3. Results — silicon-verified (XC7Z020, Vivado 2025.2)

| metric | result |
|---|---|
| Whole-SoC DSP (core + caches + 16×16 NPU + GPU) | **202 / 220 (92 %)** — separate would be 210 |
| Dual-mode PE | **1 DSP48E1** does NPU MAC *or* GPU multiply-add (`(C or P)+A*B`) |
| Routing | 0 failed nets (the separate 210-DSP build stalled here) |
| Timing @ 100 MHz | hold **met** (+0.045 ns); setup WNS **−0.054 ns** post-route phys-opt (Fmax ≈ 99.5 MHz) |
| Bitstream | `fpga/flash/rv32_unified_100mhz.bit` |
| **On-board, real silicon @ 100 MHz** | NPU GEMM = 39,53,17,23 ✅ · GPU VMUL/VMAC on the shared DSPs ✅ |
| Comprehensive on-board suite | **14/14 PASS** — RV32 loop, NPU GEMM, all GPU ops, GPU SBNZ branch-loop |
| Simulation | NPU GEMM golden, GPU `tb_unified` (vadd/saxpy/relu/vmac) all pass |

---

## 4. Usage

### 4.1 Simulation (no board / Vivado-light)
```
# Python pipeline/ISS regressions (no Vivado):
cd sim && python run_ifwb_core.py --programs 4000

# HDL (xsim) regressions:
sim\gpu\run_gpu.bat                     # GPU SIMT coprocessor   -> ALL TESTS PASS
sim\multicore\run_dual.bat              # dual-core RV32 SPMD     -> ALL PASS
# unified fabric (1-DSP proof + NPU GEMM + GPU on the shared DSPs):
vivado -mode batch -source fpga\scripts\run_unified_proof.tcl   # 202 DSP + sim
```

### 4.2 Build the bitstream (Vivado batch)
```
:: 1) package the PL (rv32_platform) as an IP — version bumped each run so Vivado
::    re-synthesizes from current RTL (a same-version repackage reuses a stale netlist)
vivado -mode batch -source fpga\scripts\package_platform_ip.tcl
:: 2) build the Zynq block design + synth + impl + bitstream (FCLK0 = 100 MHz)
vivado -mode batch -source fpga\scripts\build_npu16_100mhz.tcl
```
Output: `vivado_zynq/.../impl_1/rv32_top_wrapper.bit` (copied to `fpga/flash/`). The Zybo pin
constraints `fpga/constraints/zybo_z7_20_{gpio,pmod}.xdc` must be in the impl constraint set
(`fpga/scripts/add_xdc_rebuild.tcl` adds them if a build skipped them). See `fpga/scripts/README.md`.

### 4.3 Bring the board up (JTAG + ARM monitor)
With the board on USB, program the FPGA and launch the PS monitor over JTAG:
```
flash\run_monitor.bat        # fpga -f <bitstream>; dow rv_firmware.elf; con  (monitor runs on the ARM)
```
The monitor now listens on the board's **PS-UART COM port** at 115200. (DDR is faulty, so the
RV32 is driven entirely through JTAG → PS-AXI → `rv32_ctrl_axi`; no QSPI/DDR boot.)

### 4.4 Live control from the PC — GUI or console
```
pip install pyserial PySide6
python sw\host\rv32_gui.py
```
Pick the board COM port (use `sw\host\port_probe.py` if unsure — the monitor replies `pc=…`/`st=…`),
**Connect**, type assembly, **Run** → the **Registers** panel highlights every value that changed,
live, as it ran on the silicon. `Step` single-steps; `Reset` clears. CLI alternative:
```
python sw\host\rv32_console.py --port COM10
rv32> addi x1,x0,7   ↵   add x3,x1,x2   ↵   run     ->   x1=7  x3=18
```

### 4.5 Comprehensive on-board test
```
flash\run_comprehensive.bat   # 14 cases: RV32 loop, NPU GEMM, every GPU op, GPU branch-loop
```
Expect `==== COMPREHENSIVE BOARD TEST: 14 PASS / 0 FAIL ====`. The kernels are generated by
`sw/host/gen_board_tests.py` (RV32 assembler + a small GPU-ISA encoder).

---

## 5. Interface reference

**AXI-Lite control slave** (`rv32_ctrl_axi`, PS base `0x4000_0000`)

| off | R/W | name | meaning |
|---|---|---|---|
| 0x00 | W | CTRL | b0 reset · b1 run · b2 step · b3 clr_commit |
| 0x04 | R | STATUS | b0 halted · b2 run |
| 0x08/0x0C | W | IMEM_ADDR / WDATA | load instruction memory |
| 0x10/0x14 | W | DMEM_ADDR / WDATA | load data memory |
| 0x18/0x1C | W/R | REG_ADDR / RDATA | pick register N, then read it |
| 0x20 | R | PC | current PC |
| 0x24/0x28 | R | LAST_RD / WDATA | last retired rd / written value |
| 0x2C | R | COMMIT_CNT | retired-instruction count |

**UART monitor protocol** (one line = one command, hex): `r` reset · `i A D` imem · `d A D` dmem ·
`g` run · `s` step · `x N` read reg · `m A` read dmem · `p` PC · `c` commits · `t` status ·
`D` dump all regs · `L/W/N` LED/SW/BTN · `h` help.

---

## 6. Documentation
- [`docs/UNIFIED_NPU_GPU.md`](docs/UNIFIED_NPU_GPU.md) — the shared-DSP fabric (design + silicon results)
- [`docs/NPU_DESIGN.md`](docs/NPU_DESIGN.md) · [`docs/GPU_DESIGN.md`](docs/GPU_DESIGN.md) — accelerators
- [`docs/SOC_INTEGRATION.md`](docs/SOC_INTEGRATION.md) · [`docs/SOC_PLATFORM_DESIGN.md`](docs/SOC_PLATFORM_DESIGN.md) — Zynq platform
- [`docs/PMOD_PERIPHERALS_DESIGN.md`](docs/PMOD_PERIPHERALS_DESIGN.md) — Pmod MMIO map + examples
- [`docs/MULTICORE_DESIGN.md`](docs/MULTICORE_DESIGN.md) · [`docs/VERIFICATION.md`](docs/VERIFICATION.md) · [`docs/BOARD_VERIFICATION_REPORT.md`](docs/BOARD_VERIFICATION_REPORT.md)

---

## 7. Status
RV32I+Zicsr+trap+FENCE.I core, I$/D$/AXI, 16×16 INT8 NPU, 8-lane SIMT GPU, the **unified
shared-DSP fabric**, Pmod peripherals, dual-core variants, the Zynq platform + ARM monitor, and the
PC GUI/console are all complete and **verified on real XC7Z020 silicon @ 100 MHz** — including a
14/14 on-board test suite and live register read-back in the GUI.
