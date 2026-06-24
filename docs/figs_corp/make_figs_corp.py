# Academic-minimal diagrams for the RV32-FullStack presentation.
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle, Circle
from matplotlib.lines import Line2D

INK="#1c3a5e"; FILL="#eef4fb"; FILL2="#dce8f5"; ACC="#2680d4"; ACC2="#5f9e30"
MUT="#6b7d92"; LINE="#39517a"; HL="#cfe6f7"; WHITE="#ffffff"; GRID="#c2d2e3"
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":10})
OUT="/sessions/lucid-intelligent-einstein/mnt/RV32-FullStack/docs/figs_corp/"

def newfig(w,h):
    fig,ax=plt.subplots(figsize=(w,h),dpi=200); ax.set_xlim(0,100); ax.set_ylim(0,100)
    ax.axis("off"); return fig,ax
def box(ax,x,y,w,h,t,fc=FILL,ec=INK,fs=10,bold=False,tc=INK,lw=1.4,r=0.025):
    p=FancyBboxPatch((x,y),w,h,boxstyle=f"round,pad=0.2,rounding_size={r*100}",
        fc=fc,ec=ec,lw=lw,mutation_aspect=h/max(w,1)); ax.add_patch(p)
    ax.text(x+w/2,y+h/2,t,ha="center",va="center",fontsize=fs,color=tc,
        fontweight="bold" if bold else "normal",linespacing=1.35,zorder=5)
def arr(ax,x1,y1,x2,y2,c=LINE,lw=1.6,style="-|>",ls="-"):
    ax.add_patch(FancyArrowPatch((x1,y1),(x2,y2),arrowstyle=style,mutation_scale=14,
        lw=lw,color=c,ls=ls,shrinkA=0,shrinkB=0,zorder=4))
def lbl(ax,x,y,t,fs=8.5,c=MUT,ha="center",rot=0,bold=False):
    ax.text(x,y,t,ha=ha,va="center",fontsize=fs,color=c,rotation=rot,
        fontweight="bold" if bold else "normal",zorder=6)
def title(ax,t):
    ax.text(50,97,t,ha="center",va="top",fontsize=15,color=INK,fontweight="bold")
def save(fig,name):
    fig.savefig(OUT+name,bbox_inches="tight",pad_inches=0.12,facecolor="white"); plt.close(fig)

# ---------- 1. System architecture (PS / PL) ----------
fig,ax=newfig(11,7.2); title(ax,"System Architecture  ·  PS-host-controlled RV32 + NPU SoC")
box(ax,28,84,44,9,"Host PC\nRISC-V assembler · Python GUI (PySide6)",fc="#dbeafe",fs=9.5,bold=True)
box(ax,28,69,44,9,"Zynq PS  ·  ARM Cortex-A9\nbare-metal monitor (rv32_monitor.c) / JTAG (XSDB)",fc="#dcfce7",fs=10,bold=True)
# PL container
ax.add_patch(FancyBboxPatch((6,6),88,55,boxstyle="round,pad=0.2,rounding_size=2.5",
    fc="#eef5fc",ec=ACC2,lw=1.8)); lbl(ax,11,57.5,"Zynq PL  —  rv32_platform  (XC7Z020)",fs=11,c=ACC2,ha="left",bold=True)
