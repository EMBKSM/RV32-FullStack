# Pmod Peripheral Overhaul — Design & Review (Zybo Z7-20)

**Status:** RTL + constraints written, **not yet synthesized** (review first, then build).
**Scope:** allocate every Pmod pin (JA–JE, 40 pins) to a dedicated, MMIO-mapped
hardware controller so an RV32 assembly program can drive SPI, I2C, UART, PWM and
GPIO directly with `sw`/`lw`.

---

## 1. Before vs. after

| | Allocated peripherals | Free pin headers |
|---|---|---|
| **Before** | LED (0x00), SW (0x04), BTN (0x08) — 3 MMIO regs | **All 5 Pmods (JA–JE), 40 pins unused** |
| **After** | LED/SW/BTN + 2×SPI + 2×I2C + 1×UART + 4×PWM + 22×GPIO | 0 (every Pmod pin assigned) |

Nothing in the PS monitor (`rv32_monitor.c`) or the host GUI needs to change: the
assembly program you load already does loads/stores, and these peripherals are just
new addresses in the existing MMIO window. The AXI-Lite control slave
(`rv32_ctrl_axi`) is untouched.

---

## 2. Per-Pmod allocation

Pin index `n` = `jX_io(n)`; top row = 0–3, bottom row = 4–7 (matches the Digilent
master XDC ordering). Functions follow standard Pmod interface types so real Pmod
modules plug in directly.

| Header | Controller | Pin map |
|---|---|---|
| **JA** | **SPI0** (Type 2A) | 0=SS_n 1=MOSI 2=MISO 3=SCLK · 4–7=GPIO0–3 |
| **JB** | **SPI1** | 0=SS_n 1=MOSI 2=MISO 3=SCLK · 4–7=GPIO4–7 |
| **JC** | **I2C0** (Type 6A) | 2=SCL 3=SDA · 0,1,4–7=GPIO8–13 |
| **JD** | **I2C1** | 2=SCL 3=SDA · 0,1,4–7=GPIO14–19 |
| **JE** | **UART + PWM** | 1=TXD 2=RXD · 4–7=PWM0–3 · 0,3=GPIO20–21 |

GPIO bank = 22 bits collected from the leftover pins (bit→pin mapping above and in
`rv32_platform.vhd`).

---

## 3. MMIO register map

Base = **0x1000_0000**. Decode uses only `addr[7:0]` (any `0x1xxx_xxxx` alias works).
`block = addr[7:5]`, `reg = addr[4:2]`. All accesses are single-cycle (no stall).

| Addr | Block | Reg | Access | Meaning |
|---|---|---|---|---|
| 0x00 | SYS | LED | R/W | board LEDs (low 4 bits) |
| 0x04 | SYS | SW | R | board switches |
| 0x08 | SYS | BTN | R | board buttons |
| 0x20 | GPIO | DIR | R/W | 1=output, 0=input (22 bits) |
| 0x24 | GPIO | OUT | R/W | output value |
| 0x28 | GPIO | IN | R | synchronized pin value |
| 0x40 | SPI0 | CTRL | R/W | b0 CPOL · b1 CPHA · b2 SS_MANUAL · b3 SS_LEVEL |
| 0x44 | SPI0 | STATUS | R | b0 BUSY · b1 DONE |
| 0x48 | SPI0 | DIV | R/W | SCLK = clk/(2·(DIV+1)); reset 24 → ~1 MHz |
| 0x4C | SPI0 | TX | W | write byte → start transfer |
| 0x50 | SPI0 | RX | R | received byte |
| 0x60–0x70 | SPI1 | … | | same layout as SPI0 |
| 0x80 | I2C0 | CMD | W | b0 START · b1 STOP · b2 WRITE · b3 READ · b4 ACK(0=ack) |
| 0x84 | I2C0 | STATUS | R | b0 BUSY · b1 RXACK (0 = slave ACKed) |
| 0x88 | I2C0 | DIV | R/W | SCL = clk/(4·(DIV+1)); reset 124 → ~100 kHz |
| 0x8C | I2C0 | TX | W | byte to send (address+R/W or data) |
| 0x90 | I2C0 | RX | R | byte received |
| 0xA0–0xB0 | I2C1 | … | | same layout as I2C0 |
| 0xC0 | UART | DIV | R/W | baud divisor = clk/baud; reset 434 → 115200 |
| 0xC4 | UART | STATUS | R | b0 TX_BUSY · b1 RX_VALID · b2 RX_OVERRUN · b3 TX_READY |
| 0xC8 | UART | TX | W | write byte → transmit |
| 0xCC | UART | RX | R | received byte (read clears RX_VALID) |
| 0xE0 | PWM | CTRL | R/W | b[3:0] per-channel enable |
| 0xE4 | PWM | PERIOD | R/W | counter modulus; pwm_freq = clk/PERIOD |
| 0xE8–0xF4 | PWM | DUTY0–3 | R/W | high-time per channel (count < DUTY → high) |

Clock = `S_AXI_ACLK` (FCLK, 50 MHz). All defaults assume 50 MHz; change DIV regs to retune.

---

## 4. Example assembly (base 0x1000_0000)

**SPI0 — send 0x55, read response (mode 0):**
```asm
    li   x1, 0x10000040     # SPI0 base
    li   x2, 24
    sw   x2, 8(x1)          # DIV  -> ~1 MHz
    sw   x0, 0(x1)          # CTRL -> mode 0, auto-SS
    li   x2, 0x55
    sw   x2, 12(x1)         # TX   -> start
1:  lw   x3, 4(x1)          # STATUS
    andi x3, x3, 1          # BUSY?
    bnez x3, 1b
    lw   x4, 16(x1)         # RX
```

