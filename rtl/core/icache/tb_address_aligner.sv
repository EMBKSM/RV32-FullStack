// tb_address_aligner.sv - self-checking TB for address_aligner.vhd (entity addr_aligner).
// Pure slicing: tag=addr[31:12], idx=addr[11:4], offset=addr[3:0].
`timescale 1ns/1ps
module tb_address_aligner;
  logic [31:0] address;
  logic [19:0] tag;
  logic [7:0]  idx;
  logic [3:0]  offset;
  addr_aligner dut (.address(address), .tag(tag), .idx(idx), .offset(offset));

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] a, input string nm);
    logic [19:0] et = a[31:12]; logic [7:0] ei = a[11:4]; logic [3:0] eo = a[3:0];
    address=a; #1; checks++;
    if (tag!==et || idx!==ei || offset!==eo) begin errors++;
      $error("%s FAIL: a=%h tag=%h/%h idx=%h/%h off=%h/%h",nm,a,tag,et,idx,ei,offset,eo); end
  endtask

  initial begin
    ck(32'h0000_0000, "zero");
    ck(32'hFFFF_FFFF, "all ones");
    ck(32'hABCDE_123 << 0, "mix");        // arbitrary
    ck(32'h1234_5678, "pattern");
    for (int i=0;i<4000;i++) ck($urandom, "rand");
    // ---- 3-point boundary value analysis (offset/idx carry boundaries) ----
    ck(32'h0000000E, "BVA off=E");
    ck(32'h0000000F, "BVA off=F (max)");
    ck(32'h00000010, "BVA off carry -> idx");
    ck(32'h00000FF0, "BVA idx=FF");
    ck(32'h00000FFF, "BVA idx=FF off=F");
    ck(32'h00001000, "BVA idx carry -> tag");
    ck(32'h00000000, "BVA all-min");
    ck(32'hFFFFFFFF, "BVA all-max");

    $display("[tb_address_aligner] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
