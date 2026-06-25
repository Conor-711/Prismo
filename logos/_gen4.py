#!/usr/bin/env python3
# 25 ORIGINAL bold-geometric app-tiles for Prismo, built from the extracted grammar.
import math, os
OUT="set25"; os.makedirs(OUT, exist_ok=True)
TILE="#1B1E22"; W="#F4F5F5"; TEAL="#57D7BA"; AQUA="#8CEDE3"; CORAL="#FF3D51"

def pt(cx,cy,r,d):
    a=math.radians(d); return (round(cx+r*math.cos(a),1), round(cy+r*math.sin(a),1))
def A(cx,cy,r,a0,a1,sweep=1,large=0):
    x0,y0=pt(cx,cy,r,a0); x1,y1=pt(cx,cy,r,a1)
    return f'M{x0} {y0} A{r} {r} 0 {large} {sweep} {x1} {y1}'
def circ(cx,cy,r,fill="none",stroke=None,sw=0,sop=None):
    s=f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    if sop is not None: s+=f' stroke-opacity="{sop}"'
    return s+'/>'
def ell(cx,cy,rx,ry,fill="none",stroke=None,sw=0):
    s=f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    return s+'/>'
def rect(x,y,w,h,rx,fill="none",stroke=None,sw=0):
    s=f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    return s+'/>'
def line(x1,y1,x2,y2,stroke,sw):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round"/>'
def path(d,stroke=None,sw=0,fill="none"):
    s=f'<path d="{d}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
    return s+'/>'
def L(text,x,y,size,fill,anchor="middle",weight=700):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" '
            f"font-family=\"'Avenir Next','Futura','Century Gothic',system-ui,sans-serif\" "
            f'font-size="{size}" font-weight="{weight}" letter-spacing="-1" fill="{fill}">{text}</text>')
def tile(body,bg=TILE):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="prismo">\n<rect width="512" height="512" rx="120" fill="{bg}"/>\n{body}\n</svg>\n'

I=[]
def add(n,slug,g,name,mem,body): I.append((n,slug,g,name,mem,body))

# ---- G1 字母 P / o ----
add(1,"aperture-p","1","光圈 P","P 的碗是一只镜头,瞳点=信号",
    rect(186,150,44,216,22,W)+circ(258,214,64,stroke=W,sw=40)+circ(258,214,18,fill=TEAL))
add(2,"solid-p","1","实心 P","最干净的实心几何 P",
    rect(176,150,44,216,22,W)+path("M220 150 A66 66 0 0 1 220 282 Z",fill=W)+circ(238,216,30,fill=TILE))
add(3,"coin-p","1","P 币","一枚实心币,镂出一个 P",
    circ(256,256,98,fill=W)+L("P",256,312,150,TILE))
add(4,"split-p","1","双色 P","P 的碗对半分两色",
    rect(176,150,44,216,22,W)+path("M220 150 A66 66 0 0 1 286 216 L220 216 Z",fill=CORAL)
    +path("M286 216 A66 66 0 0 1 220 282 L220 216 Z",fill=TEAL)+circ(236,216,26,fill=TILE))
add(5,"focus-o","1","聚焦 o","整环+12 点钟的信号点+靶心",
    circ(256,256,92,stroke=W,sw=36)+circ(256,164,20,fill=TEAL)+circ(256,256,12,fill=W))
add(6,"stack-p","1","积木 P","纯色简形堆出的 P",
    rect(176,158,150,48,24,CORAL)+rect(176,228,108,48,24,TEAL)+circ(316,252,26,fill=AQUA)+rect(176,298,80,48,24,W))
add(7,"lower-p","1","小写 p","小写 p,肚子是实心信号点",
    rect(180,140,40,206,20,W)+circ(246,196,52,fill=TEAL))

# ---- G2 聚合 many -> one ----
b=circ(256,256,96,stroke=W,sw=6,sop=0.32)
for i in range(8):
    x,y=pt(256,256,96,i*45-90); b+=circ(x,y,15,fill=W)
b+=circ(256,256,34,fill=TEAL)
add(8,"chorus","2","合声环","一圈声音围着被点亮的核",b)

b=circ(256,256,30,fill=TEAL)
for i in range(8):
    x0,y0=pt(256,256,52,i*45); x1,y1=pt(256,256,92,i*45); b+=line(x0,y0,x1,y1,W,16)
add(9,"converge","2","汇入","八方信息汇入核心",b)
add(10,"target","2","同心靶","把一切聚到靶心",
    circ(256,256,92,stroke=W,sw=28)+circ(256,256,48,stroke=TEAL,sw=24)+circ(256,256,10,fill=W))
add(11,"cluster","2","共识","三个声音叠出一个共识",
    circ(212,226,56,fill=TILE,stroke=W,sw=14)+circ(300,226,56,fill=TILE,stroke=W,sw=14)+circ(256,302,58,fill=TEAL))
b=""
for gx in (190,256,322):
    for gy in (190,256,322):
        if gx==256 and gy==256: b+=circ(gx,gy,24,fill=TEAL)
        else: b+=circ(gx,gy,14,fill=W)
add(12,"grid","2","放大一个","9 个里被放大的那一个",b)
add(13,"feed","2","信息流","流里被点亮的那一条",
    rect(150,168,212,34,17,W)+rect(150,220,212,34,17,TEAL)+rect(150,272,150,34,17,W)+rect(150,324,188,34,17,W))
