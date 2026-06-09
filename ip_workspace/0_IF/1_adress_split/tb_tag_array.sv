// tb_tag_array.sv - self-checking TB for tag_array.vhd (I-cache tag store).
// Async read of idx; sync write (we): tag<=tag_in, valid<=1; inv clears all valid;
// reset clears all valid. inv has priority over we.
//
// Clocking discipline (race-free, mixed-language): control signals (we/inv) are
// asserted, held THROUGH the capturing posedge, then deasserted on the following
// negedge. Deasserting right after @(posedge) can race with the VHDL clocked
// process sampling 'we' in the same time-step (caused earlier write-swallow).
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

  // race-free refill: drive at negedge, hold through posedge, release at next negedge
  task automatic wline(input logic [7:0] ix, input logic [19:0] t);
    @(negedge clk); idx=ix; tag_in=t; we=1;
    @(posedge clk); @(negedge clk); we=0;
  endtask
  task automatic do_inv();
    @(negedge clk); inv=1;
    @(posedge clk); @(negedge clk); inv=0;
  endtask

  initial begin
    reset=1; we=0; inv=0; idx=0; tag_in=0;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);

    // line 5 invalid after reset
    idx=8'd5; #1; ck(valid_out==1'b0, "post-reset invalid");
    // write line 5
    wline(8'd5, 20'hABCDE); idx=8'd5; #1; ck(valid_out==1'b1 && tag_out==20'hABCDE, "write line5");
    // different line still invalid
    idx=8'd6; #1; ck(valid_out==1'b0, "line6 invalid");
    // write line 6
    wline(8'd6, 20'h12345); idx=8'd6; #1; ck(valid_out==1'b1 && tag_out==20'h12345, "write line6");
    // invalidate clears all valid (tag may remain)
    do_inv();
    idx=8'd5; #1; ck(valid_out==1'b0, "inv clears line5");
    idx=8'd6; #1; ck(valid_out==1'b0, "inv clears line6");
    // inv priority over we (same edge)
    wline(8'd7, 20'hAAAAA);                                  // valid7=1
    @(negedge clk); idx=8'd7; tag_in=20'hBBBBB; we=1; inv=1; // both asserted
    @(posedge clk); @(negedge clk); we=0; inv=0;
    idx=8'd7; #1; ck(valid_out==1'b0, "inv beats we");

    // ---- 3-point boundary value analysis (index edges 0/1/254/255, no aliasing) ----
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    wline(8'd0,   20'h0AAAA);
    wline(8'd255, 20'h0BBBB);
    idx=8'd0;   #1; ck(valid_out==1'b1 && tag_out==20'h0AAAA, "BVA idx=0 (min)");
    idx=8'd255; #1; ck(valid_out==1'b1 && tag_out==20'h0BBBB, "BVA idx=255 (max)");
    idx=8'd1;   #1; ck(valid_out==1'b0, "BVA idx=1 untouched");
    idx=8'd254; #1; ck(valid_out==1'b0, "BVA idx=254 untouched");

    // ---- timing-issue tests (sync-write latency vs async-read, async reset) ----
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    // write committed only on the clock edge: async read shows OLD (invalid) pre-edge
    @(negedge clk); idx=8'd9; tag_in=20'h0CECE; we=1; #1; ck(valid_out==1'b0, "TIMING write invisible pre-edge");
    @(posedge clk); @(negedge clk); we=0; #1; ck(valid_out==1'b1 && tag_out==20'h0CECE, "TIMING visible post-edge");
    // async reset clears valid immediately (between edges)
    reset=1; #2; ck(valid_out==1'b0, "TIMING async reset clears valid"); reset=0;

    $display("[tb_tag_array] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