box(ax,10,40,17,11,"AXI-Lite\nctrl slave\n(load/run/\nreadback)",fc=FILL,fs=8.5)
box(ax,30,40,19,11,"RV32 Core\n5-stage pipeline\nRV32I + FENCE.I",fc="#e0f2fe",fs=9,bold=True)
box(ax,52,40,17,11,"I$ / D$\nLUTRAM\n+ BRAM",fc=FILL,fs=8.5)
box(ax,72,40,18,11,"MMIO Bridge\n0x1xxx / 0x3xxx",fc=FILL,fs=8.5)
box(ax,30,22,39,12,"NPU  ·  16x16 INT8 systolic GEMM\n256 MAC (200 DSP48 + 56 LUT-MAC)",fc="#e7f2d6",fs=9,bold=True)
box(ax,10,9,80,8,"Peripherals (Pmod JA-JE, 40 pin): 2x SPI · 2x I2C · UART · 4-ch PWM · 22-bit GPIO  |  LED/SW/BTN",fc=FILL2,fs=8.5)
box(ax,72,24,18,9,"PL MMCM\nclk_wiz\nFCLK0->106",fc="#ede9fe",fs=8.5,bold=True,ec=ACC)
arr(ax,50,84,50,78,c=MUT); lbl(ax,57,81,"UART 115200 / program",fs=8)
arr(ax,50,69,50,61.2,c=MUT); lbl(ax,58,65,"AXI-Lite @ 0x4000_0000",fs=8)
arr(ax,38.5,69,20,51,c=ACC2,ls="--"); lbl(ax,8,66,"JTAG ctrl_axi · DDR/OCM bypass",fs=7.5,c=ACC2,ha="left")
arr(ax,27,45.5,30,45.5); arr(ax,49,45.5,52,45.5); arr(ax,69,45.5,72,45.5)
arr(ax,49,42,49,34,c=ACC); arr(ax,72,40,69,34,c=ACC)
arr(ax,49,40,20,17,c=MUT,lw=1.2)
save(fig,"fig_arch.png")

# ---------- 2. SoC block diagram (PL internal) ----------
fig,ax=newfig(11,7.0); title(ax,"SoC Block Diagram  ·  rv32_platform internals + clocking")
box(ax,4,80,20,12,"PS  Cortex-A9\nM_AXI_GP0",fc="#dcfce7",fs=9,bold=True)
box(ax,4,60,20,11,"PS FCLK0\n100 MHz",fc="#dcfce7",fs=9)
box(ax,30,60,16,11,"clk_wiz\nMMCM\n100->106",fc="#ede9fe",fs=9,bold=True,ec=ACC)
box(ax,30,80,16,12,"AXI\nSmartConnect",fc=FILL,fs=9)
box(ax,52,73,16,19,"ctrl_axi\nAXI4-Lite\nslave\n@0x4000_0000",fc=FILL,fs=8.5,bold=True)
box(ax,74,73,22,19,"RV32 Core\nIF·ID·EX·MEM·WB\nforward + hazard\nI$ / D$ (LUTRAM)",fc="#e0f2fe",fs=9,bold=True)
box(ax,52,40,44,22,"mmio_bridge   (single-cycle decode)\n0x1xxx_xxxx MMIO  ·  0x3xxx_xxxx NPU",fc=FILL,fs=9.5,bold=True)
box(ax,8,8,40,26,"npu_top16  (N=16)\n- A/B scratchpads (distributed RAM)\n- skew feed (registered)\n- 16x16 PE array (output-stationary)\n- requantize (INT32->INT8)\n- 5-stage pipelined read-back",fc="#e7f2d6",fs=9,bold=True,ec=ACC2)
box(ax,54,8,42,26,"Peripherals\nSPI x2 · I2C x2 · UART\nPWM 4-ch · GPIO 22-bit\nLED / SW / BTN",fc=FILL2,fs=9)
arr(ax,24,86,30,86); arr(ax,24,65.5,30,65.5); lbl(ax,27,68,"100",fs=7.5)
arr(ax,38,71,38,80,c=ACC); lbl(ax,44.5,76,"106 MHz",fs=7.5,c=ACC)
arr(ax,46,86,52,84,c=LINE); arr(ax,46,84,74,84,c=LINE)
arr(ax,68,82,74,82);
arr(ax,74,76,68,76,c=ACC); lbl(ax,71,78.5,"clk",fs=7,c=ACC)
arr(ax,74,62,74,72,c=LINE); lbl(ax,80,66,"dmem / MMIO",fs=7.5)
arr(ax,60,40,40,34,c=ACC2); lbl(ax,44,37,"NPU window",fs=7.5,c=ACC2)
arr(ax,80,40,80,34,c=LINE); lbl(ax,86,37,"MMIO",fs=7.5)
save(fig,"fig_block.png")

# ---------- 3. RV32 5-stage pipeline ----------
fig,ax=newfig(11,5.6); title(ax,"RV32I Core  ·  classic 5-stage pipeline")
stages=[("IF","Instr Fetch\nPC, I$"),("ID","Decode\nregfile, imm"),("EX","Execute\nALU, branch"),
        ("MEM","Memory\nD$ / MMIO"),("WB","Writeback\nregfile")]
