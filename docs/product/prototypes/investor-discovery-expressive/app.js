(() => {
  'use strict';
  const people = window.DISCOVERY_PEOPLE;
  const evidence = window.DISCOVERY_EVIDENCE;
  const byID = new Map(people.map(p => [p.id, p]));
  const storageKey = 'bsmart.prototype.expressive.following.v1';
  const $ = selector => document.querySelector(selector);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const icon = name => `<i data-lucide="${name}"></i>`;
  const sectors = { 'Semiconductors': ['半导体', 'cpu'], 'AI infrastructure': ['AI 基础设施', 'network'], 'Software': ['软件', 'braces'], 'Crypto-linked equities': ['加密关联股', 'bitcoin'], 'Cross-sector equities': ['跨行业', 'compass'], 'Consumer': ['消费', 'shopping-bag'], 'Fintech': ['金融科技', 'landmark'] };
  const sectorLabel = key => sectors[key]?.[0] || key;
  const styleLabel = key => ({ 'Technical': '技术分析', 'Fundamental': '基本面', 'Flow Momentum': '资金动量', 'Event Driven': '事件驱动', 'Unknown': '风格待识别' }[key] || key);
  const horizonLabel = key => ({ 'Medium term': '中线', 'Short term': '短线', 'Long term': '长线' }[key] || '周期未标明');
  let saved = [];
  try { const parsed = JSON.parse(localStorage.getItem(storageKey) || '[]'); if (Array.isArray(parsed)) saved = parsed.filter(id => byID.has(id)); } catch {}
  const state = { mode: 'pool', sector: '', selected: people[0].id, page: 0, followed: new Set(saved), feedFollowed: false, direction: '', opinionIndex: 0, shareKind: 'person', shareTheme: 'mint', sharePage: 0, sharePersonID: null, shareOpinion: null, modal: null, query: '', profileIDs: [], profileID: null };
  const sharePanel = $('#share-panel');
  const shareStudio = $('.share-studio');
  let toastTimer;
  let restoreFocus;
  const filtered = () => people.filter(p => !state.sector || p.sector === state.sector);
  const selected = () => byID.get(state.selected);
  const followed = () => [...state.followed].map(id => byID.get(id)).filter(Boolean);
  const rank = p => `Top ${(p.percentile * 100).toFixed(1)}%`;
  const date = value => value.slice(5, 10).replace('-', '.');
  const opinions = (list = filtered()) => list.flatMap(p => p.opinions.map((o, index) => ({ ...o, author: p, index }))).sort((a, b) => b.at.localeCompare(a.at));
  const latest = p => opinions([p])[0];
  const avatar = p => p.avatar ? `<img src="${p.avatar}" alt="${esc(p.name)}" draggable="false">` : `<span class="avatar-fallback" aria-label="${esc(p.name)}">${esc([...p.name.replace(/^@/, '')][0])}</span>`;
  const direction = o => `<span class="direction ${esc(o.direction)}">${({ bullish: '看多', bearish: '看空' })[o.direction] || '中性'}</span>`;
  const safeURL = url => { try { const u = new URL(url); return u.protocol === 'https:' ? esc(u.href) : '#'; } catch { return '#'; } };
  function icons() { window.lucide.createIcons(); }
  function toast(text) { clearTimeout(toastTimer); $('#toast').textContent = text; $('#toast').hidden = false; toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 2600); }
  function followButton(p, compact = false) {
    const on = state.followed.has(p.id);
    return `<button data-follow="${p.id}" class="${compact ? 'icon-button' : `primary${on ? ' followed' : ''}`}" aria-pressed="${on}" aria-label="${on ? '取消追踪' : '追踪'} ${esc(p.name)}" title="${on ? '取消追踪' : '追踪'}">${icon(on ? 'check' : 'plus')}${compact ? '' : on ? '已追踪' : '追踪'}</button>`;
  }
  function specialties(p) { return `<div class="specialties"><span>${esc(sectorLabel(p.sector))}</span><span>${esc(styleLabel(p.style))}</span><span>${horizonLabel(p.horizon)}</span></div>`; }
  function focus(p) {
    return `<section class="focus"><div class="focus-heading"><div><h2>${esc(p.name)}</h2><p class="handle">${esc(p.handle)} · X · ${rank(p)}</p></div><div class="score"><strong>${p.score}</strong><span>Score</span></div></div>${specialties(p)}<div class="focus-bottom">${followButton(p)}<button class="secondary" data-profile="${p.id}">认识这位投资者 ${icon('arrow-up-right')}</button><button class="icon-button" data-share-person="${p.id}" aria-label="分享 ${esc(p.name)}" title="分享人物名片">${icon('arrow-up-from-line')}</button></div></section>`;
  }
  function empty(text, action = '') { return `<div class="empty">${icon('users-round')}<p>${text}</p>${action}</div>`; }
  function renderPool() {
    const p = selected(), list = filtered().filter(x => x.id !== p.id);
    const outer = list.slice(state.page * 14, state.page * 14 + 14);
    const slots = [[1,1],[2,1],[5,1],[6,1],[1,2],[2,2],[5,2],[6,2],[1,3],[2,3],[3,3],[4,3],[5,3],[6,3]];
    return `<div class="portrait-wall" aria-label="投资者头像池"><button class="portrait featured" data-profile="${p.id}" aria-label="了解 ${esc(p.name)}" title="${esc(p.name)} · ${rank(p)}">${avatar(p)}<span class="rank-sticker">${rank(p)}</span></button>${outer.map((a,i) => `<button class="portrait${state.followed.has(a.id) ? ' is-followed' : ''}" style="grid-column:${slots[i][0]};grid-row:${slots[i][1]}" data-select="${a.id}" title="${esc(a.name)} · Score ${a.score}" aria-label="选择 ${esc(a.name)}">${avatar(a)}</button>`).join('')}</div>${focus(p)}`;
  }
  function byline(o) { return `<div class="byline"><button class="small-avatar" data-profile="${o.author.id}" aria-label="了解 ${esc(o.author.name)}">${avatar(o.author)}</button><button class="author-name" data-profile="${o.author.id}">${esc(o.author.name)}</button><time datetime="${o.at}">${date(o.at)}</time></div>`; }
  function feedItem(o) { return `<article class="feed-item">${byline(o)}<div class="feed-head">${esc(o.ticker)} ${direction(o)}</div><button class="feed-text" data-opinion="${o.author.id}:${o.index}" aria-label="阅读 ${esc(o.author.name)} 关于 ${esc(o.ticker)} 的观点摘要">${esc(o.text)}</button></article>`; }
  function renderDeep() {
    const p = selected();
    return `<article class="deep-card"><div class="eyebrow">SMART ACCOUNT / INVESTOR PROFILE</div><div class="deep-identity"><div class="profile-photo">${avatar(p)}</div><div class="score"><strong>${p.score}</strong><span>Score</span></div></div><h2>${esc(p.name)}</h2><p class="handle">${esc(p.handle)} · X</p>${specialties(p)}<div class="deep-footer"><span class="rank-tag">${icon('award')} ${rank(p)}</span><span>${p.samples} 个已结算判断</span></div></article><div class="deep-below"><div class="profile-nav"><span>第 ${filtered().findIndex(x => x.id === p.id) + 1} / ${filtered().length} 位</span><div><button data-step="-1" aria-label="上一位投资者">${icon('arrow-left')}</button><button data-step="1" aria-label="下一位投资者">${icon('arrow-right')}</button></div></div><div class="focus-bottom">${followButton(p)}<button class="secondary" data-profile="${p.id}">查看代表判断 ${icon('arrow-up-right')}</button><button class="icon-button" data-share-person="${p.id}" aria-label="分享人物名片" title="分享人物名片">${icon('arrow-up-from-line')}</button></div><div class="subheading"><h3>最近观点</h3><span>快照内最新</span></div>${latest(p) ? feedItem(latest(p)) : empty('当前快照暂无近期观点')}</div>`;
  }
  function renderSectors() {
    return `<div class="sectors-grid">${Object.entries(sectors).map(([key, [label, symbol]]) => {
      const members = people.filter(p => p.sector === key);
      return `<button class="sector-item" data-sector="${esc(key)}"><div>${icon(symbol)}<span>${members.length} 位 ${icon('arrow-up-right')}</span></div><h3>${label}</h3><div class="sector-faces">${members.slice(0,4).map(p => `<span>${avatar(p)}</span>`).join('')}</div></button>`;
    }).join('')}</div>`;
  }
  function currentOpinions() { return opinions().filter(o => !state.direction || o.direction === state.direction); }
  function renderOpinions() {
    const list = currentOpinions(); state.opinionIndex = Math.min(state.opinionIndex, Math.max(0, list.length - 1));
    const o = list[state.opinionIndex];
    let html = `<div class="opinion-switch" aria-label="观点方向">${[['','全部'],['bullish','看多'],['bearish','看空']].map(([key,label]) => `<button data-direction="${key}" aria-pressed="${state.direction === key}">${label}</button>`).join('')}</div>`;
    if (!o) return html + empty('当前筛选范围暂无观点');
    return html + `<article class="opinion-feature ${o.direction === 'bearish' ? 'is-bearish' : ''}"><span class="eyebrow">THE VIEW / ${String(state.opinionIndex + 1).padStart(2,'0')}</span><h3>${esc(o.ticker)}</h3>${direction(o)}<p class="opinion-statement">${esc(o.text)}</p><button class="opinion-open" data-opinion="${o.author.id}:${o.index}">观点摘要 · 阅读完整依据 ${icon('arrow-up-right')}</button>${byline(o)}</article><div class="opinion-actions"><button class="secondary" data-profile="${o.author.id}">认识 ${esc(o.author.name)}</button><button class="icon-button" data-share-opinion="${o.author.id}:${o.index}" aria-label="分享此观点" title="分享观点">${icon('arrow-up-from-line')}</button><button class="icon-button" data-opinion-step="-1" ${state.opinionIndex === 0 ? 'disabled' : ''} aria-label="上一条观点">${icon('arrow-left')}</button><button class="icon-button" data-opinion-step="1" ${state.opinionIndex >= list.length - 1 ? 'disabled' : ''} aria-label="下一条观点">${icon('arrow-right')}</button></div>`;
  }
  function renderFeed() {
    const list = state.feedFollowed ? followed() : people;
    const feed = list.map(p => latest(p)).filter(Boolean).sort((a,b) => b.at.localeCompare(a.at)).slice(0, 8);
    $('#feed').innerHTML = feed.length ? feed.map(feedItem).join('') : empty(state.feedFollowed ? '已追踪作者暂无近期观点' : '暂无观点');
    $('[data-action="feed-filter"]').setAttribute('aria-pressed', String(state.feedFollowed));
    $('[data-action="feed-filter"]').title = state.feedFollowed ? '当前只看已追踪，点击查看全部' : '只看已追踪';
  }
  function renderChrome() {
    $('#follow-count').textContent = state.followed.size;
    $('#dock-count').textContent = `${state.followed.size} 位已追踪`;
    $('#dock-faces').innerHTML = followed().length ? followed().slice(0,3).map(p => `<span>${avatar(p)}</span>`).join('') : `<span>${icon('users-round')}</span>`;
    $('#pool-count').textContent = filtered().length;
    document.querySelectorAll('[data-mode]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.mode === state.mode)));
    const pages = Math.max(1, Math.ceil((filtered().length - 1) / 14));
    $('#filter-bar').innerHTML = `<button data-action="${state.sector ? 'clear-sector' : 'choose-sector'}">${state.sector ? esc(sectorLabel(state.sector)) + icon('x') : '全部赛道' + icon('chevron-down')}</button><div class="right-actions">${state.mode === 'pool' ? `<span>${state.page + 1} / ${pages}</span><button data-action="next-pool" ${pages <= 1 ? 'disabled' : ''}>换一组 ${icon('shuffle')}</button>` : '<span>X 平台 · 09.09 快照</span>'}</div>`;
  }
  function render() {
    if (!filtered().some(p => p.id === state.selected)) state.selected = filtered()[0]?.id || people[0].id;
    renderChrome();
    $('#discovery-body').innerHTML = ({ pool: renderPool, profile: renderDeep, sectors: renderSectors, opinions: renderOpinions })[state.mode]();
    renderFeed(); icons(); renderShare();
  }
  function shareModel() {
    const person = byID.get(state.sharePersonID) || selected();
    return { kind: state.shareKind, theme: state.shareTheme, page: state.sharePage, person, followed: followed(), opinion: state.shareOpinion || latest(person), sectorLabel, styleLabel };
  }
  function renderShare() {
    const max = Math.max(1, Math.ceil(state.followed.size / 6)); state.sharePage = Math.min(state.sharePage, max - 1);
    document.querySelectorAll('[data-share-kind]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.shareKind === state.shareKind)));
    document.querySelectorAll('[data-theme]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.theme === state.shareTheme)));
    $('#share-pages').innerHTML = state.shareKind === 'lineup' && max > 1 ? `<button data-share-page="-1" ${state.sharePage === 0 ? 'disabled' : ''} aria-label="上一页阵容">${icon('chevron-left')}</button>${state.sharePage + 1}/${max}<button data-share-page="1" ${state.sharePage === max - 1 ? 'disabled' : ''} aria-label="下一页阵容">${icon('chevron-right')}</button>` : '';
    const noContent = (state.shareKind === 'lineup' && !state.followed.size) || (state.shareKind === 'opinion' && !shareModel().opinion);
    $('[data-action="download"]').disabled = noContent; $('[data-action="copy"]').disabled = noContent;
    window.ExpressiveShare.draw(shareModel()); icons();
  }
  function choose(id) { if (!byID.has(id)) return; state.selected = id; state.sharePersonID = null; state.shareOpinion = null; render(); }
  function toggleFollow(id) {
    if (!byID.has(id)) return;
    if (state.followed.has(id)) state.followed.delete(id); else state.followed.add(id);
    try { localStorage.setItem(storageKey, JSON.stringify([...state.followed])); } catch { toast('追踪已更新，但浏览器未允许本地保存'); }
    const modalScroll = $('#sheet-body').scrollTop;
    render();
    if (state.modal === 'profile') renderProfile();
    if (state.modal === 'search' || state.modal === 'directory') renderDirectoryList();
    if (state.modal === 'opinion') {
      document.querySelectorAll('#sheet-body [data-follow]').forEach(button => {
        button.outerHTML = followButton(byID.get(button.dataset.follow));
      });
      icons();
    }
    $('#sheet-body').scrollTop = modalScroll;
  }
  function openSheet(title, type) {
    if (state.modal === 'share') shareStudio.insertBefore(sharePanel, $('.design-points'));
    restoreFocus = document.activeElement;
    state.modal = type; $('#sheet-title').textContent = title;
    $('.sheet').classList.toggle('share-sheet', type === 'share');
    $('#overlay').hidden = false; $('#app-scroll').inert = true; $('.lineup-dock').inert = true;
    shareStudio.inert = true; $('.review-bar').inert = true;
    $('#sheet-body').innerHTML = ''; $('#sheet-body').scrollTop = 0;
    $('.sheet>header button').focus();
  }
  function closeSheet() {
    if (state.modal === 'share') shareStudio.insertBefore(sharePanel, $('.design-points'));
    state.modal = null; $('#overlay').hidden = true; $('#app-scroll').inert = false; $('.lineup-dock').inert = false;
    shareStudio.inert = false; $('.review-bar').inert = false;
    if (restoreFocus?.isConnected) restoreFocus.focus(); else $('[data-action="search"]').focus();
  }
  function openProfile(id, ids) {
    state.profileIDs = ids || (state.modal === 'directory' ? followed().map(p => p.id) : state.modal === 'search' ? directoryPeople().map(p => p.id) : filtered().map(p => p.id));
    if (!state.profileIDs.includes(id)) state.profileIDs = [id];
    state.profileID = id; openSheet('投资者档案', 'profile'); renderProfile();
  }
  function renderProfile() {
    const p = byID.get(state.profileID), index = state.profileIDs.indexOf(p.id);
    const works = evidence.filter(e => e.authorId === p.id).sort((a,b) => a.rank - b.rank).slice(0,3);
    $('#sheet-body').innerHTML = `<div class="profile-nav"><span>当前候选 ${index + 1} / ${state.profileIDs.length}</span><div><button data-profile-step="-1" ${index === 0 ? 'disabled' : ''} aria-label="上一位档案">${icon('arrow-left')}</button><button data-profile-step="1" ${index === state.profileIDs.length - 1 ? 'disabled' : ''} aria-label="下一位档案">${icon('arrow-right')}</button></div></div><div class="profile-top"><div class="profile-photo">${avatar(p)}</div><div><h3>${esc(p.name)}</h3><p class="handle">${esc(p.handle)} · X</p></div></div>${specialties(p)}<div class="metric-row"><div><b>${p.score}</b><span>Score</span></div><div><b>${rank(p)}</b><span>X 平台排名</span></div><div><b>${p.samples}</b><span>已结算判断</span></div></div><div class="focus-bottom">${followButton(p)}<button class="secondary" data-share-person="${p.id}">${icon('arrow-up-from-line')} 分享名片</button></div><div class="subheading"><h3>代表判断</h3><span>按现有贡献排名</span></div>${works.length ? works.map(e => {
      const excess = e.settlement?.marketExcessReturnPercent;
      return `<article class="evidence-row"><div><strong>${esc(e.ticker)}</strong><span>${e.settlement?.horizon || '待结算'}</span></div><p>${esc(e.text)}</p><div><small>${e.at.slice(0,10)}</small>${Number.isFinite(excess) ? `<span>${excess >= 0 ? '+' : ''}${excess.toFixed(1)}% <small>相对标普</small></span>` : '<small>尚未结算</small>'}</div><a href="${safeURL(e.url)}" target="_blank" rel="noopener noreferrer">查看原始帖子 ${icon('arrow-up-right')}</a></article>`;
    }).join('') : empty('暂无代表判断')}<p class="evidence-note">展示判断对应标的的区间超额收益，不是作者真实账户收益，也不是积分式 Score。历史表现不保证未来结果。</p><div class="subheading"><h3>近期观点</h3><span>${p.opinions.length} 条快照记录</span></div>${opinions([p]).map(feedItem).join('') || empty('当前快照暂无近期观点')}`;
    icons();
  }
  function directoryPeople() {
    const source = state.modal === 'directory' ? followed() : filtered();
    const q = state.query.toLowerCase().trim();
    return source.filter(p => [p.name,p.handle,sectorLabel(p.sector),...p.tickers].some(s => s.toLowerCase().includes(q)));
  }
  function renderDirectoryList() {
    const list = directoryPeople();
    $('#directory-list').innerHTML = list.map(p => `<div class="directory-row"><button class="directory-person" data-profile="${p.id}"><span class="small-avatar">${avatar(p)}</span><span><b>${esc(p.name)}</b><small>${esc(sectorLabel(p.sector))} · ${rank(p)} · ${p.score}</small></span></button>${followButton(p,true)}</div>`).join('') || empty(state.query ? '没有找到匹配的投资者' : '研究阵容还是空的', '<button class="secondary" data-action="close">继续发现</button>');
    icons();
  }
  function openDirectory(type) {
    state.query = ''; openSheet(type === 'search' ? '发现投资者' : '我的研究阵容', type);
    $('#sheet-body').innerHTML = `<label class="search-field">${icon('search')}<input id="directory-search" type="search" placeholder="姓名、赛道或标的" aria-label="搜索姓名、赛道或标的"></label>${type === 'directory' ? '<button class="primary" data-action="share-lineup" style="width:100%;margin-bottom:12px">分享我的阵容</button>' : ''}<div id="directory-list"></div>`;
    renderDirectoryList(); $('#directory-search').addEventListener('input', e => { state.query = e.target.value; renderDirectoryList(); });
    if (type === 'search') $('#directory-search').focus();
  }
  function resolveOpinion(key) { const [id, i] = key.split(':'), p = byID.get(id); return p?.opinions[Number(i)] ? { ...p.opinions[Number(i)], index: Number(i), author:p } : null; }
  function openOpinion(key) {
    const o = resolveOpinion(key); if (!o) return;
    openSheet('观点依据', 'opinion');
    $('#sheet-body').innerHTML = `<article class="modal-opinion">${byline(o)}<h3>${esc(o.ticker)} ${direction(o)}</h3><span class="eyebrow">结构化观点摘要 / ${o.at.slice(0,10)}</span><p class="opinion-statement">${esc(o.text)}</p><a class="source-link" href="${safeURL(o.url)}" target="_blank" rel="noopener noreferrer">查看 X 原始帖子 ${icon('arrow-up-right')}</a><div class="focus-bottom">${followButton(o.author)}<button class="secondary" data-share-opinion="${key}">分享观点 ${icon('arrow-up-from-line')}</button></div><p class="data-note">此内容是既有管线的结构化摘要，不是原文全文。实际发布时间、条件和表述以链接中的作者原帖为准。</p></article>`;
    icons();
  }
  function openShare(kind, id, o = null) {
    if (id) { state.sharePersonID = id; state.shareOpinion = o; }
    state.shareKind = kind; state.sharePage = 0;
    if (window.matchMedia('(max-width:600px)').matches) {
      openSheet('分享', 'share'); $('#sheet-body').append(sharePanel);
    } else {
      if (state.modal) closeSheet();
      sharePanel.scrollIntoView({ block:'nearest', behavior:'auto' });
      if (kind === 'lineup' && !state.followed.size) toast('追踪投资者后即可生成你的阵容');
    }
    renderShare();
  }
  function copyText() {
    const model = shareModel(), p = model.person;
    const base = 'bSmart · X 平台数据快照 2026.09.09。历史评分不保证未来表现。';
    if (model.kind === 'lineup') return `我的研究阵容\n${model.followed.map(p => `${p.name} (${p.handle}) · Score ${p.score} · ${rank(p)} · ${sectorLabel(p.sector)}`).join('\n')}\n${base}\n个人关注，不代表合作或背书。`;
    if (model.kind === 'opinion' && model.opinion) return `${model.opinion.ticker} · ${p.name} 的观点摘要\n${model.opinion.text}\n发布于 ${model.opinion.at.slice(0,10)}\n原帖：${model.opinion.url}\n${base}`;
    return `${p.name} ${p.handle}\nScore ${p.score} · ${rank(p)} · ${p.samples} 个已结算判断\n${sectorLabel(p.sector)} · ${styleLabel(p.style)}\n${base}`;
  }
  document.addEventListener('click', async event => {
    const b = event.target.closest('button'); if (!b || b.disabled) return;
    const d = b.dataset;
    if ('mode' in d) { state.mode = d.mode; state.opinionIndex = 0; render(); }
    else if ('select' in d) choose(d.select);
    else if ('sector' in d) { state.sector = d.sector; state.mode = 'pool'; state.page = 0; state.opinionIndex = 0; render(); }
    else if ('step' in d) { const list = filtered(), i = list.findIndex(p => p.id === state.selected); choose(list[(i + Number(d.step) + list.length) % list.length].id); }
    else if ('follow' in d) { const on = !state.followed.has(d.follow); toggleFollow(d.follow); toast(on ? '已加入你的研究阵容' : '已取消追踪'); }
    else if ('profile' in d) openProfile(d.profile);
    else if ('profileStep' in d) { const i = state.profileIDs.indexOf(state.profileID) + Number(d.profileStep); if (state.profileIDs[i]) { state.profileID = state.profileIDs[i]; renderProfile(); $('#sheet-body').scrollTop = 0; } }
    else if ('opinion' in d) openOpinion(d.opinion);
    else if ('direction' in d) { state.direction = d.direction; state.opinionIndex = 0; render(); }
    else if ('opinionStep' in d) { state.opinionIndex += Number(d.opinionStep); render(); }
    else if ('sharePerson' in d) openShare('person', d.sharePerson);
    else if ('shareOpinion' in d) { const o = resolveOpinion(d.shareOpinion); if (o) openShare('opinion', o.author.id, o); }
    else if ('shareKind' in d) { state.shareKind = d.shareKind; state.sharePage = 0; renderShare(); }
    else if ('theme' in d) { state.shareTheme = d.theme; renderShare(); }
    else if ('sharePage' in d) { state.sharePage += Number(d.sharePage); renderShare(); }
    else if (d.action === 'search') openDirectory('search');
    else if (d.action === 'directory') openDirectory('directory');
    else if (d.action === 'close') closeSheet();
    else if (d.action === 'choose-sector') { state.mode = 'sectors'; render(); }
    else if (d.action === 'clear-sector') { state.sector = ''; state.page = 0; render(); }
    else if (d.action === 'next-pool') { state.page = (state.page + 1) % Math.max(1, Math.ceil((filtered().length - 1) / 14)); render(); }
    else if (d.action === 'feed-filter') { state.feedFollowed = !state.feedFollowed; renderFeed(); icons(); }
    else if (d.action === 'share-lineup') openShare('lineup');
    else if (d.action === 'download') {
      try { await window.ExpressiveShare.download(`bsmart-${state.shareKind}-${state.sharePage + 1}`); toast('分享图片已生成'); } catch { toast('图片生成失败，请重试'); }
    } else if (d.action === 'copy') {
      const text = copyText();
      try { await navigator.clipboard.writeText(text); toast('分享文案已复制'); } catch {
        openSheet('分享文案', 'copy'); $('#sheet-body').innerHTML = `<textarea class="copy-fallback" readonly aria-label="分享文案">${esc(text)}</textarea>`; $('.copy-fallback').select(); icons();
      }
    }
  });
  document.addEventListener('keydown', e => {
    if (!state.modal) return;
    if (e.key === 'Escape') closeSheet();
    if (e.key === 'Tab') {
      const nodes = [...$('.sheet').querySelectorAll('button:not(:disabled),a,input,textarea')].filter(n => n.getClientRects().length);
      const first = nodes[0], last = nodes[nodes.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); }
      if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); }
    }
  });
  window.matchMedia('(max-width:600px)').addEventListener('change', () => { if (state.modal === 'share') closeSheet(); });
  render();
})();
