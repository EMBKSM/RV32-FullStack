# GPU on-board demo driver (RV32I) -- VERIFIED on real XC7Z020 @100MHz.
# Proves the SHARED-DSP GPU runs on silicon. GPU @ 0x4000_0000 (RV32 data space,
# decoded by mmio_bridge addr[31:28]=0x4). Assemble with sw/host/rv32_console.py.
# Kernel: VMOVI V1=6, VMOVI V2=7, VMUL V3=V1*V2 (=42 via a borrowed NPU DSP),
#         VLID V4 (V4[k]=k), VADD V3=V3+V4 (=42+k), VST V3 -> scratchpad row 0.
# Driver reads lanes 0..3 -> x10..x13 = 42,43,44,45 (read back via ctrl_axi rdreg).
# Separate base regs keep every load/store offset within the 12-bit signed range.
# (double lw per lane: the GPU scratchpad read has 1-cycle BRAM latency, no stall)
li x4, 0x40000000      # CTRL / STATUS base
li x1, 0x40001000      # GPU imem  base
li x2, 0x40004000      # GPU scratchpad base
# --- load GPU kernel into GPU imem ---
li x5, 0x08800006      # VMOVI V1,#6
sw x5, 0(x1)
li x5, 0x09000007      # VMOVI V2,#7
sw x5, 4(x1)
li x5, 0x3D940000      # VMUL  V3,V1,V2   (shared-DSP multiply)
sw x5, 8(x1)
li x5, 0x06000000      # VLID  V4         (V4[k]=k)
sw x5, 12(x1)
li x5, 0x15B80000      # VADD  V3,V3,V4   (V3[k]=42+k)
sw x5, 16(x1)
li x5, 0x10060000      # VST   V3,S0      (store V3 to scratchpad row 0)
sw x5, 20(x1)
sw x0, 24(x1)          # HALT
# --- start GPU (CTRL bit0=1) ---
li x5, 1
sw x5, 0(x4)
# --- poll STATUS done (bit0) ---
poll:
lw x6, 4(x4)
andi x6, x6, 1
beqz x6, poll
# --- read scratchpad lanes 0..3 into x10..x13 (double read for BRAM latency) ---
lw x10, 0(x2)
lw x10, 0(x2)
lw x11, 4(x2)
lw x11, 4(x2)
lw x12, 8(x2)
lw x12, 8(x2)
lw x13, 12(x2)
lw x13, 12(x2)
done:
jal x0, done
