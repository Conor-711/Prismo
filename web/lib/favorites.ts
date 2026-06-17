// 账户系统的客户端数据层：用户私有「收藏 / 追踪」。
// 照抄 analytics.ts 的范式 —— 客户端经 anon key + RLS 直接读写 Supabase，未配置时静默降级（返回空/false）。
// 后端 schema 见 supabase/migrations/20260612000007_user_collections.sql。
import { supabase } from "./supabase";
import type { FeedRow, CommentRow } from "./queries";

export type CollectionKind = "post" | "comment" | "subreddit" | "ticker" | "author";

// 帖子/评论收藏时一并写入的「展示快照」（个人主页直接渲染，不回查 posts/comments，保持运行时不连库）。
export interface PostSnapshot {
  title: string;
  title_zh: string;
  subreddit: string;
  author: string | null;
  tldr: string;
  tldr_zh: string;
  score: number;
  created: string;
}
export interface CommentSnapshot {
  post_id: string;
  post_title: string;
  post_title_zh: string;
  body: string;
  body_zh: string;
  author: string | null;
  score: number;
  created: string;
}
export type Snapshot = PostSnapshot | CommentSnapshot | null;

export interface CollectionRow {
  kind: CollectionKind;
  ref_id: string;
  snapshot: Snapshot;
  created_at: string;
}

// 本地 Set 的 key（kind + ref_id），供卡片 isSaved 做 O(1) 判断。
export function keyOf(kind: CollectionKind, refId: string): string {
  return `${kind}:${refId}`;
}

// 拉当前用户全部 (kind, ref_id)，构建轻量 Set（不含 snapshot）。
export async function loadKeys(userId: string): Promise<Set<string>> {
  const set = new Set<string>();
  if (!supabase) return set;
  try {
    const { data, error } = await supabase
      .from("user_collections")
      .select("kind, ref_id")
      .eq("user_id", userId);
    if (error || !data) return set;
    for (const r of data as { kind: CollectionKind; ref_id: string }[]) set.add(keyOf(r.kind, r.ref_id));
  } catch {
    /* 网络/未配置 → 空集 */
  }
  return set;
}

// 拉某一类的完整行（含 snapshot），供个人主页渲染。
export async function listCollection(userId: string, kind: CollectionKind): Promise<CollectionRow[]> {
  if (!supabase) return [];
  try {
    const { data, error } = await supabase
      .from("user_collections")
      .select("kind, ref_id, snapshot, created_at")
      .eq("user_id", userId)
      .eq("kind", kind)
      .order("created_at", { ascending: false });
    if (error || !data) return [];
    return data as CollectionRow[];
  } catch {
    return [];
  }
}

// 添加（幂等：已存在则不动，靠 PK ON CONFLICT DO NOTHING）。
export async function addCollection(
  userId: string,
  kind: CollectionKind,
  refId: string,
  snapshot?: Snapshot
): Promise<boolean> {
  if (!supabase) return false;
  try {
    const { error } = await supabase
      .from("user_collections")
      .upsert(
        { user_id: userId, kind, ref_id: refId, snapshot: snapshot ?? null },
        { onConflict: "user_id,kind,ref_id", ignoreDuplicates: true }
      );
    return !error;
  } catch {
    return false;
  }
}

// 移除。
export async function removeCollection(userId: string, kind: CollectionKind, refId: string): Promise<boolean> {
  if (!supabase) return false;
  try {
    const { error } = await supabase
      .from("user_collections")
      .delete()
      .eq("user_id", userId)
      .eq("kind", kind)
      .eq("ref_id", refId);
    return !error;
  } catch {
    return false;
  }
}

// ---------- 快照构造助手（写入端用；纯函数，server / client 皆可调用） ----------
export function postSnapshot(p: {
  title: string;
  title_zh?: string;
  subreddit: string;
  author?: string | null;
  tldr?: string;
  tldr_zh?: string;
  score?: number;
  created?: string;
}): PostSnapshot {
  return {
    title: p.title,
    title_zh: p.title_zh || "",
    subreddit: p.subreddit,
    author: p.author ?? null,
    tldr: p.tldr || "",
    tldr_zh: p.tldr_zh || "",
    score: p.score ?? 0,
    created: p.created || "",
  };
}

export function postSnapshotFromFeed(p: FeedRow): PostSnapshot {
  return postSnapshot({
    title: p.title,
    title_zh: p.title_zh,
    subreddit: p.subreddit,
    author: p.author,
    tldr: p.tldr,
    tldr_zh: p.tldr_zh,
    score: p.score,
    created: p.created,
  });
}

export function commentSnapshot(
  ctx: { postId: string; postTitle?: string; postTitleZh?: string },
  c: CommentRow
): CommentSnapshot {
  return {
    post_id: ctx.postId,
    post_title: ctx.postTitle || "",
    post_title_zh: ctx.postTitleZh || "",
    body: c.body,
    body_zh: c.body_zh || "",
    author: c.author ?? null,
    score: c.score ?? 0,
    created: c.created || "",
  };
}
