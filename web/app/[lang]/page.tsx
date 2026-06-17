import { LocaleLink } from "@/components/i18n/LocaleLink";
import { IconUpvote, IconArrow } from "@/components/icons";
import { RedditMark, SnooCharacter } from "@/components/reddit";
import { CommunityIcon } from "@/components/CommunityIcon";
import { LegendsCarousel } from "@/components/LegendsCarousel";
import { fmtInt, fmtCompact } from "@/lib/format";
import { getLandingStats } from "@/lib/queries";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

const FALLBACK_SUBS = [
  { id: "wallstreetbets", subscribers: 20043788 },
  { id: "stocks", subscribers: 9268383 },
  { id: "stockmarket", subscribers: 4067736 },
  { id: "investing", subscribers: 3388641 },
  { id: "options", subscribers: 1414521 },
  { id: "valueinvesting", subscribers: 752379 },
  { id: "thetagang", subscribers: 331918 },
  { id: "securityanalysis", subscribers: 210051 },
];

// 真实「Reddit 股神」——公开报道 / 本人披露的战绩，作为「Reddit = 美股高质量社区」的佐证。
type Legend = {
  avatar: 1 | 2 | 3 | 4; // Snoo 兜底
  img: string; // public/legends/{img}.png（来自 X 的真实头像）
  flair: string;
  year: string;
  handle: string;
  name: { zh: string; en: string };
  stat: string;
  statClass: string;
  era: { zh: string; en: string };
  story: { zh: string; en: string };
  tickers: string[];
  source: string;
  href: string;
};
// 按时间从过去到现在排列（左→右）。
const LEGENDS: Legend[] = [
  {
    avatar: 1,
    flair: "👑",
    year: "2012",
    handle: "@0xRogozinski",
    img: "rogozinski",
    name: { zh: "Jaime Rogozinski · WSB 创始人", en: "Jaime Rogozinski · WSB founder" },
    stat: "17M+",
    statClass: "metal-text m-gold",
    era: { zh: "创立 r/wallstreetbets", en: "Founded r/wallstreetbets" },
    story: {
      zh: "2012 年在 Reddit 创立 r/wallstreetbets，为散户造了「金融界最大的赌场」。如今社区超 1,700 万成员，掀起 GME / AMC 史诗级逼空，逼华尔街重新敬畏散户。著有《WallStreetBets》一书。",
      en: "Founded r/wallstreetbets on Reddit in 2012 — “the world’s biggest casino for the people.” Now 17M+ members strong, it drove the GME/AMC squeezes and forced Wall Street to respect retail. Author of the book “WallStreetBets.”",
    },
    tickers: ["GME", "AMC"],
    source: "Wikipedia · CoinDesk",
    href: "https://jaimerogozinski.com/",
  },
  {
    avatar: 1,
    flair: "🚀",
    year: "2020",
    handle: "u/wsbgod",
    img: "wsbgod",
    name: { zh: "WSBGod · YOLO 之神", en: "WSBGod · the YOLO legend" },
    stat: "$20K → $8M",
    statClass: "text-reddit",
    era: { zh: "TSLA / AMD 期权", en: "TSLA / AMD options" },
    story: {
      zh: "零经验、2 万美元起步，靠特斯拉/AMD 看涨期权封神——12.6 万美元的特斯拉期权一度值 430 万，账户从 420 万翻到约 800 万，并开直播分享屏幕自证。",
      en: "Started with $20K and zero experience; rode Tesla/AMD calls to fame — a $126K Tesla options bet hit $4.3M, and the account doubled from $4.2M to ~$8M (later screen-shared live to prove it).",
    },
    tickers: ["TSLA", "AMD"],
    source: "Markets Insider",
    href: "https://markets.businessinsider.com/news/stocks/tesla-stock-price-reddit-trader-options-gains-millions-wallstreetbets-tsla-2020-2",
  },
  {
    avatar: 3,
    flair: "📈",
    year: "2021",
    handle: "@imkevinxu",
    img: "kevinxu",
    name: { zh: "Kevin Xu · 全程公开晒单", en: "Kevin Xu · trades in the open" },
    stat: "$35K → $8M",
    statClass: "text-reddit",
    era: { zh: "透明交易 · 后创办锦标赛", en: "Transparent trading" },
    story: {
      zh: "疫情期间加入 WSB，把每一笔交易（含具体金额）全程公开晒出——3.5 万美元做到 800 多万且没有回吐；后来创办了 Stonk Madness 交易锦标赛。",
      en: "Joined WSB during the pandemic and posted every single trade (with dollar amounts) in the open — turned $35K into $8M+ without giving it back. Later founded the Stonk Madness tournament.",
    },
    tickers: ["TSLA", "SPY"],
    source: "BusinessWire",
    href: "https://www.businesswire.com/news/home/20240305148457/en/",
  },
  {
    avatar: 2,
    flair: "🐱",
    year: "2021",
    handle: "u/DeepFuckingValue",
    img: "roaringkitty",
    name: { zh: "Keith Gill · 咆哮小猫", en: "Keith Gill · Roaring Kitty" },
    stat: "$53K → $48M",
    statClass: "metal-text m-gold",
    era: { zh: "GME · 史诗级逼空", en: "GME · the great squeeze" },
    story: {
      zh: "在 r/wallstreetbets 用深度 DD 押注 GameStop，约 5.3 万美元本金一度做到约 4,800 万；2024 年回归晒仓，账面峰值一度超 5.85 亿美元。国会留下名言「I like the stock.」",
      en: "Backed GameStop with deep DD on r/wallstreetbets — ~$53K became ~$48M. His 2024 return revealed a position that peaked above $585M on paper. Told Congress: “I like the stock.”",
    },
    tickers: ["GME"],
    source: "Wikipedia · CNBC",
    href: "https://en.wikipedia.org/wiki/Keith_Gill",
  },
  {
    avatar: 4,
    flair: "📺",
    year: "2021",
    handle: "@matt_kohrs",
    img: "mattkohrs",
    name: { zh: "Matt Kohrs · 迷因股旗手", en: "Matt Kohrs · meme-stock voice" },
    stat: "1M+",
    statClass: "text-reddit",
    era: { zh: "百万粉丝 · GME/AMC 起义", en: "1M+ followers · GME/AMC uprising" },
    story: {
      zh: "GME / AMC 逼空潮中崛起的迷因股直播旗手，把 r/wallstreetbets 的 DD 与情绪带给上百万散户，是 2021『散户起义』最响亮的声音之一。",
      en: "Rose during the GME/AMC squeezes as a meme-stock streamer, carrying r/wallstreetbets DD and sentiment to over a million retail traders — one of the loudest voices of the 2021 retail uprising.",
    },
    tickers: ["GME", "AMC"],
    source: "YouTube · X",
    href: "https://x.com/matt_kohrs",
  },
  {
    avatar: 4,
    flair: "🔬",
    year: "2024–26",
    handle: "u/AleaBito",
    img: "serenity",
    name: { zh: "Serenity · 卡脖子猎手", en: "Serenity · chokepoint hunter" },
    stat: "≈ 225× / 2 年",
    statClass: "metal-text m-silver",
    era: { zh: "AI 供应链「卡脖子」", en: "AI supply-chain chokepoints" },
    story: {
      zh: "反向研究英伟达上游的「卡脖子」环节：2022 年发 AXTI 深度贴被 WSB 封号，随后 $12→$140；一条推让 Raspberry Pi 两天涨约 90%。两年自述约 225 倍回报，被路透、彭博点名，50 万+ 粉丝跟读（自述、未经审计）。",
      en: "Reverse-engineers the “chokepoints” upstream of Nvidia: his 2022 AXTI thesis got him banned from WSB right before it ran $12→$140; one post sent Raspberry Pi ~90% in two days. ~225× self-reported over two years, cited by Reuters & Bloomberg, 500K+ followers (self-reported, unaudited).",
    },
    tickers: ["AXTI", "RPI", "NVDA"],
    source: "Reuters · Bloomberg",
    href: "https://x.com/aleabitoreddit",
  },
  {
    avatar: 2,
    flair: "⚡",
    year: "2025",
    handle: "u/Grandmaster-Obi",
    img: "obi",
    name: { zh: "Grandmaster-Obi · 散户动能", en: "Grandmaster-Obi · retail momentum" },
    stat: "100–1,000%+",
    statClass: "text-reddit",
    era: { zh: "散户涨停潮 · 触发熔断", en: "Halts & momentum" },
    story: {
      zh: "2021 GME 逼空时期的 WSB 老版主，最懂散户动能怎么点燃。2025 年带着「Making Easy Money」社群，被指连续触发多次美股熔断停牌，数十个标的接连跑出 100%–1,000%+。",
      en: "A former r/wallstreetbets moderator from the 2021 GME run who knows how retail momentum ignites. In 2025 his “Making Easy Money” community was credited with triggering multiple market circuit-breaker halts, with dozens of plays running 100%–1,000%+.",
    },
    tickers: ["GME", "0DTE"],
    source: "WSB · 2025",
    href: "https://www.reddit.com/r/wallstreetbets/",
  },
];

