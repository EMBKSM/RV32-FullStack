// tb_icache_unit.sv - integration TB for the rebuilt read-only I-cache.
// icache_unit (addr_aligner + tag_array + comparator + cache_controller +
// icache_data_array + icache_axi_adapter) wired to the behavioral AXI memory.
// Verifies: cold-miss refill returns the correct word; subsequent words in the
// same 16-byte line HIT (0 stall cycles); a different line that maps to a free
// index stays cached; a conflicting tag at the same index evicts and re-misses.
`timescale 1ns/1ps
module tb_icache_unit;
  logic clk=0, reset=1;
  logic [31:0] addr, rword;
  logic        stall;
  logic        fence_i=0;
  // AXI between cache and memory
  logic [31:0] ARADDR, RDATA, AWADDR, WDATA;
  logic        ARVALID, ARREADY, RLAST, RVALID, RREADY;
  logic        AWVALID, AWREADY, WLAST, WVALID, WREADY, BVALID, BREADY;
  logic [3:0]  WSTRB;
  // preload
  logic        prog_we; logic [31:0] prog_addr, prog_data;

  icache_unit dut(.clk(clk), .reset(reset),
    .addr(addr), .rword(rword), .stall(stall),
    .fence_i(fence_i), .ext_inv(1'b0), .iflush(),
    .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
    .RDATA(RDATA), .RLAST(RLAST), .RVALID(RVALID), .RREADY(RREADY),
    .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
    .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST), .WVALID(WVALID), .WREADY(WREADY),
    .BVALID(BVALID), .BREADY(BREADY));

  axi_slave_mem #(.WORDS(4096)) mem(.clk(clk), .reset(reset),
    .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
    .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
    .RDATA(RDATA), .RLAST(RLAST), .RVALID(RVALID), .RREADY(RREADY),
    .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
    .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST), .WVALID(WVALID), .WREADY(WREADY),
    .BVALID(BVALID), .BREADY(BREADY));

  always #5 clk = ~clk;

  // golden image: word k = 0xC0DE0000 + k
  function automatic logic [31:0] gold(input int wk); return 32'hC0DE0000 + wk; endfunction

  int errors=0, checks=0;
  task automatic preload(input int wk);
    @(negedge clk); prog_we=1; prog_addr=wk*4; prog_data=gold(wk);
  endtask

  // fetch: drive addr, count stall cycles, sample word once not stalled
  task automatic fetch(input logic [31:0] ba, output logic [31:0] instr, output int scyc);
    @(negedge clk); addr=ba; #1; scyc=0;
    while (stall===1'b1) begin scyc++; @(negedge clk); #1; end
    instr=rword;
  endtask

  task automatic ck_word(input logic [31:0] got, input int wk, input string nm);
    checks++;
    if (got !== gold(wk)) begin errors++; $error("%s: got=%h exp=%h", nm, got, gold(wk)); end
  endtask
  task automatic ck_hit(input int scyc, input bit want_hit, input string nm);
    checks++;
    if (want_hit && scyc!=0)      begin errors++; $error("%s: expected HIT but stalled %0d", nm, scyc); end
    if (!want_hit && scyc==0)     begin errors++; $error("%s: expected MISS but 0 stall", nm); end
  endtask

  logic [31:0] w; int sc;
  initial begin
    prog_we=0; addr=0;
    // preload line0 (w0..3), line1 (w4..7), and line @0x1000 (w 0x400..0x403)
    for (int k=0;k<8;k++)   preload(k);
    for (int k=0;k<4;k++)   preload('h400 + k);
    @(negedge clk); prog_we=0;
    repeat(3) @(negedge clk); reset=0; @(negedge clk);

    fetch(32'h0000_0000, w, sc); ck_word(w,0,"fetch 0x00");      ck_hit(sc,0,"0x00 cold miss");
    fetch(32'h0000_0004, w, sc); ck_word(w,1,"fetch 0x04");      ck_hit(sc,1,"0x04 same-line HIT");
    fetch(32'h0000_0008, w, sc); ck_word(w,2,"fetch 0x08");      ck_hit(sc,1,"0x08 HIT");
    fetch(32'h0000_000C, w, sc); ck_word(w,3,"fetch 0x0C");      ck_hit(sc,1,"0x0C HIT");
    fetch(32'h0000_0010, w, sc); ck_word(w,4,"fetch 0x10");      ck_hit(sc,0,"0x10 new-line miss");
    // line0 (idx0) and line1 (idx1) coexist -> 0x00 still cached
    fetch(32'h0000_0000, w, sc); ck_word(w,0,"refetch 0x00");    ck_hit(sc,1,"0x00 still cached HIT");
    // 0x1000 maps to idx0 (same index, different tag) -> conflict miss + evict
    fetch(32'h0000_1000, w, sc); ck_word(w,'h400,"fetch 0x1000");ck_hit(sc,0,"0x1000 conflict miss");
    // 0x00 was evicted by the 0x1000 fill -> miss again
    fetch(32'h0000_0000, w, sc); ck_word(w,0,"refetch 0x00 #2"); ck_hit(sc,0,"0x00 evicted -> miss");

    // ---- FENCE.I invalidate: a cached line must MISS again after a fence pulse ----
    fetch(32'h0000_0000, w, sc); ck_hit(sc,1,"0x00 cached (pre-fence HIT)"); // just refilled above
    @(negedge clk); fence_i=1; @(negedge clk); fence_i=0;                    // 1-cycle invalidate-all
    fetch(32'h0000_0000, w, sc); ck_word(w,0,"post-fence word ok");
    ck_hit(sc,0,"0x00 MISS after FENCE.I invalidate");

    if (errors==0) $display("tb_icache_unit: ALL PASS (%0d checks)", checks);
    else           $fatal(1, "tb_icache_unit: %0d FAIL", errors);
    $finish;
  end

  initial begin #2000000; $fatal(1,"TIMEOUT"); end
endmodule
