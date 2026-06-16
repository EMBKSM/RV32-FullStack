"""Self-checking unit test for the RV32 host assembler (rv32_console.assemble).

    python host_app/test_assembler.py      # prints PASS/FAIL per case + summary

Covers pseudo-op expansion (li 32-bit, b*z), encoding correctness against known-good
machine code, and the range-checks that reject out-of-range immediates (which used to
truncate silently). Exit code 0 = all pass.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rv32_console as A

npass = nfail = 0
def _ok(cond, name, extra=""):
    global npass, nfail
    if cond:
        npass += 1; print("PASS", name)
    else:
        nfail += 1; print("FAIL", name, "--", extra)

def words(src):
    return A.assemble(src.split("\n"))

def eq(name, src, expected):
    """assembles to exactly `expected` words"""
    try:
        w = words(src)
    except Exception as e:
        _ok(False, name, f"unexpected error: {e}"); return
    _ok(w == expected, name,
        f"got {[hex(x) for x in w]} expected {[hex(x) for x in expected]}")

def raises(name, src):
    """must raise ValueError (out of range / bad operand / unknown label)"""
    try:
        words(src)
        _ok(False, name, "expected an error but it assembled OK")
    except ValueError:
        _ok(True, name)
    except Exception as e:
        _ok(False, name, f"wrong error type {type(e).__name__}: {e}")

# ---- valid encodings (ground truth, verified on hardware/decoder) ----
eq("li small (addi)",   "li x2, 24",          [0x01800113])
eq("li 32-bit addr",    "li x1, 0x10000040",  [0x100000b7, 0x04008093])
eq("li 0xDEADBEEF",     "li x6, 0xDEADBEEF",  [0xdeadc337, 0xeef30313])
eq("li hi-aligned",     "li x8, 0xFFFFF000",  [0xfffff437])
eq("li negative",       "li x7, -5",          [0xffb00393])
eq("addi",              "addi x1, x0, 5",     [0x00500093])
eq("sw dec offset",     "sw x2, 8(x1)",       [0x0020a423])
eq("lw 0x hex offset",  "lw x4, 0x10(x1)",    [0x0100a203])
eq("bnez + label",      "bnez x3, here\nhere: nop", [0x00019263, 0x00000013])

# ---- range checks: these used to truncate silently, now must raise ----
raises("addi out of range",    "addi x1, x0, 5000")
raises("load off out of range", "lw x1, 0x800(x2)")
raises("store off out of range","sw x1, 2048(x2)")
raises("lui out of range",      "lui x1, 0x123456")
raises("shamt > 31",            "slli x1, x2, 40")
raises("undefined label",       "bne x1, x2, nowhere")
raises("bare-hex offset",       "lw x1, ff(x2)")

# ---- the README SPI example assembles cleanly ----
example = """    lui x1, 0x10000
    addi x1, x1, 0x40
    li x2, 24
    sw x2, 8(x1)
    sw x0, 0(x1)
    li x2, 0x55
    sw x2, 12(x1)
wait:
    lw x3, 4(x1)
    andi x3, x3, 1
    bne x3, x0, wait
    lw x4, 16(x1)"""
try:
    _ok(len(words(example)) == 11, "README SPI example (11 words)")
except Exception as e:
    _ok(False, "README SPI example", f"error: {e}")

print(f"\n=== assembler test: {npass} passed, {nfail} failed ===")
sys.exit(1 if nfail else 0)
