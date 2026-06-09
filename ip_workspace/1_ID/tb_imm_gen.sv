// tb_imm_gen.sv - self-checking TB for imm_gen.vhd (RV32I I/S/B/U/J immediates).
// Directed + random vs an independent golden decoder.
`timescale 1ns/1ps
module tb_imm_gen;
  logic [31:0] instr, imm;
  logic [6:0]  opcode;
  imm_gen dut (.instr(instr), .opcode(opcode), .imm(imm));

  localparam OP_I=7'h13, OP_LD=7'h03, OP_ST=7'h23, OP_BR=7'h63,
             OP_LUI=7'h37, OP_AUIPC=7'h17, OP_JAL=7'h6F, OP_JALR=7'h67;

  function automatic logic [31:0] golden(input logic [31:0] x, input logic [6:0] op);
    case (op)
      OP_ST:           return {{20{x[31]}}, x[31:25], x[11:7]};
      OP_BR:           return {{19{x[31]}}, x[31], x[7], x[30:25], x[11:8], 1'b0};
      OP_LUI, OP_AUIPC:return {x[31:12], 12'h0};
      OP_JAL:          return {{11{x[31]}}, x[31], x[19:12], x[20], x[30:21], 1'b0};
      default:         return {{20{x[31]}}, x[31:20]};   // I (incl. Load/JALR)
    endcase
  endfunction

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] x, input logic [6:0] op, input string nm);
    logic [31:0] exp=golden(x,op); instr=x; opcode=op; #1; checks++;
    if (imm !== exp) begin errors++; $error("%s FAIL: instr=%h op=%h imm=%h exp=%h",nm,x,op,imm,exp); end
  endtask

  initial begin
    ck(32'hFFF00013, OP_I,   "I -1");
    ck(32'h00100013, OP_I,   "I +1");
    ck(32'h7FF00013, OP_I,   "I +2047");
    ck(32'h80000023, OP_ST,  "S sign");
    ck(32'hABCDE0B7, OP_LUI, "U LUI");
    ck(32'h800000EF, OP_JAL, "J sign bit20");
    ck(32'h80000063, OP_BR,  "B sign bit12");
    for (int i=0;i<5000;i++) begin
      logic [6:0] ops [0:7] = '{OP_I,OP_LD,OP_ST,OP_BR,OP_LUI,OP_AUIPC,OP_JAL,OP_JALR};
      ck($urandom, ops[$urandom_range(0,7)], "rand");
    end
    // ---- 3-point boundary value analysis (12-bit signed imm @ +2047/-2048) ----
    ck(32'h7FE00013, OP_I,   "BVA I +2046");
    ck(32'h7FF00013, OP_I,   "BVA I +2047 (max+)");
    ck(32'h80000013, OP_I,   "BVA I -2048 (min-)");   // imm field 0x800
    ck(32'hFFF00013, OP_I,   "BVA I -1");
    ck(32'h00000013, OP_I,   "BVA I 0");
    ck(32'h00100013, OP_I,   "BVA I +1");
    ck(32'hFFFFF037, OP_LUI, "BVA U max field");
    ck(32'h00000037, OP_LUI, "BVA U 0 field");

    $display("[tb_imm_gen] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
