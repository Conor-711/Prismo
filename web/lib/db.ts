import { DatabaseSync } from "node:sqlite";
import path from "node:path";

// 单例连接，直读 Python 管线产出的 SQLite 库（生产改为 Postgres 时替换此层）。
let _db: DatabaseSync | null = null;

export function db(): DatabaseSync {
  if (!_db) {
    const p =
      process.env.PIPELINE_DB ?? path.join(process.cwd(), "..", "data", "dev.db");
    _db = new DatabaseSync(p);
  }
  return _db;
}

// node:sqlite 返回的是 null 原型对象；展开为普通对象，
// 以便能安全地从 Server Component 传给 Client Component。
export function all<T = any>(sql: string, ...params: unknown[]): T[] {
  return (db().prepare(sql).all(...params) as any[]).map((r) => ({ ...r })) as T[];
}

export function get<T = any>(sql: string, ...params: unknown[]): T | undefined {
  const r = db().prepare(sql).get(...params) as any;
  return r ? ({ ...r } as T) : undefined;
}

export function parseJSON<T>(v: unknown, fallback: T): T {
  if (typeof v !== "string") return fallback;
  try {
    return JSON.parse(v) as T;
  } catch {
    return fallback;
  }
}
