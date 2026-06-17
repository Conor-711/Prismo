"use client";

import { Avatar } from "./ui";
import { AuthorLink } from "./author/AuthorLink";
import { MarkdownLite } from "./MarkdownLite";
import { IconUpvote } from "./icons";
import { SnooMascot } from "./reddit";
import { useLocale } from "./i18n/LocaleProvider";
import { timeAgo, fmtCompact } from "@/lib/format";
import type { CommentRow } from "@/lib/queries";
import { SaveButton } from "./favorites/SaveButton";
import { commentSnapshot } from "@/lib/favorites";

// 把扁平评论（按分数降序）组装成 1~3 层讨论树：parent t3_=顶层(回帖)，t1_=回复某条评论。
// showZh=true 时，若该评论有中文译文(body_zh)则渲染中文。
export function Comments({
  comments,
  showZh = false,
  postId,
  postTitle = "",
  postTitleZh = "",
  linkable = [],
}: {
  comments: CommentRow[];
  showZh?: boolean;
  postId?: string;
  postTitle?: string;
  postTitleZh?: string;
  linkable?: string[]; // 这些评论作者「本身也发过帖」→ 有作者页，可加链接
}) {
  const { dict } = useLocale();
  const ctx = postId ? { postId, postTitle, postTitleZh } : null;
  const linkSet = new Set(linkable);
  if (!comments.length) {
    return (
      <div className="panel rounded-xl p-6 flex flex-col items-center text-center gap-2.5">
        <SnooMascot className="w-12 h-14 text-neutral-400" />
        <div className="text-sm text-neutral-500">{dict.comments.empty}</div>
      </div>
    );
  }

  const byId = new Set(comments.map((c) => c.id));
  const tree = new Map<string, CommentRow[]>();
  const roots: CommentRow[] = [];
  for (const c of comments) {
    const p = c.parent || "";
    if (p.startsWith("t1_") && byId.has(p.slice(3))) {
      const pid = p.slice(3);
      const arr = tree.get(pid) ?? [];
      arr.push(c);
      tree.set(pid, arr);
    } else {
      roots.push(c); // 顶层回帖，或父评论未抓到的回复（按顶层展示）
    }
  }
  for (const arr of tree.values()) arr.sort((a, b) => b.score - a.score);

  return (
    <div className="space-y-3">
      {roots.map((c) => (
        <CommentNode key={c.id} c={c} tree={tree} depth={0} showZh={showZh} ctx={ctx} linkSet={linkSet} />
      ))}
    </div>
  );
}

function CommentNode({
  c,
  tree,
  depth,
  showZh,
  ctx,
  linkSet,
}: {
  c: CommentRow;
  tree: Map<string, CommentRow[]>;
  depth: number;
  showZh: boolean;
  ctx: { postId: string; postTitle: string; postTitleZh: string } | null;
  linkSet: Set<string>;
}) {
  const { lang, dict } = useLocale();
  const kids = tree.get(c.id) ?? [];
  const top = c.score >= 50;
  const body = showZh && c.body_zh ? c.body_zh : c.body;
  return (
    <div>
      <div className={`rounded-xl bg-white/[.02] ring-1 ring-inset p-3.5 ${top ? "ring-reddit/25" : "ring-white/[.06]"}`}>
        <div className="flex items-center gap-2 text-xs text-neutral-500">
          {c.author && linkSet.has(c.author) ? (
            <AuthorLink name={c.author} size={18} className="text-neutral-300 font-medium" />
          ) : (
            <>
              <Avatar name={c.author || "?"} size={18} />
              <span className="text-neutral-300 font-medium">u/{c.author || "[deleted]"}</span>
            </>
          )}
          <span className="inline-flex items-center gap-0.5 text-reddit font-medium">
            <IconUpvote className="w-3 h-3" /> {fmtCompact(c.score)}
          </span>
          <span>· {timeAgo(c.created, lang)}</span>
          {top && <span className="text-[10px] font-bold metal-text m-gold">{dict.comments.topBadge}</span>}
          {ctx && (
            <span className="ml-auto shrink-0">
              <SaveButton kind="comment" refId={c.id} snapshot={commentSnapshot(ctx, c)} size="xs" />
            </span>
          )}
        </div>
        <div className="mt-1">
          <MarkdownLite md={body} />
        </div>
      </div>
      {kids.length > 0 && depth < 3 && (
        <div className="mt-3 ml-3 sm:ml-5 pl-3 border-l border-line space-y-3">
          {kids.map((k) => (
            <CommentNode key={k.id} c={k} tree={tree} depth={depth + 1} showZh={showZh} ctx={ctx} linkSet={linkSet} />
          ))}
        </div>
      )}
    </div>
  );
}
