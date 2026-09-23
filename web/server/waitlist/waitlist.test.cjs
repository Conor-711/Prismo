const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { handleWaitlist } = require(path.join(process.env.BSMART_WAITLIST_TEST_BUILD, "server/waitlist/handler.js"));

class MemoryKV {
  values = new Map();
  writes = [];
  async get(key) { return this.values.get(key) ?? null; }
  async put(key, value, options) { this.writes.push({ key, options }); this.values.set(key, value); }
}
function request(body = {}, headers = {}, method = "POST") {
  return new Request("https://bsmart.today/api/waitlist", { method, headers: { "Content-Type": "application/json", Origin: "https://bsmart.today", ...headers }, ...(method === "POST" ? { body: JSON.stringify({ email: "reader@example.com", consent: true, lang: "zh", website: "", survey: answers, ...body }) } : {}) });
}

function seedLegacy(kv, email = "reader@example.com") {
  kv.values.set(`entry:${createHash("sha256").update(email).digest("hex")}`, JSON.stringify({ email, lang: "zh", source: "bsmart.today", createdAt: "2026-09-13T00:00:00.000Z", consentVersion: "beta-invitation-2026-09-13" }));
}

const answers = { channels: ["accounts", "onchain", "other"], otherChannel: "  投资播客  ", contact: { platform: "telegram", handle: "  @reader  " } };

test("survey stores normalized multiple choices, other text and each supported contact platform", async () => {
  for (const platform of ["telegram", "wechat", "twitter"]) {
    const kv = new MemoryKV();
    const survey = { ...answers, channels: [...answers.channels, "accounts"], contact: { platform, handle: "  reader账号  ", secret: "discard" }, arbitrary: "discard" };
    assert.equal((await handleWaitlist(request({ survey }), { WAITLIST: kv })).status, 200);
    const record = JSON.parse([...kv.values.values()][0]);
    assert.deepEqual(record.survey, { channels: answers.channels, otherChannel: "投资播客", contact: { platform, handle: "reader账号" } });
    assert.equal(record.surveyVersion, "investment-interests-required-2026-09-15");
    assert.ok(Number.isFinite(Date.parse(record.surveySubmittedAt)));
  }
});

test("all three fields are required, including older clients with no survey", async () => {
  for (const survey of [
    undefined,
    { channels: [], otherChannel: "", contact: null },
    { channels: ["institutions", "insiders", "politicians"], otherChannel: "", contact: null },
    { channels: [], otherChannel: "", contact: { platform: "twitter", handle: "https://x.com/reader" } },
  ]) {
    const kv = new MemoryKV();
    assert.equal((await handleWaitlist(request({ survey }), { WAITLIST: kv })).status, 400);
    assert.equal(kv.writes.length, 0);
  }
});

test("invalid surveys return a field error without writing anything", async () => {
  for (const survey of [null, [], "wrong", {},
    { ...answers, channels: "accounts" }, { ...answers, channels: ["unknown"] },
    { ...answers, channels: Array(7).fill("accounts") }, { ...answers, channels: [null] },
    { ...answers, otherChannel: " " }, { ...answers, otherChannel: "x".repeat(201) },
    { ...answers, channels: [], otherChannel: "hidden answer" },
    { ...answers, contact: { platform: "email", handle: "reader" } },
    { ...answers, contact: { platform: "telegram", handle: " " } },
    { ...answers, contact: { platform: "telegram", handle: "x".repeat(121) } },
    { ...answers, contact: { platform: "telegram", handle: "foo\nbar" } },
  ]) {
    const kv = new MemoryKV();
    const response = await handleWaitlist(request({ survey }), { WAITLIST: kv });
    assert.equal(response.status, 400); assert.equal((await response.json()).code, "invalid_survey"); assert.equal(kv.writes.length, 0);
  }
});

test("email-only applicants can add their first survey without losing original metadata", async () => {
  const kv = new MemoryKV();
  seedLegacy(kv);
  const original = JSON.parse([...kv.values.values()][0]);
  assert.equal((await handleWaitlist(request({ survey: answers, lang: "en" }), { WAITLIST: kv })).status, 200);
  const updated = JSON.parse([...kv.values.values()][0]);
  for (const key of Object.keys(original)) assert.deepEqual(updated[key], original[key]);
  assert.equal(updated.survey.contact.handle, "@reader");
  const before = [...kv.values.entries()];
  await handleWaitlist(request({ survey: { ...answers, contact: { platform: "wechat", handle: "replacement" } } }), { WAITLIST: kv });
  assert.deepEqual([...kv.values.entries()], before);
});

test("adding a survey is throttled and persistence failure is not reported as success", async () => {
  const kv = new MemoryKV();
  for (let i = 0; i < 6; i++) seedLegacy(kv, `old${i}@example.com`);
  for (let i = 0; i < 6; i++) {
    const response = await handleWaitlist(request({ email: `old${i}@example.com`, survey: answers }, { "CF-Connecting-IP": "192.0.2.13" }), { WAITLIST: kv });
    assert.equal(response.status, i < 5 ? 200 : 429);
  }
  const broken = { get: kv.get.bind(kv), put: async () => { throw new Error("offline"); } };
  assert.equal((await handleWaitlist(request({ email: "old5@example.com", survey: answers }), { WAITLIST: broken })).status, 503);
});

