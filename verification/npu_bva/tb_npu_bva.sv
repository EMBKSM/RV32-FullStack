// tb_npu_bva.sv - 3-point boundary value analysis + cycle-timing verification for npu_top.
//   Boundaries:  K (contraction depth) at {0,1,2} (low) and {63,64} (high, KMAX=64)
//                INT8 operands at extremes {-128,-127, 126,127, 0}
//   Correctness: every C[i][j] compared to a software GEMM golden.
//   Timing:      measure done-latency (cycles start->done); verify it is LINEAR in K
//                (each extra contraction step = exactly 1 cycle => systolic accumulation
//                depth), and that busy/done protocol behaves.
`timescale 1ns/1ps
module tb_npu_bva;
  logic clk=0, rst=1;
  logic sel=0, we=0; logic [12:0] addr=0; logic [31:0] wdata=0; logic [3:0] wstrb=0; logic [31:0] rdata;
  always #5 clk=~clk;

  npu_top dut(.clk(clk), .rst(rst), .sel(sel), .we(we), .addr(addr), .wdata(wdata), .wstrb(wstrb), .rdata(rdata));

  int errors=0, checks=0;

  task automatic bw(input int a, input int d);
    @(negedge clk); addr=a[12:0]; wdata=d; wstrb=4'hF; sel=1; we=1;
    @(negedge clk); sel=0; we=0; wstrb=0;
  endtask
  task automatic br(input int a, output int d);
    @(negedge clk); addr=a[12:0]; sel=1; we=0; #1; d=rdata; @(negedge clk); sel=0;
  endtask
  function automatic int Caddr(input int i, input int j); return 'h1800 + (i*8+j)*4; endfunction

  // load uniform A[i][k]=av, B[k][j]=bv for all i,j,k<K ; set K_DIM
  task automatic load_uniform(input int K, input int av, input int bv);
    bw('h8, K);
    for (int i=0;i<8;i++) for (int k=0;k<K;k++) bw('h800 + i*256 + k*4, av & 'hFF);
    for (int j=0;j<8;j++) for (int k=0;k<K;k++) bw('h1000+ j*256 + k*4, bv & 'hFF);
  endtask

  // start + measure done-latency (cycles), holding the STATUS read so 1 iter = 1 cycle
  task automatic run_measure(output int latency);
    bw(0, 3);                            // CTRL = start | clr_acc
    addr='h4; sel=1; we=0;               // hold STATUS read
    latency=0;
    forever begin
      @(posedge clk); latency++; #1;
      if (rdata[1]) break;               // done
      if (latency>3000) begin $display("  TIMEOUT (no done)"); errors++; break; end
    end
    sel=0;
  endtask

  task automatic check_uniform(input int K, input int av, input int bv, input string nm, output int lat);
    int c, exp;
    load_uniform(K, av, bv);
    run_measure(lat);
    exp = K*av*bv;
    for (int i=0;i<8;i++) for (int j=0;j<8;j++) begin
      br(Caddr(i,j), c); checks++;
      if (c !== exp) begin errors++; if (errors<20) $display("  FAIL %s C[%0d][%0d]=%0d exp=%0d", nm,i,j,c,exp); end
    end
  endtask

  // 3-point K boundaries
  localparam int NK=5;
  int Kv [0:NK-1] = '{0,1,2,63,64};
  int latK [0:NK-1];

  initial begin
    rst=1; repeat(5) @(negedge clk); rst=0; @(negedge clk);
    $display("=== NPU 3-point boundary value analysis + cycle-timing ===");

    for (int t=0;t<NK;t++) begin
      int K=Kv[t]; int la,lb,lc,ld,le,lf;
      // INT8 extreme operand combinations (value boundaries)
      check_uniform(K, 127, 127, $sformatf("K=%0d 127x127",K), la);   // max+ product
      check_uniform(K,-128,-128, $sformatf("K=%0d -128x-128",K), lb); // max product (neg*neg)
      check_uniform(K, 127,-128, $sformatf("K=%0d 127x-128",K), lc);  // max- product
      check_uniform(K,-127, 126, $sformatf("K=%0d -127x126",K), ld);  // just-inside boundary
      check_uniform(K,   0,   0, $sformatf("K=%0d 0x0",K), le);        // zero
      check_uniform(K,   1,  -1, $sformatf("K=%0d 1x-1",K), lf);       // around-zero
      latK[t]=la;
      // protocol: latencies for a fixed K must be identical regardless of operands
      checks++;
      if (!(la==lb && lb==lc && lc==ld && ld==le && le==lf)) begin
        errors++; $display("  FAIL K=%0d latency not data-independent: %0d %0d %0d %0d %0d %0d",K,la,lb,lc,ld,le,lf);
      end
      $display("  K=%0d : C correct, done-latency = %0d cycles (data-independent)", K, la);
    end

    // ---- TIMING: done-latency must be linear in K (slope 1 = one cycle / contraction step) ----
    $display("  --- timing linearity (systolic accumulation depth) ---");
    for (int t=1;t<NK;t++) begin
      int dlat = latK[t]-latK[t-1]; int dK = Kv[t]-Kv[t-1];
      checks++;
      if (dlat != dK) begin errors++; $display("  FAIL slope K %0d->%0d : dlat=%0d dK=%0d",Kv[t-1],Kv[t],dlat,dK); end
      else $display("  PASS slope K %0d->%0d : +%0d cycle (=dK) -> linear", Kv[t-1],Kv[t],dlat);
    end

    // ---- positional (non-uniform) boundary case at K=64: spatial correctness ----
    begin
      int K=64, lat, c, g;
      bw('h8, K);
      for (int i=0;i<8;i++) for (int k=0;k<K;k++) bw('h800 + i*256 + k*4, (((i+k)&1)?127:-128) & 'hFF);
      for (int j=0;j<8;j++) for (int k=0;k<K;k++) bw('h1000+ j*256 + k*4, (((k+j)&1)?127:-128) & 'hFF);
      run_measure(lat);
      for (int i=0;i<8;i++) for (int j=0;j<8;j++) begin
        g=0; for (int k=0;k<K;k++) g += (((i+k)&1)?127:-128) * (((k+j)&1)?127:-128);
        br(Caddr(i,j), c); checks++;
        if (c !== g) begin errors++; if (errors<20) $display("  FAIL mixed C[%0d][%0d]=%0d exp=%0d",i,j,c,g); end
      end
      $display("  positional/mixed K=64 : C correct, latency=%0d", lat);
    end

    $display("=== checks=%0d errors=%0d ===", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS - NPU 3-point BVA correct + done-latency linear in K");
    else           $display("RESULT: FAIL (%0d errors)", errors);
    $finish;
  end
  initial begin #50_000_000; $display("RESULT: TIMEOUT(sim)"); $finish; end
endmodule
