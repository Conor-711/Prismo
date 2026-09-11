const assets = '../../../../ios/BSmart/Assets.xcassets/';
const nvda = `${assets}Ticker_NVDA.imageset/NVDA.png`;
const documents = {
  earnings: {
    type: '财报', date: '2025.08.27', period: 'FY2026 Q2',
    title: 'Blackwell 数据中心收入环比增长 17%',
    description: 'NVIDIA 发布 FY2026 第二季度业绩。该数字是本季度已披露数据，不是未来增长承诺。',
    fullTitle: 'NVIDIA 公布 FY2026 第二季度业绩',
    metrics: [['$46.7B', '公司总收入'], ['+17%', 'Blackwell 数据中心收入 · 环比']],
    facts: ['本季度收入为 467 亿美元，财季截至 2025 年 7 月 27 日。', 'Blackwell 数据中心收入环比增长 17%。'],
    outlook: '管理层当时预计下一季度收入为 540 亿美元，上下浮动 2%；该指引未假设对中国的 H20 出货。',
    boundary: '“产品升级可能继续带动需求”属于作者的推断。这份公告披露了本季结果和管理层指引，并未保证未来增长。',
    excerpts: ['reported revenue for the second quarter ended July 27, 2025, of $46.7 billion', 'NVIDIA’s Blackwell Data Center revenue grew 17% sequentially.'],
    locator: '新闻稿 · 开头业绩段落',
    url: 'https://nvidianews.nvidia.com/news/nvidia-announces-financial-results-for-second-quarter-fiscal-2026',
    filing: 'https://www.sec.gov/Archives/edgar/data/1045810/000104581025000207/nvda-20250827.htm'
  },
  partnership: {
    type: '合作', date: '2025.03.18', period: 'Oracle × NVIDIA',
    title: 'Oracle 与 NVIDIA 宣布企业 AI 集成',
    description: '官方公告涉及 OCI 与 NVIDIA AI Enterprise 的集成，以及企业 AI 开发工具的可用性。',
    fullTitle: 'Oracle 与 NVIDIA 合作推进企业 Agentic AI',
    metrics: [['OCI', 'Oracle 云基础设施'], ['AI Enterprise', 'NVIDIA 软件平台']],
    facts: ['双方宣布将 NVIDIA 的加速计算与推理软件接入 Oracle 的 AI 基础设施及生成式 AI 服务。', '公告计划通过 OCI Console 提供 NVIDIA AI 工具与 NIM 微服务。'],
    outlook: '产品可用性与预期效果属于公告中的计划性表述，不等于已交付收入。',
    boundary: '该公告没有披露合作订单金额。不能由“宣布合作”推导出新增订单规模或确定的股价影响。',
    excerpts: ['Oracle and NVIDIA today announced a first-of-its-kind integration', 'will make 160+ AI tools and 100+ NVIDIA NIM'],
    locator: '新闻稿 · 开头集成说明（短摘录）',
    url: 'https://nvidianews.nvidia.com/news/oracle-and-nvidia-collaborate-to-help-enterprises-accelerate-agentic-ai-inference'
  }
};
const scenarios = {
  earnings: {doc: 'earnings', date: '2025.08.28', title: 'Blackwell 已兑现增长，我更关注下一季能否延续',
    reason: '直接引用', copy: 'Blackwell 数据中心收入环比增长 17%，这是我继续关注 NVDA 的原因之一。',
    inference: '我的判断是：产品升级可能继续带动需求，但下一季的兑现程度仍然需要观察。我不会把一个季度的增长直接外推成长期趋势。',
    english: 'The reported quarterly improvement in Blackwell revenue is why I am still watching NVDA. My inference is that the product upgrade could continue to support demand, but the next quarter still needs to deliver.',
    decision: '一条观点，一份出处。', explanation: '作者明确链接了官方财报。默认只露出最相关的一件披露；同一新闻稿在 IR 与 SEC 的副本按同一事件处理。'},
  partnership: {doc: 'partnership', date: '2025.03.19', title: 'Oracle 的集成可能扩大 NVIDIA 软件触达',
    reason: '系统关联', copy: '我关注的是 Oracle 与 NVIDIA 对企业 AI 的集成，这可能降低企业使用 NVIDIA 软件的门槛。',
    inference: '我的判断偏向中期的软件分发机会，而不是已经到手的收入。合作能否带来足够的商业转化，还要看后续披露。',
    english: 'The Oracle and NVIDIA integration could lower the barrier for enterprises to use NVIDIA software. This is a medium-term distribution thesis, not a claim about revenue already secured.',
    decision: '有官方资料，不代表作者引用过。', explanation: '这个示例没有原帖链接。系统找到了同一事件的官方公告，只标“相关官方资料”。公司、事项和日期都必须匹配。'},
  unmatched: {doc: null, date: '2025.08.28', title: '我在关注一项尚未披露的大型订单传闻',
    reason: null, copy: '市场上有人讨论 NVIDIA 可能获得一项新的大型订单，但目前我还没有看到对应的公司公告。',
    inference: '这只是一个尚待确认的关注点，并不是已披露的合同。我会先等待官方信息。',
    english: 'I am watching a rumor about a potential large NVIDIA order. I have not seen a corresponding company announcement. This is an unconfirmed watch item, not a disclosed contract.',
    decision: '留白，也是一种准确。', explanation: '没有找到可定位的官方披露时，不用同标的的旧新闻填空，不制造“官方已验证”。仍允许用户追踪公司后续披露。'}
};
let scenario = 'earnings';
let stack = [{page: 'opinion', scroll: 0}];
let translated = true;
const savedOpinions = new Set();
let channelFilter = '全部';
let preferences = {followed: false, earnings: true, partnership: true, filings: true, cadence: 'digest'};
try { const saved = JSON.parse(localStorage.getItem('bsmart.official-context.prototype') || 'null'); if (saved) preferences = {...preferences, ...saved}; } catch {}
const app = document.getElementById('app');
const icon = name => `<i data-lucide="${name}"></i>`;
const logo = () => `<img src="${nvda}" alt="NVIDIA">`;
const external = (url, label) => `<a class="original-link" href="${url}" target="_blank" rel="noopener noreferrer">${label}${icon('arrow-up-right')}</a>`;
const current = () => stack[stack.length - 1];
const follow = (full = false) => `<button class="follow ${preferences.followed ? 'on' : ''}" data-action="follow" aria-pressed="${preferences.followed}">${icon(preferences.followed ? 'check' : 'plus')}${preferences.followed ? '已追踪' : full ? '追踪 NVIDIA 官方' : '追踪'}</button>`;
const channelRow = () => `<div class="channel-row">${logo()}<button class="channel-label" data-action="channel"><b>NVIDIA 官方渠道</b><small>IR · Newsroom · SEC 披露</small></button>${follow()}</div>`;

