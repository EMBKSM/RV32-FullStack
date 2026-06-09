// tb_dcache_controller.sv - self-checking TB for dcache_controller.vhd (write-back FSM).
// States: D_IDLE->(D_WB if dirty)->D_ALLOC->D_REFILL->D_WAKE->D_IDLE.
// Checks store-hit (data_we+we_dirty), miss-clean alloc path, miss-dirty writeback path,
// axi_addr selection (victim_tag in WB, req_tag otherwise).
`timescale 1ns/1ps
module tb_dcache_controller;
  logic clk=0, reset;
  logic mem_read, mem_write, hit, dirty, axi_done;
  logic [19:0] req_tag, victim_tag;
  logic [7:0]  idx;
  logic stall, wake_up, we_tag, we_dirty, data_we, line_fill, rd_start, wr_start;
  logic [31:0] axi_addr;
  always #5 clk=~clk;

  dcache_controller dut (.clk(clk), .reset(reset), .mem_read(mem_read), .mem_write(mem_write),
    .hit(hit), .dirty(dirty), .req_tag(req_tag), .victim_tag(victim_tag), .idx(idx),
    .stall(stall), .wake_up(wake_up), .we_tag(we_tag), .we_dirty(we_dirty),
    .data_we(data_we), .line_fill(line_fill), .rd_start(rd_start), .wr_start(wr_start),
    .axi_addr(axi_addr), .axi_done(axi_done));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if(!cond) begin errors++;
      $error("%s FAIL: stall=%b rd=%b wr=%b lf=%b we_tag=%b dwe=%b dirtywe=%b wake=%b addr=%h",
             nm,stall,rd_start,wr_start,line_fill,we_tag,data_we,we_dirty,wake_up,axi_addr); end
  endtask
  task automatic idle(); mem_read=0; mem_write=0; hit=0; dirty=0; axi_done=0; endtask

  initial begin
    reset=1; idle(); req_tag=20'hAAAAA; victim_tag=20'h5AAAA; idx=8'h12;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);

    // store hit: data_we + we_dirty in IDLE
    mem_write=1; hit=1; #1; ck(data_we==1 && we_dirty==1 && stall==0, "store hit dirty+data_we");
    idle(); @(negedge clk);

    // ---- miss CLEAN: IDLE -> ALLOC -> REFILL -> WAKE -> IDLE ----
    mem_read=1; hit=0; dirty=0; #1; ck(stall==1 && rd_start==0, "miss clean: stall in IDLE");
    @(posedge clk); @(negedge clk);                 // -> D_ALLOC
    ck(stall==1 && rd_start==1, "ALLOC rd_start"); ck(axi_addr=={req_tag,idx,4'h0}, "ALLOC uses req_tag");
    axi_done=1; @(posedge clk); @(negedge clk); axi_done=0;   // -> D_REFILL
    ck(line_fill==1 && we_tag==1 && stall==1, "REFILL line_fill+we_tag");
    @(posedge clk); @(negedge clk);                 // -> D_WAKE
    ck(wake_up==1, "WAKE pulse");
    @(posedge clk); @(negedge clk);                 // -> D_IDLE
    idle(); #1; ck(stall==0 && wake_up==0, "back to IDLE");

    // ---- miss DIRTY: IDLE -> WB -> ALLOC -> REFILL -> WAKE ----
    mem_write=1; hit=0; dirty=1; #1; ck(stall==1, "miss dirty: stall");
    @(posedge clk); @(negedge clk);                 // -> D_WB
    ck(stall==1 && wr_start==1, "WB wr_start"); ck(axi_addr=={victim_tag,idx,4'h0}, "WB uses victim_tag");
    axi_done=1; @(posedge clk); @(negedge clk); axi_done=0;   // -> D_ALLOC
    ck(rd_start==1, "after WB -> ALLOC rd_start");
    axi_done=1; @(posedge clk); @(negedge clk); axi_done=0;   // -> D_REFILL
    ck(line_fill==1 && we_tag==1, "REFILL after WB");
    @(posedge clk); @(negedge clk);                 // -> D_WAKE
    ck(wake_up==1, "WAKE after dirty path");

    // ---- 3-point boundary value analysis (idx/tag extremes + axi_done timing) ----
    idle(); req_tag=20'hFFFFF; idx=8'hFF; @(negedge clk);
    mem_read=1; hit=0; dirty=0; @(posedge clk); @(negedge clk);    // -> D_ALLOC
    ck(rd_start==1 && axi_addr=={req_tag,idx,4'h0}, "BVA ALLOC addr at extremes");
    axi_done=0; @(posedge clk); @(negedge clk);                     // before: stay D_ALLOC
    ck(rd_start==1 && stall==1, "BVA ALLOC wait (axi_done=0)");
    axi_done=1; @(posedge clk); @(negedge clk); axi_done=0;         // at boundary -> D_REFILL
    ck(line_fill==1 && we_tag==1, "BVA REFILL after done");
    @(posedge clk); @(negedge clk);                                  // -> D_WAKE
    ck(wake_up==1, "BVA wake");
    @(posedge clk); @(negedge clk); idle();                          // -> D_IDLE

    // ---- timing-issue tests (axi_done single-step, wake pulse, async reset) ----
    idle(); req_tag=20'h2; victim_tag=20'h1; idx=8'h10; @(negedge clk);
    mem_read=1; hit=0; dirty=0; @(posedge clk); @(negedge clk);    // -> D_ALLOC
    ck(rd_start==1, "TIMING ALLOC");
    axi_done=1; @(posedge clk); @(negedge clk); axi_done=0;        // single done -> D_REFILL only
    ck(line_fill==1 && we_tag==1, "TIMING done advances exactly one state");
    @(posedge clk); @(negedge clk);                                 // -> D_WAKE
    ck(wake_up==1'b1, "TIMING wake high");
    @(posedge clk); @(negedge clk);                                 // -> D_IDLE
    ck(wake_up==1'b0, "TIMING wake is 1-cycle pulse");
    idle();
    // async reset mid-FSM (in D_WB) returns to IDLE
    mem_write=1; hit=0; dirty=1; @(posedge clk); @(negedge clk);   // -> D_WB
    reset=1; idle(); #2; ck(stall==1'b0 && wr_start==1'b0 && wake_up==1'b0, "TIMING async reset -> IDLE");
    reset=0;

    $display("[tb_dcache_controller] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
