const people = window.DISCOVERY_PEOPLE;
const byId = id => people.find(p => p.id === id);
const icon = name => `<i data-lucide="${name}"></i>`;
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const text = {'Semiconductors':'半导体','Software':'软件与互联网','AI infrastructure':'AI 基础设施','Crypto-linked equities':'加密相关股票','Cross-sector equities':'跨行业','Consumer':'消费','Fintech':'金融科技','Fundamental':'基本面','Technical':'技术分析','Event Driven':'事件驱动','Flow Momentum':'资金与动量','Unknown':'风格待归类','Medium term':'中线','Short term':'短线','Long term':'长线'};
const cn = s => text[s] || s;
const date = s => s ? `${s.slice(5,7)}/${s.slice(8,10)}` : '';
const rank = p => `Top ${Math.max(1, Math.ceil(p.percentile * 100))}%`;
const peopleWithViews = people.filter(p => p.opinions.length).sort((a,b) => b.opinions[0].at.localeCompare(a.opinions[0].at));
const scenarios = [
  {id:'A',name:'头像池 + 焦点人物',short:'头像池',tag:'最接近你的初始想法',why:'先感受到人才密度，再点选一个人了解。头像池保留探索欲，焦点简介提供追踪的理由。',tradeoff:'浏览自由、发现效率高；陌生头像本身的信息量有限，需要精选排序和清楚的能力简介。'},
  {id:'B',name:'逐人发现',short:'逐人发现',tag:'把每个人的价值讲完整',why:'每次只认识一位投资者，能力、历史样本与最新观点一起出现。通过左右切换和追踪建立自己的名单。',tradeoff:'人物记忆更深，适合初次进入；浏览速度较慢，不宜让熟练用户每天重复挑人。'},
  {id:'C',name:'按赛道选人',short:'赛道选人',tag:'先找到同路人',why:'先选关注的研究领域，再浏览该领域的投资者。三位不同风格的人并列，便于快速判断是否适合。',tradeoff:'相关性最直观，效率高；整体更像专业目录，人物探索的惊喜感相对弱。'},
  {id:'D',name:'从观点发现人',short:'观点识人',tag:'用一句观点建立兴趣',why:'先展示一条真实的近期判断，再揭示作者与相关背景。用户因为观点而认识人，不必先理解陌生名字。',tradeoff:'最直接连接人与正在讨论的事；必须保留观点日期，不能把有趣等同于准确或实时。'}
];
let followed;
try { followed = new Set(JSON.parse(localStorage.getItem('bsmart-discovery-review-followed') || '[]')); } catch { followed = new Set(); }
let mode = 'compare', activeScheme = 'A', toastTimer;
const states = Object.fromEntries(scenarios.map(s => [s.id, {selected:peopleWithViews[0]?.id || people[0].id, page:0, sector:'Semiconductors', feed:'all', deck:0}]));
const avatar = (p, size='') => `<span class="avatar ${size}" aria-hidden="true">${p.avatar ? `<img src="${p.avatar}" alt="">` : esc([...p.name][0])}</span>`;
const follow = (p, primary=false, compact=false) => `<button class="follow ${primary?'primary':''}" data-action="follow" data-person="${p.id}" aria-pressed="${followed.has(p.id)}" aria-label="${followed.has(p.id)?'取消追踪':'追踪'} ${esc(p.name)}">${icon(followed.has(p.id)?'check':'plus')}${compact?'':followed.has(p.id)?'已追踪':'追踪'}</button>`;
const tickers = p => `<div class="tickers">${p.tickers.slice(0,3).map(t => `<span>${esc(t)}</span>`).join('')}</div>`;
const personHeading = (p, size='') => `${avatar(p,size)}<div class="name"><h4>${esc(p.name)}</h4><div class="meta">${esc(p.platform)} <span class="rank">${rank(p)}</span> · ${esc(cn(p.horizon))}</div></div>`;
function poolView(state) {
  const slice = people.slice(state.page * 18, state.page * 18 + 18), p = byId(state.selected);
  return `<div class="section-top"><div><span class="small-kicker">SMART ACCOUNT</span><h3>认识值得追踪的人</h3></div><button class="icon-button" data-action="pool-next" aria-label="换一组投资者" title="换一组投资者">${icon('shuffle')}</button></div><div class="pool">${slice.map(p => `<button data-action="select" data-person="${p.id}" class="${state.selected===p.id?'selected':''}" aria-pressed="${state.selected===p.id}" aria-label="了解 ${esc(p.name)}" title="${esc(p.name)} · ${rank(p)}">${avatar(p)}</button>`).join('')}</div>
  <div class="profile-focus"><div class="person-head">${personHeading(p)}${follow(p)}</div><p class="profile-line">${esc(cn(p.sector))} · ${esc(cn(p.style))}<br><span class="meta">${p.samples} 个已结算判断 · 关注 ${esc(p.tickers.slice(0,2).join('、'))}</span></p><div class="profile-bottom">${tickers(p)}<button class="text-link" data-action="detail" data-person="${p.id}">了解这位投资者 ${icon('arrow-up-right')}</button></div></div>`;
}
function deckView(state) {
  const p = people[state.deck % people.length], u = p.opinions[0];
  return `<div class="section-top"><div><span class="small-kicker">MEET YOUR NEXT FOLLOW</span><h3>你的下一位研究搭档</h3></div></div><div class="discovery-pagination"><span>${String(state.deck+1).padStart(2,'0')} / ${people.length} 位投资者</span><div class="arrows"><button class="icon-button" data-action="previous" aria-label="上一位投资者" title="上一位">${icon('arrow-left')}</button><button class="icon-button" data-action="next" aria-label="下一位投资者" title="下一位">${icon('arrow-right')}</button></div></div>
  <div class="dossier" data-swipe="B"><div class="portrait-band">${personHeading(p,'big')}</div><div class="profile-facts"><div class="metric"><b>${p.score}</b><span>Score</span></div><div class="metric"><b>${p.samples}</b><span>已结算判断</span></div><div class="metric"><b>${esc(cn(p.horizon))}</b><span>时间级别</span></div></div><h5>${esc(cn(p.sector))} · ${esc(cn(p.style))}</h5><p class="profile-line">${u ? esc(u.text) : '关注 '+esc(p.tickers.slice(0,4).join('、'))+'，查看其研究背景。'}</p><div class="profile-bottom">${tickers(p)}<span class="meta">${u?date(u.at):''}</span></div><div class="dossier-actions"><button class="follow" data-action="detail" data-person="${p.id}">了解更多 ${icon('arrow-up-right')}</button>${follow(p,true)}</div></div>`;
}
const sectorOptions = ['Semiconductors','Software','AI infrastructure','all'];
function sectorView(state) {
  const list = people.filter(p => state.sector==='all' || p.sector===state.sector);
  return `<div class="section-top"><div><span class="small-kicker">FIND YOUR CIRCLE</span><h3>你关心的领域，谁在研究？</h3></div></div><nav class="sector-tabs" aria-label="研究赛道">${sectorOptions.map(s => `<button data-action="sector" data-sector="${s}" aria-pressed="${state.sector===s}" class="${state.sector===s?'active':''}">${s==='all'?'全部':esc(cn(s))}</button>`).join('')}</nav><div class="sector-header"><div><b>${state.sector==='all'?'跨领域发现':esc(cn(state.sector))}</b><small>${list.length} 位投资者 · 本次快照</small></div>${icon(state.sector==='Semiconductors'?'cpu':state.sector==='Software'?'layers':'network')}</div><div class="expert-list">${list.slice(0,3).map(p => expertRow(p)).join('')}<button class="text-link" data-action="directory" data-sector="${state.sector}">查看该领域全部投资者 ${icon('arrow-right')}</button></div>`;
}
function expertRow(p) {
  return `<div class="expert-row"><button class="expert-main" data-action="detail" data-person="${p.id}" aria-label="了解 ${esc(p.name)}">${avatar(p)}<div class="name"><h4>${esc(p.name)}</h4><div class="meta"><span class="rank">${rank(p)}</span> · ${esc(cn(p.style))}</div></div></button>${follow(p,false,true)}</div>`;
}
function viewFirst(state) {
  const p = peopleWithViews.find(p=>p.id===state.selected) || peopleWithViews[0], u = p.opinions[0];
  return `<div class="section-top"><div><span class="small-kicker">A VIEW WORTH KNOWING</span><h3>因为一个观点，认识一个人</h3></div></div><div class="new-view"><div class="lead-view"><div class="small-kicker"><b>${esc(u.ticker)} · ${u.direction==='bullish'?'看多':u.direction==='bearish'?'看空':'观点更新'}</b><span>${date(u.at)} · ${p.platform}</span></div><p class="quote">${esc(u.text)}</p><div class="person-head">${personHeading(p)}${follow(p)}</div><p class="profile-line">${esc(cn(p.sector))} · ${esc(cn(p.style))}</p><button class="text-link" data-action="detail" data-person="${p.id}">为什么值得认识他 ${icon('arrow-right')}</button></div><div class="related-people"><span>还有这些声音</span>${peopleWithViews.slice(0,5).map(q=>`<button data-action="select" data-person="${q.id}" class="${q.id===p.id?'selected':''}" aria-label="查看 ${esc(q.name)} 的观点" title="${esc(q.name)}">${avatar(q)}</button>`).join('')}</div></div>`;
}
function feedView(state) {
  let rows = people.flatMap(p => p.opinions.map(u=>({p,u}))).sort((a,b)=>b.u.at.localeCompare(a.u.at));
  if (state.feed==='tracked') rows = rows.filter(r=>followed.has(r.p.id));
  if (state.feed==='holdings') rows = rows.filter(r=>['NVDA','MU','MSTR'].includes(r.u.ticker));
  return `<section class="stream"><div class="stream-head"><h3>他们如何看市场</h3><span>项目观点快照</span></div><nav class="feed-tabs" aria-label="观点范围">${[['all','市场观点'],['tracked','我的追踪'],['holdings','持仓相关']].map(([id,label])=>`<button data-action="feed" data-feed="${id}" aria-pressed="${state.feed===id}" class="${state.feed===id?'active':''}">${label}${id==='tracked'&&followed.size?' '+followed.size:''}</button>`).join('')}</nav>${rows.length ? rows.slice(0,8).map(({p,u})=>`<article class="feed-item"><div class="ticker-title"><b>${esc(u.ticker)}</b><span class="direction ${u.direction}">${u.direction==='bullish'?'看多':u.direction==='bearish'?'看空':'观点更新'}</span></div><p class="quote">${esc(u.text)}</p><div class="source">${avatar(p)}<button data-action="detail" data-person="${p.id}">${esc(p.name)} · ${rank(p)}</button><time>${date(u.at)}</time></div></article>`).join('') : `<div class="empty-state">${icon('bookmark')}尚无可展示的追踪观点<br><span class="meta">${followed.size?'本次快照中，已追踪投资者暂无近期观点。':'追踪名单为空。'}</span></div>`}</section>`;
}
function phone(s) {
  const state=states[s.id], upper = {A:poolView,B:deckView,C:sectorView,D:viewFirst}[s.id](state);
  return `<article class="concept" data-scheme="${s.id}"><header class="concept-label"><span class="concept-letter">${s.id}</span><h2>${s.name}</h2><button data-action="focus" data-scheme="${s.id}" title="单屏体验">${icon('maximize-2')}体验</button></header><div class="phone"><div class="status"><span>9:41</span><div class="status-icons">${icon('signal')}${icon('wifi')}${icon('battery-full')}</div></div><div class="app-scroll"><header class="app-head"><span class="brand">b<span>Smart</span></span><button class="head-icon" data-action="following" aria-label="查看我的追踪" title="我的追踪">${icon('bookmark')}</button></header>${upper}${feedView(state)}</div><div class="bottom-tab" aria-hidden="true"><div class="active">${icon('house')}今日</div><div>${icon('wallet')}持仓</div><div>${icon('users-round')}Smart</div><div>${icon('message-circle')}Mr Collie</div></div><div class="home-indicator"></div></div><div class="concept-note"><strong>${s.tag}</strong>${s.why}<br>${s.tradeoff}</div></article>`;
}
function render() {
  const scrolls = Object.fromEntries([...document.querySelectorAll('.concept')].map(c=>[c.dataset.scheme,c.querySelector('.app-scroll').scrollTop]));
  document.querySelector('#stage').className=`stage ${mode==='single'?'single':''}`;
  document.querySelector('#stage').innerHTML=scenarios.filter(s=>mode==='compare'||s.id===activeScheme).map(phone).join('');
  document.querySelector('#scheme-tabs').innerHTML=scenarios.map(s=>`<button data-action="scheme" data-scheme="${s.id}" aria-current="${activeScheme===s.id}">${s.id} · ${s.short}</button>`).join('');
  document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.mode===mode));
  const note=document.querySelector('#single-note'), s=scenarios.find(s=>s.id===activeScheme);
  note.hidden=mode!=='single';note.innerHTML=`<h3>${s.id} / ${s.tag}</h3>${s.why}<br>${s.tradeoff}`;
  document.querySelectorAll('.concept').forEach(c=>{c.querySelector('.app-scroll').scrollTop=scrolls[c.dataset.scheme]||0;});
  lucide.createIcons();
}
function openDialog(title, body) {
  document.querySelector('#detail-body').innerHTML=`<header class="dialog-head"><h3 id="detail-title">${title}</h3><button class="icon-button" data-action="close" aria-label="关闭">${icon('x')}</button></header><div class="dialog-content">${body}</div>`;
  lucide.createIcons();const dialog=document.querySelector('#detail');if(!dialog.open)dialog.showModal();
}
function showPerson(id) {
  const p=byId(id);
  openDialog('投资者档案', `<div class="person-head">${personHeading(p,'large')}${follow(p)}</div><p class="profile-line">${esc(cn(p.sector))} · ${esc(cn(p.style))}</p>${tickers(p)}<div class="profile-facts"><div class="metric"><b>${p.score}</b><span>Score</span></div><div class="metric"><b>${p.samples}</b><span>已结算判断</span></div><div class="metric"><b>${rank(p)}</b><span>${p.platform} 平台排名</span></div></div><h4>近期观点</h4>${p.opinions.length?p.opinions.map(u=>`<div class="evidence"><div class="ticker-title"><b>${esc(u.ticker)}</b><span>${date(u.at)}</span></div><p class="quote">${esc(u.text)}</p>${/^https?:\/\//.test(u.url||'')?`<a class="text-link" href="${esc(u.url)}" target="_blank" rel="noopener noreferrer">原始证据 ${icon('external-link')}</a>`:''}</div>`).join(''):'<p class="meta">本次预览快照未收录该投资者的近期观点。</p>'}<p class="snapshot-note">本地历史快照。Score 衡量已结算公开判断，不等于作者真实账户收益，也不保证未来表现。</p>`);
}
function showDirectory(sector='all', tracked=false) {
  const list=people.filter(p=>(sector==='all'||p.sector===sector)&&(!tracked||followed.has(p.id)));
  openDialog(tracked?'我的追踪':sector==='all'?'发现投资者':cn(sector), `<input id="people-search" placeholder="搜索姓名、标的或领域" aria-label="搜索投资者"><div class="expert-list" id="directory-results">${list.length?list.map(expertRow).join(''):'<p class="empty-state">还没有追踪投资者。</p>'}</div>`);
  document.querySelector('#people-search').addEventListener('input',e=>{const q=e.target.value.trim().toLowerCase();document.querySelector('#directory-results').innerHTML=list.filter(p=>[p.name,...p.tickers,cn(p.sector)].join(' ').toLowerCase().includes(q)).map(expertRow).join('')||'<p class="empty-state">没有匹配的投资者。</p>';lucide.createIcons();});
}
function notify(message) {const t=document.querySelector('#toast');t.textContent=message;t.style.display='block';clearTimeout(toastTimer);toastTimer=setTimeout(()=>t.style.display='none',2200);}
document.addEventListener('click',e=>{
  const b=e.target.closest('button'); if(!b)return;
  if(b.dataset.mode){mode=b.dataset.mode;render();return;}
  const action=b.dataset.action, id=b.dataset.person, scheme=b.closest('.concept')?.dataset.scheme || activeScheme, state=states[scheme];
  if(action==='select'){state.selected=id;render();}
  if(action==='follow'){
    followed.has(id)?followed.delete(id):followed.add(id);
    try{localStorage.setItem('bsmart-discovery-review-followed',JSON.stringify([...followed]));}catch{}
    render();document.querySelectorAll(`#detail [data-action="follow"][data-person="${id}"]`).forEach(el=>{el.outerHTML=follow(byId(id),false,el.closest('.expert-row')!==null);});lucide.createIcons();notify(`${followed.has(id)?'已追踪':'已取消追踪'} ${byId(id).name}`);
  }
  if(action==='pool-next'){state.page=(state.page+1)%Math.ceil(people.length/18);state.selected=people[state.page*18].id;render();}
  if(action==='next'||action==='previous'){state.deck=(state.deck+(action==='next'?1:-1)+people.length)%people.length;render();}
  if(action==='sector'){state.sector=b.dataset.sector;render();}
  if(action==='feed'){state.feed=b.dataset.feed;render();}
  if(action==='detail')showPerson(id);
  if(action==='directory')showDirectory(b.dataset.sector);
  if(action==='following')showDirectory('all',true);
  if(action==='close')document.querySelector('#detail').close();
  if(action==='scheme'||action==='focus'){activeScheme=b.dataset.scheme;mode='single';render();}
});
let touchStart=null;
document.addEventListener('touchstart',e=>{if(e.target.closest('[data-swipe]')&&!e.target.closest('button'))touchStart={x:e.touches[0].clientX,y:e.touches[0].clientY};},{passive:true});
document.addEventListener('touchend',e=>{if(!touchStart)return;const dx=e.changedTouches[0].clientX-touchStart.x,dy=e.changedTouches[0].clientY-touchStart.y;touchStart=null;if(Math.abs(dx)>55&&Math.abs(dx)>Math.abs(dy)*1.5){states.B.deck=(states.B.deck+(dx<0?1:-1)+people.length)%people.length;render();}},{passive:true});
document.querySelector('#detail').addEventListener('click',e=>{if(e.target===e.currentTarget){const r=e.currentTarget.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)e.currentTarget.close();}});
render();
