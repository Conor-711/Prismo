import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";

type Row = {
  account_id: string;
  onboarding_completed: boolean;
  followed_authors: string[];
  followed_money: string[];
  revision: number;
};

const fields = "account_id,onboarding_completed,followed_authors,followed_money,revision";

function present(row: Row) {
  return {
    onboardingCompleted: row.onboarding_completed,
    followedAuthors: row.followed_authors,
    followedMoney: row.followed_money,
    revision: row.revision,
  };
}

async function find(client: SupabaseClient, accountID: string): Promise<Row | null> {
  const { data, error } = await client.from("bsmart_account_preferences").select(fields)
    .eq("account_id", accountID).maybeSingle();
  if (error) throw new Error("state_unavailable");
  return data as Row | null;
}

async function ensure(client: SupabaseClient, accountID: string): Promise<Row> {
  const existing = await find(client, accountID);
  if (existing) return existing;
  const { error } = await client.from("bsmart_account_preferences").insert({ account_id: accountID });
  if (error && error.code !== "23505") throw new Error("state_unavailable");
  const created = await find(client, accountID);
  if (!created) throw new Error("state_unavailable");
  return created;
}

export async function readAccountState(client: SupabaseClient, accountID: string) {
  return present(await ensure(client, accountID));
}

export function followInput(value: any): { kind: "author" | "money"; id: string; following: boolean } {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).sort().join() !== "following,id,kind" ||
      !["author", "money"].includes(value.kind) ||
      typeof value.id !== "string" || value.id.length < 1 || value.id.length > 256 ||
      value.id.trim() !== value.id || /[\x00-\x1f\x7f]/.test(value.id) ||
      typeof value.following !== "boolean") throw new Error("invalid_input");
  return value;
}

export async function setAccountFollow(client: SupabaseClient, accountID: string,
                                       input: ReturnType<typeof followInput>) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const row = await ensure(client, accountID);
    if (!Number.isSafeInteger(row.revision) || row.revision < 0) throw new Error("state_unavailable");
    const column = input.kind === "author" ? "followed_authors" : "followed_money";
    const values = row[column];
    if (!Array.isArray(values)) throw new Error("state_unavailable");
    const next = input.following ? [...new Set([...values, input.id])] : values.filter(id => id !== input.id);
    if (next.length === values.length && next.every((id, index) => id === values[index])) return present(row);
    if (next.length > 1000) throw new Error("follow_limit");
    const { data, error } = await client.from("bsmart_account_preferences").update({
      [column]: next, revision: row.revision + 1, updated_at: new Date().toISOString(),
    }).eq("account_id", accountID).eq("revision", row.revision).select(fields).maybeSingle();
    if (error) throw new Error("state_unavailable");
    if (data) return present(data as Row);
  }
  throw new Error("state_conflict");
}

export async function finishAccountOnboarding(client: SupabaseClient, accountID: string) {
  const row = await ensure(client, accountID);
  if (row.onboarding_completed) return present(row);
  const { data, error } = await client.from("bsmart_account_preferences")
    .update({ onboarding_completed: true, updated_at: new Date().toISOString() })
    .eq("account_id", accountID).select(fields).maybeSingle();
  if (error || !data) throw new Error("state_unavailable");
  return present(data as Row);
}
