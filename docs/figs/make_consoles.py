# Terminal/console-style screenshots of the REAL captured run outputs.
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle
OUT="/sessions/lucid-intelligent-einstein/mnt/RV32-FullStack/docs/figs/"
BG="#0d1117"; BAR="#161b22"; FG="#c9d1d9"; GRN="#3fb950"; YEL="#d29922"; CYAN="#39c5cf"; MUT="#8b949e"; RED="#f85149"; BLU="#58a6ff"

def term(name,title,lines,w=11,h=6.2):
    fig,ax=plt.subplots(figsize=(w,h),dpi=200); ax.set_xlim(0,100); ax.set_ylim(0,100); ax.axis("off")
    ax.add_patch(FancyBboxPatch((1,1),98,98,boxstyle="round,pad=0,rounding_size=2.2",fc=BG,ec="#30363d",lw=1.5))
    ax.add_patch(FancyBboxPatch((1,92),98,7,boxstyle="round,pad=0,rounding_size=2.2",fc=BAR,ec="none"))
    for i,c in enumerate(["#ff5f56","#ffbd2e","#27c93f"]): ax.add_patch(Circle((5+i*3.2,95.5),0.9,fc=c,ec="none"))
    ax.text(50,95.5,title,ha="center",va="center",fontsize=9.5,color=MUT,family="monospace")
    y=88
    for txt,col,sz in lines:
        ax.text(4,y,txt,ha="left",va="top",fontsize=sz,color=col,family="monospace")
        y-=(sz*0.62+1.7)
    fig.savefig(OUT+name,bbox_inches="tight",pad_inches=0.08,facecolor="white"); plt.close(fig)

# 1) Board GEMM @106MHz (MMCM) — real XSCT log
term("fig_board_console.png","xsct  —  jtag_gemm_test_mmcm.tcl   (real XC7Z020, JTAG)",[
 ("$ xsct jtag_gemm_test_mmcm.tcl",FG,10),
 ("### 16x16 + PL MMCM: FCLK0=100MHz -> MMCM -> 106MHz PL; driving RV32 via ctrl_axi ###",CYAN,9.2),
 ("### imem loaded (32 words); releasing RV32 ###",MUT,9.2),
 ("",FG,5),
 ("  PC      = 0x0000007c",FG,10),
 ("  STATUS  = 0x00000004        # halted, run_en latched",MUT,9.2),
 ("",FG,4),
 ("  BOARD  16x16 NPU GEMM @106MHz(MMCM):  C00=39  C01=53  C10=17  C11=23",BLU,9.6),
 ("  GOLDEN                             :  C00=39  C01=53  C10=17  C11=23",FG,9.6),
 ("",FG,4),
 (">>> BOARD-GEMM-MMCM-106MHZ: PASS",GRN,12.5),
 ("    (16x16 NPU @ 106 MHz via PL MMCM on real XC7Z020 matches golden)",GRN,9.0),
 ("",FG,4),
 ("GEMM-TEST-MMCM-COMPLETE   [xsct exit=0]",MUT,9.2),
],h=6.4)

# 2) Timing + verification summary panel
term("fig_timing_console.png","Vivado timing summary + functional regression",[
 ("# report_timing_summary  —  rv32_16x16_100mhz  (clk 100 MHz / 10.0 ns)",CYAN,9.4),
 ("",FG,3),
 ("  Design Timing Summary",FG,10),
 ("  -------------------------------------------------------------",MUT,8.6),
 ("    WNS(ns)   TNS(ns)   Failing EP     WHS(ns)    Failing EP",MUT,8.8),
 ("    +0.085     0.000        0          +0.014        0",GRN,10),
 ("",FG,2),
 ("  >> All user specified timing constraints are met.",GRN,10),
 ("",FG,3),
 ("# functional regression  —  verification/npu_scale16  (xsim)",CYAN,9.4),
 ("  -------------------------------------------------------------",MUT,8.6),
 ("  GEMM + 256 PE spatial corners + accumulate + 40 random + requant",FG,8.8),
 ("  checks = 18688      errors = 0",GRN,10.5),
 ("",FG,2),
 ("# resources (XC7Z020)   DSP 220/220 = 100%   (200 DSP + 56 LUT-MAC)",YEL,9.2),
 ("  RV32 core ~7.4k LUT   |   16x16 NPU ~8.1k LUT   |   LUT < 50%",FG,8.8),
],h=6.6)
print("DONE consoles")
