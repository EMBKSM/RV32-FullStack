// tb_pc_adder.sv - self-checking TB for pc_adder.vhd (combinational pc+4).
// Mixed-language (VHDL DUT + SV TB): xsim/Questa. Pattern mirrors tb_alu.sv.
`timescale 1ns/1ps
module tb_pc_adder;
  logic [31:0] pc_in, pc_out;
  pc_adder dut (.pc_in(pc_in), .pc_out(pc_out));

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] a, input logic [31:0] exp, input string nm);
    pc_in=a; #1; checks++;
    if (pc_out !== exp) begin errors++; $error("%s FAIL: pc_in=%h pc_out=%h exp=%h",nm,a,pc_out,exp); end
  endtask

  initial begin
    ck(32'h0000_0000, 32'h0000_0004, "reset+4");
    ck(32'h0000_0004, 32'h0000_0008, "seq");
    ck(32'h0000_00FC, 32'h0000_0100, "carry");
    ck(32'hFFFF_FFFC, 32'h0000_0000, "wrap");      // +4 wraps to 0
    ck(32'hFFFF_FFFF, 32'h0000_0003, "wrap odd");
    for (int i=0;i<2000;i++) begin
      logic [31:0] r=$urandom; ck(r, (r+32'd4)&32'hFFFFFFFF, "rand");
    end
    // ---- 3-point boundary value analysis (wrap @0xFFFFFFFC, min @0) ----
    ck(32'hFFFFFFFB, 32'hFFFFFFFF, "BVA wrap-1");
    ck(32'hFFFFFFFC, 32'h00000000, "BVA wrap");
    ck(32'hFFFFFFFD, 32'h00000001, "BVA wrap+1");
    ck(32'hFFFFFFFF, 32'h00000003, "BVA max in");
    ck(32'h00000000, 32'h00000004, "BVA min in");
    ck(32'h00000001, 32'h00000005, "BVA min+1");

    $display("[tb_pc_adder] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
