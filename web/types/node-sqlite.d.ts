// Node 23 内置 node:sqlite 的最小类型声明（@types/node 20 尚未包含）。
declare module "node:sqlite" {
  export interface Statement {
    all(...params: unknown[]): any[];
    get(...params: unknown[]): any;
    run(...params: unknown[]): { changes: number; lastInsertRowid: number | bigint };
  }
  export class DatabaseSync {
    constructor(path: string, options?: { readOnly?: boolean; open?: boolean });
    prepare(sql: string): Statement;
    exec(sql: string): void;
    close(): void;
  }
}
