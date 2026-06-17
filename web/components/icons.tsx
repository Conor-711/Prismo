type P = { className?: string };
const base = "none";
function S({ className = "w-[18px] h-[18px]", children }: P & { children: React.ReactNode }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill={base} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  );
}
export const IconGrid = (p: P) => <S {...p}><rect x="3" y="3" width="7" height="9" rx="1.5" /><rect x="14" y="3" width="7" height="5" rx="1.5" /><rect x="14" y="12" width="7" height="9" rx="1.5" /><rect x="3" y="16" width="7" height="5" rx="1.5" /></S>;
export const IconTrend = (p: P) => <S {...p}><path d="M3 17l6-6 4 4 8-8" /><path d="M17 7h4v4" /></S>;
export const IconLayers = (p: P) => <S {...p}><path d="M12 3l9 5-9 5-9-5 9-5z" /><path d="M3 13l9 5 9-5" /></S>;
export const IconList = (p: P) => <S {...p}><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01" /></S>;
export const IconTrophy = (p: P) => <S {...p}><path d="M6 4h12v3a6 6 0 0 1-12 0V4z" /><path d="M6 6H4a2 2 0 0 0 2 2M18 6h2a2 2 0 0 1-2 2M9 18h6M10 18v-3M14 18v-3" /></S>;
export const IconDoc = (p: P) => <S {...p}><path d="M7 3h7l5 5v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z" /><path d="M14 3v5h5M9 13h6M9 17h6" /></S>;
export const IconSearch = (p: P) => <S {...p}><circle cx="11" cy="11" r="7" /><path d="M21 21l-4-4" /></S>;
export const IconPulse = (p: P) => <S {...p}><path d="M3 12h4l2-7 4 14 2-7h6" /></S>;
export const IconArrow = (p: P) => <S {...p}><path d="M5 12h14M13 6l6 6-6 6" /></S>;
export const IconFlame = (p: P) => <S {...p}><path d="M12 3c1 4 4 5 4 9a4 4 0 0 1-8 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3 0-5-2-7z" /></S>;
// 中概·港股入口图标：¥ 置于圆环内
export const IconYuan = (p: P) => <S {...p}><circle cx="12" cy="12" r="9" /><path d="M9 8l3 4 3-4M12 12v5M9.5 13.5h5M9.5 16h5" /></S>;
// 折叠箭头（向下）；展开态由 group-open:rotate-180 翻转
export const IconChevron = (p: P) => <S {...p}><path d="M6 9l6 6 6-6" /></S>;
// Reddit 投票箭头（实心）+ 评论气泡
export const IconUpvote = ({ className = "w-5 h-5" }: P) => (
  <svg viewBox="0 0 24 24" className={className} fill="currentColor"><path d="M12 3.6l8.2 9.2H15v7.6H9v-7.6H3.8z" /></svg>
);
export const IconDownvote = ({ className = "w-5 h-5" }: P) => (
  <svg viewBox="0 0 24 24" className={className} fill="currentColor"><path d="M12 20.4L3.8 11.2H9V3.6h6v7.6h5.2z" /></svg>
);
export const IconComment = (p: P) => <S {...p}><path d="M21 11.5a8 8 0 0 1-11.7 7.1L4 20l1.4-5.1A8 8 0 1 1 21 11.5z" /></S>;
// 品牌波浪（呼应 logo 的橙色波纹）
export const IconWaves = ({ className = "w-6 h-4" }: P) => (
  <svg viewBox="0 0 34 16" className={className} fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round">
    <path d="M2 4.5c4-4 7.5 4 11.5 0s7.5-4 11.5 0 5.5 2 7 1" />
    <path d="M2 11.5c4-4 7.5 4 11.5 0s7.5-4 11.5 0 5.5 2 7 1" />
  </svg>
);
