// tb_rv32_soc_npu.sv - full-RTL end-to-end: the actual assembled NPU driver runs
// on rv32_core + I$/D$ + mmio_bridge + NPU (rv32_soc_npu). Preload program, run,
// read back architectural x10..x13, compare to the GEMM golden.
//   A[i][k]=i+1, B[k][j]=j+1, K=4 -> C=4(i+1)(j+1):  x10=4 x11=16 x13=96 x12=256
`timescale 1ns/1ps
module tb_rv32_soc_npu;
  logic clk=0, reset;
  logic prog_we; logic [31:0] prog_addr, prog_data;
  logic dpre_we; logic [31:0] dpre_addr, dpre_data;
  logic dbg_commit; logic [4:0] dbg_rd, dbg_reg_addr;
  logic [31:0] dbg_wdata, dbg_reg_data, dbg_pc, dbg_instr;
  logic dbg_mstall;
  always #5 clk = ~clk;

  rv32_soc_npu #(.RESET_ADDR(32'h0000_0000)) dut (
    .clk(clk), .reset(reset),
    .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
    .dmem_we_pre(dpre_we), .dmem_addr_pre(dpre_addr), .dmem_data_pre(dpre_data),
    .dbg_commit(dbg_commit), .dbg_rd(dbg_rd), .dbg_wdata(dbg_wdata),
    .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data),
    .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_mstall(dbg_mstall));

  // === the EXACT assembled driver (host_app/npu_gemm_demo.s) ===
  localparam int N = 41;
  logic [31:0] img [0:N-1] = '{
    32'h300000b7, 32'h00400113, 32'h00800e13, 32'h0020a423, 32'h300012b7, 32'h80028293,
    32'h00000313, 32'h00130393, 32'h00831413, 32'h00828433, 32'h00000493, 32'h00742023,
    32'h00440413, 32'h00148493, 32'hfe249ae3, 32'h00130313, 32'hfdc31ee3, 32'h300012b7,
    32'h00000313, 32'h00130393, 32'h00831413, 32'h00828433, 32'h00000493, 32'h00742023,
    32'h00440413, 32'h00148493, 32'hfe249ae3, 32'h00130313, 32'hfdc31ee3, 32'h00300113,
    32'h0020a023, 32'h0040a183, 32'h0021f193, 32'hfe018ce3, 32'h300022b7, 32'h80028293,
    32'h0002a503, 32'h0242a583, 32'h0742a683, 32'h0fc2a603, 32'h0000006f };

  logic [31:0] r [0:31];
  int errors = 0;
  task automatic ck(int idx, logic [31:0] exp, string nm);
    if (r[idx] !== exp) begin errors++; $display("  FAIL %s : x%0d=%0d (0x%h) expected %0d", nm, idx, r[idx], r[idx], exp); end
    else                 $display("  PASS %s : x%0d = %0d", nm, idx, r[idx]);
  endtask

  initial begin
    reset=1; prog_we=0; dpre_we=0; prog_addr=0; prog_data=0; dpre_addr=0; dpre_data=0;
    @(negedge clk);
    for (int i=0;i<N;i++) begin prog_we=1; prog_addr=i*4; prog_data=img[i]; @(negedge clk); end
    prog_we=0; @(negedge clk);
    reset=0;
    repeat (40000) @(posedge clk);              // A/B load loops + systolic run + poll + readback
    for (int i=0;i<32;i++) begin dbg_reg_addr=i[4:0]; #1; r[i]=dbg_reg_data; end
    $display("==== full-RTL SoC+NPU end-to-end (driver executed on real RTL) ====");
    ck(10, 32'd4,   "C[0][0]");
    ck(11, 32'd16,  "C[1][1]");
    ck(13, 32'd96,  "C[3][5]");
    ck(12, 32'd256, "C[7][7]");
    if (errors==0) $display("RESULT: ALL PASS - CPU(RTL)+bridge+NPU(RTL) ran the driver, GEMM correct");
    else           $display("RESULT: FAIL (%0d errors)", errors);
    $finish;
  end
  initial begin #80_000_000; $display("RESULT: TIMEOUT"); $finish; end
endmodule
