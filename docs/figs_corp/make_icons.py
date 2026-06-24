# Flat white-glyph icons (transparent bg) for the corporate-infographic deck.
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyBboxPatch, Polygon, Wedge, Rectangle, Arc, Ellipse
from matplotlib.lines import Line2D
import numpy as np, os
OUT="/sessions/lucid-intelligent-einstein/mnt/RV32-FullStack/docs/figs_corp/icons/"
os.makedirs(OUT,exist_ok=True)
W="white"

def canvas():
    fig,ax=plt.subplots(figsize=(2.56,2.56),dpi=100)
    ax.set_xlim(0,100); ax.set_ylim(0,100); ax.axis("off"); ax.set_aspect("equal")
    return fig,ax
def save(fig,name):
    fig.savefig(OUT+name,transparent=True,bbox_inches="tight",pad_inches=0.05); plt.close(fig)
def L(ax,pts,lw=8,cap="round",join="round"):
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    ax.add_line(Line2D(xs,ys,color=W,lw=lw,solid_capstyle=cap,solid_joinstyle=join))

def ic_globe():
    f,ax=canvas(); c=(50,50); r=34
    ax.add_patch(Circle(c,r,fill=False,ec=W,lw=7))
    ax.add_patch(Ellipse(c,r*0.9,2*r,fill=False,ec=W,lw=5))
    ax.add_patch(Ellipse(c,2*r,r*0.95,fill=False,ec=W,lw=5))
    L(ax,[(50,16),(50,84)],5);
    ax.add_patch(Arc(c,2*r,2*r,theta1=200,theta2=340,color=W,lw=0))
    save(f,"globe.png")

def ic_gear():
    f,ax=canvas(); cx,cy=50,50; ro=36; ri=26; teeth=8
    pts=[]
    for i in range(teeth*2):
        ang=np.pi*i/teeth; rr=ro if i%2==0 else ri
        pts.append((cx+rr*np.cos(ang),cy+rr*np.sin(ang)))
    ax.add_patch(Polygon(pts,closed=True,fc="none",ec=W,lw=7,joinstyle="round"))
    ax.add_patch(Circle((cx,cy),12,fc="none",ec=W,lw=7))
    save(f,"gear.png")

def ic_gear_hole():
    f,ax=canvas(); cx,cy=50,50; ro=40; ri=29; teeth=8
    pts=[]
    for i in range(teeth*2):
        ang=np.pi*i/teeth; rr=ro if i%2==0 else ri
        pts.append((cx+rr*np.cos(ang),cy+rr*np.sin(ang)))
    ax.add_patch(Polygon(pts,closed=True,fc=W,ec=W,lw=1,joinstyle="round"))
    save(f,"gearf.png")

def ic_chip():
    f,ax=canvas()
    ax.add_patch(FancyBboxPatch((28,28),44,44,boxstyle="round,pad=0,rounding_size=6",fc="none",ec=W,lw=7))
    ax.add_patch(FancyBboxPatch((40,40),20,20,boxstyle="round,pad=0,rounding_size=3",fc=W,ec=W,lw=1))
    for k in range(3):
        x=37+k*13
        L(ax,[(x,72),(x,82)],6); L(ax,[(x,18),(x,28)],6)
        L(ax,[(72,37+k*13),(82,37+k*13)],6); L(ax,[(18,37+k*13),(28,37+k*13)],6)
    save(f,"chip.png")

def ic_search():
    f,ax=canvas()
    ax.add_patch(Circle((43,57),22,fill=False,ec=W,lw=7))
    L(ax,[(58,42),(80,20)],9)
    save(f,"search.png")

def ic_chartup():
    f,ax=canvas()
    L(ax,[(20,80),(20,20),(84,20)],7,cap="round")          # L axes, origin bottom-left
    L(ax,[(28,34),(44,48),(57,40),(77,63)],8)              # rising line
    ax.add_patch(Polygon([(84,68),(72,62),(79,55)],closed=True,fc=W,ec=W,joinstyle="round"))  # up-right arrow
    save(f,"chartup.png")