export default function Landing({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const t = getDictionary(lang).landing;

  // 把 lede 按首句拆成两行，做出阅读节奏（不改字典，按句号/句点切分）。
  const ledeSep = zh ? "。" : ". ";
  const ledeIdx = t.ledePre.indexOf(ledeSep);
  const lede1 = ledeIdx >= 0 ? t.ledePre.slice(0, ledeIdx) : t.ledePre;
  const lede2 = ledeIdx >= 0 ? t.ledePre.slice(ledeIdx + ledeSep.length) : "";

  const s = getLandingStats();
  const subs = s.subs.length ? s.subs : FALLBACK_SUBS;
  const totalSubscribers =
    s.totalSubscribers || FALLBACK_SUBS.reduce((a, c) => a + c.subscribers, 0);
  const subsValue = zh ? `${fmtInt(Math.round(totalSubscribers / 1e4))}万` : fmtCompact(totalSubscribers);
  const posts = s.posts || 1176;
  const tickers = s.tickers || 50;
  const authors = s.authors || 848;

  // 把股神数据本地化后传给客户端轮播组件
  const legendViews = LEGENDS.map((L) => ({
    handle: L.handle,
    name: zh ? L.name.zh : L.name.en,
    era: zh ? L.era.zh : L.era.en,
    story: zh ? L.story.zh : L.story.en,
    stat: L.stat,
    statClass: L.statClass,
    tickers: L.tickers,
    source: L.source,
    href: L.href,
    flair: L.flair,
    year: L.year,
    img: `${BASE}/legends/${L.img}.png`,
    fallback: `${BASE}/avatars/snoo-${L.avatar}.png`,
  }));

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto snap-y snap-proximity theme-canvas">
      {/* ============ 视图一：英雄区（整屏） ============ */}
      <section className="relative min-h-[100svh] snap-start flex flex-col">
        <header className="flex items-center justify-center sm:justify-start px-6 sm:px-10 h-20 shrink-0">
          <div className="flex items-center gap-2.5">
            <span className="w-9 h-9 rounded-xl overflow-hidden bg-white shrink-0 ring-1 ring-white/10">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`${BASE}/logo.png`} alt="redditalpha" className="w-full h-full object-contain rounded-xl" />
            </span>
            <span className="font-display font-extrabold text-cream text-[18px] tracking-tight">
              reddit<span className="text-reddit">alpha</span>
            </span>
          </div>
        </header>

        <div className="flex-1 flex flex-col items-center justify-center text-center px-6 pb-20 pt-2">
          <div className="w-full max-w-5xl mx-auto">
            <div className="inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-[12px] font-semibold ring-1 ring-inset ring-white/10 bg-white/[.03] text-neutral-300">
              <IconUpvote className="w-3.5 h-3.5 text-reddit" />
              {t.badge}
            </div>

            {/* 主标题：强制单行（whitespace-nowrap），用 vw 自适应缩放以适配各宽度 */}
            <h1 className="mt-6 font-display font-extrabold text-cream tracking-tight leading-[1.1] whitespace-nowrap text-[clamp(20px,5vw,52px)]">
              {t.titleLead} <span className="metal-text m-gold">{t.titleGold}</span>
              {t.titleTail}
            </h1>

            {/* lede：拆成两句两行，重点短语强调 + 平衡换行 */}
            <div className="mt-6 mx-auto max-w-xl flex flex-col gap-1.5 [text-wrap:balance]">
              <p className="text-cream/90 font-medium leading-relaxed text-[16px] sm:text-[17px]">
                {lede1}{zh ? "。" : "."}
              </p>
              <p className="text-neutral-400 leading-relaxed text-[15px] sm:text-[16px]">
                {lede2}
                <span className="text-cream font-semibold">{t.ledeStrong}</span>
                {t.ledePost}
              </p>
            </div>

            <div className="mt-8 flex flex-col items-center">
              <LocaleLink
                href="/dashboard"
                className="group inline-flex items-center justify-center gap-2 rounded-xl px-7 py-4 font-display font-bold text-white text-[16px] shadow-lg shadow-reddit/30 ring-1 ring-inset ring-white/15 hover:brightness-110 hover:-translate-y-0.5 transition"
                style={{ backgroundImage: "var(--grad-brand)" }}
              >
                {t.enterCta}
                <IconArrow className="w-4 h-4 transition group-hover:translate-x-0.5" />
              </LocaleLink>
              <p className="mt-3 text-[13px] text-neutral-500">{t.enterDesc}</p>
            </div>

            {/* 统计条 */}
            <div className="mt-12 flex flex-wrap items-start justify-center gap-x-10 gap-y-4">
              <Stat big={String(subs.length)} label={t.statCommunities} />
              <Stat big={subsValue} label={t.statSubscribers} />
              <Stat big={fmtInt(posts)} label={t.statPosts} />
              <Stat big={String(tickers)} label={t.statTickers} />
              <Stat big={fmtInt(authors)} label={t.statAuthors} />
            </div>
          </div>
        </div>

        {/* 向下滚动提示 */}
        <a
          href="#legends"
          className="absolute inset-x-0 bottom-6 mx-auto flex w-max flex-col items-center gap-1 text-[12px] text-neutral-500 hover:text-reddit transition"
        >
          <span>{zh ? "看看从这里走出的股神" : "Meet the legends forged here"}</span>
          <svg className="w-5 h-5 animate-bounce" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 9l6 6 6-6" />
          </svg>
        </a>
      </section>

      {/* ============ 视图二：Reddit 股神（整屏） ============ */}
      <section id="legends" className="relative min-h-[100svh] snap-start flex flex-col justify-center px-6 py-16">
        <div className="w-full max-w-5xl mx-auto">
          <div className="text-center">
            <div className="inline-flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[.16em] text-reddit">
              <RedditMark size={16} />
              {zh ? "真实人物 · 真实战绩" : "Real people · real track records"}
            </div>
            <h2 className="mt-3 font-display font-extrabold text-cream tracking-tight leading-[1.1] text-[clamp(28px,4.5vw,44px)]">
              {zh ? "从 Reddit 走出的" : "Legends forged on "}
              <span className="metal-text m-gold">{zh ? "股神" : "Reddit"}</span>
            </h2>
            <p className="mt-4 mx-auto max-w-2xl text-neutral-400 leading-relaxed text-[15px]">
              {zh
                ? "Reddit 不是赌场——有人靠公开的深度研究改写了人生。这正是这里值得被认真对待的原因。"
                : "Reddit isn't a casino — here, deep public research has changed lives. That's why this community is worth taking seriously."}
            </p>
          </div>

          {/* 股神时间线轮播：左右滑动，居中者被聚光灯打亮 */}
          <div className="mt-6">
            <LegendsCarousel
              legends={legendViews}
              spotlight={zh ? "聚光灯" : "Spotlight"}
              hint={zh ? "← 左右滑动 · 从过去到现在的 Reddit 股神 →" : "← swipe · Reddit legends, past to present →"}
            />
          </div>

          {/* 社区芯片 */}
          <div className="mt-9 flex flex-wrap items-center justify-center gap-2">
            {subs.slice(0, 8).map((c) => (
              <span
                key={c.id}
                className="inline-flex items-center gap-1.5 rounded-full pl-1 pr-2.5 py-1 ring-1 ring-inset ring-white/10 bg-white/[.025]"
              >
                <CommunityIcon id={c.id} size={18} className="text-[9px]" />
                <span className="text-[12px] text-neutral-300">r/{c.id}</span>
              </span>
            ))}
          </div>

          {/* Reddit 吉祥物：社区「股神小队」 */}
          <div className="relative mt-12">
            <div
              className="absolute inset-x-0 bottom-1 h-px"
              style={{ background: "linear-gradient(90deg, transparent, rgba(255,69,0,.35), transparent)" }}
            />
            <div className="relative flex items-end justify-center gap-2 sm:gap-5 flex-wrap">
              {(["a", 2, 1, "b", 3, "c", 4] as const).map((n, i, arr) => {
                const mid = (arr.length - 1) / 2;
                const d = Math.abs(i - mid);
                const h = d < 1 ? "h-20 sm:h-32" : d < 2 ? "h-[4.5rem] sm:h-28" : "h-16 sm:h-24";
                return (
                  <SnooCharacter
                    key={String(n)}
                    n={n}
                    className={`w-auto drop-shadow-[0_14px_22px_rgba(0,0,0,.22)] transition duration-300 hover:-translate-y-1.5 ${h} ${i % 2 ? "translate-y-1" : ""}`}
                  />
                );
              })}
            </div>
          </div>

          {/* CTA + 页脚 */}
          <div className="mt-10 flex flex-col items-center gap-4">
            <LocaleLink
              href="/dashboard"
              className="group inline-flex items-center justify-center gap-2 rounded-xl px-6 py-3 font-display font-bold text-white text-[15px] shadow-lg shadow-reddit/30 ring-1 ring-inset ring-white/15 hover:brightness-110 hover:-translate-y-0.5 transition"
              style={{ backgroundImage: "var(--grad-brand)" }}
            >
              {t.enterCta}
              <IconArrow className="w-4 h-4 transition group-hover:translate-x-0.5" />
            </LocaleLink>
            <div className="flex items-center justify-center gap-1.5 text-[11px] text-neutral-600">
              <RedditMark size={14} />
              <span>{t.footer}</span>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}

function Stat({ big, label }: { big: string; label: string }) {
  return (
    <div className="text-center">
      <div className="font-display font-extrabold text-cream text-[24px] leading-none tabular tracking-tight">{big}</div>
      <div className="mt-1.5 text-[11px] text-neutral-500">{label}</div>
    </div>
  );
}
