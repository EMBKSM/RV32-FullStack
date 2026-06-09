// tb_csr_file.sv - self-checking TB for csr_file.vhd (machine-mode Zicsr + trap path).
// Read combinational; CSRRW/RS/RC write & trap/MRET update on clock edge.
//
// NOTE: reads use a TASK (ckrd) not a function -- a SystemVerilog function may not
// contain delays (#), so the settle delay before sampling csr_rdata must live in a
// task. Write-enables are held through the posedge and deasserted on the next
// negedge (race-free in mixed-language sim).
`timescale 1ns/1ps
module tb_csr_file;
  logic clk=0, reset;
  logic [11:0] csr_addr;
  logic [1:0]  csr_cmd;
  logic [31:0] csr_wdata, csr_rdata;
  logic        csr_we, trap_we, is_mret;
  logic [31:0] trap_mepc, trap_mcause, trap_mtval, mstatus_o, mtvec_o, mepc_o;
  always #5 clk=~clk;

  csr_file dut (.clk(clk), .reset(reset), .csr_addr(csr_addr), .csr_cmd(csr_cmd),
    .csr_wdata(csr_wdata), .csr_we(csr_we), .csr_rdata(csr_rdata),
    .trap_we(trap_we), .trap_mepc(trap_mepc), .trap_mcause(trap_mcause),
    .trap_mtval(trap_mtval), .is_mret(is_mret),
    .mstatus_o(mstatus_o), .mtvec_o(mtvec_o), .mepc_o(mepc_o));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if (!cond) begin errors++; $error("%s FAIL (rdata=%h mstatus=%h)",nm,csr_rdata,mstatus_o); end
  endtask
  // read+check (settle delay lives in a task, not a function)
  task automatic ckrd(input logic [11:0] a, input logic [31:0] exp, input string nm);
    csr_addr=a; #1; checks++;
    if (csr_rdata !== exp) begin errors++; $error("%s FAIL: csr[%h]=%h exp=%h",nm,a,csr_rdata,exp); end
  endtask
  // race-free CSR access: hold csr_we through the posedge, deassert at next negedge
  task automatic csrop(input logic [11:0] a, input logic [1:0] cmd,
                       input logic [31:0] d, input logic we);
    @(negedge clk); csr_addr=a; csr_cmd=cmd; csr_wdata=d; csr_we=we; trap_we=0; is_mret=0;
    @(posedge clk); @(negedge clk); csr_we=0; csr_cmd=2'b00;
  endtask

  initial begin
    reset=1; csr_addr=0; csr_cmd=0; csr_wdata=0; csr_we=0;
    trap_we=0; trap_mepc=0; trap_mcause=0; trap_mtval=0; is_mret=0;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);

    // misa read-only identity
    ckrd(12'h301, 32'h40000100, "misa RO");
    // mtvec CSRRW
    csrop(12'h305, 2'b01, 32'hDEADBEEF, 1); ckrd(12'h305, 32'hDEADBEEF, "mtvec RW");
    ck(mtvec_o==32'hDEADBEEF, "mtvec exported");
    // mscratch set/clear (RS/RC)
    csrop(12'h340, 2'b01, 32'h0000000F, 1);
    csrop(12'h340, 2'b10, 32'h000000F0, 1); ckrd(12'h340, 32'h000000FF, "RS set");
    csrop(12'h340, 2'b11, 32'h0000000F, 1); ckrd(12'h340, 32'h000000F0, "RC clear");
    // csr_we=0 suppresses write
    csrop(12'h340, 2'b01, 32'h12345678, 0); ckrd(12'h340, 32'h000000F0, "we=0 no write");

    // ---- trap entry: MIE=1 first ----
    csrop(12'h300, 2'b01, 32'h00000008, 1);                 // mstatus.MIE=1 (bit3)
    @(negedge clk); csr_addr=0; csr_cmd=0; csr_we=0; trap_we=1; is_mret=0;
    trap_mepc=32'h00000100; trap_mcause=32'd2; trap_mtval=32'h00000ABC;
    @(posedge clk); @(negedge clk); trap_we=0;
    ckrd(12'h341, 32'h00000100, "trap mepc");
    ckrd(12'h342, 32'd2,        "trap mcause");
    ckrd(12'h343, 32'h00000ABC, "trap mtval");
    ck(mstatus_o[7]==1'b1 && mstatus_o[3]==1'b0 && mstatus_o[12:11]==2'b11, "trap mstatus MPIE/MIE/MPP");

    // ---- MRET restore ----
    @(negedge clk); trap_we=0; is_mret=1;
    @(posedge clk); @(negedge clk); is_mret=0;
    ck(mstatus_o[3]==1'b1 && mstatus_o[7]==1'b1 && mstatus_o[12:11]==2'b00, "mret mstatus MIE<=MPIE,MPP=0");

    // ---- 3-point boundary value analysis (write-data min/max, set/clear mask edges) ----
    csrop(12'h340, 2'b01, 32'h00000000, 1); ckrd(12'h340, 32'h00000000, "BVA RW min");
    csrop(12'h340, 2'b01, 32'hFFFFFFFF, 1); ckrd(12'h340, 32'hFFFFFFFF, "BVA RW max");
    csrop(12'h340, 2'b11, 32'hFFFFFFFF, 1); ckrd(12'h340, 32'h00000000, "BVA RC all-ones -> 0");
    csrop(12'h340, 2'b10, 32'h00000001, 1); ckrd(12'h340, 32'h00000001, "BVA RS bit0");
    csrop(12'h340, 2'b10, 32'h80000000, 1); ckrd(12'h340, 32'h80000001, "BVA RS bit31");

    // ---- timing-issue tests (edge update priority, async reset) ----
    // trap_we + is_mret + csr_we all asserted on the SAME edge -> trap entry wins
    csrop(12'h341, 2'b01, 32'h00000000, 1);                 // mepc <- 0 first
    @(negedge clk); csr_addr=12'h300; csr_cmd=2'b01; csr_wdata=32'hFFFFFFFF; csr_we=1;
    trap_we=1; trap_mepc=32'h00000200; trap_mcause=32'd7; trap_mtval=32'h00000111; is_mret=1;
    @(posedge clk); @(negedge clk); csr_we=0; trap_we=0; is_mret=0;
    ckrd(12'h341, 32'h00000200, "TIMING trap_we beats csr_we/mret (mepc)");
    ckrd(12'h342, 32'd7,        "TIMING trap_we beats csr_we/mret (mcause)");
    // async reset clears CSRs immediately (between edges)
    csrop(12'h305, 2'b01, 32'hDEADBEEF, 1);
    reset=1; #2; ck(mtvec_o==32'h00000000, "TIMING async reset clears CSR"); reset=0;

    $display("[tb_csr_file] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
