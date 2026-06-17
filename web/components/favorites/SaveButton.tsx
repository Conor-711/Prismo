"use client";

// 通用收藏/追踪按钮。两种形态：
//   variant="bookmark" → 图标书签（帖子/评论收藏）
//   variant="follow"   → 带标签的胶囊（社区/标的/作者追踪）
// 未配置 Supabase → 不渲染（静默降级）；未登录 → 点击跳 /login。
import { useRouter } from "next/navigation";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { useFavorites } from "./FavoritesProvider";
import type { CollectionKind, Snapshot } from "@/lib/favorites";

export function SaveButton({
  kind,
  refId,
  snapshot,
  variant = "bookmark",
  size = "sm",
  className = "",
}: {
  kind: CollectionKind;
  refId: string;
  snapshot?: Snapshot;
  variant?: "bookmark" | "follow";
  size?: "sm" | "xs";
  className?: string;
}) {
  const { lang, dict } = useLocale();
  const t = dict.favorites;
  const router = useRouter();
  const { configured, signedIn, isSaved, toggle } = useFavorites();

  if (!configured) return null;

  const saved = isSaved(kind, refId);

  const onClick = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (!signedIn) {
      router.push(withLang(lang, "/login"));
      return;
    }
    void toggle(kind, refId, snapshot);
  };

  // 两种形态统一为「带文字标签的胶囊」：静止态也有可见底色 + 描边（不再是隐形灰图标），
  // 悬停高亮品牌橙，已收藏 / 已追踪填充橙色。整体放大以更醒目。
  const isFollow = variant === "follow";
  const label = saved ? (isFollow ? t.following : t.saved) : isFollow ? t.follow : t.save;
  const pad =
    size === "xs"
      ? "text-[11px] px-2 py-1 gap-1"
      : "text-[13px] px-3 py-1.5 gap-1.5";
  const ic = size === "xs" ? "w-3.5 h-3.5" : "w-4 h-4";
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={saved}
      title={label}
      className={`inline-flex items-center self-center rounded-full font-semibold ring-1 ring-inset transition ${pad} ${
        saved
          ? "bg-reddit text-white ring-reddit shadow-sm hover:bg-reddit/90"
          : "bg-reddit/10 text-reddit ring-reddit/40 hover:bg-reddit/20 hover:ring-reddit/60"
      } ${className}`}
    >
      {isFollow ? (
        saved ? <IconCheck className={ic} /> : <IconPlus className={ic} />
      ) : (
        <IconBookmark filled={saved} className={ic} />
      )}
      {label}
    </button>
  );
}

function IconBookmark({ filled, className = "" }: { filled?: boolean; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M6 4h12a1 1 0 0 1 1 1v15l-7-4-7 4V5a1 1 0 0 1 1-1z" />
    </svg>
  );
}
function IconPlus({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}
function IconCheck({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 6 9 17l-5-5" />
    </svg>
  );
}
