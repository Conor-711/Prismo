const rows = Array.from({ length: 9 });
const stats = Array.from({ length: 6 });
const bars = Array.from({ length: 18 });

function Pulse({ className }: { className: string }) {
  return <div className={`animate-pulse rounded-md bg-white/[.055] ${className}`} />;
}

export function AppRouteSkeleton() {
  return (
    <div className="h-full min-h-0 overflow-hidden" aria-label="Loading page">
      <div className="mb-4 flex items-center justify-between gap-4">
        <div className="flex min-w-0 items-center gap-3">
          <Pulse className="h-11 w-11 rounded-xl" />
          <div className="min-w-0 space-y-2">
            <Pulse className="h-5 w-44" />
            <Pulse className="h-3 w-28" />
          </div>
        </div>
        <div className="hidden min-w-0 flex-1 grid-cols-6 gap-2 lg:grid">
          {stats.map((_, index) => (
            <Pulse key={index} className="h-11" />
          ))}
        </div>
      </div>

      <div className="grid h-[calc(100%-64px)] min-h-0 gap-3 lg:grid-cols-[392px_minmax(0,1fr)]">
        <section className="min-h-0 overflow-hidden rounded-xl bg-panel/70 ring-1 ring-inset ring-line">
          <div className="flex h-12 items-center gap-4 border-b border-line px-4">
            <Pulse className="h-4 w-16" />
            <Pulse className="h-4 w-16" />
            <Pulse className="h-4 w-16" />
          </div>
          <div className="divide-y divide-line/70">
            {rows.map((_, index) => (
              <div key={index} className="flex gap-3 px-4 py-3">
                <Pulse className="h-9 w-9 shrink-0 rounded-full" />
                <div className="min-w-0 flex-1 space-y-2">
                  <Pulse className="h-4 w-2/5" />
                  <Pulse className="h-3 w-full" />
                  <Pulse className="h-3 w-4/5" />
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="grid min-h-0 gap-3 lg:grid-rows-[minmax(0,1fr)_190px]">
          <div className="min-h-0 rounded-xl bg-panel/70 p-4 ring-1 ring-inset ring-line">
            <div className="mb-4 flex items-center justify-between">
              <Pulse className="h-5 w-28" />
              <Pulse className="h-8 w-24" />
            </div>
            <div className="flex h-[calc(100%-52px)] items-end gap-2 border-b border-line/70 px-2 pb-5">
              {bars.map((_, index) => (
                <div
                  key={index}
                  className="flex flex-1 items-end"
                  style={{ height: `${30 + ((index * 17) % 64)}%` }}
                >
                  <Pulse className="h-full w-full rounded-t-sm" />
                </div>
              ))}
            </div>
          </div>
          <div className="grid min-h-0 gap-3 lg:grid-cols-3">
            <Pulse className="h-full min-h-[150px] rounded-xl" />
            <Pulse className="h-full min-h-[150px] rounded-xl" />
            <Pulse className="h-full min-h-[150px] rounded-xl" />
          </div>
        </section>
      </div>
    </div>
  );
}
