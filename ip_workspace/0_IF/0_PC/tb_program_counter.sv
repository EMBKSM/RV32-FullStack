// tb_program_counter.sv - self-checking TB for program_counter.vhd (entity pc_reg).
// Async active-high reset -> RESET_ADDR; stall holds; else pc<=next_pc on rising edge.
`timescale 1ns/1ps
module tb_program_counter;
  logic clk=0, reset, stall;
  logic [31:0] next_pc, pc;
  always #5 clk=~clk;

  pc_reg #(.RESET_ADDR(32'h0000_0000)) dut
    (.clk(clk), .reset(reset), .stall(stall), .next_pc(next_pc), .pc(pc));

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] exp, input string nm);
    checks++;
    if (pc !== exp) begin errors++; $error("%s FAIL: pc=%h exp=%h",nm,pc,exp); end
  endtask

  initial begin
    // async reset
    reset=1; stall=0; next_pc=32'hDEAD_BEEF; #2; ck(32'h0000_0000, "async reset");
    @(negedge clk); reset=0;
    // normal advance
    next_pc=32'h0000_0004; @(posedge clk); #1; ck(32'h0000_0004, "advance to 4");
    next_pc=32'h0000_0008; @(posedge clk); #1; ck(32'h0000_0008, "advance to 8");
    // stall holds
    stall=1; next_pc=32'h1234_5678; @(posedge clk); #1; ck(32'h0000_0008, "stall hold");
    @(posedge clk); #1; ck(32'h0000_0008, "stall hold 2");
    // release
    stall=0; @(posedge clk); #1; ck(32'h1234_5678, "resume");
    // redirect value
    next_pc=32'h0000_1000; @(posedge clk); #1; ck(32'h0000_1000, "redirect");
    // re-assert reset mid-run
    reset=1; #2; ck(32'h0000_0000, "reset mid-run");
    reset=0;

    // ---- 3-point boundary value analysis (next_pc min/sign/max, stall edge) ----
    reset=0; stall=0;
    next_pc=32'h00000000; @(posedge clk); #1; ck(32'h00000000, "BVA pc=min");
    next_pc=32'h7FFFFFFC; @(posedge clk); #1; ck(32'h7FFFFFFC, "BVA pc=sign-bound");
    next_pc=32'hFFFFFFFF; @(posedge clk); #1; ck(32'hFFFFFFFF, "BVA pc=max");
    next_pc=32'h00000010; stall=1; @(posedge clk); #1; ck(32'hFFFFFFFF, "BVA stall=1 holds");
    stall=0;             @(posedge clk); #1; ck(32'h00000010, "BVA stall=0 release");

    // ---- timing-issue tests (async reset dominance, multi-cycle stall hold) ----
    // async reset asserted between edges dominates an active stall
    stall=1; next_pc=32'h0BADF00D; reset=1; #2; ck(32'h00000000, "TIMING async reset dominates stall");
    reset=0; stall=0; next_pc=32'h00000020; @(posedge clk); #1; ck(32'h00000020, "TIMING resume after reset");
    // 3-cycle stall: next_pc churns underneath but pc is frozen
    stall=1; next_pc=32'h11111111; @(posedge clk);
             next_pc=32'h22222222; @(posedge clk);
             next_pc=32'h33333333; @(posedge clk); #1; ck(32'h00000020, "TIMING 3-cycle stall hold");
    stall=0; @(posedge clk); #1; ck(32'h33333333, "TIMING release latches latest next_pc");

    $display("[tb_program_counter] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
