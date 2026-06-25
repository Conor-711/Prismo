import type { Metadata } from "next";
import { PageHeader } from "@/components/ui";
import { InvestorBoardView } from "@/components/prismo/InvestorBoard";
import { getInvestorBoard } from "@/lib/investorQueries";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";

// 投资者榜单（X / YouTube / Reddit / 雪球）。薄壳：服务端把四平台榜单烤进去，过滤在客户端。
// [lang] 的 generateStaticParams 由 layout 提供，与 output:export 兼容。
export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const t = getDictionary(params.lang).investors;
  return { title: `${t.title} · Prismo`, description: t.subtitle };
}

export default function InvestorsPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).investors;
  const board = getInvestorBoard();

  return (
    <div className="space-y-6">
      <PageHeader eyebrow="PRISMO" title={t.title} subtitle={t.subtitle} />
      <InvestorBoardView board={board} />
    </div>
  );
}
