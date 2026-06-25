// tb_npu_regress.sv - extended boundary axes + randomized regression for npu_top.
//  axis 1: 3-point K {0,1,2,63,64} x INT8 extremes (127,-128)
//  axis 2: spatial single-element (one PE active) at corners {0,7}x{0,7} + middle
//  axis 3: accumulate mode (clr_acc=0) = K-tiling, C accumulates onto prior result
//  axis 4: randomized regression - N back-to-back GEMMs, random K in [1,64] and
//          random INT8 A/B, every C[i][j] compared to an in-TB software GEMM golden.
//  Run:  xsim tb_npu_regress -runall  (override count: -testplusarg NRAND=200)
`timescale 1ns/1ps
module tb_npu_regress;
  logic clk=0, rst=1;
  logic sel=0, we=0; logic [12:0] addr=0; logic [31:0] wdata=0; logic [3:0] wstrb=0; logic [31:0] rdata;
  always #5 clk=~clk;
  npu_top dut(.clk(clk),.rst(rst),.sel(sel),.we(we),.addr(addr),.wdata(wdata),.wstrb(wstrb),.rdata(rdata));

  int errors=0, checks=0;
  int A_g[0:7][0:63];
  int B_g[0:63][0:7];

  task automatic bw(input int a, input int d);
    @(negedge clk); addr=a[12:0]; wdata=d; wstrb=4'hF; sel=1; we=1;
    @(negedge clk); sel=0; we=0; wstrb=0;
  endtask
  task automatic br(input int a, output int d);
    @(negedge clk); addr=a[12:0]; sel=1; we=0; #1; d=rdata; @(negedge clk); sel=0;
  endtask
  function automatic int Caddr(input int i,input int j); return 'h1800+(i*8+j)*4; endfunction
  function automatic int golden(input int i,input int j,input int K);
    int g=0; for(int k=0;k<K;k++) g+=A_g[i][k]*B_g[k][j]; return g;
  endfunction
  // requantize golden: clip((acc*mult + round) >>> shift, -128, 127)
  function automatic int rq(input int acc, input int mult, input int sh);
    longint p = longint'(acc) * longint'(mult);
    if (sh>0) p += (longint'(1) << (sh-1));   // round half up
    p = p >>> sh;
    if (p > 127) return 127; else if (p < -128) return -128; else return int'(p);
  endfunction
  task automatic load_AB(input int K);
    bw('h8,K);
    for(int i=0;i<8;i++) for(int k=0;k<K;k++) bw('h800 +i*256+k*4, A_g[i][k]&'hFF);
    for(int j=0;j<8;j++) for(int k=0;k<K;k++) bw('h1000+j*256+k*4, B_g[k][j]&'hFF);
  endtask
  task automatic start_and_wait(input bit clr);
    int g; bw(0, clr?3:1);
    addr='h4; sel=1; we=0; g=0;
    forever begin @(posedge clk); g++; #1; if(rdata[1]) break;
      if(g>4000) begin errors++; $display("  TIMEOUT(no done)"); break; end end
    sel=0;
  endtask
  task automatic check_golden(input int K, input string nm);
    int c,gg;
    for(int i=0;i<8;i++) for(int j=0;j<8;j++) begin
      gg=golden(i,j,K); br(Caddr(i,j),c); checks++;
      if(c!==gg) begin errors++; if(errors<25) $display("  FAIL %s C[%0d][%0d]=%0d exp=%0d",nm,i,j,c,gg); end
    end
  endtask
  task automatic set_cfg(input int mult, input int sh, input bit en);
    bw('hC, ((mult & 'hFFFF)<<16) | ((sh & 'h3F)<<8) | (en?1:0));
  endtask
  task automatic check_requant(input int K, input int mult, input int sh, input string nm);
    int c,g;
    for(int i=0;i<8;i++) for(int j=0;j<8;j++) begin
      g=rq(golden(i,j,K),mult,sh); br(Caddr(i,j),c); checks++;
      if(c!==g) begin errors++; if(errors<25) $display("  FAIL %s C[%0d][%0d]=%0d exp=%0d",nm,i,j,c,g); end
    end
  endtask
  task automatic fill_uniform(input int K,input int av,input int bv);
    for(int i=0;i<8;i++) for(int k=0;k<K;k++) A_g[i][k]=av;
    for(int k=0;k<K;k++) for(int j=0;j<8;j++) B_g[k][j]=bv;
  endtask
  task automatic fill_random(input int K);
    for(int i=0;i<8;i++) for(int k=0;k<K;k++) A_g[i][k]=($urandom%256)-128;
    for(int k=0;k<K;k++) for(int j=0;j<8;j++) B_g[k][j]=($urandom%256)-128;
  endtask

  int NRAND=100;
  int Ks[5]='{0,1,2,63,64};
  int Rr[5]='{0,7,0,7,3};
  int Cc[5]='{0,7,7,0,5};

  initial begin
    if($value$plusargs("NRAND=%d",NRAND));
    rst=1; repeat(5)@(negedge clk); rst=0; @(negedge clk);
    $display("=== NPU extended boundary axes + random regression ===");

    // ---- axis 1: 3-point K x INT8 extremes ----
    for(int t=0;t<5;t++) begin
      int K=Ks[t];
      fill_uniform(K,127,127);   load_AB(K); start_and_wait(1); check_golden(K,$sformatf("K=%0d 127x127",K));
      fill_uniform(K,-128,-128); load_AB(K); start_and_wait(1); check_golden(K,$sformatf("K=%0d -128x-128",K));
      fill_uniform(K,127,-128);  load_AB(K); start_and_wait(1); check_golden(K,$sformatf("K=%0d 127x-128",K));
    end
    $display("  [axis1] 3-point K x INT8 extremes : done");

    // ---- axis 2: spatial single-element (one PE path) at corners + middle ----
    for(int t=0;t<5;t++) begin
      int K=8, R=Rr[t], C=Cc[t];
      for(int i=0;i<8;i++) for(int k=0;k<K;k++) A_g[i][k]=((i==R && k==0)?1:0);
      for(int k=0;k<K;k++) for(int j=0;j<8;j++) B_g[k][j]=((k==0 && j==C)?1:0);
      load_AB(K); start_and_wait(1); check_golden(K,$sformatf("spatial PE[%0d][%0d]",R,C));
    end
    $display("  [axis2] spatial single-element (corners+middle) : done");

    // ---- axis 3: accumulate mode (clr_acc=0) - K-tiling onto prior C ----
    begin
      int C1[0:7][0:7], c, exp;
      fill_uniform(4,2,3); load_AB(4); start_and_wait(1);          // C = 4*2*3 = 24
      for(int i=0;i<8;i++) for(int j=0;j<8;j++) C1[i][j]=golden(i,j,4);
      check_golden(4,"accum step1 (=24)");
      fill_uniform(4,5,1); load_AB(4); start_and_wait(0);          // clr_acc=0 -> C += 20 -> 44
      for(int i=0;i<8;i++) for(int j=0;j<8;j++) begin
        exp=C1[i][j]+golden(i,j,4); br(Caddr(i,j),c); checks++;
        if(c!==exp) begin errors++; if(errors<25) $display("  FAIL accum C[%0d][%0d]=%0d exp=%0d",i,j,c,exp); end
      end
      $display("  [axis3] accumulate mode (clr_acc=0, K-tiling) : done");
    end

    // ---- axis 4: randomized regression (random K + random INT8, back-to-back) ----
    for(int n=0;n<NRAND;n++) begin
      int K = 1 + ($urandom % 64);
      fill_random(K); load_AB(K); start_and_wait(1);
      check_golden(K,$sformatf("rand#%0d K=%0d",n,K));
    end
    $display("  [axis4] random regression : %0d back-to-back GEMMs (random K,A,B) : done", NRAND);

    // ---- axis 5: requantize mode (INT32 -> mult/shift/clip -> INT8) ----
    begin
      int K=8;
      fill_uniform(K,4, 4); load_AB(K); start_and_wait(1);              // C = 128
      set_cfg(1,0,1); check_requant(K,1,0,"rq C=128 m1 s0 (clip 127)");
      set_cfg(1,1,1); check_requant(K,1,1,"rq C=128 m1 s1 (=64)");
      set_cfg(1,4,1); check_requant(K,1,4,"rq C=128 m1 s4 (=8)");
      fill_uniform(K,4,-4); load_AB(K); start_and_wait(1);              // C = -128
      set_cfg(1,0,1); check_requant(K,1,0,"rq C=-128 m1 s0 (clip -128)");
      set_cfg(1,1,1); check_requant(K,1,1,"rq C=-128 m1 s1 (=-64)");
      fill_uniform(K,4, 2); load_AB(K); start_and_wait(1);              // C = 64
      set_cfg(1,0,1); check_requant(K,1,0,"rq C=64 m1 s0 (=64, in-range)");
      set_cfg(2,2,1); check_requant(K,2,2,"rq C=64 m2 s2 (=32)");
      set_cfg(0,0,0); check_golden(K,"requant OFF -> raw INT32 restored");   // no-regression
      for(int n=0;n<30;n++) begin                                       // random scale x random GEMM
        int Kr=1+($urandom%64), m=1+($urandom%512), s=$urandom%16;
        fill_random(Kr); load_AB(Kr); start_and_wait(1);
        set_cfg(m,s,1); check_requant(Kr,m,s,$sformatf("rq rand#%0d K=%0d m=%0d s=%0d",n,Kr,m,s));
      end
      set_cfg(0,0,0);
      $display("  [axis5] requantize (scale/shift/clip 3-point + 30 random + OFF->raw) : done");
    end

    $display("=== checks=%0d errors=%0d ===", checks, errors);
    if(errors==0) $display("RESULT: ALL PASS - NPU extended BVA + %0d random GEMMs match golden", NRAND);
    else          $display("RESULT: FAIL (%0d errors)", errors);
    $finish;
  end
  initial begin #300_000_000; $display("RESULT: TIMEOUT(sim)"); $finish; end
endmodule
