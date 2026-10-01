export const INVESTMENT_CHANNELS = ["accounts", "politicians", "institutions", "onchain", "insiders", "other"] as const;
export const CONTACT_PLATFORMS = ["telegram", "wechat", "twitter", "discord"] as const;

export interface WaitlistSurvey {
  channels: (typeof INVESTMENT_CHANNELS)[number][];
  otherChannel: string;
  contact: { platform: (typeof CONTACT_PLATFORMS)[number]; handle: string } | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function cleanText(value: unknown, max: number): string | null {
  if (typeof value !== "string" || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) return null;
  return value.trim();
}

export function parseWaitlistSurvey(value: unknown): WaitlistSurvey | null {
  if (value === undefined) value = {};
  if (!isRecord(value)) return null;
  const selected = value.channels === undefined ? [] : value.channels;
  if (!Array.isArray(selected) || selected.length > INVESTMENT_CHANNELS.length) return null;
  if (selected.some(channel => !INVESTMENT_CHANNELS.includes(channel))) return null;
  const channels = INVESTMENT_CHANNELS.filter(channel => selected.includes(channel));
  const otherChannel = cleanText(value.otherChannel === undefined ? "" : value.otherChannel, 200);
  if (otherChannel === null || (channels.includes("other") && !otherChannel) || (!channels.includes("other") && otherChannel)) return null;
  if (value.contact === undefined || value.contact === null) return { channels, otherChannel, contact: null };
  if (!isRecord(value.contact) || !CONTACT_PLATFORMS.includes(value.contact.platform as typeof CONTACT_PLATFORMS[number])) return null;
  const handle = cleanText(value.contact.handle, 120);
  if (!handle) return null;
  const contact = { platform: value.contact.platform as typeof CONTACT_PLATFORMS[number], handle };
  return { channels, otherChannel, contact };
}
