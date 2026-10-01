export const ABILITY_VERSION = "follow-ability-v1";

const kinds = new Set([
  "platform",
  "politician",
  "celebrity",
  "insider",
  "institution",
]);
const pending = new Set([
  "insufficient_history",
  "unverified_source",
  "unaudited_backtest",
  "incomplete_prices",
  "no_observable_trade",
]);

export type AbilityItem = {
  actorKind: string;
  actorId: string;
  displayName: string;
  platform: string | null;
  avatarURL: string | null;
  status: string;
  score: number | null;
  observedCalendarDays: number;
  independentDecisionDays: number;
  pricedCoverage: number;
  rank: number | null;
};

function validItem(value: unknown): value is Omit<AbilityItem, "rank"> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const item = value as Record<string, unknown>;
  const scoreIsValid = item.status === "scored"
    ? typeof item.score === "number" && Number.isFinite(item.score)
    : pending.has(String(item.status)) && item.score === null;
  return kinds.has(String(item.actorKind)) &&
    typeof item.actorId === "string" && item.actorId.length > 0 &&
    item.actorId.length <= 256 &&
    typeof item.displayName === "string" &&
    item.displayName.trim().length > 0 && item.displayName.length <= 160 &&
    (item.platform === null ||
      typeof item.platform === "string" && item.platform.length <= 40) &&
    (item.avatarURL === null ||
      typeof item.avatarURL === "string" &&
        item.avatarURL.startsWith("https://") &&
        item.avatarURL.length <= 2048) &&
    scoreIsValid &&
    Number.isSafeInteger(item.observedCalendarDays) &&
    Number(item.observedCalendarDays) >= 0 &&
    Number.isSafeInteger(item.independentDecisionDays) &&
    Number(item.independentDecisionDays) >= 0 &&
    Number(item.independentDecisionDays) <= Number(item.observedCalendarDays) &&
    typeof item.pricedCoverage === "number" &&
    Number.isFinite(item.pricedCoverage) &&
    item.pricedCoverage >= 0 && item.pricedCoverage <= 1;
}

export function abilityLeaderboard(snapshot: unknown) {
  if (snapshot === null) {
    return {
      status: "unpublished",
      version: ABILITY_VERSION,
      revision: null,
      asOf: null,
      scoreUnit: "annualized_adjusted_pp",
      items: [],
    };
  }
  if (!snapshot || typeof snapshot !== "object") {
    throw new Error("invalid_ability_snapshot");
  }
  const row = snapshot as Record<string, unknown>;
  if (
    row.scoring_version !== ABILITY_VERSION ||
    !Number.isSafeInteger(row.revision) || Number(row.revision) < 1 ||
    typeof row.as_of !== "string" || !Number.isFinite(Date.parse(row.as_of)) ||
    !Array.isArray(row.items) || row.items.length > 10000 ||
    !row.items.every(validItem)
  ) {
    throw new Error("invalid_ability_snapshot");
  }
  const seen = new Set<string>();
  for (const item of row.items as AbilityItem[]) {
    const key = `${item.actorKind}:${item.actorId}`;
    if (seen.has(key)) throw new Error("duplicate_ability_actor");
    seen.add(key);
  }
  const items = (row.items as AbilityItem[]).map((item) => ({
    ...item,
    rank: null as number | null,
  }));
  items.sort((a, b) => {
    if (a.score !== null && b.score === null) return -1;
    if (a.score === null && b.score !== null) return 1;
    if (a.score !== null && b.score !== null && a.score !== b.score) {
      return b.score - a.score;
    }
    return `${a.actorKind}:${a.actorId}`.localeCompare(
      `${b.actorKind}:${b.actorId}`,
    );
  });
  let lastScore: number | null = null;
  let lastRank = 0;
  items.forEach((item, index) => {
    if (item.score === null) return;
    if (lastScore !== item.score) lastRank = index + 1;
    item.rank = lastRank;
    lastScore = item.score;
  });
  return {
    status: "published",
    version: ABILITY_VERSION,
    revision: row.revision,
    asOf: row.as_of,
    scoreUnit: "annualized_adjusted_pp",
    items,
  };
}
