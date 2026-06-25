// tb_bcu.sv - self-checking TB for bcu.vhd (branch compare + target + pc_src).
// pc_src = jump | (branch & cond); target = jalr ? (rs1+imm)&~1 : pc+imm.
`timescale 1ns/1ps
module tb_bcu;
  logic [31:0] a_fwd, b_fwd, rs1_fwd, pc, imm, target_addr;
  logic [2:0]  funct3;
  logic        branch, jump, is_jalr, branch_taken, pc_src;
  bcu dut (.a_fwd(a_fwd), .b_fwd(b_fwd), .rs1_fwd(rs1_fwd), .pc(pc), .imm(imm),
           .funct3(funct3), .branch(branch), .jump(jump), .is_jalr(is_jalr),
           .branch_taken(branch_taken), .pc_src(pc_src), .target_addr(target_addr));

  function automatic logic gcond(input logic [31:0] a,b, input logic [2:0] f3);
    case (f3)
      3'b000: return a==b; 3'b001: return a!=b;
      3'b100: return $signed(a) <  $signed(b);
      3'b101: return $signed(a) >= $signed(b);
      3'b110: return a < b;  3'b111: return a >= b;
      default: return 1'b0;
    endcase
  endfunction

  int errors=0, checks=0;
  task automatic ck(input logic [31:0] a,b,r1,p,im, input logic[2:0] f3,
                    input logic br,jp,jr, input string nm);
    logic ec = gcond(a,b,f3);
    logic eps = jp | (br & ec);
    logic [31:0] et = jr ? ((r1+im) & 32'hFFFFFFFE) : (p+im);
    a_fwd=a; b_fwd=b; rs1_fwd=r1; pc=p; imm=im; funct3=f3;
    branch=br; jump=jp; is_jalr=jr; #1; checks++;
    if (branch_taken!==ec || pc_src!==eps || target_addr!==et) begin errors++;
      $error("%s FAIL: cond=%b/%b pc_src=%b/%b tgt=%h/%h",nm,branch_taken,ec,pc_src,eps,target_addr,et); end
  endtask

  initial begin
    ck(5,5,0,0,0,3'b000,1,0,0,"BEQ taken");
    ck(5,6,0,0,0,3'b000,1,0,0,"BEQ ntaken");
    ck(5,6,0,0,0,3'b001,1,0,0,"BNE taken");
    ck(32'hFFFFFFFF,1,0,0,0,3'b100,1,0,0,"BLT -1<1");
    ck(2,1,0,0,0,3'b101,1,0,0,"BGE 2>=1");
    ck(1,32'hFFFFFFFF,0,0,0,3'b110,1,0,0,"BLTU 1<max");
    ck(32'hFFFFFFFF,1,0,0,0,3'b111,1,0,0,"BGEU max>=1");
    ck(0,0,0,32'h1000,32'h20,3'b000,0,1,0,"JAL target pc+imm");
    ck(0,0,32'h1001,0,32'h4,3'b000,0,1,1,"JALR (rs1+imm)&~1");
    for (int i=0;i<8000;i++) begin
      logic [2:0] f3s [0:5] = '{3'b000,3'b001,3'b100,3'b101,3'b110,3'b111};
      ck($urandom,$urandom,$urandom,$urandom&32'hFFFFFFFC,$urandom,
         f3s[$urandom_range(0,5)],$urandom_range(0,1),$urandom_range(0,1),$urandom_range(0,1),"rand");
    end
    // ---- 3-point boundary value analysis (compare around equality + sign edge) ----
    ck(32'd4,32'd5,0,0,0,3'b100,1,0,0,"BVA BLT a=b-1 taken");
    ck(32'd5,32'd5,0,0,0,3'b100,1,0,0,"BVA BLT a=b not");
    ck(32'd6,32'd5,0,0,0,3'b100,1,0,0,"BVA BLT a=b+1 not");
    ck(32'd4,32'd5,0,0,0,3'b000,1,0,0,"BVA BEQ -1 not");
    ck(32'd5,32'd5,0,0,0,3'b000,1,0,0,"BVA BEQ eq taken");
    ck(32'd6,32'd5,0,0,0,3'b000,1,0,0,"BVA BEQ +1 not");
    ck(32'h7FFFFFFF,32'h80000000,0,0,0,3'b100,1,0,0,"BVA BLT signed maxpos<maxneg");
    ck(32'h7FFFFFFF,32'h80000000,0,0,0,3'b110,1,0,0,"BVA BLTU unsigned divergence");

    $display("[tb_bcu] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
