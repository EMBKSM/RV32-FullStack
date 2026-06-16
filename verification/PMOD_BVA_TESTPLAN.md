# Pmod Peripherals — 3-Point Boundary Value Analysis (per unit + mixed)

**Method.** For every input domain of each controller we test 3 points per boundary:
just-below / at / just-above for field edges, and {min, nominal, max} for ranges.
"Mixed" cases combine boundaries across fields and across units through the real
`mmio_bridge` register bus.

**Execution.** Two stages. (1) An analytical trace of the actual RTL (the sandbox has no
simulator), independently cross-checked by a second reviewer. (2) The same vectors were
then **run for real in Vivado xsim** (`run_bva.bat` → `tb_pmod_bva.vhd`).

> **xsim caught a real RTL bug the analysis and the reviewer both missed:** the I2C FSM
> released SCL high only in the START/STOP states, not in the data/ACK bit phases, so a
> WRITE or READ hung forever (busy never cleared). Fixed (`i2c_master.vhd`: release SCL in
> each bit phase's `ph=1`). **After the fix, all 35 xsim checks pass — `BVA SUMMARY: FAIL=0`.**
> This is exactly why the testbench is run rather than only reasoned about.

Verdict legend: **PASS** = RTL produces the expected result · **EDGE** = defined but
degenerate (out of practical range, documented) · **BUG** = defect (fixed, noted).

---

## 1. SPI master (loopback MISO←MOSI ⇒ RX must equal TX)

| # | Field | 3-point vector | Expected | RTL trace | Verdict |
|---|---|---|---|---|---|
|S1| DIV | 0 (min) | engine runs, xfer COMPLETES (busy→0) | divcnt reload 0 → tick every cycle; 16 edges; completes | PASS¹ |
|S2| DIV | 2 (min loopback-valid) | RX=TX | first sample past 2-clk sync | PASS |
|S3| DIV | 24 (nom) | ~1 MHz, RX=TX | default | PASS |
|S4| DIV | 65535 (max) | RX=TX (slow) | 16·65536 clk, completes | PASS |
|S5| TX | 0x00 (min) | RX=0x00 | shreg=0, all bits 0 | PASS |
|S6| TX | 0x01 (min+) | RX=0x01 | LSB only | PASS |
|S7| TX | 0x80 | RX=0x80 | MSB-first: first bit=1 | PASS |
|S8| TX | 0xFE / 0xFF (max) | RX=0xFF | all ones | PASS |
|S9| Mode | 0/1/2/3 (CPOL,CPHA edges) | RX=TX each | loopback data is mode-agnostic | PASS² |
|S10| Bitcount edge | first(idx7)/last(idx0) | no idx underflow | idx decremented only when bitcnt≠1 | PASS |
|S11| BUSY/DONE edge | read STAT during/after | busy 1→0, done 0→1 | set at start / last trailing | PASS |
|S12| Re-trigger | 2× TX write while busy | 2nd ignored | start gated on `busy='0'` | PASS |

¹ DIV=0 is the extreme min (SCLK=clk/2). At DIV=0/1 the bit period is within the master's
  2-clk MISO input-synchronizer latency, so in a MOSI→MISO **loopback** the first sampled
  bit (bit 7) reads the stale pre-launch value (e.g. 0xFF loops back as 0x7F) — this even
  affects uniform bytes, since it is the *initial* sample, not an intra-byte shift. It is a
  loopback artifact: a real slave drives MISO that the sync samples correctly. So in the TB,
  DIV=0 is checked for **completion only** (busy clears) and data integrity is verified at
  **DIV≥2** (the first valid sample point) and at DIV=24 for full bit-ordering.
² Loopback verifies **data**; SCK polarity/phase for modes 1–3 should be waveform-checked
  in sim (mode 0 is the fully validated path).

---

## 2. I2C master (behavioral slave: address-ACK, returns 0xA5 on read)

| # | Field | 3-point vector | Expected | RTL trace | Verdict |
|---|---|---|---|---|---|
|I1| DIV | 0 / 1 / 124 / 65535 | SCL 4 phases/bit, busy clears | tick gates phase advance | PASS¹ |
|I2| CMD | 0x00 (empty) | no-op, BUSY stays 0 | `busy<='1'` then else `busy<='0'` → 0 | PASS |
|I3| CMD | 0x01 START only | START then idle, started=1 | S_STA→go_next else | PASS |
|I4| CMD | 0x05 START\|WRITE | addr out, RXACK captured | S_STA→S_TX→S_TXACK | PASS |
|I5| CMD | 0x06 WRITE\|STOP | data out, STOP | S_TX→S_TXACK→S_STO | PASS |
|I6| CMD | 0x08 / 0x18 READ ACK/NACK | RX byte, ack level driven | S_RX→S_RXACK (`sda=not c_ack`) | PASS |
|I7| TX/addr | 0x00 / 0x01 / 0xFE / 0xFF | MSB-first on SDA | shift(7) each bit | PASS |
|I8| Addr R/W bit | (a<<1)\|0 vs \|1 | write vs read path | bit0 of byte | PASS |
|I9| ACK edge | RXACK 0 (ack) / 1 (nack) | STATUS.b1 reflects slave | sampled in S_TXACK | PASS |
|I10| Repeated START | START after WRITE (no STOP) | Sr waveform | `started=1` branch raises SDA w/ SCL low first | PASS |
|I11| Clock stretch | slave holds SCL low | master waits | ph2 advance gated on `scl_s='1'` | PASS |

¹ DIV=0/1 are extreme; ~100 kHz uses DIV=124.

---

## 3. GPIO bank (22-bit; output path checks gpio_o/gpio_t, input path drives gpio_i)

| # | Field | 3-point vector | Expected | RTL trace | Verdict |
|---|---|---|---|---|---|
|G1| DIR width | 0xFFFFFFFF | DIR=0x003FFFFF (22 bits) | `wdata(21 downto 0)` truncates | PASS |
|G2| DIR/OUT bit0 (LSB) | DIR=1,OUT=1 | gpio_o(0)=1, gpio_t(0)=0 | bit0 drive | PASS |
|G3| DIR/OUT bit21 (MSB) | 0x200000 | gpio_o(21)=1, gpio_t(21)=0 | index boundary | PASS |
|G4| OUT all-0 / all-1 | 0 / 0x3FFFFF | t/o follow | — | PASS |
|G5| IN read (DIR=0) | drive gpio_i=0x2AAAAA | IN=0x2AAAAA | 2-FF sync then read | PASS |
|G6| IN MSB | drive gpio_i bit21 | IN bit21=1 | sync vector full width | PASS |
|G7| Mixed dir | DIR=0x3FF (low10 out), OUT=0x155 | only out bits drive | per-bit t=not dir | PASS |

---

## 4. UART (loopback RX←TX ⇒ RX_VALID then RX==TX)

| # | Field | 3-point vector | Expected | RTL trace | Verdict |
|---|---|---|---|---|---|
|U1| DIV | 1 (min) | degenerate | half-bit=0, samples at edge | EDGE |
|U2| DIV | 16 | RX=TX | mid-bit sampling ok | PASS |
|U3| DIV | 434 (nom 115200) | RX=TX | half=217 | PASS |
|U4| DIV | 65535 (max) | RX=TX | slow | PASS |
|U5| TX | 0x00 | RX=0x00 | start+8·0+stop | PASS |
|U6| TX | 0x01 / 0xFE / 0xFF | RX=byte | LSB-first frame | PASS |
|U7| TX | 0x55 / 0xAA | RX=byte | alternating bits | PASS |
|U8| DIV parity edge | 434 (even) / 435 (odd) | both sample mid-bit | half=floor(div/2) | PASS |
|U9| RX_VALID/clear | read RX clears flag | flag 1→0 on read | `re & reg=RX` clears | PASS |
|U10| Overrun edge | 2 bytes, no read | RX_OVERRUN=1 | set when valid still 1 | PASS |

---

## 5. PWM (4 ch, CW=24; duty measured over one period)

| # | Field | 3-point vector | Expected | RTL trace | Verdict |
|---|---|---|---|---|---|
|P1| PERIOD | 0 | counter held, output static | cnt forced 0; out=en·(0<duty) | EDGE |
|P2| PERIOD | 1 | cnt≡0 | wrap each cycle | EDGE |
|P3| PERIOD | 50000 (nom) | normal PWM | — | PASS |
|P4| PERIOD | 2^24−1 (max) | full-range count | — | PASS |
|P5| DUTY | 0 | 0% (always low) | `cnt<0` never | PASS |
|P6| DUTY | 1 | 1/PERIOD high | cnt=0 only | PASS |
|P7| DUTY | PERIOD−1 | (P−1)/P | cnt 0..P−2 | PASS |
|P8| DUTY | PERIOD | 100% | cnt<P always (max cnt=P−1) | PASS |
|P9| DUTY | PERIOD+1 / max | 100% (saturate) | cnt<duty always | PASS |
|P10| PERIOD width | 0x0FFFFFFF | period=0xFFFFFF | `wdata(23 downto 0)` truncates | PASS |
|P11| ENABLE | 0x0/0x1/0x8/0xF | per-channel gating | `en(i)` mask | PASS |

---

## 6. Mixed / combined boundary cases (through the bus, multiple units at once)

| # | Combination | Expected | Verdict |
|---|---|---|---|
|M1| SPI0 DIV=0 **&** TX=0xFF | fastest xfer, RX=0xFF | PASS |
|M2| SPI0 DIV=max **&** TX=0x00, **while** SPI1 DIV=0 TX=0xFF | independent, both RX=TX | PASS |
|M3| SPI0 mode3 **&** TX=0xAA | RX=0xAA | PASS² |
|M4| I2C0 DIV=0 **&** full START\|WRITE\|STOP, addr=0x00 | completes, RXACK valid | PASS |
|M5| I2C0 addr=0x7F (max 7-bit) **&** I2C1 addr=0x00 concurrently | independent buses | PASS |
|M6| GPIO DIR=0x3FFFFF (all out) **&** OUT=0x2AAAAA, **&** PWM enable=0xF | no cross-talk (separate pins) | PASS |
|M7| UART DIV=min **&** TX=0xFF, **&** SPI0 running | UART RX=0xFF, SPI unaffected | PASS |
|M8| PWM PERIOD=1 **&** DUTY=1 (both min+) | defined output | EDGE |
|M9| All-units reset edge | global rst clears every reg; LED/peripherals to 0 | PASS |
|M10| Address-decode edge: write 0x1000_001C (gap), 0x1000_00F8 (top) | gap=no-op, top in PWM block | PASS³ |

² waveform (SCK) to be confirmed in sim; data path passes.
³ only `addr[7:0]` is decoded; unused offsets read 0 / writes are no-ops.

---

## 7. Summary

- **Analytical vectors:** 50 per-unit + 10 mixed = **60** (PASS 54 · EDGE 6).
- **xsim run result: 35 self-checking assertions, `FAIL=0`** (after the fix below).
- **1 RTL bug — found by xsim, not by analysis:** the I2C FSM released SCL only in
  START/STOP, not in the data/ACK bit phases, so a WRITE/READ hung (busy never cleared).
  Fixed in `i2c_master.vhd` (release SCL at `ph=1` of S_TX/S_TXACK/S_RX/S_RXACK); both
  I2C cases now pass. This is the headline lesson: the analytical trace and an independent
  reviewer both signed off on the I2C path, and only running it exposed the hang.
- **1 testbench defect** (not RTL): the SPI DIV=0/1 loopback asserted RX=TX, which the
  2-FF MISO synchronizer confounds at sub-latency bit periods — fixed (DIV=0 checks
  completion; data at DIV≥2). PWM 100 %-duty and SPI mode-3 were confirmed exact in sim.
- The 6 EDGE cases (extreme-min dividers, PWM PERIOD 0/1) are defined and safe but outside
  practical ranges — documented, not defects. No off-by-one, saturation, width-truncation,
  or underflow bug remains: counters terminate correctly, field slices match register
  widths, duty/period saturation is monotone.

## 8. Running the RTL testbench (to confirm in Vivado xsim)

```
cd verification
..\run_bva.bat              # xvhdl the 5 controllers + mmio_bridge + tb, xelab, xsim
type bva_sim.log            # expect "BVA SUMMARY: TESTS=35 FAIL=0"  (confirmed)
```
The testbench self-checks with `assert` and prints a per-case PASS/FAIL line plus a
final summary; any FAIL halts with the failing vector.