x=6; w=15; gap=3.5
xs=[]
for i,(s,d) in enumerate(stages):
    box(ax,x,45,w,22,f"{s}\n\n{d}",fc="#e0f2fe" if i in(0,2) else FILL,fs=10,bold=True)
    xs.append(x+w/2)
    if i>0: box(ax,x-gap+0.3,47,gap-1,18,"",fc="#c2d2e3",ec=MUT,lw=1,r=0.01)  # pipeline reg
    if i<4: arr(ax,x+w,56,x+w+gap,56)
    x+=w+gap
for i in range(1,5): lbl(ax,xs[i]-(w/2+gap/2),70,"reg",fs=7,c=MUT)
# forwarding + hazard
arr(ax,xs[3],45,xs[2],42,c=ACC,style="-|>",lw=1.6)
arr(ax,xs[4],42,xs[2]+2,40,c=ACC,style="-|>",lw=1.6)
lbl(ax,xs[3]-6,35,"EX/MEM, MEM/WB forwarding",fs=8.5,c=ACC,ha="center")
arr(ax,xs[2],72,xs[0],75,c=ACC2,style="-|>",lw=1.6)
lbl(ax,xs[1],79,"load-use hazard -> stall IF/ID  (critical path @ high clock)",fs=8.5,c=ACC2)
lbl(ax,50,20,"RV32I base ISA  ·  FENCE.I (self-modifying / I-cache invalidate)  ·  CSR + trap",fs=9,c=MUT)
save(fig,"fig_pipeline.png")

# ---------- 4. NPU systolic array ----------
fig,ax=newfig(10.5,7.2); title(ax,"NPU  ·  16x16 output-stationary INT8 systolic GEMM")
gx,gy=34,16; cell=8; n=5
for i in range(n):
    for j in range(n):
        fc="#e7f2d6" if (i+j)<3 else FILL
        box(ax,gx+j*cell,gy+(n-1-i)*cell,cell-1.2,cell-1.2,"PE",fc=fc,fs=8,lw=1.1,r=0.012)
lbl(ax,gx+n*cell+1,gy+(n-1)*cell+3,". . .",fs=12,c=INK,ha="left")
lbl(ax,gx+2*cell,gy-4,"16 columns  (B fed from top, propagates down)",fs=8.5,c=MUT)
ax.text(gx+n*cell/2,gy+n*cell+3,"PE[i][j]:  p += a·b",
        ha="center",fontsize=9.5,color=INK,fontweight="bold")
# A scratchpad (left) + B scratchpad (top)
box(ax,8,gy+6,18,n*cell-12,"A scratchpad\n16 rows\n(distributed RAM)\nskew feed a_west\n(registered)",fc="#e0f2fe",fs=8.5,bold=True)
box(ax,gx,gy+n*cell+8,n*cell-1,9,"B scratchpad  ·  skew feed b_north (registered)",fc="#e0f2fe",fs=8.5,bold=True)
for i in range(n): arr(ax,26,gy+(n-1-i)*cell+3.4,gx,gy+(n-1-i)*cell+3.4,c=ACC,lw=1.3)
for j in range(n): arr(ax,gx+j*cell+3.4,gy+n*cell+8,gx+j*cell+3.4,gy+n*cell+3,c=ACC,lw=1.3)
# requantize + readback (right)
box(ax,82,40,16,22,"Requantize\nINT32 -> INT8\nclip(acc*m\n>> sh)",fc="#e7f2d6",fs=8.5,bold=True,ec=ACC2)
box(ax,82,15,16,20,"Read-back\n5-stage pipe\ncol->row->\nmul->shift->\nclip",fc=FILL,fs=8.5,bold=True)
arr(ax,gx+n*cell,gy+n*cell-8,82,50,c=LINE); lbl(ax,75,58,"acc_flat\n256x32",fs=7.5)
arr(ax,82,40,82,35,c=LINE)
lbl(ax,50,6,"output-stationary  ·  A[i][t-i], B[t-j][j] skew  ·  t_last = K + 2N-2",fs=8.5,c=MUT)
save(fig,"fig_npu.png")

