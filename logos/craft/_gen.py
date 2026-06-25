#!/usr/bin/env python3
# 6 hand-crafted, production-grade Prismo marks. Bold app-icons, mono + one dollar-green accent.
# Built on the threads that actually resonated: refraction that bends UP (prism + bullish signal).
import math, os
OUT="tiles"; os.makedirs(OUT, exist_ok=True)
TILE="#1B1E22"; W="#F4F5F5"; G="#85BB65"

def pt(cx,cy,r,d):
    a=math.radians(d); return (round(cx+r*math.cos(a),1), round(cy+r*math.sin(a),1))
def circ(cx,cy,r,fill="none",stroke=None,sw=0,op=None):
    s=f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    if op is not None: s+=f' fill-opacity="{op}"'
    return s+'/>'
def line(x1,y1,x2,y2,stroke,sw):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round"/>'
def path(d,fill="none",stroke=None,sw=0):
    s=f'<path d="{d}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
    return s+'/>'
def tile(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="prismo">\n'
            f'<rect width="512" height="512" rx="120" fill="{TILE}"/>\n{body}\n</svg>\n')

marks={}

# 1 — Refracted Rise (HERO): flat signal enters a lens, leaves bending UP to a green dot
b  = circ(222,300,58,stroke=W,sw=22)
b += line(48,300,164,300,W,34)
b += line(259,256,452,150,W,34)
b += circ(452,150,24,fill=G)
marks["1-refracted-rise"]=(b,"折射上扬","信号穿过镜片被向上掰起→绿点(棱镜+看涨+信号)")

# 2 — Inverse Prism: 3 noisy lines in, one clean line out, through a lens
b  = circ(300,256,64,stroke=W,sw=22)
b += line(70,212,236,212,W,18)
b += line(50,256,236,256,W,18)
b += line(84,300,236,300,W,18)
b += line(364,256,452,256,W,30)
b += circ(470,256,22,fill=G)
marks["2-inverse-prism"]=(b,"反向棱镜","三条噪声进、一条信号出→绿点(噪声→清晰)")

# 3 — Rising Echo: a solid mark with two narrower green echoes rising (momentum)
b  = circ(196,212,50,fill=G,op=0.3)
b += circ(258,262,60,fill=G,op=0.55)
b += circ(330,320,70,fill=W)
marks["3-rising-echo"]=(b,"上行残影","白盘+两道渐窄绿残影向左上爬升(动量)")

# 4 — Split-shift: a disc sheared, halves offset, a green seam of light between
b  = path("M156 292 A80 80 0 0 0 316 292 Z",fill=W)
b += path("M196 252 A80 80 0 0 1 356 252 Z",fill=W)
b += line(202,272,312,272,G,16)
marks["4-split-shift"]=(b,"错移盘","盘被剪开错位,缝里一道绿光(折射位移)")

# 5 — Focus ring: a lens with a green signal core and one rising ray
b  = circ(256,256,88,stroke=W,sw=30)
b += circ(256,256,26,fill=G)
b += line(318,194,392,120,W,26)
marks["5-focus-ring"]=(b,"聚焦环","全球镜片+绿信号核+一道上扬射线")

# 6 — Lens-rise bars: ascending signal bars inside the lens, tallest green
b  = circ(256,256,92,stroke=W,sw=24)
b += line(206,320,206,262,W,26)
b += line(256,320,256,222,W,26)
b += line(306,320,306,182,G,26)
marks["6-lens-rise"]=(b,"镜中拾级","镜片里三柱上行信号,最高一柱为绿")

for k,(body,name,mem) in marks.items():
    open(os.path.join(OUT,f"{k}.svg"),"w").write(tile(body))

cards="".join(
  f'<div class="card"><div class="ci"><img src="{OUT}/{k}.svg"></div>'
  f'<div class="fv"><img src="{OUT}/{k}.svg" width="48"><img src="{OUT}/{k}.svg" width="28"><img src="{OUT}/{k}.svg" width="18"></div>'
  f'<div class="cl"><b>{k.split("-",1)[0]} · {name}</b><span>{mem}</span></div></div>'
  for k,(body,name,mem) in marks.items())
html=f'''<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Prismo · crafted</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;background:#0E0E0E;color:#ECEDED;padding:2.4rem 2rem 4rem}}
h1{{font-size:1.35rem;font-weight:600}}
.sub{{font-size:.86rem;opacity:.6;margin:.5rem 0 1.6rem;max-width:64ch;line-height:1.5}}
.grid{{display:grid;gap:1.4rem;grid-template-columns:repeat(auto-fill,minmax(240px,1fr))}}
.card{{border:1px solid rgba(140,140,140,.2);border-radius:16px;overflow:hidden;background:#101010}}
.ci{{display:flex;align-items:center;justify-content:center;padding:1.4rem;background:#0E0E0E}}
.ci img{{width:188px;height:188px}}
.fv{{display:flex;gap:1rem;align-items:center;justify-content:center;padding:.6rem;background:#0E0E0E;border-top:1px solid rgba(140,140,140,.12)}}
.fv img{{border-radius:5px}}
.cl{{padding:.7rem .9rem;border-top:1px solid rgba(140,140,140,.16);font-size:.84rem;display:flex;flex-direction:column;gap:.18rem}}
.cl b{{font-weight:600}} .cl span{{opacity:.55;font-size:.76rem;line-height:1.4}}
</style></head><body>
<h1>Prismo · 6 个手工精修矢量标记</h1>
<p class="sub">不是 GPT 缩略图——这是真矢量、可直接上线、可导 favicon。每张下方是 48/28/18px 小尺寸检查。核心想法:折射把信号向上掰(棱镜+看涨)。挑一个,或告诉我整轮里最接近的那一个,我据此精修收口。</p>
<div class="grid">{cards}</div>
</body></html>'''
open("preview.html","w").write(html)
print("wrote",len(marks),"marks + preview.html")
