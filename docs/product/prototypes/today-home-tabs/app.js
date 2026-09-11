(() => {
  "use strict";

  const ROOT = "../../../../";
  const ASSETS = `${ROOT}ios/BSmart/Assets.xcassets/`;
  const labels = ["持仓与追踪", "市场情况", "聪明动态"];
  const updates = [...window.PROTOTYPE_UPDATES].sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
  const schemes = [
    { id: "a", title: "顶部轻量标签", note: "内容优先，三个需求一眼可见。" },
    { id: "b", title: "顶部原生分段", note: "分组明确，切换状态更强。" },
    { id: "c", title: "底部单手切换", note: "靠近拇指，但多一层底部导航。" },
  ];
  const escape = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]));
  const icon = name => `<i data-lucide="${name}" aria-hidden="true"></i>`;
  const date = value => new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", timeZone: "Asia/Shanghai" }).format(new Date(value));
  const rank = actor => actor.money ? "Smart Money" : `Top ${Math.ceil(actor.platformPercentile * 100)}%`;
  const logo = ticker => {
    const extension = ["META", "MU"].includes(ticker) ? "svg" : "png";
    return `<img class="asset" src="${ASSETS}Ticker_${ticker}.imageset/${ticker}.${extension}" alt="${ticker}">`;
  };
  const avatar = actor => `<span class="avatar" data-initial="${escape(actor.authorName.slice(0, 1))}"><img src="${escape(actor.authorAvatarURL)}" alt="${escape(actor.authorName)}" referrerpolicy="no-referrer" loading="lazy"></span>`;
  const platform = actor => actor.money
    ? `<span class="platform" aria-label="Hyperliquid" title="Hyperliquid">${icon("waves")}</span>`
    : `<img class="platform" src="${ROOT}web/public/platform/x.png" alt="X">`;

  // These two movements are copied from the local Smart Money evidence snapshot, not live quotes.
  const money = [
    { id: "23ab0bd4-2c7e-5417-8dcc-f4ab8b7497da", ticker: "NVDA", authorId: "0x1b7ca89aa121890b8572d326e363185cf4780c6a", authorName: "Ivan", authorAvatarURL: `${ASSETS}SmartMoneyBorderCollieBrown.imageset/SmartMoneyBorderCollieBrown.png`, publishedAt: "2026-08-14T07:56:37+00:00", activityTitleZH: "减少 NVDA 多仓，持仓敞口从 $115.3K 降至 $97.0K。", money: true, market: "xyz:NVDA", sourceURL: "https://hyperdash.com/trader/0x1b7ca89aa121890b8572d326e363185cf4780c6a" },
    { id: "93585e37-5bda-5b62-8252-2e2f08954375", ticker: "MSTR", authorId: "0xe8d89110c52df4ca33e75e060e3c72dcbf6c8dda", authorName: "Iris", authorAvatarURL: `${ASSETS}SmartMoneyBorderCollieBowTie.imageset/SmartMoneyBorderCollieBowTie.png`, publishedAt: "2026-08-14T07:56:37+00:00", activityTitleZH: "平仓 MSTR 空仓，此前持仓敞口为 $194.9K。", money: true, market: "xyz:MSTR", sourceURL: "https://hyperdash.com/trader/0xe8d89110c52df4ca33e75e060e3c72dcbf6c8dda" },
  ];
  const allUpdates = [...updates, ...money].sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
  const actors = [...new Map(allUpdates.map(item => [item.authorId, item])).values()];
  const actorById = new Map(actors.map(actor => [actor.authorId, actor]));
  const itemById = new Map(allUpdates.map(item => [item.id, item]));
  const initialTracked = ["958217615545049090", "1707559719215489024", money[0].authorId];
  let tracked = new Set(initialTracked);
  let holdings = new Set(["NVDA", "MSTR"]);
  const read = new Set();
  let scenario = "normal";
  let light = false;
  let phones = [];

  function refreshIcons() {
    window.lucide?.createIcons();
  }

  function footer(item, showTime = true) {
    return `<div class="source-footer">${avatar(item)}${platform(item)}<div><strong>${escape(item.authorName)}</strong><small class="rank">${rank(item)}</small></div>${showTime ? `<time datetime="${item.publishedAt}">${date(item.publishedAt)}</time>` : ""}</div>`;
  }

  function entry(item, { withSource = false, reason = "" } = {}) {
    return `<button class="activity-entry ${read.has(item.id) ? "read" : ""}" data-event="${item.id}" aria-label="${escape(item.authorName)}，${item.ticker}，${date(item.publishedAt)}的动态">
      <div class="entry-top">${logo(item.ticker)}<span>${item.ticker}</span>${reason ? `<span class="reason">${reason}</span>` : ""}<time datetime="${item.publishedAt}">${date(item.publishedAt)}</time></div>
      <div class="entry-text">${escape(item.activityTitleZH)}</div>${withSource ? footer(item, false) : ""}
    </button>`;
  }

  function trackButton(actor) {
    const active = tracked.has(actor.authorId);
    return `<button class="track" data-track="${actor.authorId}" aria-pressed="${active}" aria-label="${active ? "取消追踪" : "追踪"}${escape(actor.authorName)}" title="${active ? "取消追踪" : "追踪"}">${icon("star")}</button>`;
  }

  function actorCard(actor) {
    const items = allUpdates.filter(item => item.authorId === actor.authorId);
    return `<article class="investor"><div class="investor-header">${avatar(actor)}<div class="investor-info"><button class="name" data-actor="${actor.authorId}">${escape(actor.authorName)}</button><div class="investor-meta">${platform(actor)}<span>${actor.money ? "Hyperliquid" : "Smart Account"}</span><span class="rank">${actor.money ? "" : rank(actor)}</span></div></div>${trackButton(actor)}</div>${items.slice(0, 2).map(item => entry(item)).join("")}<button class="all-activity" data-actor="${actor.authorId}">查看全部动态 ${icon("arrow-right")}</button></article>`;
  }

  function marketCard(ticker, index, alpha = false) {
    const items = updates.filter(item => item.ticker === ticker);
    const item = items[0];
    const latestAuthors = [...new Map(items.map(item => [item.authorId, item])).keys()].slice(0, 3).map(id => items.find(item => item.authorId === id));
    return `<button class="market-card ${index % 2 === 0 && !alpha ? "pale" : ""} ${alpha ? "alpha-card" : ""} ${read.has(item.id) ? "read" : ""}" data-event="${item.id}" aria-label="${ticker}，${escape(item.authorName)}的最新观点">
      <div class="market-banner"><div class="market-ticker">${logo(ticker)}${ticker}</div>${alpha ? `<span class="alpha-dot">${icon("sparkles")}</span>` : `<div class="author-trio">${latestAuthors.map(actor => `<div class="trio-one">${avatar(actor)}<span class="rank">${rank(actor)}</span></div>`).join("")}</div>`}</div>
      <div class="market-body"><div class="entry-text">${escape(item.activityTitleZH)}</div>${footer(item)}</div>
    </button>`;
  }

  function heading(title, action, label = "查看全部") {
    return `<div class="section-heading"><h4>${title}</h4>${action ? `<button data-list="${action}">${label}${icon("chevron-right")}</button>` : ""}</div>`;
  }

  function recommendations() {
    return actors.filter(actor => !actor.money && !tracked.has(actor.authorId)).sort((a, b) => a.platformPercentile - b.platformPercentile).slice(0, 3).map(actor => `<div class="recommendation">${avatar(actor)}<strong>${escape(actor.authorName)}<span class="rank">${rank(actor)}</span></strong>${trackButton(actor)}</div>`).join("");
  }

  function holdingsFeed() {
    let result = heading("持仓相关", "holdings", "管理");
    if (!holdings.size) {
      result += `<div class="quiet-state">${icon("pie-chart")}<strong>从你的第一只持仓开始</strong><button class="action-link" data-list="holdings">${icon("plus")}添加持仓</button></div>`;
    } else {
      result += `<div class="ticker-strip">${[...holdings].map(ticker => `<button class="ticker-tag" data-ticker="${ticker}">${logo(ticker)}${ticker}</button>`).join("")}</div>`;
      if (scenario === "quiet") {
        result += `<div class="quiet-state"><strong>近 30 天暂无持仓动态</strong></div>`;
      } else {
        const relevant = [...holdings].map(ticker => allUpdates.find(item => item.ticker === ticker)).filter(Boolean).slice(0, 2);
        result += relevant.map(item => entry(item, { withSource: true, reason: "持有" })).join("");
        result += `<button class="all-activity" data-list="related">全部持仓动态 ${icon("arrow-right")}</button>`;
      }
    }
    result += `<div class="section-space">${heading("追踪动态", "tracked", "全部")}</div>`;
    if (!tracked.size) {
      result += `<div class="quiet-state"><strong>追踪你想持续了解的投资者</strong></div>${recommendations()}`;
    } else if (scenario === "quiet") {
      result += `<div class="quiet-state"><strong>近 30 天暂无追踪动态</strong></div>${[...tracked].map(id => `<div class="recommendation">${avatar(actorById.get(id))}<strong>${escape(actorById.get(id).authorName)}</strong>${trackButton(actorById.get(id))}</div>`).join("")}`;
    } else {
      result += [...tracked].map(id => actorCard(actorById.get(id))).join("");
    }
    return `${result}<div class="endmark">近 30 天</div>`;
  }

  function marketFeed() {
    if (scenario === "quiet") return `${heading("热门标的")}<div class="quiet-state"><strong>近 30 天暂无新观点</strong></div>${heading("阿尔法标的")}<div class="quiet-state"><strong>暂无新的阿尔法动态</strong></div>`;
    return `${heading("热门标的", "trending")}${["META", "NVDA"].map((ticker, index) => marketCard(ticker, index)).join("")}<div class="section-space">${heading("阿尔法标的", "alpha")}</div>${["CRWD", "MCD"].map((ticker, index) => marketCard(ticker, index, true)).join("")}<div class="endmark">近 30 天</div>`;
  }

  function smartFeed(filter) {
    const sourceFilters = `<div class="source-filter" role="group" aria-label="动态来源">${[["all", "全部"], ["accounts", "Smart Account"], ["money", "Smart Money"]].map(([id, title]) => `<button class="${id === filter ? "active" : ""}" data-filter="${id}" aria-pressed="${id === filter}">${title}</button>`).join("")}</div>`;
    if (scenario === "quiet") return `${sourceFilters}<div class="quiet-state">${icon("activity")}<strong>近 30 天暂无新动态</strong></div>`;
    const selected = actors.filter(actor => filter === "all" || (filter === "money" ? actor.money : !actor.money));
    return `${sourceFilters}${selected.map(actorCard).join("")}<div class="endmark">近 30 天</div>`;
  }

  class Phone {
    constructor(scheme) {
      this.scheme = scheme;
      this.index = 0;
      this.filter = "all";
      this.history = [];
      this.suppressClickUntil = 0;
      const article = document.createElement("article");
      article.className = "proposal";
      article.dataset.scheme = scheme.id;
      article.innerHTML = `<header class="proposal-head"><span class="proposal-number">方案 ${scheme.id.toUpperCase()}</span><h2>${scheme.title}${scheme.id === "a" ? '<span class="recommended">推荐</span>' : ""}</h2><p>${scheme.note}</p></header>
        <div class="phone" data-scheme="${scheme.id}"><div class="statusbar"><span>9:41</span><span class="status-icons">${icon("signal")}${icon("wifi")}${icon("battery-full")}</span></div>
        <header class="phone-header"><h3>${scheme.id === "c" ? labels[0] : "今日"}</h3><button class="settings" data-settings aria-label="设置与提醒">${icon("settings-2")}</button></header>
        <nav class="subnav" role="tablist" aria-label="首页场景">${labels.map((label, index) => `<button role="tab" id="${scheme.id}-tab-${index}" aria-controls="${scheme.id}-panel-${index}" aria-selected="${index === 0}" tabindex="${index === 0 ? 0 : -1}" data-page="${index}">${label}</button>`).join("")}</nav>
        <div class="pager"><div class="pages">${labels.map((label, index) => `<section class="feed" role="tabpanel" aria-labelledby="${scheme.id}-tab-${index}" id="${scheme.id}-panel-${index}" tabindex="0" ${index ? "inert" : ""}></section>`).join("")}</div></div>
        <div class="phone-bottom"><div class="main-nav" aria-label="现有主导航，当前为今日">${[["house", "今日"], ["pie-chart", "持仓"], ["activity", "Smart"], ["sparkles", "Mr Collie"]].map(([symbol, title], index) => `<span class="${index === 0 ? "active" : ""}" role="img" aria-label="${title}" title="${title}">${icon(symbol)}</span>`).join("")}</div><div class="home-indicator"></div></div>
        <section class="detail" aria-label="详情" inert><header class="detail-bar"><button class="detail-back" aria-label="返回">${icon("arrow-left")}</button><h4></h4></header><div class="detail-body"></div></section></div>`;
      document.querySelector("#prototypes").append(article);
      this.root = article.querySelector(".phone");
      this.pager = article.querySelector(".pager");
      this.pages = article.querySelector(".pages");
      this.feeds = [...article.querySelectorAll(".feed")];
      this.detail = article.querySelector(".detail");
      this.renderFeeds();
      this.listen();
    }

    renderFeeds() {
      const positions = this.feeds.map(feed => feed.scrollTop);
      const content = [holdingsFeed(), marketFeed(), smartFeed(this.filter)];
      this.feeds.forEach((feed, index) => {
        feed.innerHTML = content[index];
        feed.scrollTop = positions[index];
      });
    }

    go(index, focus = false) {
      this.index = Math.max(0, Math.min(2, index));
      this.pages.classList.remove("dragging");
      this.pages.style.transform = `translate3d(${-100 * this.index}%,0,0)`;
      this.root.querySelectorAll("[data-page]").forEach((tab, position) => {
        tab.setAttribute("aria-selected", position === this.index);
        tab.tabIndex = position === this.index ? 0 : -1;
        if (focus && position === this.index) tab.focus();
      });
      this.feeds.forEach((feed, position) => { feed.inert = position !== this.index; });
      if (this.scheme.id === "c") this.root.querySelector(".phone-header h3").textContent = labels[this.index];
    }

    show(title, content) {
      if (!this.history.length) this.returnFocus = document.activeElement;
      else this.history[this.history.length - 1].scroll = this.detail.querySelector(".detail-body").scrollTop;
      this.history.push({ title, content, scroll: 0 });
      this.paintDetail();
    }

    paintDetail() {
      const current = this.history.at(-1);
      this.detail.querySelector("h4").textContent = current.title;
      this.detail.querySelector(".detail-body").innerHTML = current.content;
      this.detail.querySelector(".detail-body").scrollTop = current.scroll;
      this.detail.querySelectorAll("[data-track]").forEach(button => {
        const active = tracked.has(button.dataset.track);
        button.setAttribute("aria-pressed", active);
        button.setAttribute("aria-label", `${active ? "取消追踪" : "追踪"}${actorById.get(button.dataset.track).authorName}`);
      });
      this.detail.querySelectorAll("[data-event]").forEach(button => button.classList.toggle("read", read.has(button.dataset.event)));
      this.detail.classList.add("open");
      this.detail.inert = false;
      [...this.root.children].filter(child => !child.classList.contains("detail") && !child.classList.contains("statusbar")).forEach(child => { child.inert = true; });
      this.detail.querySelector(".detail-back").focus({ preventScroll: true });
      refreshIcons();
    }

    back() {
      this.history.pop();
      if (this.history.length) return this.paintDetail();
      this.detail.classList.remove("open");
      this.detail.inert = true;
      [...this.root.children].forEach(child => { if (!child.classList.contains("detail")) child.inert = false; });
      this.go(this.index);
      this.returnFocus?.focus({ preventScroll: true });
    }

    evidence(id) {
      const item = itemById.get(id);
      read.add(id);
      document.querySelectorAll(`[data-event="${id}"]`).forEach(element => element.classList.add("read"));
      this.show(`${item.ticker} · ${item.money ? "资金动态" : "观点详情"}`, `${footer(item)}<div class="detail-meta">${item.publishedAt.slice(0, 10)}${item.money ? ` · ${item.market}` : " · 来源摘要"}</div><h3>${escape(item.activityTitleZH)}</h3>${item.thesis ? `<p>${escape(item.thesis)}</p>` : ""}<a class="action-link" href="${escape(item.sourceURL)}" target="_blank" rel="noopener">${icon("arrow-up-right")}${item.money ? "查看公开账户" : "打开原帖"}</a>`);
    }

    actor(id) {
      const actor = actorById.get(id);
      const items = allUpdates.filter(item => item.authorId === id);
      this.show(actor.authorName, `<div class="investor-header">${avatar(actor)}<div class="investor-info"><strong>${escape(actor.authorName)}</strong><div class="investor-meta">${platform(actor)}<span>${rank(actor)}</span></div></div>${trackButton(actor)}</div>${scenario === "quiet" ? '<div class="quiet-state">近 30 天暂无动态</div>' : items.map(item => entry(item)).join("")}`);
    }

    list(type) {
      if (type === "holdings") {
        this.show("我的持仓", `<div class="detail-meta">${holdings.size} 只标的</div>${["NVDA", "META", "MSTR", "MU", "PLTR", "CRWD", "MCD"].map(ticker => `<label class="setting-row"><span class="entry-top">${logo(ticker)}${ticker}</span><input type="checkbox" data-holding="${ticker}" ${holdings.has(ticker) ? "checked" : ""} aria-label="持有 ${ticker}"></label>`).join("")}`);
      } else if (type === "related") {
        this.show("持仓相关", allUpdates.filter(item => holdings.has(item.ticker)).map(item => entry(item, { withSource: true })).join(""));
      } else if (type === "tracked") {
        const contents = scenario === "quiet"
          ? `<div class="quiet-state"><strong>近 30 天暂无追踪动态</strong></div>`
          : [...tracked].map(id => actorCard(actorById.get(id))).join("");
        this.show("追踪动态", tracked.size ? contents : `<div class="quiet-state"><strong>追踪你想持续了解的投资者</strong></div>${recommendations()}`);
      } else {
        const tickers = type === "alpha" ? ["CRWD", "MCD"] : ["META", "NVDA", "MU", "PLTR", "MSTR"];
        this.show(type === "alpha" ? "阿尔法标的" : "热门标的", scenario === "quiet" ? '<div class="quiet-state">近 30 天暂无新观点</div>' : tickers.map((ticker, index) => marketCard(ticker, index, type === "alpha")).join(""));
      }
    }

    listen() {
      this.root.addEventListener("click", event => {
        if (performance.now() < this.suppressClickUntil) { event.preventDefault(); return; }
        const target = event.target.closest("button");
        if (!target) return;
        if (target.classList.contains("detail-back")) return this.back();
        if (target.hasAttribute("data-page")) return this.go(Number(target.dataset.page));
        if (target.dataset.event) return this.evidence(target.dataset.event);
        if (target.dataset.actor) return this.actor(target.dataset.actor);
        if (target.dataset.list) return this.list(target.dataset.list);
        if (target.dataset.track) {
          const id = target.dataset.track;
          if (tracked.has(id)) tracked.delete(id); else tracked.add(id);
          const active = tracked.has(id);
          document.querySelectorAll(`[data-track="${id}"]`).forEach(button => {
            button.setAttribute("aria-pressed", active);
            button.setAttribute("aria-label", `${active ? "取消追踪" : "追踪"}${actorById.get(id).authorName}`);
            button.title = active ? "取消追踪" : "追踪";
          });
          refreshFeeds();
          return;
        }
        if (target.dataset.ticker) {
          const items = allUpdates.filter(item => item.ticker === target.dataset.ticker);
          return this.show(`${target.dataset.ticker} · Smart Activity`, scenario === "quiet" ? '<div class="quiet-state">近 30 天暂无动态</div>' : items.map(item => entry(item, { withSource: true })).join(""));
        }
        if (target.dataset.filter) { this.filter = target.dataset.filter; this.renderFeeds(); refreshIcons(); return; }
        if (target.hasAttribute("data-settings")) this.show("设置与提醒", `<label class="setting-row"><span>白天模式</span><input type="checkbox" data-light ${light ? "checked" : ""}></label><div class="setting-row"><span>提醒</span><span>尚未开启</span></div>`);
      });
      this.root.addEventListener("change", event => {
        if (event.target.dataset.holding) {
          const ticker = event.target.dataset.holding;
          if (event.target.checked) holdings.add(ticker); else holdings.delete(ticker);
          this.detail.querySelector(".detail-meta").textContent = `${holdings.size} 只标的`;
          refreshFeeds();
        }
        if (event.target.hasAttribute("data-light")) toggleTheme(event.target.checked);
      });
      this.root.addEventListener("keydown", event => {
        if (event.key === "Escape" && this.history.length) { event.preventDefault(); this.back(); }
        if (!this.history.length && event.target.closest(".subnav") && ["ArrowLeft", "ArrowRight"].includes(event.key)) {
          event.preventDefault(); this.go(this.index + (event.key === "ArrowRight" ? 1 : -1), true);
        }
      });
      this.swipe();
    }

    swipe() {
      let gesture = null;
      this.pager.addEventListener("pointerdown", event => {
        if (event.button !== 0 || event.target.closest("input, select")) return;
        gesture = { x: event.clientX, y: event.clientY, dx: 0, axis: "", time: performance.now() };
      });
      this.pager.addEventListener("pointermove", event => {
        if (!gesture) return;
        const dx = event.clientX - gesture.x;
        const dy = event.clientY - gesture.y;
        if (!gesture.axis && Math.max(Math.abs(dx), Math.abs(dy)) > 10) {
          gesture.axis = Math.abs(dx) > Math.abs(dy) * 1.25 ? "x" : "y";
          if (gesture.axis === "x") {
            this.pager.setPointerCapture(event.pointerId);
            this.pages.classList.add("dragging");
          }
        }
        if (gesture.axis !== "x") return;
        event.preventDefault();
        gesture.dx = dx;
        const shift = (this.index === 0 && dx > 0) || (this.index === 2 && dx < 0) ? dx * 0.2 : dx;
        this.pages.style.transform = `translate3d(calc(${-100 * this.index}% + ${shift}px),0,0)`;
      });
      const finish = (event, cancelled = false) => {
        if (!gesture) return;
        if (gesture.axis === "x") {
          const { dx, time } = gesture;
          const advance = !cancelled && (Math.abs(dx) > 55 || (Math.abs(dx) > 24 && Math.abs(dx) / (performance.now() - time) > 0.45));
          this.go(this.index + (advance ? (dx < 0 ? 1 : -1) : 0));
          this.suppressClickUntil = performance.now() + 350;
          if (this.pager.hasPointerCapture(event.pointerId)) this.pager.releasePointerCapture(event.pointerId);
        }
        gesture = null;
      };
      this.pager.addEventListener("pointerup", event => finish(event));
      this.pager.addEventListener("pointercancel", event => finish(event, true));
      let wheelSum = 0;
      let lastWheel = 0;
      let wheelLock = 0;
      this.pager.addEventListener("wheel", event => {
        if (Math.abs(event.deltaX) < Math.abs(event.deltaY) || Math.abs(event.deltaX) < 2) return;
        event.preventDefault();
        const now = performance.now();
        if (now < wheelLock) return;
        if (now - lastWheel > 200) wheelSum = 0;
        lastWheel = now;
        wheelSum += event.deltaX;
        if (Math.abs(wheelSum) > 60) {
          this.go(this.index + (wheelSum > 0 ? 1 : -1));
          wheelSum = 0; wheelLock = now + 550;
        }
      }, { passive: false });
    }
  }

  function refreshFeeds() {
    phones.forEach(phone => phone.renderFeeds());
    refreshIcons();
  }

  function toggleTheme(value = !light) {
    light = value;
    phones.forEach(phone => phone.root.classList.toggle("light", light));
    const button = document.querySelector("#theme");
    button.innerHTML = icon(light ? "moon" : "sun");
    button.title = button.ariaLabel = light ? "切换黑夜模式" : "切换白天模式";
    document.querySelectorAll("[data-light]").forEach(input => { input.checked = light; });
    refreshIcons();
  }

  // Keep a usable identity even when a remote avatar is unavailable.
  document.addEventListener("error", event => {
    const target = event.target;
    if (target instanceof HTMLImageElement && target.parentElement.classList.contains("avatar")) {
      const parent = target.parentElement;
      parent.textContent = parent.dataset.initial;
      parent.classList.add("initials");
    }
  }, true);

  phones = schemes.map(scheme => new Phone(scheme));
  document.querySelectorAll("[data-mode]").forEach(button => {
    if (button.tagName !== "BUTTON") return;
    button.addEventListener("click", () => {
      document.querySelector("#prototypes").dataset.mode = button.dataset.mode;
      document.querySelectorAll(".review-modes button").forEach(other => other.classList.toggle("active", other === button));
    });
  });
  document.querySelectorAll("[data-sync]").forEach(button => button.addEventListener("click", () => {
    phones.forEach(phone => { while (phone.history.length) phone.back(); phone.go(Number(button.dataset.sync)); });
    document.querySelectorAll("[data-sync]").forEach(other => other.classList.toggle("active", other === button));
  }));
  document.querySelector("#theme").addEventListener("click", () => toggleTheme());
  document.querySelector("#scenario").addEventListener("change", event => {
    scenario = event.target.value;
    tracked = new Set(scenario === "empty" ? [] : initialTracked);
    holdings = new Set(scenario === "empty" ? [] : ["NVDA", "MSTR"]);
    read.clear();
    phones.forEach(phone => { while (phone.history.length) phone.back(); phone.feeds.forEach(feed => { feed.scrollTop = 0; }); });
    refreshFeeds();
  });
  refreshIcons();
})();
