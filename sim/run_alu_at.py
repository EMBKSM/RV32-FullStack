#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_alu_at.py — ALU ATDD acceptance-test runner (sandbox-executable equivalent
of tb_alu.sv). Mirrors alu.vhd semantics and runs AT-01..AT-30 against
independent expected values + a randomized counter-example sweep vs a golden
reference. Fault-injection (--bug) demonstrates the tests actually catch bugs.

Usage:
    python3 verification/run_alu_at.py            # clean run (expect 30/30)
    python3 verification/run_alu_at.py --bug sra  # inject SRA->SRL fault
    python3 verification/run_alu_at.py --n 200000 # bigger random sweep
"""
import sys, random

M32 = (1 << 32) - 1


def _signed(x):
    return x - (1 << 32) if (x >> 31) & 1 else x


# ---- DUT model: mirrors alu.vhd (optionally fault-injected via `bug`) ----
def alu_dut(a, b, ctrl, bug=None):
    a &= M32; b &= M32
    sh = b & 0x1F
    if bug == "shamt":
        sh = b & 0xFF                      # missing proper b[4:0] mask
    if ctrl == 0x0:  r = (a + b) & M32
    elif ctrl == 0x1: r = (a - b) & M32
    elif ctrl == 0x2: r = a & b
    elif ctrl == 0x3: r = a | b
    elif ctrl == 0x4: r = a ^ b
    elif ctrl == 0x5: r = (a << sh) & M32 if sh < 64 else 0
    elif ctrl == 0x6: r = a >> sh if sh < 64 else 0
    elif ctrl == 0x7:                      # SRA (arithmetic)
        if bug == "sra":
            r = a >> sh if sh < 64 else 0  # buggy: logical shift
        else:
            r = (_signed(a) >> sh) & M32 if sh < 64 else (M32 if (a >> 31) & 1 else 0)
    elif ctrl == 0x8:                      # SLT (signed)
        if bug == "slt":
            r = 1 if a < b else 0          # buggy: unsigned compare
        else:
            r = 1 if _signed(a) < _signed(b) else 0
    elif ctrl == 0x9: r = 1 if a < b else 0
    elif ctrl == 0xA: r = b
    else:             r = 0
    z = 1 if r == 0 else 0
    return r, z


# ---- independent golden reference (for AT-30) ----
def golden(a, b, ctrl):
    a &= M32; b &= M32; sh = b & 0x1F
    sa, sb = _signed(a), _signed(b)
    table = {
        0x0: (a + b) & M32, 0x1: (a - b) & M32, 0x2: a & b, 0x3: a | b, 0x4: a ^ b,
        0x5: (a << sh) & M32, 0x6: a >> sh, 0x7: (sa >> sh) & M32,
        0x8: 1 if sa < sb else 0, 0x9: 1 if a < b else 0, 0xA: b,
    }
    return table.get(ctrl, 0)


# ---- directed acceptance tests (independent expected constants) ----
DIRECTED = [
    ("AT-01 ADD",            0x00000003, 0x00000004, 0x0, 0x00000007),
    ("AT-02 ADD wrap",       0xFFFFFFFF, 0x00000001, 0x0, 0x00000000),
    ("AT-03 ADD -1+2",       0xFFFFFFFF, 0x00000002, 0x0, 0x00000001),
    ("AT-04 SUB",            0x0000000A, 0x00000003, 0x1, 0x00000007),
    ("AT-05 SUB to 0",       0x00000005, 0x00000005, 0x1, 0x00000000),
    ("AT-06 SUB underflow",  0x00000000, 0x00000001, 0x1, 0xFFFFFFFF),
    ("AT-07 AND",            0xF0F0F0F0, 0x0FF00FF0, 0x2, 0x00F000F0),
    ("AT-08 OR",             0xF0F0F0F0, 0x0F0F0F0F, 0x3, 0xFFFFFFFF),
    ("AT-09 XOR self",       0xAAAAAAAA, 0xAAAAAAAA, 0x4, 0x00000000),
    ("AT-10 SLL 1",          0x00000001, 0x00000001, 0x5, 0x00000002),
    ("AT-11 SLL 31",         0x00000001, 0x0000001F, 0x5, 0x80000000),
    ("AT-12 SLL mask",       0x00000001, 0x00000020, 0x5, 0x00000001),
    ("AT-13 SRL 4",          0x000000F0, 0x00000004, 0x6, 0x0000000F),
    ("AT-14 SRL MSB",        0x80000000, 0x00000001, 0x6, 0x40000000),
    ("AT-15 SRA neg",        0x80000000, 0x00000001, 0x7, 0xC0000000),
    ("AT-16 SRA pos",        0x40000000, 0x00000001, 0x7, 0x20000000),
    ("AT-17 SRA 31 neg",     0x80000000, 0x0000001F, 0x7, 0xFFFFFFFF),
    ("AT-18 SLT -1<1",       0xFFFFFFFF, 0x00000001, 0x8, 0x00000001),
    ("AT-19 SLT 1<-1",       0x00000001, 0xFFFFFFFF, 0x8, 0x00000000),
    ("AT-20 SLT equal",      0x00000005, 0x00000005, 0x8, 0x00000000),
    ("AT-21 SLTU 1<max",     0x00000001, 0xFFFFFFFF, 0x9, 0x00000001),
    ("AT-22 SLTU max<1",     0xFFFFFFFF, 0x00000001, 0x9, 0x00000000),
    ("AT-23 SLTU divergence",0x7FFFFFFF, 0x80000000, 0x9, 0x00000001),
    ("AT-24 Bpass",          0x12345678, 0xDEADBEEF, 0xA, 0xDEADBEEF),
    ("AT-25 zero via AND",   0x0000FF00, 0x000000FF, 0x2, 0x00000000),
    ("AT-26 SLL high bits",  0xFFFFFFFF, 0x00000004, 0x5, 0xFFFFFFF0),
    ("AT-27 SLL by 0",       0x12345678, 0x00000000, 0x5, 0x12345678),
    ("AT-28 illegal ctrl",   0x12345678, 0x9ABCDEF0, 0xF, 0x00000000),
    ("AT-29 SRL 31",         0xFFFFFFFF, 0x0000001F, 0x6, 0x00000001),
]


def run(bug=None, n=100000, seed=20260608, quiet=False):
    random.seed(seed)
    npass = 0
    results = []
    for name, a, b, ctrl, exp in DIRECTED:
        r, z = alu_dut(a, b, ctrl, bug=bug)
        ok = (r == exp) and (z == (1 if exp == 0 else 0))
        results.append((name, ok, f"result={r:#010x} exp={exp:#010x} zero={z}"))
        npass += ok
    # AT-30 randomized counter-example sweep
    ce = None
    mism = 0
    for _ in range(n):
        a = random.getrandbits(32); b = random.getrandbits(32); ctrl = random.randint(0, 11)
        r, _z = alu_dut(a, b, ctrl, bug=bug)
        g = golden(a, b, ctrl)
        if r != g:
            mism += 1
            if ce is None:
                ce = (a, b, ctrl, r, g)
    at30_ok = (mism == 0)
    results.append(("AT-30 random counter-example",
                    at30_ok, f"{n} vectors, mismatches={mism}" +
                    (f"  반례: a={ce[0]:#010x} b={ce[1]:#010x} ctrl={ce[2]:#06b} dut={ce[3]:#010x} golden={ce[4]:#010x}" if ce else "")))
    npass += at30_ok

    if not quiet:
        tag = f"[bug={bug}]" if bug else "[clean]"
        print(f"===== ALU ATDD {tag}  (n={n}) =====")
        for name, ok, detail in results:
            print(f"  [{'PASS' if ok else 'FAIL'}] {name:30} {detail if not ok else ''}".rstrip())
        print(f"----- {npass}/{len(results)} acceptance tests passed -----")
    return npass, len(results), results


def main():
    bug = None; n = 100000
    if "--bug" in sys.argv: bug = sys.argv[sys.argv.index("--bug") + 1]
    if "--n" in sys.argv: n = int(sys.argv[sys.argv.index("--n") + 1])
    npass, total, _ = run(bug=bug, n=n)
    if bug is None:
        # auto-demo: fault injection must be caught (counter-examples)
        print("\n===== Counter-example 시연 (결함 주입 → 반례 검출 기대) =====")
        for fb in ("sra", "slt", "shamt"):
            p, t, _ = run(bug=fb, n=n, quiet=True)
            caught = t - p
            print(f"  --bug {fb:6}: {p}/{t} 통과  → {caught}개 AT가 반례로 결함 검출 "
                  f"({'OK 검출' if caught > 0 else 'FAIL 미검출'})")
    return 0 if npass == total else 1


if __name__ == "__main__":
    sys.exit(main())
