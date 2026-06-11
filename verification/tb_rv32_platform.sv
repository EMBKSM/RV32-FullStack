// tb_rv32_platform.sv - verify the PL platform via its AXI4-Lite control slave.
// Primary (production) flow: load program -> RUN -> read back register/MMIO state.
// This is exactly how the host (PS/Windows app) will use it: assemble + load +
// run + read the result. Plus a single-step SANITY check (commit advances).
`timescale 1ns/1ps
module tb_rv32_platform;
  logic ACLK=0, ARESETN=0;
  logic [7:0]  AWADDR=0;  logic AWVALID=0, AWREADY;
  logic [31:0] WDATA=0;   logic [3:0] WSTRB=4'hF; logic WVALID=0, WREADY;
  logic [1:0]  BRESP;     logic BVALID, BREADY=1;
  logic [7:0]  ARADDR=0;  logic ARVALID=0, ARREADY;
  logic [31:0] RDATA;     logic [1:0] RRESP; logic RVALID, RREADY=1;
  logic [3:0]  led_o;     logic [3:0] sw_i=4'h0, btn_i=4'h0;

  rv32_platform dut (
    .S_AXI_ACLK(ACLK), .S_AXI_ARESETN(ARESETN),
    .S_AXI_AWADDR(AWADDR), .S_AXI_AWVALID(AWVALID), .S_AXI_AWREADY(AWREADY),
    .S_AXI_WDATA(WDATA), .S_AXI_WSTRB(WSTRB), .S_AXI_WVALID(WVALID), .S_AXI_WREADY(WREADY),
    .S_AXI_BRESP(BRESP), .S_AXI_BVALID(BVALID), .S_AXI_BREADY(BREADY),
    .S_AXI_ARADDR(ARADDR), .S_AXI_ARVALID(ARVALID), .S_AXI_ARREADY(ARREADY),
    .S_AXI_RDATA(RDATA), .S_AXI_RRESP(RRESP), .S_AXI_RVALID(RVALID), .S_AXI_RREADY(RREADY),
    .led_o(led_o), .sw_i(sw_i), .btn_i(btn_i));
  always #5 ACLK = ~ACLK;

  localparam CTRL=8'h00, STATUS=8'h04, IMEM_ADDR=8'h08, IMEM_WDATA=8'h0C,
             REG_ADDR=8'h18, REG_RDATA=8'h1C, PC=8'h20, COMMIT_CNT=8'h2C;

  task automatic axi_w(input [7:0] a, input [31:0] d);
    @(negedge ACLK); AWADDR=a; WDATA=d; AWVALID=1; WVALID=1;
    @(posedge ACLK); while(!(AWREADY&&WREADY)) @(posedge ACLK);
    @(negedge ACLK); AWVALID=0; WVALID=0;
    @(posedge ACLK); while(!BVALID) @(posedge ACLK);
    @(negedge ACLK);
  endtask
  task automatic axi_r(input [7:0] a, output [31:0] d);
    @(negedge ACLK); ARADDR=a; ARVALID=1;
    @(posedge ACLK); while(!ARREADY) @(posedge ACLK);
    @(negedge ACLK); ARVALID=0;
    @(posedge ACLK); while(!RVALID) @(posedge ACLK);
    d=RDATA; @(negedge ACLK);
  endtask
  task automatic rdreg(input int idx, output [31:0] d);
    axi_w(REG_ADDR, idx); axi_r(REG_RDATA, d);
  endtask

  int errors=0, checks=0;
  task automatic ck(input [31:0] got, exp, input string nm);
    checks++; if(got!==exp) begin errors++; $error("%s: got=%h exp=%h",nm,got,exp); end
  endtask

  function automatic logic [31:0] Itype(int imm,rs1,f3,rd,opc);
    return ((imm&12'hFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] R(int f7,rs2,rs1,f3,rd,opc);
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] Stype(int imm,rs2,rs1,f3,opc);
    return (((imm>>5)&7'h7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&5'h1F)<<7)|opc; endfunction
  function automatic logic [31:0] addi(int rd,rs1,imm); return Itype(imm,rs1,0,rd,7'h13); endfunction
  function automatic logic [31:0] add_(int rd,rs1,rs2); return R(0,rs2,rs1,0,rd,7'h33); endfunction
  function automatic logic [31:0] lui_(int rd,imm20);   return ((imm20&20'hFFFFF)<<12)|(rd<<7)|7'h37; endfunction
  function automatic logic [31:0] sw_ (int rs2,rs1,imm);return Stype(imm,rs2,rs1,2,7'h23); endfunction
  function automatic logic [31:0] jal_(int rd,off);     return (((off>>20)&1)<<31)|(((off>>1)&10'h3FF)<<21)|
                                                                (((off>>11)&1)<<20)|(((off>>12)&8'hFF)<<12)|(rd<<7)|7'h6F; endfunction

  task automatic load_and_reset(input logic [31:0] p[]);
    axi_w(CTRL, 32'h1);                              // cpu_reset=1 (hold)
    for (int i=0;i<p.size();i++) begin
      axi_w(IMEM_ADDR, i*4); axi_w(IMEM_WDATA, p[i]);
    end
    axi_w(CTRL, 32'h0);                              // release (frozen, run=0)
  endtask

  logic [31:0] prog [];
  logic [31:0] v, c0, c1;
  initial begin
    prog = '{ addi(1,0,7), addi(2,0,11), add_(3,1,2),
              lui_(4,'h10000), sw_(3,4,0), jal_(0,0) };   // LED base=0x10000000, halt

    ARESETN=0; repeat(4) @(negedge ACLK); ARESETN=1; @(negedge ACLK);

    // ===== production flow: load -> RUN -> read state =====
    load_and_reset(prog);
    axi_w(CTRL, 32'h2);                              // run_en=1
    repeat (1500) @(posedge ACLK);                  // run to halt
    rdreg(1,v); ck(v,32'h7,       "x1 = 7");
    rdreg(2,v); ck(v,32'hB,       "x2 = 11");
    rdreg(3,v); ck(v,32'h12,      "x3 = 18");
    rdreg(4,v); ck(v,32'h10000000,"x4 = LED base");
    ck({28'h0,led_o}, 32'h2, "MMIO LED = 18 & 0xF = 2");
    axi_r(STATUS, v); ck(v[0],1'b1, "STATUS.halted after run");

    // ===== single-step SANITY: from reset, one step advances >=1 commit =====
    load_and_reset(prog);
    axi_r(COMMIT_CNT, c0);
    axi_w(CTRL, 32'h4);                              // step
    repeat (60) @(posedge ACLK);                    // allow refill + retire
    axi_r(COMMIT_CNT, c1);
    checks++;
    if (!(c1 > c0)) begin errors++; $error("step did not advance commit (c0=%0d c1=%0d)",c0,c1); end
    else $display("INFO single-step advanced commit %0d -> %0d", c0, c1);

    if (errors==0) $display("tb_rv32_platform: ALL PASS (%0d checks)", checks);
    else           $fatal(1,"tb_rv32_platform: %0d FAIL", errors);
    $finish;
  end
  initial begin #3000000; $fatal(1,"TIMEOUT"); end
endmodule