add(14,"globe","2","全球之声","全球的声音汇成一个核",
    circ(256,256,92,stroke=W,sw=18)+ell(256,256,36,92,stroke=W,sw=10)+ell(256,256,92,36,stroke=W,sw=10)+circ(256,256,16,fill=TEAL))

# ---- G3 信号 / 行情 ----
add(15,"bars","3","三柱","三柱信号,最高那根浮出",
    rect(168,250,46,110,23,W)+rect(233,160,46,200,23,TEAL)+rect(298,210,46,150,23,W))
add(16,"gauge","3","表盘","开口表盘+一个读数",
    path(A(256,256,86,150,30,large=1),stroke=W,sw=34)+circ(*pt(256,256,86,-42),16,fill=TEAL)+circ(256,256,9,fill=W))
add(17,"steps","3","拾级","三阶上行,顶阶浮出",
    rect(158,288,66,66,12,W)+rect(230,248,66,66,12,W)+rect(302,208,66,66,12,TEAL))
add(18,"sunrise","3","日出","开盘的日出与地平线",
    path("M150 300 A106 106 0 0 1 362 300 Z",fill=W)+rect(150,316,212,16,8,TEAL))
add(19,"candle","3","K 线","一根干净的 K 线蜡烛",
    line(256,156,256,356,W,8)+rect(230,210,52,116,12,TEAL))
add(20,"throughline","3","穿越","穿过噪声的那条线",
    circ(256,256,86,stroke=W,sw=34)+rect(132,244,248,22,11,TEAL))

# ---- G4 讨论 / 货币 ----
add(21,"speech-coin","4","话币","气泡的中心是投币口",
    circ(256,238,92,stroke=W,sw=38)+path("M214 312 Q188 348 234 350",stroke=W,sw=30)+rect(222,230,68,16,8,TEAL))
add(22,"bubble-dot","4","标记一句","一句被标记的话",
    rect(150,158,212,150,40,stroke=W,sw=16)+circ(198,320,11,stroke=W,sw=16)+circ(256,233,22,fill=TEAL))
add(23,"dialogue","4","多空对话","两只气泡:多空对望",
    rect(138,168,150,108,30,stroke=TEAL,sw=14)+circ(166,290,8,stroke=TEAL,sw=14)
    +rect(232,210,150,108,30,stroke=W,sw=14)+circ(354,332,8,stroke=W,sw=14))
b=line(164,224,164,322,W,12)+line(348,224,348,322,W,12)
b+=ell(256,322,92,24,stroke=W,sw=12)+ell(256,272,92,24,stroke=W,sw=12)+ell(256,222,92,24,stroke=TEAL,sw=12)
add(24,"coin-stack","4","币摞","一摞硬币:沉淀的资产",b)
add(25,"quotes","4","引号","引号=众议,也是'报价'",
    rect(150,176,40,72,16,TEAL)+rect(202,176,40,72,16,TEAL)+rect(282,176,40,72,16,W)+rect(334,176,40,72,16,W))

for n,slug,g,name,mem,body in I:
    open(os.path.join(OUT,f"{n:02d}-{slug}.svg"),"w").write(tile(body))

groups=[("1","字母 P / o"),("2","聚合 · many → one"),("3","信号 / 行情"),("4","讨论 / 货币")]
sec=""
for gk,gt in groups:
    cards="".join(
        f'<div class="card"><div class="ci"><img src="{OUT}/{n:02d}-{slug}.svg"></div>'
        f'<div class="cl"><b>{n:02d} · {name}</b><span>{mem}</span></div></div>'
        for n,slug,g,name,mem,body in I if g==gk)
    sec+=f'<h2>{gt}</h2><div class="grid">{cards}</div>'
html=f'''<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Prismo · 25 bold tiles</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;background:#0E0E0E;color:#ECEDED;padding:2.2rem 2rem 4rem}}
h1{{font-size:1.35rem;font-weight:600}}
h2{{font-size:.95rem;font-weight:600;opacity:.9;margin:2.2rem 0 1rem;border-left:3px solid {TEAL};padding-left:.6rem}}
.sub{{font-size:.85rem;opacity:.55;margin:.4rem 0;max-width:66ch;line-height:1.5}}
.grid{{display:grid;gap:1.1rem;grid-template-columns:repeat(auto-fill,minmax(190px,1fr))}}
.card{{border:1px solid rgba(140,140,140,.2);border-radius:14px;overflow:hidden;background:#101010}}
.ci{{display:flex;align-items:center;justify-content:center;padding:1.3rem;background:#0E0E0E}}
.ci img{{width:156px;height:156px}}
.cl{{padding:.55rem .8rem;border-top:1px solid rgba(140,140,140,.16);font-size:.8rem;display:flex;flex-direction:column;gap:.12rem}}
.cl b{{font-weight:600}} .cl span{{opacity:.5;font-size:.73rem;line-height:1.35}}
</style></head><body>
<h1>Prismo · 25 个粗描几何方案</h1>
<p class="sub">全部用你参考里的语法原创(基本形+同一模数+简单色+App 砖+一个记忆点),不抄具体形。挑你有感觉的几个编号告诉我。</p>
{sec}</body></html>'''
open("preview.html","w").write(html)
print("wrote", len(I), "tiles + preview.html")