**I2C0 — write 0xAB to device 0x50:**
```asm
    li   x1, 0x10000080     # I2C0 base
    li   x2, 124
    sw   x2, 8(x1)          # DIV -> ~100 kHz
    li   x2, 0xA0           # (0x50<<1)|0  address + write
    sw   x2, 12(x1)         # TX
    li   x2, 0x05           # START|WRITE
    sw   x2, 0(x1)          # CMD
2:  lw   x3, 4(x1)
    andi x3, x3, 1
    bnez x3, 2b             # wait busy
    li   x2, 0xAB
    sw   x2, 12(x1)         # TX = data
    li   x2, 0x06           # WRITE|STOP
    sw   x2, 0(x1)          # CMD
```

**UART — send 'A':**
```asm
    li   x1, 0x100000C0
    li   x2, 434
    sw   x2, 0(x1)          # DIV -> 115200
    li   x2, 0x41
    sw   x2, 8(x1)          # TX = 'A'
```

**GPIO — drive GPIO0 (JA pin 4) high, read GPIO bank:**
```asm
    li   x1, 0x10000020
    li   x2, 1
    sw   x2, 0(x1)          # DIR  bit0 = output
    sw   x2, 4(x1)          # OUT  bit0 = 1
    lw   x3, 8(x1)          # IN
```

**PWM — 50 % on channel 0:**
```asm
    li   x1, 0x100000E0
    li   x2, 50000
    sw   x2, 4(x1)          # PERIOD
    li   x2, 25000
    sw   x2, 8(x1)          # DUTY0
    li   x2, 1
    sw   x2, 0(x1)          # CTRL enable ch0
```

---

## 5. Files

**New controllers** (`ip_workspace/5_Platform/`):
`spi_master.vhd`, `i2c_master.vhd`, `gpio_port.vhd`, `uart_lite.vhd`, `pwm_gen.vhd`.

**Modified:** `mmio_bridge.vhd` (block decode + read mux + controller instances),
`rv32_platform.vhd` (Pmod inout ports + tri-state pad mapping).

**New constraints:** `constraints/zybo_z7_20_pmod.xdc` (40 pins, official master-XDC
assignments; internal PULLUP on I2C lines for bench use without a module).

---

## 6. Build / integration steps  — **DONE** (bitstream built & timing-clean)

Automated as three Vivado-batch scripts (run via the matching `.bat` at repo root):

1. **Re-package the IP** — `scripts/package_platform_ip.tcl` (globs `ip_workspace/**/*.vhd`,
   picks up the 5 new modules). ✅ integrity check passed.
2. **BD integration** — `scripts/integrate_pmod_bd.tcl`: `update_ip_catalog` → `upgrade_ip`
   (refreshes the locked `plat` cell so the new ports appear) → `make_bd_pins_external`
   for `ja_io…je_io` (→ `ja_io_0…je_io_0`) → validate → regenerate wrapper. ✅
3. **XDC + synth → impl → bitstream** — `scripts/synth_pmod.tcl`. ✅
   Result: **0 critical warnings, 26 IOBUFs, WNS +2.06 ns / WHS +0.02 ns (timing met),
   `rv32_top_wrapper.bit` written.**

> **CRITICAL build gotcha (fixed):** the BD must be synthesized in **GLOBAL** mode
> (`set_property synth_checkpoint_mode None [get_files rv32_top.bd]`). With the default
> per-IP **out-of-context** synthesis, the platform's 26 inout tri-states are *converted to
> logic* (`[Synth 8-5799]`) and the bidirectional pins get OBUFs instead of IOBUFs — GPIO
> inputs and I2C open-drain silently break. Global synthesis lets the top inout ports and
> the tri-state logic be seen together so proper IOBUFs are inferred. This was caught only
> by inspecting the synth log, not by RTL review.

**No firmware change** — the PS monitor/GUI are untouched; load the new bitstream over JTAG
(DDR not required) and drive the peripherals from assembly via MMIO.

---

## 7. Verification plan

The ISS golden model does not model MMIO side effects, so peripherals are checked at
sim / HW level:

- **Unit sim** — per-controller testbench: SPI MOSI→MISO loopback; I2C against a
  behavioral slave model (ACK + register); UART TX→RX loopback; GPIO out→in; PWM duty
  measured by counting high cycles. (Extend `verification/tb_rv32_platform.sv`.)
- **On hardware (JItag, no DDR)** — jumper loopbacks: SPI0 MOSI(JA1)→MISO(JA3),
  UART TXD(JE2)→RXD(JE3), a GPIO out pin → a GPIO in pin; confirm RX==TX and pin reads.
- **Regression** — existing 39-instruction / 100-random ISS tests still pass unchanged
  (CPU core and the cached memory path are untouched; only the MMIO bridge grew).

### Known caveats to confirm in sim
- **SPI** mode 0 (CPOL=0,CPHA=0) is the validated default; modes 1–3 are structurally
  supported via the CPOL/CPHA edge selection — verify timing in sim before relying on them.
- **I2C** repeated-START, clock-stretch, and multi-byte read sequencing should be
  checked against a model slave.
- **Tri-state** inout ports rely on Vivado inferring IOBUFs from the `'Z'` assignments in
  `rv32_platform.vhd`. **Confirmed in global synthesis: 26 IOBUFs** (22 GPIO + 4 I2C), IBUF
  on MISO/RXD, OBUF on SCLK/MOSI/SS/TXD/PWM. (Requires the global-synth setting in §6 — OOC
  synthesis breaks this.)
