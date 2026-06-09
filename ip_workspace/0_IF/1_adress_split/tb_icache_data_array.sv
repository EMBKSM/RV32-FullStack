// tb_icache_data_array.sv - unit TB for the read-only I-cache line store.
// Checks: whole-line fill, per-word read select, idx isolation, and
// 3-point boundary value analysis on idx (0/1/254/255) and word_off (0..3).
`timescale 1ns/1ps
module tb_icache_data_array;
  logic clk=0;
  logic [7:0]   idx;
  logic [1:0]   word_off;
  logic         line_fill;
  logic [127:0] fill_line;
  logic [31:0]  word_out;

  icache_data_array dut(.clk(clk), .idx(idx), .word_off(word_off),
                        .line_fill(line_fill), .fill_line(fill_line), .word_out(word_out));

  always #5 clk = ~clk;

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] got, exp, input string nm);
    checks++;
    if (got !== exp) begin errors++; $error("%s: got=%h exp=%h", nm, got, exp); end
  endtask

  // write a 128-bit line at index `i` (sampled on posedge)
  task automatic fill(input logic [7:0] i, input logic [127:0] line);
    @(negedge clk); idx=i; fill_line=line; line_fill=1;
    @(posedge clk); #1 line_fill=0;
  endtask

  // read word `w` from index `i` (combinational)
  task automatic rdw(input logic [7:0] i, input logic [1:0] w, output logic [31:0] d);
    idx=i; word_off=w; #1 d=word_out;
  endtask

  logic [31:0] d;
  initial begin
    line_fill=0; idx=0; word_off=0; fill_line=0;

    // distinct words per lane
    fill(8'd0,   128'h44444444_33333333_22222222_11111111);
    rdw(8'd0,2'd0,d); ck(d,32'h11111111,"idx0 w0");
    rdw(8'd0,2'd1,d); ck(d,32'h22222222,"idx0 w1");
    rdw(8'd0,2'd2,d); ck(d,32'h33333333,"idx0 w2");
    rdw(8'd0,2'd3,d); ck(d,32'h44444444,"idx0 w3");

    // index isolation: another line elsewhere doesn't disturb idx0
    fill(8'd128, 128'hCAFEF00D_DEADBEEF_0BADC0DE_FEEDFACE);
    rdw(8'd0,2'd0,d); ck(d,32'h11111111,"idx0 intact after idx128 write");
    rdw(8'd128,2'd0,d); ck(d,32'hFEEDFACE,"idx128 w0");
    rdw(8'd128,2'd3,d); ck(d,32'hCAFEF00D,"idx128 w3");

    // ---- BVA on idx: 0,1,254,255 ----
    fill(8'd1,   128'h00000001_00000001_00000001_00000001);
    fill(8'd254, 128'h000000FE_000000FE_000000FE_000000FE);
    fill(8'd255, 128'h000000FF_000000FF_000000FF_000000FF);
    rdw(8'd1,  2'd0,d); ck(d,32'h00000001,"BVA idx1");
    rdw(8'd254,2'd2,d); ck(d,32'h000000FE,"BVA idx254");
    rdw(8'd255,2'd3,d); ck(d,32'h000000FF,"BVA idx255");

    // overwrite same line (re-fill) replaces all words
    fill(8'd255, 128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD);
    rdw(8'd255,2'd0,d); ck(d,32'hDDDDDDDD,"refill idx255 w0");
    rdw(8'd255,2'd3,d); ck(d,32'hAAAAAAAA,"refill idx255 w3");

    if (errors==0) $display("tb_icache_data_array: ALL PASS (%0d checks)", checks);
    else           $fatal(1, "tb_icache_data_array: %0d FAIL", errors);
    $finish;
  end
endmodule
