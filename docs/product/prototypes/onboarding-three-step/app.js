const $ = selector => document.querySelector(selector);
const icon = name => `<i data-lucide="${name}" aria-hidden="true"></i>`;
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const money = value => '$' + Number(value).toLocaleString('en-US', {maximumFractionDigits:2});
const dotDate = value => value.slice(0,10).replaceAll('-', '.');
const story = DEMO.story;
const name = escapeHTML(story.name), ticker = escapeHTML(story.ticker);
const screen = $('#screen');
const dialog = $('#detail');
let step = 0, followed = false, notify = false, amount = '100', leverage = 1, toastTimer;
const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const refreshIcons = () => lucide.createIcons();
document.querySelectorAll('[data-brand]').forEach(img => img.src = DEMO.brand);
document.documentElement.style.setProperty('--atlas', `url("${DEMO.atlas}")`);

function heading(number, label, title, intro) {
  return `<div class="page-heading"><div class="step-label"><b>0${number} / 03</b>${label}</div><h2>${title}</h2><p class="intro">${intro}</p></div>`;
}
function author(withFollow = false) {
  return `<div class="author"><img class="avatar" src="${story.avatar}" alt="${name}"><div class="author-main"><b>${name}</b><small>X · ${escapeHTML(story.handle)}</small></div>${withFollow ? `<button class="follow" data-follow aria-pressed="${followed}">${icon(followed?'check':'plus')}${followed?'已追踪':'追踪'}</button>` : `<span class="rank rank-pill">Top ${story.percentile}%</span>`}</div>`;
}
function pool() {
  return `<div class="pool" aria-hidden="true">${Array.from({length:11},(_,i)=>`<div class="pool-column">${Array.from({length:3},(_,j)=>{const n=(i*19+j*79)%950;return `<span class="pool-face" style="background-position:${-(n%32)*37}px ${-Math.floor(n/32)*37}px"></span>`}).join('')}</div>`).join('')}</div>`;
}
function discover() {
  return `${heading(1,'发现','投资，该追踪谁？','从上千位投资者中，找到值得你关注的人。')}${pool()}${author()}
  <section class="work"><div class="work-top"><div class="ticker"><img src="${story.logo}" alt="${ticker}"><b>${ticker}</b><small>代表作</small></div><div class="performance"><strong>+${Math.round(story.peakChange)}%</strong><small>区间最高股价涨幅</small></div></div>
  <div class="chart"><canvas id="chart" role="img" aria-label="${ticker} 历史价格与最早至多三次看多节点"></canvas><div id="markers"></div></div>
  <p class="story">作者在 <strong>${money(story.reference)}</strong> 看多 <strong>${ticker}</strong>，之后再次看多。后来最高到 <strong>${money(story.peak)}</strong>。</p></section>
  <div class="rank-explainer"><span>Top ${story.percentile}%</span><p>在 X 参与排名的投资者中，<br>位于前 ${story.percentile}%。</p></div>
  <p class="footnote">榜单快照 · ${dotDate(DEMO.update.authorScoreAsOf)}。股价统计至 ${dotDate(story.endDay)}；历史高点涨幅不等于作者收益，也不代表未来表现。</p>`;
}
function tracking() {
  return `${heading(2,'追踪','他有新判断，<br>你能跟上。','追踪你认可的人，把他的更新留在首页。')}${author(true)}
  <section class="opinion"><div class="meta"><span class="bull">${ticker} · 看多</span><span>·</span><time>${dotDate(DEMO.update.publishedAt)}</time></div><h3>融资稀释带来压力，<br>仍看好 AAOI 的需求</h3><p>作者认为 AAOI 产能受限、需求清晰，同时担心增发融资造成短期压力。对融资方式有保留，但仍维持看多。</p><div class="quote"><p>“我不必支持公司的每一个决定，才能继续看多。”</p></div><button class="source" data-original>查看这条观点 ${icon('arrow-up-right')}</button></section>
  <section class="tracking"><div class="section-label"><span>我的追踪</span>${followed?`<button class="bell-button" data-notify>${icon(notify?'bell-ring':'bell-plus')}${notify?'已选择通知':'更新通知'}</button>`:''}</div>
  ${followed?`<div class="tracked-row"><img src="${story.avatar}" alt=""><div><b>${name} 的 ${ticker} 观点</b><p>已加入我的追踪 · Top ${story.percentile}%</p></div>${icon('check')}</div>`:`<p class="tracking-empty">还没有追踪的投资者</p>`}</section>
  <p class="footnote">历史观点示例。数据随发布批次更新，不是实时逐条推送。</p>`;
}
function trading() {
  return `${heading(3,'交易','认可这个判断？<br>直接交易。','从观点到交易，不用再切换另一个 App。')}
  <div class="trade-context"><img src="${story.avatar}" alt="${name}"><div><strong>${name} · ${ticker} 看多</strong><p>仍看好 AAOI 需求，留意融资压力</p></div></div>
  <div class="trade-header"><div class="ticker"><img src="${story.logo}" alt="${ticker}"><div><b>${ticker}</b><small>${escapeHTML(story.company)}</small></div></div><span class="instrument">永续合约 · 多仓</span></div>
  <div class="amount"><label for="amount">投入保证金</label><div class="amount-entry"><span>$</span><input id="amount" aria-label="投入保证金金额" inputmode="decimal" value="${amount}" maxlength="7" autocomplete="off"></div></div>
  <div class="quick">${[50,100,200,500].map(n=>`<button data-amount="${n}" class="${Number(amount)===n?'selected':''}">$${n}</button>`).join('')}</div>
  <div class="order-data"><span>杠杆</span><div class="segment" aria-label="杠杆">${[1,2,3].map(n=>`<button data-leverage="${n}" aria-pressed="${leverage===n}">${n}×</button>`).join('')}</div></div>
  <div class="order-data"><span>名义仓位</span><strong id="notional">${money(Number(amount||0)*leverage)}</strong></div>
  <button class="preview-order" data-preview ${Number(amount)>0?'':'disabled'}>${icon('scan-line')}查看订单预览</button>
  <p class="footnote">仅教学预览，不会下单。永续合约不是股票现货，存在杠杆和强平风险；实际费用及可用余额以交易时为准。</p>`;
}
function finished() {
  return `<section class="finish"><div class="finish-icon">${icon('check')}</div><h2>从这里开始，<br>建立你的判断。</h2><p class="intro">发现值得关注的人。<br>跟上他们，再做自己的决定。</p>${author(true)}<div class="finish-row"><span>我的追踪</span><b>${followed?'1 位投资者':'尚未选择'}</b></div><div class="finish-row"><span>已看过的代表作</span><b>${ticker}</b></div><button class="text-button" data-profile>${icon('user-round')}查看首次资料页</button><p class="footnote">演示已结束。此 HTML 不创建真实账户、不同步追踪，也不发送交易或通知请求。</p></section>`;
}
function render() {
  screen.innerHTML = [discover,tracking,trading,finished][step]();
  screen.scrollTop=0;
  screen.classList.remove('page-enter');
  if (!document.startViewTransition || reduced()) {void screen.offsetWidth; screen.classList.add('page-enter');}
  document.querySelectorAll('[data-step]').forEach(button=>{button.classList.toggle('active',Number(button.dataset.step)===step); button.setAttribute('aria-current', Number(button.dataset.step)===step?'step':'false');});
  $('.progress').innerHTML = step<3 ? [0,1,2].map(n=>`<button data-step="${n}" class="${n===step?'active':''}" aria-label="第 ${n+1} 页" aria-current="${n===step?'step':'false'}"></button>`).join(''):'';
  $('#next').innerHTML = `<span>${['看看他的新观点','看看如何交易','进入 bSmart','重新体验'][step]}</span>${icon(step===3?'rotate-ccw':'arrow-right')}`;
  $('.skip').hidden=step===3;
  refreshIcons();
  if(step===0) drawChart();
}
function go(next) {
  if(dialog.open)dialog.close();
  const change=()=>{step=next;render();screen.focus({preventScroll:true})};
  if(document.startViewTransition&&!reduced())document.startViewTransition(change);else change();
}
function showDetail(title,body) {
  $('#detail-content').innerHTML=`<div class="dialog-top"><h3>${title}</h3><button class="icon-button" data-close aria-label="关闭" title="关闭">${icon('x')}</button></div>${body}`;
  refreshIcons();if(!dialog.open)dialog.showModal();
}
function toast(message) {clearTimeout(toastTimer);$('#toast').textContent=message;$('#toast').classList.add('show');toastTimer=setTimeout(()=>$('#toast').classList.remove('show'),2600)}
function drawChart() {
  const canvas=$('#chart');if(!canvas)return;
  const bounds=canvas.getBoundingClientRect(),w=bounds.width,h=bounds.height,dpr=devicePixelRatio||1;
  canvas.width=w*dpr;canvas.height=h*dpr;
  const c=canvas.getContext('2d');c.scale(dpr,dpr);
  const theme=getComputedStyle(document.documentElement),color=name=>theme.getPropertyValue(name).trim();
  const points=[[story.referenceDay,story.reference],...story.candles];
  const start=Date.parse(points[0][0]),end=Date.parse(points.at(-1)[0]);
  const low=Math.min(...points.map(p=>p[1]),...story.calls.map(call=>call.price))*.9;
  const high=Math.max(story.peak,...points.map(p=>p[1]));
  const x=day=>16+(Date.parse(day)-start)/(end-start)*(w-32),y=value=>h-32-(value-low)/(high-low)*(h-57);
  c.lineWidth=1;c.strokeStyle=color('--line');[.2,.5,.8].map(r=>low+(high-low)*r).forEach(v=>{c.beginPath();c.moveTo(0,y(v));c.lineTo(w,y(v));c.stroke()});
  c.strokeStyle=color('--mint');c.lineWidth=2;c.lineJoin='round';c.beginPath();points.forEach(([day,price],i)=>i?c.lineTo(x(day),y(price)):c.moveTo(x(day),y(price)));c.stroke();
  c.fillStyle=color('--text');c.font='600 12px -apple-system, sans-serif';c.textAlign='center';c.fillText(money(story.peak),x(story.peakDay),15);
  c.beginPath();c.arc(x(story.peakDay),y(story.peak),3,0,Math.PI*2);c.fill();
  c.font='11px -apple-system, sans-serif';c.fillStyle=color('--muted');c.textAlign='left';c.fillText(dotDate(story.referenceDay),0,h-3);c.textAlign='right';c.fillText(dotDate(story.endDay),w,h-3);
  const calls=story.calls.filter(call=>call.direction==='bullish').slice(0,3);
  $('#markers').innerHTML=calls.map((call,i)=>`<button class="marker" data-call="${i}" style="left:${x(call.day)}px;top:${y(call.price)}px" aria-label="${dotDate(call.day)} 看多 ${ticker}，价格 ${money(call.price)}" title="${dotDate(call.day)} · ${money(call.price)}"><img src="${story.avatar}" alt=""></button>`).join('');
  c.fillStyle=color('--text');c.textAlign='left';c.font='600 11px -apple-system, sans-serif';c.fillText(money(story.reference),Math.max(0,x(calls[0].day)-14),y(calls[0].price)-24);
}
function updateOrder() {
  $('#notional').textContent=money(Number(amount||0)*leverage);
  document.querySelectorAll('[data-amount]').forEach(b=>b.classList.toggle('selected',Number(b.dataset.amount)===Number(amount)));
  document.querySelectorAll('[data-leverage]').forEach(b=>b.setAttribute('aria-pressed',Number(b.dataset.leverage)===leverage));
  $('[data-preview]').disabled=!(Number(amount)>0);
}
function profile() {
  showDetail('你的账户',`<h2 class="dialog-title">取一个用户名</h2><div class="setup-photo"><label class="photo-control" for="photo">${icon('camera')}</label><input id="photo" type="file" accept="image/*" hidden><div><b>添加头像</b><small>可选</small></div></div><label class="profile-field" for="handle">用户名</label><div class="handle-input"><span>@</span><input id="handle" placeholder="你的用户名" autocomplete="off" autocapitalize="none" spellcheck="false" maxlength="24"></div><p class="error" id="handle-error" role="status"></p><button class="primary setup-submit" data-save-profile disabled><span>继续</span>${icon('arrow-right')}</button>`);
}
document.addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button)return;
  if(button.matches('[data-step]'))go(Number(button.dataset.step));
  else if(button.id==='next')go(step===3?0:step+1);
  else if(button.matches('[data-skip]'))go(3);
  else if(button.matches('[data-theme-toggle]')){document.documentElement.dataset.theme=document.documentElement.dataset.theme==='dark'?'light':'dark';button.innerHTML=icon(document.documentElement.dataset.theme==='dark'?'sun':'moon');refreshIcons();drawChart()}
  else if(button.matches('[data-follow]')){followed=!followed;const scroll=screen.scrollTop;render();screen.scrollTop=scroll;toast(followed?`已追踪 ${story.name}`:'已取消追踪')}
  else if(button.matches('[data-notify]'))showDetail('不错过下一次更新',`<h2 class="dialog-title">数据更新时，<br>通知你。</h2><p class="dialog-copy">通知跟随数据发布批次，不是每条发帖的即时提醒。</p><button class="primary" data-enable-notify>开启更新通知 ${icon('bell')}</button><button class="secondary" data-close>稍后</button>`);
  else if(button.matches('[data-enable-notify]')){notify=true;dialog.close();render();toast('已选择开启；演示不会申请系统权限')}
  else if(button.matches('[data-original]'))showDetail(`${name} · ${ticker}`,`<div class="meta">X · ${dotDate(DEMO.update.publishedAt)} · 历史观点</div><p class="original">${escapeHTML(DEMO.update.originalText)}</p><a class="source" href="${escapeHTML(DEMO.update.sourceURL)}" target="_blank" rel="noopener noreferrer">查看 X 原帖 ${icon('external-link')}</a>`);
  else if(button.matches('[data-call]')){const call=story.calls.filter(c=>c.direction==='bullish').slice(0,3)[Number(button.dataset.call)];showDetail('当时的判断',`<h2 class="dialog-title">${ticker} · 公开看多</h2><div class="meta">${dotDate(call.day)} · 价格 ${money(call.price)}</div><p class="original">${escapeHTML(call.originalText || '本地记录收录了这次看多节点。完整观点请查看对应原帖。')}</p><a class="source" href="${escapeHTML(call.sourceURL)}" target="_blank" rel="noopener noreferrer">查看 X 原帖 ${icon('external-link')}</a><p class="footnote">价格取观点发布前最近一个已完成交易日的收盘价，不是作者买入价。</p>`)}
  else if(button.matches('[data-amount]')){amount=button.dataset.amount;$('#amount').value=amount;updateOrder()}
  else if(button.matches('[data-leverage]')){leverage=Number(button.dataset.leverage);updateOrder()}
  else if(button.matches('[data-preview]'))showDetail('订单预览',`<h2 class="dialog-title">${ticker} · 多仓</h2><div class="order-data"><span>交易工具</span><b>永续合约</b></div><div class="order-data"><span>投入保证金</span><b>${money(amount)}</b></div><div class="order-data"><span>杠杆</span><b>${leverage}×</b></div><div class="order-data"><span>名义仓位</span><b>${money(Number(amount)*leverage)}</b></div><p class="dialog-copy" style="margin-top:22px">正式交易前会核验余额、行情及费用，并由你确认。这次仅预览，没有创建或发送订单。</p><button class="primary" style="margin-top:25px" data-close>返回观点 ${icon('arrow-left')}</button>`);
  else if(button.matches('[data-profile]'))profile();
  else if(button.matches('[data-save-profile]')){dialog.close();toast('资料页体验完成；未创建或保存真实账户')}
  else if(button.matches('[data-close]'))dialog.close();
});
document.addEventListener('input',event=>{
  if(event.target.id==='amount'){const value=event.target.value;if(/^\d{0,4}(\.\d{0,2})?$/.test(value))amount=value;else event.target.value=amount;updateOrder()}
  if(event.target.id==='handle'){const value=event.target.value.trim().toLowerCase();const valid=/^[a-z][a-z0-9_]{2,23}$/.test(value);$('[data-save-profile]').disabled=!valid;$('#handle-error').textContent=value&&!valid?'使用 3–24 位字母、数字或下划线，以字母开头。':''}
});
document.addEventListener('change',event=>{
  if(event.target.id==='photo'&&event.target.files[0]){const file=event.target.files[0];if(!file.type.startsWith('image/')||file.size>5000000){toast('请选择 5 MB 以内的图片');return}const reader=new FileReader();reader.onload=()=>{$('.photo-control').innerHTML=`<img alt="已选择的头像">`;$('.photo-control img').src=reader.result};reader.readAsDataURL(file)}
});
window.addEventListener('resize',drawChart);
render();
