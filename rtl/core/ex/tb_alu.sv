// =====================================================================
// tb_alu.sv  -  Self-checking SystemVerilog testbench for alu.vhd
// ATDD: implements acceptance tests AT-01..AT-30 (alu_acceptance_tests.md).
// Mixed-language: instantiates the VHDL entity 'alu' (run in Vivado xsim / Questa).
//   xsim:  xvhdl alu.vhd ; xvlog -sv tb_alu.sv ; xelab tb_alu -R
//   questa: vcom alu.vhd ; vlog -sv tb_alu.sv ; vsim -c tb_alu -do "run -all"
// =====================================================================
`timescale 1ns/1ps
module tb_alu;

  logic [31:0] a, b, result;
  logic [3:0]  alu_ctrl;
  logic        zero;

  // ---- DUT (VHDL) ----
  alu dut (.a(a), .b(b), .alu_ctrl(alu_ctrl), .result(result), .zero(zero));

  // ---- independent golden reference (AT-30 random) ----
  function automatic logic [31:0] golden(input logic [31:0] ga, gb, input logic [3:0] gc);
    logic [4:0] sh = gb[4:0];
    case (gc)
      4'b0000: golden = ga + gb;
      4'b0001: golden = ga - gb;
      4'b0010: golden = ga & gb;
      4'b0011: golden = ga | gb;
      4'b0100: golden = ga ^ gb;
      4'b0101: golden = ga << sh;
      4'b0110: golden = ga >> sh;
      4'b0111: golden = $signed(ga) >>> sh;
      4'b1000: golden = ($signed(ga) <  $signed(gb)) ? 32'd1 : 32'd0;
      4'b1001: golden = (ga < gb)                    ? 32'd1 : 32'd0;
      4'b1010: golden = gb;
      default: golden = 32'd0;
    endcase
  endfunction

  int unsigned checks = 0, errors = 0;

  // directed check with an INDEPENDENT expected value (acceptance criteria)
  task automatic at(input logic [31:0] ta, tb_, input logic [3:0] tc,
                    input logic [31:0] exp, input string name);
    a = ta; b = tb_; alu_ctrl = tc; #1;
    checks++;
    if (result !== exp) begin errors++;
      $error("%s FAIL: a=%h b=%h ctrl=%b result=%h expected=%h", name, ta, tb_, tc, result, exp); end
    if (zero !== (exp == 32'd0)) begin errors++;
      $error("%s FAIL: zero=%b expected=%b", name, zero, (exp==32'd0)); end
  endtask

  // randomized counter-example check vs golden
  task automatic at_rand(input int n);
    logic [31:0] ra, rb, exp; logic [3:0] rc;
    for (int i = 0; i < n; i++) begin
      ra = $urandom; rb = $urandom; rc = $urandom_range(0, 11);
      a = ra; b = rb; alu_ctrl = rc; #1;
      exp = golden(ra, rb, rc); checks++;
      if (result !== exp) begin errors++;
        $error("AT-30 COUNTER-EXAMPLE: a=%h b=%h ctrl=%b result=%h golden=%h", ra, rb, rc, result, exp);
        if (errors > 20) return;  // cap output
      end
    end
  endtask

  initial begin
    at(32'h00000003, 32'h00000004, 4'b0000, 32'h00000007, "AT-01 ADD");
    at(32'hFFFFFFFF, 32'h00000001, 4'b0000, 32'h00000000, "AT-02 ADD wrap");
    at(32'hFFFFFFFF, 32'h00000002, 4'b0000, 32'h00000001, "AT-03 ADD -1+2");
    at(32'h0000000A, 32'h00000003, 4'b0001, 32'h00000007, "AT-04 SUB");
    at(32'h00000005, 32'h00000005, 4'b0001, 32'h00000000, "AT-05 SUB to 0");
    at(32'h00000000, 32'h00000001, 4'b0001, 32'hFFFFFFFF, "AT-06 SUB underflow");
    at(32'hF0F0F0F0, 32'h0FF00FF0, 4'b0010, 32'h00F000F0, "AT-07 AND");
    at(32'hF0F0F0F0, 32'h0F0F0F0F, 4'b0011, 32'hFFFFFFFF, "AT-08 OR");
    at(32'hAAAAAAAA, 32'hAAAAAAAA, 4'b0100, 32'h00000000, "AT-09 XOR self");
    at(32'h00000001, 32'h00000001, 4'b0101, 32'h00000002, "AT-10 SLL 1");
    at(32'h00000001, 32'h0000001F, 4'b0101, 32'h80000000, "AT-11 SLL 31");
    at(32'h00000001, 32'h00000020, 4'b0101, 32'h00000001, "AT-12 SLL mask");
    at(32'h000000F0, 32'h00000004, 4'b0110, 32'h0000000F, "AT-13 SRL 4");
    at(32'h80000000, 32'h00000001, 4'b0110, 32'h40000000, "AT-14 SRL MSB");
    at(32'h80000000, 32'h00000001, 4'b0111, 32'hC0000000, "AT-15 SRA neg");
    at(32'h40000000, 32'h00000001, 4'b0111, 32'h20000000, "AT-16 SRA pos");
    at(32'h80000000, 32'h0000001F, 4'b0111, 32'hFFFFFFFF, "AT-17 SRA 31 neg");
    at(32'hFFFFFFFF, 32'h00000001, 4'b1000, 32'h00000001, "AT-18 SLT -1<1");
    at(32'h00000001, 32'hFFFFFFFF, 4'b1000, 32'h00000000, "AT-19 SLT 1<-1");
    at(32'h00000005, 32'h00000005, 4'b1000, 32'h00000000, "AT-20 SLT equal");
    at(32'h00000001, 32'hFFFFFFFF, 4'b1001, 32'h00000001, "AT-21 SLTU 1<max");
    at(32'hFFFFFFFF, 32'h00000001, 4'b1001, 32'h00000000, "AT-22 SLTU max<1");
    at(32'h7FFFFFFF, 32'h80000000, 4'b1001, 32'h00000001, "AT-23 SLTU divergence");
    at(32'h12345678, 32'hDEADBEEF, 4'b1010, 32'hDEADBEEF, "AT-24 Bpass");
    at(32'h0000FF00, 32'h000000FF, 4'b0010, 32'h00000000, "AT-25 zero via AND");
    at(32'hFFFFFFFF, 32'h00000004, 4'b0101, 32'hFFFFFFF0, "AT-26 SLL high bits");
    at(32'h12345678, 32'h00000000, 4'b0101, 32'h12345678, "AT-27 SLL by 0");
    at(32'h12345678, 32'h9ABCDEF0, 4'b1111, 32'h00000000, "AT-28 illegal ctrl");
    at(32'hFFFFFFFF, 32'h0000001F, 4'b0110, 32'h00000001, "AT-29 SRL 31");
    at_rand(100000);                                         // AT-30 counter-example sweep

    // ---- 3-point boundary value analysis (ADD wrap, shamt 30/31/32, sign edge) ----
    at(32'hFFFFFFFE, 32'h00000001, 4'b0000, 32'hFFFFFFFF, "BVA ADD max-1");
    at(32'hFFFFFFFF, 32'h00000001, 4'b0000, 32'h00000000, "BVA ADD wrap");
    at(32'h00000000, 32'h00000001, 4'b0000, 32'h00000001, "BVA ADD min+1");
    at(32'h00000001, 32'h0000001E, 4'b0101, 32'h40000000, "BVA SLL sh=30");
    at(32'h00000001, 32'h0000001F, 4'b0101, 32'h80000000, "BVA SLL sh=31 (max)");
    at(32'h00000001, 32'h00000020, 4'b0101, 32'h00000001, "BVA SLL sh=32 -> mask 0");
    at(32'h7FFFFFFF, 32'h80000000, 4'b1000, 32'h00000000, "BVA SLT maxpos<maxneg=0");
    at(32'h80000000, 32'h7FFFFFFF, 4'b1000, 32'h00000001, "BVA SLT maxneg<maxpos=1");
    at(32'h7FFFFFFF, 32'h80000000, 4'b1001, 32'h00000001, "BVA SLTU divergence=1");

    $display("[tb_alu] checks=%0d errors=%0d", checks, errors);
    if (errors == 0) $display("RESULT: ALL PASS (30 acceptance tests)");
    else             $fatal(1, "RESULT: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
