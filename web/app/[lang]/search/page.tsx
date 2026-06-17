import { SearchExperience } from "@/components/SearchExperience";
import { getGlobalSearchableTickers, getGlobalSearchHeat } from "@/lib/queries";

// 全站搜索：一个入口搜全部市场——美股 + 中概/港股/A 股。
// 每个结果按其实际个股页路由（美股→/ticker，中概港股→/cn/ticker）。
export default function SearchPage() {
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
