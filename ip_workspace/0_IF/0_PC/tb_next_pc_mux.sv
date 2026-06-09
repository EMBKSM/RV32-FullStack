// tb_next_pc_mux.sv - self-checking TB for next_pc_mux.vhd (2:1 PC mux).
// next_pc = pc_src ? target_addr : pc_plus_4.  xsim/Questa mixed-language.
`timescale 1ns/1ps
module tb_next_pc_mux;
  logic [31:0] pc_plus_4, target_addr, next_pc;
  logic        pc_src;
  next_pc_mux dut (.pc_plus_4(pc_plus_4), .target_addr(target_addr),
                   .pc_src(pc_src), .next_pc(next_pc));

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] p4,ta, input logic s, input string nm);
    logic [31:0] exp = s ? ta : p4;
    pc_plus_4=p4; target_addr=ta; pc_src=s; #1; checks++;
    if (next_pc !== exp) begin errors++; $error("%s FAIL: src=%b out=%h exp=%h",nm,s,next_pc,exp); end
  endtask

  initial begin
    ck(32'h0000_0004, 32'h8000_0000, 1'b0, "sequential");
    ck(32'h0000_0004, 32'h8000_0000, 1'b1, "redirect");
    ck(32'hDEAD_BEEF, 32'h1234_5678, 1'b0, "sel0");
    ck(32'hDEAD_BEEF, 32'h1234_5678, 1'b1, "sel1");
    for (int i=0;i<2000;i++)
      ck($urandom, $urandom, $urandom_range(0,1), "rand");
    // ---- 3-point boundary value analysis (sel {0,1}, data min/sign/max) ----
    ck(32'h00000000, 32'hFFFFFFFF, 1'b0, "BVA sel0 min");
    ck(32'h7FFFFFFF, 32'h80000000, 1'b0, "BVA sel0 sign-bound");
    ck(32'hFFFFFFFF, 32'h00000000, 1'b0, "BVA sel0 max");
    ck(32'h00000000, 32'hFFFFFFFF, 1'b1, "BVA sel1 max");
    ck(32'h7FFFFFFF, 32'h80000000, 1'b1, "BVA sel1 sign-bound");
    ck(32'hFFFFFFFF, 32'h00000000, 1'b1, "BVA sel1 min");

    $display("[tb_next_pc_mux] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
