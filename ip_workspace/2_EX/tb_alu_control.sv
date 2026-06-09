// tb_alu_control.sv - self-checking TB for alu_control.vhd (exhaustive 64 + golden).
// alu_op: 00 ADD,01 SUB,11 Bpass,10 funct decode (funct3,funct7_5).
`timescale 1ns/1ps
module tb_alu_control;
  logic [1:0] alu_op;
  logic [2:0] funct3;
  logic       funct7_5;
  logic [3:0] alu_ctrl;
  alu_control dut (.alu_op(alu_op), .funct3(funct3), .funct7_5(funct7_5), .alu_ctrl(alu_ctrl));

  function automatic logic [3:0] golden(input logic [1:0] op, input logic [2:0] f3, input logic f75);
    if (op==2'b00) return 4'b0000;
    if (op==2'b01) return 4'b0001;
    if (op==2'b11) return 4'b1010;
    case (f3)
      3'b000: return f75 ? 4'b0001 : 4'b0000;  // SUB/ADD
      3'b001: return 4'b0101;                   // SLL
      3'b010: return 4'b1000;                   // SLT
      3'b011: return 4'b1001;                   // SLTU
      3'b100: return 4'b0100;                   // XOR
      3'b101: return f75 ? 4'b0111 : 4'b0110;  // SRA/SRL
      3'b110: return 4'b0011;                   // OR
      default:return 4'b0010;                   // AND
    endcase
  endfunction

  int errors=0, checks=0;
  initial begin
    for (int op=0; op<4; op++)
      for (int f=0; f<8; f++)
        for (int b=0; b<2; b++) begin
          alu_op=op[1:0]; funct3=f[2:0]; funct7_5=b[0]; #1; checks++;
          if (alu_ctrl !== golden(op[1:0],f[2:0],b[0])) begin errors++;
            $error("FAIL op=%b f3=%b f75=%b ctrl=%b exp=%b",
                   alu_op,funct3,funct7_5,alu_ctrl,golden(op[1:0],f[2:0],b[0])); end
        end
    // ---- 3-point boundary value analysis (funct7_5 edge on bit-sensitive funct3) ----
    // exhaustive sweep above already covers these; asserted explicitly as boundary cases.
    alu_op=2'b10; funct3=3'b000; funct7_5=1'b0; #1; checks++;
      if (alu_ctrl!==4'b0000) begin errors++; $error("BVA ADD f75=0 FAIL"); end
    alu_op=2'b10; funct3=3'b000; funct7_5=1'b1; #1; checks++;
      if (alu_ctrl!==4'b0001) begin errors++; $error("BVA SUB f75=1 FAIL"); end
    alu_op=2'b10; funct3=3'b101; funct7_5=1'b0; #1; checks++;
      if (alu_ctrl!==4'b0110) begin errors++; $error("BVA SRL f75=0 FAIL"); end
    alu_op=2'b10; funct3=3'b101; funct7_5=1'b1; #1; checks++;
      if (alu_ctrl!==4'b0111) begin errors++; $error("BVA SRA f75=1 FAIL"); end

    $display("[tb_alu_control] exhaustive checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS (64 combinations)"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
