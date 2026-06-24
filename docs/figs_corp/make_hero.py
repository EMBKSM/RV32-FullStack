# Title/closing hero motif (globe + orbiting icon circles + gears) and blue bg texture.
from PIL import Image, ImageDraw, ImageFilter
import math, os
D="/sessions/lucid-intelligent-einstein/mnt/RV32-FullStack/docs/figs_corp/"
IC=D+"icons/"

RED=(232,82,63); ORANGE=(245,166,35); GREEN=(124,179,66); TEAL=(25,181,201)
BLUE=(38,128,212); PURPLE=(142,91,166); GLOBE=(46,123,214); GLOBED=(30,92,170)

def cog(draw,cx,cy,ro,ri,teeth,fill,width=0):
    pts=[]
    for i in range(teeth*2):
        a=math.pi*i/teeth; r=ro if i%2==0 else ri
        pts.append((cx+r*math.cos(a),cy+r*math.sin(a)))
    if width: draw.line(pts+[pts[0]],fill=fill,width=width,joint="curve")
    else: draw.polygon(pts,fill=fill)

# ---------- HERO ----------
S=4  # supersample
W,H=1200,1020
img=Image.new("RGBA",(W*S,H*S),(0,0,0,0)); d=ImageDraw.Draw(img)
cx,cy=600*S,575*S; R=232*S

# faint gears behind
for (gx,gy,gr) in [(330,300,150),(880,760,175),(870,300,95)]:
    g=Image.new("RGBA",img.size,(0,0,0,0)); dg=ImageDraw.Draw(g)
    cog(dg,gx*S,gy*S,gr*S,gr*0.7*S,9,(255,255,255,30))
    dg.ellipse([(gx-gr*0.34)*S,(gy-gr*0.34)*S,(gx+gr*0.34)*S,(gy+gr*0.34)*S],fill=(0,0,0,0))
    img=Image.alpha_composite(img,g); d=ImageDraw.Draw(img)

# globe shadow
sh=Image.new("RGBA",img.size,(0,0,0,0)); ds=ImageDraw.Draw(sh)
ds.ellipse([cx-R,cy-R+18*S,cx+R,cy+R+18*S],fill=(20,50,90,90))
sh=sh.filter(ImageFilter.GaussianBlur(14*S)); img=Image.alpha_composite(img,sh); d=ImageDraw.Draw(img)
# globe body (radial-ish: base + lighter top-left)
d.ellipse([cx-R,cy-R,cx+R,cy+R],fill=GLOBE+(255,))
hl=Image.new("RGBA",img.size,(0,0,0,0)); dh=ImageDraw.Draw(hl)
dh.ellipse([cx-R*0.92,cy-R*0.92,cx+R*0.2,cy+R*0.2],fill=(120,180,240,90))
hl=hl.filter(ImageFilter.GaussianBlur(20*S));
m=Image.new("L",img.size,0); dm=ImageDraw.Draw(m); dm.ellipse([cx-R,cy-R,cx+R,cy+R],fill=255)
img.paste(Image.alpha_composite(img.crop((0,0,W*S,H*S)),hl),(0,0),m); d=ImageDraw.Draw(img)
# meridians & parallels (white)
lw=max(2,int(3.2*S))
for fr in (0.42,0.78):
    d.ellipse([cx-R*fr,cy-R,cx+R*fr,cy+R],outline=(255,255,255,235),width=lw)
for fr in (0.5,0.85):
    d.ellipse([cx-R,cy-R*fr,cx+R,cy+R*fr],outline=(255,255,255,235),width=lw)
d.line([cx,cy-R,cx,cy+R],fill=(255,255,255,235),width=lw)
d.line([cx-R,cy,cx+R,cy],fill=(255,255,255,235),width=lw)
d.ellipse([cx-R,cy-R,cx+R,cy+R],outline=(255,255,255,255),width=int(4*S))

# orbiting icon circles
specs=[(158,TEAL,"share"),(123,GREEN,"check"),(90,RED,"bolt"),(57,ORANGE,"chartup"),(22,BLUE,"chip")]
OR=338*S; cr=78*S
for ang,col,icon in specs:
    a=math.radians(ang); ix=cx+OR*math.cos(a); iy=cy-OR*math.sin(a)
    # connector dots
    gx0=cx+(R+10*S)*math.cos(a); gy0=cy-(R+10*S)*math.sin(a)
    gx1=ix-cr*math.cos(a); gy1=iy+cr*math.sin(a)
    nd=5
    for t in range(nd+1):
        px=gx0+(gx1-gx0)*t/nd; py=gy0+(gy1-gy0)*t/nd
        d.ellipse([px-3*S,py-3*S,px+3*S,py+3*S],fill=(255,255,255,150))
    # shadow
    cs=Image.new("RGBA",img.size,(0,0,0,0)); dcs=ImageDraw.Draw(cs)
    dcs.ellipse([ix-cr,iy-cr+10*S,ix+cr,iy+cr+10*S],fill=(20,40,70,110))
    cs=cs.filter(ImageFilter.GaussianBlur(9*S)); img=Image.alpha_composite(img,cs); d=ImageDraw.Draw(img)
    d.ellipse([ix-cr,iy-cr,ix+cr,iy+cr],fill=col+(255,))
    d.ellipse([ix-cr,iy-cr,ix+cr,iy+cr],outline=(255,255,255,60),width=int(2*S))
    ico=Image.open(IC+icon+".png").convert("RGBA")
    isz=int(cr*1.15); ico=ico.resize((isz,isz))
    img.paste(ico,(int(ix-isz/2),int(iy-isz/2)),ico)
    d=ImageDraw.Draw(img)

img=img.resize((W,H),Image.LANCZOS)
img.save(D+"hero.png"); print("hero.png",img.size)

# ---------- BLUE BG TEXTURE ----------
BW,BH=1333,750
bg=Image.new("RGB",(BW,BH),(19,58,110))
dt=ImageDraw.Draw(bg,"RGBA")
# subtle darker vignette bottom-right + faint dot grid
for yy in range(0,BH,24):
    for xx in range(0,BW,24):
        dt.ellipse([xx-2,yy-2,xx+2,yy+2],fill=(255,255,255,9))
# soft lighter glow top-left
gl=Image.new("RGBA",(BW,BH),(0,0,0,0)); dgl=ImageDraw.Draw(gl)
dgl.ellipse([-300,-380,620,420],fill=(60,120,200,55)); gl=gl.filter(ImageFilter.GaussianBlur(160))
bg=Image.alpha_composite(bg.convert("RGBA"),gl).convert("RGB")
bg.save(D+"bg_blue.png"); print("bg_blue.png",bg.size)
