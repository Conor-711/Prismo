import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";

// 单例连接，直读 Python 管线产出的 SQLite 库（生产改为 Postgres 时替换此层）。
// 关键：构建期（output:export 全量预渲染）若快照缺失/无法打开，必须降级为空，
// 不能让 new DatabaseSync 抛 "unable to open database file" 把整个静态导出搞崩。
// 云端（Railway）dev.db 被 gitignore、且未跑 cloud-pull → 根本没有库文件，
// 这里以「文件不存在 → 返回 null，查询层返回空」兜底，使每页渲染空状态而非失败。
let _db: DatabaseSync | null = null;
let _tried = false; // 是否已尝试打开（失败也不重试，避免每次查询都抛/反复 stat）
let _warned = false;

function warnOnce(msg: string) {
  if (_warned) return;
  _warned = true;
  // 仅告警、不抛——本地有库时不会触发；云端无库时留一行线索。
  console.warn(`[db] ${msg}`);
}

function dbPath(): string {
  return process.env.PIPELINE_DB ?? path.join(process.cwd(), "..", "data", "dev.db");
}

// 可能返回 null（库不存在/打不开）。本仓库无人直接用裸句柄——查询一律走 all/get。
export function db(): DatabaseSync | null {
  if (_tried) return _db;
  _tried = true;
  const p = dbPath();
  if (!fs.existsSync(p)) {
    warnOnce(`snapshot not found at ${p}; rendering empty state (run \`make cloud-pull\` for data)`);
    return (_db = null);
  }
  try {
    _db = new DatabaseSync(p);
  } catch (e) {
    warnOnce(`failed to open ${p}: ${(e as Error).message}; rendering empty state`);
    _db = null;
  }
  return _db;
}

// node:sqlite 返回的是 null 原型对象；展开为普通对象，
// 以便能安全地从 Server Component 传给 Client Component。
// 任何打开/查询失败都降级为空数组——构建期缺表/缺库时产出空状态页而非崩溃。
export function all<T = any>(sql: string, ...params: unknown[]): T[] {
  const d = db();
  if (!d) return [];
  try {
    return (d.prepare(sql).all(...params) as any[]).map((r) => ({ ...r })) as T[];
  } catch (e) {
    warnOnce(`query failed (${sql.trim().split("\n")[0].slice(0, 80)}): ${(e as Error).message}`);
    return [];
  }
}

export function get<T = any>(sql: string, ...params: unknown[]): T | undefined {
  const d = db();
  if (!d) return undefined;
  try {
    const r = d.prepare(sql).get(...params) as any;
    return r ? ({ ...r } as T) : undefined;
  } catch (e) {
    warnOnce(`query failed (${sql.trim().split("\n")[0].slice(0, 80)}): ${(e as Error).message}`);
    return undefined;
  }
}

export function parseJSON<T>(v: unknown, fallback: T): T {
  if (typeof v !== "string") return fallback;
  try {
    return JSON.parse(v) as T;
  } catch {
    return fallback;
  }
}
