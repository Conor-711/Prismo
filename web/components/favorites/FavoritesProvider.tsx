"use client";

// 全站收藏/追踪状态。追踪始终读取设备缓存；登录后再合并账户收藏。
import { createContext, useContext, useEffect, useState, useCallback } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { isAuthConfigured } from "@/lib/supabase";
import {
  loadKeys,
  listCollection,
  addCollection,
  removeCollection,
  loadLocalTrackingKeys,
  addLocalTrackingCollection,
  removeLocalTrackingCollection,
  mergeLocalTrackingCollections,
  hasMigratedLocalTracking,
  markLocalTrackingMigrated,
  isLocalTrackingKind,
  LOCAL_TRACKING_KINDS,
  LOCAL_TRACKING_STORAGE_KEY,
  keyOf,
  type CollectionKind,
  type Snapshot,
} from "@/lib/favorites";

type FavState = {
  ready: boolean; // 已完成首次加载
  configured: boolean; // 本地追踪能力是否可用
  signedIn: boolean;
  isSaved: (kind: CollectionKind, refId: string) => boolean;
  toggle: (kind: CollectionKind, refId: string, snapshot?: Snapshot) => Promise<void>;
  countOf: (kind: CollectionKind) => number;
  version: number; // 每次变更自增，个人主页据此重新拉列表
};

const FavCtx = createContext<FavState>({
  ready: false,
  configured: true,
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
    setKeys(loadLocalTrackingKeys());
    setReady(true);
    if (!userId || !isAuthConfigured) return;

    const shouldMigrateTracking = !hasMigratedLocalTracking(userId);
    Promise.all([
      loadKeys(userId),
      shouldMigrateTracking
        ? Promise.all(LOCAL_TRACKING_KINDS.map((kind) => listCollection(userId, kind)))
        : Promise.resolve([]),
    ]).then(([remoteKeys, remoteTracking]) => {
      if (!active) return;
      if (shouldMigrateTracking && mergeLocalTrackingCollections(remoteTracking.flat())) {
        markLocalTrackingMigrated(userId);
      }
      const next = loadLocalTrackingKeys();
      for (const key of remoteKeys) {
        const separator = key.indexOf(":");
        const kind = key.slice(0, separator) as CollectionKind;
        if (!isLocalTrackingKind(kind)) next.add(key);
      }
      setKeys(next);
      setVersion((v) => v + 1);
    });
    return () => {
      active = false;
    };
  }, [userId]);

  useEffect(() => {
    const syncFromStorage = (event: StorageEvent) => {
      if (event.key !== LOCAL_TRACKING_STORAGE_KEY) return;
      setKeys((previous) => {
        const next = loadLocalTrackingKeys();
        for (const key of previous) {
          const separator = key.indexOf(":");
          const kind = key.slice(0, separator) as CollectionKind;
          if (!isLocalTrackingKind(kind)) next.add(key);
        }
        return next;
      });
      setVersion((v) => v + 1);
    };
    window.addEventListener("storage", syncFromStorage);
    return () => window.removeEventListener("storage", syncFromStorage);
  }, []);

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
      let ok = false;
      if (isLocalTrackingKind(kind)) {
        ok = has
          ? removeLocalTrackingCollection(kind, refId)
          : addLocalTrackingCollection(kind, refId, snapshot);
      } else if (userId) {
        ok = has
          ? await removeCollection(userId, kind, refId)
          : await addCollection(userId, kind, refId, snapshot);
      }
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
      value={{ ready, configured: true, signedIn: !!userId, isSaved, toggle, countOf, version }}
    >
      {children}
    </FavCtx.Provider>
  );
}

export const useFavorites = () => useContext(FavCtx);
