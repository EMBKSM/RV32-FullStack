// tb_forwarding_unit.sv - self-checking TB for forwarding_unit.vhd.
// Priority EX/MEM(10) > MEM/WB(01) > RF(00); rd!=0 and reg_write gating.
`timescale 1ns/1ps
module tb_forwarding_unit;
  logic [4:0] id_ex_rs1, id_ex_rs2, ex_mem_rd, mem_wb_rd;
  logic       ex_mem_reg_write, mem_wb_reg_write;
  logic [1:0] forward_a, forward_b;
  forwarding_unit dut (.id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
    .ex_mem_rd(ex_mem_rd), .ex_mem_reg_write(ex_mem_reg_write),
    .mem_wb_rd(mem_wb_rd), .mem_wb_reg_write(mem_wb_reg_write),
    .forward_a(forward_a), .forward_b(forward_b));

  function automatic logic [1:0] g(input logic[4:0] rs, em_rd, mw_rd, input logic em_rw, mw_rw);
    if (em_rw && em_rd!=0 && em_rd==rs) return 2'b10;
    if (mw_rw && mw_rd!=0 && mw_rd==rs) return 2'b01;
    return 2'b00;
  endfunction

  int errors=0, checks=0;
  task automatic ck(input logic[4:0] s1,s2,em,mw, input logic erw,mrw, input string nm);
    logic[1:0] ea=g(s1,em,mw,erw,mrw), eb=g(s2,em,mw,erw,mrw);
    id_ex_rs1=s1; id_ex_rs2=s2; ex_mem_rd=em; mem_wb_rd=mw;
    ex_mem_reg_write=erw; mem_wb_reg_write=mrw; #1; checks++;
    if (forward_a!==ea || forward_b!==eb) begin errors++;
      $error("%s FAIL: fa=%b/%b fb=%b/%b",nm,forward_a,ea,forward_b,eb); end
  endtask

  initial begin
    ck(5,6,5,9,1,1,"EX/MEM fa");
    ck(5,6,9,5,1,1,"MEM/WB fa");
    ck(5,6,9,8,1,1,"none");
    ck(5,0,5,5,1,1,"priority EX/MEM beats MEM/WB");
    ck(0,0,0,0,1,1,"x0 no forward");
    ck(5,5,5,5,0,1,"em_rw=0 -> MEM/WB");
    for (int i=0;i<5000;i++)
      ck($urandom,$urandom,$urandom,$urandom,$urandom_range(0,1),$urandom_range(0,1),"rand");
    // ---- 3-point boundary value analysis (rd register-number edge x0/x1/x31) ----
    ck(5'd1, 5'd2, 5'd1, 5'd9, 1,1, "BVA em_rd=x1");
    ck(5'd0, 5'd0, 5'd0, 5'd0, 1,1, "BVA rd=x0 (no fwd)");
    ck(5'd31,5'd2, 5'd31,5'd9, 1,1, "BVA em_rd=x31");
    ck(5'd1, 5'd2, 5'd9, 5'd1, 1,1, "BVA mw_rd=x1");

    $display("[tb_forwarding_unit] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
