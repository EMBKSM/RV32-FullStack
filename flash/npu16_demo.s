# 16x16 NPU on-board demo driver (RV32I) -- 2x2 tile GEMM, K=2.
# NPU @ 0x3000_0000.  A=[[3,4],[1,2]]  B(=B[k][col])=[[5,7],[6,8]]  ->  C=[[39,53],[17,23]]
# Loaded into RV32 imem via ctrl_axi (PS-AXI 0x4000_0000) by jtag_gemm_test.tcl.
# Assemble with host_app/rv32_console.py :: assemble().
li x4, 0x30000000      # CTRL base
li x1, 0x30001000      # A   base
li x2, 0x30002000      # B   base
li x3, 0x30003000      # C   base
li x5, 2
sw x5, 8(x4)           # K_DIM = 2
li x6, 3
sw x6, 0(x1)           # A[0][0]=3
li x6, 4
sw x6, 4(x1)           # A[0][1]=4
li x6, 1
sw x6, 256(x1)         # A[1][0]=1
li x6, 2
sw x6, 260(x1)         # A[1][1]=2
li x7, 5
sw x7, 0(x2)           # B[0][0]=5
li x7, 6
sw x7, 4(x2)           # B[1][0]=6
li x7, 7
sw x7, 256(x2)         # B[0][1]=7
li x7, 8
sw x7, 260(x2)         # B[1][1]=8
li x8, 3
sw x8, 0(x4)           # CTRL = start | clr_acc
poll:
lw x9, 4(x4)           # STATUS
andi x9, x9, 2         # done bit
beq x9, x0, poll
lw x10, 0(x3)          # C[0][0] -> 39
lw x11, 4(x3)          # C[0][1] -> 53
lw x12, 64(x3)         # C[1][0] -> 17
lw x13, 68(x3)         # C[1][1] -> 23
done:
jal x0, done
