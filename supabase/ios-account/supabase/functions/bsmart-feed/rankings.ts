export function rankingScope(url: URL, now: number) {
  const kind = url.searchParams.get("kind"), sort = url.searchParams.get("sort"), window = url.searchParams.get("window");
  const anchor = url.searchParams.get("asOf");
  const asOf = anchor === null ? now : Date.parse(anchor);
  if (!["opinions", "investors"].includes(kind ?? "") || !["traders", "volume"].includes(sort ?? "") ||
    !["1d", "7d", "30d", "all"].includes(window ?? "") || !Number.isFinite(asOf) || asOf > now || asOf < 0) {
    throw new Error("invalid_input");
  }
  return { p_kind: kind, p_sort: sort, p_window: window, p_as_of: new Date(asOf).toISOString() };
}
