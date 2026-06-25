# ============================================================================
# npu_gemm_demo.s  -  RV32 driver / example for the INT8 8x8 systolic GEMM NPU
#
# NPU MMIO window @ 0x3000_0000  (see docs/NPU_DESIGN.md):
#   CTRL   0x30000000   bit0 start, bit1 clr_acc      (write to launch)
#   STATUS 0x30000004   bit0 busy,  bit1 done
#   K_DIM  0x30000008   contraction depth K (1..64)
#   A_BUF  0x30000800 + i*256 + k*4   <- A[i][k] (INT8 in low byte of the word)
#   B_BUF  0x30001000 + j*256 + k*4   <- B[k][j]
#   C_BUF  0x30001800 + (i*8+j)*4     -> C[i][j] (INT32, read back)
#
# Demo problem:  A[i][k] = i+1 ,  B[k][j] = j+1 ,  K = 4
#   => C[i][j] = sum_{k=0..3} (i+1)(j+1) = 4*(i+1)*(j+1)
#   expected:  C[0][0]=4   C[1][1]=16   C[3][5]=96   C[7][7]=256
# Results are left in x10..x13 so the PS monitor can read them back.
# (MMIO offsets are 12-bit, so addresses are built with a pointer we increment.)
# ============================================================================

    li   x1, 0x30000000        # x1 = NPU base
    li   x2, 4                 # K = 4
    li   x28, 8                # N = 8  (outer loop bound)
    sw   x2, 8(x1)             # K_DIM = 4

    # ---- load A : A[i][k] = i+1 ----------------------------------------
    li   x5, 0x30000800        # A_BUF base
    li   x6, 0                 # i = 0
a_i:
    addi x7, x6, 1             # val = i+1
    slli x8, x6, 8             # i*256
    add  x8, x5, x8            # ptr = A_BUF + i*256
    li   x9, 0                 # k = 0
a_k:
    sw   x7, 0(x8)             # A[i][k] = i+1
    addi x8, x8, 4             # advance one element (word-aligned)
    addi x9, x9, 1
    bne  x9, x2, a_k           # while k != K
    addi x6, x6, 1
    bne  x6, x28, a_i          # while i != 8

    # ---- load B : B[k][j] = j+1 ----------------------------------------
    li   x5, 0x30001000        # B_BUF base (column j lives at +j*256)
    li   x6, 0                 # j = 0
b_j:
    addi x7, x6, 1             # val = j+1
    slli x8, x6, 8             # j*256
    add  x8, x5, x8            # ptr = B_BUF + j*256
    li   x9, 0                 # k = 0
b_k:
    sw   x7, 0(x8)             # B[k][j] = j+1
    addi x8, x8, 4
    addi x9, x9, 1
    bne  x9, x2, b_k
    addi x6, x6, 1
    bne  x6, x28, b_j

    # ---- launch : start | clr_acc --------------------------------------
    li   x2, 3                 # bit0 start, bit1 clr_acc
    sw   x2, 0(x1)             # CTRL <- 3

    # ---- wait for done (STATUS bit1) -----------------------------------
poll:
    lw   x3, 4(x1)
    andi x3, x3, 2
    beq  x3, x0, poll

    # ---- read back a few results ---------------------------------------
    li   x5, 0x30001800        # C_BUF base
    lw   x10, 0(x5)            # C[0][0]  -> expect 4    (word 0)
    lw   x11, 36(x5)           # C[1][1]  -> expect 16   (word 9)
    lw   x13, 116(x5)          # C[3][5]  -> expect 96   (word 29)
    lw   x12, 252(x5)          # C[7][7]  -> expect 256  (word 63)

hang:
    j    hang                  # spin so the monitor can read x10..x13
