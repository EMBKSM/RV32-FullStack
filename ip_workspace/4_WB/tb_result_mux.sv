// tb_result_mux.sv - self-checking TB for result_mux.vhd (WB write-back select).
// csr_to_reg overrides -> csr; else result_src: 00 ALU,01 ReadData,10 PC+4.
`timescale 1ns/1ps
module tb_result_mux;
  logic [1:0]  result_src;
  logic        csr_to_reg;
  logic [31:0] alu_result, read_data, pc_plus4, csr_rdata, write_data;
  result_mux dut (.result_src(result_src), .csr_to_reg(csr_to_reg),
    .alu_result(alu_result), .read_data(read_data), .pc_plus4(pc_plus4),
    .csr_rdata(csr_rdata), .write_data(write_data));

  function automatic logic [31:0] g(input logic[1:0] rs, input logic cr,
                                    input logic[31:0] al,rd,p4,cs);
    if (cr) return cs;
    case (rs) 2'b00:return al; 2'b01:return rd; 2'b10:return p4; default:return al; endcase
  endfunction

  int errors=0, checks=0;
  task automatic ck(input logic[1:0] rs, input logic cr,
                    input logic[31:0] al,rd,p4,cs, input string nm);
    logic[31:0] exp=g(rs,cr,al,rd,p4,cs);
    result_src=rs; csr_to_reg=cr; alu_result=al; read_data=rd; pc_plus4=p4; csr_rdata=cs; #1; checks++;
    if (write_data!==exp) begin errors++; $error("%s FAIL: wd=%h exp=%h",nm,write_data,exp); end
  endtask

  initial begin
    ck(2'b00,0,32'hA,32'hB,32'hC,32'hD,"ALU");
    ck(2'b01,0,32'hA,32'hB,32'hC,32'hD,"ReadData");
    ck(2'b10,0,32'hA,32'hB,32'hC,32'hD,"PC+4");
    ck(2'b00,1,32'hA,32'hB,32'hC,32'hD,"CSR override");
    ck(2'b10,1,32'hA,32'hB,32'hC,32'hD,"CSR beats PC+4");
    for (int i=0;i<5000;i++)
      ck($urandom_range(0,3),$urandom_range(0,1),$urandom,$urandom,$urandom,$urandom,"rand");
    // ---- 3-point boundary value analysis (result_src 00/01/10/11-default, csr edge) ----
    ck(2'b00, 0, 32'hA, 32'hB, 32'hC, 32'hD, "BVA src=00 ALU");
    ck(2'b01, 0, 32'hA, 32'hB, 32'hC, 32'hD, "BVA src=01 MEM");
    ck(2'b10, 0, 32'hA, 32'hB, 32'hC, 32'hD, "BVA src=10 PC+4");
    ck(2'b11, 0, 32'hA, 32'hB, 32'hC, 32'hD, "BVA src=11 default->ALU");
    ck(2'b00, 1, 32'hA, 32'hB, 32'hC, 32'hD, "BVA csr=1 override edge");

    $display("[tb_result_mux] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