test("persists only the normalized invitation record, not arbitrary request fields", async () => {
  const kv = new MemoryKV();
  const response = await handleWaitlist(request({ email: "  Reader+Beta@Example.com  ", arbitrary: "discard me" }), { WAITLIST: kv });
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), { ok: true });
  assert.equal(kv.values.size, 1);
  const [key, value] = [...kv.values.entries()][0];
  assert.match(key, /^entry:[a-f0-9]{64}$/); assert.equal(key.includes("reader"), false);
  const record = JSON.parse(value);
  assert.equal(record.email, "reader+beta@example.com"); assert.equal(record.lang, "zh");
  assert.equal(record.consentVersion, "beta-invitation-2026-09-13"); assert.equal(record.arbitrary, undefined);
  assert.ok(Number.isFinite(Date.parse(record.createdAt))); assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("duplicates are idempotent and do not rewrite consent or creation time", async () => {
  const kv = new MemoryKV();
  await handleWaitlist(request(), { WAITLIST: kv });
  const before = [...kv.values.entries()];
  const response = await handleWaitlist(request({ email: "READER@example.com", lang: "en" }), { WAITLIST: kv });
  assert.equal(response.status, 200); assert.deepEqual([...kv.values.entries()], before); assert.equal(kv.writes.length, 1);
});

test("invalid email, consent, locale and honeypot never reach storage", async () => {
  for (const body of [{ email: "bad" }, { email: "a..b@example.com" }, { email: "a@localhost" }, { email: "x".repeat(65) + "@example.com" }, { consent: false }, { consent: "true" }, { lang: "xx" }, { website: "bot.example" }]) {
    const kv = new MemoryKV();
    assert.equal((await handleWaitlist(request(body), { WAITLIST: kv })).status, 400); assert.equal(kv.writes.length, 0);
  }
});

test("missing binding and failed persistence never report success", async () => {
  assert.equal((await handleWaitlist(request(), {})).status, 503);
  const broken = { get: async () => null, put: async () => { throw new Error("storage offline"); } };
  const response = await handleWaitlist(request(), { WAITLIST: broken });
  assert.equal(response.status, 503); assert.equal((await response.json()).ok, false);
});

test("cross-origin submission is rejected; local proxy must be enabled explicitly", async () => {
  const kv = new MemoryKV();
  assert.equal((await handleWaitlist(request({}, { Origin: "https://unrelated.example" }), { WAITLIST: kv })).status, 403);
  assert.equal((await handleWaitlist(request({}, { "Sec-Fetch-Site": "cross-site" }), { WAITLIST: kv })).status, 403);
  assert.equal((await handleWaitlist(request({}, { Origin: "http://127.0.0.1:3100" }), { WAITLIST: kv })).status, 403);
  assert.equal((await handleWaitlist(request({}, { Origin: "http://127.0.0.1:3100" }), { WAITLIST: kv, WAITLIST_LOCAL_DEV: "true" })).status, 200);
});

test("body and method restrictions protect the public collection endpoint", async () => {
  const kv = new MemoryKV();
  for (const method of ["GET", "DELETE", "OPTIONS"]) assert.equal((await handleWaitlist(request({}, {}, method), { WAITLIST: kv })).status, 405);
  assert.equal((await handleWaitlist(request({}, { "Content-Type": "text/plain" }), { WAITLIST: kv })).status, 415);
  assert.equal((await handleWaitlist(request({ extra: "x".repeat(3000) }), { WAITLIST: kv })).status, 413);
  const malformed = new Request("https://bsmart.today/api/waitlist", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{oops" });
  assert.equal((await handleWaitlist(malformed, { WAITLIST: kv })).status, 400); assert.equal(kv.values.size, 0);
});

test("coarse per-network throttle rejects the sixth new email and stores no raw IP", async () => {
  const kv = new MemoryKV(); const ip = "192.0.2.12";
  for (let i = 0; i < 5; i++) assert.equal((await handleWaitlist(request({ email: `reader${i}@example.com` }, { "CF-Connecting-IP": ip }), { WAITLIST: kv })).status, 200);
  const response = await handleWaitlist(request({ email: "sixth@example.com" }, { "CF-Connecting-IP": ip }), { WAITLIST: kv });
  assert.equal(response.status, 429); assert.equal(response.headers.get("Retry-After"), "3600");
  assert.equal([...kv.values.keys()].filter(key => key.startsWith("entry:")).length, 5);
  assert.equal(JSON.stringify([...kv.values.entries()]).includes(ip), false);
  assert.equal(kv.writes.find(write => write.key.startsWith("rate:")).options.expirationTtl, 3600);
});


test("application button records an application, never a privacy-checkbox consent", async () => {
  const kv = new MemoryKV();
  const application = { consent: undefined, intent: "beta-access", lang: "en" };
  assert.equal((await handleWaitlist(request(application), { WAITLIST: kv })).status, 200);
  const record = JSON.parse([...kv.values.values()][0]);
  assert.equal(record.requestVersion, "beta-application-2026-09-13");
  assert.equal(record.requestMethod, "application-button");
  assert.equal(record.consentVersion, undefined);
  const before = [...kv.values.entries()];
  await handleWaitlist(request(), { WAITLIST: kv });
  assert.deepEqual([...kv.values.entries()], before);
  for (const intent of [undefined, "", "marketing", true]) {
    assert.equal((await handleWaitlist(request({ email: "new@example.com", consent: undefined, intent }), { WAITLIST: kv })).status, 400);
  }
});
