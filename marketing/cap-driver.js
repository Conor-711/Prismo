(function () {
  // split 慢一步 into per-char spans
  var EM = new Set("慢一步");
  document.querySelectorAll("[data-split]").forEach(function (el) {
    var t = el.textContent || "";
    el.textContent = "";
    Array.from(t).forEach(function (c) {
      var s = document.createElement("span");
      s.className = "ch" + (EM.has(c) ? " em" : "");
      s.textContent = c;
      el.appendChild(s);
    });
  });
  // ticker
  var tk = document.getElementById("ticker");
  if (tk)
    tk.innerHTML = [["NVDA", "3.4"], ["TSLA", "5.1"], ["GME", "18"], ["AMD", "2.7"], ["PLTR", "4.2"], ["SMCI", "6.8"]]
      .map(function (t) { return t[0] + ' <span class="up">▲' + t[1] + "%</span>"; })
      .join("");
  // feeds (duplicated for seamless loop)
  var POSTS = ["DD: why $NVDA still has room to run into next print", "GME gamma squeeze thesis — updated OI tables", "Loaded calls on $TSLA earnings, here's my reasoning", "$AMD vs $INTC: the real datacenter share story", "My $PLTR position and exactly why I'm still holding", "Bear case for $SPY into CPI — hedging with puts", "Found the next chokepoint upstream of Nvidia: $AXTI", "0DTE flow that actually printed this week, full log", "Why I sold my $AAPL puts before the gap up", "Semis are heating up — deep dive on $SMCI margins", "Retail sentiment vs institutional positioning, $QQQ", "Options skew is screaming — $MSFT pre-earnings note"];
  var U = ["deepvalue", "wsb_ape", "quantkid", "thetagang_x", "ironcondor", "rocketman"];
  function fill(id, n) {
    var el = document.getElementById(id);
    if (el) el.innerHTML = Array.from({ length: n }, function (_, i) { return '<div class="row">u/' + U[i % 6] + " · " + POSTS[i % POSTS.length] + "</div>"; }).join("");
  }
  fill("feed2", 24);
  fill("feed3", 24);
  var f2 = document.getElementById("feed2"), f3 = document.getElementById("feed3");
  if (f2) f2.innerHTML += f2.innerHTML;
  if (f3) f3.innerHTML += f3.innerHTML;

  // timeline — paused (identical to approved HTML, minus timeScale; we seek at t*1.42)
  var tl = gsap.timeline({ paused: true, defaults: { ease: "power3.out", duration: 0.8 } });
  tl.set(".s1", { autoAlpha: 1 }, 0)
    .from(".s1 .ticker span", { autoAlpha: 0, y: -14, stagger: 0.05, duration: 0.5 }, 0.15)
    .fromTo(".s1 .l1", { autoAlpha: 0, y: 26, filter: "blur(10px)" }, { autoAlpha: 1, y: 0, filter: "blur(0px)", duration: 0.9 }, 0.55)
    .from(".s1 .l2 .ch", { autoAlpha: 0, yPercent: -120, stagger: 0.045, ease: "back.out(2)", duration: 0.7 }, 1.15)
    .to(".s1 .l2 .ch.em", { scale: 1.22, transformOrigin: "50% 100%", stagger: 0.05, yoyo: true, repeat: 1, ease: "power2.out", duration: 0.2 }, 2.15)
    .to(".s1", { autoAlpha: 0, y: -46, duration: 0.5 }, 4.15);
  tl.set(".s2bg", { autoAlpha: 1 }, 4.4)
    .set(".s2", { autoAlpha: 1 }, 4.4)
    .from(".s2 .head .rlogo", { autoAlpha: 0, scale: 0.3, rotation: -40, ease: "back.out(1.8)", duration: 0.7 }, 4.55)
    .from(".s2 .head .t", { autoAlpha: 0, x: 26 }, 4.8)
    .from(".s2 .snoo-2", { autoAlpha: 0, xPercent: 150, rotation: 14, ease: "back.out(1.5)", duration: 0.9 }, 4.85)
    .from(".s2 .card", { autoAlpha: 0, x: -90, stagger: 0.5, ease: "back.out(1.4)", duration: 0.7 }, 5.6)
    .from(".s2 .card .ava", { scale: 0.2, rotation: -25, stagger: 0.5, ease: "back.out(2)", duration: 0.6 }, 5.75)
    .from(".s2 .card .gain", { autoAlpha: 0, scale: 0.4, stagger: 0.5, ease: "back.out(2.2)", duration: 0.55 }, 6.15)
    .from(".s2 .foot", { autoAlpha: 0, y: 18 }, 8.6)
    .to(".s2", { autoAlpha: 0, scale: 0.97, duration: 0.5 }, 10.2)
    .to(".s2bg", { autoAlpha: 0, duration: 0.5 }, 10.2);
  tl.set(".s3", { autoAlpha: 1 }, 10.4)
    .from(".s3 .veil", { autoAlpha: 0, duration: 0.6 }, 10.5)
    .from(".s3 .p1", { autoAlpha: 0, y: 24 }, 11)
    .from(".s3 .p2 .seg:not(.blk)", { autoAlpha: 0, y: 24 }, 11.5)
    .fromTo(".s3 .p2 .blk", { scale: 1.55, autoAlpha: 0 }, { scale: 1, autoAlpha: 1, ease: "power4.out", duration: 0.5 }, 12)
    .to(".s3", { autoAlpha: 0, duration: 0.5 }, 13.9);
  tl.set(".s4", { autoAlpha: 1 }, 14)
    .from(".s4 .wave", { autoAlpha: 0, yPercent: 80, duration: 1 }, 14)
    .from(".s4 .brand .ltile", { autoAlpha: 0, scale: 0.4, rotation: -8, ease: "back.out(1.7)", duration: 0.7 }, 14.45)
    .from(".s4 .brand .wm", { autoAlpha: 0, x: 26 }, 14.7)
    .from(".s4 .sub", { autoAlpha: 0, y: 14 }, 15)
    .from(".s4 .snoo-s4", { autoAlpha: 0, xPercent: 165, rotation: 12, ease: "back.out(1.5)", duration: 0.9 }, 14.6)
    .from(".s4 .fcard", { autoAlpha: 0, y: 42, scale: 0.9, rotation: function (i) { return i % 2 ? 2.5 : -2.5; }, stagger: 0.5, ease: "back.out(1.3)", duration: 0.7 }, 15.7)
    .from(".s4 .foot", { autoAlpha: 0, y: 22 }, 21.6)
    .fromTo(".s4 .foot em", { scale: 0.5, autoAlpha: 0 }, { scale: 1, autoAlpha: 1, ease: "back.out(2.4)", duration: 0.6 }, 21.9)
    .to(".s4", { autoAlpha: 0, duration: 0.6 }, 24.7);
  tl.set(".s5", { autoAlpha: 1 }, 25)
    .from(".s5 .big", { autoAlpha: 0, scale: 0.7, ease: "back.out(1.5)", duration: 1 }, 25.1)
    .from(".s5 .url", { autoAlpha: 0, y: 20, duration: 0.8 }, 25.7)
    .from(".s5 .squad .snoo-wrap", { autoAlpha: 0, yPercent: 170, stagger: 0.12, ease: "back.out(1.6)", duration: 0.7 }, 25.9)
    .to(".s5 .url", { duration: 3.0 }, 26.6);

  window.__seek = function (t) {
    tl.time(Math.min(t * 1.42, tl.duration()));
    if (f2) gsap.set(f2, { yPercent: -50 * ((t / 26) % 1) });
    if (f3) gsap.set(f3, { yPercent: -50 * ((t / 19) % 1) });
  };
  window.__dur = tl.duration() / 1.42;
  window.__seek(0);
  window.__ready = true;
})();
