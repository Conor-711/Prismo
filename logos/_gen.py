#!/usr/bin/env python3
# Brainstorm generator — 25 distinct Prismo logo concepts, each with a memory point.
# All flat, black-friendly, single teal accent, NO triangles.
import math, os

INK="#ECEDED"; TEAL="#57D7BA"; BG="#0E0E0E"
OUT="brainstorm"; os.makedirs(OUT, exist_ok=True)

def pt(cx,cy,r,deg):
    a=math.radians(deg); return (round(cx+r*math.cos(a),1), round(cy+r*math.sin(a),1))
def A(cx,cy,r,a0,a1,sweep=1,large=0):
    x0,y0=pt(cx,cy,r,a0); x1,y1=pt(cx,cy,r,a1)
    return f'M{x0} {y0} A{r} {r} 0 {large} {sweep} {x1} {y1}'
def circ(cx,cy,r,fill="none",stroke=None,sw=0,op=None,sop=None):
    s=f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    if op is not None: s+=f' fill-opacity="{op}"'
    if sop is not None: s+=f' stroke-opacity="{sop}"'
    return s+'/>'
def ell(cx,cy,rx,ry,fill="none",stroke=None,sw=0,op=None):
    s=f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    if op is not None: s+=f' stroke-opacity="{op}"'
    return s+'/>'
def line(x1,y1,x2,y2,stroke,sw,op=None,cap="round"):
    s=f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="{cap}"'
    if op is not None: s+=f' stroke-opacity="{op}"'
    return s+'/>'
def rect(x,y,w,h,rx,fill="none",stroke=None,sw=0,op=None):
    s=f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}"'
    if op is not None: s+=f' fill-opacity="{op}"'
    return s+'/>'
def path(d,stroke=None,sw=0,fill="none",cap="round",op=None):
    s=f'<path d="{d}" fill="{fill}"'
    if stroke: s+=f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="{cap}" stroke-linejoin="round"'
    if op is not None: s+=f' stroke-opacity="{op}"'
    return s+'/>'
def WORD(x,y,size=120,weight=600,ls=-1,anchor="start",text="prismo",fill=INK):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" '
            f"font-family=\"'Avenir Next','Futura','Century Gothic','Segoe UI',system-ui,sans-serif\" "
            f'font-size="{size}" font-weight="{weight}" letter-spacing="{ls}" fill="{fill}">{text}</text>')