# ---------- 5. GEMM sequence diagram ----------
fig,ax=newfig(11,7.0); title(ax,"Control Flow  ·  GEMM call sequence (host -> RV32 -> NPU)")
actors=[("Host / JTAG\n(PS-AXI)",12),("RV32 Core",37),("mmio_bridge\n/ ctrl_axi",62),("NPU 16x16",86)]
top=86; bot=10
for name,x in actors:
    box(ax,x-9,top,18,7,name,fc=FILL,fs=8.5,bold=True)
    ax.add_line(Line2D([x,x],[top,bot],color=GRID,lw=1.2,ls=(0,(4,3))))
def msg(y,x1,x2,t,c=LINE,dash=False):
    arr(ax,x1,y,x2,y,c=c,ls="--" if dash else "-",lw=1.5)
    ax.text((x1+x2)/2,y+1.6,t,ha="center",fontsize=7.8,color=INK)
X=[a[1] for a in actors]
msg(80,X[0],X[1],"load RV32 imem (driver) via ctrl_axi",ACC2)
msg(73,X[1],X[3],"write A[i][k], B[k][j], K_DIM  (sw -> 0x3000_xxxx)")
msg(66,X[1],X[3],"CTRL = start | clr_acc")
# NPU self compute
ax.add_patch(Rectangle((X[3]-5,46),10,16,fc="#e7f2d6",ec=ACC2,lw=1.3,zorder=5))
ax.text(X[3],54,"systolic\ncompute\nK+2N-2\ncycles",ha="center",va="center",fontsize=7.6,color=INK,zorder=6)
msg(40,X[1],X[3],"poll STATUS.done  (lw, 5-cyc read)",MUT,dash=True)
msg(33,X[3],X[1],"done=1",MUT,dash=True)
msg(26,X[1],X[3],"read C[i][j]  (lw 0x3000_3xxx)")
msg(19,X[3],X[1],"C = [[39,53],[17,23]]",ACC)
msg(13,X[1],X[0],"readback x10..x13 via ctrl_axi  ==  golden  (PASS)",ACC)
save(fig,"fig_seq.png")

# ---------- 6. Module structure tree ----------
fig,ax=newfig(11,7.0); title(ax,"Program / Module Structure")
box(ax,36,86,28,8,"rv32_top  (Block Design)",fc="#dbeafe",fs=10,bold=True)
lvl2=[("ps7  (Cortex-A9)",6),("clk_wiz (MMCM)",27.5),("axi_smc",49),("rv32_platform",70)]
for t,x in lvl2:
    box(ax,x,70,21,8,t,fc=FILL,fs=8.5,bold=(t=="rv32_platform"))
    arr(ax,50,86,x+10.5,78,c=MUT,lw=1.1)
# platform children
plat=[("ctrl_axi",4,"AXI4-Lite slave"),("rv32_core",27,"5-stage units"),("icache/dcache",50,"LUTRAM+BRAM"),("mmio_bridge",74,"decode + peripherals")]
for t,x,d in plat:
    box(ax,x,52,21,9,f"{t}\n{d}",fc="#e0f2fe" if t in("rv32_core","mmio_bridge") else FILL,fs=8,bold=True)
    arr(ax,80,70,x+10.5,61,c=MUT,lw=1.0)
# core units
units="next_pc · pc_adder · regfile · imm_gen · control\nalu+alu_ctrl · bcu · forwarding · hazard · csr · trap"
box(ax,16,37,41,9,units,fc=FILL2,fs=7.2); arr(ax,37,52,37,46,c=MUT,lw=1)
# npu chain
box(ax,62,38,34,8,"npu_top16  ->  npu_array  ->  npu_pe",fc="#e7f2d6",fs=8.5,bold=True,ec=ACC2)
arr(ax,84,52,80,46,c=ACC2,lw=1.1)
box(ax,28,21,44,10,"Verification:  ISS golden · 100+ regress\n18,688-check NPU TB (xsim) · on-board GEMM",fc=FILL,fs=7.6)
box(ax,28,9,44,8,"Host SW:  rv32_console.py · rv32_gui.py (PySide6)",fc=FILL2,fs=7.8)
save(fig,"fig_modules.png")

