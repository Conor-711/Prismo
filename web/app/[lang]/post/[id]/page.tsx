import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { notFound } from "next/navigation";
import { SubredditChip, SentPill, TickerChip, ThemeTag } from "@/components/ui";
import { AuthorLink } from "@/components/author/AuthorLink";
import { MarkdownLite } from "@/components/MarkdownLite";
import { Comments } from "@/components/Comments";
import { TranslateToggle } from "@/components/TranslateToggle";
import { ShareBar } from "@/components/ShareBar";
import { SaveButton } from "@/components/favorites/SaveButton";
import { postSnapshot } from "@/lib/favorites";
import { IconUpvote, IconComment, IconDoc, IconList } from "@/components/icons";
import { timeAgo, fmtCompact, fmtInt, REDDIT } from "@/lib/format";
import { getPostDetail, getAllPostIds, linkableAuthors } from "@/lib/queries";
import { getDictionary, isLocale, defaultLocale, type Locale, type Dictionary } from "@/lib/i18n";
import { SITE_URL, OG_IMAGE } from "@/lib/site";

export const dynamicParams = false;

export function generateStaticParams() {
  return getAllPostIds().map((id) => ({ id }));
}

// 帖子页独立 OG / Twitter 卡片：分享到社媒展开富预览，带来免费流量。
export function generateMetadata({ params }: { params: { lang: string; id: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const d = getPostDetail(params.id);
  if (!d) return {};
  const zh = lang === "zh";
  const rawTitle = (zh && d.post.title_zh) ? d.post.title_zh : d.post.title;
  const title = `${rawTitle.slice(0, 90)} | redditalpha`;
  const desc =
    (zh && d.analysis?.tldr_zh ? d.analysis.tldr_zh : d.analysis?.tldr) ||
    (zh ? "Reddit 财经社区的真实讨论与多空提炼。" : "Real discussion and distilled bull/bear takes from Reddit.");
  const url = `${SITE_URL}/${lang}/post/${params.id}/`;
  return {
    title,
    description: desc,
    alternates: { canonical: url },
    openGraph: { title, description: desc, url, siteName: "redditalpha", type: "article", images: [{ url: OG_IMAGE, width: 1200, height: 630 }] },
    twitter: { card: "summary_large_image", title, description: desc, images: [OG_IMAGE] },
  };
}

export default function PostPage({ params }: { params: { lang: string; id: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).post;
  const sh = getDictionary(lang).share;
  const d = getPostDetail(params.id);
  if (!d) notFound();
  const { post, analysis, comments } = d;
  // 评论区作者：只有「本身也发过帖」的作者才有作者页 → 据此决定是否加链接（其余纯文本，不 404）。
  const commentLinkable = linkableAuthors(comments.map((c) => c.author).filter(Boolean) as string[]);
  const hasAI = analysis && (analysis.tldr || analysis.bull.length > 0 || analysis.bear.length > 0);
  const isZh = lang === "zh";
  // 标题 + 摘要直接给中文；正文 / 评论用「译文 / 原文」切换按钮。
  const postTitle = isZh && post.title_zh ? post.title_zh : post.title;
  const aiTldr = isZh && analysis?.tldr_zh ? analysis.tldr_zh : analysis?.tldr ?? "";
  const aiBull = isZh && analysis?.bull_zh.length ? analysis.bull_zh : analysis?.bull ?? [];
  const aiBear = isZh && analysis?.bear_zh.length ? analysis.bear_zh : analysis?.bear ?? [];

  return (
    // 无卡片：各模块在更宽的阅读栏里自然分布，靠区块标题 + 分隔线区分，正文留足宽度便于阅读。
    <article className="max-w-5xl mx-auto">
      <div className="flex items-center justify-between gap-3 mb-6">
        <LocaleLink href="/dashboard" className="text-xs text-neutral-500 hover:text-reddit transition">{t.back}</LocaleLink>
        <div className="flex items-center gap-2">
          <SaveButton
            kind="post"
            refId={post.id}
            snapshot={postSnapshot({ title: post.title, title_zh: post.title_zh, subreddit: post.subreddit, author: post.author, tldr: analysis?.tldr, tldr_zh: analysis?.tldr_zh, score: post.score, created: post.created })}
          />
          <ShareBar path={`/${lang}/post/${post.id}`} text={sh.postText.replace("{s}", postTitle)} ticker={analysis?.tickers?.[0]?.ticker} />
        </div>
      </div>

      {/* ① 标题 / 帖头 —— masthead（投票轨 + 元信息 + 标题），底部分隔线 */}
      <header className="flex gap-4 sm:gap-5 pb-7 border-b border-line">
        <div className="flex flex-col items-center gap-0.5 shrink-0 w-11">
          <IconUpvote className="w-5 h-5 text-reddit" />
          <span className="font-mono font-bold text-reddit tabular leading-none">{fmtCompact(post.score)}</span>
          {post.upvote_ratio > 0 && (
            <span className="text-[10px] text-neutral-500 mt-0.5">{Math.round(post.upvote_ratio * 100)}%</span>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-neutral-500">
            <SubredditChip name={post.subreddit} />
            <SaveButton kind="subreddit" refId={post.subreddit} variant="follow" size="xs" />
            {post.author && (
              <>
                <span className="inline-flex items-center gap-1">
                  · <AuthorLink name={post.author} size={15} />
                </span>
                <SaveButton kind="author" refId={post.author} variant="follow" size="xs" />
              </>
            )}
            <span>· {timeAgo(post.created, lang)}</span>
            {post.flair && (
              <span className="px-1.5 py-0.5 rounded-full bg-white/[.06] text-neutral-400 text-[10px] font-medium">{post.flair}</span>
            )}
            <span className="inline-flex items-center gap-1">
              <IconComment className="w-3.5 h-3.5" /> {fmtInt(post.comments)}
            </span>
          </div>
          <h1 className="mt-2.5 font-display font-extrabold text-cream text-[26px] sm:text-[30px] leading-tight tracking-tight">
            {postTitle}
          </h1>
        </div>
      </header>

      {/* ② 投资者摘要（结论先行）—— 无卡片，区块标题 + 内容 */}
      {hasAI && (
        <section className="pt-8">
          <SectionHead accent="reddit" icon={<IconList className="w-4 h-4" />} title={t.aiSummary} right={analysis!.stance ? <SentPill stance={analysis!.stance} /> : null} />
          {aiTldr && <p className="text-[17px] text-cream leading-relaxed">{aiTldr}</p>}
          {(aiBull.length > 0 || aiBear.length > 0) && (
            <div className="mt-5 grid sm:grid-cols-2 gap-x-8 gap-y-3">
              <PointList t={t} tone="bull" items={aiBull} />
              <PointList t={t} tone="bear" items={aiBear} />
            </div>
          )}
          {(analysis!.tickers.length > 0 || analysis!.themes.length > 0) && (
            <div className="mt-5 flex flex-wrap items-center gap-1.5">
              {analysis!.tickers.slice(0, 8).map((tk) => (
                <TickerChip key={tk.ticker} ticker={tk.ticker} size="xs" />
              ))}
              {analysis!.themes.slice(0, 6).map((th) => (
                <ThemeTag key={th}>{th}</ThemeTag>
              ))}
            </div>
          )}
        </section>
      )}

      {/* ③ 帖子正文 —— 阅读区，留足宽度 */}
      <section className="pt-8">
        {post.selftext ? (
          <>
            <SectionHead accent="gold" icon={<IconDoc className="w-4 h-4" />} title={t.bodyTitle} />
            {/* 正文阅读区：一层柔和的浅色底，把正文从页面背景里托起来，提升可读性 */}
            <div className="rounded-2xl bg-white/[.025] ring-1 ring-inset ring-white/[.06] px-5 py-6 sm:px-8 sm:py-7 text-[16px] leading-[1.85]">
              <TranslateToggle
                hasZh={!!post.selftext_zh}
                original={<MarkdownLite md={post.selftext_fmt || post.selftext} size="base" />}
                zh={<MarkdownLite md={post.selftext_zh} size="base" />}
              />
            </div>
          </>
        ) : (
          <div className="text-sm text-neutral-500">
            {t.noSelftext}
            {post.permalink && (
              <a href={`${REDDIT}${post.permalink}`} target="_blank" rel="noreferrer" className="ml-1 text-reddit hover:underline">
                {t.viewLink}
              </a>
            )}
          </div>
        )}
      </section>

      {/* ④ 讨论 / 评论 —— 社区 */}
      <section className="pt-8">
        <SectionHead
          accent="bull"
          icon={<IconComment className="w-4 h-4" />}
          title={t.discussion}
          right={comments.length > 0 ? <span className="text-xs text-neutral-500">{comments.length} {t.commentsCount}</span> : null}
        />
        <TranslateToggle
          hasZh={comments.some((c) => !!c.body_zh)}
          original={<Comments comments={comments} showZh={false} postId={post.id} postTitle={post.title} postTitleZh={post.title_zh} linkable={commentLinkable} />}
          zh={<Comments comments={comments} showZh={true} postId={post.id} postTitle={post.title} postTitleZh={post.title_zh} linkable={commentLinkable} />}
        />
      </section>

      {/* 原帖（次要入口） */}
      <div className="pt-10 pb-4 text-center">
        <a href={`${REDDIT}${post.permalink}`} target="_blank" rel="noreferrer" className="text-xs text-neutral-500 hover:text-reddit transition">
          {t.viewOnReddit}
        </a>
      </div>
    </article>
  );
}

// 区块标题：彩色图标徽标 + 标题 + 可选右侧（立场 / 计数），底部一条细分隔线——替代原卡片边框。
function SectionHead({
  accent, icon, title, right,
}: { accent: "reddit" | "gold" | "bull"; icon: React.ReactNode; title: string; right?: React.ReactNode }) {
  const badge =
    accent === "reddit" ? "bg-reddit/15 text-reddit"
    : accent === "gold" ? "bg-gold/15 text-gold"
    : "bg-bull/15 text-bull";
  const border =
    accent === "reddit" ? "border-reddit/20"
    : accent === "gold" ? "border-gold/20"
    : "border-bull/20";
  return (
    <div className={`flex items-center gap-2.5 pb-3 mb-4 border-b ${border}`}>
      <span className={`grid place-items-center w-7 h-7 rounded-lg shrink-0 ${badge}`}>{icon}</span>
      <span className="font-display font-bold text-cream text-[15px]">{title}</span>
      {right && <span className="ml-auto shrink-0">{right}</span>}
    </div>
  );
}

function PointList({ t, tone, items }: { t: Dictionary["post"]; tone: "bull" | "bear"; items: string[] }) {
  if (!items.length) return null;
  const color = tone === "bull" ? "text-bull" : "text-bear";
  const dot = tone === "bull" ? "bg-bull" : "bg-bear";
  return (
    <div>
      <div className={`text-xs font-semibold ${color} mb-1.5`}>{tone === "bull" ? t.bullPoints : t.bearPoints}</div>
      <ul className="space-y-1.5">
        {items.map((p, i) => (
          <li key={i} className="flex gap-2 text-sm text-neutral-300 leading-relaxed">
            <span className={`mt-1.5 w-1.5 h-1.5 rounded-full ${dot} shrink-0`} />
            <span>{p}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
