// tb_register_file.sv - self-checking TB for register_file.vhd (32x32, 2R/1W).
// x0 hardwired 0; sync write on clk; combinational read with write-first bypass.
`timescale 1ns/1ps
module tb_register_file;
  logic clk=0, reset, we3;
  logic [4:0]  a1,a2,a3;
  logic [31:0] wd3, rd1, rd2;
  always #5 clk=~clk;

  register_file dut (.clk(clk), .reset(reset), .we3(we3), .a1(a1), .a2(a2), .a3(a3),
                     .wd3(wd3), .rd1(rd1), .rd2(rd2));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if (!cond) begin errors++; $error("%s FAIL: rd1=%h rd2=%h",nm,rd1,rd2); end
  endtask
  task automatic wr(input logic [4:0] rd, input logic [31:0] d);
    a3=rd; wd3=d; we3=1; @(posedge clk); we3=0; @(negedge clk);
  endtask

  initial begin
    reset=1; we3=0; a1=0; a2=0; a3=0; wd3=0; @(posedge clk); @(negedge clk); reset=0;
    // x1..x31 cleared by sync reset
    a1=5'd1; #1; ck(rd1==32'h0, "post-reset x1=0");
    // write x5, read back
    wr(5'd5, 32'h1234_5678); a1=5'd5; #1; ck(rd1==32'h1234_5678, "read x5");
    // x0 always 0 even after attempted write
    wr(5'd0, 32'hDEAD_BEEF); a1=5'd0; #1; ck(rd1==32'h0, "x0 write ignored");
    // x0 read on rd2
    a2=5'd0; #1; ck(rd2==32'h0, "x0 read rd2");
    // two ports independent
    wr(5'd9, 32'hAAAA_5555); a1=5'd5; a2=5'd9; #1;
    ck(rd1==32'h1234_5678 && rd2==32'hAAAA_5555, "dual read");
    // write-first bypass: reading rd while writing same reg returns new data
    a1=5'd7; a3=5'd7; wd3=32'hCAFEBABE; we3=1; #1;
    ck(rd1==32'hCAFEBABE, "write-first bypass rs1=rd");
    a2=5'd7; #1; ck(rd2==32'hCAFEBABE, "write-first bypass rs2=rd");
    @(posedge clk); we3=0; @(negedge clk);   // hold we3=1 THROUGH the edge to actually commit
    a1=5'd7; #1; ck(rd1==32'hCAFEBABE, "bypass committed");
    // write-first to x0 still reads 0
    a1=5'd0; a3=5'd0; wd3=32'h99; we3=1; #1; ck(rd1==32'h0, "x0 no bypass"); we3=0;

    // ---- 3-point boundary value analysis (reg-num edge x0/x1/x30/x31, data min/max) ----
    wr(5'd1, 32'h00000000); a1=5'd1; #1; ck(rd1==32'h00000000, "BVA x1 data=min");
    wr(5'd1, 32'hFFFFFFFF); a1=5'd1; #1; ck(rd1==32'hFFFFFFFF, "BVA x1 data=max");
    wr(5'd30,32'h12345678); a1=5'd30; #1; ck(rd1==32'h12345678, "BVA x30");
    wr(5'd31,32'hDEADBEEF); a1=5'd31; #1; ck(rd1==32'hDEADBEEF, "BVA x31 (max idx)");
    a1=5'd0; #1; ck(rd1==32'h00000000, "BVA x0 (min idx) hardwired");

    // ---- timing-issue tests (write-first bypass timing, commit latency, back-to-back) ----
    // pre-edge: combinational read already reflects wd3 in the SAME cycle as we3 (write-first)
    a3=5'd12; wd3=32'hF00DCAFE; we3=1; a1=5'd12; #1; ck(rd1==32'hF00DCAFE, "TIMING write-first same-cycle");
    @(posedge clk); we3=0; @(negedge clk); a1=5'd12; #1; ck(rd1==32'hF00DCAFE, "TIMING committed post-edge");
    // back-to-back writes to same reg on consecutive edges: last value wins
    a3=5'd12; wd3=32'h11111111; we3=1; @(posedge clk);
              wd3=32'h22222222;        @(posedge clk); we3=0; @(negedge clk);
    a1=5'd12; #1; ck(rd1==32'h22222222, "TIMING back-to-back write last wins");

    $display("[tb_register_file] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
