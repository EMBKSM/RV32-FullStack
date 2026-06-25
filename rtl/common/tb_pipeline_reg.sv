// tb_pipeline_reg.sv - self-checking TB for pipeline_reg.vhd (generic boundary reg).
// reset->0; flush: data passes, control=0 (bubble); stall: hold; else latch.
// Instantiated with DW=32, CW=8 (defaults).
`timescale 1ns/1ps
module tb_pipeline_reg;
  localparam DW=32, CW=8;
  logic clk=0, reset, stall, flush;
  logic [DW-1:0] d_in, d_out;
  logic [CW-1:0] c_in, c_out;
  always #5 clk=~clk;

  pipeline_reg #(.DW(DW), .CW(CW)) dut
    (.clk(clk), .reset(reset), .stall(stall), .flush(flush),
     .d_in(d_in), .c_in(c_in), .d_out(d_out), .c_out(c_out));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if(!cond) begin errors++; $error("%s FAIL: d_out=%h c_out=%h",nm,d_out,c_out); end
  endtask

  initial begin
    reset=1; stall=0; flush=0; d_in=0; c_in=0; @(negedge clk); @(negedge clk); reset=0;
    // normal latch
    d_in=32'hAAAA_AAAA; c_in=8'h3; @(posedge clk); #1; ck(d_out==32'hAAAA_AAAA && c_out==8'h3, "latch");
    // stall holds
    d_in=32'hBBBB_BBBB; c_in=8'h1; stall=1; @(posedge clk); #1; ck(d_out==32'hAAAA_AAAA && c_out==8'h3, "stall hold");
    stall=0;
    // flush: data passes through, control nullified
    d_in=32'hCCCC_CCCC; c_in=8'hFF; flush=1; @(posedge clk); #1; ck(d_out==32'hCCCC_CCCC && c_out==8'h00, "flush bubble");
    flush=0;
    // normal again
    d_in=32'h1234_5678; c_in=8'h7; @(posedge clk); #1; ck(d_out==32'h1234_5678 && c_out==8'h7, "latch2");
    // async reset
    reset=1; #2; ck(d_out==0 && c_out==0, "async reset"); reset=0;

    // ---- 3-point boundary value analysis (data min/max, flush>stall priority edge) ----
    reset=0; stall=0; flush=0;
    d_in=32'h00000000; c_in=8'h00; @(posedge clk); #1; ck(d_out==32'h00000000 && c_out==8'h00, "BVA data=min");
    d_in=32'hFFFFFFFF; c_in=8'hFF; @(posedge clk); #1; ck(d_out==32'hFFFFFFFF && c_out==8'hFF, "BVA data=max");
    d_in=32'h5A5A5A5A; c_in=8'hFF; flush=1; @(posedge clk); #1; ck(d_out==32'h5A5A5A5A && c_out==8'h00, "BVA flush: data passes, ctrl=0"); flush=0;
    // boundary: stall & flush both asserted -> flush has priority (RTL checks flush first)
    d_in=32'h11111111; c_in=8'h0F; stall=1; flush=1; @(posedge clk); #1; ck(d_out==32'h11111111 && c_out==8'h00, "BVA flush beats stall");
    stall=0; flush=0;

    // ---- timing-issue tests (multi-cycle stall hold, async reset dominance) ----
    reset=0; stall=0; flush=0;
    d_in=32'hA1A1A1A1; c_in=8'h5; @(posedge clk); #1; ck(d_out==32'hA1A1A1A1 && c_out==8'h5, "TIMING latch");
    stall=1;
    d_in=32'hB2B2B2B2; c_in=8'h6; @(posedge clk);
    d_in=32'hC3C3C3C3; c_in=8'h7; @(posedge clk); #1; ck(d_out==32'hA1A1A1A1 && c_out==8'h5, "TIMING 2-cycle stall hold");
    stall=0;
    // async reset dominates simultaneous stall+flush
    stall=1; flush=1; reset=1; #2; ck(d_out==32'h00000000 && c_out==8'h00, "TIMING async reset dominates stall+flush");
    reset=0; stall=0; flush=0;

    $display("[tb_pipeline_reg] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
