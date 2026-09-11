const people = window.DISCOVERY_PEOPLE;
const evidence = window.DISCOVERY_EVIDENCE;
const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = name => `<i data-lucide="${name}"></i>`;
const byId = id => people.find(p=>p.id===id);
const sectors = ['all','Semiconductors','Software','AI infrastructure','Crypto-linked equities'];
const labels = {all:'全部','Semiconductors':'半导体','Software':'软件','AI infrastructure':'AI 基础设施','Crypto-linked equities':'加密相关','Cross-sector equities':'跨行业','Consumer':'消费','Fintech':'金融科技','Fundamental':'基本面','Technical':'技术分析','Event Driven':'事件驱动','Flow Momentum':'资金与动量','Unknown':'风格待归类','Medium term':'中线','Short term':'短线','Long term':'长线'};
const cn = value => labels[value] || value;
const date = value => value ? value.slice(5,10).replace('-','/') : '';
const rank = p => `Top ${Math.max(1,Math.ceil(p.percentile*100))}%`;
const direction = value => ({bullish:'看多',bearish:'看空',neutral:'中性',mixed:'多空混合'}[value] || '观点更新');
const storageKey = 'bsmart-unified-discovery-followed-v1';
let followed;
try { followed=new Set(JSON.parse(localStorage.getItem(storageKey)||'[]').filter(id=>byId(id))); } catch { followed=new Set(); }
const initialPerson = people.find(p=>p.name==='Wey How') || people[0];
const state={mode:'people',sector:'all',selected:initialPerson.id,page:0,feed:'all'};
let profile=null,sheet=null,toastTimer,lastFocus=null;
const candidates = () => people.filter(p=>state.sector==='all'||p.sector===state.sector);
const viewCandidates = () => candidates().filter(p=>p.opinions.length).sort((a,b)=>b.opinions[0].at.localeCompare(a.opinions[0].at));
const selectedPerson = () => candidates().find(p=>p.id===state.selected)||candidates()[0];
const selectedViewPerson = () => viewCandidates().find(p=>p.id===state.selected)||viewCandidates()[0];
const avatar = (p,size='')=>`<span class="avatar ${size}" aria-hidden="true">${p.avatar?`<img src="${p.avatar}" alt="">`:esc([...p.name][0])}</span>`;
const followButton = (p,primary=false,compact=false)=>`<button class="follow ${primary?'primary':''}" data-action="follow" data-person="${p.id}" aria-pressed="${followed.has(p.id)}" aria-label="${followed.has(p.id)?'取消追踪':'追踪'} ${esc(p.name)}">${icon(followed.has(p.id)?'check':'plus')}${compact?'':followed.has(p.id)?'已追踪':'追踪'}</button>`;
const name = p=>`<div class="person-name"><h3>${esc(p.name)}</h3><div class="meta">${esc(p.platform)} <span class="rank">${rank(p)}</span> · ${esc(cn(p.horizon))}</div></div>`;
const tickerList = p=>`<div class="ticker-list">${p.tickers.slice(0,3).map(t=>`<span>${esc(t)}</span>`).join('')}</div>`;
const empty = (title,description='')=>`<div class="empty">${icon('scan-search')}<span>${title}</span>${description?`<p>${description}</p>`:''}</div>`;
function focusPerson(p) {
  return `<div class="focus-person"><div class="person-row">${avatar(p)}${name(p)}${followButton(p)}</div><p class="focus-body">${esc(cn(p.sector))} · ${esc(cn(p.style))} <span class="meta">/ ${p.samples} 个已结算判断</span></p><div class="focus-footer">${tickerList(p)}<button class="text-button" data-action="profile" data-person="${p.id}">深入了解 ${icon('arrow-up-right')}</button></div></div>`;
}
function peopleMode() {
  const list=candidates(), pageCount=Math.max(1,Math.ceil(list.length/18));
  state.page=Math.min(state.page,pageCount-1);
  const visible=list.slice(state.page*18,state.page*18+18),p=selectedPerson();
  if(!p)return empty('这个领域暂未收录投资者');
  return `<div class="pool" style="grid-template-rows:repeat(${Math.ceil(visible.length/6)},43px);min-height:0">${visible.map(p=>`<button data-action="select" data-person="${p.id}" aria-pressed="${state.selected===p.id}" aria-label="选择 ${esc(p.name)}" title="${esc(p.name)} · ${rank(p)}">${avatar(p)}</button>`).join('')}</div><div class="pool-footer"><span>${state.page*18+1}–${Math.min((state.page+1)*18,list.length)} / ${list.length} 位</span><button data-action="next-pool" ${pageCount===1?'disabled':''}>换一组 ${icon('arrow-right')}</button></div>${focusPerson(p)}`;
}
function viewsMode() {
  const p=selectedViewPerson(),list=viewCandidates();
  if(!p)return empty('这个领域暂无观点快照','可切换到「看人」继续了解投资者。');
  const u=p.opinions[0];
  const index=list.findIndex(x=>x.id===p.id);
  const start=Math.floor(index/5)*5,visible=list.slice(start,start+5);
  return `<div class="view-discovery"><article class="lead-opinion"><header class="topline"><b>${esc(u.ticker)} · ${direction(u.direction)}</b><span>${date(u.at)} · ${p.platform}</span></header><button class="read-quote" data-action="opinion" data-person="${p.id}" data-opinion="0" aria-label="阅读 ${esc(p.name)} 的完整观点"><blockquote>${esc(u.text)}</blockquote></button><div class="person-row">${avatar(p)}${name(p)}${followButton(p)}</div><div class="focus-footer"><span class="meta">${esc(cn(p.style))}</span><button class="text-button" data-action="profile" data-person="${p.id}">了解作者 ${icon('arrow-up-right')}</button></div></article><div class="other-voices"><span>${index+1} / ${list.length} 位作者</span>${visible.map(p=>`<button data-action="select" data-person="${p.id}" aria-pressed="${p.id===selectedViewPerson().id}" aria-label="查看 ${esc(p.name)} 的观点" title="${esc(p.name)}">${avatar(p)}</button>`).join('')}<button class="icon-button" data-action="next-view" aria-label="下一位作者的观点" title="下一位作者">${icon('arrow-right')}</button></div></div>`;
}
function marketRows() {
  let rows=people.flatMap(p=>p.opinions.map((u,index)=>({p,u,index})));
  if(state.feed==='followed')rows=rows.filter(r=>followed.has(r.p.id));
  if(state.feed==='holdings')rows=rows.filter(r=>['NVDA','MU','MSTR'].includes(r.u.ticker));
  return rows.sort((a,b)=>b.u.at.localeCompare(a.u.at));
}
function renderMarket() {
  $('#feed-tabs').innerHTML=[['all','市场观点'],['followed','我的追踪'],['holdings','持仓相关']].map(([id,title])=>`<button data-action="feed" data-feed="${id}" aria-pressed="${state.feed===id}">${title}${id==='followed'&&followed.size?` ${followed.size}`:''}</button>`).join('');
  const groups=new Map();
  for(const row of marketRows()) {if(!groups.has(row.u.ticker))groups.set(row.u.ticker,[]);const group=groups.get(row.u.ticker);if(!group.some(r=>r.p.id===row.p.id))group.push(row);}
  $('#market-feed').innerHTML=groups.size?[...groups].slice(0,5).map(([ticker,rows])=>`<article class="market-group"><header class="market-title"><span class="ticker-mark">${esc(ticker.slice(0,2))}</span><h3>${esc(ticker)}</h3><span class="meta">${rows.length} 位作者 · 快照</span></header>${rows.slice(0,2).map(({p,u,index})=>`<button class="opinion-row" data-action="opinion" data-person="${p.id}" data-opinion="${index}"><p class="opinion-text">${esc(u.text)}</p><div class="opinion-byline">${avatar(p,'sm')}<span>${esc(p.name)}</span><small class="direction ${esc(u.direction)}">${direction(u.direction)}</small><time>${date(u.at)}</time></div></button>`).join('')}</article>`).join(''):empty(followed.size?'已追踪作者暂无近期观点快照':'还没有追踪投资者','在上方选一位你想持续了解的人。');
}
function renderHome() {
  const scroll=$('#home').scrollTop,filterScroll=$('#sectors').scrollLeft;
  $('#candidate-count').textContent=`${candidates().length} 位投资者`;
  document.querySelectorAll('[data-action=mode]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.mode===state.mode));
  $('#sectors').innerHTML=sectors.map(s=>`<button data-action="sector" data-sector="${s}" aria-pressed="${state.sector===s}">${cn(s)}</button>`).join('');
  $('#sectors').scrollLeft=filterScroll;
  $('#discovery-body').innerHTML=state.mode==='people'?peopleMode():viewsMode();
  $('#follow-count').textContent=followed.size||'';
  renderMarket();lucide.createIcons();$('#home').scrollTop=scroll;renderState();
}
function renderState() {
  $('#state-route').textContent=profile?'深入了解':state.mode==='people'?'头像池 → 认识人':'观点 → 认识作者';
  $('#state-sector').textContent=profile?profile.context:cn(state.sector);
  $('#state-followed').textContent=`${followed.size} 位投资者`;
}
function renderProfile() {
  if(!profile){$('#profile-screen').hidden=true;syncLayers();renderState();return;}
  const p=byId(profile.ids[profile.index]);
  const history=evidence.filter(e=>e.authorId===p.id).sort((a,b)=>a.rank-b.rank);
  $('#profile-screen').innerHTML=`<header class="profile-nav"><button class="icon-button" data-action="back-profile" aria-label="返回发现">${icon('arrow-left')}</button><h2>投资者档案</h2><span>${esc(profile.context)}</span></header><div class="profile-scroll"><section class="profile-hero">${avatar(p,'xl')}<div class="person-name"><h3>${esc(p.name)}</h3><div class="meta">${esc(p.handle)} · ${p.platform}</div><span class="rank">${rank(p)} · ${p.platform} 平台</span></div></section><div class="ability-line"><span>${esc(cn(p.sector))}</span><span>${esc(cn(p.style))}</span><span>${esc(cn(p.horizon))}</span></div><div class="stats"><div><b>${p.score}</b><span>Score</span></div><div><b>${p.samples}</b><span>已结算判断</span></div><div><b>${esc(cn(p.horizon))}</b><span>时间级别</span></div></div>${tickerList(p)}<nav class="profile-tabs" aria-label="档案内容"><button data-action="profile-tab" data-tab="recent" aria-pressed="${profile.tab==='recent'}">近期观点</button><button data-action="profile-tab" data-tab="history" aria-pressed="${profile.tab==='history'}">代表判断 ${history.length}</button></nav><div id="profile-content">${profile.tab==='recent'?recentEvidence(p):historicEvidence(history)}</div><p class="profile-limit">历史项目快照。Score 来自公开判断的历史验证，不代表实际交易收益，也不保证未来表现。</p></div><footer class="profile-bottom"><button class="icon-button" data-action="profile-prev" aria-label="上一位投资者" title="上一位投资者" ${profile.index===0?'disabled':''}>${icon('arrow-left')}</button><span class="context">${profile.index+1} / ${profile.ids.length}</span><button class="icon-button" data-action="profile-next" aria-label="下一位投资者" title="下一位投资者" ${profile.index===profile.ids.length-1?'disabled':''}>${icon('arrow-right')}</button>${followButton(p,true)}</footer>`;
  $('#profile-screen').hidden=false;syncLayers();lucide.createIcons();renderState();
}
function recentEvidence(p) {
  return p.opinions.length?p.opinions.map((u,index)=>`<article class="profile-evidence"><header><b>${esc(u.ticker)}</b><small class="direction ${esc(u.direction)}">${direction(u.direction)}</small><time>${date(u.at)}</time></header><p>${esc(u.text)}</p><button class="text-button" data-action="opinion" data-person="${p.id}" data-opinion="${index}">查看完整观点 ${icon('arrow-up-right')}</button></article>`).join(''):empty('本次快照未收录近期观点','可以查看已有代表判断。');
}
function historicEvidence(rows) {
  if(!rows.length)return empty('本次快照暂无代表判断');
  return rows.map(e=>{const s=e.settlement,value=s?.tickerReturnPercent;return `<article class="profile-evidence"><header><b>${esc(e.ticker)}</b><small class="direction ${esc(e.direction)}">${direction(e.direction)}</small><time>${date(e.at)}</time></header><p>${esc(e.text)}</p>${s?`<div class="result-facts"><div><b>${esc(s.horizon||'未注明')}</b><span>结算窗口</span></div><div><b class="${value>=0?'positive':'negative'}">${Number.isFinite(value)?`${value>0?'+':''}${value.toFixed(2)}%`:'未提供'}</b><span>窗口内标的涨跌</span></div></div><div class="meta">${esc(s.entryDay||'')} → ${esc(s.exitDay||'')}</div>`:''}${sourceLink(e.url)}</article>`;}).join('');
}
function sourceLink(url){return /^https?:\/\//.test(url||'')?`<a class="text-button" href="${esc(url)}" target="_blank" rel="noopener noreferrer">原始证据 ${icon('external-link')}</a>`:'';}
function openProfile(id,ids,context) {
  if(profile && !ids && profile.ids.includes(id)) { closeSheet(false);profile.index=profile.ids.indexOf(id);renderProfile();$('#profile-screen [data-action=back-profile]').focus({preventScroll:true});return; }
  lastFocus=document.activeElement;
  if(!ids){const list=state.mode==='people'?candidates():viewCandidates();ids=list.map(p=>p.id);context=cn(state.sector);}
  if(!ids.includes(id)){ids=[id];context='来自市场观点';}
  closeSheet(false);profile={ids:[...ids],index:ids.indexOf(id),context,tab:'recent'};renderProfile();
  $('#profile-screen [data-action=back-profile]').focus({preventScroll:true});
}
function closeProfile(){profile=null;renderProfile();if(lastFocus?.isConnected)lastFocus.focus({preventScroll:true});else $('[data-action=mode]').focus({preventScroll:true});}
function syncLayers() {
  $('#home').inert=Boolean(profile||sheet);
  $('.bottom-nav').hidden=Boolean(profile);
  $('.bottom-nav').inert=Boolean(sheet);
  $('#profile-screen').inert=Boolean(sheet);
}
function directoryRows(list) {
  return list.length?list.map(p=>`<div class="directory-row"><button data-action="directory-person" data-person="${p.id}">${avatar(p)}${name(p)}</button>${followButton(p,false,true)}</div>`).join(''):empty('没有匹配的投资者');
}
function filteredDirectory() {
  const ids=sheet.kind==='following'?[...followed]:sheet.ids;
  return ids.map(byId).filter(Boolean).filter(p=>[p.name,p.handle,cn(p.sector),...p.tickers].join(' ').toLowerCase().includes(sheet.query||''));
}
function openDirectory(kind='directory') {
  sheet={kind,query:'',ids:candidates().map(p=>p.id),context:kind==='following'?'我的追踪':cn(state.sector)};
  showSheet(kind==='following'?'我的追踪':`发现投资者 · ${cn(state.sector)}`,`<input id="directory-search" aria-label="搜索姓名或标的" placeholder="搜索姓名、标的或领域"><div id="directory-results">${directoryRows(filteredDirectory())}</div>`);
  $('#directory-search').addEventListener('input',e=>{sheet.query=e.target.value.trim().toLowerCase();$('#directory-results').innerHTML=directoryRows(filteredDirectory());lucide.createIcons();});
}
function showSheet(title,body) {
  $('#sheet-title').textContent=title;$('#sheet-body').innerHTML=body;$('#sheet').hidden=false;$('#sheet-body').scrollTop=0;syncLayers();lucide.createIcons();$('#sheet [data-action=close-sheet]').focus({preventScroll:true});
}
function closeSheet(restore=true) {
  sheet=null;$('#sheet').hidden=true;syncLayers();
  if(restore){const target=profile?$('#profile-screen [data-action=back-profile]'):$('.app-header [data-action=search]');target?.focus({preventScroll:true});}
}
function showOpinion(id,index) {
  const p=byId(id),u=p.opinions[index];
  sheet={kind:'opinion',id,index};
  showSheet(`${u.ticker} · ${direction(u.direction)}`,`<div class="person-row">${avatar(p)}${name(p)}${followButton(p)}</div><div class="meta">原帖日期 ${esc(u.at.slice(0,10))}</div><p class="full-opinion">${esc(u.text)}</p><button class="text-button" data-action="profile" data-person="${p.id}">查看投资者档案 ${icon('arrow-up-right')}</button><br>${sourceLink(u.url)}`);
}
function notify(message) {clearTimeout(toastTimer);$('#toast').textContent=message;$('#toast').style.display='block';toastTimer=setTimeout(()=>$('#toast').style.display='none',2000);}
function toggleFollow(id) {
  followed.has(id)?followed.delete(id):followed.add(id);
  try{localStorage.setItem(storageKey,JSON.stringify([...followed]));}catch{}
  renderHome();
  document.querySelectorAll(`#profile-screen [data-action=follow], #sheet [data-action=follow]`).forEach(b=>{const p=byId(b.dataset.person);b.outerHTML=followButton(p,b.classList.contains('primary'),Boolean(b.closest('.directory-row')));});
  if(sheet&&['directory','following'].includes(sheet.kind)){$('#directory-results').innerHTML=directoryRows(filteredDirectory());}
  lucide.createIcons();notify(`${followed.has(id)?'已追踪':'已取消追踪'} ${byId(id).name}`);
}
document.addEventListener('click',e=>{
  const button=e.target.closest('button[data-action]');if(!button)return;
  const {action,person}=button.dataset;
  if(action==='select'){state.selected=person;renderHome();}
  if(action==='mode'){state.mode=button.dataset.mode;renderHome();}
  if(action==='sector'){state.sector=button.dataset.sector;state.page=0;if(!candidates().some(p=>p.id===state.selected))state.selected=candidates()[0]?.id;renderHome();}
  if(action==='next-pool'){state.page=(state.page+1)%Math.ceil(candidates().length/18);state.selected=candidates()[state.page*18].id;renderHome();}
  if(action==='next-view'){const list=viewCandidates(),index=list.findIndex(p=>p.id===selectedViewPerson().id);state.selected=list[(index+1)%list.length].id;renderHome();}
  if(action==='feed'){state.feed=button.dataset.feed;renderHome();}
  if(action==='follow')toggleFollow(person);
  if(action==='profile')openProfile(person);
  if(action==='directory-person'){const ids=filteredDirectory().map(p=>p.id),context=sheet.context;openProfile(person,ids,context);}
  if(action==='back-profile')closeProfile();
  if(action==='profile-next'||action==='profile-prev'){profile.index+=action==='profile-next'?1:-1;renderProfile();$('#profile-screen .profile-scroll').scrollTop=0;}
  if(action==='profile-tab'){profile.tab=button.dataset.tab;const scroll=$('.profile-scroll').scrollTop;renderProfile();$('.profile-scroll').scrollTop=scroll;}
  if(action==='opinion')showOpinion(person,Number(button.dataset.opinion));
  if(action==='close-sheet')closeSheet();
  if(action==='search'||action==='directory')openDirectory();
  if(action==='following')openDirectory('following');
  if(action==='home'){$('#home').scrollTo({top:0,behavior:'auto'});}
  if(action==='portfolio'){sheet={kind:'portfolio'};showSheet('持仓关联 · 评审示例',`<p class="meta">这三个示例标的用于下方的持仓观点筛选，不代表你的真实持仓。</p>${['NVDA','MU','MSTR'].map(t=>`<div class="ticker-example"><b>${t}</b><span>示例标的</span></div>`).join('')}<button class="text-button" data-action="show-holdings">查看持仓相关观点 ${icon('arrow-right')}</button>`);}
  if(action==='show-holdings'){state.feed='holdings';closeSheet();renderHome();const home=$('#home');home.scrollTo({top:home.scrollTop+$('.market-section').getBoundingClientRect().top-home.getBoundingClientRect().top-10,behavior:'auto'});}
  if(action==='collie'){sheet={kind:'collie'};showSheet('Mr Collie',`<p class="full-opinion">本次原型聚焦投资者发现，未连接 AI 服务。</p><p class="meta">已追踪 ${followed.size} 位投资者。可以先查看他们的原始观点与代表判断。</p><button class="text-button" data-action="following">查看我的追踪 ${icon('arrow-right')}</button>`);}
});
$('#sheet').addEventListener('click',e=>{if(e.target===$('#sheet'))closeSheet();});
document.addEventListener('keydown',e=>{
  if(e.key==='Escape'){if(sheet)closeSheet();else if(profile)closeProfile();}
  const layer=sheet?$('.sheet'):profile?$('#profile-screen'):null;
  if(e.key==='Tab'&&layer){const els=[...layer.querySelectorAll('button:not(:disabled),a[href],input')].filter(el=>el.getClientRects().length),first=els[0],last=els.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}
});
$('#reset').addEventListener('click',()=>{followed.clear();try{localStorage.removeItem(storageKey);}catch{}Object.assign(state,{mode:'people',sector:'all',selected:initialPerson.id,page:0,feed:'all'});profile=null;closeSheet(false);renderProfile();renderHome();$('#home').scrollTop=0;notify('已重置此原型的追踪与筛选');});
renderHome();
