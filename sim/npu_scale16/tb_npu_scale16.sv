// tb_npu_scale16.sv - functional verification of the 16x16 NPU (npu_top16, N=16).
//  Proves the parameterized systolic array scales from 8x8 to 16x16:
//    axis1 GEMM correctness over K {1,2,63,64} x INT8 extremes
//    axis2 spatial single-element at the FULL-array corners {0,15}x{0,15}+middle
//          (exercises 16-wide row/col address decode + skew across all 256 PEs)
//    axis3 accumulate mode (clr_acc=0 K-tiling)
//    axis4 randomized regression (random K, random INT8) vs software golden
//    axis5 requantize (scale/shift/clip + OFF->raw)
//  Run: xsim scaletb -runall   (override: -testplusarg NRAND=80)
`timescale 1ns/1ps
module tb_npu_scale16;
  localparam int N = 16;
  logic clk=0, rst=1;
  logic sel=0, we=0, re=0, rd_valid; logic [13:0] addr=0; logic [31:0] wdata=0; logic [3:0] wstrb=0; logic [31:0] rdata;
  always #5 clk=~clk;
  npu_top16 dut(.clk(clk),.rst(rst),.sel(sel),.we(we),.addr(addr),.wdata(wdata),.wstrb(wstrb),
                .re(re),.rdata(rdata),.rd_valid(rd_valid));

  int errors=0, checks=0;
  int A_g[0:N-1][0:63];
  int B_g[0:63][0:N-1];

  task automatic bw(input int a, input int d);
    @(negedge clk); addr=a[13:0]; wdata=d; wstrb=4'hF; sel=1; we=1;
    @(negedge clk); sel=0; we=0; wstrb=0;
  endtask
  task automatic br(input int a, output int d);
    // pipelined read: hold sel/re until rd_valid, then capture (3-cycle latency)
    @(negedge clk); addr=a[13:0]; sel=1; we=0; re=1;
    forever begin @(posedge clk); #1; if(rd_valid) break; end
    d=rdata;
    @(negedge clk); sel=0; re=0;
  endtask
  function automatic int Aaddr(input int i,input int k); return 'h1000 + i*256 + k*4; endfunction
  function automatic int Baddr(input int k,input int j); return 'h2000 + j*256 + k*4; endfunction
  function automatic int Caddr(input int i,input int j); return 'h3000 + (i*N+j)*4; endfunction
  function automatic int golden(input int i,input int j,input int K);
    int g=0; for(int k=0;k<K;k++) g+=A_g[i][k]*B_g[k][j]; return g;
  endfunction
  function automatic int rq(input int acc, input int mult, input int sh);
    longint p = longint'(acc)*longint'(mult);
    if (sh>0) p += (longint'(1)<<(sh-1));
    p = p >>> sh;
    if (p>127) return 127; else if (p<-128) return -128; else return int'(p);
  endfunction

  task automatic load_AB(input int K);
    bw('h8,K);
    for(int i=0;i<N;i++) for(int k=0;k<K;k++) bw(Aaddr(i,k), A_g[i][k]&'hFF);
    for(int j=0;j<N;j++) for(int k=0;k<K;k++) bw(Baddr(k,j), B_g[k][j]&'hFF);
  endtask
  task automatic start_and_wait(input bit clr);
    int g, s; bw(0, clr?3:1);
    g=0;
    forever begin
      br('h4, s); g++;            // STATUS read (pipelined); bit1 = done
      if(s[1]) break;
      if(g>6000) begin errors++; $display("  TIMEOUT(no done)"); break; end
    end
  endtask
  task automatic set_cfg(input int mult, input int sh, input bit en);
    bw('hC, ((mult&'hFFFF)<<16) | ((sh&'h3F)<<8) | (en?1:0));
  endtask
  task automatic check_golden(input int K, input string nm);
    int c,gg;
    for(int i=0;i<N;i++) for(int j=0;j<N;j++) begin
      gg=golden(i,j,K); br(Caddr(i,j),c); checks++;
      if(c!==gg) begin errors++; if(errors<25) $display("  FAIL %s C[%0d][%0d]=%0d exp=%0d",nm,i,j,c,gg); end
    end
  endtask
  task automatic check_requant(input int K,input int mult,input int sh,input string nm);
    int c,g;
    for(int i=0;i<N;i++) for(int j=0;j<N;j++) begin
      g=rq(golden(i,j,K),mult,sh); br(Caddr(i,j),c); checks++;
      if(c!==g) begin errors++; if(errors<25) $display("  FAIL %s C[%0d][%0d]=%0d exp=%0d",nm,i,j,c,g); end
    end
  endtask
  task automatic fill_uniform(input int K,input int av,input int bv);
    for(int i=0;i<N;i++) for(int k=0;k<K;k++) A_g[i][k]=av;
    for(int k=0;k<K;k++) for(int j=0;j<N;j++) B_g[k][j]=bv;
  endtask
  task automatic fill_random(input int K);
    for(int i=0;i<N;i++) for(int k=0;k<K;k++) A_g[i][k]=($urandom%256)-128;
    for(int k=0;k<K;k++) for(int j=0;j<N;j++) B_g[k][j]=($urandom%256)-128;
  endtask

  int NRAND=40;
  int Ks[4]='{1,2,63,64};

  initial begin
    if($value$plusargs("NRAND=%d",NRAND));
    rst=1; repeat(5)@(negedge clk); rst=0; @(negedge clk);
    $display("=== NPU 16x16 scale-up functional verification (N=%0d, 256 PEs) ===",N);

    // ---- axis 1: K x INT8 extremes (uniform) ----
    for(int t=0;t<4;t++) begin
      int K=Ks[t];
      fill_uniform(K,127,127);   load_AB(K); start_and_wait(1); check_golden(K,$sformatf("K=%0d 127x127",K));
      fill_uniform(K,-128,-128); load_AB(K); start_and_wait(1); check_golden(K,$sformatf("K=%0d -128x-128",K));
      fill_uniform(K,127,-128);  load_AB(K); start_and_wait(1); check_golden(K,$sformatf("K=%0d 127x-128",K));
    end
    $display("  [axis1] K x INT8 extremes : done");

    // ---- axis 2: spatial single-element at FULL 16x16 corners + middle ----
    begin
      int Rr[5]; int Cc[5];
      Rr='{0,15,0,15,8}; Cc='{0,15,15,0,7};
      for(int t=0;t<5;t++) begin
        int K=8, R=Rr[t], C=Cc[t];
        for(int i=0;i<N;i++) for(int k=0;k<K;k++) A_g[i][k]=((i==R&&k==0)?1:0);
        for(int k=0;k<K;k++) for(int j=0;j<N;j++) B_g[k][j]=((k==0&&j==C)?1:0);
        load_AB(K); start_and_wait(1); check_golden(K,$sformatf("spatial PE[%0d][%0d]",R,C));
      end
    end
    $display("  [axis2] spatial corners+middle of 16x16 (256-PE addressing) : done");

    // ---- axis 3: accumulate mode (clr_acc=0 K-tiling) ----
    begin
      int C1[0:N-1][0:N-1], c, exp;
      fill_uniform(4,2,3); load_AB(4); start_and_wait(1);          // C = 4*2*3 = 24
      for(int i=0;i<N;i++) for(int j=0;j<N;j++) C1[i][j]=golden(i,j,4);
      check_golden(4,"accum step1 (=24)");
      fill_uniform(4,5,1); load_AB(4); start_and_wait(0);          // clr_acc=0 -> +20 -> 44
      for(int i=0;i<N;i++) for(int j=0;j<N;j++) begin
        exp=C1[i][j]+golden(i,j,4); br(Caddr(i,j),c); checks++;
        if(c!==exp) begin errors++; if(errors<25) $display("  FAIL accum C[%0d][%0d]=%0d exp=%0d",i,j,c,exp); end
      end
    end
    $display("  [axis3] accumulate mode (clr_acc=0, K-tiling) : done");

    // ---- axis 4: randomized regression ----
    for(int n=0;n<NRAND;n++) begin
      int K=1+($urandom%64);
      fill_random(K); load_AB(K); start_and_wait(1);
      check_golden(K,$sformatf("rand#%0d K=%0d",n,K));
    end
    $display("  [axis4] random regression : %0d back-to-back GEMMs : done",NRAND);

    // ---- axis 5: requantize ----
    begin
      int K=8;
      fill_uniform(K,4, 4); load_AB(K); start_and_wait(1);          // C = 128
      set_cfg(1,0,1); check_requant(K,1,0,"rq C=128 clip127");
      set_cfg(1,1,1); check_requant(K,1,1,"rq C=128 s1 (=64)");
      fill_uniform(K,4,-4); load_AB(K); start_and_wait(1);          // C = -128
      set_cfg(1,0,1); check_requant(K,1,0,"rq C=-128 clip-128");
      set_cfg(0,0,0); check_golden(K,"requant OFF -> raw INT32");   // no-regression
      for(int n=0;n<10;n++) begin
        int Kr=1+($urandom%64), m=1+($urandom%512), s=$urandom%16;
        fill_random(Kr); load_AB(Kr); start_and_wait(1);
        set_cfg(m,s,1); check_requant(Kr,m,s,$sformatf("rq rand#%0d K=%0d m=%0d s=%0d",n,Kr,m,s));
      end
      set_cfg(0,0,0);
    end
    $display("  [axis5] requantize (clip + OFF->raw + random) : done");

    $display("=== checks=%0d errors=%0d ===",checks,errors);
    if(errors==0) $display("RESULT: ALL PASS - 16x16 NPU matches golden (GEMM+spatial+accum+random+requant)");
    else          $display("RESULT: FAIL (%0d errors)",errors);
    $finish;
  end
  initial begin #800_000_000; $display("RESULT: TIMEOUT(sim)"); $finish; end
endmodule
