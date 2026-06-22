import sys, traceback
sys.path.insert(0, r'C:\work\github\RV32-FullStack\host_app')
try:
    import rv32_console as A
except Exception as e:
    print("IMPORT FAIL:", e); traceback.print_exc(); sys.exit(1)

def show(name, src):
    try:
        w = A.assemble(src.split('\n'))
        print(f"{name}: {len(w)} words: " + " ".join('0x%08x' % x for x in w))
    except Exception as e:
        print(f"{name}: ERROR {e}")

show("li_small(24)",        "li x2, 24")
show("li_byte(0x55)",       "li x2, 0x55")
show("li_addr(0x10000040)", "li x1, 0x10000040")
show("li_deadbeef",         "li x6, 0xDEADBEEF")
show("li_neg(-5)",          "li x7, -5")
show("li_hi(0xFFFFF000)",   "li x8, 0xFFFFF000")
show("bnez",                "bnez x3, here\nhere: nop")
show("bltz/blez/bgtz",      "bltz x5, t\nblez x5, t\nbgtz x5, t\nt: nop")
show("EXAMPLE", """    lui x1, 0x10000
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
    lw x4, 16(x1)""")
print("DONE")
