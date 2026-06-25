// tb_ps_regress.sv - PS-control-path regression for the rv32 platform.
// Drives rv32_platform through its AXI4-Lite slave EXACTLY as the PS monitor
// firmware does (reset -> clear data -> load imem -> run -> read registers),
// for N>=20 random RV32I programs, and checks the final 32-register state
// against an independent in-TB ISS golden. Proves the PS control logic +
// platform + CPU agree, repeatedly.
//
//   default 25 programs; override:  xsim ... -testplusarg PROGRAMS=40
`timescale 1ns/1ps
module tb_ps_regress;
  logic ACLK=0, ARESETN=0;
  logic [7:0]  AWADDR=0;  logic AWVALID=0, AWREADY;
  logic [31:0] WDATA=0;   logic [3:0] WSTRB=4'hF; logic WVALID=0, WREADY;
  logic [1:0]  BRESP;     logic BVALID, BREADY=1;
  logic [7:0]  ARADDR=0;  logic ARVALID=0, ARREADY;
  logic [31:0] RDATA;     logic [1:0] RRESP; logic RVALID, RREADY=1;
  logic [3:0]  led_o;     logic [3:0] sw_i=0, btn_i=0;

  rv32_platform dut (
    .S_AXI_ACLK(ACLK), .S_AXI_ARESETN(ARESETN),
    .S_AXI_AWADDR(AWADDR), .S_AXI_AWVALID(AWVALID), .S_AXI_AWREADY(AWREADY),
    .S_AXI_WDATA(WDATA), .S_AXI_WSTRB(WSTRB), .S_AXI_WVALID(WVALID), .S_AXI_WREADY(WREADY),
    .S_AXI_BRESP(BRESP), .S_AXI_BVALID(BVALID), .S_AXI_BREADY(BREADY),
    .S_AXI_ARADDR(ARADDR), .S_AXI_ARVALID(ARVALID), .S_AXI_ARREADY(ARREADY),
    .S_AXI_RDATA(RDATA), .S_AXI_RRESP(RRESP), .S_AXI_RVALID(RVALID), .S_AXI_RREADY(RREADY),
    .led_o(led_o), .sw_i(sw_i), .btn_i(btn_i));
  always #5 ACLK = ~ACLK;

  localparam CTRL=8'h00, IMEM_ADDR=8'h08, IMEM_WDATA=8'h0C, DMEM_ADDR=8'h10,
             DMEM_WDATA=8'h14, REG_ADDR=8'h18, REG_RDATA=8'h1C;
  localparam C_RESET=32'h1, C_RUN=32'h2, C_CLR=32'h8;

  // ---- AXI-Lite BFM (always-ready master, like the PS) ----
  task automatic axw(input [7:0] a, input [31:0] d);
    @(negedge ACLK); AWADDR=a; WDATA=d; AWVALID=1; WVALID=1;
    @(posedge ACLK); while(!(AWREADY&&WREADY)) @(posedge ACLK);
    @(negedge ACLK); AWVALID=0; WVALID=0;
    @(posedge ACLK); while(!BVALID) @(posedge ACLK);
    @(negedge ACLK);
  endtask
  task automatic axr(input [7:0] a, output [31:0] d);
    @(negedge ACLK); ARADDR=a; ARVALID=1;
    @(posedge ACLK); while(!ARREADY) @(posedge ACLK);
    @(negedge ACLK); ARVALID=0;
    @(posedge ACLK); while(!RVALID) @(posedge ACLK);
    d=RDATA; @(negedge ACLK);
  endtask

  // ---- PS-monitor-equivalent operations ----
  task automatic ps_reset();  axw(CTRL, C_RESET | C_CLR); endtask  // reset held + clear commit (no glitch)
  task automatic ps_clear_data();
    for (int j=0;j<16;j++) begin axw(DMEM_ADDR, 32'h40+j*4); axw(DMEM_WDATA, 0); end
  endtask
  task automatic ps_load(input logic [31:0] p[], input int n);
    for (int i=0;i<n;i++) begin axw(IMEM_ADDR, i*4); axw(IMEM_WDATA, p[i]); end
    axw(IMEM_ADDR, n*4); axw(IMEM_WDATA, 32'h0000006f);   // halt
  endtask
  task automatic ps_run();    axw(CTRL,0); axw(CTRL,C_RUN); endtask
  task automatic ps_rdreg(input int n, output [31:0] v); axw(REG_ADDR,n); axr(REG_RDATA,v); endtask

  // ---- assembler (subset used by gen_random) ----
  function automatic logic [31:0] R(int f7,rs2,rs1,f3,rd,op); return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op; endfunction
  function automatic logic [31:0] I(int im,rs1,f3,rd,op); return ((im&12'hFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op; endfunction
  function automatic logic [31:0] S(int im,rs2,rs1,f3,op); return (((im>>5)&7'h7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((im&5'h1F)<<7)|op; endfunction
  function automatic logic [31:0] B(int im,rs2,rs1,f3,op); return (((im>>12)&1)<<31)|(((im>>5)&6'h3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((im>>1)&4'hF)<<8)|(((im>>11)&1)<<7)|op; endfunction
  localparam OP_R=7'h33,OP_I=7'h13,OP_LD=7'h03,OP_ST=7'h23,OP_BR=7'h63,OP_JAL=7'h6F,OP_LUI=7'h37,OP_AUIPC=7'h17;
  function automatic logic [31:0] addi(int rd,rs1,im); return I(im,rs1,0,rd,OP_I); endfunction
  function automatic logic [31:0] NOPI(); return I(0,0,0,0,OP_I); endfunction

  // ---- independent ISS golden ----
  localparam int DW=4096;
  logic [31:0] gmem [0:DW-1];
  function automatic logic [31:0] gimm(input logic [31:0] ins, input int op);
    case(op) OP_ST:return $signed({ins[31:25],ins[11:7]});
             OP_BR:return $signed({ins[31],ins[7],ins[30:25],ins[11:8],1'b0});
             OP_LUI,OP_AUIPC:return {ins[31:12],12'h0};
             OP_JAL:return $signed({ins[31],ins[19:12],ins[20],ins[30:21],1'b0});
             default:return $signed(ins[31:20]); endcase
  endfunction
  function automatic logic [31:0] gload(input logic [31:0] w, input logic [1:0] bo, input logic [2:0] f3);
    logic [7:0] b; logic [15:0] h; b=w[8*bo+:8]; h=(bo[1]==0)?w[15:0]:w[31:16];
    case(f3) 3'b000:return $signed(b);3'b001:return $signed(h);3'b010:return w;
             3'b100:return {24'h0,b};3'b101:return {16'h0,h};default:return w; endcase
  endfunction
  task automatic gstore(input logic [31:0] a, input logic [2:0] f3, input logic [31:0] sd);
    int idx; logic [3:0] st; logic [31:0] al; logic [1:0] bo; idx=(a>>2)%DW; bo=a[1:0];
    case(f3) 3'b000:begin st=(4'h1<<bo); al={4{sd[7:0]}}; end
             3'b001:begin st=(bo[1]==0)?4'h3:4'hC; al={2{sd[15:0]}}; end
             3'b010:begin st=4'hF; al=sd; end default:begin st=0; al=sd; end endcase
    for(int k=0;k<4;k++) if(st[k]) gmem[idx][8*k+:8]=al[8*k+:8];
  endtask
  task automatic iss_run(input logic [31:0] p[], input int n, output logic [31:0] rf[0:31]);
    int pc,op,f3,rs1,rs2,rd,f75,ao,ct,cnt; logic [31:0] ins,im,a,bb,np,wd,sa,sb; bit hw,cd;
    for(int i=0;i<32;i++) rf[i]=0; for(int i=0;i<DW;i++) gmem[i]=0; pc=0; cnt=0;
    while((pc>>2)<n && cnt<6000) begin
      cnt++; ins=p[pc>>2]; op=ins[6:0]; rd=ins[11:7]; f3=ins[14:12]; rs1=ins[19:15]; rs2=ins[24:20];
      f75=(op==OP_R||(op==OP_I&&f3==3'b101))?ins[30]:0; im=gimm(ins,op); a=rf[rs1]; bb=rf[rs2]; np=pc+4; hw=0; wd=0;
      case(op)
        OP_R,OP_I,OP_LUI,OP_AUIPC: begin
          if(op==OP_LUI)ao=3; else if(op==OP_AUIPC)ao=0; else ao=2;
          if(ao==0)ct=0; else if(ao==3)ct=10;
          else case(f3) 3'b000:ct=f75?1:0;3'b001:ct=5;3'b010:ct=8;3'b011:ct=9;3'b100:ct=4;3'b101:ct=f75?7:6;3'b110:ct=3;default:ct=2; endcase
          sa=(op==OP_AUIPC)?pc:a; sb=(op==OP_R)?bb:im;
          case(ct) 0:wd=sa+sb;1:wd=sa-sb;2:wd=sa&sb;3:wd=sa|sb;4:wd=sa^sb;5:wd=sa<<sb[4:0];6:wd=sa>>sb[4:0];7:wd=$signed(sa)>>>sb[4:0];8:wd=($signed(sa)<$signed(sb))?1:0;9:wd=(sa<sb)?1:0;10:wd=sb;default:wd=0; endcase
          hw=1; end
        OP_LD: begin wd=gload(gmem[((a+im)>>2)%DW],(a+im)&3,f3); hw=1; end
        OP_ST: gstore(a+im,f3,bb);
        OP_BR: begin case(f3) 3'b000:cd=(a==bb);3'b001:cd=(a!=bb);3'b100:cd=($signed(a)<$signed(bb));3'b101:cd=($signed(a)>=$signed(bb));3'b110:cd=(a<bb);3'b111:cd=(a>=bb);default:cd=0; endcase if(cd)np=pc+im; end
        OP_JAL: begin wd=pc+4; hw=1; np=pc+im; end
        default:;
      endcase
      if(hw&&rd!=0) rf[rd]=wd; rf[0]=0; pc=np;
    end
  endtask

  // ---- random program gen (forward-only ctrl, x1..x8, data window 0x40) ----
  function automatic int rr();   return $urandom%9;     endfunction
  function automatic int rrnz(); return 1+($urandom%8); endfunction
  task automatic gen(input int len, output logic [31:0] p[]);
    int rd,rs1,rs2,off,base; p=new[len]; base='h40;
    for(int i=0;i<len;i++) begin
      int k=$urandom%10; rd=rr(); rs1=rr(); rs2=rr();
      case(k)
        0,1: case($urandom%6) 0:p[i]=I(($urandom%4096)-2048,rs1,0,rd,OP_I);1:p[i]=I(($urandom%4096)-2048,rs1,7,rd,OP_I);
               2:p[i]=I(($urandom%4096)-2048,rs1,6,rd,OP_I);3:p[i]=I(($urandom%4096)-2048,rs1,4,rd,OP_I);
               4:p[i]=I(($urandom%4096)-2048,rs1,2,rd,OP_I);default:p[i]=I(($urandom%4096)-2048,rs1,3,rd,OP_I); endcase
        2,3: case($urandom%10) 0:p[i]=R(0,rs2,rs1,0,rd,OP_R);1:p[i]=R(32,rs2,rs1,0,rd,OP_R);2:p[i]=R(0,rs2,rs1,7,rd,OP_R);
               3:p[i]=R(0,rs2,rs1,6,rd,OP_R);4:p[i]=R(0,rs2,rs1,4,rd,OP_R);5:p[i]=R(0,rs2,rs1,2,rd,OP_R);
               6:p[i]=R(0,rs2,rs1,3,rd,OP_R);7:p[i]=R(0,rs2,rs1,1,rd,OP_R);8:p[i]=R(0,rs2,rs1,5,rd,OP_R);default:p[i]=R(32,rs2,rs1,5,rd,OP_R); endcase
        4: case($urandom%3) 0:p[i]=I($urandom%32,rs1,1,rd,OP_I);1:p[i]=I($urandom%32,rs1,5,rd,OP_I);default:p[i]=I(32'h400|($urandom%32),rs1,5,rd,OP_I); endcase
        5: p[i]=(($urandom&20'hFFFFF)<<12)|(rd<<7)|OP_LUI;
        6,7: begin off=base+(($urandom%5)*4);
               if($urandom%2) case($urandom%3) 0:p[i]=S(off,rrnz(),0,2,OP_ST);1:p[i]=S(off,rrnz(),0,0,OP_ST);default:p[i]=S(off,rrnz(),0,1,OP_ST); endcase
               else case($urandom%5) 0:p[i]=I(off,0,2,rd,OP_LD);1:p[i]=I(off,0,0,rd,OP_LD);2:p[i]=I(off,0,4,rd,OP_LD);3:p[i]=I(off,0,1,rd,OP_LD);default:p[i]=I(off,0,5,rd,OP_LD); endcase
             end
        8: begin off=($urandom%3)*4+8; case($urandom%6) 0:p[i]=B(off,rs2,rs1,0,OP_BR);1:p[i]=B(off,rs2,rs1,1,OP_BR);2:p[i]=B(off,rs2,rs1,4,OP_BR);3:p[i]=B(off,rs2,rs1,5,OP_BR);4:p[i]=B(off,rs2,rs1,6,OP_BR);default:p[i]=B(off,rs2,rs1,7,OP_BR); endcase end
        default: p[i]=(((($urandom%2)*4+8)>>1)&10'h3FF)<<21 | (rr()<<7) | OP_JAL;
      endcase
    end
  endtask

  int n_prog=25, errors=0, mism=0;
  logic [31:0] body[], full[], r[0:31], gr[0:31], v;
  initial begin
    if ($value$plusargs("PROGRAMS=%d", n_prog)) ;
    ARESETN=0; repeat(4) @(negedge ACLK); ARESETN=1; @(negedge ACLK);

    for (int t=0;t<n_prog;t++) begin
      bit bad; int L;
      gen(20, body); L=20;
      full = new[L+4];
      for (int i=0;i<L;i++) full[i]=body[i];
      for (int i=0;i<4;i++) full[L+i]=NOPI();        // branch/jal landing pad
      // PS-style: reset -> clear data -> load -> run
      ps_reset(); ps_clear_data(); ps_load(full, L+4); ps_run();
      repeat (L*60 + 1500) @(posedge ACLK);          // run to halt (cache stalls)
      // read back all 32 regs via the control slave (as the PS 'D' command does)
      for (int n=0;n<32;n++) ps_rdreg(n, r[n]);
      iss_run(full, L+4, gr);
      bad=0; for (int n=0;n<32;n++) if (r[n]!==gr[n]) bad=1;
      if (bad) begin
        errors++; mism++;
        $display("==== PS-REGRESS COUNTER-EXAMPLE prog#%0d ====", t);
        for (int i=0;i<L+4;i++) $display("  prog[%0d]=%08x;", i, full[i]);
        for (int n=0;n<32;n++) if (r[n]!==gr[n]) $display("  x%0d DUT=%08x ISS=%08x  <-- DIFF", n, r[n], gr[n]);
      end else $display("PS-REGRESS prog#%0d OK", t);
    end

    $display("[tb_ps_regress] programs=%0d  mismatches=%0d", n_prog, mism);
    if (errors==0) $display("RESULT: ALL PASS (PS control path vs ISS, %0d programs)", n_prog);
    else           $fatal(1, "RESULT: FAIL (%0d mismatches)", mism);
    $finish;
  end
  initial begin #500000000; $fatal(1,"TIMEOUT"); end
endmodule
