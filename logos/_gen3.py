#!/usr/bin/env python3
# 3 ORIGINAL directions for Prismo, built from the extracted grammar
# (module primitives + simple color + app-tile + gestalt memory point).
import math, os
OUT="final"; os.makedirs(OUT, exist_ok=True)

TILE="#1B1E22"; WHITE="#F4F5F5"; TEAL="#57D7BA"; CORAL="#FF3D51"

def pt(cx,cy,r,deg):
    a=math.radians(deg); return (round(cx+r*math.cos(a),1), round(cy+r*math.sin(a),1))
def circ(cx,cy,r,fill="none",stroke=None,sw=0,sop=None):
    s=f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    if sop is not None: s+=f' stroke-opacity="{sop}"'
    return s+'/>'
def rect(x,y,w,h,rx,fill):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"/>'
def path(d,stroke=None,sw=0,fill="none"):
    s=f'<path d="{d}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
    return s+'/>'
def A(cx,cy,r,a0,a1,sweep=1,large=0):
    x0,y0=pt(cx,cy,r,a0); x1,y1=pt(cx,cy,r,a1)
    return f'M{x0} {y0} A{r} {r} 0 {large} {sweep} {x1} {y1}'
def WORD(x,y,size=150,anchor="start"):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" '
            f"font-family=\"'Avenir Next','Futura','Century Gothic','Segoe UI',system-ui,sans-serif\" "
            f'font-size="{size}" font-weight="600" letter-spacing="-1" fill="{WHITE}">prismo</text>')

# ---- marks: canonical, centered ~ (256,256) ----
def mark_a(accent=TEAL):  # Aperture-P : stem pill + ring bowl + pupil = a P that is a lens
    return (rect(186,150,44,216,22,WHITE)
            + circ(258,214,64,stroke=WHITE,sw=40)
            + circ(258,214,18,fill=accent))
def mark_b(accent=TEAL):  # Chorus : a ring of 8 equal voices + one solid core (the signal)
    body=circ(256,256,96,stroke=WHITE,sw=6,sop=0.32)
    for i in range(8):
        x,y=pt(256,256,96,i*45-90); body+=circ(x,y,15,fill=WHITE)
    body+=circ(256,256,34,fill=accent)
    return body
def mark_c(accent=TEAL):  # Speech-coin : a bubble (ring+tail) whose center is a coin slot
    return (circ(256,238,92,stroke=WHITE,sw=38)
            + path("M214 312 Q188 348 234 350",stroke=WHITE,sw=30)
            + rect(222,230,68,16,8,accent))

def tile(markbody,bg=TILE):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="prismo">\n<rect x="0" y="0" width="512" height="512" rx="120" fill="{bg}"/>\n{markbody}\n</svg>\n'

def lockup(markbody):
    s=0.52; tx=round(176-256*s,1); ty=round(160-256*s,1)
    g=f'<g transform="translate({tx},{ty}) scale({s})">{markbody}</g>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1180 320" role="img" aria-label="prismo">\n{g}\n{WORD(360,212)}\n</svg>\n'

out={
 "a-tile.svg":  tile(mark_a()),
 "a-lockup.svg":lockup(mark_a()),
 "a-coral.svg": tile(mark_a(CORAL)),
 "b-tile.svg":  tile(mark_b()),
 "b-lockup.svg":lockup(mark_b()),
 "c-tile.svg":  tile(mark_c()),
 "c-lockup.svg":lockup(mark_c()),
}
for k,v in out.items(): open(os.path.join(OUT,k),"w").write(v)

dirs=[
 ("a","方向 A — 光圈 P（Aperture-P）",
   "构造：一根胶囊竖笔 + 一个等模数圆环 + 一颗瞳点（3 个基本形，同一描边/同一半径）。",
   "含义：P＝Prismo；圆环＝把全世界的讨论收成一只镜头；瞳点＝聚出的那束信号。",
   "记忆点：一个 P，同时是一只'看市场'的眼睛/镜头。"),
 ("b","方向 B — 合声环（Chorus）",
   "构造：8 个等大圆点匀布成环（重复模数，致敬 Figma 那种'同一积木拼出系统'）+ 一个实心核。",
   "含义：环上的点＝全球各地的声音；中心实心＝集成后的共识/信号。",
   "记忆点：一圈'声音'围着一个被点亮的核——many→one。"),
 ("c","方向 C — 话币（Speech-coin）",
   "构造：一个圆环 + 一条圆尾（对话气泡）+ 中心一道投币口（硬币）——一个圆形里读出两个意思。",
   "含义：把'讨论'与'钱'熔进同一个形：金钱在此对话。",
   "记忆点：一个气泡，中心却是投币口——讨论=资本的入口。"),
]
blocks=""
for k,title,build,mean,mem in dirs:
    coral = f'<img class="mini" src="{OUT}/a-coral.svg">' if k=="a" else ""
    blocks+=f'''<section>
<h2>{title}</h2>
<div class="row">
  <div class="tile"><img src="{OUT}/{k}-tile.svg">{coral}</div>
  <div class="lock"><img src="{OUT}/{k}-lockup.svg"></div>
</div>
<ul><li>{build}</li><li>{mean}</li><li><b>{mem}</b></li></ul>
</section>'''

html=f'''<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Prismo · 3 directions</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;background:#0E0E0E;color:#ECEDED;padding:2.4rem 2.2rem 4rem;line-height:1.5}}
h1{{font-size:1.4rem;font-weight:600}}
.sub{{font-size:.86rem;opacity:.6;margin:.5rem 0 1.4rem;max-width:70ch}}
section{{border-top:1px solid rgba(140,140,140,.18);padding:1.8rem 0}}
h2{{font-size:1.05rem;font-weight:600;border-left:3px solid {TEAL};padding-left:.6rem;margin-bottom:1rem}}
.row{{display:flex;gap:1.6rem;align-items:center;flex-wrap:wrap}}
.tile img{{width:172px;height:172px;border-radius:20px;display:block}}
.tile{{display:flex;gap:.8rem;align-items:center}}
.tile .mini{{width:96px;height:96px}}
.lock img{{height:120px;max-width:560px}}
ul{{margin:1rem 0 0 1.1rem;font-size:.85rem}} li{{margin:.25rem 0;opacity:.85}} li b{{opacity:1;color:{TEAL}}}
</style></head><body>
<h1>Prismo · 从参考的"语法"出发的 3 个原创方向</h1>
<p class="sub">不照抄任何一张参考；只取它们共同的设计语法：少量基本形 + 同一模数 + 简单颜色 + App 砖 + 一个"会心一击"的记忆点。下面每个都是为本项目（集成全球金融讨论→信号）原创。先看形与概念，选定一个再做色板/排布/导出。</p>
{blocks}
</body></html>'''
open("preview.html","w").write(html)
print("wrote", len(out), "svgs + preview.html")