function nav(title, action = 'back') {
  return `<header class="app-nav"><button class="icon" data-action="${action}" title="${action === 'back' ? '返回' : '重新开始'}" aria-label="${action === 'back' ? '返回' : '重新开始'}">${icon('chevron-left')}</button><div class="nav-title">${logo()}${title}</div>${current().page === 'official' ? `<button class="icon" data-action="channel" title="公司官方渠道" aria-label="公司官方渠道">${icon('radio')}</button>` : ''}</header>`;
}
function officialCard(key, linkType = true) {
  const d = documents[key];
  return `${linkType ? `<div class="link-type">${icon(scenario === 'earnings' ? 'link-2' : 'scan-search')}${scenario === 'earnings' ? '作者引用' : '相关官方资料 · 系统关联'}</div>` : ''}
    <button class="official-card" data-doc="${key}" style="view-transition-name:official-card" aria-label="查看${d.fullTitle}">
      <div class="issuer">${logo()}<span>NVIDIA 官方</span><span class="doc-kind">${d.type}</span></div>
      <h3>${d.title}</h3><p>${d.description}</p>
      <div class="card-meta"><span>${d.date} · ${d.period}</span><span>查看披露${icon('arrow-up-right')}</span></div>
    </button>`;
}
function opinion() {
  const s = scenarios[scenario];
  return `${nav('NVDA · 观点', 'restart')}<div class="app-scroll" tabindex="-1">
    <div class="author-row"><div class="avatar" aria-hidden="true">SA</div><div><div class="author-name">示例 Smart Account</div><div class="author-meta">X · ${s.date}</div></div><div class="rank">Top 10% · 示例</div></div>
    <h2 class="opinion-title" tabindex="-1">${s.title}</h2>
    <div class="tags"><span class="tag mint">${scenario === 'unmatched' ? '观察' : '看多'}</span><span class="tag">中期</span>${s.doc ? `<button class="source-chip" data-action="jump-official">${icon('file-text')}1 件官方披露${icon('chevron-down')}</button>` : ''}</div>
    <div class="copy-mode" role="group" aria-label="观点语言"><button data-language="zh" class="${translated ? 'selected' : ''}" aria-pressed="${translated}">中文译文</button><button data-language="en" class="${!translated ? 'selected' : ''}" aria-pressed="${!translated}">英文原文</button></div>
    <div class="opinion-copy">${translated ? `<p>${s.doc ? `<button class="fact-ref" data-doc="${s.doc}">${s.copy}</button>` : s.copy}</p><p>${s.inference}</p>` : `<p>${s.english}</p>`}</div>
    <section id="official-context"><div class="section-label"><span>官方信息</span><span class="minor">NVDA</span></div>${s.doc ? officialCard(s.doc) : `<div class="unmatched">${icon('file-question')}<span>暂无可关联的官方披露</span></div>`}${channelRow()}</section>
    <div class="save-row"><span>${s.date} · 示例观点</span><button class="icon" data-action="save-opinion" aria-pressed="${savedOpinions.has(scenario)}" aria-label="收藏观点" title="收藏观点">${icon(savedOpinions.has(scenario) ? 'bookmark-check' : 'bookmark')}</button></div>
  </div>`;
}
function official(key) {
  const d = documents[key];
  return `${nav('官方披露')}<div class="app-scroll" tabindex="-1">
    <div class="document-hero" style="view-transition-name:official-card"><div class="issuer">${logo()}NVIDIA Newsroom <span class="doc-kind">${d.type}</span></div><h2 class="disclosure-title" tabindex="-1">${d.fullTitle}</h2><div class="disclosure-date">${d.date} · ${d.period}</div></div>
    <div class="source-label">公司披露 · bSmart 转述</div>
    <div class="metric-band">${d.metrics.map(([value,label])=>`<div><b class="${value.length > 9 ? 'word-value' : ''}">${value}</b><small>${label}</small></div>`).join('')}</div>
    <ol class="fact-lines">${d.facts.map((fact,i)=>`<li><span class="num">0${i+1}</span><span>${fact}<button data-action="show-extract" data-excerpt="${i}" aria-label="查看第${i+1}条的原始出处">[${i+1}]</button></span></li>`).join('')}</ol>
    <div class="outlook"><b>${key === 'earnings' ? '管理层预期 · 非已实现业绩' : '公告中的计划'}</b><p>${d.outlook}</p></div>
    <div class="section-label"><span>原始出处</span><span class="minor">EN</span></div>
    <div class="source-extract" id="source-extract"><blockquote><mark>${d.excerpts[0]}</mark></blockquote><div class="extract-meta">${d.locator}</div></div>
    ${external(d.url, '打开 NVIDIA 官方原文')}
    ${d.filing ? external(d.filing, '同一披露的 SEC 8-K · 附件索引') : ''}
    <p class="boundary">${d.boundary}</p>
    ${channelRow()}
    ${scenarios[scenario].doc === key ? `<button class="back-to-call" data-action="opinion"><div class="avatar">SA</div><span><b>回到作者的解读</b><small>示例 Smart Account · ${scenarios[scenario].date}</small></span>${icon('arrow-right')}</button>` : ''}
  </div>`;
}
function channel() {
  const items = Object.entries(documents).filter(([,d])=>channelFilter === '全部' || d.type === channelFilter);
  return `${nav('官方渠道')}<div class="app-scroll" tabindex="-1"><div class="channel-hero">${logo()}<div><h2 tabindex="-1">NVIDIA 官方</h2><p>NVDA · 公司公告与披露</p></div></div>
    <div class="channel-actions">${follow(true)}<button class="icon" data-action="settings" aria-label="追踪设置" title="追踪设置">${icon('sliders-horizontal')}</button></div>
    <div class="source-label">渠道来源</div><a class="original-link" href="https://investor.nvidia.com" target="_blank" rel="noopener noreferrer">NVIDIA Investor Relations ${icon('arrow-up-right')}</a><a class="original-link" href="https://nvidianews.nvidia.com" target="_blank" rel="noopener noreferrer">NVIDIA Newsroom ${icon('arrow-up-right')}</a>
    <div class="filter-tabs" role="group" aria-label="公告类型">${['全部','财报','合作'].map(x=>`<button data-filter="${x}" class="${channelFilter===x?'selected':''}" aria-pressed="${channelFilter===x}">${x}</button>`).join('')}</div>
    ${items.map(([key,d])=>`<button class="event-row" data-doc="${key}"><div class="event-date"><span>${d.date}</span><span>${d.type}</span></div><h3>${d.fullTitle}</h3><div class="row-end"><span>NVIDIA 官方</span>${icon('arrow-up-right')}</div></button>`).join('')}
    <p class="boundary">历史资料 · 更新顺序以官方发布时间为准</p>
  </div>`;
}
function settings() {
  return `${nav('追踪设置')}<div class="app-scroll" tabindex="-1"><div class="channel-hero">${logo()}<div><h2 tabindex="-1">NVIDIA 官方</h2><p>NVDA</p></div></div>
    <div class="settings-group"><h3>披露类型</h3>${[['earnings','财报与业绩指引'],['partnership','重大合作与公司公告'],['filings','重大 SEC 披露']].map(([id,label])=>`<label class="setting"><span>${label}</span><input type="checkbox" data-preference="${id}" ${preferences[id]?'checked':''} aria-label="${label}"></label>`).join('')}</div>
    <div class="settings-group"><h3>提醒方式</h3><label class="setting"><span>每日摘要</span><input name="cadence" type="radio" value="digest" ${preferences.cadence==='digest'?'checked':''}></label><label class="setting"><span>重要披露即时，其余进摘要</span><input name="cadence" type="radio" value="important" ${preferences.cadence==='important'?'checked':''}></label></div>
    <button class="primary" data-action="save-settings">${preferences.followed?'保存设置':'保存并追踪'}</button>
  </div>`;
}
function render() {
  const state = current();
  app.innerHTML = `<div class="screen">${state.page === 'opinion' ? opinion() : state.page === 'official' ? official(state.doc) : state.page === 'channel' ? channel() : settings()}</div>`;
  if (window.lucide) lucide.createIcons();
  const scroll = app.querySelector('.app-scroll');
  scroll.scrollTop = state.scroll || 0;
  document.getElementById('route').textContent = {opinion:'观点详情 → 官方信息',official:'官方披露 → 原始出处',channel:'公司官方渠道 → 持续追踪',settings:'追踪设置'}[state.page];
  document.getElementById('decision-title').textContent = scenarios[scenario].decision;
  document.getElementById('decision-copy').textContent = scenarios[scenario].explanation;
}
function transition(change) {
  current().scroll = app.querySelector('.app-scroll')?.scrollTop || 0;
  const update = () => { change(); render(); };
  if (document.startViewTransition && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.startViewTransition(update).finished.then(()=>app.querySelector('h2')?.focus({preventScroll:true})).catch(()=>{});
  } else { update(); app.querySelector('.screen').animate?.([{opacity:.65, transform:'translateX(12px)'},{opacity:1,transform:'none'}],{duration:matchMedia('(prefers-reduced-motion: reduce)').matches?0:180}); }
}
function open(page, doc) { transition(()=>stack.push({page,doc,scroll:0})); }
function back() { if (stack.length>1) transition(()=>stack.pop()); else toast('当前为观点详情预览'); }
function persist() { try { localStorage.setItem('bsmart.official-context.prototype',JSON.stringify(preferences)); } catch {} }
let toastTimer;
function toast(text) { clearTimeout(toastTimer); app.querySelector('.toast')?.remove(); const el=document.createElement('div'); el.className='toast'; el.role='status'; el.textContent=text; app.append(el); toastTimer=setTimeout(()=>el.remove(),2200); }
app.addEventListener('click', event=>{
  const button = event.target.closest('button'); if (!button) return;
  if (button.dataset.doc) { open('official',button.dataset.doc); return; }
  if (button.dataset.language) { translated=button.dataset.language==='zh'; current().scroll=app.querySelector('.app-scroll').scrollTop; render(); return; }
  if (button.dataset.filter) { channelFilter=button.dataset.filter; current().scroll=app.querySelector('.app-scroll').scrollTop; render(); return; }
  switch(button.dataset.action) {
    case 'back': back(); break;
    case 'restart': transition(()=>stack=[{page:'opinion',scroll:0}]); break;
    case 'jump-official': app.querySelector('#official-context').scrollIntoView({behavior:'smooth',block:'start'}); break;
    case 'show-extract': app.querySelector('#source-extract mark').textContent=documents[current().doc].excerpts[Number(button.dataset.excerpt)]; app.querySelector('#source-extract').scrollIntoView({behavior:'smooth',block:'center'}); break;
    case 'channel': open('channel'); break;
    case 'settings': open('settings'); break;
    case 'opinion': transition(()=>{ const index=stack.findLastIndex(state=>state.page==='opinion'); stack=index>=0?stack.slice(0,index+1):[{page:'opinion',scroll:0}]; }); break;
    case 'follow': preferences.followed=!preferences.followed; persist(); current().scroll=app.querySelector('.app-scroll').scrollTop; render(); toast(preferences.followed?`已追踪 NVIDIA 官方 · ${preferences.cadence==='digest'?'每日摘要':'重要披露即时提醒'}`:'已取消追踪 NVIDIA 官方'); break;
    case 'save-settings': {
      const inputs=app.querySelectorAll('[data-preference]');
      if (![...inputs].some(input=>input.checked)) { toast('至少选择一种披露类型'); return; }
      inputs.forEach(input=>preferences[input.dataset.preference]=input.checked);
      preferences.cadence=app.querySelector('[name=cadence]:checked').value; preferences.followed=true; persist(); back(); setTimeout(()=>toast('追踪设置已保存'),400); break;
    }
    case 'save-opinion': savedOpinions.has(scenario)?savedOpinions.delete(scenario):savedOpinions.add(scenario); current().scroll=app.querySelector('.app-scroll').scrollTop; render(); toast(savedOpinions.has(scenario)?'观点已收藏':'已取消收藏'); break;
  }
});
document.querySelectorAll('[data-scenario]').forEach(button=>button.addEventListener('click',()=>{
  scenario=button.dataset.scenario; translated=true; stack=[{page:'opinion',scroll:0}];
  document.querySelectorAll('[data-scenario]').forEach(x=>{x.classList.toggle('active',x===button);x.setAttribute('aria-pressed',x===button);}); render();
}));
document.querySelectorAll('[data-studio]').forEach(button=>button.addEventListener('click',()=>{
  document.querySelectorAll('[data-studio]').forEach(x=>x.classList.toggle('active',x===button));
  document.getElementById('prototype').hidden=button.dataset.studio!=='prototype'; document.getElementById('research').hidden=button.dataset.studio!=='research';
}));
document.getElementById('theme').addEventListener('click',()=>document.body.classList.toggle('light'));
document.getElementById('channel-shortcut').addEventListener('click',()=>open('channel'));
document.getElementById('reset').addEventListener('click',()=>{ preferences={followed:false,earnings:true,partnership:true,filings:true,cadence:'digest'};savedOpinions.clear();channelFilter='全部';persist();document.querySelector('[data-scenario=earnings]').click(); });
document.addEventListener('keydown',event=>{if(event.key==='Escape')back();});
render();
