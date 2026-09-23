export function normalizeWaitlistEmail(value: string): string | null {
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/i.test(email)) return null;
  const local = email.split("@")[0];
  return local.length > 64 || local.startsWith(".") || local.endsWith(".") || local.includes("..") ? null : email;
}
