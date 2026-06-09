// tb_icache_axi_adapter.sv - unit TB for the simple-handshake <-> AXI4 burst
// bridge. A tiny inline 4-beat AXI read slave (mirrors axi_slave_mem timing)
// feeds the adapter; the stimulus emulates cache_controller's S_SEND_AR/
// S_WAIT_R handshake and checks the assembled 128-bit line + single rvalid.
`timescale 1ns/1ps
module tb_icache_axi_adapter;
  logic clk=0, reset=1;
  // controller side
  logic        c_arvalid, c_arready, c_rvalid;
  logic [31:0] line_addr;
  logic [127:0] rd_line;
  // AXI
  logic [31:0] ARADDR;  logic ARVALID, ARREADY;
  logic [31:0] RDATA;   logic RLAST, RVALID, RREADY;

  icache_axi_adapter dut(.clk(clk), .reset(reset),
    .c_arvalid(c_arvalid), .c_arready(c_arready), .c_rvalid(c_rvalid),
    .line_addr(line_addr), .rd_line(rd_line),
    .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
    .RDATA(RDATA), .RLAST(RLAST), .RVALID(RVALID), .RREADY(RREADY));

  always #5 clk = ~clk;

  // ---- inline behavioral 4-beat AXI read slave ----
  logic [31:0] mem [0:1023];
  typedef enum {S_IDLE, S_DATA} st_e; st_e st=S_IDLE;
  int base, beat;
  assign ARREADY = (st==S_IDLE);
  assign RVALID  = (st==S_DATA);
  assign RLAST   = (st==S_DATA && beat==3);
  assign RDATA   = (st==S_DATA) ? mem[(base+beat) % 1024] : 32'h0;
  always @(posedge clk) begin
    if (reset) begin st<=S_IDLE; beat<=0; end
    else case (st)
      S_IDLE: if (ARVALID) begin base<=ARADDR>>2; beat<=0; st<=S_DATA; end
      S_DATA: if (RREADY) begin if (beat==3) st<=S_IDLE; else beat<=beat+1; end
    endcase
  end

  int errors=0, checks=0;
  task automatic ck(input logic [127:0] got, exp, input string nm);
    checks++;
    if (got !== exp) begin errors++; $error("%s: got=%h exp=%h", nm, got, exp); end
  endtask

  // emulate cache_controller: present arvalid for one cycle (adapter's c_arready
  // is combinational: 1 only while ADP_IDLE & arvalid, BEFORE the posedge latches
  // it into ADP_AR). So check arready combinationally, then hold arvalid through
  // exactly one posedge so the adapter accepts, then wait for the rvalid pulse.
  task automatic do_refill(input logic [31:0] addr, output logic [127:0] line);
    @(negedge clk); c_arvalid=1; line_addr=addr;
    #1; checks++;                                   // settle: arready should be asserted now
    if (c_arready!==1'b1) begin errors++; $error("arready not asserted on request"); end
    @(negedge clk); c_arvalid=0;                    // held one posedge -> adapter latched (ADP_AR)
    while (c_rvalid!==1'b1) @(negedge clk);         // wait line-ready pulse (ADP_DONE)
    line = rd_line;
    @(negedge clk);
  endtask

  logic [127:0] L; int b;
  initial begin
    c_arvalid=0; line_addr=0;
    for (int i=0;i<1024;i++) mem[i] = 32'hA000_0000 + i; // mem[k]=0xA0000000+k
    repeat(3) @(negedge clk); reset=0; @(negedge clk);

    // line @ word base 0 (addr 0x00): words mem[0..3]
    do_refill(32'h0000_0000, L);
    ck(L, {mem[3],mem[2],mem[1],mem[0]}, "line@0");

    // line @ 0x40 (word base 16): mem[16..19]
    do_refill(32'h0000_0040, L);
    ck(L, {mem[19],mem[18],mem[17],mem[16]}, "line@0x40");

    // unaligned addr 0x4C -> adapter aligns to 0x40 (same line)
    do_refill(32'h0000_004C, L);
    ck(L, {mem[19],mem[18],mem[17],mem[16]}, "unaligned 0x4C -> 0x40");

    // back-to-back second refill proves adapter returns to idle cleanly
    do_refill(32'h0000_0080, L);
    ck(L, {mem[35],mem[34],mem[33],mem[32]}, "line@0x80 (b2b)");

    if (errors==0) $display("tb_icache_axi_adapter: ALL PASS (%0d checks)", checks);
    else           $fatal(1, "tb_icache_axi_adapter: %0d FAIL", errors);
    $finish;
  end

  initial begin #100000; $fatal(1,"TIMEOUT"); end
endmodule
