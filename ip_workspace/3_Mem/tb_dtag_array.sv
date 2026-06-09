// tb_dtag_array.sv - self-checking TB for dtag_array.vhd (D-cache tag+valid+dirty).
// we_tag: tag<=tag_in, valid<=1, dirty<=0 (refill). we_dirty: dirty<=1 (store hit).
// reset clears valid+dirty. Async read of idx.
//
// Race-free clocking: write-enables are held THROUGH the capturing posedge and
// deasserted on the following negedge (deasserting right after @(posedge) can
// race with the VHDL clocked process sampling we_tag/we_dirty in mixed-language sim).
`timescale 1ns/1ps
module tb_dtag_array;
  logic clk=0, reset, we_tag, we_dirty;
  logic [7:0]  idx;
  logic [19:0] tag_in, tag_out;
  logic        valid_out, dirty_out;
  always #5 clk=~clk;

  dtag_array dut (.clk(clk), .reset(reset), .idx(idx), .we_tag(we_tag),
    .we_dirty(we_dirty), .tag_in(tag_in), .tag_out(tag_out),
    .valid_out(valid_out), .dirty_out(dirty_out));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if(!cond) begin errors++;
      $error("%s FAIL: tag=%h v=%b d=%b",nm,tag_out,valid_out,dirty_out); end
  endtask

  // race-free refill (we_tag) and dirty-set (we_dirty)
  task automatic refill(input logic [7:0] ix, input logic [19:0] t);
    @(negedge clk); idx=ix; tag_in=t; we_tag=1;
    @(posedge clk); @(negedge clk); we_tag=0;
  endtask
  task automatic setdirty(input logic [7:0] ix);
    @(negedge clk); idx=ix; we_dirty=1;
    @(posedge clk); @(negedge clk); we_dirty=0;
  endtask

  initial begin
    reset=1; we_tag=0; we_dirty=0; idx=0; tag_in=0;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);

    idx=8'd5; #1; ck(valid_out==1'b0 && dirty_out==1'b0, "post-reset clean");
    // refill line5
    refill(8'd5, 20'hABCDE);
    idx=8'd5; #1; ck(tag_out==20'hABCDE && valid_out==1'b1 && dirty_out==1'b0, "refill sets tag/valid, clears dirty");
    // store hit sets dirty
    setdirty(8'd5);
    idx=8'd5; #1; ck(valid_out==1'b1 && dirty_out==1'b1, "store hit sets dirty");
    // refill again clears dirty
    refill(8'd5, 20'h11111);
    idx=8'd5; #1; ck(tag_out==20'h11111 && valid_out==1'b1 && dirty_out==1'b0, "refill clears dirty");
    // we_tag has priority over we_dirty (same edge)
    @(negedge clk); idx=8'd5; tag_in=20'h22222; we_tag=1; we_dirty=1;
    @(posedge clk); @(negedge clk); we_tag=0; we_dirty=0;
    idx=8'd5; #1; ck(tag_out==20'h22222 && dirty_out==1'b0, "we_tag beats we_dirty");
    // reset clears valid/dirty
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    idx=8'd5; #1; ck(valid_out==1'b0 && dirty_out==1'b0, "reset clears");

    // ---- 3-point boundary value analysis (index edges 0/1/255) ----
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    refill(8'd0,   20'h0AAAA);
    refill(8'd255, 20'h0BBBB);
    idx=8'd0;   #1; ck(tag_out==20'h0AAAA && valid_out==1'b1, "BVA dtag idx=0 (min)");
    idx=8'd255; #1; ck(tag_out==20'h0BBBB && valid_out==1'b1, "BVA dtag idx=255 (max)");
    idx=8'd1;   #1; ck(valid_out==1'b0, "BVA dtag idx=1 untouched");

    // ---- timing-issue tests (sync-write latency, edge priority, async reset) ----
    reset=1; @(posedge clk); @(negedge clk); reset=0; @(negedge clk);
    // refill committed only on edge: async read invalid pre-edge
    @(negedge clk); idx=8'd3; tag_in=20'h0F0F0; we_tag=1; #1; ck(valid_out==1'b0, "TIMING dtag write invisible pre-edge");
    @(posedge clk); @(negedge clk); we_tag=0; #1; ck(valid_out==1'b1 && tag_out==20'h0F0F0, "TIMING dtag post-edge");
    // we_tag beats we_dirty on same edge (refill clears dirty)
    @(negedge clk); idx=8'd3; tag_in=20'h0AAAA; we_tag=1; we_dirty=1;
    @(posedge clk); @(negedge clk); we_tag=0; we_dirty=0;
    idx=8'd3; #1; ck(tag_out==20'h0AAAA && dirty_out==1'b0, "TIMING we_tag beats we_dirty");
    // async reset clears valid+dirty between edges
    reset=1; #2; ck(valid_out==1'b0 && dirty_out==1'b0, "TIMING async reset clears"); reset=0;

    $display("[tb_dtag_array] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