def svg(vb,body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="prismo">\n{body}\n</svg>\n'

W="0 0 760 240"; S="0 0 300 300"
items=[]  # (num, slug, family, name, memory, vb, body)
def add(num,slug,fam,name,memory,vb,body): items.append((num,slug,fam,name,memory,vb,body))

# ---------- A · 字标 / 字母巧思 ----------
# 1 coin-o
b=WORD(470,150,120,anchor="end",text="prism")+circ(540,108,42,stroke=INK,sw=14)+circ(540,108,24,stroke=INK,sw=5,sop=0.55)+circ(540,108,9,fill=TEAL)
add(1,"coin-o","A","币·o","o 是一枚硬币(内圈+核)",W,b)
# 2 bubble-o
b=WORD(470,150,120,anchor="end",text="prism")+circ(540,108,42,stroke=INK,sw=14)+path("M512 138 Q500 160 492 150",stroke=INK,sw=14)+circ(540,108,9,fill=TEAL)
add(2,"bubble-o","A","气泡·o","o 是会说话的对话气泡",W,b)
# 3 sparkline underline
b=WORD(170,128,120,text="prismo")+path("M180 174 L250 174 L300 158 L342 186 L392 150 L442 176 L500 168 L592 168",stroke=TEAL,sw=7)+circ(592,168,8,fill=TEAL)
add(3,"sparkline","A","行情线","单词站在一条会跳动的行情线上",W,b)
# 4 candle-i (icon)
b=rect(138,140,24,118,9,fill=INK)+rect(132,72,36,44,6,fill=TEAL)+line(150,52,150,72,INK,6)+line(150,116,150,132,INK,6)
add(4,"candle-i","A","蜡烛·i","i 头上的点是一根 K 线蜡烛",S,b)
# 5 filled-p (icon)
b=line(112,70,112,250,INK,26)+circ(160,120,50,fill=TEAL)
add(5,"filled-p","A","实心 p","p 的肚子是一颗实心信号点",S,b)
# 12 dot-P
dots=[(108,72),(108,100),(108,128),(108,156),(108,184),(108,212),(140,72),(167,82),(179,106),(167,130),(140,140)]
b="".join(circ(x,y,9,fill=(TEAL if i==8 else INK)) for i,(x,y) in enumerate(dots))
add(12,"dot-P","A","点阵 P","散户的点连成一个 P",S,b)
# 21 coin-P
b=circ(150,150,90,stroke=INK,sw=12)+WORD(150,196,130,weight=700,anchor="middle",text="P",fill=TEAL)
add(21,"coin-P","A","P 币","一枚 Prismo 代币的币面",S,b)

# ---------- B · 信号 / 波形 / 脉冲 ----------
# 6 equalizer
bars=[(70,80),(105,130),(140,176),(175,112),(210,72)]
b="".join(rect(x,235-h,24,h,11,fill=(TEAL if i==2 else INK)) for i,(x,h) in enumerate(bars))
add(6,"equalizer","B","均衡器","情绪均衡器,最高那根是信号",S,b)
# 7 pulse ECG
b=line(46,150,250,150,INK,6,op=0.18)+path("M52 150 L104 150 L126 150 L146 104 L168 200 L192 150 L248 150",stroke=TEAL,sw=12)
add(7,"pulse","B","心跳","市场心跳:一条 ECG 信号线",S,b)
# 8 sonar
sx,sy=116,176
b=circ(sx,sy,14,fill=TEAL)+path(A(sx,sy,48,-80,18),stroke=INK,sw=9,op=0.7)+path(A(sx,sy,84,-80,18),stroke=INK,sw=9,op=0.45)+path(A(sx,sy,120,-80,18),stroke=INK,sw=9,op=0.25)
add(8,"sonar","B","声呐","在'听'整个市场",S,b)
# 9 waveform ring
cx=cy=150; N=32; b=""
for i in range(N):
    deg=i*(360/N); ln=16+20*abs(math.sin(math.radians(i*22.5)))
    x0,y0=pt(cx,cy,52,deg); x1,y1=pt(cx,cy,52+ln,deg)
    col=TEAL if i in (0,1,31) else INK; op=None if col==TEAL else 0.85
    b+=line(x0,y0,x1,y1,col,5,op)
add(9,"waveform-ring","B","声纹环","人群的声纹绕成一圈",S,b)
# 10 noise to signal
b=""
for x,h,op in [(60,28,.45),(78,52,.5),(96,36,.45),(114,64,.5),(132,44,.45)]:
    b+=rect(x,150-h/2,8,h,4,fill=INK,op=op)
b+=path("M150 150 Q180 150 200 150",stroke=INK,sw=4,op=.4)+rect(212,70,26,160,13,fill=TEAL)
add(10,"noise-signal","B","噪声→信号","左边噪声收敛成右边一根清晰信号",S,b)
# 19 up-tick
b=line(60,196,236,196,INK,5,op=0.18)+path("M62 188 Q152 180 236 76",stroke=TEAL,sw=16)+circ(236,76,12,fill=TEAL)
add(19,"uptick","B","上扬笔","上扬的那一笔(圆润,非箭头)",S,b)
# 23 spectrum slit
b=rect(86,80,16,140,8,fill=INK)
for y,col,op in [(104,TEAL,None),(134,INK,.7),(166,INK,.55),(198,INK,.4)]:
    b+=path(f"M104 150 Q172 {round((150+y)/2)} 238 {y}",stroke=col,sw=8,op=op)
add(23,"spectrum","B","分光","不用三角的'分光':一束变多束",S,b)

# ---------- C · 对话 / 讨论 / 人群 ----------
# 11 converge
b=""
for y in (78,114,150,186,222):
    b+=path(f"M58 {y} Q150 {y} 230 150",stroke=INK,sw=5,op=0.65)
b+=circ(234,150,16,fill=TEAL)
add(11,"converge","C","汇聚","万千讨论汇聚到一个点",S,b)
# 13 hub
cx=cy=150; b=""
for i in range(6):
    x,y=pt(cx,cy,92,i*60-90); b+=line(cx,cy,x,y,INK,3,op=0.4)
for i in range(6):
    x,y=pt(cx,cy,92,i*60-90); b+=circ(x,y,11,fill=INK)
b+=circ(cx,cy,19,fill=TEAL)
add(13,"hub","C","中枢","讨论的中枢:众星拱一核",S,b)
# 14 confluence
b=""
for y in (96,150,204):
    b+=path(f"M58 {y} Q150 {y} 200 150",stroke=INK,sw=9)
b+=path("M200 150 L246 150",stroke=TEAL,sw=14)
add(14,"confluence","C","合流","多股观点合流成一束",S,b)
# 15 chat-coin
b=rect(58,66,184,116,34,fill="none",stroke=INK,sw=12)+circ(96,196,11,fill="none",stroke=INK,sw=12)
b+=circ(150,124,34,stroke=TEAL,sw=10)+circ(150,124,7,fill=TEAL)
add(15,"chat-coin","C","钱在说话","对话气泡里装着一枚币",S,b)
# 16 dialogue (bull/bear two bubbles)
b=rect(46,78,96,84,26,fill="none",stroke=TEAL,sw=12)+circ(70,170,9,fill="none",stroke=TEAL,sw=12)
b+=rect(158,108,96,84,26,fill="none",stroke=INK,sw=12)+circ(232,200,9,fill="none",stroke=INK,sw=12)
add(16,"dialogue","C","多空对话","两只气泡对望:多空两方",S,b)
# 17 bubble cluster
b=circ(118,138,46,fill=BG,stroke=INK,sw=12)+circ(184,126,46,fill=BG,stroke=INK,sw=12)+circ(150,186,48,fill=TEAL)
add(17,"bubble-cluster","C","点亮一句","众声里被点亮的那一句",S,b)

# ---------- D · 金融形态 ----------
# 18 candle-P
b=path(A(150,112,44,-90,90),stroke=INK,sw=22)+line(127,70,127,238,INK,6)+rect(108,118,38,82,7,fill=TEAL)
add(18,"candle-P","D","蜡烛 P","P 的竖笔是一根蜡烛",S,b)
# 20 cup
b=path("M64 116 Q150 238 236 116",stroke=INK,sw=14)+circ(150,92,16,fill=TEAL)
add(20,"cup","D","杯形","经典杯形(cup)托起信号点",S,b)
# 22 infinity
b=path("M150 150 C120 112 74 112 74 150 C74 188 120 188 150 150",stroke=TEAL,sw=15)+path("M150 150 C180 112 226 112 226 150 C226 188 180 188 150 150",stroke=INK,sw=15)
add(22,"infinity","D","无限流","永不停歇的讨论流(∞)",S,b)
# 24 compass
nx,ny=pt(150,150,66,-45); sx2,sy2=pt(150,150,66,135)
b=circ(150,150,90,stroke=INK,sw=10)+line(150,150,nx,ny,TEAL,16)+line(150,150,sx2,sy2,INK,16)+circ(150,150,10,fill=INK)
add(24,"compass","D","罗盘","市场罗盘:一根圆头指针",S,b)
# 25 coin stack
b=line(70,124,70,188,INK,10,op=0.55)+line(230,124,230,188,INK,10,op=0.55)
b+=ell(150,188,80,20,stroke=INK,sw=10)+ell(150,156,80,20,stroke=INK,sw=10)+ell(150,124,80,20,stroke=TEAL,sw=10)
add(25,"coin-stack","D","币摞","一摞硬币:沉淀的资产",S,b)

# ---- write svgs ----
for num,slug,fam,name,memory,vb,body in items:
    open(os.path.join(OUT,f"{num:02d}-{slug}.svg"),"w").write(svg(vb,body))

# ---- gallery ----
fams=[("A","字标 / 字母巧思"),("B","信号 / 波形 / 脉冲"),("C","对话 / 讨论 / 人群"),("D","金融形态")]
sections=""
for fk,ftitle in fams:
    cards=""
    for num,slug,fam,name,memory,vb,body in items:
        if fam!=fk: continue
        cards+=(f'<div class="card"><div class="ci"><img src="{OUT}/{num:02d}-{slug}.svg" alt="{num}"></div>'
                f'<div class="cl"><b>{num:02d} · {name}</b><span>{memory}</span></div></div>\n')
    sections+=f'<h2>{fk} · {ftitle}</h2>\n<div class="grid">\n{cards}</div>\n'

html=f'''<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Prismo · 25 概念</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;background:{BG};color:{INK};padding:2.4rem 2rem 4rem}}
.head{{display:flex;justify-content:space-between;align-items:center}}
h1{{font-size:1.35rem;font-weight:600}}
h2{{font-size:.95rem;font-weight:600;opacity:.9;margin:2.4rem 0 1rem;border-left:3px solid {TEAL};padding-left:.6rem}}
.sub{{font-size:.85rem;opacity:.55;margin-top:.4rem;max-width:66ch;line-height:1.55}}
.toggle{{padding:.45rem .9rem;border:1px solid currentColor;border-radius:6px;background:transparent;color:inherit;cursor:pointer;font-size:.8rem}}
.grid{{display:grid;gap:1.1rem;grid-template-columns:repeat(auto-fill,minmax(220px,1fr))}}
.card{{border:1px solid rgba(140,140,140,.22);border-radius:13px;overflow:hidden;background:#101010}}
.ci{{display:flex;align-items:center;justify-content:center;padding:1.7rem;min-height:150px;background:{BG}}}
.ci img{{max-width:100%;max-height:120px}}
.cl{{padding:.6rem .8rem;border-top:1px solid rgba(140,140,140,.16);font-size:.8rem;display:flex;flex-direction:column;gap:.15rem}}
.cl b{{font-weight:600}} .cl span{{opacity:.5;font-size:.75rem}}
body.light{{background:#f5f5f5;color:#222}} body.light .ci{{background:#fff}} body.light .card{{background:#fafafa}}
</style></head><body>
<div class="head"><h1>Prismo · 25 个全新概念</h1>
<button class="toggle" onclick="document.body.classList.toggle('light');this.textContent=document.body.classList.contains('light')?'☾ 深色':'☀︎ 浅色'">☀︎ 浅色</button></div>
<p class="sub">完全发散:4 个方向、25 个概念,每个有一个记忆点,全部无三角、黑底、青绿单点(先比形,选定再上多主题色 + 排布 + favicon)。挑你有感觉的几个编号告诉我。</p>
{sections}
</body></html>'''
open("preview.html","w").write(html)
print(f"wrote {len(items)} svgs + preview.html")
