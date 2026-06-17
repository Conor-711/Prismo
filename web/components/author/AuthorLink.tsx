import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Avatar } from "@/components/ui";

// 作者名 + 头像 → 作者页的统一入口（feed 卡片 / 帖子详情 / 榜单 / 评论复用）。
export function AuthorLink({
  name,
  size = 15,
  className = "",
  showAvatar = true,
}: {
  name: string;
  size?: number;
  className?: string;
  showAvatar?: boolean;
}) {
  return (
    <LocaleLink
      href={`/author/${encodeURIComponent(name)}`}
      className={`inline-flex items-center gap-1 hover:text-reddit transition ${className}`}
    >
      {showAvatar && <Avatar name={name} size={size} />}
      <span className="truncate">u/{name}</span>
    </LocaleLink>
  );
}
