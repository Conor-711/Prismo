const directions = [{ id: 'a', name: '紧凑双圆' }, { id: 'b', name: '同轴双像' }, { id: 'c', name: '头像主视觉' }];
const stage = document.querySelector('#stage');
const samplePicker = document.querySelector('#sample');
const dialog = document.querySelector('#preview-dialog');
let selected = /^[abc]$/.test(location.hash.slice(1)) ? location.hash.slice(1) : 'a';
let example = 0;
const escapeHTML = (value) => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const icon = (name) => `<i data-lucide="${name}" aria-hidden="true"></i>`;
const refreshIcons = () => lucide.createIcons();

samplePicker.innerHTML = COVER_DATA.map((data, index) => `<option value="${index}">${escapeHTML(data.shortName)} / ${escapeHTML(data.ticker)}</option>`).join('');

function render() {
  const data = COVER_DATA[example];
  const isBearish = data.direction === 'bearish';
  stage.innerHTML = directions.map(({ id, name }) => `
    <section class="concept ${selected === id ? 'chosen' : ''}" data-concept="${id}" aria-label="方案 ${id.toUpperCase()} ${name}">
      <header class="concept-heading"><h2><em>${id.toUpperCase()}</em>${name}</h2><button class="choose" data-choice="${id}" aria-pressed="${selected === id}">${icon(selected === id ? 'check' : 'plus')}<span>${selected === id ? '已选中' : '选择此方案'}</span></button></header>
      <div class="phone"><div class="screen" tabindex="0" aria-label="观点详情预览">
        <figure class="cover cover-${id}" aria-label="作者头像与标的 Logo 组合头图">
          <nav class="cover-nav" aria-label="详情操作"><button class="icon-button" data-action="back" aria-label="回到顶部" title="回到顶部">${icon('chevron-left')}</button><button class="icon-button" data-action="source" aria-label="查看来源" title="查看来源">${icon('arrow-up-right')}</button></nav>
          <div class="composition"><div class="portrait"><img src="${data.avatar}" alt="${escapeHTML(data.authorName)}的彩色头像" draggable="false"></div><div class="asset"><img src="${data.logo}" alt="${data.ticker} Logo" draggable="false"></div></div>
        </figure>
        <div class="reading">
          <div class="byline"><img class="platform" src="${data.platformImage}" alt="X"><strong title="${escapeHTML(data.authorName)}">${escapeHTML(data.shortName)}</strong><span class="rank">Top ${data.percentile}%</span></div>
          <div class="metadata"><span>${data.ticker} · ${escapeHTML(data.companyName)}</span><span>·</span><time datetime="${data.publishedAt}">${data.date}</time></div>
          <details class="traders"><summary>${icon('users-round')}<span><b>12 人</b>通过此观点完成交易</span><span class="sample-label">样例</span>${icon('chevron-down')}</summary><div class="trader-row"><span class="trader-symbol">L</span><span>Lin · 示例用户</span><span>做多</span></div><div class="trader-row"><span class="trader-symbol">K</span><span>Kai · 示例用户</span><span>做多</span></div></details>
          <div class="stance" ${isBearish ? 'style="color:var(--bear)"' : ''}><span>${icon(isBearish ? 'trending-down' : 'trending-up')}${isBearish ? '看空' : '看多'}</span>${data.horizon && data.horizon !== 'unknown' ? `<span>· ${escapeHTML(data.horizon)}</span>` : ''}</div>
          <h2 class="article-title">${escapeHTML(data.title)}</h2>
          <p class="thesis">${escapeHTML(data.summary)}</p>
          <div class="reader-tools"><button data-action="original" aria-expanded="false">查看原文</button><button class="icon-button" data-action="font" aria-label="切换正文字号" title="切换正文字号">${icon('type')}</button></div>
          <p class="original" hidden>${escapeHTML(data.originalText)}</p>
        </div>
      </div><div class="trade-dock"><button data-action="trade">${icon('arrow-down-right')}做空</button><button data-action="trade">${icon('arrow-up-right')}做多</button></div></div>
    </section>`).join('');
  applyChoice();
  document.querySelectorAll('.cover').forEach(installStretch);
  refreshIcons();
}

