"use client";

// 全站收藏/追踪状态。挂在 AuthProvider 之内（依赖 useAuth）。
// 登录后一次性拉取用户的全部 (kind, ref_id) 建成 Set → 卡片 isSaved O(1)；toggle 乐观更新再落库。
import { createContext, useContext, useEffect, useState, useCallback } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { isAuthConfigured } from "@/lib/supabase";
import {
  loadKeys,
  addCollection,
  removeCollection,
  keyOf,
  type CollectionKind,
  type Snapshot,
} from "@/lib/favorites";

type FavState = {
  ready: boolean; // 已完成首次加载
  configured: boolean; // Supabase 是否已配置
  signedIn: boolean;
  isSaved: (kind: CollectionKind, refId: string) => boolean;
  toggle: (kind: CollectionKind, refId: string, snapshot?: Snapshot) => Promise<void>;
  countOf: (kind: CollectionKind) => number;
  version: number; // 每次变更自增，个人主页据此重新拉列表
};

const FavCtx = createContext<FavState>({
  ready: false,
  configured: false,
  signedIn: false,
  isSaved: () => false,
  toggle: async () => {},
  countOf: () => 0,
  version: 0,
});

export function FavoritesProvider({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();
  const userId = user?.id ?? null;
  const [keys, setKeys] = useState<Set<string>>(new Set());
  const [ready, setReady] = useState(false);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    let active = true;
    if (!userId || !isAuthConfigured) {
      setKeys(new Set());
      setReady(true);
      return;
    }
    setReady(false);
    loadKeys(userId).then((s) => {
      if (!active) return;
      setKeys(s);
      setReady(true);
      setVersion((v) => v + 1);
    });
    return () => {
      active = false;
    };
  }, [userId]);

  const isSaved = useCallback(
    (kind: CollectionKind, refId: string) => keys.has(keyOf(kind, refId)),
    [keys]
  );

  const countOf = useCallback(
    (kind: CollectionKind) => {
      let n = 0;
      const prefix = `${kind}:`;
      for (const k of keys) if (k.startsWith(prefix)) n++;
      return n;
    },
    [keys]
  );

  const toggle = useCallback(
    async (kind: CollectionKind, refId: string, snapshot?: Snapshot) => {
      if (!userId) return;
      const k = keyOf(kind, refId);
      const has = keys.has(k);
      // 乐观更新
      setKeys((prev) => {
        const next = new Set(prev);
        if (has) next.delete(k);
        else next.add(k);
        return next;
      });
      setVersion((v) => v + 1);
      const ok = has
        ? await removeCollection(userId, kind, refId)
        : await addCollection(userId, kind, refId, snapshot);
      if (!ok) {
        // 落库失败 → 回滚
        setKeys((prev) => {
          const next = new Set(prev);
          if (has) next.add(k);
          else next.delete(k);
          return next;
        });
        setVersion((v) => v + 1);
      }
    },
    [userId, keys]
  );

  return (
    <FavCtx.Provider
      value={{ ready, configured: isAuthConfigured, signedIn: !!userId, isSaved, toggle, countOf, version }}
    >
      {children}
    </FavCtx.Provider>
  );
}

export const useFavorites = () => useContext(FavCtx);
