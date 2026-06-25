# SPMD vector-add  C[i]=A[i]+B[i], split across 2 harts by hart id.
# shared base 0x80000000:  word0=HARTID  word1=BARRIER
# scratchpad @ 0x80000100:  A[0..7]@+0x00  B[0..7]@+0x20  C[0..7]@+0x40
    lui   x10, 0x80000        # x10 = shared base
    lw    x5, 0(x10)          # x5  = hart id (0 / 1)
    slli  x6, x5, 2           # x6  = i   = hartid*4   (core0:0  core1:4)
    addi  x7, x6, 4           # x7  = end = i+4
loop:
    slli  x8, x6, 2           # x8  = i*4 (byte offset)
    addi  x9, x10, 0x100      # &A[0]
    add   x11, x9, x8
    lw    x12, 0(x11)         # A[i]
    addi  x9, x10, 0x120      # &B[0]
    add   x13, x9, x8
    lw    x14, 0(x13)         # B[i]
    add   x15, x12, x14       # A[i]+B[i]
    addi  x9, x10, 0x140      # &C[0]
    add   x16, x9, x8
    sw    x15, 0(x16)         # C[i] = A[i]+B[i]
    addi  x6, x6, 1           # i++
    blt   x6, x7, loop        # while i < end
    sw    x5, 4(x10)          # barrier: arrive
hang:
    jal   x0, hang            # halt (spin)