function applyChoice() {
  document.querySelectorAll('[data-concept]').forEach(node => node.classList.toggle('chosen', node.dataset.concept === selected));
  document.querySelectorAll('[data-choice]').forEach(button => {
    const chosen = button.dataset.choice === selected;
    button.setAttribute('aria-pressed', String(chosen));
    if (button.classList.contains('choose')) button.innerHTML = `${icon(chosen ? 'check' : 'plus')}<span>${chosen ? '已选中' : '选择此方案'}</span>`;
  });
  refreshIcons();
}

function showDialog(html) {
  document.querySelector('#dialog-content').innerHTML = html;
  dialog.showModal();
}

document.addEventListener('click', event => {
  const choice = event.target.closest('[data-choice]');
  if (choice) { selected = choice.dataset.choice; location.hash = selected; applyChoice(); return; }
  const button = event.target.closest('[data-action]');
  if (!button) return;
  const screen = button.closest('.phone').querySelector('.screen');
  const data = COVER_DATA[example];
  switch (button.dataset.action) {
    case 'back': screen.scrollTo({ top: 0, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' }); break;
    case 'source': showDialog(`<h2>${escapeHTML(data.authorName)}</h2><p>${data.date} · ${data.ticker}</p><p><a href="${data.sourceURL}" target="_blank" rel="noopener noreferrer">查看 X 原帖</a></p>`); break;
    case 'trade': showDialog('<h2>交易预览</h2><p>此文件仅用于选择头图设计，不连接钱包，也不会提交任何交易。</p>'); break;
    case 'font': {
      const body = screen.querySelector('.thesis');
      const large = body.style.fontSize !== '18px';
      body.style.fontSize = large ? '18px' : '';
      button.setAttribute('aria-pressed', String(large)); break;
    }
    case 'original': {
      const body = screen.querySelector('.original');
      body.hidden = !body.hidden; button.textContent = body.hidden ? '查看原文' : '收起原文';
      button.setAttribute('aria-expanded', String(!body.hidden)); break;
    }
  }
});
document.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
samplePicker.addEventListener('change', () => { example = Number(samplePicker.value); render(); });
document.querySelector('#theme').addEventListener('click', event => {
  const light = document.documentElement.dataset.theme !== 'light';
  document.documentElement.dataset.theme = light ? 'light' : 'dark';
  const button = event.currentTarget;
  button.innerHTML = icon(light ? 'moon' : 'sun');
  button.title = button.ariaLabel = light ? '切换为黑夜模式' : '切换为白天模式';
  refreshIcons();
});
['compare', 'single'].forEach(mode => document.getElementById(mode).addEventListener('click', () => {
  stage.dataset.mode = mode;
  ['compare', 'single'].forEach(id => {
    document.getElementById(id).classList.toggle('active', id === mode);
    document.getElementById(id).setAttribute('aria-pressed', String(id === mode));
  });
}));
window.addEventListener('hashchange', () => { if (/^[abc]$/.test(location.hash.slice(1))) { selected = location.hash.slice(1); applyChoice(); } });

function installStretch(cover) {
  const scroll = cover.closest('.screen');
  let drag = null;
  cover.addEventListener('pointerdown', event => {
    if (event.target.closest('button') || event.button !== 0) return;
    drag = { y: event.clientY, top: scroll.scrollTop };
    cover.setPointerCapture(event.pointerId);
    cover.classList.add('dragging');
  });
  cover.addEventListener('pointermove', event => {
    if (!drag) return;
    const delta = event.clientY - drag.y;
    const pull = drag.top === 0 && delta > 0 ? Math.min(110, delta * 0.5) : 0;
    cover.style.setProperty('--pull', `${pull}px`);
    cover.style.setProperty('--zoom', String(1 + pull / 600));
    if (!pull) scroll.scrollTop = Math.max(0, drag.top - delta);
  });
  const release = () => { drag = null; cover.classList.remove('dragging'); cover.style.setProperty('--pull', '0px'); cover.style.setProperty('--zoom', '1'); };
  ['pointerup', 'pointercancel', 'lostpointercapture'].forEach(name => cover.addEventListener(name, release));
}
render();
