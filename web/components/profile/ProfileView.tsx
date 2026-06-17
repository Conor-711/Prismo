"use client";

// 个人主页（私密空间）：仅本人可见的收藏与追踪。
// 未登录 → 跳 /login（沿用 account 页门禁范式）。数据全部客户端从 Supabase 拉取（user_collections）。
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang, type Locale, type Dictionary } from "@/lib/i18n";
import { useAuth } from "@/components/auth/AuthProvider";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { SaveButton } from "@/components/favorites/SaveButton";
import { displayName, avatarUrl } from "@/lib/auth";
import {
  listCollection,
  type CollectionKind,
  type CollectionRow,
  type PostSnapshot,
  type CommentSnapshot,
} from "@/lib/favorites";
import { Panel, SubredditChip, TickerChip, Avatar } from "@/components/ui";
import { CommunityIcon } from "@/components/CommunityIcon";
import { timeAgo } from "@/lib/format";

const TAB_KINDS: CollectionKind[] = ["post", "comment", "subreddit", "ticker", "author"];

export function ProfileView() {
  const { lang, dict } = useLocale();
  const p = dict.profile;
  const { user, loading } = useAuth();
  const { version, countOf } = useFavorites();
  const router = useRouter();
  const [kind, setKind] = useState<CollectionKind>("post");
  const [rows, setRows] = useState<CollectionRow[]>([]);
  const [busy, setBusy] = useState(true);

  // 门禁：未登录跳登录页
  useEffect(() => {
    if (!loading && !user) router.replace(withLang(lang, "/login"));
  }, [loading, user, router, lang]);

  // 当前标签的数据（user / kind / version 任一变化都重拉，保证取消收藏后即时刷新）
  useEffect(() => {
    let active = true;
    if (!user) {
      setRows([]);
      setBusy(false);
      return;
    }
    setBusy(true);
    listCollection(user.id, kind).then((r) => {
      if (!active) return;
      setRows(r);
      setBusy(false);
    });
    return () => {
      active = false;
    };
  }, [user, kind, version]);

  if (loading || !user) {
    return <div className="py-24 text-center text-sm text-neutral-500">{p.loading}</div>;
  }

  const name = displayName(user);
  const avatar = avatarUrl(user);

  const label = (k: CollectionKind) =>
    k === "post" ? p.tabPosts
    : k === "comment" ? p.tabComments
    : k === "subreddit" ? p.tabCommunities
    : k === "ticker" ? p.tabTickers
    : p.tabAuthors;
  const emptyText = (k: CollectionKind) =>
    k === "post" ? p.emptyPosts
    : k === "comment" ? p.emptyComments
    : k === "subreddit" ? p.emptyCommunities
    : k === "ticker" ? p.emptyTickers
    : p.emptyAuthors;

  const statLabel = (k: CollectionKind) =>
    k === "post" ? p.statPosts
    : k === "comment" ? p.statComments
    : k === "subreddit" ? p.statCommunities
    : k === "ticker" ? p.statTickers
    : p.statAuthors;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <header>
        <h1 className="font-display font-extrabold text-cream text-2xl sm:text-[28px] tracking-tight">{p.title}</h1>
        <p className="mt-1 text-sm text-neutral-500">{p.subtitle}</p>
      </header>

      {/* 身份卡：顶部品牌渐变条 + 大头像 + 信息 */}
      <Panel className="overflow-hidden">
        <div className="h-1.5 bg-gradient-to-r from-reddit via-reddit/70 to-bull/70" />
        <div className="p-5 flex items-center gap-4">
          {avatar ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={avatar} alt={name} className="w-16 h-16 rounded-full object-cover ring-2 ring-reddit/30" referrerPolicy="no-referrer" />
          ) : (
            <span className="grid place-items-center w-16 h-16 rounded-full bg-reddit text-white text-2xl font-bold ring-2 ring-reddit/30">
              {(name.charAt(0) || "U").toUpperCase()}
            </span>
          )}
          <div className="min-w-0 flex-1">
            <div className="font-display font-bold text-cream text-lg truncate">{name}</div>
            <div className="text-sm text-neutral-500 truncate">{user.email}</div>
          </div>
          <LocaleLink href="/account" className="text-xs font-medium text-neutral-400 hover:text-reddit transition shrink-0">
            {p.accountSettings} →
          </LocaleLink>
        </div>
      </Panel>

      {/* 收藏总览：5 张统计卡，同时作为分区切换 */}
      <section>
        <div className="flex items-center gap-2 mb-2.5">
          <span className="w-[3px] h-3.5 rounded-full bg-reddit shrink-0" />
          <h2 className="font-display text-[13px] font-bold text-cream tracking-tight">{p.overview}</h2>
        </div>
        <div className="grid grid-cols-3 sm:grid-cols-5 gap-2">
          {TAB_KINDS.map((k) => {
            const active = k === kind;
            const n = countOf(k);
            return (
              <button
                key={k}
                onClick={() => setKind(k)}
                aria-pressed={active}
                className={`rounded-xl px-3 py-3 text-left ring-1 ring-inset transition ${
                  active
                    ? "bg-reddit text-white ring-reddit shadow-sm"
                    : "bg-card ring-line hover:ring-reddit/40 hover:-translate-y-0.5"
                }`}
              >
                <div className={`font-display text-2xl font-extrabold tabular leading-none ${active ? "text-white" : "text-cream"}`}>{n}</div>
                <div className={`mt-1.5 text-xs font-medium ${active ? "text-white/85" : "text-neutral-500"}`}>{statLabel(k)}</div>
              </button>
            );
          })}
        </div>
      </section>

      {/* 当前分区 */}
      <section className="space-y-3">
        <div className="flex items-baseline gap-2">
          <h3 className="font-display text-sm font-bold text-cream">{label(kind)}</h3>
          {!busy && rows.length > 0 && <span className="text-xs text-neutral-500 tabular">{rows.length}</span>}
        </div>

        {busy ? (
          <div className="py-16 text-center text-sm text-neutral-500">{p.loading}</div>
        ) : rows.length === 0 ? (
          <Panel className="py-14 px-6 flex flex-col items-center text-center gap-3">
            <span className="grid place-items-center w-12 h-12 rounded-full bg-reddit/10 text-reddit">
              <EmptyIcon kind={kind} />
            </span>
            <p className="text-sm text-neutral-500 max-w-xs leading-relaxed">{emptyText(kind)}</p>
            <LocaleLink
              href="/lab/global-retail"
              className="mt-1 inline-flex items-center gap-1 rounded-full bg-reddit text-white text-xs font-semibold px-3.5 py-1.5 hover:bg-reddit/90 transition"
            >
              {p.goDashboard} →
            </LocaleLink>
          </Panel>
        ) : (
          <div className="space-y-2.5">
            {rows.map((r) => (
              <CollectionItem key={`${r.kind}:${r.ref_id}`} row={r} lang={lang} p={p} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function EmptyIcon({ kind }: { kind: CollectionKind }) {
  const follow = kind === "subreddit" || kind === "ticker" || kind === "author";
  return (
    <svg viewBox="0 0 24 24" className="w-6 h-6" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      {follow ? <path d="M12 5v14M5 12h14" /> : <path d="M6 4h12a1 1 0 0 1 1 1v15l-7-4-7 4V5a1 1 0 0 1 1-1z" />}
    </svg>
  );
}

function CollectionItem({ row, lang, p }: { row: CollectionRow; lang: Locale; p: Dictionary["profile"] }) {
  const isZh = lang === "zh";

  if (row.kind === "post") {
    const s = (row.snapshot ?? {}) as PostSnapshot;
    const title = (isZh && s.title_zh ? s.title_zh : s.title) || row.ref_id;
    const tldr = isZh && s.tldr_zh ? s.tldr_zh : s.tldr;
    return (
      <Panel className="p-3.5 flex gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-1.5 text-xs text-neutral-500">
            {s.subreddit && <SubredditChip name={s.subreddit} />}
            {s.author && <span className="truncate">· u/{s.author}</span>}
            {s.created && <span>· {timeAgo(s.created, lang)}</span>}
          </div>
          <LocaleLink href={`/post/${row.ref_id}`} className="mt-1 block font-medium text-cream hover:text-reddit transition leading-snug">
            {title}
          </LocaleLink>
          {tldr && <p className="mt-1 text-sm text-neutral-400 line-clamp-2 leading-relaxed">{tldr}</p>}
        </div>
        <SaveButton kind="post" refId={row.ref_id} size="xs" className="shrink-0" />
      </Panel>
    );
  }

  if (row.kind === "comment") {
    const s = (row.snapshot ?? {}) as CommentSnapshot;
    const body = isZh && s.body_zh ? s.body_zh : s.body;
    const ptitle = (isZh && s.post_title_zh ? s.post_title_zh : s.post_title) || s.post_id;
    return (
      <Panel className="p-3.5 flex gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 text-xs text-neutral-500">
            {s.author && <span className="truncate">u/{s.author}</span>}
            {s.created && <span>· {timeAgo(s.created, lang)}</span>}
          </div>
          <p className="mt-1 text-sm text-neutral-300 line-clamp-3 leading-relaxed">{body}</p>
          {s.post_id && (
            <LocaleLink href={`/post/${s.post_id}`} className="mt-1 inline-block text-xs text-neutral-500 hover:text-reddit transition truncate max-w-full">
              ↳ {ptitle}
            </LocaleLink>
          )}
        </div>
        <SaveButton kind="comment" refId={row.ref_id} size="xs" className="shrink-0" />
      </Panel>
    );
  }

  if (row.kind === "subreddit") {
    return (
      <Panel className="p-3 flex items-center gap-3">
        <CommunityIcon id={row.ref_id} size={24} className="text-[11px]" />
        <span className="text-sm text-neutral-200 flex-1 truncate">r/{row.ref_id}</span>
        <a
          href={`https://www.reddit.com/r/${row.ref_id}`}
          target="_blank"
          rel="noreferrer noopener"
          className="text-xs text-neutral-600 hover:text-reddit transition shrink-0"
        >
          {p.viewOnReddit} ↗
        </a>
        <SaveButton kind="subreddit" refId={row.ref_id} variant="follow" size="xs" />
      </Panel>
    );
  }

  if (row.kind === "ticker") {
    return (
      <Panel className="p-3 flex items-center gap-3">
        <TickerChip ticker={row.ref_id} />
        <span className="flex-1" />
        <SaveButton kind="ticker" refId={row.ref_id} variant="follow" size="xs" />
      </Panel>
    );
  }

  // author
  return (
    <Panel className="p-3 flex items-center gap-3">
      <Avatar name={row.ref_id} size={26} />
      <span className="text-sm text-neutral-200 flex-1 truncate">u/{row.ref_id}</span>
      <SaveButton kind="author" refId={row.ref_id} variant="follow" size="xs" />
    </Panel>
  );
}
