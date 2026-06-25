// tb_axi_master.sv - self-checking TB for axi_master.vhd (AXI4 32-bit burst master).
// Read:  A_IDLE->A_AR->A_R(4 beat,RLAST)->A_DONE, rd_line assembled.
// Write: A_IDLE->A_AW->A_W(4 beat,WLAST)->A_B->A_DONE, WDATA streams wb_line words.
// Constant AXI attrs: ARLEN/AWLEN=3, xSIZE=010, xBURST=01, WSTRB=1111.
`timescale 1ns/1ps
module tb_axi_master;
  logic clk=0, reset;
  logic rd_start, wr_start;
  logic [31:0]  addr;
  logic [127:0] wb_line, rd_line;
  logic done;
  logic [31:0] ARADDR, AWADDR, WDATA;
  logic [7:0]  ARLEN, AWLEN;
  logic [2:0]  ARSIZE, AWSIZE;
  logic [1:0]  ARBURST, AWBURST;
  logic [3:0]  WSTRB;
  logic ARVALID, RREADY, AWVALID, WVALID, WLAST, BREADY;
  logic ARREADY, RVALID, RLAST, AWREADY, WREADY, BVALID;
  logic [31:0] RDATA;
  always #5 clk=~clk;

  axi_master dut (.clk(clk), .reset(reset), .rd_start(rd_start), .wr_start(wr_start),
    .addr(addr), .wb_line(wb_line), .rd_line(rd_line), .done(done),
    .ARADDR(ARADDR), .ARLEN(ARLEN), .ARSIZE(ARSIZE), .ARBURST(ARBURST),
    .ARVALID(ARVALID), .ARREADY(ARREADY), .RDATA(RDATA), .RLAST(RLAST),
    .RVALID(RVALID), .RREADY(RREADY),
    .AWADDR(AWADDR), .AWLEN(AWLEN), .AWSIZE(AWSIZE), .AWBURST(AWBURST),
    .AWVALID(AWVALID), .AWREADY(AWREADY), .WDATA(WDATA), .WSTRB(WSTRB),
    .WLAST(WLAST), .WVALID(WVALID), .WREADY(WREADY), .BVALID(BVALID), .BREADY(BREADY));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if(!cond) begin errors++; $error("%s FAIL",nm); end
  endtask

  logic [31:0] rwords [0:3] = '{32'h11111111,32'h22222222,32'h33333333,32'h44444444};

  initial begin
    reset=1; rd_start=0; wr_start=0; addr=32'h1000_0000;
    wb_line=128'hAAAA0003_AAAA0002_AAAA0001_AAAA0000;
    ARREADY=0; RVALID=0; RLAST=0; RDATA=0; AWREADY=0; WREADY=0; BVALID=0;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);

    // constant attributes
    #1; ck(ARLEN==8'd3 && ARSIZE==3'b010 && ARBURST==2'b01, "AR attrs");
    ck(AWLEN==8'd3 && AWSIZE==3'b010 && AWBURST==2'b01 && WSTRB==4'hF, "AW/W attrs");
    ck(ARADDR==addr && AWADDR==addr, "addr passthrough");

    // ---------------- READ burst ----------------
    rd_start=1; @(posedge clk); @(negedge clk); rd_start=0;     // -> A_AR
    ck(ARVALID==1, "ARVALID in A_AR");
    ARREADY=1; @(posedge clk); @(negedge clk); ARREADY=0;       // -> A_R beat0
    for (int beat=0; beat<4; beat++) begin
      ck(RREADY==1, "RREADY in A_R");
      RVALID=1; RDATA=rwords[beat]; RLAST=(beat==3);
      @(posedge clk); @(negedge clk);
      RVALID=0; RLAST=0;
    end
    // now A_DONE
    ck(done==1, "read done pulse");
    ck(rd_line==128'h44444444_33333333_22222222_11111111, "rd_line assembled");
    @(posedge clk); @(negedge clk);                              // -> A_IDLE
    ck(done==0, "done deasserts");

    // ---------------- WRITE burst ----------------
    wr_start=1; @(posedge clk); @(negedge clk); wr_start=0;     // -> A_AW
    ck(AWVALID==1, "AWVALID in A_AW");
    AWREADY=1; @(posedge clk); @(negedge clk); AWREADY=0;       // -> A_W beat0
    for (int beat=0; beat<4; beat++) begin
      ck(WVALID==1, "WVALID in A_W");
      ck(WDATA==wb_line[32*beat +: 32], "WDATA beat");
      ck(WLAST==(beat==3), "WLAST on last beat");
      WREADY=1; @(posedge clk); @(negedge clk); WREADY=0;
    end
    // -> A_B
    ck(BREADY==1, "BREADY in A_B");
    BVALID=1; @(posedge clk); @(negedge clk); BVALID=0;         // -> A_DONE
    ck(done==1, "write done pulse");
    @(posedge clk); @(negedge clk);

    // ---- 3-point boundary value analysis (burst beat-count boundary: first/last) ----
    ck(ARLEN==8'd3 && AWLEN==8'd3, "BVA burst-len=3 (4-beat)");
    rd_start=1; @(posedge clk); @(negedge clk); rd_start=0;          // -> A_AR
    ARREADY=1; @(posedge clk); @(negedge clk); ARREADY=0;            // -> A_R beat0
    RVALID=1; RDATA=32'hB0B0B0B0; RLAST=1'b0; @(posedge clk); @(negedge clk);  // beat0 (first)
    ck(done==1'b0, "BVA mid-burst not done (beat0)");
    RDATA=32'hB1B1B1B1; @(posedge clk); @(negedge clk);              // beat1
    RDATA=32'hB2B2B2B2; @(posedge clk); @(negedge clk);              // beat2
    RDATA=32'hB3B3B3B3; RLAST=1'b1; @(posedge clk); @(negedge clk);  // beat3 (last boundary)
    RVALID=0; RLAST=0;
    ck(done==1'b1, "BVA last-beat (RLAST) -> done");
    ck(rd_line==128'hB3B3B3B3_B2B2B2B2_B1B1B1B1_B0B0B0B0, "BVA all 4 beats assembled");
    @(posedge clk); @(negedge clk);

    // ---- timing-issue tests (ready stretch, beat-advances-only-on-handshake, reset) ----
    rd_start=1; @(posedge clk); @(negedge clk); rd_start=0;        // -> A_AR
    ARREADY=0; repeat (2) @(posedge clk); #1; ck(ARVALID==1, "TIMING AR stretched (ARREADY low)"); @(negedge clk);
    ARREADY=1; @(posedge clk); @(negedge clk); ARREADY=0;          // -> A_R beat0
    // RVALID gap: RREADY held, no beat advance, no done
    RVALID=0; repeat (2) @(posedge clk); #1; ck(RREADY==1 && done==1'b0, "TIMING R gap holds, beat frozen"); @(negedge clk);
    // 4 beats advance only on RVALID handshake
    RVALID=1; RDATA=32'h000000C0; RLAST=1'b0; @(posedge clk); @(negedge clk);
              RDATA=32'h000000C1;             @(posedge clk); @(negedge clk);
              RDATA=32'h000000C2;             @(posedge clk); @(negedge clk);
              RDATA=32'h000000C3; RLAST=1'b1; @(posedge clk); @(negedge clk); RVALID=0; RLAST=0;
    ck(done==1'b1, "TIMING read done");
    ck(rd_line==128'h000000C3_000000C2_000000C1_000000C0, "TIMING beats captured on handshake only");
    @(posedge clk); @(negedge clk); ck(done==1'b0, "TIMING done is 1-cycle pulse");
    // async reset mid-write burst -> A_IDLE
    wr_start=1; @(posedge clk); @(negedge clk); wr_start=0;        // -> A_AW
    reset=1; #2; ck(AWVALID==1'b0 && done==1'b0, "TIMING async reset mid-burst -> IDLE"); reset=0;
    @(posedge clk); @(negedge clk);

    $display("[tb_axi_master] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