# ---------- 7. Fmax journey ----------
fig,ax2=plt.subplots(figsize=(11,5.6),dpi=200)
names=["50\n(orig 16x16\nfail)","30\n(demo)","75\n(readback\npipeline)","94\n(+ requant\npipeline)","100\n(+ t-counter\nFCLK0/10)","106\n(+ retiming\n+ MMCM)"]
vals=[50,30,75,94,100,106]
cols=["#dce8f5",MUT,"#93c5fd","#60a5fa",ACC,ACC2]
bars=ax2.bar(range(len(vals)),vals,color=cols,edgecolor=INK,linewidth=1.2,width=0.66,zorder=3)
bars[0].set_hatch("///"); bars[0].set_edgecolor("#9ca3af")
for i,v in enumerate(vals):
    ax2.text(i,v+2,f"{v} MHz",ha="center",fontsize=10,fontweight="bold",color=INK)
ax2.axhline(100,color=ACC,lw=1,ls="--",zorder=1); ax2.text(5.45,101.5,"100 MHz",color=ACC,fontsize=8,ha="right")
ax2.set_xticks(range(len(names))); ax2.set_xticklabels(names,fontsize=8.6)
ax2.set_ylabel("PL clock (MHz)",fontsize=10,color=INK); ax2.set_ylim(0,120)
ax2.set_title("Fmax journey  ·  37 -> 106 MHz, board-verified at each step (zero MAC-array change)",
              fontsize=13,color=INK,fontweight="bold",pad=12)
for s in ["top","right"]: ax2.spines[s].set_visible(False)
ax2.spines["left"].set_color(GRID); ax2.spines["bottom"].set_color(GRID)
ax2.tick_params(colors=MUT); ax2.grid(axis="y",color="#eef4fb",zorder=0)
ax2.text(0,-20,"(also: 8x8 baseline ran at 50 MHz; the 16x16 NPU = 4x the MACs)",fontsize=8,color=MUT)
plt.savefig(OUT+"fig_fmax.png",bbox_inches="tight",pad_inches=0.15,facecolor="white"); plt.close(fig)

# ---------- 8. Read-back optimization ----------
fig,ax=newfig(11,5.8); title(ax,"Key optimization  ·  pipelined accumulator read-back")
box(ax,4,58,44,18,"BEFORE  (combinational)",fc="#fee2e2",ec="#b91c1c",fs=10,bold=True,tc="#b91c1c")
box(ax,6,40,18,12,"256x32\nacc_flat",fc=WHITE,fs=8.5)
box(ax,28,40,18,12,"256:1 mux\n34 levels",fc="#fecaca",fs=8.5,bold=True)
arr(ax,24,46,28,46,c="#b91c1c"); arr(ax,46,46,49,46,c="#b91c1c")
lbl(ax,49.5,46,"core",fs=8,ha="left")
lbl(ax,26,34,"critical path 26.7 ns  ->  Fmax 37 MHz",fs=9,c="#b91c1c",ha="center",bold=True)
box(ax,52,58,44,18,"AFTER  (registered stages)",fc="#dcfce7",ec=ACC,fs=10,bold=True,tc="#15803d")
for i,(t) in enumerate(["col\nselect","row\nselect","mul\n(DSP)","shift\n+round","clip\n/sel"]):
    box(ax,53+i*8.6,40,7.6,12,t,fc="#bbf7d0",fs=7.6,bold=True)
    if i>0: arr(ax,53+i*8.6-1,46,53+i*8.6,46,c=ACC,lw=1.3)
lbl(ax,74,34,"each hop < 10 ns  ·  5-cyc read, stall-handshake (transparent to SW)",fs=8.6,c="#15803d",ha="center",bold=True)
box(ax,18,12,64,12,"Same idea applied to: requant 32x17 multiply (-> DSP)  and  systolic t-counter feed\n(register a_west/b_north).  Diagnosis showed the MAC array was never the bottleneck (~0.5 ns).",fc=FILL,fs=9)
save(fig,"fig_readback.png")

print("DONE figs:",end=" ")
import os
print(", ".join(sorted(f for f in os.listdir(OUT) if f.endswith(".png"))))
                                                                             