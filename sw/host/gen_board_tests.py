import sys; sys.path.insert(0,'.')
from rv32_console import assemble

def g(op,d=0,a=0,b=0,imm=0):           # GPU ISA encoder: [31:26]op [25:23]d [22:20]a [19:17]b [16:0]imm
    return ((op&0x3F)<<26)|((d&7)<<23)|((a&7)<<20)|((b&7)<<17)|(imm&0x1FFFF)
OPV={'HALT':0,'VLID':1,'VMOVI':2,'VST':4,'VADD':5,'VSUB':6,'VAND':7,'VOR':8,'VXOR':9,
     'VSLL':10,'VSRL':11,'VSRA':12,'VMIN':13,'VMAX':14,'VMUL':15,'VMAC':16,'SADDI':21,'SBNZ':22}

def drv(kernel):                       # RV32 driver: load GPU kernel, run, read lanes0-3 -> x10..x13
    L=['li x4,0x40000000','li x1,0x40001000','li x2,0x40004000']
    for i,w in enumerate(kernel):
        L += ([f'sw x0,{i*4}(x1)'] if w==0 else [f'li x5,0x{w:08X}',f'sw x5,{i*4}(x1)'])
    L += ['li x5,1','sw x5,0(x4)','poll:','lw x6,4(x4)','andi x6,x6,1','beqz x6,poll']
    for k in range(4): L += [f'lw x{10+k},{k*4}(x2)',f'lw x{10+k},{k*4}(x2)']
    L += ['done:','jal x0,done']
    return assemble(L)

def gpu_binop(opname,va,vb,extra=None):   # kernel: V1=va,V2=vb,[extra],OP V3,V1,V2,VST,HALT
    k=[g(OPV['VMOVI'],d=1,imm=va), g(OPV['VMOVI'],d=2,imm=vb)]
    if extra is not None: k.append(extra)
    k += [g(OPV[opname],d=3,a=1,b=2), g(OPV['VST'],a=0,b=3), g(OPV['HALT'])]
    return k

tests=[]   # (name, progwords, [reg,exp,...])

# 1) RV32 loop: sum 1..10 = 55
tests.append(('RV32_loop_sum1..10',
  assemble(['li x10,0','li x11,1','li x12,11','loop:','add x10,x10,x11','addi x11,x11,1','blt x11,x12,loop','done:','jal x0,done']),
  [10,55]))

# 2) NPU GEMM (existing 32-word driver) -> C=39,53,17,23
gemm=[0x30000237,0x300010b7,0x30002137,0x300031b7,0x00200293,0x00522423,0x00300313,0x0060a023,
 0x00400313,0x0060a223,0x00100313,0x1060a023,0x00200313,0x1060a223,0x00500393,0x00712023,
 0x00600393,0x00712223,0x00700393,0x10712023,0x00800393,0x10712223,0x00300413,0x00822023,
 0x00422483,0x0024f493,0xfe048ce3,0x0001a503,0x0041a583,0x0401a603,0x0441a683,0x0000006f]
tests.append(('NPU_GEMM_2x2', gemm, [10,39,11,53,12,17,13,23]))

# 3) GPU vector ops (result V3[k] broadcast -> all lanes equal)
def m32(x): return x & 0xFFFFFFFF
for nm,va,vb,exp in [('VADD',12,10,22),('VSUB',12,10,2),('VAND',12,10,8),('VOR',12,10,14),
                     ('VXOR',12,10,6),('VMIN',12,10,10),('VMAX',12,10,12),('VMUL',6,7,42),
                     ('VSLL',3,4,48),('VSRL',200,3,25)]:
    tests.append(('GPU_'+nm, drv(gpu_binop(nm,va,vb)), [10,exp,11,exp,12,exp,13,exp]))
# VMAC: V3=5 then V3 += 6*7 = 47  (extra VMOVI V3=5 before the MAC; MAC uses old V3)
kmac=[g(OPV['VMOVI'],d=1,imm=6),g(OPV['VMOVI'],d=2,imm=7),g(OPV['VMOVI'],d=3,imm=5),
      g(OPV['VMAC'],d=3,a=1,b=2),g(OPV['VST'],a=0,b=3),g(OPV['HALT'])]
