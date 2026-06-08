#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_ifwb_core.py - IF~WB write-path integration acceptance harness (ATDD).

Two independent models:
  * Pipeline   : cycle-accurate model that MIRRORS rv32_core.vhd exactly
                 (IF/ID, ID/EX, EX/MEM, MEM/WB regs; EX/MEM & MEM/WB
                 forwarding; load-use 1-bubble stall; branch/jump resolved
                 in EX with 2-bubble flush; write-first register file).
  * ISS        : independent sequential reference (executes one instruction
                 at a time, in program order) used as the golden model for
                 the AT-30 random counter-example sweep.

Directed tests AT-01..AT-29 use INDEPENDENT hand-computed expected register
state (see ip_workspace/if_wb_acceptance_tests.md). AT-30 runs random RV32I
programs on the pipeline and compares the final architectural register file
to the ISS, bit-for-bit. --bug injects integration faults to prove the tests
catch them.

This is model-based verification (logic/protocol). Final HDL sign-off is the
SystemVerilog testbench (verification/tb_rv32_core_if_wb.sv) under xsim/Questa.
"""
import argparse
import random

M32 = (1 << 32) - 1
NOP = 0x00000013                 # addi x0,x0,0
NWORDS = 256                     # shared data-memory size (words)


# =====================================================================
# Assembler helpers (build instruction words)
# =====================================================================
def _u(x):  return x & M32
def R(funct7, rs2, rs1, funct3, rd, opc):
    return _u((funct7 << 25)|(rs2 << 20)|(rs1 << 15)|(funct3 << 12)|(rd << 7)|opc)
def I(imm, rs1, funct3, rd, opc):
    return _u(((imm & 0xFFF) << 20)|(rs1 << 15)|(funct3 << 12)|(rd << 7)|opc)
def S(imm, rs2, rs1, funct3, opc):
    imm &= 0xFFF
    return _u(((imm >> 5) << 25)|(rs2 << 20)|(rs1 << 15)|(funct3 << 12)|((imm & 0x1F) << 7)|opc)
def B(imm, rs2, rs1, funct3, opc):
    imm &= 0x1FFF
    b12=(imm>>12)&1; b11=(imm>>11)&1; b10_5=(imm>>5)&0x3F; b4_1=(imm>>1)&0xF
    return _u((b12<<31)|(b10_5<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(b4_1<<8)|(b11<<7)|opc)
def Utype(imm, rd, opc):
    return _u((imm & 0xFFFFF) << 12 | (rd << 7) | opc)
def J(imm, rd, opc):
    imm &= 0x1FFFFF
    b20=(imm>>20)&1; b10_1=(imm>>1)&0x3FF; b11=(imm>>11)&1; b19_12=(imm>>12)&0xFF
    return _u((b20<<31)|(b10_1<<21)|(b11<<20)|(b19_12<<12)|(rd<<7)|opc)

OP_R=0x33; OP_I=0x13; OP_LD=0x03; OP_ST=0x23; OP_BR=0x63
OP_JAL=0x6F; OP_JALR=0x67; OP_LUI=0x37; OP_AUIPC=0x17

# convenience mnemonics
def addi(rd,rs1,imm): return I(imm,rs1,0,rd,OP_I)
def andi(rd,rs1,imm): return I(imm,rs1,7,rd,OP_I)
def ori (rd,rs1,imm): return I(imm,rs1,6,rd,OP_I)
def xori(rd,rs1,imm): return I(imm,rs1,4,rd,OP_I)
def slti(rd,rs1,imm): return I(imm,rs1,2,rd,OP_I)
def sltiu(rd,rs1,imm):return I(imm,rs1,3,rd,OP_I)
def slli(rd,rs1,sh):  return I(sh & 0x1F,rs1,1,rd,OP_I)
def srli(rd,rs1,sh):  return I(sh & 0x1F,rs1,5,rd,OP_I)
def srai(rd,rs1,sh):  return I(0x400|(sh & 0x1F),rs1,5,rd,OP_I)
def add (rd,rs1,rs2): return R(0,rs2,rs1,0,rd,OP_R)
def sub (rd,rs1,rs2): return R(0x20,rs2,rs1,0,rd,OP_R)
def sll (rd,rs1,rs2): return R(0,rs2,rs1,1,rd,OP_R)
def slt (rd,rs1,rs2): return R(0,rs2,rs1,2,rd,OP_R)
def sltu(rd,rs1,rs2): return R(0,rs2,rs1,3,rd,OP_R)
def xor_(rd,rs1,rs2): return R(0,rs2,rs1,4,rd,OP_R)
def srl (rd,rs1,rs2): return R(0,rs2,rs1,5,rd,OP_R)
def sra (rd,rs1,rs2): return R(0x20,rs2,rs1,5,rd,OP_R)
def or_ (rd,rs1,rs2): return R(0,rs2,rs1,6,rd,OP_R)
def and_(rd,rs1,rs2): return R(0,rs2,rs1,7,rd,OP_R)
def lw  (rd,rs1,imm): return I(imm,rs1,2,rd,OP_LD)
def lb  (rd,rs1,imm): return I(imm,rs1,0,rd,OP_LD)
def lbu (rd,rs1,imm): return I(imm,rs1,4,rd,OP_LD)
def lh  (rd,rs1,imm): return I(imm,rs1,1,rd,OP_LD)
def lhu (rd,rs1,imm): return I(imm,rs1,5,rd,OP_LD)
def sw  (rs2,rs1,imm):return S(imm,rs2,rs1,2,OP_ST)
def sb  (rs2,rs1,imm):return S(imm,rs2,rs1,0,OP_ST)
def sh  (rs2,rs1,imm):return S(imm,rs2,rs1,1,OP_ST)
def beq (rs1,rs2,off):return B(off,rs2,rs1,0,OP_BR)
def bne (rs1,rs2,off):return B(off,rs2,rs1,1,OP_BR)
def blt (rs1,rs2,off):return B(off,rs2,rs1,4,OP_BR)
def bge (rs1,rs2,off):return B(off,rs2,rs1,5,OP_BR)
def bltu(rs1,rs2,off):return B(off,rs2,rs1,6,OP_BR)
def bgeu(rs1,rs2,off):return B(off,rs2,rs1,7,OP_BR)
def lui (rd,imm20):   return Utype(imm20,rd,OP_LUI)
def auipc(rd,imm20):  return Utype(imm20,rd,OP_AUIPC)
def jal (rd,off):     return J(off,rd,OP_JAL)
def jalr(rd,rs1,imm): return I(imm,rs1,0,rd,OP_JALR)


# =====================================================================
# Shared combinational primitives (identical in ISS and pipeline & TB)
# =====================================================================
def s32(a): return a - (1 << 32) if a & 0x80000000 else a

def alu_op_exec(ctrl, a, b):
    sh = b & 0x1F
    if   ctrl == 0x0: return (a + b) & M32
    elif ctrl == 0x1: return (a - b) & M32
    elif ctrl == 0x2: return (a & b) & M32
    elif ctrl == 0x3: return (a | b) & M32
    elif ctrl == 0x4: return (a ^ b) & M32
    elif ctrl == 0x5: return (a << sh) & M32
    elif ctrl == 0x6: return (a >> sh) & M32
    elif ctrl == 0x7: return (s32(a) >> sh) & M32
    elif ctrl == 0x8: return 1 if s32(a) < s32(b) else 0
    elif ctrl == 0x9: return 1 if a < b else 0
    elif ctrl == 0xA: return b & M32
    return 0

def alu_control(alu_op, funct3, funct7_5):
    if alu_op == 0: return 0x0          # ADD
    if alu_op == 1: return 0x1          # SUB
    if alu_op == 3: return 0xA          # Bpass
    return {0:0x1 if funct7_5 else 0x0, 1:0x5, 2:0x8, 3:0x9,
            4:0x4, 5:0x7 if funct7_5 else 0x6, 6:0x3, 7:0x2}[funct3]

def imm_gen(instr, opc):
    f = lambda hi, lo: (instr >> lo) & ((1 << (hi-lo+1)) - 1)
    def sx(v, bits): return v - (1 << bits) if (v >> (bits-1)) & 1 else v
    if opc == OP_ST:  return sx((f(31,25) << 5) | f(11,7), 12) & M32
    if opc == OP_BR:  return sx((f(31,31)<<12)|(f(7,7)<<11)|(f(30,25)<<5)|(f(11,8)<<1), 13) & M32
    if opc in (OP_LUI, OP_AUIPC): return (instr & 0xFFFFF000) & M32
    if opc == OP_JAL: return sx((f(31,31)<<20)|(f(19,12)<<12)|(f(20,20)<<11)|(f(30,21)<<1), 21) & M32
    return sx(f(31,20), 12) & M32       # I (incl. JALR/Load)

def read_aligner(word, boff, f3):
    b = (word >> (8*boff)) & 0xFF
    h = word & 0xFFFF if (boff & 2) == 0 else (word >> 16) & 0xFFFF
    def sx(v, bits): return v - (1 << bits) if (v >> (bits-1)) & 1 else v
    if f3 == 0: return sx(b, 8) & M32   # LB
    if f3 == 1: return sx(h, 16) & M32  # LH
    if f3 == 2: return word & M32       # LW
    if f3 == 4: return b                # LBU
    if f3 == 5: return h                # LHU
    return word & M32

def write_strobe(f3, boff, sd):
    if f3 == 0:  # SB
        return {0:0x1,1:0x2,2:0x4,3:0x8}[boff], ((sd & 0xFF) * 0x01010101) & M32
    if f3 == 1:  # SH
        return (0x3 if (boff & 2) == 0 else 0xC), ((sd & 0xFFFF) * 0x00010001) & M32
    if f3 == 2:  # SW
        return 0xF, sd & M32
    return 0x0, sd & M32

def mem_load(mem, addr, f3):
    return read_aligner(mem[(addr >> 2) % NWORDS], addr & 3, f3)

def mem_store(mem, addr, f3, data):
    idx = (addr >> 2) % NWORDS
    wstrb, wal = write_strobe(f3, addr & 3, data)
    w = mem[idx]
    for k in range(4):
        if (wstrb >> k) & 1:
            w = (w & ~(0xFF << (8*k))) | (((wal >> (8*k)) & 0xFF) << (8*k))
    mem[idx] = w & M32

def decode(instr):
    """Return control dict mirroring control_unit.vhd + field extraction."""
    opc = instr & 0x7F
    rd  = (instr >> 7) & 0x1F
    f3  = (instr >> 12) & 0x7
    rs1 = (instr >> 15) & 0x1F
    rs2 = (instr >> 20) & 0x1F
    # funct7[5] gating: only R-type and I-type SRLI/SRAI(funct3=101) encode it;
    # for ADDI(funct3=000) instr[30] is an immediate bit and must be 0.
    f7_5 = (instr >> 30) & 1 if (opc == OP_R or (opc == OP_I and f3 == 5)) else 0
    c = dict(opc=opc, rd=rd, f3=f3, rs1=rs1, rs2=rs2, f7_5=f7_5,
             reg_write=0, mem_read=0, mem_write=0, alu_src=0, src_a=0,
             branch=0, jump=0, jalr=0, alu_op=0, result_src=0)
    if   opc == OP_R:    c.update(reg_write=1, alu_op=2)
    elif opc == OP_I:    c.update(reg_write=1, alu_src=1, alu_op=2)
    elif opc == OP_LD:   c.update(reg_write=1, alu_src=1, mem_read=1, result_src=1, alu_op=0)
    elif opc == OP_ST:   c.update(alu_src=1, mem_write=1, alu_op=0)
    elif opc == OP_BR:   c.update(branch=1, alu_op=1)
    elif opc == OP_JAL:  c.update(reg_write=1, jump=1, src_a=1, alu_src=1, result_src=2)
    elif opc == OP_JALR: c.update(reg_write=1, jump=1, jalr=1, alu_src=1, result_src=2)
    elif opc == OP_LUI:  c.update(reg_write=1, alu_src=1, alu_op=3)
    elif opc == OP_AUIPC:c.update(reg_write=1, src_a=1, alu_src=1, alu_op=0)
    # SYSTEM/FENCE/illegal: out of this integration's scope -> treated as NOP
    return c


# =====================================================================
# Independent ISS golden (sequential, one instruction at a time)
# =====================================================================
def iss_run(prog, max_instr=2000):
    reg = [0]*32
    mem = [0]*NWORDS
    pc = 0
    n = len(prog)
    for _ in range(max_instr):
        if (pc >> 2) >= n or pc < 0:
            break
        instr = prog[pc >> 2]
        c = decode(instr)
        imm = imm_gen(instr, c['opc'])
        a = reg[c['rs1']]; b = reg[c['rs2']]
        npc = (pc + 4) & M32
        wd = None
        if c['opc'] in (OP_R, OP_I, OP_LUI, OP_AUIPC):
            srca = pc if c['src_a'] else a
            srcb = imm if c['alu_src'] else b
            ctrl = alu_control(c['alu_op'], c['f3'], c['f7_5'])
            wd = alu_op_exec(ctrl, srca, srcb)
        elif c['opc'] == OP_LD:
            addr = (a + imm) & M32
            wd = mem_load(mem, addr, c['f3'])
        elif c['opc'] == OP_ST:
            addr = (a + imm) & M32
            mem_store(mem, addr, c['f3'], b)
        elif c['opc'] == OP_BR:
            sa, sb = s32(a), s32(b)
            cond = {0:a==b,1:a!=b,4:sa<sb,5:sa>=sb,6:a<b,7:a>=b}.get(c['f3'], False)
            if cond: npc = (pc + imm) & M32
        elif c['opc'] == OP_JAL:
            wd = (pc + 4) & M32; npc = (pc + imm) & M32
        elif c['opc'] == OP_JALR:
            wd = (pc + 4) & M32; npc = (a + imm) & M32 & 0xFFFFFFFE
        if wd is not None and c['reg_write'] and c['rd'] != 0:
            reg[c['rd']] = wd & M32
        reg[0] = 0
        pc = npc
    return reg


# =====================================================================
# Cycle-accurate pipeline model (mirrors rv32_core.vhd)
# =====================================================================
class Pipeline:
    def __init__(self, prog, bug=None):
        self.prog = prog
        self.bug = bug
        self.reg = [0]*32
        self.mem = [0]*NWORDS
        self.pc = 0
        # pipeline registers
        self.ifid = dict(pc=0, pc4=0, instr=NOP)
        self.idex = self._idex_bubble()
        self.exmem = dict(alu=0, store=0, pc4=0, rd=0, f3=0,
                          reg_write=0, mem_read=0, mem_write=0, result_src=0)
        self.memwb = dict(read_data=0, alu=0, pc4=0, rd=0, reg_write=0, result_src=0)

    def _idex_bubble(self):
        return dict(pc=0, pc4=0, rs1d=0, rs2d=0, imm=0, rs1=0, rs2=0, rd=0,
                    f3=0, f7_5=0, jalr=0, reg_write=0, mem_read=0, mem_write=0,
                    alu_src=0, src_a=0, branch=0, jump=0, alu_op=0, result_src=0)

    def imem(self, pc):
        idx = pc >> 2
        return self.prog[idx] if 0 <= idx < len(self.prog) else NOP

    def cycle(self):
        b = self.bug
        x0hw = (b != 'x0')   # x0 read/forward hardwiring (disabled by x0 fault)
        # ---------- WB (comb) ----------
        mw = self.memwb
        if mw['result_src'] == 0:   wb = mw['alu']
        elif mw['result_src'] == 1: wb = mw['read_data']
        elif mw['result_src'] == 2: wb = mw['pc4']
        else:                       wb = mw['alu']
        wb &= M32
        wb_we = mw['reg_write']; wb_rd = mw['rd']

        # ---------- ID (comb) ----------
        instr = self.ifid['instr']
        c = decode(instr)
        imm = imm_gen(instr, c['opc'])
        # register read with write-first bypass (mirrors register_file.vhd)
        def rf_read(a):
            if a == 0 and x0hw: return 0
            if wb_we and (wb_rd != 0 or not x0hw) and wb_rd == a: return wb
            return self.reg[a]
        id_rs1d = rf_read(c['rs1']); id_rs2d = rf_read(c['rs2'])

        # ---------- hazard (comb) ----------
        idex = self.idex
        load_use = 1 if (idex['mem_read'] == 1 and idex['rd'] != 0 and
                         (idex['rd'] == c['rs1'] or idex['rd'] == c['rs2'])) else 0
        if b == 'hazard':
            load_use = 0                      # FAULT: drop load-use stall

        # ---------- EX (comb) ----------
        em = self.exmem
        def fwd(rs):
            if em['reg_write'] and (em['rd'] != 0 or not x0hw) and em['rd'] == rs: return '10'
            if wb_we and (wb_rd != 0 or not x0hw) and wb_rd == rs: return '01'
            return '00'
        fa = fwd(idex['rs1']); fb = fwd(idex['rs2'])
        if b == 'forward':
            fa = fb = '00'                    # FAULT: disable forwarding
        fa_val = em['alu'] if fa == '10' else wb if fa == '01' else idex['rs1d']
        fb_val = em['alu'] if fb == '10' else wb if fb == '01' else idex['rs2d']
        srca = idex['pc'] if idex['src_a'] else fa_val
        srcb = idex['imm'] if idex['alu_src'] else fb_val
        ctrl = alu_control(idex['alu_op'], idex['f3'], idex['f7_5'])
        alu_res = alu_op_exec(ctrl, srca & M32, srcb & M32)
        # BCU
        sa, sb = s32(fa_val), s32(fb_val)
        cond = {0:fa_val==fb_val,1:fa_val!=fb_val,4:sa<sb,5:sa>=sb,
                6:fa_val<fb_val,7:fa_val>=fb_val}.get(idex['f3'], False)
        pc_src = 1 if (idex['jump'] or (idex['branch'] and cond)) else 0
        if b == 'branch':
            pc_src = 0                        # FAULT: never redirect/flush
        if idex['jalr']:
            target = (fa_val + idex['imm']) & M32 & 0xFFFFFFFE
        else:
            target = (idex['pc'] + idex['imm']) & M32

        # ---------- MEM (comb) ----------
        addr = em['alu']
        word = self.mem[(addr >> 2) % NWORDS]
        read_data = read_aligner(word, addr & 3, em['f3'])

        # ---------- next-state ----------
        # PC
        if pc_src:
            next_pc = target
        elif load_use:
            next_pc = self.pc          # hold
        else:
            next_pc = (self.pc + 4) & M32

        # IF/ID next
        cur_fetch = self.imem(self.pc)
        if pc_src:
            ifid_n = dict(pc=self.pc, pc4=(self.pc+4)&M32, instr=NOP)
        elif load_use:
            ifid_n = dict(self.ifid)   # hold
        else:
            ifid_n = dict(pc=self.pc, pc4=(self.pc+4)&M32, instr=cur_fetch)

        # ID/EX next
        bubble = load_use or pc_src
        idex_n = dict(pc=self.ifid['pc'], pc4=self.ifid['pc4'],
                      rs1d=id_rs1d, rs2d=id_rs2d, imm=imm,
                      rs1=c['rs1'], rs2=c['rs2'], rd=c['rd'],
                      f3=c['f3'], f7_5=c['f7_5'], jalr=c['jalr'])
        if bubble:
            idex_n.update(reg_write=0, mem_read=0, mem_write=0, alu_src=0,
                          src_a=0, branch=0, jump=0, alu_op=0, result_src=0)
        else:
            idex_n.update(reg_write=c['reg_write'], mem_read=c['mem_read'],
                          mem_write=c['mem_write'], alu_src=c['alu_src'],
                          src_a=c['src_a'], branch=c['branch'], jump=c['jump'],
                          alu_op=c['alu_op'], result_src=c['result_src'])

        # EX/MEM next
        exmem_n = dict(alu=alu_res, store=fb_val & M32, pc4=idex['pc4'],
                       rd=idex['rd'], f3=idex['f3'], reg_write=idex['reg_write'],
                       mem_read=idex['mem_read'], mem_write=idex['mem_write'],
                       result_src=idex['result_src'])

        # MEM/WB next
        memwb_n = dict(read_data=read_data, alu=em['alu'], pc4=em['pc4'],
                       rd=em['rd'], reg_write=em['reg_write'],
                       result_src=em['result_src'])

        # ---------- clocked side effects ----------
        # data memory store (MEM stage, sync)
        if em['mem_write']:
            mem_store(self.mem, addr, em['f3'], em['store'])
        # register file write (WB stage, sync)
        allow_x0 = (b == 'x0')
        if wb_we and (wb_rd != 0 or allow_x0):
            self.reg[wb_rd] = wb
        if not allow_x0:
            self.reg[0] = 0

        # commit registers
        self.pc = next_pc
        self.ifid = ifid_n
        self.idex = idex_n
        self.exmem = exmem_n
        self.memwb = memwb_n

    def run(self, cycles):
        for _ in range(cycles):
            self.cycle()
        self.reg[0] = 0
        return self.reg


def run_pipeline(prog, bug=None, cycles=None):
    if cycles is None:
        cycles = len(prog) * 4 + 60
    p = Pipeline(prog, bug=bug)
    return p.run(cycles)


# =====================================================================
# Directed acceptance tests AT-01..AT-29 (independent expected state)
# =====================================================================
def at_directed(bug=None):
    """Each entry: (id, program, {reg: expected}). Expected = hand-computed."""
    cases = []
    cases.append(("AT-01 ADDI", [addi(1,0,5)], {1:5}))
    cases.append(("AT-02 ADDI -1", [addi(2,0,-1)], {2:0xFFFFFFFF}))
    cases.append(("AT-03 ADD+fwd", [addi(1,0,7), addi(2,0,11), add(3,1,2)], {1:7,2:11,3:18}))
    cases.append(("AT-04 SUB", [addi(1,0,20), addi(2,0,8), sub(3,1,2)], {3:12}))
    cases.append(("AT-05 AND/OR/XOR",
                  [addi(1,0,0xF0), andi(2,1,0xFF), ori(3,1,0x0F), xori(4,1,0xFF)],
                  {1:0xF0,2:0xF0,3:0xFF,4:0x0F}))
    cases.append(("AT-06 SLTI/SLTIU", [addi(1,0,-1), slti(2,1,0), sltiu(3,1,0)], {2:1,3:0}))
    cases.append(("AT-07 shifts",
                  [addi(1,0,-16), srai(2,1,2), srli(3,1,2), slli(4,1,1)],
                  {2:0xFFFFFFFC,3:0x3FFFFFFC,4:0xFFFFFFE0}))
    cases.append(("AT-08 LUI", [lui(1,0xABCDE)], {1:0xABCDE000}))
    cases.append(("AT-09 AUIPC@0", [auipc(1,0x12345)], {1:0x12345000}))
    cases.append(("AT-10 LUI+ADDI", [lui(1,0x12345), addi(1,1,0x678)], {1:0x12345678}))
    cases.append(("AT-11 EX/MEM fwd", [addi(1,0,10), addi(2,1,20)], {1:10,2:30}))
    cases.append(("AT-12 MEM/WB fwd", [addi(1,0,10), NOP, add(2,1,1)], {2:20}))
    cases.append(("AT-13 dual-stage fwd", [addi(1,0,3), addi(2,0,4), add(3,1,2)], {3:7}))
    cases.append(("AT-14 x0 hardwired",
                  [addi(0,0,123), add(1,0,0), addi(2,0,5)], {0:0,1:0,2:5}))
    cases.append(("AT-15 SW->LW",
                  [addi(2,0,0x40), addi(1,0,0x123), sw(1,2,0), lw(3,2,0)], {3:0x123}))
    cases.append(("AT-16 load-use",
                  [addi(2,0,0x40), addi(5,0,0x55), sw(5,2,0), lw(1,2,0), add(3,1,1)],
                  {1:0x55,3:0xAA}))
    cases.append(("AT-17 SB/LBU",
                  [addi(2,0,0x40), addi(5,0,0xAB), sb(5,2,0), lbu(1,2,0)], {1:0xAB}))
    cases.append(("AT-18 SH/LH/LHU",
                  [addi(5,0,-1), addi(2,0,0x40), sh(5,2,0), lh(1,2,0), lhu(3,2,0)],
                  {1:0xFFFFFFFF,3:0x0000FFFF}))
    cases.append(("AT-19 BEQ taken",
                  [addi(1,0,5), addi(2,0,5), beq(1,2,8), addi(3,0,99), addi(4,0,7)],
                  {3:0,4:7}))
    cases.append(("AT-20 BEQ not-taken",
                  [addi(1,0,5), addi(2,0,6), beq(1,2,8), addi(3,0,99), addi(4,0,7)],
                  {3:99,4:7}))
    cases.append(("AT-21 BNE taken",
                  [addi(1,0,5), addi(2,0,6), bne(1,2,8), addi(3,0,99), addi(4,0,1)],
                  {3:0,4:1}))
    cases.append(("AT-22 BLT taken",
                  [addi(1,0,-1), addi(2,0,1), blt(1,2,8), addi(3,0,99), addi(4,0,2)],
                  {3:0,4:2}))
    cases.append(("AT-23 BLTU not-taken",
                  [addi(1,0,-1), addi(2,0,1), bltu(1,2,8), addi(3,0,99), addi(4,0,3)],
                  {3:99,4:3}))
    cases.append(("AT-24 fwd->BCU",
                  [addi(1,0,5), addi(2,1,0), beq(1,2,8), addi(3,0,99), addi(4,0,4)],
                  {3:0,4:4}))
    cases.append(("AT-25 JAL link",
                  [jal(1,8), addi(2,0,99), addi(3,0,7)], {1:4,2:0,3:7}))
    cases.append(("AT-26 JALR link+fwd",
                  [addi(1,0,12), jalr(2,1,0), addi(3,0,99), addi(4,0,5)],
                  {2:8,3:0,4:5}))
    cases.append(("AT-27 fwd chain x3",
                  [addi(1,0,1), addi(2,1,1), addi(3,2,1), addi(4,3,1)],
                  {1:1,2:2,3:3,4:4}))
    cases.append(("AT-28 backward loop sum",
                  [addi(1,0,0), addi(2,0,4), add(1,1,2), addi(2,2,-1), bne(2,0,-8)],
                  {1:10,2:0}))
    cases.append(("AT-29 2x SW/LW",
                  [addi(2,0,0x40), addi(3,0,0x44), addi(10,0,0xAA), addi(11,0,0xBB),
                   sw(10,2,0), sw(11,3,0), lw(4,2,0), lw(5,3,0)],
                  {4:0xAA,5:0xBB}))
    results = []
    for name, prog, exp in cases:
        reg = run_pipeline(prog, bug=bug)
        ok = all(reg[r] == (v & M32) for r, v in exp.items())
        # also require ISS-equivalence (full register file)
        iss = iss_run(prog)
        equiv = (reg == iss)
        results.append((name, ok and equiv, exp, reg, iss))
    return results


# =====================================================================
# AT-30 random counter-example sweep (pipeline vs ISS)
# =====================================================================
def gen_random_program(rng, length=40):
    """Generate a terminating RV32I program over x1..x8 (no JALR/backward)."""
    prog = []
    regs = list(range(1, 9))
    base_off = 0x40
    for i in range(length):
        kind = rng.choice(
            ['ri','ri','rr','rr','shift','lui','auipc','mem','mem','branch','jal'])
        rd = rng.choice(regs + [0])
        rs1 = rng.choice(regs + [0]); rs2 = rng.choice(regs + [0])
        if kind == 'ri':
            op = rng.choice([addi, andi, ori, xori, slti, sltiu])
            prog.append(op(rd, rs1, rng.randint(-2048, 2047)))
        elif kind == 'rr':
            op = rng.choice([add, sub, and_, or_, xor_, slt, sltu, sll, srl, sra])
            prog.append(op(rd, rs1, rs2))
        elif kind == 'shift':
            op = rng.choice([slli, srli, srai])
            prog.append(op(rd, rs1, rng.randint(0, 31)))
        elif kind == 'lui':
            prog.append(lui(rd, rng.randint(0, 0xFFFFF)))
        elif kind == 'auipc':
            prog.append(auipc(rd, rng.randint(0, 0xFFFFF)))
        elif kind == 'mem':
            # confine address near base_off; mem model masks to NWORDS anyway
            off = rng.choice([0, 4, 8, 12, 16, 2, 1])
            if rng.random() < 0.5:
                op = rng.choice([sw, sb, sh]); prog.append(op(rng.choice(regs), 0, base_off + off))
            else:
                op = rng.choice([lw, lb, lbu, lh, lhu]); prog.append(op(rd, 0, base_off + off))
        elif kind == 'branch':
            op = rng.choice([beq, bne, blt, bge, bltu, bgeu])
            off = rng.choice([8, 12, 16])          # forward only
            prog.append(op(rs1, rs2, off))
        elif kind == 'jal':
            off = rng.choice([8, 12])              # forward only
            prog.append(jal(rng.choice(regs + [0]), off))
    return prog

def at30_counter_example(seed=20260609, n_programs=2000, length=40, bug=None, verbose=False):
    rng = random.Random(seed)
    mismatches = 0
    first = None
    for k in range(n_programs):
        prog = gen_random_program(rng, length)
        pipe = run_pipeline(prog, bug=bug, cycles=length*4 + 60)
        iss = iss_run(prog)
        if pipe != iss:
            mismatches += 1
            if first is None:
                first = (k, prog, pipe, iss)
            if verbose and mismatches <= 3:
                diff = [(r, pipe[r], iss[r]) for r in range(32) if pipe[r] != iss[r]]
                print(f"  COUNTER-EXAMPLE prog#{k}: diffs (reg,pipe,iss)={diff[:6]}")
    return n_programs, mismatches, first


# =====================================================================
# Reporting
# =====================================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bug', choices=['forward','hazard','branch','x0'], default=None)
    ap.add_argument('--programs', type=int, default=2000)
    ap.add_argument('--length', type=int, default=40)
    ap.add_argument('--seed', type=int, default=20260609)
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    print("=" * 70)
    print("RV32 IF~WB Write-Path 통합 수용 테스트 (ATDD / Shift-Left)")
    if args.bug:
        print(f"  [FAULT INJECTED: {args.bug}]")
    print("=" * 70)

    directed = at_directed(bug=args.bug)
    dpass = 0
    for name, ok, exp, reg, iss in directed:
        if ok:
            dpass += 1
        if not ok and not args.quiet:
            diff = {f"x{r}": (hex(reg[r]), hex(v & M32)) for r, v in exp.items()
                    if reg[r] != (v & M32)}
            eqv = "" if reg == iss else "  [pipeline != ISS]"
            print(f"  [FAIL] {name}: got/exp {diff}{eqv}")
    print(f"  Directed AT-01..AT-29: {dpass}/29 PASS")

    n, mm, first = at30_counter_example(seed=args.seed, n_programs=args.programs,
                                        length=args.length, bug=args.bug,
                                        verbose=not args.quiet)
    print(f"  AT-30 random counter-example: {n} programs, {mm} mismatch(es)")
    if first and not args.quiet:
        k, prog, pipe, iss = first
        diff = [(f"x{r}", hex(pipe[r]), hex(iss[r])) for r in range(32) if pipe[r] != iss[r]]
        print(f"         first rebel prog#{k} (len {len(prog)}): {diff[:8]}")

    print("-" * 70)
    iters = 30
    all_green = (dpass == 29 and mm == 0)
    print(f"  iteration count: {iters}  (AT-01..AT-29 directed + AT-30 sweep)")
    if args.bug:
        caught = (dpass < 29 or mm > 0)
        print("  result:", "FAULT CAUGHT (verification effective)" if caught else "FAULT MISSED!!")
        return 0 if caught else 1
    print("  result:", "ALL GREEN" if all_green else "FAILURES PRESENT")
    return 0 if all_green else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
