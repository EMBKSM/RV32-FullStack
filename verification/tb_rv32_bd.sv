// tb_rv32_bd.sv - smoke test for the Block-Design wrapper (RV32_SoC_wrapper).
// The BD is a 1:1 graphical wiring of the already-verified rv32_soc, so this
// just confirms the assembled blocks actually run a program. No debug ports on
// the BD -> observe results in the WAVEFORM (see "what to watch" below).
//
// Program (expected):
//   x1=7  x2=11  x3=18(0x12)  x5=18  x6=19 ;  data mem[0x40]=18
`timescale 1ns/1ps
module tb_rv32_bd;
  logic clk = 0, reset = 1;
  logic        imem_prog_we = 0, dmem_prog_we = 0;
  logic [31:0] imem_prog_addr = 0, imem_prog_data = 0;
  logic [31:0] dmem_prog_addr = 0, dmem_prog_data = 0;

  // ---- DUT: the BD wrapper ----
  RV32_SoC_wrapper dut (
    .clk(clk), .reset(reset),
    .imem_prog_we(imem_prog_we), .imem_prog_addr(imem_prog_addr), .imem_prog_data(imem_prog_data),
    .dmem_prog_we(dmem_prog_we), .dmem_prog_addr(dmem_prog_addr), .dmem_prog_data(dmem_prog_data)
  );

  always #5 clk = ~clk;

  // ---- tiny assembler ----
  function automatic logic [31:0] Itype(int imm,rs1,f3,rd,opc);
    return ((imm & 12'hFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] Stype(int imm,rs2,rs1,f3,opc);
    return (((imm>>5)&7'h7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&5'h1F)<<7)|opc; endfunction
  function automatic logic [31:0] R(int f7,rs2,rs1,f3,rd,opc);
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] Jtype(int imm,rd,opc);
    return (((imm>>20)&1)<<31)|(((imm>>1)&10'h3FF)<<21)|(((imm>>11)&1)<<20)|
           (((imm>>12)&8'hFF)<<12)|(rd<<7)|opc; endfunction
  function automatic logic [31:0] addi(int rd,rs1,imm); return Itype(imm,rs1,0,rd,7'h13); endfunction
  function automatic logic [31:0] add_(int rd,rs1,rs2); return R(0,rs2,rs1,0,rd,7'h33);   endfunction
  function automatic logic [31:0] sw_ (int rs2,rs1,imm);return Stype(imm,rs2,rs1,2,7'h23); endfunction
  function automatic logic [31:0] lw_ (int rd,rs1,imm); return Itype(imm,rs1,2,rd,7'h03);  endfunction
  function automatic logic [31:0] jal_(int rd,off);     return Jtype(off,rd,7'h6F);        endfunction

  logic [31:0] prog [];
  initial begin
    prog = '{ addi(1,0,7), addi(2,0,11), add_(3,1,2),
              addi(4,0,'h40), sw_(3,4,0), lw_(5,4,0),
              addi(6,5,1), jal_(0,0) };          // halt = jal x0,0

    reset = 1; @(negedge clk);
    // preload instruction memory (drive at negedge -> sampled by next posedge)
    for (int i=0;i<prog.size();i++) begin
      imem_prog_we=1; imem_prog_addr=i*4; imem_prog_data=prog[i]; @(negedge clk);
    end
    imem_prog_we=0; @(negedge clk);
    reset = 0;

    repeat (2000) @(posedge clk);                // cache miss/refill stalls inflate cycles
    $display("[tb_rv32_bd] run complete - inspect waveform (pc, register_file writes, dmem[0x40]=0x12)");
    $finish;
  end

  initial begin #500000; $finish; end
endmodule
