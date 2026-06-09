// tb_read_aligner.sv - self-checking TB for read_aligner.vhd (load extract+extend).
// Input is the word-selected 32-bit word; byte_off + funct3 -> LB/LH/LW/LBU/LHU.
`timescale 1ns/1ps
module tb_read_aligner;
  logic [31:0] word_data, read_data;
  logic [1:0]  byte_off;
  logic [2:0]  funct3;
  read_aligner dut (.word_data(word_data), .byte_off(byte_off),
                    .funct3(funct3), .read_data(read_data));

  function automatic logic [31:0] golden(input logic [31:0] w, input logic [1:0] bo, input logic [2:0] f3);
    logic [7:0]  b = w[8*bo +: 8];
    logic [15:0] h = (bo[1]==0) ? w[15:0] : w[31:16];
    case (f3)
      3'b000: return {{24{b[7]}}, b};   // LB
      3'b001: return {{16{h[15]}}, h};  // LH
      3'b010: return w;                 // LW
      3'b100: return {24'h0, b};        // LBU
      3'b101: return {16'h0, h};        // LHU
      default:return w;
    endcase
  endfunction

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] w, input logic [1:0] bo, input logic [2:0] f3, input string nm);
    logic [31:0] exp=golden(w,bo,f3); word_data=w; byte_off=bo; funct3=f3; #1; checks++;
    if (read_data!==exp) begin errors++; $error("%s FAIL: w=%h bo=%0d f3=%b rd=%h exp=%h",nm,w,bo,f3,read_data,exp); end
  endtask

  initial begin
    ck(32'h000000FF,2'd0,3'b000,"LB sign");
    ck(32'h000000FF,2'd0,3'b100,"LBU zero");
    ck(32'h80000000,2'd3,3'b000,"LB off3 neg");
    ck(32'h0000FFFF,2'd0,3'b001,"LH sign");
    ck(32'hABCD0000,2'd2,3'b101,"LHU off2");
    ck(32'h12345678,2'd0,3'b010,"LW");
    for (int i=0;i<6000;i++) begin
      logic [2:0] f3s [0:4] = '{3'b000,3'b001,3'b010,3'b100,3'b101};
      ck($urandom, $urandom_range(0,3), f3s[$urandom_range(0,4)], "rand");
    end
    // ---- 3-point boundary value analysis (byte sign @0x7F/0x80, half @0x7FFF/0x8000) ----
    ck(32'h0000007E, 2'd0, 3'b000, "BVA LB +126");
    ck(32'h0000007F, 2'd0, 3'b000, "BVA LB +127 (max+)");
    ck(32'h00000080, 2'd0, 3'b000, "BVA LB -128 (min-)");
    ck(32'h0000007F, 2'd0, 3'b100, "BVA LBU +127");
    ck(32'h00007FFF, 2'd0, 3'b001, "BVA LH +32767 (max+)");
    ck(32'h00008000, 2'd0, 3'b001, "BVA LH -32768 (min-)");
    ck(32'hFF000000, 2'd3, 3'b000, "BVA LB off3 byte boundary");

    $display("[tb_read_aligner] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
