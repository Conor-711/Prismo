import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../..');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const accounts = read('contracts/fixtures/smart-accounts.json');
const evidence = read('contracts/fixtures/smart-account-evidence.json');
const updates = read('contracts/fixtures/smart-account-updates.json');
const choices = [
  { id: '3e286673-9b81-5d9b-b2a7-7d233c88df6f', company: '美光', style: '中线 · 技术分析' },
  { id: 'dfd5ce60-4ce1-5df6-9c4c-0cda7c6ed915', company: 'Lumentum', style: '中线 · 基本面研究' },
  { id: '0eb40732-4955-5b13-9581-130a4447fa34', company: '英伟达', style: '中线 · 基本面研究' },
];
const ny = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' });
const nyHour = new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: '2-digit', hourCycle: 'h23' });
function relatedCalls(record, account, endDay) {
  const related = [...evidence, ...updates].filter(row => row.authorId === record.authorId && row.ticker === record.ticker);
  const candidates = [...related.flatMap(row => row.priceEvidence?.opinionMarkers ?? []), ...related];
  const unique = new Map();
  for (const row of candidates) {
    if (!['bullish', 'bearish'].includes(row.direction)) continue;
    const sourceURL = row.evidenceURL ?? row.sourceURL;
    if (!sourceURL) continue;
    const url = new URL(sourceURL);
    const parts = url.pathname.split('/').filter(Boolean);
    if (!['twitter.com', 'x.com'].includes(url.hostname) || parts[1] !== 'status') continue;
    if (![account.id, account.handle.replace(/^@/, '').toLowerCase()].includes(parts[0].toLowerCase())) continue;
    const postId = parts[2];
    const date = new Date(row.publishedAt);
    if (!Number.isFinite(date.getTime())) continue;
    const day = ny.format(date);
    if (date < new Date(record.publishedAt) || day > endDay) continue;
    const first = row.firstOpinion;
    const completed = record.priceEvidence.candles.filter(c => c.day < day || (c.day === day && Number(nyHour.format(date)) >= 16)).at(-1);
    const knownFirst = first?.sourcePostId === postId && first.price > 0;
    const price = knownFirst ? first.price : completed?.close;
    const priceDay = knownFirst ? first.priceDay : completed?.day;
    if (!(price > 0) || !priceDay) continue;
    unique.set(postId, {
      ...unique.get(postId), id: postId, publishedAt: row.publishedAt, day,
      price, priceDay, direction: row.direction, sourceURL,
      originalText: row.originalText ?? unique.get(postId)?.originalText ?? null,
    });
  }
  const calls = [...unique.values()].sort((a, b) => a.publishedAt.localeCompare(b.publishedAt));
  assert(calls[0]?.id === record.sourcePostId);
  return calls;
}
function image(file) {
  const type = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml' }[path.extname(file)];
  assert(type && fs.existsSync(file), `Missing image: ${file}`);
  return `data:${type};base64,${fs.readFileSync(file).toString('base64')}`;
}
const data = choices.map(choice => {
  const record = evidence.find(row => row.id === choice.id);
  const account = accounts.find(row => row.id === record?.authorId && row.platform === record.platform);
  assert(record && account && record.direction === 'bullish');
  assert(account.platformPercentile <= .25);
  assert(record.firstOpinion.sourcePostId === record.sourcePostId, 'Do not combine different historical posts');
  const publishedDay = ny.format(new Date(record.publishedAt));
  const first = record.firstOpinion;
  assert(first.price > 0 && first.priceBasis === 'last_completed_daily_close');
  // Only later complete sessions are eligible: publication-day highs may precede the post.
  const candles = record.priceEvidence.candles.filter(c => c.day > publishedDay)
    .sort((a, b) => a.day.localeCompare(b.day));
  assert(candles.length > 0 && new Set(candles.map(c => c.day)).size === candles.length);
  for (const candle of candles) assert(Number.isFinite(candle.high) && candle.high >= candle.close && candle.high > 0);
  const peak = candles.reduce((best, candle) => candle.high > best.high ? candle : best);
  const peakChange = (peak.high / first.price - 1) * 100;
  const calls = relatedCalls(record, account, candles.at(-1).day);
  assert(peak.day > publishedDay && peakChange > 0);
  const hash = crypto.createHash('sha256').update(account.avatarURL).digest('hex');
  const logoDirectory = path.join(root, `ios/BSmart/Assets.xcassets/Ticker_${record.ticker}.imageset`);
  const logo = JSON.parse(fs.readFileSync(path.join(logoDirectory, 'Contents.json'))).images.find(row => row.filename).filename;
  return {
    ...choice, ticker: record.ticker, name: account.name, handle: account.handle,
    profileURL: account.profileURL, percentile: Math.ceil(account.platformPercentile * 100),
    originalText: record.originalText, sourceURL: record.evidenceURL, publishedAt: record.publishedAt,
    publishedDay, reference: first.price, referenceDay: first.priceDay, startDay: candles[0].day,
    endDay: candles.at(-1).day, peak: peak.high, peakDay: peak.day, peakChange,
    priceSource: record.priceEvidence.source, candles: candles.map(c => [c.day, c.close]), calls,
    avatar: image(path.join(root, `ios/BSmart/Assets.xcassets/AuthorAvatar_${hash}.imageset/avatar.jpg`)),
    logo: image(path.join(logoDirectory, logo)),
  };
});
assert(Math.abs(data[0].peakChange - 429.0447685692606) < .0001);
fs.writeFileSync(path.join(here, 'data.js'), `// Generated from local project snapshots; not live returns.\nconst STORY_DATA = ${JSON.stringify(data)};\n`);
const script = file => `<script>${fs.readFileSync(file, 'utf8').replace(/<\/script/gi, '<\\/script')}</script>`;
const html = fs.readFileSync(path.join(here, 'index.html'), 'utf8')
  .replace('<link rel="stylesheet" href="styles.css">', () => `<style>${fs.readFileSync(path.join(here, 'styles.css'), 'utf8')}</style>`)
  .replace('<script src="../investor-discovery/lucide.min.js"></script>', () => script(path.join(here, '../investor-discovery/lucide.min.js')))
  .replace('<script src="data.js"></script>', () => script(path.join(here, 'data.js')))
  .replace('<script src="app.js"></script>', () => script(path.join(here, 'app.js')));
fs.writeFileSync(path.join(here, 'bsmart-representative-work.html'), html);
console.log(JSON.stringify({ bytes: Buffer.byteLength(html), examples: data.map(d => ({ name: d.name, ticker: d.ticker, reference: d.reference, peak: d.peak, peakDay: d.peakDay, cutoff: d.endDay, peakChange: d.peakChange, bullish: d.calls.filter(c => c.direction === 'bullish').length, bearish: d.calls.filter(c => c.direction === 'bearish').length })) }, null, 2));