tests.append(('GPU_VMAC_5+6*7', drv(kmac), [10,47,11,47,12,47,13,47]))

# 4) GPU branch-LOOP (SBNZ): V3=0; S1=5; loop{ V3+=V1(=1); S1-- } while S1!=0  -> V3=5
kloop=[g(OPV['VMOVI'],d=1,imm=1),          # 0 V1=1
       g(OPV['VMOVI'],d=3,imm=0),          # 1 V3=0
       g(OPV['SADDI'],d=1,a=0,imm=5),      # 2 S1=S0+5=5
       g(OPV['VADD'],d=3,a=3,b=1),         # 3 loop: V3+=V1
       g(OPV['SADDI'],d=1,a=1,imm=-1),     # 4 S1--
       g(OPV['SBNZ'],a=1,imm=-2),          # 5 if S1!=0 goto 3
       g(OPV['VST'],a=0,b=3),              # 6 store V3
       g(OPV['HALT'])]                     # 7
tests.append(('GPU_SBNZ_loop_x5', drv(kloop), [10,5,11,5,12,5,13,5]))

# ---- emit XSCT tcl ----
out=[]
out.append('# AUTO-GENERATED comprehensive on-board test of the unified NPU/GPU @100MHz.')
out.append('connect')
out.append('source C:/work/github/RV32-FullStack/flash/ps7_init.tcl')
out.append('targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}')
out.append('configparams force-mem-access 1')
out.append('rst -processor')
out.append('ps7_mio_init_data_3_0; ps7_pll_init_data_3_0; ps7_clock_init_data_3_0; ps7_peripherals_init_data_3_0')
out.append('mwr 0xF8000008 0x0000DF0D; mwr 0xF8000170 0x00100A00; mwr 0xF8000004 0x0000767B')
out.append('fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_unified_100mhz.bit')
out.append('ps7_post_config')
out.append('memmap -addr 0x40000000 -size 0x00010000 -flags 3')
out.append('set B 0x40000000')
out.append('proc rdreg {B n} { mwr [expr {$B + 0x18}] $n ; return [lindex [mrd -value [expr {$B + 0x1C}]] 0] }')
out.append('set NP 0; set NF 0')
out.append('proc runtest {name prog golden} {')
out.append('  global B NP NF')
out.append('  mwr [expr {$B+0x00}] 0x1')
out.append('  foreach {a w} $prog { mwr [expr {$B+0x08}] $a ; mwr [expr {$B+0x0C}] $w }')
out.append('  mwr [expr {$B+0x00}] 0x2')
out.append('  after 200')
out.append('  set ok 1; set msg ""')
out.append('  foreach {n exp} $golden { set got [rdreg $B $n]; if {$got != $exp} { set ok 0; append msg " x${n}=${got}(exp${exp})" } }')
out.append('  if {$ok} { incr NP; puts [format "  PASS  %-22s %s" $name $golden] } else { incr NF; puts [format "  FAIL  %-22s ->%s" $name $msg] }')
out.append('}')
for nm,prog,gold in tests:
    pw=' '.join('%d 0x%08x'%(i*4,w&0xFFFFFFFF) for i,w in enumerate(prog))
    gw=' '.join(str(x) for x in gold)
    out.append('runtest %-22s {%s} {%s}' % ('{'+nm+'}', pw, gw))
out.append('puts "==== COMPREHENSIVE BOARD TEST: $NP PASS / $NF FAIL ===="')
out.append('disconnect')
out.append('puts "COMPREHENSIVE-TEST-COMPLETE"')
open('/sessions/lucid-intelligent-einstein/mnt/RV32-FullStack/flash/jtag_comprehensive.tcl','w').write('\n'.join(out)+'\n')
print("tests:",len(tests)," tcl lines:",len(out))
for nm,prog,gold in tests: print("  %-22s %d words  golden=%s"%(nm,len(prog),gold))
