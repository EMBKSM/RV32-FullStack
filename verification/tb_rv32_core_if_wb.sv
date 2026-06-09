// =====================================================================
// tb_rv32_core_if_wb.sv
//   Self-checking SystemVerilog testbench for the integrated IF~WB
//   write-back datapath (rv32_core.vhd).  ATDD: implements acceptance
//   tests AT-01..AT-30 from ip_workspace/if_wb_acceptance_tests.md.
//
//   Methodology:
//     * AT-01..AT-29  directed programs with INDEPENDENT (hand-computed)
//                     expected architectural register state.
//     * AT-30         random RV32I programs compared, register-for-register,
//                     against an independent in-TB ISS golden model
//                     (counter-example search).
//
//   Mixed-language run (VHDL DUT + SV TB) — examples:
//     xsim  : xvhdl ../ip_workspace/0_IF/0_PC/*.vhd \
//                   ../ip_workspace/1_ID/*.vhd ../ip_workspace/2_EX/*.vhd \
//                   ../ip_workspace/3_Mem/read_aligner.vhd \
//                   ../ip_workspace/3_Mem/write_strobe_gen.vhd \
//                   ../ip_workspace/4_WB/result_mux.vhd \
//                   ../ip_workspace/rv32_core.vhd
//             xvlog -sv tb_rv32_core_if_wb.sv
//             xelab tb_rv32_core_if_wb -R
//     questa: vcom <same .vhd list> ; vlog -sv tb_rv32_core_if_wb.sv
//             vsim -c tb_rv32_core_if_wb -do "run -all"
// =====================================================================
`timescale 1ns/1ps
module tb_rv32_core_if_wb;

  // ---------------- clock / reset ----------------
  logic clk = 0, reset = 1;
  always #5 clk = ~clk;                       // 100 MHz

  // ---------------- DUT I/O ----------------
  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_wstrb;
  logic        dmem_we, dmem_re;
  logic        dbg_commit;
  logic [4:0]  dbg_rd, dbg_reg_addr;
  logic [31:0] dbg_wdata, dbg_reg_data;

  // ---------------- memories ----------------
  localparam int IMEM_WORDS = 1024;
  localparam int DMEM_WORDS = 256;
  logic [31:0] imem [0:IMEM_WORDS-1];
  logic [31:0] dmem [0:DMEM_WORDS-1];

  // instruction fetch: ideal combinational read (always hit)
  assign imem_rdata = imem[imem_addr[31:2] % IMEM_WORDS];
  // data read: ideal combinational read
  assign dmem_rdata = dmem[dmem_addr[31:2] % DMEM_WORDS];

  // data write: byte-strobed, on rising edge (mirrors a single-cycle hit)
  always_ff @(posedge clk) begin
    if (dmem_we) begin
      automatic int idx = dmem_addr[31:2] % DMEM_WORDS;
      for (int k = 0; k < 4; k++)
        if (dmem_wstrb[k]) dmem[idx][8*k +: 8] <= dmem_wdata[8*k +: 8];
    end
  end

  // ---------------- DUT ----------------
  rv32_core #(.RESET_ADDR(32'h0000_0000)) dut (
    .clk(clk), .reset(reset),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
    .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_rdata(dmem_rdata),
    .dbg_commit(dbg_commit), .dbg_rd(dbg_rd), .dbg_wdata(dbg_wdata),
    .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data)
  );

  // =================================================================
  // RV32I assembler helpers
  // =================================================================
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

  // =================================================================
  // DUT control: load a program, reset, run, snapshot the register file
  // =================================================================
  int unsigned checks = 0, errors = 0;

  task automatic load_prog(input logic [31:0] prog[], input int n);
    for (int i = 0; i < IMEM_WORDS; i++) imem[i] = NOP;
    for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = 32'h0;
    for (int i = 0; i < n;          i++) imem[i] = prog[i];
  endtask

  task automatic do_reset();
    reset = 1; @(posedge clk); @(posedge clk); reset = 0; @(negedge clk);
  endtask

  task automatic run_cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  task automatic snapshot(output logic [31:0] r[0:31]);
    for (int i = 0; i < 32; i++) begin
      dbg_reg_addr = i[4:0]; #1; r[i] = dbg_reg_data;
    end
  endtask

  // run a program on the DUT and return final architectural registers
  task automatic dut_run(input logic [31:0] prog[], input int n,
                         output logic [31:0] r[0:31]);
    load_prog(prog, n);
    do_reset();
    run_cycles(n*4 + 60);
    snapshot(r);
  endtask

  // =================================================================
  // Independent ISS golden model (sequential, in-order)  -- AT-30
  // =================================================================
  function automatic logic [31:0] g_imm(input logic [31:0] ins, input int opc);
    case (opc)
      OP_ST: return $signed({ins[31:25], ins[11:7]});
      OP_BR: return $signed({ins[31], ins[7], ins[30:25], ins[11:8], 1'b0});
      OP_LUI, OP_AUIPC: return {ins[31:12], 12'h0};
      OP_JAL: return $signed({ins[31], ins[19:12], ins[20], ins[30:21], 1'b0});
      default: return $signed(ins[31:20]);   // I
    endcase
  endfunction

  function automatic logic [31:0] g_load(input logic [31:0] word, input logic [1:0] boff,
                                         input logic [2:0] f3);
    logic [7:0]  bb; logic [15:0] hh;
    bb = word[8*boff +: 8];
    hh = (boff[1]==0) ? word[15:0] : word[31:16];
    case (f3)
      3'b000: return $signed(bb);   // LB
      3'b001: return $signed(hh);   // LH
      3'b010: return word;          // LW
      3'b100: return {24'h0, bb};   // LBU
      3'b101: return {16'h0, hh};   // LHU
      default: return word;
    endcase
  endfunction

  // mem (golden) is a separate array so it cannot alias the DUT's dmem
  logic [31:0] gmem [0:DMEM_WORDS-1];
  task automatic g_store(input logic [31:0] addr, input logic [2:0] f3, input logic [31:0] sd);
    int idx; logic [3:0] wstrb; logic [31:0] wal; logic [1:0] boff;
    idx = (addr>>2) % DMEM_WORDS; boff = addr[1:0];
    case (f3)
      3'b000: begin wstrb = (4'h1<<boff); wal = {4{sd[7:0]}}; end
      3'b001: begin wstrb = (boff[1]==0)?4'h3:4'hC; wal = {2{sd[15:0]}}; end
      3'b010: begin wstrb = 4'hF; wal = sd; end
      default:begin wstrb = 4'h0; wal = sd; end
    endcase
    for (int k=0;k<4;k++) if (wstrb[k]) gmem[idx][8*k +: 8] = wal[8*k +: 8];
  endtask

  task automatic iss_run(input logic [31:0] prog[], input int n,
                         output logic [31:0] reg_[0:31]);
    int pc, opc, f3, rs1, rs2, rd, f7_5, alu_op, ctrl, cnt;
    logic [31:0] ins, imm, a, bb, npc, wd, srca, srcb; bit has_wd, cond;
    for (int i=0;i<32;i++) reg_[i]=0;
    for (int i=0;i<DMEM_WORDS;i++) gmem[i]=0;
    pc = 0; cnt = 0;
    while ((pc>>2) < n && cnt < 4000) begin
      cnt++; ins = prog[pc>>2];
      opc=ins[6:0]; rd=ins[11:7]; f3=ins[14:12]; rs1=ins[19:15]; rs2=ins[24:20];
      f7_5 = (opc==OP_R || (opc==OP_I && f3==3'b101)) ? ins[30] : 0;
      imm = g_imm(ins, opc);
      a = reg_[rs1]; bb = reg_[rs2]; npc = pc+4; has_wd = 0; wd = 0;
      case (opc)
        OP_R, OP_I, OP_LUI, OP_AUIPC: begin
          // derive alu_op then alu_ctrl (mirror control_unit + alu_control)
          if      (opc==OP_LUI)   alu_op=3;
          else if (opc==OP_AUIPC) alu_op=0;
          else                    alu_op=2;   // R / I-ALU funct decode
          if      (alu_op==0) ctrl=0;
          else if (alu_op==3) ctrl=10;
          else case (f3)
            3'b000: ctrl = f7_5 ? 1 : 0;
            3'b001: ctrl = 5;
            3'b010: ctrl = 8;
            3'b011: ctrl = 9;
            3'b100: ctrl = 4;
            3'b101: ctrl = f7_5 ? 7 : 6;
            3'b110: ctrl = 3;
            default:ctrl = 2;
          endcase
          srca = (opc==OP_AUIPC) ? pc : a;
          srcb = (opc==OP_R)     ? bb : imm;
          case (ctrl)
            0: wd = srca + srcb;
            1: wd = srca - srcb;
            2: wd = srca & srcb;
            3: wd = srca | srcb;
            4: wd = srca ^ srcb;
            5: wd = srca << srcb[4:0];
            6: wd = srca >> srcb[4:0];
            7: wd = $signed(srca) >>> srcb[4:0];
            8: wd = ($signed(srca) <  $signed(srcb)) ? 1 : 0;
            9: wd = (srca < srcb) ? 1 : 0;
            10:wd = srcb;
            default: wd = 0;
          endcase
          has_wd = 1;
        end
        OP_LD: begin wd = g_load(gmem[((a+imm)>>2)%DMEM_WORDS], (a+imm)&3, f3); has_wd=1; end
        OP_ST: begin g_store(a+imm, f3, bb); end
        OP_BR: begin
          case (f3)
            3'b000: cond = (a==bb);
            3'b001: cond = (a!=bb);
            3'b100: cond = ($signed(a) <  $signed(bb));
            3'b101: cond = ($signed(a) >= $signed(bb));
            3'b110: cond = (a < bb);
            3'b111: cond = (a >= bb);
            default:cond = 0;
          endcase
          if (cond) npc = pc + imm;
        end
        OP_JAL:  begin wd = pc+4; has_wd=1; npc = pc+imm; end
        OP_JALR: begin wd = pc+4; has_wd=1; npc = (a+imm) & 32'hFFFFFFFE; end
        default: ;  // SYSTEM/FENCE/illegal treated as NOP
      endcase
      if (has_wd && rd!=0) reg_[rd] = wd;
      reg_[0] = 0;
      pc = npc;
    end
  endtask

  // =================================================================
  // Checkers
  // =================================================================
  // directed: compare selected regs to independent expected values
  task automatic ck_reg(input logic [31:0] r[0:31], input int idx,
                        input logic [31:0] exp, input string name);
    checks++;
    if (r[idx] !== exp) begin
      errors++;
      $error("%s FAIL: x%0d=%h expected=%h", name, idx, r[idx], exp);
    end
  endtask

  // =================================================================
  // Stimulus
  // =================================================================
  logic [31:0] prog[];
  logic [31:0] r[0:31];

  // ---- AT-30 random program generation (mirrors run_ifwb_core.py) ----
  function automatic int rrange(int lo, int hi);
    return lo + ($urandom % (hi-lo+1));
  endfunction
  function automatic int rreg();      // x0..x8
    int t = $urandom % 9; return t;
  endfunction
  function automatic int rregnz();    // x1..x8
    return 1 + ($urandom % 8);
  endfunction

  task automatic gen_random(input int len, output logic [31:0] p[]);
    int kind, rd, rs1, rs2, off, base; p = new[len];
    base = 'h40;
    for (int i=0;i<len;i++) begin
      kind = $urandom % 11; rd = rreg(); rs1 = rreg(); rs2 = rreg();
      case (kind)
        0,1: case ($urandom%6)
               0: p[i]=addi (rd,rs1,rrange(-2048,2047));
               1: p[i]=andi (rd,rs1,rrange(-2048,2047));
               2: p[i]=ori_ (rd,rs1,rrange(-2048,2047));
               3: p[i]=xori (rd,rs1,rrange(-2048,2047));
               4: p[i]=slti (rd,rs1,rrange(-2048,2047));
               default: p[i]=sltiu(rd,rs1,rrange(-2048,2047));
             endcase
        2,3: case ($urandom%10)
               0: p[i]=add_ (rd,rs1,rs2); 1: p[i]=sub_(rd,rs1,rs2);
               2: p[i]=and_ (rd,rs1,rs2); 3: p[i]=or_ (rd,rs1,rs2);
               4: p[i]=xor_ (rd,rs1,rs2); 5: p[i]=slt_(rd,rs1,rs2);
               6: p[i]=sltu_(rd,rs1,rs2); 7: p[i]=sll_(rd,rs1,rs2);
               8: p[i]=srl_ (rd,rs1,rs2); default: p[i]=sra_(rd,rs1,rs2);
             endcase
        4: case ($urandom%3)
             0: p[i]=slli(rd,rs1,$urandom%32);
             1: p[i]=srli(rd,rs1,$urandom%32);
             default: p[i]=srai(rd,rs1,$urandom%32);
           endcase
        5: p[i]=lui_  (rd, $urandom & 'hFFFFF);
        6: p[i]=auipc_(rd, $urandom & 'hFFFFF);
        7,8: begin
               off = base + (($urandom%5)*4);
               if ($urandom % 2)
                 case ($urandom%3)
                   0: p[i]=sw_(rregnz(),0,off); 1: p[i]=sb_(rregnz(),0,off);
                   default: p[i]=sh_(rregnz(),0,off);
                 endcase
               else
                 case ($urandom%5)
                   0: p[i]=lw_ (rd,0,off); 1: p[i]=lb_(rd,0,off);
                   2: p[i]=lbu_(rd,0,off); 3: p[i]=lh_(rd,0,off);
                   default: p[i]=lhu_(rd,0,off);
                 endcase
             end
        9: begin
             off = ($urandom%3)*4 + 8;     // forward only: 8/12/16
             case ($urandom%6)
               0: p[i]=beq_(rs1,rs2,off); 1: p[i]=bne_(rs1,rs2,off);
               2: p[i]=blt_(rs1,rs2,off); 3: p[i]=bge_(rs1,rs2,off);
               4: p[i]=bltu_(rs1,rs2,off);default: p[i]=bgeu_(rs1,rs2,off);
             endcase
           end
        default: p[i]=jal_(rreg(), (($urandom%2)*4)+8);   // forward only
      endcase
    end
  endtask

  int n_programs = 500;          // AT-30 sweep size (override with +PROGRAMS=)
  int mism = 0;

  // ---- debug monitors (enabled only during a +DEBUGPROG run) ----
  bit mon_on = 0;
  always @(posedge clk) begin
    if (mon_on && dmem_we)
      $display("[ST ] t=%0t addr=%08x wstrb=%b wdata=%08x", $time, dmem_addr, dmem_wstrb, dmem_wdata);
    if (mon_on && dmem_re)
      $display("[LD ] t=%0t addr=%08x rdata=%08x", $time, dmem_addr, dmem_rdata);
    if (mon_on && dbg_commit)
      $display("[WB ] t=%0t x%0d <= %08x", $time, dbg_rd, dbg_wdata);
  end

  initial begin
    logic [31:0] gp[];
    logic [31:0] gr[0:31];
    if ($value$plusargs("PROGRAMS=%d", n_programs)) ;

    // ===================== +DEBUGPROG: trace the known counter-example =====================
    if ($test$plusargs("DEBUGPROG")) begin
      logic [31:0] dp[];
      dp = new[40];
      dp = '{32'h00139463,32'h0c10e013,32'h04801823,32'h04801823,32'h41535213,
             32'h41615213,32'h04200223,32'h00c0026f,32'h39002013,32'h0001a133,
             32'h0d199197,32'h00744663,32'hfcc300b7,32'hc9b76337,32'h008003ef,
             32'h408000b3,32'h6f606393,32'hba92a413,32'h0041a333,32'h7d2ae417,
             32'h00004133,32'h02b0a3b7,32'h003083b3,32'hac212013,32'h0080016f,
             32'h0073a033,32'h04601223,32'h05002083,32'h4043d413,32'h00739463,
             32'h04501223,32'h0073e863,32'h04800403,32'h0b30a413,32'h04002403,
             32'h04402823,32'h04402203,32'h40a1d393,32'h00817863,32'h0d726293};
      $display("==== DEBUGPROG: store / load / WB trace ====");
      mon_on = 1; dut_run(dp, 40, r); mon_on = 0;
      $display("---- final dmem around 0x40..0x5c ----");
      for (int a = 16; a <= 23; a++)
        $display("  dmem[%0d] (addr 0x%02x) = %08x", a, a*4, dmem[a]);
      $display("---- FINAL x4 = %08x (expected 0) ----", r[4]);
      $finish;
    end

    // ===================== AT-01..AT-29 (directed) =====================
    prog = '{ addi(1,0,5) };                                       dut_run(prog,1,r);
      ck_reg(r,1,32'h5,"AT-01 ADDI");
    prog = '{ addi(2,0,-1) };                                      dut_run(prog,1,r);
      ck_reg(r,2,32'hFFFFFFFF,"AT-02 ADDI -1");
    prog = '{ addi(1,0,7),addi(2,0,11),add_(3,1,2) };              dut_run(prog,3,r);
      ck_reg(r,3,32'd18,"AT-03 ADD+fwd");
    prog = '{ addi(1,0,20),addi(2,0,8),sub_(3,1,2) };              dut_run(prog,3,r);
      ck_reg(r,3,32'd12,"AT-04 SUB");
    prog = '{ addi(1,0,'hF0),andi(2,1,'hFF),ori_(3,1,'h0F),xori(4,1,'hFF) };
      dut_run(prog,4,r);
      ck_reg(r,1,32'hF0,"AT-05a"); ck_reg(r,2,32'hF0,"AT-05b");
      ck_reg(r,3,32'hFF,"AT-05c"); ck_reg(r,4,32'h0F,"AT-05d");
    prog = '{ addi(1,0,-1),slti(2,1,0),sltiu(3,1,0) };             dut_run(prog,3,r);
      ck_reg(r,2,32'd1,"AT-06 SLTI"); ck_reg(r,3,32'd0,"AT-06 SLTIU");
    prog = '{ addi(1,0,-16),srai(2,1,2),srli(3,1,2),slli(4,1,1) }; dut_run(prog,4,r);
      ck_reg(r,2,32'hFFFFFFFC,"AT-07 SRAI"); ck_reg(r,3,32'h3FFFFFFC,"AT-07 SRLI");
      ck_reg(r,4,32'hFFFFFFE0,"AT-07 SLLI");
    prog = '{ lui_(1,'hABCDE) };                                   dut_run(prog,1,r);
      ck_reg(r,1,32'hABCDE000,"AT-08 LUI");
    prog = '{ auipc_(1,'h12345) };                                 dut_run(prog,1,r);
      ck_reg(r,1,32'h12345000,"AT-09 AUIPC");
    prog = '{ lui_(1,'h12345),addi(1,1,'h678) };                   dut_run(prog,2,r);
      ck_reg(r,1,32'h12345678,"AT-10 LUI+ADDI");
    prog = '{ addi(1,0,10),addi(2,1,20) };                         dut_run(prog,2,r);
      ck_reg(r,1,32'd10,"AT-11a"); ck_reg(r,2,32'd30,"AT-11 EX/MEM fwd");
    prog = '{ addi(1,0,10),NOP,add_(2,1,1) };                      dut_run(prog,3,r);
      ck_reg(r,2,32'd20,"AT-12 MEM/WB fwd");
    prog = '{ addi(1,0,3),addi(2,0,4),add_(3,1,2) };               dut_run(prog,3,r);
      ck_reg(r,3,32'd7,"AT-13 dual-stage fwd");
    prog = '{ addi(0,0,123),add_(1,0,0),addi(2,0,5) };             dut_run(prog,3,r);
      ck_reg(r,0,32'd0,"AT-14 x0"); ck_reg(r,1,32'd0,"AT-14 x1"); ck_reg(r,2,32'd5,"AT-14 x2");
    prog = '{ addi(2,0,'h40),addi(1,0,'h123),sw_(1,2,0),lw_(3,2,0) };
      dut_run(prog,4,r);
      ck_reg(r,3,32'h123,"AT-15 SW->LW");
    prog = '{ addi(2,0,'h40),addi(5,0,'h55),sw_(5,2,0),lw_(1,2,0),add_(3,1,1) };
      dut_run(prog,5,r);
      ck_reg(r,1,32'h55,"AT-16 load"); ck_reg(r,3,32'hAA,"AT-16 load-use");
    prog = '{ addi(2,0,'h40),addi(5,0,'hAB),sb_(5,2,0),lbu_(1,2,0) };
      dut_run(prog,4,r);
      ck_reg(r,1,32'hAB,"AT-17 SB/LBU");
    prog = '{ addi(5,0,-1),addi(2,0,'h40),sh_(5,2,0),lh_(1,2,0),lhu_(3,2,0) };
      dut_run(prog,5,r);
      ck_reg(r,1,32'hFFFFFFFF,"AT-18 LH"); ck_reg(r,3,32'h0000FFFF,"AT-18 LHU");
    prog = '{ addi(1,0,5),addi(2,0,5),beq_(1,2,8),addi(3,0,99),addi(4,0,7) };
      dut_run(prog,5,r);
      ck_reg(r,3,32'd0,"AT-19 BEQ skip"); ck_reg(r,4,32'd7,"AT-19 BEQ taken");
    prog = '{ addi(1,0,5),addi(2,0,6),beq_(1,2,8),addi(3,0,99),addi(4,0,7) };
      dut_run(prog,5,r);
      ck_reg(r,3,32'd99,"AT-20 BEQ ntaken"); ck_reg(r,4,32'd7,"AT-20");
    prog = '{ addi(1,0,5),addi(2,0,6),bne_(1,2,8),addi(3,0,99),addi(4,0,1) };
      dut_run(prog,5,r);
      ck_reg(r,3,32'd0,"AT-21 BNE skip"); ck_reg(r,4,32'd1,"AT-21");
    prog = '{ addi(1,0,-1),addi(2,0,1),blt_(1,2,8),addi(3,0,99),addi(4,0,2) };
      dut_run(prog,5,r);
      ck_reg(r,3,32'd0,"AT-22 BLT skip"); ck_reg(r,4,32'd2,"AT-22");
    prog = '{ addi(1,0,-1),addi(2,0,1),bltu_(1,2,8),addi(3,0,99),addi(4,0,3) };
      dut_run(prog,5,r);
      ck_reg(r,3,32'd99,"AT-23 BLTU ntaken"); ck_reg(r,4,32'd3,"AT-23");
    prog = '{ addi(1,0,5),addi(2,1,0),beq_(1,2,8),addi(3,0,99),addi(4,0,4) };
      dut_run(prog,5,r);
      ck_reg(r,3,32'd0,"AT-24 fwd->BCU skip"); ck_reg(r,4,32'd4,"AT-24");
    prog = '{ jal_(1,8),addi(2,0,99),addi(3,0,7) };                dut_run(prog,3,r);
      ck_reg(r,1,32'd4,"AT-25 JAL link"); ck_reg(r,2,32'd0,"AT-25 skip"); ck_reg(r,3,32'd7,"AT-25");
    prog = '{ addi(1,0,12),jalr_(2,1,0),addi(3,0,99),addi(4,0,5) };dut_run(prog,4,r);
      ck_reg(r,2,32'd8,"AT-26 JALR link"); ck_reg(r,3,32'd0,"AT-26 skip"); ck_reg(r,4,32'd5,"AT-26");
    prog = '{ addi(1,0,1),addi(2,1,1),addi(3,2,1),addi(4,3,1) };   dut_run(prog,4,r);
      ck_reg(r,1,32'd1,"AT-27a"); ck_reg(r,2,32'd2,"AT-27b");
      ck_reg(r,3,32'd3,"AT-27c"); ck_reg(r,4,32'd4,"AT-27 chain");
    prog = '{ addi(1,0,0),addi(2,0,4),add_(1,1,2),addi(2,2,-1),bne_(2,0,-8) };
      dut_run(prog,5,r);
      ck_reg(r,1,32'd10,"AT-28 loop sum"); ck_reg(r,2,32'd0,"AT-28 loop done");
    prog = '{ addi(2,0,'h40),addi(3,0,'h44),addi(10,0,'hAA),addi(11,0,'hBB),
              sw_(10,2,0),sw_(11,3,0),lw_(4,2,0),lw_(5,3,0) };     dut_run(prog,8,r);
      ck_reg(r,4,32'hAA,"AT-29 lw x4"); ck_reg(r,5,32'hBB,"AT-29 lw x5");

    // ===================== 3-point boundary value analysis (integration) =====================
    // I-type signed immediate edge: +2046 / +2047(max) / -2048(min)
    prog = '{ addi(1,0,2046), addi(2,0,2047), addi(3,0,-2048) }; dut_run(prog,3,r);
      ck_reg(r,1,32'd2046,    "BVA imm +2046");
      ck_reg(r,2,32'd2047,    "BVA imm +2047 (max+)");
      ck_reg(r,3,32'hFFFFF800,"BVA imm -2048 (min-)");
    // load sign edge: store 0x80, LB sign-extends (-128), LBU zero-extends (+128)
    prog = '{ addi(2,0,'h40), addi(5,0,'h80), sb_(5,2,0), lb_(1,2,0), lbu_(3,2,0) }; dut_run(prog,5,r);
      ck_reg(r,1,32'hFFFFFF80,"BVA LB sign -128");
      ck_reg(r,3,32'h00000080,"BVA LBU +128");
    // shift-amount edge: shamt 30 / 31 (max)
    prog = '{ addi(1,0,1), slli(2,1,30), slli(3,1,31) }; dut_run(prog,3,r);
      ck_reg(r,2,32'h40000000,"BVA SLLI sh=30");
      ck_reg(r,3,32'h80000000,"BVA SLLI sh=31 (max)");

    // ===================== timing-issue tests (pipeline cycle timing) =====================
    // Two consecutive load-use hazards: each must insert exactly 1 bubble then
    // forward the loaded value from MEM/WB into EX (stall+forward interplay).
    prog = '{ addi(2,0,'h40), addi(6,0,'h11), sw_(6,2,0),
              lw_(1,2,0), addi(3,1,1),       // load-use #1 (x1 -> immediate use)
              lw_(4,2,0), addi(5,4,2) };     // load-use #2 (x4 -> immediate use)
      dut_run(prog,7,r);
      ck_reg(r,1,32'h11,"TIMING load #1 value");
      ck_reg(r,3,32'h12,"TIMING load-use #1 (0x11+1 via MEM/WB fwd)");
      ck_reg(r,4,32'h11,"TIMING load #2 value");
      ck_reg(r,5,32'h13,"TIMING load-use #2 (0x11+2 via MEM/WB fwd)");
    // Branch resolved in EX must flush exactly 2 instructions (2-bubble);
    // the two skipped slots must NOT commit.
    prog = '{ addi(1,0,1), addi(2,0,1), beq_(1,2,12),  // taken: skip next two
              addi(9,0,99), addi(8,0,88),               // both squashed
              addi(7,0,7) };                            // branch target
      dut_run(prog,6,r);
      ck_reg(r,9,32'd0,"TIMING branch 2-bubble: slot1 squashed");
      ck_reg(r,8,32'd0,"TIMING branch 2-bubble: slot2 squashed");
      ck_reg(r,7,32'd7,"TIMING branch target executes");

    // ===================== AT-30 random counter-example =====================
    // On the FIRST mismatching program, dump the whole program (copy-pasteable)
    // plus the full DUT-vs-ISS register file, then stop -- this gives a single
    // reproducible counter-example to analyse instead of a flood of reg diffs.
    for (int k = 0; k < n_programs; k++) begin
      bit bad;
      gen_random(40, gp);
      dut_run(gp, 40, r);
      iss_run(gp, 40, gr);
      checks++;
      bad = 1'b0;
      for (int i = 0; i < 32; i++) if (r[i] !== gr[i]) bad = 1'b1;
      if (bad) begin
        errors++; mism++;
        $display("======== AT-30 COUNTER-EXAMPLE prog#%0d ========", k);
        $display("---- program (40 words, copy-paste) ----");
        for (int i = 0; i < 40; i++)
          $display("  prog[%0d]=32'h%08x;", i, gp[i]);
        $display("---- register file (xN: DUT vs ISS) ----");
        for (int i = 0; i < 32; i++)
          $display("  x%0d:\tDUT=%08x\tISS=%08x%s", i, r[i], gr[i],
                   (r[i] !== gr[i]) ? "   <-- DIFF" : "");
        $display("======== stopping at first counter-example ========");
        $finish;
      end
    end

    // ===================== verdict =====================
    $display("[tb_rv32_core_if_wb] checks=%0d errors=%0d (AT-30 programs=%0d mism=%0d)",
             checks, errors, n_programs, mism);
    if (errors == 0) $display("RESULT: ALL PASS (AT-01..AT-30, IF~WB write path)");
    else             $fatal(1, "RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  // global watchdog
  initial begin
    #50_000_000;
    $fatal(1, "TIMEOUT");
  end

endmodule
