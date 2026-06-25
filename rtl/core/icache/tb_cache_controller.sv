// tb_cache_controller.sv - self-checking TB for cache_controller.vhd (I-cache refill FSM).
// States: S_IDLE -> S_SEND_AR -> S_WAIT_R -> S_UPDATE_CACHE -> S_WAKE_UP -> S_IDLE.
// Checks: stall through miss, arvalid in SEND_AR, rready+we=rvalid in WAIT_R,
// wake_up in WAKE_UP; B1 invalidate (fence_i/ext_inv -> inv,stall,iflush=fence_i).
`timescale 1ns/1ps
module tb_cache_controller;
  logic clk=0, reset;
  logic miss, fence_i, ext_inv, arready, rvalid;
  logic stall, wake_up, we, inv, iflush, arvalid, rready;
  always #5 clk=~clk;

  cache_controller dut (.clk(clk), .reset(reset), .miss(miss), .fence_i(fence_i),
    .ext_inv(ext_inv), .stall(stall), .wake_up(wake_up), .we(we), .inv(inv),
    .iflush(iflush), .arready(arready), .rvalid(rvalid), .arvalid(arvalid), .rready(rready));

  int errors=0, checks=0;
  task automatic ck(input logic cond, input string nm);
    checks++; if (!cond) begin errors++;
      $error("%s FAIL: stall=%b arvalid=%b rready=%b we=%b wake=%b inv=%b iflush=%b",
             nm,stall,arvalid,rready,we,wake_up,inv,iflush); end
  endtask

  initial begin
    reset=1; miss=0; fence_i=0; ext_inv=0; arready=0; rvalid=0;
    @(negedge clk); @(negedge clk); reset=0; @(negedge clk);
    // idle, no miss
    #1; ck(stall==0 && arvalid==0 && wake_up==0, "IDLE quiet");

    // ----- miss refill walk -----
    miss=1; #1; ck(stall==1 && arvalid==0, "IDLE miss -> stall");
    @(posedge clk); @(negedge clk); miss=0;          // now S_SEND_AR
    #1; ck(stall==1 && arvalid==1, "SEND_AR arvalid");
    arready=1; @(posedge clk); @(negedge clk); arready=0;  // -> S_WAIT_R
    #1; ck(stall==1 && rready==1 && we==1'b0, "WAIT_R rready, we=0 before rvalid");
    rvalid=1; #1; ck(rready==1 && we==1'b1, "WAIT_R we=rvalid (BUG-001 fix)");
    @(posedge clk); @(negedge clk); rvalid=0;        // -> S_UPDATE_CACHE
    #1; ck(stall==1 && we==1'b0, "UPDATE_CACHE settle");
    @(posedge clk); @(negedge clk);                  // -> S_WAKE_UP
    #1; ck(wake_up==1, "WAKE_UP pulse");
    @(posedge clk); @(negedge clk);                  // -> S_IDLE
    #1; ck(stall==0 && wake_up==0, "back to IDLE");

    // ----- FENCE.I invalidate -----
    fence_i=1; #1; ck(inv==1 && stall==1 && iflush==1, "fence_i: inv+stall+iflush");
    @(posedge clk); @(negedge clk); fence_i=0;
    #1; ck(inv==0 && iflush==0, "fence_i 1-cycle pulse");

    // ----- host ext_inv (no iflush) -----
    ext_inv=1; #1; ck(inv==1 && stall==1 && iflush==1'b0, "ext_inv: inv+stall, no iflush");
    @(posedge clk); @(negedge clk); ext_inv=0;

    // ---- 3-point boundary value analysis (handshake timing: early/at/late) ----
    // Boundary = the cycle a handshake (arready/rvalid) asserts. Hold low (before),
    // assert (at), and confirm capture happens exactly on the boundary beat.
    miss=1; #1; @(posedge clk); @(negedge clk); miss=0;            // -> S_SEND_AR
    ck(arvalid==1 && stall==1, "BVA SEND_AR");
    arready=0; @(posedge clk); @(negedge clk);                     // before: stay SEND_AR
    ck(arvalid==1 && stall==1, "BVA SEND_AR wait (arready=0)");
    arready=1; @(posedge clk); @(negedge clk); arready=0;          // at: -> S_WAIT_R
    ck(rready==1 && we==1'b0, "BVA WAIT_R before rvalid: we=0");
    rvalid=0; @(posedge clk); @(negedge clk);                      // before: stay WAIT_R
    ck(rready==1 && we==1'b0, "BVA WAIT_R wait: we=0");
    rvalid=1; #1; ck(we==1'b1, "BVA WAIT_R AT rvalid beat: we=1");  // at boundary
    @(posedge clk); @(negedge clk); rvalid=0;                      // -> S_UPDATE_CACHE
    @(posedge clk); @(negedge clk);                                 // -> S_WAKE_UP
    ck(wake_up==1, "BVA wake_up");
    @(posedge clk); @(negedge clk);                                 // -> S_IDLE

    // ---- timing-issue tests (capture-on-RVALID, long latency, pulse width, reset) ----
    // long AR latency: arvalid/stall held, NO premature we
    miss=1; #1; @(posedge clk); @(negedge clk); miss=0;            // -> S_SEND_AR
    repeat (3) begin arready=0; @(posedge clk); @(negedge clk);
      ck(arvalid==1 && we==1'b0, "TIMING AR wait: no we"); end
    arready=1; @(posedge clk); @(negedge clk); arready=0;          // -> S_WAIT_R
    // long R latency: we stays 0 until the exact RVALID beat (BUG-001 capture timing)
    repeat (3) begin rvalid=0; @(posedge clk); @(negedge clk);
      ck(we==1'b0, "TIMING R wait: no we"); end
    rvalid=1; #1; ck(we==1'b1, "TIMING we asserts exactly on RVALID beat");
    @(posedge clk); @(negedge clk); rvalid=0; #1; ck(we==1'b0, "TIMING we drops after capture"); // S_UPDATE
    @(posedge clk); @(negedge clk);                                 // -> S_WAKE_UP
    ck(wake_up==1'b1, "TIMING wake_up high");
    @(posedge clk); @(negedge clk);                                 // -> S_IDLE
    ck(wake_up==1'b0, "TIMING wake_up is a 1-cycle pulse");
    // async reset mid-FSM -> S_IDLE quiet
    miss=1; #1; @(posedge clk); @(negedge clk);                     // -> S_SEND_AR (arvalid=1)
    reset=1; miss=0; #2; ck(arvalid==1'b0 && stall==1'b0 && wake_up==1'b0, "TIMING async reset -> IDLE");
    reset=0;

    $display("[tb_cache_controller] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
