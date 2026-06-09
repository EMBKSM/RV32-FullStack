// tb_tag_array.sv - self-checking TB for tag_array.vhd (I-cache tag store).
// Async read of idx; sync write (we): tag<=tag_in, valid<=1; inv clears all valid;
// reset clears all valid. inv has priority over we.
`timescale 1ns/1ps
module tb_tag_array;
  logic clk=0, reset, we, inv;
  logic [7:0]  idx;
  logic [19:0] tag_in, tag_out;
  logic        valid_out;
  always #5 clk=~clk;

  tag_array dut (.clk(clk), .reset(reset), .we(we), .inv(inv),
                 .idx(idx), .tag_in(tag_in), .tag_out(tag_out), .valid_out(valid_out));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if (!cond) begin errors++; $error("%s FAIL (tag=%h valid=%b)",nm,tag_out,valid_out); end
  endtask

  initial begin
    reset=1; we=0; inv=0; idx=0; tag_in=0; @(negedge clk); @(negedge clk); reset=0;
    // line 5 invalid after reset
    idx=8'd5; #1; ck(valid_out==1'b0, "post-reset invalid");
    // write line 5
    tag_in=20'hABCDE; we=1; @(posedge clk); we=0; @(negedge clk);
    idx=8'd5; #1; ck(valid_out==1'b1 && tag_out==20'hABCDE, "write line5");
    // different line still invalid
    idx=8'd6; #1; ck(valid_out==1'b0, "line6 invalid");
    // write line 6
    idx=8'd6; tag_in=20'h12345; we=1; @(posedge clk); we=0; @(negedge clk);
    #1; ck(valid_out==1'b1 && tag_out==20'h12345, "write line6");
    // invalidate clears all valid (tag may remain)
    inv=1; @(posedge clk); inv=0; @(negedge clk);
    idx=8'd5; #1; ck(valid_out==1'b0, "inv clears line5");
    idx=8'd6; #1; ck(valid_out==1'b0, "inv clears line6");
    // inv priority over we (same cycle)
    idx=8'd7; tag_in=20'hAAAAA; we=1; @(posedge clk); we=0; @(negedge clk);  // valid7=1
    idx=8'd7; we=1; inv=1; tag_in=20'hBBBBB; @(posedge clk); we=0; inv=0; @(negedge clk);
    #1; ck(valid_out==1'b0, "inv beats we");

    // ---- 3-point boundary value analysis (index edges 0/1/254/255, no aliasing) ----
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    idx=8'd0;   tag_in=20'h0AAAA; we=1; @(posedge clk); we=0; @(negedge clk);
    idx=8'd255; tag_in=20'h0BBBB; we=1; @(posedge clk); we=0; @(negedge clk);
    idx=8'd0;   #1; ck(valid_out==1'b1 && tag_out==20'h0AAAA, "BVA idx=0 (min)");
    idx=8'd255; #1; ck(valid_out==1'b1 && tag_out==20'h0BBBB, "BVA idx=255 (max)");
    idx=8'd1;   #1; ck(valid_out==1'b0, "BVA idx=1 untouched");
    idx=8'd254; #1; ck(valid_out==1'b0, "BVA idx=254 untouched");

    // ---- timing-issue tests (sync-write latency vs async-read, async reset) ----
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    // write committed only on the clock edge: async read shows OLD (invalid) pre-edge
    idx=8'd9; tag_in=20'h0CECE; we=1; #1; ck(valid_out==1'b0, "TIMING write invisible pre-edge");
    @(posedge clk); we=0; @(negedge clk); #1; ck(valid_out==1'b1 && tag_out==20'h0CECE, "TIMING visible post-edge");
    // async reset clears valid immediately (between edges)
    reset=1; #2; ck(valid_out==1'b0, "TIMING async reset clears valid"); reset=0;

    $display("[tb_tag_array] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