def ic_check():
    f,ax=canvas()
    ax.add_patch(Circle((50,50),36,fill=False,ec=W,lw=7))
    L(ax,[(33,51),(45,39),(68,65)],9)
    save(f,"check.png")

def ic_grid():
    f,ax=canvas()
    for r in range(3):
        for c in range(3):
            ax.add_patch(FancyBboxPatch((26+c*18,26+r*18),13,13,boxstyle="round,pad=0,rounding_size=2.5",fc=W,ec=W,lw=1))
    save(f,"grid.png")

def ic_db():
    f,ax=canvas(); cx=50; rx=26; ry=9
    ax.add_patch(Ellipse((cx,72),2*rx,2*ry,fc="none",ec=W,lw=7))
    L(ax,[(24,72),(24,32)],7); L(ax,[(76,72),(76,32)],7)
    ax.add_patch(Arc((cx,32),2*rx,2*ry,theta1=180,theta2=360,color=W,lw=7))
    ax.add_patch(Arc((cx,52),2*rx,2*ry,theta1=180,theta2=360,color=W,lw=5))
    save(f,"db.png")

def ic_bolt():
    f,ax=canvas()
    ax.add_patch(Polygon([(56,84),(30,50),(47,50),(42,16),(70,54),(52,54)],closed=True,fc=W,ec=W,lw=1,joinstyle="round"))
    save(f,"bolt.png")

def ic_layers():
    f,ax=canvas()
    for i,yy in enumerate([34,50,66]):
        ax.add_patch(Polygon([(50,yy-10),(80,yy),(50,yy+10),(20,yy)],closed=True,fc=(W if i==2 else "none"),ec=W,lw=6,joinstyle="round"))
    save(f,"layers.png")

def ic_clock():
    f,ax=canvas()
    ax.add_patch(Circle((50,50),34,fill=False,ec=W,lw=7))
    L(ax,[(50,50),(50,72)],7); L(ax,[(50,50),(65,50)],7)
    save(f,"clock.png")

def ic_doc():
    f,ax=canvas()
    ax.add_patch(Polygon([(30,18),(30,82),(70,82),(70,34),(54,18)],closed=True,fc="none",ec=W,lw=7,joinstyle="round"))
    L(ax,[(54,18),(54,34),(70,34)],6)
    for yy in (44,54,64): L(ax,[(40,yy),(60,yy)],5)
    save(f,"doc.png")

def ic_share():
    f,ax=canvas()
    for p in [(28,28),(28,72),(76,50)]: ax.add_patch(Circle(p,11,fc=W,ec=W))
    L(ax,[(34,33),(70,47)],6); L(ax,[(34,67),(70,53)],6)
    save(f,"share.png")

def ic_cpu_core():
    f,ax=canvas()
    ax.add_patch(FancyBboxPatch((26,26),48,48,boxstyle="round,pad=0,rounding_size=8",fc="none",ec=W,lw=7))
    for i in range(4):
        x=33+i*11.5
        L(ax,[(x,74),(x,84)],5); L(ax,[(x,16),(x,26)],5)
        L(ax,[(74,33+i*11.5),(84,33+i*11.5)],5); L(ax,[(16,33+i*11.5),(26,33+i*11.5)],5)
    ax.text(50,50,"RV",ha="center",va="center",color=W,fontsize=15,fontweight="bold")
    save(f,"core.png")

for fn in [ic_globe,ic_gear,ic_gear_hole,ic_chip,ic_search,ic_chartup,ic_check,ic_grid,ic_db,ic_bolt,ic_layers,ic_clock,ic_doc,ic_share,ic_cpu_core]:
    fn()
print("icons:",", ".join(sorted(os.listdir(OUT))))
