export function smartVoiceInvestorSlug(id: string) {
  return Array.from(String(id)).map((char) => (/^[A-Za-z0-9_-]$/.test(char) ? char : `~${char.charCodeAt(0).toString(16).padStart(2, "0")}`)).join("");
}

export function smartVoiceInvestorIdFromSlug(slug: string) {
  return String(slug).replace(/~([0-9a-fA-F]{2})/g, (_, hex: string) => String.fromCharCode(Number.parseInt(hex, 16)));
}

export function smartVoiceInvestorHref(id: string) {
  return `/investors/smart-account/${smartVoiceInvestorSlug(id)}`;
}
