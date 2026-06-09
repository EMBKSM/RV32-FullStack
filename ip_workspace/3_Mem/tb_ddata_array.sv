// tb_ddata_array.sv - self-checking TB for ddata_array.vhd (256 x 128b D-cache data).
// word load (word_off), byte-strobed store-hit, whole-line refill, line writeback out.
`timescale 1ns/1ps
module tb_ddata_array;
  logic clk=0;
  logic [7:0]   idx;
  logic [1:0]   word_off;
  logic         we, line_fill;
  logic [3:0]   wstrb;
  logic [31:0]  wdata, word_out;
  logic [127:0] fill_line, line_out;
  always #5 clk=~clk;

  ddata_array dut (.clk(clk), .idx(idx), .word_off(word_off), .we(we), .wstrb(wstrb),
    .wdata(wdata), .line_fill(line_fill), .fill_line(fill_line),
    .word_out(word_out), .line_out(line_out));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if(!cond) begin errors++; $error("%s FAIL: word_out=%h line_out=%h",nm,word_out,line_out); end
  endtask

  initial begin
    idx=0; word_off=0; we=0; line_fill=0; wstrb=0; wdata=0; fill_line=0; @(negedge clk);
    // whole-line refill
    idx=8'd3; fill_line=128'h44332211_33221100_22110099_11009988; line_fill=1;
    @(posedge clk); line_fill=0; @(negedge clk);
    word_off=2'd0; #1; ck(word_out==32'h11009988, "refill word0");
    word_off=2'd3; #1; ck(word_out==32'h44332211, "refill word3");
    idx=8'd3; #1; ck(line_out==128'h44332211_33221100_22110099_11009988, "line_out");
    // byte store into word1, lane 1 (wstrb=0010)
    idx=8'd7; fill_line=128'h0; line_fill=1; @(posedge clk); line_fill=0; @(negedge clk);
    word_off=2'd1; wdata=32'h0000AB00; wstrb=4'b0010; we=1; @(posedge clk); we=0; @(negedge clk);
    word_off=2'd1; #1; ck(word_out[15:8]==8'hAB && word_out[7:0]==8'h00, "SB lane1");
    // full word store (wstrb=1111)
    wdata=32'hDEADBEEF; wstrb=4'b1111; we=1; @(posedge clk); we=0; @(negedge clk);
    word_off=2'd1; #1; ck(word_out==32'hDEADBEEF, "SW word1");
    // other words untouched
    word_off=2'd0; #1; ck(word_out==32'h0, "word0 untouched");

    // ---- 3-point boundary value analysis (idx 0/255, word_off 0/3, wstrb 0x0/0xF) ----
    idx=8'd0;   fill_line=128'h0; line_fill=1; @(posedge clk); line_fill=0; @(negedge clk);
    idx=8'd255; fill_line={32'hD3,32'hD2,32'hD1,32'hD0}; line_fill=1; @(posedge clk); line_fill=0; @(negedge clk);
    idx=8'd255; word_off=2'd0; #1; ck(word_out==32'hD0, "BVA idx=255 word_off=0");
    idx=8'd255; word_off=2'd3; #1; ck(word_out==32'hD3, "BVA idx=255 word_off=3");
    idx=8'd0;   word_off=2'd0; #1; ck(word_out==32'h0,  "BVA idx=0 cleared");
    // wstrb boundary: 0x0 (no write) then 0xF (full write)
    idx=8'd0; word_off=2'd0; wdata=32'hAABBCCDD; wstrb=4'h0; we=1; @(posedge clk); we=0; @(negedge clk);
    word_off=2'd0; #1; ck(word_out==32'h0, "BVA wstrb=0x0 no write");
    wstrb=4'hF; we=1; @(posedge clk); we=0; @(negedge clk);
    word_off=2'd0; #1; ck(word_out==32'hAABBCCDD, "BVA wstrb=0xF full write");

    // ---- timing-issue tests (sync-write latency, line_fill vs we edge priority) ----
    idx=8'd4; fill_line=128'h0; line_fill=1; @(posedge clk); line_fill=0; @(negedge clk);
    // store committed only on edge: async word_out shows OLD (0) pre-edge
    idx=8'd4; word_off=2'd0; wdata=32'hCAFEBABE; wstrb=4'hF; we=1; #1;
    ck(word_out==32'h00000000, "TIMING ddata store invisible pre-edge");
    @(posedge clk); we=0; @(negedge clk); word_off=2'd0; #1; ck(word_out==32'hCAFEBABE, "TIMING ddata post-edge");
    // line_fill beats we on the same edge (whole-line refill wins)
    idx=8'd4; fill_line={32'h44,32'h33,32'h22,32'h11}; line_fill=1; wdata=32'hDEADBEEF; wstrb=4'hF; we=1;
    @(posedge clk); line_fill=0; we=0; @(negedge clk);
    word_off=2'd0; #1; ck(word_out==32'h00000011, "TIMING line_fill beats we");

    $display("[tb_ddata_array] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
