// 收藏与追踪的客户端数据层。
// 帖子/评论收藏仍经 anon key + RLS 写 Supabase；标的/作者/叙事追踪保存在当前设备 localStorage。
// 后端 schema 见 supabase/migrations/20260612000007_user_collections.sql。
import { supabase } from "./supabase";
import type { FeedRow, CommentRow } from "./queries";

export type CollectionKind = "post" | "comment" | "subreddit" | "ticker" | "author" | "narrative";
export type LocalTrackingKind = Extract<CollectionKind, "ticker" | "author" | "narrative">;

export const LOCAL_TRACKING_STORAGE_KEY = "bsmart:tracking:v1";
export const LOCAL_TRACKING_KINDS: LocalTrackingKind[] = ["ticker", "author", "narrative"];
const LOCAL_TRACKING_KIND_SET = new Set<CollectionKind>(LOCAL_TRACKING_KINDS);
const LOCAL_TRACKING_MIGRATION_PREFIX = "bsmart:tracking:migrated:v1:";
const LOCAL_TRACKING_STORAGE_VERSION = 2;

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

export function isLocalTrackingKind(kind: CollectionKind): kind is LocalTrackingKind {
  return LOCAL_TRACKING_KIND_SET.has(kind);
}

function localStorageHandle(): Storage | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function normalizeLocalRows(value: unknown): CollectionRow[] {
  const source =
    value && typeof value === "object" && "rows" in value
      ? (value as { rows?: unknown }).rows
      : value;
  if (!Array.isArray(source)) return [];

  const byKey = new Map<string, CollectionRow>();
  for (const item of source) {
    if (!item || typeof item !== "object") continue;
    const row = item as Partial<CollectionRow>;
    if (!row.kind || !isLocalTrackingKind(row.kind) || typeof row.ref_id !== "string") continue;
    const refId = row.ref_id.trim();
    if (!refId) continue;
    const normalized: CollectionRow = {
      kind: row.kind,
      ref_id: refId,
      snapshot: row.snapshot ?? null,
      created_at:
        typeof row.created_at === "string" && row.created_at
          ? row.created_at
          : new Date(0).toISOString(),
    };
    const key = keyOf(normalized.kind, normalized.ref_id);
    const current = byKey.get(key);
    if (!current || normalized.created_at > current.created_at) byKey.set(key, normalized);
  }
  return [...byKey.values()].sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function readLocalTrackingRows(): CollectionRow[] {
  const storage = localStorageHandle();
  if (!storage) return [];
  try {
    return normalizeLocalRows(JSON.parse(storage.getItem(LOCAL_TRACKING_STORAGE_KEY) || "[]"));
  } catch {
    return [];
  }
}

function writeLocalTrackingRows(rows: CollectionRow[]): boolean {
  const storage = localStorageHandle();
  if (!storage) return false;
  try {
    storage.setItem(
      LOCAL_TRACKING_STORAGE_KEY,
      JSON.stringify({ version: LOCAL_TRACKING_STORAGE_VERSION, rows: normalizeLocalRows(rows) }),
    );
    return true;
  } catch {
    return false;
  }
}

export function loadLocalTrackingKeys(): Set<string> {
  return new Set(readLocalTrackingRows().map((row) => keyOf(row.kind, row.ref_id)));
}

export function listLocalTrackingCollection(kind: LocalTrackingKind): CollectionRow[] {
  return readLocalTrackingRows().filter((row) => row.kind === kind);
}

export function addLocalTrackingCollection(
  kind: LocalTrackingKind,
  refId: string,
  snapshot?: Snapshot,
): boolean {
  const normalizedRefId = refId.trim();
  if (!normalizedRefId) return false;
  const rows = readLocalTrackingRows();
  const key = keyOf(kind, normalizedRefId);
  if (rows.some((row) => keyOf(row.kind, row.ref_id) === key)) return true;
  return writeLocalTrackingRows([
    {
      kind,
      ref_id: normalizedRefId,
      snapshot: snapshot ?? null,
      created_at: new Date().toISOString(),
    },
    ...rows,
  ]);
}

export function removeLocalTrackingCollection(kind: LocalTrackingKind, refId: string): boolean {
  const key = keyOf(kind, refId);
  return writeLocalTrackingRows(
    readLocalTrackingRows().filter((row) => keyOf(row.kind, row.ref_id) !== key),
  );
}

export function mergeLocalTrackingCollections(rows: CollectionRow[]): boolean {
  const localRows = readLocalTrackingRows();
  const merged = normalizeLocalRows([...localRows, ...rows.filter((row) => isLocalTrackingKind(row.kind))]);
  const before = localRows.map((row) => `${keyOf(row.kind, row.ref_id)}:${row.created_at}`).join("|");
  const after = merged.map((row) => `${keyOf(row.kind, row.ref_id)}:${row.created_at}`).join("|");
  if (before === after) return true;
  return writeLocalTrackingRows(merged);
}

export function hasMigratedLocalTracking(userId: string): boolean {
  const storage = localStorageHandle();
  if (!storage) return false;
  try {
    return storage.getItem(`${LOCAL_TRACKING_MIGRATION_PREFIX}${userId}`) === "1";
  } catch {
    return false;
  }
}

export function markLocalTrackingMigrated(userId: string): boolean {
  const storage = localStorageHandle();
  if (!storage) return false;
  try {
    storage.setItem(`${LOCAL_TRACKING_MIGRATION_PREFIX}${userId}`, "1");
    return true;
  } catch {
    return false;
  }
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
