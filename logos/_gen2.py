#!/usr/bin/env python3
# Bold geometric app-tiles — channeling the user's 4 refs:
# simple primitives, app-tile, simple-but-distinctive color, one memory point each.
import math, os
OUT="tiles"; os.makedirs(OUT, exist_ok=True)

TILE="#1B1E22"; WHITE="#F4F5F5"; TEAL="#57D7BA"; AQUA="#8CEDE3"; CORAL="#FF3D51"; DARK="#12181B"

def pt(cx,cy,r,deg):
    a=math.radians(deg); return (round(cx+r*math.cos(a),1), round(cy+r*math.sin(a),1))
def Arc(cx,cy,r,a0,a1,sweep=1,large=0):
    x0,y0=pt(cx,cy,r,a0); x1,y1=pt(cx,cy,r,a1)
    return f'M{x0} {y0} A{r} {r} 0 {large} {sweep} {x1} {y1}'
def circ(cx,cy,r,fill="none",stroke=None,sw=0):
    s=f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    return s+'/>'
def rect(x,y,w,h,rx,fill,stroke=None,sw=0):
    s=f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    return s+'/>'
def path(d,stroke=None,sw=0,fill="none"):
    s=f'<path d="{d}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
    return s+'/>'
def tile(bg): return rect(0,0,512,512,120,bg)
def svg(body): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="prismo">\n{body}\n</svg>\n'

items=[]
def add(num,slug,grp,name,mem,body): items.append((num,slug,grp,name,mem,body))

# ===== Group 1 — bold mono (white on charcoal) =====
add(1,"ring-chevron","1","环 + 收拢 V","环=统一信号，下方 V=把所有讨论收拢进来（致敬参考①）",
    tile(TILE)+circ(256,206,76,stroke=WHITE,sw=34)+path("M174 312 L256 366 L338 312",stroke=WHITE,sw=34))
add(2,"bold-p","1","几何 P","最干净的两笔几何 P：一竖 + 半环",
    tile(TILE)+rect(176,150,40,224,20,WHITE)+path(Arc(196,208,60,-90,90),stroke=WHITE,sw=40))
add(3,"ring-node","1","环 + 信号点","整环=全部讨论，12 点钟一颗青绿=浮出的信号",
    tile(TILE)+circ(256,256,88,stroke=WHITE,sw=34)+circ(256,168,22,fill=TEAL))
add(4,"split-o","1","对半 o","一枚对半分的 o/币：上白下青，两侧市场",
    tile(TILE)+path("M164 251 A92 92 0 0 1 348 251 Z",fill=WHITE)+path("M164 261 A92 92 0 0 0 348 261 Z",fill=TEAL))
add(5,"target","1","同心靶","粗描同心圆：把一切聚到靶心",
    tile(TILE)+circ(256,256,92,stroke=WHITE,sw=28)+circ(256,256,48,stroke=TEAL,sw=24)+circ(256,256,10,fill=WHITE))

# ===== Group 2 — simple but distinctive color =====
add(6,"banded-lens","2","光谱币","把多方信号收进一枚'光谱币'（致敬参考②的配色）",
    tile(TILE)+'<defs><clipPath id="c6"><circle cx="256" cy="256" r="96"/></clipPath></defs>'
    +'<g clip-path="url(#c6)">'+rect(160,160,192,64,0,CORAL)+rect(160,224,192,64,0,AQUA)+rect(160,288,192,64,0,TEAL)+'</g>'
    +circ(256,256,96,stroke=WHITE,sw=5))
add(7,"coral-p","2","珊瑚 P","白竖 + 珊瑚红半环：一个有记忆点颜色的 P",
    tile(TILE)+rect(176,150,40,224,20,WHITE)+path(Arc(196,208,60,-90,90),stroke=CORAL,sw=40))
add(8,"shape-stack","2","几何拼贴","四块纯色简形堆成一个字（致敬参考④ Figma）",
    tile(TILE)+rect(176,158,160,52,26,CORAL)+rect(176,230,118,52,26,TEAL)+circ(318,256,26,fill=AQUA)+rect(176,302,84,52,26,WHITE))

# ===== Group 3 — one mark (几何 P), three simple color fields =====
add(9,"p-on-teal","3","P · 青绿场","同一个 P，放到青绿色场（深色描）",
    tile(TEAL)+rect(176,150,40,224,20,DARK)+path(Arc(196,208,60,-90,90),stroke=DARK,sw=40))
add(10,"p-on-coral","3","P · 珊瑚场","同一个 P，放到珊瑚色场（白描）",
    tile(CORAL)+rect(176,150,40,224,20,WHITE)+path(Arc(196,208,60,-90,90),stroke=WHITE,sw=40))

for num,slug,grp,name,mem,body in items:
    open(os.path.join(OUT,f"{num:02d}-{slug}.svg"),"w").write(svg(body))

groups=[("1","极简·白（炭黑底）"),("2","简单但不普通的颜色"),("3","同一个「几何 P」× 三种简单色场")]
sec=""
for gk,gt in groups:
    cards=""
    for num,slug,grp,name,mem,body in items:
        if grp!=gk: continue
        cards+=(f'<div class="card"><div class="ci"><img src="{OUT}/{num:02d}-{slug}.svg" alt="{num}"></div>'
                f'<div class="cl"><b>{num:02d} · {name}</b><span>{mem}</span></div></div>\n')
    sec+=f'<h2>{gt}</h2>\n<div class="grid">\n{cards}</div>\n'

html=f'''<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Prismo · bold tiles</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;background:#0E0E0E;color:#ECEDED;padding:2.4rem 2rem 4rem}}
.head{{display:flex;justify-content:space-between;align-items:center}}
h1{{font-size:1.35rem;font-weight:600}}
h2{{font-size:.95rem;font-weight:600;opacity:.9;margin:2.4rem 0 1rem;border-left:3px solid {TEAL};padding-left:.6rem}}
.sub{{font-size:.85rem;opacity:.55;margin-top:.4rem;max-width:64ch;line-height:1.55}}
.grid{{display:grid;gap:1.3rem;grid-template-columns:repeat(auto-fill,minmax(210px,1fr))}}
.card{{border:1px solid rgba(140,140,140,.2);border-radius:14px;overflow:hidden;background:#101010}}
.ci{{display:flex;align-items:center;justify-content:center;padding:1.5rem;background:#0E0E0E}}
.ci img{{width:170px;height:170px}}
.cl{{padding:.6rem .85rem;border-top:1px solid rgba(140,140,140,.16);font-size:.82rem;display:flex;flex-direction:column;gap:.15rem}}
.cl b{{font-weight:600}} .cl span{{opacity:.5;font-size:.74rem;line-height:1.4}}
</style></head><body>
<div class="head"><h1>Prismo · 粗描几何 App 砖</h1></div>
<p class="sub">按你给的 4 张参考重做：简单几何 + 简单但不普通的颜色 + 每个一个记忆点 + App 砖。挑 1–2 个编号，我再上字标锁版、做横排/竖排、精修、导出全套。</p>
{sec}
</body></html>'''
open("preview.html","w").write(html)
print(f"wrote {len(items)} tiles + preview.html")
