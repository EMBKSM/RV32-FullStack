#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""run_pipeline50.py - 50-iteration re-verification across IF~WB.
Reuses test_rv32 (IF), run_alu_at (ALU), run_id_wb_at (ID~WB combinational),
and adds reference models for the sequential/FSM modules (csr_file, dtag/ddata,
dcache_controller, axi_master, trap_unit, pipeline_reg)."""
import os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_rv32 as IF
import run_alu_at as ALU
import run_id_wb_at as C        # ctrl, imm_gen, alu_control, bcu, fwd, haz, read_aligner, wsg, rmux

M32 = (1 << 32) - 1
random.seed(20260608)
RES = []   # (name, passed, nchecks)

def it(name):
    def deco(fn):
        ok = True; n = 0
        try:
            n = fn()
            if isinstance(n, tuple): ok, n = n
        except AssertionError as e:
            ok = False
        RES.append((name, ok, n)); return fn
    return deco

# ===================== IF (reuse test_rv32) =====================
def _ifwrap(name, fn):
    r = fn(); RES.append((name, r.passed, r.n))
_ifwrap("IF-01 RTL static sanity",        IF.iter01_static)
_ifwrap("IF-02 addr_aligner decode",      IF.iter02_addr_aligner)
_ifwrap("IF-03 comparator hit",           IF.iter03_comparator)
_ifwrap("IF-04 PC datapath",              IF.iter04_pc_datapath)
_ifwrap("IF-05 tag_array + invalidate",   IF.iter05_tag_array)
_ifwrap("IF-06 cache FSM transitions",    IF.iter06_fsm_transitions)
_ifwrap("IF-07 cache FSM outputs+B1",     IF.iter07_fsm_outputs)
_ifwrap("IF-08 integration refill",       IF.iter08_integration_refill)
_ifwrap("IF-09 BUG-001 data timing",      IF.iter09_refill_data_integrity)
_ifwrap("IF-10 regression sweep",         IF.iter10_regression)

# ===================== ID =====================
@it("ID-11 decoder R/I/Load/Store")
def _():
    a=0
    a+=C.ctrl("0110011")["reg_write"]==1 and C.ctrl("0110011")["alu_op"]=="10"
    a+=C.ctrl("0010011")["alu_src"]==1
    a+=C.ctrl("0000011")["mem_read"]==1 and C.ctrl("0000011")["result_src"]=="01"
    a+=C.ctrl("0100011")["mem_write"]==1 and C.ctrl("0100011")["reg_write"]==0
    assert a==4; return 4

@it("ID-12 decoder Branch/JAL/JALR/LUI/AUIPC")
def _():
    a=0
    a+=C.ctrl("1100011")["branch"]==1
    a+=C.ctrl("1101111")["jump"]==1 and C.ctrl("1101111")["result_src"]=="10"
    a+=C.ctrl("1100111")["jump"]==1 and C.ctrl("1100111")["alu_src"]==1
    a+=C.ctrl("0110111")["alu_op"]=="11"
    a+=C.ctrl("0010111")["src_a"]==1
    assert a==5; return 5

@it("ID-13 decoder SYSTEM (CSR/ECALL/EBREAK/MRET)")
def _():
    a=0
    a+=C.ctrl("1110011","001")["csr_cmd"]=="01"
    a+=C.ctrl("1110011","010")["csr_cmd"]=="10"
    a+=C.ctrl("1110011","111")["csr_cmd"]=="11" and C.ctrl("1110011","111")["csr_use_imm"]==1
    a+=C.ctrl("1110011","000",0x000)["ecall"]==1
    a+=C.ctrl("1110011","000",0x001)["ebreak"]==1
    a+=C.ctrl("1110011","000",0x302)["mret"]==1
    assert a==6; return 6

@it("ID-14 decoder FENCE/illegal")
def _():
    a=C.ctrl("0001111","001")["fence_i"]==1
    a+=C.ctrl("0000000")["illegal"]==1
    a+=C.ctrl("1111111")["illegal"]==1
    assert a==3; return 3

@it("ID-15 imm_gen I/S")
def _():
    a=C.imm_gen(0xFFF00013,"0010011")==0xFFFFFFFF
    a+=C.imm_gen(0x00100013,"0010011")==1
    a+=C.imm_gen((0x00<<25)|(0x05<<7)|0x23,"0100011")==5
    assert a==3; return 3

@it("ID-16 imm_gen B/U/J")
def _():
    a=C.imm_gen(0xABCDE0B7,"0110111")==0xABCDE000
    a+=(C.imm_gen(0x800000EF,"1101111") & 0x100000)!=0   # J sign bit20
    a+=(C.imm_gen(0x80000063,"1100011") & 0x1000)!=0      # B sign bit12
    assert a==3; return 3

# register_file model
class RegFile:
    def __init__(self): self.r=[0]*32
    def access(self,we3,a1,a2,a3,wd3):
        wr = 1 if (we3 and a3!=0) else 0
        rd1 = 0 if a1==0 else (wd3 if (wr and a3==a1) else self.r[a1])
        rd2 = 0 if a2==0 else (wd3 if (wr and a3==a2) else self.r[a2])
        return rd1,rd2,wr
    def clk(self,we3,a3,wd3):
        if we3 and a3!=0: self.r[a3]=wd3 & M32

@it("ID-17 register_file x0/write-first/read")
def _():
    rf=RegFile(); a=0
    rf.clk(1,5,0x1234); a+=rf.access(0,5,0,0,0)[0]==0x1234     # read back
    a+=rf.access(1,0,0,0,0x99)[0]==0                            # x0 read = 0
    a+=rf.access(1,7,0,7,0xABCD)[0]==0xABCD                     # write-first bypass rs1=rd
    rf.clk(1,0,0xDEAD); a+=rf.access(0,0,0,0,0)[0]==0           # write to x0 ignored
    assert a==4; return 4

# csr_file model
class CSR:
    def __init__(self):
        self.c={0x300:0,0x304:0,0x305:0,0x340:0,0x341:0,0x342:0,0x343:0,0x344:0}
    def rd(self,addr):
        if addr==0x301: return 0x40000100
        if addr==0xF14: return 0
        return self.c.get(addr,0)
    def step(self,addr,cmd,wdata,we,trap_we=0,t_mepc=0,t_mcause=0,t_mtval=0,mret=0):
        r=self.rd(addr)
        wv={"01":wdata,"10":r|wdata,"11":r&(~wdata & M32)}.get(cmd,r)
        if trap_we:
            self.c[0x341]=t_mepc; self.c[0x342]=t_mcause; self.c[0x343]=t_mtval
            ms=self.c[0x300]; mie=(ms>>3)&1
            ms=(ms & ~(1<<7))|(mie<<7); ms&=~(1<<3); ms=(ms & ~(3<<11))|(3<<11)
            self.c[0x300]=ms
        elif mret:
            ms=self.c[0x300]; mpie=(ms>>7)&1
            ms=(ms & ~(1<<3))|(mpie<<3); ms|=(1<<7); ms&=~(3<<11)
            self.c[0x300]=ms
        elif we and addr in self.c:
            self.c[addr]=wv & M32
        return r

@it("ID-18 csr_file CSRRW/RS/RC")
def _():
    cs=CSR(); a=0
    cs.step(0x305,"01",0xDEADBEEF,1); a+=cs.rd(0x305)==0xDEADBEEF      # mtvec RW
    cs.step(0x340,"01",0x0F,1); cs.step(0x340,"10",0xF0,1); a+=cs.rd(0x340)==0xFF  # RS set
    cs.step(0x340,"11",0x0F,1); a+=cs.rd(0x340)==0xF0                  # RC clear
    a+=cs.rd(0x301)==0x40000100                                        # misa RO
    assert a==4; return 4

@it("ID-19 csr_file trap entry + MRET")
def _():
    cs=CSR(); a=0
    cs.c[0x300]=(1<<3)   # MIE=1
    cs.step(0x000,"00",0,0,trap_we=1,t_mepc=0x100,t_mcause=2,t_mtval=0xABC)
    a+=cs.rd(0x341)==0x100 and cs.rd(0x342)==2 and cs.rd(0x343)==0xABC
    ms=cs.rd(0x300); a+=((ms>>7)&1)==1 and ((ms>>3)&1)==0 and ((ms>>11)&3)==3   # MPIE=1,MIE=0,MPP=11
    cs.step(0x000,"00",0,0,mret=1)
    ms=cs.rd(0x300); a+=((ms>>3)&1)==1 and ((ms>>7)&1)==1 and ((ms>>11)&3)==0   # MIE<=MPIE,MPP=0
    assert a==3; return 3

@it("ID-20 hazard_unit load-use matrix")
def _():
    a=0
    a+=C.haz(1,5,5,9)==(1,1)
    a+=C.haz(1,5,9,5)==(1,1)
    a+=C.haz(0,5,5,9)==(0,0)
    a+=C.haz(1,0,0,0)==(0,0)
    a+=C.haz(1,5,9,8)==(0,0)
    assert a==5; return 5

# ===================== EX =====================
def _alu_subset(prefixes):
    n=0
    for name,a,b,ctrl,exp in ALU.DIRECTED:
        if any(name.startswith(p) for p in prefixes):
            r,z=ALU.alu_dut(a,b,ctrl)
            assert r==exp and z==(1 if exp==0 else 0), name
            n+=1
    return n
@it("EX-21 alu ADD/SUB")
def _(): return _alu_subset(["AT-01","AT-02","AT-03","AT-04","AT-05","AT-06"])
@it("EX-22 alu logic+zero")
def _(): return _alu_subset(["AT-07","AT-08","AT-09","AT-25"])
@it("EX-23 alu shifts(+mask)")
def _(): return _alu_subset(["AT-10","AT-11","AT-12","AT-13","AT-14","AT-15","AT-16","AT-17","AT-26","AT-27","AT-29"])
@it("EX-24 alu SLT/SLTU/Bpass/illegal")
def _(): return _alu_subset(["AT-18","AT-19","AT-20","AT-21","AT-22","AT-23","AT-24","AT-28"])
@it("EX-25 alu random vs golden (50k)")
def _():
    mm=0
    for _ in range(50000):
        a=random.getrandbits(32); b=random.getrandbits(32); ctrl=random.randint(0,11)
        if ALU.alu_dut(a,b,ctrl)[0]!=ALU.golden(a,b,ctrl): mm+=1
    assert mm==0; return 50000
@it("EX-26 alu fault-injection caught")
def _():
    a=0
    for bug,exp in (("sra",3),("slt",3),("shamt",2)):
        p,t,_=ALU.run(bug=bug,n=20000,quiet=True); a+= (t-p)==exp
    assert a==3; return 3
@it("EX-27 alu_control exhaustive 64")
def _():
    n=0
    for op in ("00","01","10","11"):
        for f3i in range(8):
            for f75 in (0,1):
                f3=format(f3i,"03b")
                g=("0000" if op=="00" else "0001" if op=="01" else "1010" if op=="11" else
                   {"000":"0001" if f75 else "0000","001":"0101","010":"1000","011":"1001",
                    "100":"0100","101":"0111" if f75 else "0110","110":"0011","111":"0010"}[f3])
                assert C.alu_control(op,f3,f75)==g; n+=1
    return n
@it("EX-28 bcu conditions BEQ..BGEU")
def _():
    a=0
    a+=C.bcu(5,5,0,0,0,"000",1,0,0)[0]==1
    a+=C.bcu(5,6,0,0,0,"001",1,0,0)[0]==1
    a+=C.bcu(0xFFFFFFFF,1,0,0,0,"100",1,0,0)[0]==1
    a+=C.bcu(2,1,0,0,0,"101",1,0,0)[0]==1
    a+=C.bcu(1,0xFFFFFFFF,0,0,0,"110",1,0,0)[0]==1
    a+=C.bcu(0xFFFFFFFF,1,0,0,0,"111",1,0,0)[0]==1
    assert a==6; return 6
@it("EX-29 bcu pc_src/target JAL/JALR")
def _():
    a=0
    r=C.bcu(0,0,0,0x1000,0x20,"000",0,1,0); a+= r[1]==1 and r[2]==0x1020
    r=C.bcu(0,0,0x1001,0,4,"000",0,1,1);   a+= r[2]==0x1004
    a+=C.bcu(5,6,0,0,0,"000",1,0,0)[1]==0   # branch not taken -> pc_src 0
    assert a==3; return 3
@it("EX-30 bcu random vs golden")
def _():
    mm=0
    for _ in range(20000):
        a=random.getrandbits(32); b=random.getrandbits(32); pc=random.getrandbits(32)&0xFFFFFFFC
        imm=random.getrandbits(32); f3=format(random.choice([0,1,4,5,6,7]),"03b")
        br=random.randint(0,1); jp=random.randint(0,1); jr=random.randint(0,1)
        t,ps,tg=C.bcu(a,b,a,pc,imm,f3,br,jp,jr)
        # independent golden
        sa=a-(1<<32) if a&0x80000000 else a; sb=b-(1<<32) if b&0x80000000 else b
        cond={"000":a==b,"001":a!=b,"100":sa<sb,"101":sa>=sb,"110":a<b,"111":a>=b}[f3]
        eps=1 if (jp or (br and cond)) else 0
        etg=((a+imm)&0xFFFFFFFE)&M32 if jr else (pc+imm)&M32
        if ps!=eps or tg!=etg: mm+=1
    assert mm==0; return 20000
@it("EX-31 forwarding select+priority")
def _():
    a=0
    a+=C.fwd(5,6,5,1,9,1)[0]=="10"
    a+=C.fwd(5,6,9,1,5,1)[0]=="01"
    a+=C.fwd(5,6,9,1,8,1)[0]=="00"
    a+=C.fwd(5,0,5,1,5,1)[0]=="10"     # EX/MEM beats MEM/WB
    a+=C.fwd(0,0,0,1,0,1)[0]=="00"     # x0
    assert a==5; return 5

# trap_unit model
def trap_unit(ill,im,lm,sm,ec,eb,mr,pc,fa,mtvec,mepc):
    exc=ill or im or lm or sm or ec or eb
    if im: cause=0
    elif ill: cause=2
    elif eb: cause=3
    elif lm: cause=4
    elif sm: cause=6
    elif ec: cause=11
    else: cause=0
    return dict(taken=1 if (exc or mr) else 0, target=mtvec if exc else mepc,
                flush=1 if (exc or mr) else 0, we=1 if exc else 0,
                cause=cause, mepc=pc, mtval=fa)
@it("EX-32 trap_unit cause/target")
def _():
    a=0
    a+=trap_unit(1,0,0,0,0,0,0,0x100,0,0x80,0x40)["cause"]==2     # illegal
    a+=trap_unit(0,0,0,0,1,0,0,0,0,0x80,0)["cause"]==11           # ecall
    a+=trap_unit(0,0,1,0,0,0,0,0,0,0x80,0)["cause"]==4            # load misalign
    a+=trap_unit(1,0,0,0,0,0,0,0x100,0,0x80,0)["target"]==0x80    # exception->mtvec
    a+=trap_unit(0,0,0,0,0,0,1,0,0,0x80,0x40)["target"]==0x40     # mret->mepc
    a+=trap_unit(0,0,0,0,0,0,1,0,0,0x80,0x40)["we"]==0            # mret no csr-exc-update
    assert a==6; return 6

# ===================== MEM =====================
@it("MEM-33 read_aligner LB/LBU")
def _():
    a=0
    a+=C.read_aligner(0x000000FF,0,"000")==0xFFFFFFFF
    a+=C.read_aligner(0x000000FF,0,"100")==0x000000FF
    a+=C.read_aligner(0x80000000,3,"000")==0xFFFFFF80
    a+=C.read_aligner(0x7F000000,3,"100")==0x0000007F
    assert a==4; return 4
@it("MEM-34 read_aligner LH/LHU/LW")
def _():
    a=0
    a+=C.read_aligner(0x0000FFFF,0,"001")==0xFFFFFFFF
    a+=C.read_aligner(0xABCD0000,2,"101")==0x0000ABCD
    a+=C.read_aligner(0x12345678,0,"010")==0x12345678
    assert a==3; return 3
@it("MEM-35 write_strobe SB")
def _():
    a=0
    for off,ws in ((0,"0001"),(1,"0010"),(2,"0100"),(3,"1000")):
        a+=C.wsg("000",off,0xAB)[0]==ws
    assert a==4; return 4
@it("MEM-36 write_strobe SH/SW")
def _():
    a=0
    a+=C.wsg("001",0,0xBEEF)[0]=="0011"
    a+=C.wsg("001",2,0xBEEF)[0]=="1100"
    a+=C.wsg("010",0,0x12345678)==("1111",0x12345678)
    assert a==3; return 3

# dtag/ddata models
class DTag:
    def __init__(self): self.tag=[0]*256; self.val=[0]*256; self.drt=[0]*256
    def rd(self,i): return self.tag[i],self.val[i],self.drt[i]
    def clk(self,i,we_tag,we_dirty,tag_in):
        if we_tag: self.tag[i]=tag_in; self.val[i]=1; self.drt[i]=0
        elif we_dirty: self.drt[i]=1
class DData:
    def __init__(self): self.line=[0]*256
    def word(self,i,wo): return (self.line[i]>>(32*wo))&M32
    def clk(self,i,wo,we,wstrb,wdata,line_fill,fill_line):
        if line_fill: self.line[i]=fill_line & ((1<<128)-1)
        elif we:
            base=32*wo; w=(self.line[i]>>base)&M32
            for k in range(4):
                if (wstrb>>k)&1: w=(w & ~(0xFF<<(8*k))) | (((wdata>>(8*k))&0xFF)<<(8*k))
            self.line[i]=(self.line[i] & ~(M32<<base)) | (w<<base)
@it("MEM-37 dtag_array valid/dirty/refill")
def _():
    d=DTag(); a=0
    d.clk(5,1,0,0xABCDE); a+=d.rd(5)==(0xABCDE,1,0)
    d.clk(5,0,1,0); a+=d.rd(5)[2]==1                  # set dirty
    d.clk(5,1,0,0x11111); a+=d.rd(5)==(0x11111,1,0)   # refill clears dirty
    assert a==3; return 3
@it("MEM-38 ddata_array word/byte/line")
def _():
    dd=DData(); a=0
    dd.clk(3,0,0,0,0,1,0x44332211_00000000_00000000_00000000); a+=dd.word(3,3)==0x44332211
    dd.clk(7,1,1,0b0010,0x0000AB00,0,0); a+=((dd.word(7,1)>>8)&0xFF)==0xAB
    dd.clk(7,1,1,0b1111,0xDEADBEEF,0,0); a+=dd.word(7,1)==0xDEADBEEF
    assert a==3; return 3

# dcache_controller model
DI,DWB,DAL,DRF,DWK=range(5)
def dc_next(st,miss,dirty,done):
    if st==DI: return (DWB if dirty else DAL) if miss else DI
    if st==DWB: return DAL if done else DWB
    if st==DAL: return DRF if done else DAL
    if st==DRF: return DWK
    return DI
def dc_out(st,miss,hit,mem_write,access):
    o=dict(stall=0,wake=0,we_tag=0,we_dirty=0,data_we=0,line_fill=0,rd=0,wr=0)
    if st==DI:
        if miss: o["stall"]=1
        elif access and hit and mem_write: o["data_we"]=1; o["we_dirty"]=1
    elif st==DWB: o["stall"]=1; o["wr"]=1
    elif st==DAL: o["stall"]=1; o["rd"]=1
    elif st==DRF: o["stall"]=1; o["line_fill"]=1; o["we_tag"]=1
    elif st==DWK: o["wake"]=1
    return o
@it("MEM-39 dcache FSM transitions")
def _():
    a=0
    a+=dc_next(DI,1,0,0)==DAL                 # miss clean -> alloc
    a+=dc_next(DI,1,1,0)==DWB                  # miss dirty -> writeback
    a+=dc_next(DI,0,0,0)==DI
    a+=dc_next(DWB,0,0,1)==DAL
    a+=dc_next(DAL,0,0,1)==DRF
    a+=dc_next(DRF,0,0,0)==DWK
    a+=dc_next(DWK,0,0,0)==DI
    assert a==7; return 7
@it("MEM-40 dcache outputs (store-hit dirty/refill)")
def _():
    a=0
    a+=dc_out(DI,0,1,1,1)["we_dirty"]==1 and dc_out(DI,0,1,1,1)["data_we"]==1
    a+=dc_out(DI,1,0,0,1)["stall"]==1
    a+=dc_out(DRF,0,0,0,0)["line_fill"]==1 and dc_out(DRF,0,0,0,0)["we_tag"]==1
    a+=dc_out(DWB,0,0,0,0)["wr"]==1
    a+=dc_out(DWK,0,0,0,0)["wake"]==1
    assert a==5; return 5

# axi_master model
AI,AAR,AR,AAW,AW,AB,AD=range(7)
class Axi:
    def __init__(self): self.st=AI; self.beat=0; self.rbuf=0
    def comb(self,wb_line):
        wsel=(wb_line>>(32*self.beat))&M32
        return dict(arvalid=self.st==AAR, rready=self.st==AR, awvalid=self.st==AAW,
                    wvalid=self.st==AW, wlast=(self.st==AW and self.beat==3),
                    bready=self.st==AB, done=self.st==AD, wdata=wsel)
    def clk(self,rd_start,wr_start,arready,rvalid,rdata,rlast,awready,wready,bvalid):
        s=self.st
        if s==AI:
            self.beat=0
            if rd_start: self.st=AAR
            elif wr_start: self.st=AAW
        elif s==AAR:
            if arready: self.st=AR; self.beat=0
        elif s==AR:
            if rvalid:
                self.rbuf=(self.rbuf & ~(M32<<(32*self.beat)))|((rdata & M32)<<(32*self.beat))
                if rlast: self.st=AD
                else: self.beat+=1
        elif s==AAW:
            if awready: self.st=AW; self.beat=0
        elif s==AW:
            if wready:
                if self.beat==3: self.st=AB
                else: self.beat+=1
        elif s==AB:
            if bvalid: self.st=AD
        elif s==AD:
            self.st=AI
@it("MEM-41 axi_master read burst (4 beat)")
def _():
    m=Axi(); words=[0x11111111,0x22222222,0x33333333,0x44444444]; done=0
    for c in range(12):
        cb=m.comb(0)
        rds=1 if (m.st==AI and c==0) else 0
        rvalid=1 if m.st==AR else 0
        rdata=words[m.beat] if m.st==AR else 0
        rlast=1 if (m.st==AR and m.beat==3) else 0
        if cb["done"]: done=1
        m.clk(rds,0,1,rvalid,rdata,rlast,0,0,0)
    exp=0
    for k,w in enumerate(words): exp|=w<<(32*k)
    assert m.rbuf==exp and done==1; return 2
@it("MEM-42 axi_master write burst + B")
def _():
    m=Axi(); wb=0
    for k,w in enumerate([0xA,0xB,0xC,0xD]): wb|=w<<(32*k)
    got=[]; done=0; lastseen=0
    for c in range(14):
        cb=m.comb(wb)
        wrs=1 if (m.st==AW0 if False else (m.st==AI and c==0)) else 0
        wready=1 if m.st==AW else 0
        if m.st==AW and wready: got.append(cb["wdata"])
        if cb["wlast"]: lastseen=1
        bvalid=1 if m.st==AB else 0
        if cb["done"]: done=1
        m.clk(0,wrs,0,0,0,0,1,wready,bvalid)
    assert got==[0xA,0xB,0xC,0xD] and lastseen==1 and done==1; return 3
@it("MEM-43 dcache integration: load miss(clean)->refill->hit")
def _():
    st=DI; done_ctr=0; seq=[]
    miss=1; dirty=0
    for c in range(12):
        o=dc_out(st,miss,0,0,1); seq.append(st)
        done=1 if (st in (DWB,DAL) and done_ctr>=1) else 0
        nx=dc_next(st,miss,dirty,done)
        if st in (DWB,DAL): done_ctr+=1
        else: done_ctr=0
        if st==DWK: miss=0      # after refill, becomes hit
        st=nx
        if st==DI and miss==0: break
    assert DAL in seq and DRF in seq and DWK in seq and DWB not in seq; return 4
@it("MEM-44 dcache integration: store miss(dirty)->writeback->refill")
def _():
    st=DI; dc=0; seq=[]; miss=1; dirty=1
    for c in range(14):
        seq.append(st)
        done=1 if (st in (DWB,DAL) and dc>=1) else 0
        nx=dc_next(st,miss,dirty,done)
        dc = dc+1 if st in (DWB,DAL) else 0
        if st==DWK: miss=0
        st=nx
        if st==DI and miss==0: break
    assert seq.index(DWB)<seq.index(DAL)<seq.index(DRF) and DWK in seq; return 4

# ===================== WB =====================
@it("WB-45 result_mux ALU/MEM/PC4")
def _():
    a=0
    a+=C.rmux("00",0,0xA,0xB,0xC,0xD)==0xA
    a+=C.rmux("01",0,0xA,0xB,0xC,0xD)==0xB
    a+=C.rmux("10",0,0xA,0xB,0xC,0xD)==0xC
    assert a==3; return 3
@it("WB-46 result_mux CSR override + random")
def _():
    a=C.rmux("00",1,0xA,0xB,0xC,0xD)==0xD
    mm=0
    for _ in range(10000):
        rs=random.choice(["00","01","10"]); cr=random.randint(0,1)
        al,rd,p4,cs=[random.getrandbits(32) for _ in range(4)]
        exp=cs if cr else {"00":al,"01":rd,"10":p4}[rs]
        if C.rmux(rs,cr,al,rd,p4,cs)!=exp: mm+=1
    assert a and mm==0; return 10001
def pipe(state,d,c,reset,flush,stall):
    if reset: return (0,0)
    if flush: return (d,0)
    if stall: return state
    return (d,c)
@it("WB-47 pipeline_reg latch/stall")
def _():
    s=(0,0); s=pipe(s,0xAA,0x3,0,0,0); a=s==(0xAA,0x3)
    s2=pipe(s,0xBB,0x1,0,0,1); a+= s2==(0xAA,0x3)   # stall holds
    assert a==2; return 2
@it("WB-48 pipeline_reg flush(bubble)/reset")
def _():
    s=(0xAA,0x3); s=pipe(s,0xBB,0x7,0,1,0); a= s==(0xBB,0)   # flush: data passes, ctrl=0
    s=pipe(s,0xCC,0x7,1,0,0); a+= s==(0,0)                   # reset
    assert a==2; return 2

# ===================== integration =====================
@it("INT-49 forwarding back-to-back dependent (EX/MEM bypass)")
def _():
    # I0: add x1=... (in EX/MEM). I1: sub x2,x1,.. needs forward_a=10
    fa,fb=C.fwd(1,3, ex_rd:=1,1, mw_rd:=9,1)
    assert fa=="10"; return 1
@it("INT-50 load-use bubble then MEM/WB forward")
def _():
    st,fl=C.haz(1,1,1,9)        # LW x1 then use x1 -> stall+flush
    assert (st,fl)==(1,1)
    fa,_=C.fwd(1,9, 9,1, 1,1)   # next cycle: LW result in MEM/WB -> forward_a=01
    assert fa=="01"; return 2

# ===================== report =====================
def main():
    npass=sum(1 for _,ok,_ in RES if ok)
    total_checks=sum(n for _,_,n in RES)
    print("="*70)
    print("RV32 IF~WB 50-iteration 재검증 캠페인")
    print("="*70)
    for name,ok,n in RES:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name:42} ({n} checks)")
    print("-"*70)
    print(f"통과: {npass}/{len(RES)} iteration,  총 점검 {total_checks}건")
    print("결과:", "ALL GREEN" if npass==len(RES) else "FAILURES PRESENT")
    return 0 if npass==len(RES) else 1

if __name__ == "__main__":
    sys.exit(main())
