// tb_dcache_controller.sv - self-checking TB for dcache_controller.vhd (write-back FSM).
// States: D_IDLE->(D_WB if dirty)->D_ALLOC->D_REFILL->D_SWRITE->D_WAKE->D_IDLE.
//   D_SWRITE (store write-allocate): after a refill, while still stalled, write the
//   PENDING STORE word into the just-filled line (data_we+we_dirty) iff mem_write=1.
//   For a load miss, D_SWRITE is a pass-through stall cycle (no data write).
// Checks: store-hit, load-miss-clean path, store-miss-dirty path (incl. D_SWRITE
//   write-allocate), axi_addr selection (victim_tag in WB, req_tag otherwise),
//   3-point BVA, and timing (axi_done single-step, wake 1-cycle pulse, async reset).
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
  task automatic step(); @(posedge clk); @(negedge clk); endtask   // advance exactly one state

  initial begin
    reset=1; idle(); req_tag=20'hAAAAA; victim_tag=20'h5AAAA; idx=8'h12;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);

    // store hit: data_we + we_dirty in IDLE, no stall
    mem_write=1; hit=1; #1; ck(data_we==1 && we_dirty==1 && stall==0, "store hit dirty+data_we");
    idle(); @(negedge clk);

    // ---- LOAD miss CLEAN: IDLE->ALLOC->REFILL->SWRITE->WAKE->IDLE ----
    mem_read=1; hit=0; dirty=0; #1; ck(stall==1 && rd_start==0, "load miss: stall in IDLE");
    step();                                                   // -> D_ALLOC
    ck(stall==1 && rd_start==1, "ALLOC rd_start"); ck(axi_addr=={req_tag,idx,4'h0}, "ALLOC uses req_tag");
    axi_done=1; step(); axi_done=0;                           // -> D_REFILL
    ck(line_fill==1 && we_tag==1 && stall==1, "REFILL line_fill+we_tag");
    step();                                                   // -> D_SWRITE
    ck(stall==1 && data_we==0 && we_dirty==0, "SWRITE(load): stall, NO store write");
    step();                                                   // -> D_WAKE
    ck(wake_up==1, "WAKE pulse");
    step();                                                   // -> D_IDLE
    idle(); #1; ck(stall==0 && wake_up==0, "back to IDLE");

    // ---- STORE miss DIRTY: IDLE->WB->ALLOC->REFILL->SWRITE(write-allocate)->WAKE ----
    // mem_write held high for the whole miss (the store is pending until wake).
    mem_write=1; hit=0; dirty=1; #1; ck(stall==1, "store miss dirty: stall");
    step();                                                   // -> D_WB
    ck(stall==1 && wr_start==1, "WB wr_start"); ck(axi_addr=={victim_tag,idx,4'h0}, "WB uses victim_tag");
    axi_done=1; step(); axi_done=0;                           // -> D_ALLOC
    ck(rd_start==1, "after WB -> ALLOC rd_start"); ck(axi_addr=={req_tag,idx,4'h0}, "ALLOC uses req_tag (post-WB)");
    axi_done=1; step(); axi_done=0;                           // -> D_REFILL
    ck(line_fill==1 && we_tag==1, "REFILL after WB");
    step();                                                   // -> D_SWRITE  *** key new coverage ***
    ck(stall==1 && data_we==1 && we_dirty==1, "SWRITE(store): write-allocate data_we+we_dirty");
    ck(line_fill==0, "SWRITE: line already filled (no second line_fill)");
    step();                                                   // -> D_WAKE
    ck(wake_up==1, "WAKE after dirty store path");
    step(); idle();                                           // -> D_IDLE

    // ---- 3-point boundary value analysis (idx/tag extremes + axi_done timing) ----
    idle(); req_tag=20'hFFFFF; idx=8'hFF; @(negedge clk);
    mem_read=1; hit=0; dirty=0; step();                       // -> D_ALLOC
    ck(rd_start==1 && axi_addr=={req_tag,idx,4'h0}, "BVA ALLOC addr at extremes");
    axi_done=0; step();                                       // before: stay D_ALLOC
    ck(rd_start==1 && stall==1, "BVA ALLOC wait (axi_done=0)");
    axi_done=1; step(); axi_done=0;                           // at boundary -> D_REFILL
    ck(line_fill==1 && we_tag==1, "BVA REFILL after done");
    step();                                                   // -> D_SWRITE
    ck(stall==1 && data_we==0, "BVA SWRITE(load) no write");
    step();                                                   // -> D_WAKE
    ck(wake_up==1, "BVA wake");
    step(); idle();                                           // -> D_IDLE

    // ---- timing-issue tests (axi_done single-step, wake pulse, async reset) ----
    idle(); req_tag=20'h2; victim_tag=20'h1; idx=8'h10; @(negedge clk);
    mem_read=1; hit=0; dirty=0; step();                       // -> D_ALLOC
    ck(rd_start==1, "TIMING ALLOC");
    axi_done=1; step(); axi_done=0;                           // single done -> D_REFILL only
    ck(line_fill==1 && we_tag==1, "TIMING done advances exactly one state");
    step();                                                   // -> D_SWRITE
    ck(stall==1, "TIMING SWRITE stalled");
    step();                                                   // -> D_WAKE
    ck(wake_up==1'b1, "TIMING wake high");
    step();                                                   // -> D_IDLE
    ck(wake_up==1'b0, "TIMING wake is 1-cycle pulse");
    idle();
    // async reset mid-FSM (in D_WB) returns to IDLE
    mem_write=1; hit=0; dirty=1; step();                      // -> D_WB
    reset=1; idle(); #2; ck(stall==1'b0 && wr_start==1'b0 && wake_up==1'b0, "TIMING async reset -> IDLE");
    reset=0;

    $display("[tb_dcache_controller] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
