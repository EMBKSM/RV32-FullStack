// tb_comparator.sv - self-checking TB for comparator.vhd.
// hit = valid_bit AND (addr_tag == cache_tag).
`timescale 1ns/1ps
module tb_comparator;
  logic [19:0] addr_tag, cache_tag;
  logic        valid_bit, hit;
  comparator dut (.addr_tag(addr_tag), .cache_tag(cache_tag),
                  .valid_bit(valid_bit), .hit(hit));

  int errors=0, checks=0;
  task automatic ck(input logic [19:0] at,ct, input logic v, input string nm);
    logic exp = (v && (at==ct));
    addr_tag=at; cache_tag=ct; valid_bit=v; #1; checks++;
    if (hit !== exp) begin errors++; $error("%s FAIL: hit=%b exp=%b",nm,hit,exp); end
  endtask

  initial begin
    ck(20'hABCDE, 20'hABCDE, 1'b1, "hit");
    ck(20'hABCDE, 20'hABCDE, 1'b0, "match but invalid");
    ck(20'hABCDE, 20'h12345, 1'b1, "valid but mismatch");
    ck(20'h00000, 20'h00000, 1'b1, "zero hit");
    for (int i=0;i<3000;i++) begin
      logic [19:0] a=$urandom, c=($urandom_range(0,1)? a : $urandom);
      ck(a, c, $urandom_range(0,1), "rand");
    end
    // ---- 3-point boundary value analysis (equality @0x12345, tag/valid edges) ----
    ck(20'h12344, 20'h12345, 1'b1, "BVA eq-1 miss");
    ck(20'h12345, 20'h12345, 1'b1, "BVA eq hit");
    ck(20'h12346, 20'h12345, 1'b1, "BVA eq+1 miss");
    ck(20'h00000, 20'h00000, 1'b1, "BVA tag min hit");
    ck(20'hFFFFF, 20'hFFFFF, 1'b1, "BVA tag max hit");
    ck(20'h12345, 20'h12345, 1'b0, "BVA valid=0 edge");

    $display("[tb_comparator] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
