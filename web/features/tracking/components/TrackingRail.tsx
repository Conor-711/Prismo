import { LocaleLink } from "@/components/i18n/LocaleLink";
import type { CollectionRow } from "@/lib/favorites";
import { fmtCompact } from "@/shared/formatting/format";
import { Avatar } from "@/shared/market/kolPresentation";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { GrTickerRow } from "@/server/queries/globalQueries";
import type { TrackKind, TrackingCatalog } from "../trackingTypes";

export function TrackingRail({
  zh,
  busy,
  collections,
  rowMap,
  authorMap,
  narrativeMap,
  selectedSymbol,
  onSelectSymbol,
  onRemove,
}: {
  zh: boolean;
  busy: boolean;
  collections: Record<TrackKind, CollectionRow[]>;
  rowMap: Map<string, GrTickerRow>;
  authorMap: Map<string, TrackingCatalog["authors"][number]>;
  narrativeMap: Map<string, TrackingCatalog["narratives"][number]>;
  selectedSymbol: string | null;
  onSelectSymbol: (symbol: string | null) => void;
  onRemove: (kind: TrackKind, refId: string) => void;
}) {
  return (
    <aside className="flex min-h-0 flex-col overflow-hidden rounded-md bg-card/30 ring-1 ring-inset ring-line">
      <div className="flex h-[51px] shrink-0 items-center justify-between border-b border-line px-3">
        <div>
          <h2 className="text-[12.5px] font-bold text-cream">{zh ? "追踪对象" : "Tracked"}</h2>
          <p className="text-[9.5px] text-neutral-600">{zh ? "决定信息流范围" : "Controls your feed"}</p>
        </div>
        <span className="font-mono text-[10px] text-neutral-600">
          {collections.ticker.length + collections.author.length + collections.narrative.length}
        </span>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto px-2 py-2">
        {busy ? (
          <div className="py-8 text-center text-[11px] text-neutral-600">{zh ? "读取中…" : "Loading…"}</div>
        ) : (
          <>
            <RailHeading label={zh ? "标的" : "Tickers"} count={collections.ticker.length} />
            <button
              type="button"
              onClick={() => onSelectSymbol(null)}
              className={`mb-1 flex h-8 w-full items-center gap-2 rounded px-2 text-left text-[11.5px] transition ${
                selectedSymbol === null ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/35" : "text-neutral-500 hover:bg-white/[.035] hover:text-neutral-200"
              }`}
            >
              <span className="grid h-5 w-5 place-items-center rounded bg-white/[.04] text-[10px]">◎</span>
              <span className="font-semibold">{zh ? "全部标的" : "All tickers"}</span>
            </button>
            {collections.ticker.map((row) => {
              const symbol = row.ref_id.toUpperCase();
              const ticker = rowMap.get(symbol);
              return (
                <div key={row.ref_id} className="group mb-1 flex items-center gap-1">
                  <button
                    type="button"
                    onClick={() => onSelectSymbol(symbol)}
                    className={`flex h-9 min-w-0 flex-1 items-center gap-2 rounded px-2 text-left transition ${
                      selectedSymbol === symbol ? "bg-reddit/12 ring-1 ring-inset ring-reddit/35" : "hover:bg-white/[.035]"
                    }`}
                  >
                    <TickerLogo ticker={symbol} size={22} />
                    <span className="min-w-0 flex-1">
                      <span className={`block truncate font-mono text-[11.5px] font-bold ${selectedSymbol === symbol ? "text-reddit" : "text-neutral-200"}`}>{symbol}</span>
                      <span className="block truncate text-[9.5px] text-neutral-600">{ticker ? fmtCompact(ticker.total_posts) : (zh ? "暂无数据" : "No data")}</span>
                    </span>
                  </button>
                  <RemoveButton label={zh ? `取消追踪 ${symbol}` : `Unfollow ${symbol}`} onClick={() => onRemove("ticker", row.ref_id)} />
                </div>
              );
            })}

            <RailHeading label={zh ? "作者" : "Authors"} count={collections.author.length} className="mt-3" />
            {collections.author.length === 0 ? (
              <RailEmpty text={zh ? "追踪作者后将提高其观点权重" : "Follow authors to boost their views"} />
            ) : collections.author.map((row) => {
              const author = authorMap.get(row.ref_id);
              const label = author?.name ?? row.ref_id.replace(/^[^:]+:/, "");
              return (
                <div key={row.ref_id} className="group mb-1 flex h-9 items-center gap-2 rounded px-2 hover:bg-white/[.035]">
                  <Avatar src={author?.avatar} color="#57D7BA" name={label} size={21} />
                  <span className="min-w-0 flex-1 truncate text-[10.5px] text-neutral-300">{label}</span>
                  <RemoveButton label={zh ? `取消追踪 ${label}` : `Unfollow ${label}`} onClick={() => onRemove("author", row.ref_id)} />
                </div>
              );
            })}

            <RailHeading label={zh ? "叙事" : "Narratives"} count={collections.narrative.length} className="mt-3" />
            {collections.narrative.length === 0 ? (
              <RailEmpty text={zh ? "追踪叙事后将提高相关标的权重" : "Follow narratives to boost related tickers"} />
            ) : collections.narrative.map((row) => {
              const narrative = narrativeMap.get(row.ref_id);
              const label = narrative ? (zh ? narrative.titleZh : narrative.titleEn) : row.ref_id;
              return (
                <div key={row.ref_id} className="group mb-1 flex h-9 items-center gap-2 rounded px-2 hover:bg-white/[.035]">
                  <span className="h-5 w-1 shrink-0 rounded-full" style={{ background: narrative?.color ?? "#57D7BA" }} />
                  <LocaleLink href={`/narratives/${row.ref_id}`} className="min-w-0 flex-1 truncate text-[10.5px] text-neutral-300 hover:text-reddit">{label}</LocaleLink>
                  <RemoveButton label={zh ? `取消追踪 ${label}` : `Unfollow ${label}`} onClick={() => onRemove("narrative", row.ref_id)} />
                </div>
              );
            })}
          </>
        )}
      </div>
    </aside>
  );
}

function RailHeading({ label, count, className = "" }: { label: string; count: number; className?: string }) {
  return (
    <div className={`mb-1 flex items-center gap-2 px-2 ${className}`}>
      <span className="text-[9.5px] font-semibold uppercase text-neutral-600">{label}</span>
      <span className="font-mono text-[9px] text-neutral-700">{count}</span>
      <span className="h-px flex-1 bg-line/70" />
    </div>
  );
}

function RailEmpty({ text }: { text: string }) {
  return <p className="px-2 py-2 text-[9.5px] leading-relaxed text-neutral-700">{text}</p>;
}

function RemoveButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className="grid h-6 w-6 shrink-0 place-items-center rounded text-[14px] text-neutral-700 opacity-0 transition hover:bg-bear/10 hover:text-bear group-hover:opacity-100 focus:opacity-100"
    >
      ×
    </button>
  );
}
