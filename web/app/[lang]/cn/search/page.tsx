import { SearchExperience } from "@/components/SearchExperience";
import { getGlobalSearchableTickers, getGlobalSearchHeat } from "@/lib/queries";

// 搜索已合并为「全站搜索」（美股 + 中概/港股/A 股）。此路由保留为别名，渲染同一个全站搜索，
// 避免旧链接/书签 404；新的统一入口在侧边栏顶部 → /search。
export default function CnSearchPage() {
  const tickers = getGlobalSearchableTickers();
  const valid = tickers.map((t) => ({
    ticker: t.ticker, name: t.name, posts: t.posts,
    base: t.market === "cn" ? "/cn/ticker" : "/ticker",
  }));
  const heat = getGlobalSearchHeat(10).map((h) => ({
    ticker: h.ticker, name: h.name, mentions: h.mentions, sentiment: h.sentiment,
    base: h.market === "cn" ? "/cn/ticker" : "/ticker",
  }));
  const popular = heat.slice(0, 8).map((h) => h.ticker);
  return (
    <div className="max-w-3xl mx-auto">
      <SearchExperience valid={valid} popular={popular} heat={heat} />
    </div>
  );
}
