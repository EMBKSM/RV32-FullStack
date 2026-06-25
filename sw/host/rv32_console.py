#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rv32_console.py - Windows/PC host console for the RV32-FullStack FPGA CPU.

Type RISC-V assembly; it is assembled to machine code, loaded into the FPGA CPU
over UART (via the PS monitor), run, and the resulting register changes shown.

  pip install pyserial
  python rv32_console.py --port COM5            (Windows)
  python rv32_console.py --port /dev/ttyUSB1    (Linux)

REPL:
  <asm>             add an instruction to the program (e.g.  add x3, x1, x2)
  run               reset, load program (+halt), run, show changed registers
  step              single-step one instruction, show last commit
  reg               dump all registers
  mem <addr>        read a data-memory word (hex addr)
  list / clear      show / clear the program buffer
  asm <instr>       just show the machine code of one instruction (no send)
  quit
Labels supported (e.g.  loop:  ...  bne x1,x0,loop). Numbers: dec or 0x..
"""
import argparse, re, sys

# ----------------------------------------------------------------------------
# Mini RV32I assembler
# ----------------------------------------------------------------------------
M = (1 << 32) - 1
ABI = {  # ABI name -> x number
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9,
    'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
    's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
    't3':28,'t4':29,'t5':30,'t6':31}

def reg(t):
    t = t.strip().lower()
    if t in ABI: return ABI[t]
    if re.fullmatch(r'x\d+', t):
        n = int(t[1:])
        if 0 <= n <= 31: return n
    raise ValueError(f"bad register '{t}'")

def imm(t):
    t = t.strip()
    return int(t, 0)            # supports 0x.., decimal, negative

def _R(f7,rs2,rs1,f3,rd,op): return ((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)&M
def _I(im,rs1,f3,rd,op):     return (((im&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)&M
def _S(im,rs2,rs1,f3,op):    return ((((im>>5)&0x7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((im&0x1F)<<7)|op)&M
def _B(im,rs2,rs1,f3,op):
    return ((((im>>12)&1)<<31)|(((im>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|
            (((im>>1)&0xF)<<8)|(((im>>11)&1)<<7)|op)&M
def _U(im,rd,op): return (((im&0xFFFFF)<<12)|(rd<<7)|op)&M
def _J(im,rd,op):
    return ((((im>>20)&1)<<31)|(((im>>1)&0x3FF)<<21)|(((im>>11)&1)<<20)|
            (((im>>12)&0xFF)<<12)|(rd<<7)|op)&M

OP_R,OP_I,OP_LD,OP_S,OP_B,OP_JAL,OP_JALR,OP_LUI,OP_AUIPC = 0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17
RI = {'add':(0,0),'sub':(0x20,0),'sll':(0,1),'slt':(0,2),'sltu':(0,3),
      'xor':(0,4),'srl':(0,5),'sra':(0x20,5),'or':(0,6),'and':(0,7)}
II = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
LD = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
ST = {'sb':0,'sh':1,'sw':2}
BR = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

def split_ops(s): return [x for x in re.split(r'[,\s]+', s.strip()) if x]

def mem_operand(t):                    # "off(rs1)" -> (off, rs1)
    m = re.fullmatch(r'(-?(?:0x[0-9a-fA-F]+|\d+))?\((\w+)\)', t.strip())
    if not m: raise ValueError(f"bad mem operand '{t}'")
    return (imm(m.group(1)) if m.group(1) else 0), reg(m.group(2))

def _ck(v, lo, hi, what):
    """Range-check an immediate; raise instead of silently truncating."""
    if not (lo <= v <= hi):
        raise ValueError(f"{what}: immediate {v} out of range [{lo}..{hi}]")
    return v

def _cke(v, lo, hi, what):
    """Range-check a branch/jump byte offset (must be even and within reach)."""
    if v & 1:
        raise ValueError(f"{what}: target offset {v} is misaligned (odd)")
    if not (lo <= v <= hi):
        raise ValueError(f"{what}: target out of reach ({v} not in [{lo}..{hi}])")
    return v

def encode(mn, ops, pc, labels):
    mn = mn.lower()
    def tgt(t):                        # branch/jal target: label or numeric offset
        if t in labels: return labels[t] - pc
        try:
            return imm(t)
        except ValueError:
            raise ValueError(f"unknown label '{t}'")
    if mn in RI: f7,f3 = RI[mn]; return _R(f7,reg(ops[2]),reg(ops[1]),f3,reg(ops[0]),OP_R)
    if mn in II: return _I(_ck(imm(ops[2]),-2048,2047,mn),reg(ops[1]),II[mn],reg(ops[0]),OP_I)
    if mn == 'slli': return _I(_ck(imm(ops[2]),0,31,mn),reg(ops[1]),1,reg(ops[0]),OP_I)
    if mn == 'srli': return _I(_ck(imm(ops[2]),0,31,mn),reg(ops[1]),5,reg(ops[0]),OP_I)
    if mn == 'srai': return _I(0x400|_ck(imm(ops[2]),0,31,mn),reg(ops[1]),5,reg(ops[0]),OP_I)
    if mn in LD: off,rs1 = mem_operand(ops[1]); return _I(_ck(off,-2048,2047,mn),rs1,LD[mn],reg(ops[0]),OP_LD)
    if mn in ST: off,rs1 = mem_operand(ops[1]); return _S(_ck(off,-2048,2047,mn),reg(ops[0]),rs1,ST[mn],OP_S)
    if mn in BR: return _B(_cke(tgt(ops[2]),-4096,4094,mn),reg(ops[1]),reg(ops[0]),BR[mn],OP_B)
    if mn == 'lui':   return _U(_ck(imm(ops[1]),0,0xFFFFF,'lui'),reg(ops[0]),OP_LUI)
    if mn == 'auipc': return _U(_ck(imm(ops[1]),0,0xFFFFF,'auipc'),reg(ops[0]),OP_AUIPC)
    if mn == 'jal':
        if len(ops)==1: return _J(_cke(tgt(ops[0]),-(1<<20),(1<<20)-2,'jal'),0,OP_JAL)          # jal off
        return _J(_cke(tgt(ops[1]),-(1<<20),(1<<20)-2,'jal'),reg(ops[0]),OP_JAL)               # jal rd,off
    if mn == 'jalr':
        if len(ops)==2: off,rs1 = mem_operand(ops[1]); return _I(_ck(off,-2048,2047,'jalr'),rs1,0,reg(ops[0]),OP_JALR)
        return _I(_ck(imm(ops[2]),-2048,2047,'jalr'),reg(ops[1]),0,reg(ops[0]),OP_JALR)
    # pseudo-instructions
    if mn == 'nop':  return _I(0,0,0,0,OP_I)
    if mn == 'mv':   return _I(0,reg(ops[1]),0,reg(ops[0]),OP_I)             # addi rd,rs,0
    if mn == 'li':   return _I(_ck(imm(ops[1]),-2048,2047,'li'),0,0,reg(ops[0]),OP_I)  # addi rd,x0,imm
    if mn == 'j':    return _J(_cke(tgt(ops[0]),-(1<<20),(1<<20)-2,'j'),0,OP_JAL)
    if mn == 'ret':  return _I(0,1,0,0,OP_JALR)                              # jalr x0,0(ra)
    if mn in ('halt','hlt'): return _J(0,0,OP_JAL)                           # jal x0,0 (self-loop)
    raise ValueError(f"unknown instruction '{mn}'")

def expand(mn, ops):
    """Expand pseudo-instructions to base instructions (a list; usually length 1).
    'li' becomes lui+addi for full 32-bit immediates; b*z map to a branch vs x0."""
    mn = mn.lower()
    if mn == 'li':
        rd = ops[0]; v = imm(ops[1]) & M
        sv = v - (1 << 32) if (v & 0x80000000) else v
        if -2048 <= sv <= 2047:                         # fits a single addi
            return [('addi', [rd, 'x0', str(sv)])]
        hi = ((v + 0x800) >> 12) & 0xFFFFF              # lui upper 20 bits (rounded)
        lo = v - (hi << 12)                            # signed remainder, already in [-2048,2047]
        if lo == 0:
            return [('lui', [rd, str(hi)])]
        return [('lui', [rd, str(hi)]), ('addi', [rd, rd, str(lo)])]
    if mn in ('beqz', 'bnez', 'bgez', 'bltz'):          # branch-if-rs-vs-zero
        base = {'beqz': 'beq', 'bnez': 'bne', 'bgez': 'bge', 'bltz': 'blt'}[mn]
        return [(base, [ops[0], 'x0', ops[1]])]
    if mn in ('blez', 'bgtz'):                           # zero on the left
        base = {'blez': 'bge', 'bgtz': 'blt'}[mn]
        return [(base, ['x0', ops[0], ops[1]])]
    return [(mn, ops)]

def assemble(lines):
    """Two-pass: returns list of 32-bit words. Pseudo-instructions are expanded
    first so PC/label offsets stay correct even when 'li' becomes lui+addi."""
    items = []                                  # (pc, mnemonic, ops)
    labels = {}
    pc = 0
    for raw in lines:
        s = raw.split('#')[0].split(';')[0].strip()
        if not s: continue
        while ':' in s:                          # leading label(s)
            lab, _, rest = s.partition(':')
            labels[lab.strip()] = pc
            s = rest.strip()
            if not s: break
        if not s: continue
        mn, *rest = s.split(None, 1)
        ops = split_ops(rest[0]) if rest else []
        for bmn, bops in expand(mn, ops):
            items.append((pc, bmn, bops))
            pc += 4
    return [encode(mn, ops, pc, labels) for (pc, mn, ops) in items]

# ----------------------------------------------------------------------------
# UART link to the PS monitor
# ----------------------------------------------------------------------------
class Link:
    def __init__(self, port, baud):
        import serial
        self.s = serial.Serial(port, baud, timeout=1)
    def cmd(self, line):
        self.s.reset_input_buffer()
        self.s.write((line + "\n").encode())
        return self.s.readline().decode(errors="replace").strip()
    def cmd_lines(self, line, n):
        self.s.reset_input_buffer()
        self.s.write((line + "\n").encode())
        return [self.s.readline().decode(errors="replace").strip() for _ in range(n)]

def load_run(link, words, run=True):
    link.cmd("r")                                       # reset + hold
    for i, w in enumerate(words):
        link.cmd(f"i {i*4:x} {w:08x}")
    link.cmd(f"i {len(words)*4:x} 0000006f")            # append halt (jal x0,0)
    if run: link.cmd("g")

def dump_regs(link):
    out = link.cmd_lines("D", 32)
    regs = {}
    for ln in out:
        m = re.fullmatch(r'x(\d+)=([0-9a-fA-F]+)', ln.strip())
        if m: regs[int(m.group(1))] = int(m.group(2), 16)
    return regs

# ----------------------------------------------------------------------------
# REPL
# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', help='serial port (e.g. COM5 or /dev/ttyUSB1)')
    ap.add_argument('--baud', type=int, default=115200)
    args = ap.parse_args()

    link = None
    if args.port:
        try:
            link = Link(args.port, args.baud)
            print(f"[connected {args.port} @ {args.baud}]")
        except Exception as e:
            print(f"[serial open failed: {e}] -- running in OFFLINE assemble-only mode")
    else:
        print("[no --port: OFFLINE assemble-only mode]")

    prog = []
    print("RV32 console. type instructions, then 'run'.  'help' for commands.")
    while True:
        try: line = input("rv32> ").strip()
        except (EOFError, KeyboardInterrupt): print(); break
        if not line: continue
        low = line.lower()
        try:
            if low in ('quit','exit','q'): break
            elif low == 'help':
                print(__doc__)
            elif low == 'list':
                for i,w in enumerate(prog): print(f"  [{i}] {w:08x}")
            elif low == 'clear':
                prog = []; print("cleared")
            elif low.startswith('asm '):
                w = assemble([line[4:]]); print(' '.join(f"{x:08x}" for x in w))
            elif low == 'run':
                if not prog: print("empty program"); continue
                print("program:", ' '.join(f"{w:08x}" for w in prog))
                if not link: print("[offline] cannot run"); continue
                load_run(link, prog, run=True)
                import time; time.sleep(0.2)
                regs = dump_regs(link)
                changed = {n:v for n,v in regs.items() if v != 0}
                if changed:
                    for n in sorted(changed): print(f"  x{n} = 0x{changed[n]:08x} ({changed[n]:#d})")
                else:
                    print("  (no register changes)")
            elif low == 'reg':
                if not link: print("[offline]"); continue
                for n,v in sorted(dump_regs(link).items()):
                    if v: print(f"  x{n} = 0x{v:08x}")
            elif low == 'step':
                if not link: print("[offline]"); continue
                print(" ", link.cmd("s"))
            elif low.startswith('mem '):
                if not link: print("[offline]"); continue
                a = int(line.split()[1], 0); print(" ", link.cmd(f"m {a:x}"))
            else:
                # treat as one assembly instruction -> add to program
                w = assemble([line])
                if w:
                    for x in w: prog.append(x)
                    print(f"  + {w[0]:08x}   (program has {len(prog)} instr; 'run' to execute)")
        except Exception as e:
            print(f"  error: {e}")

if __name__ == '__main__':
    main()
