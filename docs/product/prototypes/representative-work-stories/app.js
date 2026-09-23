const designs = [
  { id: 'a', name: '一句话代表作', note: '像向朋友介绍一样' },
  { id: 'b', name: '前后对照', note: '两个价格，一眼看懂' },
  { id: 'c', name: '故事与轨迹', note: '图在前，故事在后 · 已选' },
];
const stage = document.querySelector('#stage');
const caseSelect = document.querySelector('#case-select');
const followed = new Set();
let caseIndex = 0;
let activeDesign = 'c';
let transitionBusy = false;

const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const icon = name => `<i data-lucide="${name}" aria-hidden="true"></i>`;
const money = number => '$' + number.toLocaleString('en-US', { maximumFractionDigits: 2 });
const change = number => '+' + Math.round(number).toLocaleString('en-US') + '%';
const dotted = day => day.replaceAll('-', '.');
const month = day => day.slice(0, 7).replaceAll('-', '.');
const safeURL = value => /^https:\/\//.test(value ?? '') ? escapeHTML(value) : '#';
const images = () => STORY_DATA.map(d => `<img src="${d.avatar}" alt="" loading="eager">`).join('');
const icons = () => lucide.createIcons();
function label(d) {
  return `<div class="story-label"><img class="ticker-logo" src="${d.logo}" alt="${d.ticker}"><strong>${d.ticker}</strong><span>· 代表作</span>${icon('arrow-up-right')}</div>`;
}
function cutoff(d) {
  return `<div class="story-date">${icon('calendar-days')}<span>股价表现 · 截至 ${dotted(d.endDay)}</span></div>`;
}
function narrative(d) {
  return `<p class="story-copy">${month(d.publishedDay)}，${escapeHTML(d.company)}价格还是 <strong>${money(d.reference)}</strong>，他就已<strong>公开看多</strong>。</p>
    <p class="story-copy">${month(d.peakDay)}，最高涨到 <strong>${money(d.peak)}</strong>，比当时高出约 <strong class="highlight">${change(d.peakChange).slice(1)}</strong>。</p>`;
}
function story(d, design) {
  if (design === 'a') return narrative(d) + cutoff(d);
  if (design === 'b') return `
    <p class="story-copy">${month(d.publishedDay)}，他已看好${escapeHTML(d.company)}。<br>后来，股价走到了这里。</p>
    <div class="price-comparison">
      <div><span>${dotted(d.publishedDay)} · 公开看多</span><b>${money(d.reference)}</b><span>当时价格</span></div>
      ${icon('arrow-right')}
      <div><span>${dotted(d.peakDay)}</span><b>${money(d.peak)}</b><span>区间最高价</span></div>
    </div>
    <div class="comparison-result"><span>区间最大股价涨幅</span><b>${change(d.peakChange)}</b></div>${cutoff(d)}`;
  return '';
}
function callCounts(d) {
  return { bull: d.calls.filter(c => c.direction === 'bullish').length, bear: d.calls.filter(c => c.direction === 'bearish').length };
}
function repeatCopy(d) {
  const count = callCounts(d).bull;
  return `${dotted(d.publishedDay)}，${escapeHTML(d.company)}还是 <strong>${money(d.reference)}</strong>，他就看多了。${count > 1 ? `这段记录里，他 <strong>${count} 次看多</strong>。` : ''}最高到 <strong>${money(d.peak)}</strong>（${dotted(d.peakDay)}），比当时涨了约 <strong>${change(d.peakChange).slice(1)}</strong>。`;
}
function markedChart(d, detail = false) {
  return `<div class="work-chart ${detail ? 'detail-plot' : ''}"><canvas class="sparkline" data-price-chart data-call-markers aria-label="${d.ticker} 价格与最多 3 个看多节点" role="img"></canvas><div class="marker-layer"></div></div>`;
}
function storyCard(d, design) {
  if (design !== 'c') return `<button class="story-card story-${design}" data-open="${design}" style="view-transition-name:work-${design}" aria-label="查看 ${d.ticker} 代表作与原帖">${label(d)}${story(d, design)}</button>`;
  const count = callCounts(d);
  return `<div class="story-card story-c" style="view-transition-name:work-c">
    <div class="story-label"><img class="ticker-logo" src="${d.logo}" alt="${d.ticker}"><strong>${d.ticker}</strong><span>· 代表作</span>
      <button class="work-open" data-open="c" aria-label="查看 ${d.ticker} 代表作与原帖" title="查看代表作">${icon('arrow-up-right')}</button></div>
    <div class="trajectory-top"><span>区间最大股价涨幅</span><b>${change(d.peakChange)}</b></div>
    ${markedChart(d)}
    <div class="chart-dates"><span>${dotted(d.referenceDay)}</span><span>${dotted(d.endDay)}</span></div>
    <div class="call-counts"><span><i class="bull-dot"></i>${count.bull} 次看多</span>${count.bear ? `<span><i class="bear-dot"></i>${count.bear} 次看空</span>` : ''}<span class="peak-key">◆ 区间最高</span></div>
    <button class="story-description" data-open="c" aria-label="展开 ${d.ticker} 的 ${d.calls.length} 条历史观点"><p>${repeatCopy(d)}</p>
      <span class="story-footer"><span>截至 ${dotted(d.endDay)}</span><span>${d.calls.length} 条历史观点 ${icon('chevron-right')}</span></span>
    </button></div>`;
}
function authorLine(d, detail = false) {
  return `<div class="author-line"><img class="author-photo" src="${d.avatar}" alt="${escapeHTML(d.name)}">
    <div class="author-info"><a class="author-name" href="${safeURL(d.profileURL)}" target="_blank" rel="noopener noreferrer">${escapeHTML(d.name)}</a>
      <div class="author-meta">X · Top ${d.percentile}% · ${escapeHTML(d.style)}</div></div>
    ${detail ? '' : `<button class="follow" data-follow aria-label="${followed.has(d.id) ? '取消追踪' : '追踪'} ${escapeHTML(d.name)}" title="${followed.has(d.id) ? '已追踪' : '追踪投资者'}" aria-pressed="${followed.has(d.id)}">${icon(followed.has(d.id) ? 'check' : 'plus')}</button>`}</div>`;
}
function portraits() {
  const order = [(caseIndex + 2) % 3, caseIndex, (caseIndex + 1) % 3];
  return order.map(index => {
    const d = STORY_DATA[index];
    return `<button class="portrait-choice ${index === caseIndex ? 'selected' : ''}" data-case="${index}" aria-label="查看 ${escapeHTML(d.name)} 的代表作" aria-pressed="${index === caseIndex}">
      <span class="portrait-wrap"><img src="${d.avatar}" alt="${escapeHTML(d.name)}"><span class="platform-dot">X</span></span>
      <span class="rank">Top ${d.percentile}%</span></button>`;
  }).join('');
}
function contextContent(d, scene = 0) {
  const content = [
    ['持仓与追踪', `${escapeHTML(d.name)} · ${d.ticker}`, '公开看多 · 历史观点'],
    ['市场情况', `${d.ticker} · 聪明共识`, `${escapeHTML(d.company)} · 相关账户判断`],
    ['聪明动态', escapeHTML(d.name), `${d.ticker} · ${dotted(d.publishedDay)} · 公开看多`],
  ][scene];
  return `<img src="${d.logo}" alt="${d.ticker}"><div><strong>${content[1]}</strong><p>${content[2]}</p></div>`;
}
function detail(d, design) {
  return `<section class="detail-page" hidden aria-label="${escapeHTML(d.name)} 的 ${d.ticker} 代表作详情">
    <header class="detail-nav"><button class="icon-button" data-back aria-label="返回首页" title="返回首页">${icon('arrow-left')}</button><b>代表作</b></header>
    <div class="detail-hero" style="view-transition-name:work-${design}">${label(d)}${narrative(d)}<div class="peak-summary">${change(d.peakChange)} <span>区间最大股价涨幅</span></div>${cutoff(d)}</div>
    ${authorLine(d, true)}
    <section class="detail-section"><h4>这次判断发生了什么</h4>
      <ol class="event-list">
        <li><time>${dotted(d.publishedDay)}</time><strong>公开看多 ${d.ticker}</strong><p>观点发布前最近一个已收盘交易日为 ${dotted(d.referenceDay)}，收盘价 ${money(d.reference)}。</p></li>
        <li><time>${dotted(d.peakDay)}</time><strong>区间内最高 ${money(d.peak)}</strong><p>比看多时的价格最高上涨约 ${change(d.peakChange).slice(1)}。这是股价涨幅，不是作者已实现收益。</p></li>
        <li><time>${dotted(d.endDay)}</time><strong>本次行情统计截止</strong><p>仅使用项目快照已有的后续日线，不表示截至今天的最高价。</p></li>
      </ol>
    </section>
    <section class="detail-section"><h4>发布之后的股价</h4>
      ${markedChart(d, true)}
      <div class="chart-dates"><span>${dotted(d.referenceDay)}</span><span>${dotted(d.endDay)}</span></div>
      <div class="chart-key"><span class="line-key"></span>日收盘价<span class="point-key"></span>区间最高价</div>
    </section>
    <section class="detail-section call-history"><h4>这段时间，他说过什么 <span>${d.calls.length}</span></h4>
      <ol>${d.calls.map(call => `<li data-record="${call.id}"><div class="call-heading"><time>${dotted(call.day)}</time><b class="${call.direction === 'bullish' ? 'bullish' : 'bearish'}">${call.direction === 'bullish' ? '看多' : '看空'} · ${money(call.price)}</b></div>
        ${call.originalText ? `<p>${escapeHTML(call.originalText.slice(0, 230))}${call.originalText.length > 230 ? '…' : ''}</p>` : ''}
        <a class="source-link" href="${safeURL(call.sourceURL)}" target="_blank" rel="noopener noreferrer">${icon('external-link')}当时的原帖</a></li>`).join('')}</ol>
    </section>
    <section class="detail-section"><h4>当时的原帖</h4><p class="original-post">${escapeHTML(d.originalText.slice(0, 440))}${d.originalText.length > 440 ? '…' : ''}</p>
      ${d.originalText.length > 440 ? `<details><summary>完整原文</summary><p class="original-post">${escapeHTML(d.originalText)}</p></details>` : ''}
      <a class="source-link" href="${safeURL(d.sourceURL)}" target="_blank" rel="noopener noreferrer">${icon('external-link')}查看 X 原帖</a>
    </section>
    <details><summary>价格与统计口径</summary><p>来源：${escapeHTML(d.priceSource)} 日线快照。观点时间以纽约时间显示。统计区间为 ${dotted(d.startDay)} 至 ${dotted(d.endDay)}，排除发布当天的最高价，避免混入发帖前的行情。</p><p>最大股价涨幅 = (${money(d.peak)} ÷ ${money(d.reference)} − 1) × 100% = +${d.peakChange.toFixed(2)}%。看多或看空节点的价格取发帖前最近一个已完成的日线收盘价，不是实时成交价或作者实际买卖价，未计交易费用。</p><p>节点来自已有观点及历史价格证据中的观点记录，按原帖去重；看多次数不是作者全部发帖次数，不代表持续持有。同一位置附近的多条观点合并显示数量，仍可查看每条原帖。Top ${d.percentile}% 为现有榜单快照中的平台排名，不是发帖当时的排名。</p></details>
    <p class="detail-caveat">这是回顾性挑选的单个代表案例，不代表作者所有观点的表现，也不表示作者买在起点或卖在最高点。公开看多不等于已核验买入。</p>
  </section>`;
}
function phone(design) {
  const d = STORY_DATA[caseIndex];
  return `<article class="design-column ${design.id === activeDesign ? 'active' : ''}" data-column="${design.id}">
    <div class="design-label"><strong>${design.id.toUpperCase()} · ${design.name}</strong><span>${design.note}</span></div>
    <div class="phone" data-phone="${design.id}">
      <div class="statusbar" aria-hidden="true">9:41<span>${icon('signal')}${icon('wifi')}${icon('battery-full')}</span></div>
      <div class="home-view">
        <header class="app-header"><h2>今日</h2><span aria-label="通知">${icon('bell')}</span></header>
        <section aria-label="发现聪明投资者">
          <div class="section-title"><h3>发现聪明投资者 ${icon('chevron-right')}</h3><small>Top 25%</small></div>
          <div class="portrait-pool">${portraits()}</div>
          <div class="focus-card">${authorLine(d)}
            ${storyCard(d, design.id)}
          </div>
          <div class="education-entry"><span class="tiny-faces">${images()}</span><span>1000 多位投资者，谁值得追踪？</span>${icon('chevron-right')}</div>
        </section>
        <section class="market-section"><h3>他们怎么看市场</h3>
          <div class="scene-tabs" role="tablist" aria-label="市场视图">${['持仓与追踪', '市场情况', '聪明动态'].map((title, i) => `<button role="tab" aria-selected="${i === 0}" aria-controls="context-${design.id}" data-scene="${i}">${title}</button>`).join('')}</div>
          <div class="context-content" id="context-${design.id}" role="tabpanel">${contextContent(d)}</div>
        </section>
      </div>
      <div class="bottom-nav" aria-hidden="true"><span>${icon('house')}</span><span>${icon('newspaper')}</span><span>${icon('search')}</span><span>${icon('circle-user-round')}</span></div>
      <div class="home-indicator" aria-hidden="true"></div>
      ${detail(d, design.id)}
    </div>
  </article>`;
}
function render() {
  stage.innerHTML = designs.map(phone).join('');
  caseSelect.value = String(caseIndex);
  icons();
  requestAnimationFrame(drawCharts);
}
function selectDesign(id) {
  activeDesign = id;
  document.querySelectorAll('[data-design]').forEach(el => el.setAttribute('aria-pressed', String(el.dataset.design === id)));
  document.querySelectorAll('[data-column]').forEach(el => el.classList.toggle('active', el.dataset.column === id));
  requestAnimationFrame(drawCharts);
}
async function toggleDetail(phoneElement, open, records = []) {
  if (transitionBusy) return;
  transitionBusy = true;
  const panel = phoneElement.querySelector('.detail-page');
  const update = () => {
    phoneElement.querySelector('.home-view').hidden = open;
    phoneElement.querySelector('.bottom-nav').hidden = open;
    panel.hidden = !open;
    if (open) panel.scrollTop = 0;
    panel.querySelectorAll('[data-record]').forEach(el => el.classList.toggle('selected-record', records.includes(el.dataset.record)));
    drawCharts();
  };
  try {
    if (document.startViewTransition && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      await document.startViewTransition(update).finished;
    } else update();
  } finally {
    transitionBusy = false;
    if (open && records.length) {
      const selected = [...panel.querySelectorAll('[data-record]')].find(el => records.includes(el.dataset.record));
      if (selected) {
        panel.scrollTop += selected.getBoundingClientRect().top - panel.getBoundingClientRect().top - 70;
        selected.querySelector('a').focus({ preventScroll: true });
      }
    } else phoneElement.querySelector(open ? '[data-back]' : '[data-open]').focus({ preventScroll: true });
  }
}
function drawChart(canvas, d) {
  if (!canvas.getClientRects().length) return;
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  if (!width || !height) return;
  const scale = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  const ctx = canvas.getContext('2d');
  ctx.scale(scale, scale);
  const styles = getComputedStyle(document.documentElement);
  const brand = styles.getPropertyValue('--brand').trim();
  const muted = styles.getPropertyValue('--muted').trim();
  const points = [[d.referenceDay, d.reference], ...d.candles];
  const timestamps = points.map(p => Date.parse(p[0] + 'T12:00:00Z'));
  const start = timestamps[0];
  const end = timestamps.at(-1);
  const marked = canvas.hasAttribute('data-call-markers');
  const min = Math.min(...points.map(p => p[1]), d.reference, ...d.calls.map(c => c.price));
  const max = Math.max(...points.map(p => p[1]), d.peak, ...d.calls.map(c => c.price));
  const inset = marked ? 18 : 7;
  const y = value => height - 18 - (value - min) / Math.max(max - min, 1) * (height - 46);
  const x = timestamp => inset + (timestamp - start) / Math.max(end - start, 1) * (width - inset * 2);
  ctx.strokeStyle = styles.getPropertyValue('--line').trim();
  ctx.lineWidth = 1;
  ctx.beginPath(); ctx.moveTo(inset, y(d.reference)); ctx.lineTo(width - inset, y(d.reference)); ctx.stroke();
  ctx.strokeStyle = brand;
  ctx.lineWidth = 1.7;
  ctx.lineJoin = 'round';
  ctx.beginPath();
  points.forEach((p, i) => i ? ctx.lineTo(x(timestamps[i]), y(p[1])) : ctx.moveTo(x(timestamps[i]), y(p[1])));
  ctx.stroke();
  const peakX = x(Date.parse(d.peakDay + 'T12:00:00Z'));
  const peakY = y(d.peak);
  const peakClose = points.find(p => p[0] === d.peakDay)?.[1];
  if (peakClose != null) {
    ctx.globalAlpha = .5;
    ctx.beginPath(); ctx.moveTo(peakX, y(peakClose)); ctx.lineTo(peakX, peakY); ctx.stroke();
    ctx.globalAlpha = 1;
  }
  ctx.fillStyle = styles.getPropertyValue('--gold').trim();
  ctx.beginPath(); ctx.moveTo(peakX, peakY - 4); ctx.lineTo(peakX + 4, peakY); ctx.lineTo(peakX, peakY + 4); ctx.lineTo(peakX - 4, peakY); ctx.closePath(); ctx.fill();
  const text = `最高 ${money(d.peak)}`;
  ctx.font = '10px -apple-system, BlinkMacSystemFont, sans-serif';
  ctx.fillStyle = muted;
  const labelWidth = ctx.measureText(text).width;
  ctx.fillText(text, Math.max(5, Math.min(peakX - labelWidth / 2, width - labelWidth - 5)), peakY - 8);
  if (marked) drawCallNodes(canvas, d, x, y);
  canvas.dataset.rendered = 'true';
}
function drawCallNodes(canvas, d, x, y) {
  const bullish = d.calls.filter(call => call.direction === 'bullish');
  const selected = bullish.slice(0, 3);
  const nodes = selected.map(call => ({ call, x: x(Date.parse(call.day + 'T12:00:00Z')), y: y(call.price) }));
  const parents = nodes.map((_, i) => i);
  const root = i => parents[i] === i ? i : (parents[i] = root(parents[i]));
  // Cluster overlapping hit targets, anchoring each cluster to a real event position.
  for (let i = 0; i < nodes.length; i++) {
    for (let j = 0; j < i; j++) {
      if (Math.abs(nodes[i].x - nodes[j].x) < 35 && Math.abs(nodes[i].y - nodes[j].y) < 35) parents[root(i)] = root(j);
    }
  }
  const groups = new Map();
  nodes.forEach((node, i) => { const key = root(i); groups.set(key, [...(groups.get(key) ?? []), node]); });
  canvas.parentElement.querySelector('.marker-layer').innerHTML = [...groups.values()].map(group => {
    const anchor = group[0];
    const bull = group.filter(n => n.call.direction === 'bullish').length;
    const bear = group.length - bull;
    const mixed = bull > 0 && bear > 0;
    const tone = mixed ? 'mixed' : bull ? 'bullish' : 'bearish';
    const dates = group.length > 1 ? `${dotted(anchor.call.day)} 至 ${dotted(group.at(-1).call.day)}` : dotted(anchor.call.day);
    const description = `${dates}，${bull ? `${bull} 次看多` : ''}${bull && bear ? '，' : ''}${bear ? `${bear} 次看空` : ''}`;
    return `<button class="call-node ${tone} ${group.length > 1 ? 'cluster' : ''}" data-nodes="${group.map(n => n.call.id).join(',')}" style="left:${anchor.x}px;top:${anchor.y}px" aria-label="${description}" title="${description}"><span>${group.length > 1 ? group.length : ''}</span></button>`;
  }).join('');
}
function drawCharts() {
  document.querySelectorAll('[data-price-chart]').forEach(canvas => drawChart(canvas, STORY_DATA[caseIndex]));
}
caseSelect.innerHTML = STORY_DATA.map((d, i) => `<option value="${i}">${escapeHTML(d.name)} · ${d.ticker}</option>`).join('');
caseSelect.addEventListener('change', () => { caseIndex = Number(caseSelect.value); render(); });
document.querySelectorAll('[data-design]').forEach(button => button.addEventListener('click', () => selectDesign(button.dataset.design)));
document.querySelector('#layout-toggle').addEventListener('click', event => {
  const single = stage.dataset.layout !== 'single';
  stage.dataset.layout = single ? 'single' : 'compare';
  event.currentTarget.innerHTML = icon(single ? 'columns-3' : 'smartphone');
  event.currentTarget.title = single ? '同时比较三种方案' : '切换单屏预览';
  event.currentTarget.setAttribute('aria-label', event.currentTarget.title);
  icons(); requestAnimationFrame(drawCharts);
});
document.querySelector('#theme-toggle').addEventListener('click', event => {
  const light = document.documentElement.dataset.theme !== 'light';
  document.documentElement.dataset.theme = light ? 'light' : 'dark';
  event.currentTarget.innerHTML = icon(light ? 'moon' : 'sun');
  icons(); drawCharts();
});
stage.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button || transitionBusy) return;
  if (button.hasAttribute('data-case')) { caseIndex = Number(button.dataset.case); render(); }
  if (button.hasAttribute('data-open')) toggleDetail(button.closest('.phone'), true);
  if (button.hasAttribute('data-nodes')) {
    const phoneElement = button.closest('.phone');
    const ids = button.dataset.nodes.split(',');
    if (phoneElement.querySelector('.detail-page').hidden) toggleDetail(phoneElement, true, ids);
    else {
      const panel = phoneElement.querySelector('.detail-page');
      panel.querySelectorAll('[data-record]').forEach(el => el.classList.toggle('selected-record', ids.includes(el.dataset.record)));
      const target = [...panel.querySelectorAll('[data-record]')].find(el => ids.includes(el.dataset.record));
      if (target) {
        panel.scrollTo({ top: panel.scrollTop + target.getBoundingClientRect().top - panel.getBoundingClientRect().top - 70, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
        target.querySelector('a').focus({ preventScroll: true });
      }
    }
  }
  if (button.hasAttribute('data-back')) toggleDetail(button.closest('.phone'), false);
  if (button.hasAttribute('data-follow')) {
    const d = STORY_DATA[caseIndex];
    followed.has(d.id) ? followed.delete(d.id) : followed.add(d.id);
    stage.querySelectorAll('[data-follow]').forEach(el => {
      const active = followed.has(d.id);
      el.setAttribute('aria-pressed', String(active));
      el.setAttribute('aria-label', `${active ? '取消追踪' : '追踪'} ${d.name}`);
      el.title = active ? '已追踪' : '追踪投资者';
      el.innerHTML = icon(active ? 'check' : 'plus');
    });
    icons();
  }
  if (button.hasAttribute('data-scene')) {
    const section = button.closest('.market-section');
    section.querySelectorAll('[data-scene]').forEach(el => el.setAttribute('aria-selected', String(el === button)));
    section.querySelector('.context-content').innerHTML = contextContent(STORY_DATA[caseIndex], Number(button.dataset.scene));
  }
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    const open = [...stage.querySelectorAll('.detail-page')].find(el => !el.hidden && el.getClientRects().length);
    if (open) toggleDetail(open.closest('.phone'), false);
  }
});
let resizeFrame;
window.addEventListener('resize', () => { cancelAnimationFrame(resizeFrame); resizeFrame = requestAnimationFrame(drawCharts); });
render();
