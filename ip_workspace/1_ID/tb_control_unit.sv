// tb_control_unit.sv - self-checking TB for control_unit.vhd (representative ID TB).
// Run in Vivado xsim / Questa (mixed-language). Pattern mirrors tb_alu.sv.
`timescale 1ns/1ps
module tb_control_unit;
  logic [6:0]  opcode;
  logic [2:0]  funct3;
  logic [11:0] instr_31_20;
  logic reg_write, mem_read, mem_write, alu_src, src_a_sel, branch, jump;
  logic [1:0] alu_op, result_src, csr_cmd;
  logic csr_to_reg, csr_use_imm, is_ecall, is_ebreak, is_mret, is_fence_i, illegal;

  control_unit dut (.opcode, .funct3, .instr_31_20,
    .reg_write, .mem_read, .mem_write, .alu_src, .src_a_sel, .branch, .jump,
    .alu_op, .result_src, .csr_to_reg, .csr_use_imm, .csr_cmd,
    .is_ecall, .is_ebreak, .is_mret, .is_fence_i, .illegal);

  int errors = 0, checks = 0;
  task automatic ck(input bit cond, input string name);
    checks++; if (!cond) begin errors++; $error("%s FAIL", name); end
  endtask

  initial begin
    opcode=7'b0110011; funct3=0; instr_31_20=0; #1;                 // R-type
    ck(reg_write && alu_op==2'b10 && !mem_write, "R-type");
    opcode=7'b0000011; #1; ck(mem_read && result_src==2'b01, "Load");
    opcode=7'b0100011; #1; ck(mem_write && !reg_write, "Store");
    opcode=7'b1100011; #1; ck(branch && alu_op==2'b01, "Branch");
    opcode=7'b1101111; #1; ck(jump && result_src==2'b10 && src_a_sel, "JAL");
    opcode=7'b0110111; #1; ck(alu_op==2'b11 && reg_write, "LUI");
    opcode=7'b0010111; #1; ck(src_a_sel && reg_write, "AUIPC");
    opcode=7'b1110011; funct3=3'b001; #1; ck(csr_to_reg && csr_cmd==2'b01, "CSRRW");
    opcode=7'b1110011; funct3=3'b110; #1; ck(csr_cmd==2'b10 && csr_use_imm, "CSRRSI");
    opcode=7'b1110011; funct3=3'b000; instr_31_20=12'h000; #1; ck(is_ecall, "ECALL");
    instr_31_20=12'h001; #1; ck(is_ebreak, "EBREAK");
    instr_31_20=12'h302; #1; ck(is_mret, "MRET");
    opcode=7'b0001111; funct3=3'b001; #1; ck(is_fence_i, "FENCE.I");
    opcode=7'b0000000; #1; ck(illegal, "illegal");
    $display("[tb_control_unit] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1, "RESULT: FAIL");
    $finish;
  end
endmodule
