// tb_trap_unit.sv - self-checking TB for trap_unit.vhd (exception detect + precise trap).
// cause priority: misalign(0)>illegal(2)>ebreak(3)>load(4)>store(6)>ecall(11).
// exception->mtvec, MRET->mepc; trap_we only on exception.
`timescale 1ns/1ps
module tb_trap_unit;
  logic illegal_instr, instr_misalign, load_misalign, store_misalign;
  logic is_ecall, is_ebreak, is_mret;
  logic [31:0] instr_pc, fault_addr, mtvec, mepc;
  logic trap_taken, flush_all, trap_we;
  logic [31:0] trap_target, trap_mepc, trap_mcause, trap_mtval;

  trap_unit dut (.illegal_instr(illegal_instr), .instr_misalign(instr_misalign),
    .load_misalign(load_misalign), .store_misalign(store_misalign),
    .is_ecall(is_ecall), .is_ebreak(is_ebreak), .is_mret(is_mret),
    .instr_pc(instr_pc), .fault_addr(fault_addr), .mtvec(mtvec), .mepc(mepc),
    .trap_taken(trap_taken), .trap_target(trap_target), .flush_all(flush_all),
    .trap_we(trap_we), .trap_mepc(trap_mepc), .trap_mcause(trap_mcause), .trap_mtval(trap_mtval));

  int errors=0, checks=0;
  task automatic setf(input logic il,im,lm,sm,ec,eb,mr);
    illegal_instr=il; instr_misalign=im; load_misalign=lm; store_misalign=sm;
    is_ecall=ec; is_ebreak=eb; is_mret=mr;
  endtask
  task automatic ck(input logic cond, input string nm);
    checks++; if(!cond) begin errors++;
      $error("%s FAIL: taken=%b we=%b target=%h cause=%h",nm,trap_taken,trap_we,trap_target,trap_mcause); end
  endtask

  initial begin
    instr_pc=32'h100; fault_addr=32'hABC; mtvec=32'h80; mepc=32'h40;
    setf(0,0,0,0,0,0,0); #1; ck(trap_taken==0 && flush_all==0 && trap_we==0, "no trap");
    setf(1,0,0,0,0,0,0); #1; ck(trap_mcause==32'd2 && trap_taken==1 && trap_target==32'h80, "illegal cause2 ->mtvec");
    setf(0,0,1,0,0,0,0); #1; ck(trap_mcause==32'd4, "load misalign cause4");
    setf(0,0,0,1,0,0,0); #1; ck(trap_mcause==32'd6, "store misalign cause6");
    setf(0,0,0,0,1,0,0); #1; ck(trap_mcause==32'd11, "ecall cause11");
    setf(0,0,0,0,0,1,0); #1; ck(trap_mcause==32'd3, "ebreak cause3");
    setf(0,1,0,0,0,0,0); #1; ck(trap_mcause==32'd0, "instr misalign cause0");
    // priority: instr_misalign over illegal
    setf(1,1,0,0,0,0,0); #1; ck(trap_mcause==32'd0, "misalign>illegal priority");
    // mepc/mtval sources
    setf(1,0,0,0,0,0,0); #1; ck(trap_mepc==32'h100 && trap_mtval==32'hABC, "mepc/mtval src");
    // MRET: taken+flush, target=mepc, no csr write
    setf(0,0,0,0,0,0,1); #1; ck(trap_taken==1 && flush_all==1 && trap_we==0 && trap_target==32'h40, "MRET ->mepc no we");

    // ---- 3-point boundary value analysis (cause priority at adjacent edges) ----
    setf(1,1,0,0,0,0,0); #1; ck(trap_mcause==32'd0, "BVA prio misalign>illegal");
    setf(1,0,0,0,0,1,0); #1; ck(trap_mcause==32'd2, "BVA prio illegal>ebreak");
    setf(0,0,1,0,0,1,0); #1; ck(trap_mcause==32'd3, "BVA prio ebreak>load");
    setf(0,0,1,1,0,0,0); #1; ck(trap_mcause==32'd4, "BVA prio load>store");
    setf(0,0,0,1,1,0,0); #1; ck(trap_mcause==32'd6, "BVA prio store>ecall");

    $display("[tb_trap_unit] checks=%0d errors=%0d", checks, errors);
    if (errors==0) $display("RESULT: ALL PASS"); else $fatal(1,"RESULT: FAIL");
    $finish;
  end
endmodule
