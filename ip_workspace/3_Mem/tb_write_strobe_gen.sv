// tb_write_strobe_gen.sv - self-checking TB for write_strobe_gen.vhd (SB/SH/SW).
// Generates byte strobe + lane-replicated wdata from funct3 + byte_off.
`timescale 1ns/1ps
module tb_write_strobe_gen;
  logic [2:0]  funct3;
  logic [1:0]  byte_off;
  logic [31:0] store_data, wdata_aligned;
  logic [3:0]  wstrb;
  write_strobe_gen dut (.funct3(funct3), .byte_off(byte_off), .store_data(store_data),
                        .wstrb(wstrb), .wdata_aligned(wdata_aligned));

  task automatic gws(input logic[2:0] f3, input logic[1:0] bo, input logic[31:0] sd,
                     output logic[3:0] ews, output logic[31:0] ewd);
    case (f3)
      3'b000: begin ews = (4'h1<<bo); ewd = {4{sd[7:0]}}; end
      3'b001: begin ews = (bo[1]==0)?4'h3:4'hC; ewd = {2{sd[15:0]}}; end
      3'b010: begin ews = 4'hF; ewd = sd; end
      default:begin ews = 4'h0; ewd = sd; end
    endcase
  endtask

  int errors=0, checks=0;
  task automatic ck(input logic[2:0] f3, input logic[1:0] bo, input logic[31:0] sd, input string nm);
    logic[3:0] ews; logic[31:0] ewd; gws(f3,bo,sd,ews,ewd);
    funct3=f3; byte_off=bo; store_data=sd; #1; checks++;
    if (wstrb!==ews || wdata_aligned!==ewd) begin errors++;
      $error("%s FAIL: ws=%b/%b wd=%h/%h",nm,wstrb,ews,wdata_aligned,ewd); end
  endtask

  initial begin
    ck(3'b000,2'd0,32'hAB,"SB off0");
    ck(3'b000,2'd1,32'hAB,"SB off1");
    ck(3'b000,2'd2,32'hAB,"SB off2");
    ck(3'b000,2'd3,32'hAB,"SB off3");
    ck(3'b001,2'd0,32'hBEEF,"SH lo");
    ck(3'b001,2'd2,32'hBEEF,"SH hi");
    ck(3'b010,2'd0,32'h12345678,"SW");
    for (int i=0;i<4000;i++) begin
      logic [2:0] f3s [0:2] = '{3'b000,3'b001,3'b010};
      ck(f3s[$urandom_range(0,2)], $urandom_range(0,3), $urandom, "rand");
    end
    // ---- 3-point boundary value analysis (byte_off edges 0/3, data min/max) ----
    ck(3'b000, 2'd0, 32'h00000000, "BVA SB off0 data=min");
    ck(3'b000, 2'd3, 32'hFFFFFFFF, "BVA SB off3 data=max");
    ck(3'b001, 2'd0, 32'h00000000, "BVA SH lo data=min");
    ck(3'b001, 2'd2, 32'hFFFFFFFF, "BVA SH hi data=max");
    ck(3'b010, 2'd0, 32'h00000000, "BVA SW min");
    ck(3'b010, 2'd0, 32'hFFFFFFFF, "BVA SW max");

    $display("[tb_write_strobe_gen] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
