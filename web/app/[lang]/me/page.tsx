import { ProfileView } from "@/components/profile/ProfileView";

// 个人主页（私密空间）。页面是薄壳，全部逻辑/取数在客户端的 ProfileView 里完成，
// 与静态导出兼容（[lang] 的 generateStaticParams 由 layout 提供）。
export default function MePage() {
  return <ProfileView />;
}
