// tb_hazard_unit.sv - self-checking TB for hazard_unit.vhd (load-use detection).
// stall=flush= (id_ex_mem_read & id_ex_rd!=0 & (id_ex_rd==if_id_rs1 | ==if_id_rs2)).
`timescale 1ns/1ps
module tb_hazard_unit;
  logic id_ex_mem_read;
  logic [4:0] id_ex_rd, if_id_rs1, if_id_rs2;
  logic stall, flush;
  hazard_unit dut (.id_ex_mem_read(id_ex_mem_read), .id_ex_rd(id_ex_rd),
                   .if_id_rs1(if_id_rs1), .if_id_rs2(if_id_rs2),
                   .stall(stall), .flush(flush));

  int errors=0, checks=0;
  task automatic ck(input logic mr, input logic[4:0] rd,rs1,rs2,
                    input logic exp, input string nm);
    id_ex_mem_read=mr; id_ex_rd=rd; if_id_rs1=rs1; if_id_rs2=rs2; #1; checks++;
    if (stall!==exp || flush!==exp) begin errors++;
      $error("%s FAIL: stall=%b flush=%b exp=%b",nm,stall,flush,exp); end
  endtask

  initial begin
    ck(1,5'd5,5'd5,5'd9, 1'b1, "match rs1");
    ck(1,5'd5,5'd9,5'd5, 1'b1, "match rs2");
    ck(0,5'd5,5'd5,5'd9, 1'b0, "not a load");
    ck(1,5'd0,5'd0,5'd0, 1'b0, "rd=x0");
    ck(1,5'd5,5'd9,5'd8, 1'b0, "no match");
    // random vs golden
    for (int i=0;i<3000;i++) begin
      logic mr=$urandom_range(0,1); logic[4:0] rd=$urandom, s1=$urandom, s2=$urandom;
      logic exp = (mr && rd!=0 && (rd==s1 || rd==s2));
      ck(mr,rd,s1,s2,exp,"rand");
    end
    // ---- 3-point boundary value analysis (rd register-number edge x0/x1/x31) ----
    ck(1,5'd0, 5'd0, 5'd0, 1'b0, "BVA rd=x0 (no stall)");
    ck(1,5'd1, 5'd1, 5'd9, 1'b1, "BVA rd=x1 match (stall)");
    ck(1,5'd31,5'd31,5'd9, 1'b1, "BVA rd=x31 match (stall)");
    ck(1,5'd1, 5'd2, 5'd3, 1'b0, "BVA rd=x1 no match");

    $display("[tb_hazard_unit] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
