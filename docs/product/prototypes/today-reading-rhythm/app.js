(() => {
  'use strict';
  const root = '../../../../';
  const assets = `${root}ios/BSmart/Assets.xcassets/`;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon = name => `<i data-lucide="${name}" aria-hidden="true"></i>`;
  const updates = [...window.PROTOTYPE_UPDATES].sort((a,b) => b.publishedAt.localeCompare(a.publishedAt));
  const money = {id:'money-ivan', ticker:'NVDA', authorId:'ivan', authorName:'Ivan', money:true, authorAvatarURL:`${assets}SmartMoneyBorderCollieBrown.imageset/SmartMoneyBorderCollieBrown.png`, publishedAt:'2026-08-14T07:56:37Z', activityTitleZH:'减少 NVDA 多仓，持仓敞口从 $115.3K 降至 $97.0K。', sourceURL:'https://hyperdash.com/trader/0x1b7ca89aa121890b8572d326e363185cf4780c6a'};
  const all = [...updates, money];
  const byID = new Map(all.map(x => [x.id,x]));
  const tracked = new Set(['1707559719215489024','ivan']);
  const labels = ['持仓与追踪','市场情况','聪明动态'];
  const notes = ['标的清单 / 与我有关','卡片 + 条目 / 发现机会','作者时间线 / 看人行动'];
  const date = x => new Intl.DateTimeFormat('zh-CN',{month:'numeric',day:'numeric',timeZone:'Asia/Shanghai'}).format(new Date(x));
  const rank = x => x.money ? 'Smart Money' : `Top ${Math.ceil(x.platformPercentile*100)}%`;
  const logo = t => `<img class="logo" src="${assets}Ticker_${t}.imageset/${t}.${['MU','META'].includes(t)?'svg':'png'}" alt="${t}">`;
  const avatar = x => `<span class="avatar" data-initial="${esc(x.authorName[0])}"><img src="${esc(x.authorAvatarURL)}" referrerpolicy="no-referrer" alt="${esc(x.authorName)}"></span>`;
  const platform = x => x.money ? icon('waves') : `<img class="platform" src="${root}web/public/platform/x.png" alt="X">`;
  const source = x => `<div class="source">${avatar(x)}${platform(x)}<span class="name">${esc(x.authorName)}</span>${!x.money?`<span class="rank">${rank(x)}</span>`:''}<time datetime="${x.publishedAt}">${date(x.publishedAt)}</time></div>`;
  const entry = x => `<button class="brief" data-evidence="${x.id}"><p>${esc(x.activityTitleZH)}</p>${source(x)}</button>`;
  const heading = (title, right='') => `<div class="section-title"><h2>${title}</h2><span>${right}</span></div>`;
  const filters = selected => `<div class="source-filters" aria-label="来源筛选">${[['all','全部'],['account','Smart Account'],['money','Smart Money']].map(([key,label])=>`<button data-filter="${key}" class="${selected===key?'active':''}" aria-pressed="${selected===key}">${label}</button>`).join('')}</div>`;
  const matches = (x,filter) => filter==='all'||(filter==='money'?x.money:!x.money);
  const track = x => `<button class="track" data-track="${x.authorId}" aria-pressed="${tracked.has(x.authorId)}" aria-label="${tracked.has(x.authorId)?'取消追踪':'追踪'} ${esc(x.authorName)}" title="${tracked.has(x.authorId)?'取消追踪':'追踪'}">${icon(tracked.has(x.authorId)?'check':'plus')}</button>`;

  function portfolio(filter) {
    let html = heading('持仓相关','3 只持仓')+filters(filter);
    for(const [ticker,percentage] of [['NVDA',32],['MSTR',18],['MU',12]]){
      const list = all.filter(x=>x.ticker===ticker&&matches(x,filter)).slice(0,2);
      html += `<section class="holding"><div class="holding-heading"><span class="symbol">${logo(ticker)}${ticker}</span><span class="exposure"><span class="bar"><i style="width:${percentage}%"></i></span>仓位 ${percentage}%</span></div>${list.length?list.map(entry).join(''):'<p class="empty">暂无相关动态</p>'}</section>`;
    }
    html += heading('追踪动态',`${tracked.size} 个账户`);
    const rows = all.filter(x=>tracked.has(x.authorId)&&matches(x,filter)).slice(0,4);
    html += rows.length?rows.map(x=>`<article class="tracking-row">${avatar(x)}<div><h3>${esc(x.authorName)}<span>${date(x.publishedAt)}</span></h3><button data-evidence="${x.id}"><p><b>${x.ticker}</b> · ${esc(x.activityTitleZH)}</p></button></div></article>`).join(''):'<p class="empty">暂无追踪动态</p>';
    return html;
  }
  function market() {
    let html = heading('热门标的', '近 30 天');
    for(const ticker of ['NVDA','META']) {
      const list = updates.filter(x=>x.ticker===ticker);
      const item = list.find(x=>x.platformPercentile<=.25)||list[0];
      const authors = [...new Map(list.map(x=>[x.authorId,x])).values()].slice(0,3);
      html += `<button class="market-card" data-evidence="${item.id}"><div class="market-banner"><span class="symbol">${logo(ticker)}${ticker}</span><div class="trio">${authors.map(x=>`<span>${avatar(x)}<span class="rank">${rank(x)}</span></span>`).join('')}</div></div><div class="market-body"><p>${esc(item.activityTitleZH)}</p>${source(item)}</div></button>`;
    }
    html += heading('Alpha 标的',icon('sparkles'));
    for(const ticker of ['MCD','CRWD']) {
      const x = updates.find(x=>x.ticker===ticker); if(!x) continue;
      html += `<button class="alpha-row" data-evidence="${x.id}">${logo(x.ticker)}<div><div class="alpha-title"><b>${x.ticker}</b><span class="rank">${rank(x)}</span></div><p>${esc(x.activityTitleZH)}</p>${source(x)}</div></button>`;
    }
    return html;
  }
  function investors(filter) {
    let html = heading('聪明动态',icon('audio-lines'))+filters(filter);
    const actors = [...new Map(all.filter(x=>matches(x,filter)).map(x=>[x.authorId,x])).keys()].slice(0,4);
    if(!actors.length) return html+'<p class="empty">暂无动态</p>';
    for(const id of actors){
      const items = all.filter(x=>x.authorId===id).slice(0,3), x=items[0];
      html += `<div class="day">${date(x.publishedAt)}</div><article class="investor"><div class="actor-head">${avatar(x)}<div><h3>${esc(x.authorName)}</h3><div class="actor-meta">${platform(x)}${x.money?'Smart Money':'Smart Account'} <span class="rank">${x.money?'':rank(x)}</span></div></div>${track(x)}</div>${items.map(item=>`<button class="thread-entry" data-evidence="${item.id}"><div class="entry-meta">${logo(item.ticker)}<b>${item.ticker}</b><time>${date(item.publishedAt)}</time></div><p>${esc(item.activityTitleZH)}</p></button>`).join('')}</article>`;
    }
    return html;
  }
  class Preview {
    constructor(index){
      this.tab=index;this.filter='all';this.ticker='NVDA';this.positions=[0,0,0];
      this.element=document.createElement('section');this.element.className='preview';
      this.element.innerHTML=`<div class="direction"><em>0${index+1}</em><b>${labels[index]}</b><span>${notes[index].split(' / ')[0]}</span></div><div class="phone"><div class="scroller"><header class="app-head"><strong>今日</strong><span>${icon('settings-2')}</span></header><div class="chart-head"></div><div class="chart"><canvas aria-label="布局示意价格图"></canvas>${avatar(updates.find(x=>x.ticker==='NVDA'))}${avatar(money)}</div><div class="chart-date"><span>8/11</span><span>8/20</span><span>8/29</span><span>9/7</span></div><div class="ticker-rail">${['NVDA','MSTR','MU'].map(t=>`<button data-ticker="${t}" class="ticker-chip ${t==='NVDA'?'active':''}">${logo(t)}${t}</button>`).join('')}</div><div class="subtabs" role="tablist"></div><div class="content" role="tabpanel"></div></div><nav class="bottom-nav" aria-label="主导航外观预览">${['house','chart-pie','activity','sparkles'].map((i,n)=>`<span title="${['今日','持仓','Smart','Mr Collie'][n]}">${icon(i)}</span>`).join('')}</nav><section class="detail" hidden></section></div>`;
      document.querySelector('#stage').append(this.element);
      this.scroll=this.element.querySelector('.scroller');this.render();this.draw();
      this.element.addEventListener('click',event=>{
        const b=event.target.closest('button');if(!b)return;
        if(b.dataset.tab!==undefined)this.select(Number(b.dataset.tab));
        if(b.dataset.filter){this.filter=b.dataset.filter;this.render();}
        if(b.dataset.ticker){this.ticker=b.dataset.ticker;this.element.querySelectorAll('[data-ticker]').forEach(x=>x.classList.toggle('active',x===b));this.draw();}
        if(b.dataset.evidence)this.detail(byID.get(b.dataset.evidence));
        if(b.hasAttribute('data-back')){this.element.querySelector('.detail').hidden=true;this.lastFocus?.focus({preventScroll:true});}
        if(b.dataset.track){const id=b.dataset.track;tracked.has(id)?tracked.delete(id):tracked.add(id);previews.forEach(p=>p.render());}
      });
      this.scroll.addEventListener('touchstart',e=>{this.touch=[e.touches[0].clientX,e.touches[0].clientY];},{passive:true});
      this.scroll.addEventListener('touchend',e=>{if(!this.touch)return;const dx=e.changedTouches[0].clientX-this.touch[0],dy=e.changedTouches[0].clientY-this.touch[1];if(Math.abs(dx)>65&&Math.abs(dx)>Math.abs(dy)*1.5)this.select(Math.max(0,Math.min(2,this.tab+(dx<0?1:-1))));this.touch=null;},{passive:true});
      this.element.addEventListener('keydown',e=>{if(e.key==='Escape')this.element.querySelector('[data-back]')?.click();if(e.target.closest('[role=tablist]')&&['ArrowRight','ArrowLeft'].includes(e.key)){e.preventDefault();this.select((this.tab+(e.key==='ArrowRight'?1:2))%3);this.element.querySelector(`[data-tab="${this.tab}"]`).focus();}});
      new ResizeObserver(()=>this.draw()).observe(this.element);
    }
    select(tab){if(tab===this.tab)return;this.positions[this.tab]=this.scroll.scrollTop;this.tab=tab;this.filter='all';this.render();this.scroll.scrollTop=this.positions[tab];}
    render(){
      this.element.querySelector('.subtabs').innerHTML=labels.map((l,i)=>`<button role="tab" data-tab="${i}" aria-selected="${this.tab===i}" tabindex="${this.tab===i?0:-1}">${l}</button>`).join('');
      this.element.querySelector('.content').innerHTML=this.tab===0?portfolio(this.filter):this.tab===1?market():investors(this.filter);
      this.element.querySelector('.content').setAttribute('aria-label',labels[this.tab]);
      window.lucide?.createIcons();
    }
    draw(){
      this.element.querySelector('.chart-head').innerHTML=`<span class="symbol">${logo(this.ticker)}${this.ticker}</span><small>1 月 · 行情示意</small>`;
      const canvas=this.element.querySelector('canvas'),r=canvas.getBoundingClientRect();if(!r.width)return;
      canvas.width=r.width*2;canvas.height=r.height*2;const c=canvas.getContext('2d');c.scale(2,2);
      const style=getComputedStyle(document.body);c.strokeStyle=style.getPropertyValue('--line');c.lineWidth=1;
      for(let i=1;i<4;i++){c.beginPath();c.moveTo(0,r.height*i/4);c.lineTo(r.width,r.height*i/4);c.stroke();}
      const values=[64,69,81,76,84,58,65,45,51,37,43,25,32,19,29,24,45,36,52,47,57,43,60,52];
      const step=r.width/values.length;
      values.forEach((v,i)=>{const previous=values[Math.max(0,i-1)],x=step*(i+.5),y=10+v*.92;
        c.strokeStyle=c.fillStyle=style.getPropertyValue(v<previous?'--mint':'--red');c.beginPath();c.moveTo(x,y-8);c.lineTo(x,y+10);c.stroke();c.fillRect(x-2,y-3,4,Math.max(2,Math.min(9,Math.abs(v-previous)/2)));});
    }
    detail(x){
      this.lastFocus=document.activeElement;const el=this.element.querySelector('.detail');
      el.innerHTML=`<div class="detail-head"><button data-back class="icon-button" aria-label="返回">${icon('arrow-left')}</button><b>${x.money?'操作详情':'观点详情'}</b></div>${source(x)}<h2>${logo(x.ticker)} ${x.ticker}</h2><p>${esc(x.activityTitleZH)}</p>${x.thesis?`<p>${esc(x.thesis)}</p>`:''}<a href="${esc(x.sourceURL)}" target="_blank" rel="noopener">查看原始来源 ${icon('arrow-up-right')}</a>`;
      el.hidden=false;el.scrollTop=0;window.lucide?.createIcons();el.querySelector('button').focus({preventScroll:true});
    }
  }
  const previews=[];[0,1,2].forEach(i=>previews.push(new Preview(i)));
  document.querySelector('#theme').onclick=()=>{document.body.classList.toggle('light');previews.forEach(p=>p.draw());};
  document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>{document.querySelector('#stage').classList.toggle('single',b.dataset.view==='single');document.querySelectorAll('[data-view]').forEach(x=>x.setAttribute('aria-pressed',x===b));});
  document.addEventListener('error',event=>{const img=event.target;if(img instanceof HTMLImageElement&&img.parentElement.classList.contains('avatar'))img.parentElement.textContent=img.parentElement.dataset.initial;},true);
})();
