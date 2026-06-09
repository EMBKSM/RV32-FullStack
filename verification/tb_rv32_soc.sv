// =====================================================================
// tb_rv32_soc.sv  -  FULL SoC integration testbench (rv32_soc.vhd)
//   pipeline core + I-cache + D-cache + behavioral AXI memories.
// The architectural register result must equal an independent in-TB ISS
// for any program, REGARDLESS of cache-miss / AXI-burst stalls. Program is
// preloaded into the instruction memory via the SoC prog_* port.
//
// Compile order (xsim): all ip_workspace .vhd (incl. axi_slave_mem.vhd,
// cache_unit.vhd, rv32_soc.vhd) + this file; set top = tb_rv32_soc.
// Run:  xvhdl ...*.vhd ; xvlog -sv tb_rv32_soc.sv ; xelab tb_rv32_soc -R
// =====================================================================
`timescale 1ns/1ps
module tb_rv32_soc;
  logic clk=0, reset;
  logic        prog_we;
  logic [31:0] prog_addr, prog_data;
  logic        dpre_we;
  logic [31:0] dpre_addr, dpre_data;
  logic        dbg_commit;
  logic [4:0]  dbg_rd, dbg_reg_addr;
  logic [31:0] dbg_wdata, dbg_reg_data;
  logic [31:0] dbg_pc, dbg_instr;
  logic        dbg_mstall;
  always #5 clk=~clk;

  rv32_soc #(.RESET_ADDR(32'h0000_0000)) dut (
    .clk(clk), .reset(reset),
    .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
    .dmem_we_pre(dpre_we), .dmem_addr_pre(dpre_addr), .dmem_data_pre(dpre_data),
    .dbg_commit(dbg_commit), .dbg_rd(dbg_rd), .dbg_wdata(dbg_wdata),
    .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data),
    .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_mstall(dbg_mstall));

  // ---- monitors (enabled only during +DEBUGPROG) ----
  bit mon_on = 0;
  always @(posedge clk) begin
    // fetch trace: only while advancing (mem_stall=0) and within the program region
    if (mon_on && dbg_mstall==1'b0 && dbg_pc < 32'h00000040)
      $display("[IF] t=%0t  pc=%08x  instr=%08x", $time, dbg_pc, dbg_instr);
    if (mon_on && dbg_commit)
      $display("[WB] t=%0t  x%0d <= %08x", $time, dbg_rd, dbg_wdata);
  end

  // ---------------- RV32I assembler ----------------
  function automatic logic [31:0] R(int f7,rs2,rs1,f3,rd,opc);
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] Itype(int imm,rs1,f3,rd,opc);
    return ((imm & 12'hFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] Stype(int imm,rs2,rs1,f3,opc);
    return (((imm>>5)&7'h7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&5'h1F)<<7)|opc; endfunction
  function automatic logic [31:0] Btype(int imm,rs2,rs1,f3,opc);
    return (((imm>>12)&1)<<31)|(((imm>>5)&6'h3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|
           (((imm>>1)&4'hF)<<8)|(((imm>>11)&1)<<7)|opc; endfunction
  function automatic logic [31:0] Utype(int imm20,rd,opc);
    return ((imm20 & 20'hFFFFF)<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] Jtype(int imm,rd,opc);
    return (((imm>>20)&1)<<31)|(((imm>>1)&10'h3FF)<<21)|(((imm>>11)&1)<<20)|
           (((imm>>12)&8'hFF)<<12)|(rd<<7)|opc; endfunction
  localparam OP_R=7'h33, OP_I=7'h13, OP_LD=7'h03, OP_ST=7'h23, OP_BR=7'h63,
             OP_JAL=7'h6F, OP_JALR=7'h67, OP_LUI=7'h37, OP_AUIPC=7'h17;
  localparam logic [31:0] NOP = 32'h0000_0013;

  function automatic logic [31:0] addi (int rd,rs1,imm); return Itype(imm,rs1,0,rd,OP_I); endfunction
  function automatic logic [31:0] andi (int rd,rs1,imm); return Itype(imm,rs1,7,rd,OP_I); endfunction
  function automatic logic [31:0] ori_ (int rd,rs1,imm); return Itype(imm,rs1,6,rd,OP_I); endfunction
  function automatic logic [31:0] xori (int rd,rs1,imm); return Itype(imm,rs1,4,rd,OP_I); endfunction
  function automatic logic [31:0] slti (int rd,rs1,imm); return Itype(imm,rs1,2,rd,OP_I); endfunction
  function automatic logic [31:0] sltiu(int rd,rs1,imm); return Itype(imm,rs1,3,rd,OP_I); endfunction
  function automatic logic [31:0] slli (int rd,rs1,sh ); return Itype(sh&31,rs1,1,rd,OP_I); endfunction
  function automatic logic [31:0] srli (int rd,rs1,sh ); return Itype(sh&31,rs1,5,rd,OP_I); endfunction
  function automatic logic [31:0] srai (int rd,rs1,sh ); return Itype(32'h400|(sh&31),rs1,5,rd,OP_I); endfunction
  function automatic logic [31:0] add_ (int rd,rs1,rs2); return R(0,rs2,rs1,0,rd,OP_R); endfunction
  function automatic logic [31:0] sub_ (int rd,rs1,rs2); return R(32,rs2,rs1,0,rd,OP_R); endfunction
  function automatic logic [31:0] sll_ (int rd,rs1,rs2); return R(0,rs2,rs1,1,rd,OP_R); endfunction
  function automatic logic [31:0] slt_ (int rd,rs1,rs2); return R(0,rs2,rs1,2,rd,OP_R); endfunction
  function automatic logic [31:0] sltu_(int rd,rs1,rs2); return R(0,rs2,rs1,3,rd,OP_R); endfunction
  function automatic logic [31:0] xor_ (int rd,rs1,rs2); return R(0,rs2,rs1,4,rd,OP_R); endfunction
  function automatic logic [31:0] srl_ (int rd,rs1,rs2); return R(0,rs2,rs1,5,rd,OP_R); endfunction
  function automatic logic [31:0] sra_ (int rd,rs1,rs2); return R(32,rs2,rs1,5,rd,OP_R); endfunction
  function automatic logic [31:0] or_  (int rd,rs1,rs2); return R(0,rs2,rs1,6,rd,OP_R); endfunction
  function automatic logic [31:0] and_ (int rd,rs1,rs2); return R(0,rs2,rs1,7,rd,OP_R); endfunction
  function automatic logic [31:0] lw_  (int rd,rs1,imm); return Itype(imm,rs1,2,rd,OP_LD); endfunction
  function automatic logic [31:0] lb_  (int rd,rs1,imm); return Itype(imm,rs1,0,rd,OP_LD); endfunction
  function automatic logic [31:0] lbu_ (int rd,rs1,imm); return Itype(imm,rs1,4,rd,OP_LD); endfunction
  function automatic logic [31:0] lh_  (int rd,rs1,imm); return Itype(imm,rs1,1,rd,OP_LD); endfunction
  function automatic logic [31:0] lhu_ (int rd,rs1,imm); return Itype(imm,rs1,5,rd,OP_LD); endfunction
  function automatic logic [31:0] sw_  (int rs2,rs1,imm);return Stype(imm,rs2,rs1,2,OP_ST); endfunction
  function automatic logic [31:0] sb_  (int rs2,rs1,imm);return Stype(imm,rs2,rs1,0,OP_ST); endfunction
  function automatic logic [31:0] sh_  (int rs2,rs1,imm);return Stype(imm,rs2,rs1,1,OP_ST); endfunction
  function automatic logic [31:0] beq_ (int rs1,rs2,off);return Btype(off,rs2,rs1,0,OP_BR); endfunction
  function automatic logic [31:0] bne_ (int rs1,rs2,off);return Btype(off,rs2,rs1,1,OP_BR); endfunction
  function automatic logic [31:0] blt_ (int rs1,rs2,off);return Btype(off,rs2,rs1,4,OP_BR); endfunction
  function automatic logic [31:0] bge_ (int rs1,rs2,off);return Btype(off,rs2,rs1,5,OP_BR); endfunction
  function automatic logic [31:0] bltu_(int rs1,rs2,off);return Btype(off,rs2,rs1,6,OP_BR); endfunction
  function automatic logic [31:0] bgeu_(int rs1,rs2,off);return Btype(off,rs2,rs1,7,OP_BR); endfunction
  function automatic logic [31:0] lui_ (int rd,imm20);   return Utype(imm20,rd,OP_LUI); endfunction
  function automatic logic [31:0] auipc_(int rd,imm20);  return Utype(imm20,rd,OP_AUIPC); endfunction
  function automatic logic [31:0] jal_ (int rd,off);     return Jtype(off,rd,OP_JAL); endfunction
  function automatic logic [31:0] jalr_(int rd,rs1,imm); return Itype(imm,rs1,0,rd,OP_JALR); endfunction

  // ---------------- DUT control ----------------
  int unsigned checks=0, errors=0;
  localparam int DMEM_WORDS = 4096;

  task automatic dut_run(input logic [31:0] prog[], input int n, output logic [31:0] r[0:31]);
    // NOTE: the SoC's instruction & data memories PERSIST across calls (they are
    // inside the DUT). So each run must (a) clear the data window the program may
    // read back, and (b) append a HALT (jal x0,0) so the PC parks there instead of
    // running off into stale instructions left by the previous program.
    reset=1; prog_we=0; dpre_we=0; prog_addr=0; prog_data=0;
    dpre_addr=0; dpre_data=0; @(negedge clk);
    // clear data window 0x40..0x7c (16 words) so reads of un-stored words give 0
    for (int j=0;j<16;j++) begin
      dpre_we=1; dpre_addr=32'h40 + j*4; dpre_data=32'h0;
      @(negedge clk);
    end
    dpre_we=0;
    // preload instruction image (drive at negedge; sampled by the next posedge --
    // driving right after @(posedge) races with the slave's clocked sampling).
    for (int i=0;i<n;i++) begin
      prog_we=1; prog_addr=i*4; prog_data=prog[i];
      @(negedge clk);
    end
    // HALT at index n: jal x0,0 (jump-to-self, rd=x0 -> no write) parks the PC.
    prog_we=1; prog_addr=n*4; prog_data=32'h0000006F; @(negedge clk);
    prog_we=0; @(negedge clk);
    reset=0;
    // generous budget: cache miss/refill stalls inflate cycle count
    repeat (n*120 + 800) @(posedge clk);
    for (int i=0;i<32;i++) begin dbg_reg_addr=i[4:0]; #1; r[i]=dbg_reg_data; end
  endtask

  task automatic ck_reg(input logic [31:0] r[0:31], input int idx,
                        input logic [31:0] exp, input string name);
    checks++;
    if (r[idx] !== exp) begin errors++; $error("%s FAIL: x%0d=%h expected=%h",name,idx,r[idx],exp); end
  endtask

  // ---------------- independent ISS golden ----------------
  logic [31:0] gmem [0:DMEM_WORDS-1];
  function automatic logic [31:0] g_imm(input logic [31:0] ins, input int opc);
    case (opc)
      OP_ST: return $signed({ins[31:25], ins[11:7]});
      OP_BR: return $signed({ins[31], ins[7], ins[30:25], ins[11:8], 1'b0});
      OP_LUI, OP_AUIPC: return {ins[31:12], 12'h0};
      OP_JAL: return $signed({ins[31], ins[19:12], ins[20], ins[30:21], 1'b0});
      default: return $signed(ins[31:20]);
    endcase
  endfunction
  function automatic logic [31:0] g_load(input logic [31:0] word, input logic [1:0] boff, input logic [2:0] f3);
    logic [7:0] bb; logic [15:0] hh;
    bb = word[8*boff +: 8];
    hh = (boff[1]==0) ? word[15:0] : word[31:16];
    case (f3)
      3'b000: return $signed(bb); 3'b001: return $signed(hh); 3'b010: return word;
      3'b100: return {24'h0,bb}; 3'b101: return {16'h0,hh}; default: return word;
    endcase
  endfunction
  task automatic g_store(input logic [31:0] addr, input logic [2:0] f3, input logic [31:0] sd);
    int idx; logic [3:0] wstrb; logic [31:0] wal; logic [1:0] boff;
    idx=(addr>>2)%DMEM_WORDS; boff=addr[1:0];
    case (f3)
      3'b000: begin wstrb=(4'h1<<boff); wal={4{sd[7:0]}}; end
      3'b001: begin wstrb=(boff[1]==0)?4'h3:4'hC; wal={2{sd[15:0]}}; end
      3'b010: begin wstrb=4'hF; wal=sd; end
      default:begin wstrb=4'h0; wal=sd; end
    endcase
    for (int k=0;k<4;k++) if (wstrb[k]) gmem[idx][8*k +: 8] = wal[8*k +: 8];
  endtask
  task automatic iss_run(input logic [31:0] prog[], input int n, output logic [31:0] reg_[0:31]);
    int pc,opc,f3,rs1,rs2,rd,f7_5,alu_op,ctrl,cnt;
    logic [31:0] ins,imm,a,bb,npc,wd,srca,srcb; bit has_wd,cond;
    for (int i=0;i<32;i++) reg_[i]=0;
    for (int i=0;i<DMEM_WORDS;i++) gmem[i]=0;
    pc=0; cnt=0;
    while ((pc>>2) < n && cnt < 4000) begin
      cnt++; ins=prog[pc>>2];
      opc=ins[6:0]; rd=ins[11:7]; f3=ins[14:12]; rs1=ins[19:15]; rs2=ins[24:20];
      f7_5 = (opc==OP_R || (opc==OP_I && f3==3'b101)) ? ins[30] : 0;
      imm=g_imm(ins,opc); a=reg_[rs1]; bb=reg_[rs2]; npc=pc+4; has_wd=0; wd=0;
      case (opc)
        OP_R,OP_I,OP_LUI,OP_AUIPC: begin
          if (opc==OP_LUI) alu_op=3; else if (opc==OP_AUIPC) alu_op=0; else alu_op=2;
          if (alu_op==0) ctrl=0; else if (alu_op==3) ctrl=10;
          else case (f3)
            3'b000: ctrl=f7_5?1:0; 3'b001: ctrl=5; 3'b010: ctrl=8; 3'b011: ctrl=9;
            3'b100: ctrl=4; 3'b101: ctrl=f7_5?7:6; 3'b110: ctrl=3; default: ctrl=2;
          endcase
          srca=(opc==OP_AUIPC)?pc:a; srcb=(opc==OP_R)?bb:imm;
          case (ctrl)
            0: wd=srca+srcb; 1: wd=srca-srcb; 2: wd=srca&srcb; 3: wd=srca|srcb; 4: wd=srca^srcb;
            5: wd=srca<<srcb[4:0]; 6: wd=srca>>srcb[4:0]; 7: wd=$signed(srca)>>>srcb[4:0];
            8: wd=($signed(srca)<$signed(srcb))?1:0; 9: wd=(srca<srcb)?1:0; 10: wd=srcb; default: wd=0;
          endcase
          has_wd=1;
        end
        OP_LD: begin wd=g_load(gmem[((a+imm)>>2)%DMEM_WORDS],(a+imm)&3,f3); has_wd=1; end
        OP_ST: begin g_store(a+imm,f3,bb); end
        OP_BR: begin
          case (f3)
            3'b000: cond=(a==bb); 3'b001: cond=(a!=bb);
            3'b100: cond=($signed(a)<$signed(bb)); 3'b101: cond=($signed(a)>=$signed(bb));
            3'b110: cond=(a<bb); 3'b111: cond=(a>=bb); default: cond=0;
          endcase
          if (cond) npc=pc+imm;
        end
        OP_JAL:  begin wd=pc+4; has_wd=1; npc=pc+imm; end
        OP_JALR: begin wd=pc+4; has_wd=1; npc=(a+imm)&32'hFFFFFFFE; end
        default: ;
      endcase
      if (has_wd && rd!=0) reg_[rd]=wd;
      reg_[0]=0; pc=npc;
    end
  endtask

  // ---------------- random program gen (forward-only ctrl, x1..x8) ----------------
  function automatic int rreg();   return $urandom % 9;       endfunction
  function automatic int rregnz(); return 1 + ($urandom % 8); endfunction
  task automatic gen_random(input int len, output logic [31:0] p[]);
    int rd,rs1,rs2,off,base; p=new[len]; base='h40;
    for (int i=0;i<len;i++) begin
      int kind = $urandom % 11; rd=rreg(); rs1=rreg(); rs2=rreg();
      case (kind)
        0,1: case ($urandom%6)
               0: p[i]=addi(rd,rs1,($urandom%4096)-2048); 1: p[i]=andi(rd,rs1,($urandom%4096)-2048);
               2: p[i]=ori_(rd,rs1,($urandom%4096)-2048); 3: p[i]=xori(rd,rs1,($urandom%4096)-2048);
               4: p[i]=slti(rd,rs1,($urandom%4096)-2048); default: p[i]=sltiu(rd,rs1,($urandom%4096)-2048);
             endcase
        2,3: case ($urandom%10)
               0:p[i]=add_(rd,rs1,rs2);1:p[i]=sub_(rd,rs1,rs2);2:p[i]=and_(rd,rs1,rs2);3:p[i]=or_(rd,rs1,rs2);
               4:p[i]=xor_(rd,rs1,rs2);5:p[i]=slt_(rd,rs1,rs2);6:p[i]=sltu_(rd,rs1,rs2);7:p[i]=sll_(rd,rs1,rs2);
               8:p[i]=srl_(rd,rs1,rs2);default:p[i]=sra_(rd,rs1,rs2);
             endcase
        4: case ($urandom%3) 0:p[i]=slli(rd,rs1,$urandom%32);1:p[i]=srli(rd,rs1,$urandom%32);default:p[i]=srai(rd,rs1,$urandom%32); endcase
        5: p[i]=lui_(rd,$urandom & 'hFFFFF);
        6: p[i]=auipc_(rd,$urandom & 'hFFFFF);
        7,8: begin
               off = base + (($urandom%5)*4);
               if ($urandom%2) case ($urandom%3) 0:p[i]=sw_(rregnz(),0,off);1:p[i]=sb_(rregnz(),0,off);default:p[i]=sh_(rregnz(),0,off); endcase
               else            case ($urandom%5) 0:p[i]=lw_(rd,0,off);1:p[i]=lb_(rd,0,off);2:p[i]=lbu_(rd,0,off);3:p[i]=lh_(rd,0,off);default:p[i]=lhu_(rd,0,off); endcase
             end
        9: begin off=($urandom%3)*4+8;
             case ($urandom%6) 0:p[i]=beq_(rs1,rs2,off);1:p[i]=bne_(rs1,rs2,off);2:p[i]=blt_(rs1,rs2,off);
                               3:p[i]=bge_(rs1,rs2,off);4:p[i]=bltu_(rs1,rs2,off);default:p[i]=bgeu_(rs1,rs2,off); endcase
           end
        default: p[i]=jal_(rreg(), (($urandom%2)*4)+8);
      endcase
    end
  endtask

  // ---------------- stimulus ----------------
  logic [31:0] prog[];
  logic [31:0] r[0:31];
  logic [31:0] gp[], gr[0:31];
  int n_programs = 30;          // SoC sim is slower; override with +PROGRAMS=
  int mism = 0;

  initial begin
    if ($value$plusargs("PROGRAMS=%d", n_programs)) ;

    // ===================== +DEBUGPROG: cycle-level WB retire trace =====================
    if ($test$plusargs("DEBUGPROG")) begin
      logic [31:0] dp[];
      dp = new[8];
      dp = '{ addi(1,0,7), addi(2,0,11), add_(3,1,2),          // reg forwarding
              addi(4,0,'h40), addi(5,0,'h55), sw_(5,4,0),       // store
              lw_(6,4,0), addi(7,6,1) };                        // load + use
      $display("==== SoC DEBUGPROG: expected retire x1<=7,x2<=11,x3<=18(0x12),");
      $display("     x4<=0x40,x5<=0x55,x6<=0x55,x7<=0x56 ====");
      mon_on = 1; dut_run(dp, 8, r); mon_on = 0;
      $display("---- final regs ----");
      for (int i=1;i<=7;i++) $display("  x%0d = %08x", i, r[i]);
      $finish;
    end

    // --------- directed: ALU / forwarding ---------
    prog='{ addi(1,0,7),addi(2,0,11),add_(3,1,2) };               dut_run(prog,3,r);
      ck_reg(r,3,32'd18,"D ADD+fwd");
    prog='{ addi(1,0,-16),srai(2,1,2),srli(3,1,2),slli(4,1,1) };  dut_run(prog,4,r);
      ck_reg(r,2,32'hFFFFFFFC,"D SRAI"); ck_reg(r,3,32'h3FFFFFFC,"D SRLI"); ck_reg(r,4,32'hFFFFFFE0,"D SLLI");
    prog='{ lui_(1,'h12345),addi(1,1,'h678) };                    dut_run(prog,2,r);
      ck_reg(r,1,32'h12345678,"D LUI+ADDI");
    // --------- directed: D-cache load/store (miss->refill->writeback) ---------
    prog='{ addi(2,0,'h40),addi(1,0,'h123),sw_(1,2,0),lw_(3,2,0) };dut_run(prog,4,r);
      ck_reg(r,3,32'h123,"D SW->LW (cache)");
    prog='{ addi(2,0,'h40),addi(5,0,'h55),sw_(5,2,0),lw_(1,2,0),add_(3,1,1) }; dut_run(prog,5,r);
      ck_reg(r,1,32'h55,"D load"); ck_reg(r,3,32'hAA,"D load-use+cache");
    prog='{ addi(5,0,-1),addi(2,0,'h40),sh_(5,2,0),lh_(1,2,0),lhu_(3,2,0) };   dut_run(prog,5,r);
      ck_reg(r,1,32'hFFFFFFFF,"D LH"); ck_reg(r,3,32'h0000FFFF,"D LHU");
    // store to two different lines -> forces writeback when reused
    prog='{ addi(2,0,'h40),addi(3,0,'h800),addi(10,0,'hAA),addi(11,0,'hBB),
            sw_(10,2,0),sw_(11,3,0),lw_(4,2,0),lw_(5,3,0) };       dut_run(prog,8,r);
      ck_reg(r,4,32'hAA,"D 2-line lw x4"); ck_reg(r,5,32'hBB,"D 2-line lw x5");
    // D-cache EVICTION -> WRITE-BACK -> RE-READ: 0x40 and 0x1040 share index 4
    // (different tag) so the 2nd store evicts the dirty 0x40 line (write-back to
    // DRAM); loading 0x40 then misses and refills from DRAM -> proves the
    // written data actually reached memory (x4 must be 0xAA, not stale/lost).
    prog='{ addi(2,0,'h40), lui_(3,1), addi(3,3,'h40),
            addi(10,0,'hAA), sw_(10,2,0),
            addi(11,0,'hBB), sw_(11,3,0),
            lw_(4,2,0), lw_(5,3,0) };                              dut_run(prog,9,r);
      ck_reg(r,4,32'hAA,"D evict->writeback->reread (0x40)");
      ck_reg(r,5,32'hBB,"D conflicting line (0x1040)");
    // --------- directed: control flow ---------
    prog='{ addi(1,0,5),addi(2,0,5),beq_(1,2,8),addi(3,0,99),addi(4,0,7) };    dut_run(prog,5,r);
      ck_reg(r,3,32'd0,"D BEQ skip"); ck_reg(r,4,32'd7,"D BEQ taken");
    prog='{ jal_(1,8),addi(2,0,99),addi(3,0,7) };                 dut_run(prog,3,r);
      ck_reg(r,1,32'd4,"D JAL link"); ck_reg(r,3,32'd7,"D JAL target");
    prog='{ addi(1,0,0),addi(2,0,4),add_(1,1,2),addi(2,2,-1),bne_(2,0,-8) };   dut_run(prog,5,r);
      ck_reg(r,1,32'd10,"D loop sum");

    // --------- AT-30 random vs ISS (full SoC, real caches/AXI) ---------
    // Each random program is followed by 4 NOPs (so any forward branch/jal in
    // the body lands in padding, never skipping the epilogue) and then a
    // memory READBACK epilogue: lw of the 8-word data window 0x40..0x5c into
    // x16..x23. The all-32-register compare therefore also checks the DATA
    // MEMORY contents (store path, byte/half lanes, dirty data) end-to-end
    // through the cache+AXI, not just the register results.
    begin
      logic [31:0] full[];
      full = new[36];
      for (int k=0;k<n_programs;k++) begin
        bit bad;
        gen_random(24, gp);
        for (int i=0;i<24;i++) full[i] = gp[i];
        for (int i=0;i<4; i++) full[24+i] = NOP;                 // branch/jal landing pad
        for (int j=0;j<8; j++) full[28+j] = lw_(16+j, 0, 'h40 + j*4); // readback -> x16..x23
        dut_run(full, 36, r);
        iss_run(full, 36, gr);
        checks++; bad=1'b0;
        for (int i=0;i<32;i++) if (r[i] !== gr[i]) bad=1'b1;
        if (bad) begin
          errors++; mism++;
          $display("======== SoC COUNTER-EXAMPLE prog#%0d (incl. mem readback) ========", k);
          for (int i=0;i<36;i++) $display("  prog[%0d]=32'h%08x;", i, full[i]);
          for (int i=0;i<32;i++)
            $display("  x%0d:\tDUT=%08x\tISS=%08x%s", i, r[i], gr[i], (r[i]!==gr[i])?"  <-- DIFF":"");
          $display("  (x16..x23 = data words 0x40..0x5c read back through the cache)");
          $finish;
        end
      end
    end

    $display("[tb_rv32_soc] checks=%0d errors=%0d (AT-30 programs=%0d mism=%0d)", checks, errors, n_programs, mism);
    if (errors==0) $display("RESULT: ALL PASS (full SoC: pipeline + I$/D$ + AXI)");
    else           $fatal(1, "RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin #200_000_000; $fatal(1, "TIMEOUT"); end
endmodule
