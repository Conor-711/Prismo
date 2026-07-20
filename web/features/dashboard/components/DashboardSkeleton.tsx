import { ViewportWorkspace } from "@/shared/layout/ViewportWorkspace";

function Lines({ count }: { count: number }) {
  return (
    <div className="divide-y divide-line/70">
      {Array.from({ length: count }).map((_, index) => (
        <div key={index} className="flex h-11 items-center gap-2.5 px-3">
          <span className="h-5 w-5 rounded-full bg-white/[.06]" />
          <span className="h-2.5 flex-1 rounded bg-white/[.05]" />
          <span className="h-2.5 w-10 rounded bg-white/[.05]" />
        </div>
      ))}
    </div>
  );
}

function SkeletonPanel({ rows = 0, className = "" }: { rows?: number; className?: string }) {
  return (
    <div className={`panel min-h-0 overflow-hidden rounded-lg ${className}`}>
      <div className="flex h-11 items-center gap-2.5 border-b border-line px-3">
        <span className="h-1.5 w-1.5 rounded-full bg-reddit/30" />
        <span className="h-3 w-28 rounded bg-white/[.07]" />
      </div>
      {rows ? <Lines count={rows} /> : <div className="m-5 h-[calc(100%-84px)] rounded bg-white/[.025]" />}
    </div>
  );
}

export function DashboardSkeleton() {
  return (
    <ViewportWorkspace className="overflow-hidden" bottomOffset={16}>
      <div className="flex h-full min-h-0 animate-pulse flex-col gap-2.5">
        <div className="flex min-h-9 items-center justify-between border-b border-line pb-2">
          <div>
            <div className="h-2 w-40 rounded bg-reddit/20" />
            <div className="mt-2 h-4 w-28 rounded bg-white/[.08]" />
          </div>
          <div className="h-2.5 w-24 rounded bg-white/[.05]" />
        </div>
        <div className="panel grid shrink-0 grid-cols-6 divide-x divide-line overflow-hidden rounded-lg">
          {Array.from({ length: 6 }).map((_, index) => (
            <div key={index} className="h-[66px] px-3 py-2.5">
              <div className="h-2 w-14 rounded bg-white/[.05]" />
              <div className="mt-2 h-4 w-20 rounded bg-white/[.08]" />
              <div className="mt-2 h-2 w-12 rounded bg-white/[.04]" />
            </div>
          ))}
        </div>
        <div className="grid min-h-0 flex-1 grid-cols-[minmax(210px,0.78fr)_minmax(360px,1.65fr)_minmax(220px,0.9fr)] gap-2.5 overflow-hidden">
          <div className="grid min-h-0 grid-rows-[1.12fr_0.88fr] gap-2.5">
            <SkeletonPanel rows={6} />
            <SkeletonPanel rows={5} />
          </div>
          <div className="grid min-h-0 grid-rows-[1.35fr_0.85fr] gap-2.5">
            <SkeletonPanel />
            <SkeletonPanel rows={4} />
          </div>
          <SkeletonPanel rows={8} />
        </div>
      </div>
    </ViewportWorkspace>
  );
}
