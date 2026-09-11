import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../..');
const read = async name => JSON.parse(await fs.readFile(path.join(root, 'contracts/fixtures', name), 'utf8'));
const accounts = await read('smart-accounts.json');
const updates = await read('smart-account-updates.json');
const selected = accounts.filter(a => a.platform === 'X' && a.platformPercentile <= .25).slice(0, 28);
const people = [];
for (const a of selected) {
  let avatar = '';
  if (a.avatarURL) {
    const sources = [a.avatarURL, `https://images.weserv.nl/?url=${encodeURIComponent(a.avatarURL)}&w=192&h=192`];
    for (const source of sources) {
    try {
      const r = await fetch(source, { signal: AbortSignal.timeout(8000) });
      if (r.ok && r.headers.get('content-type')?.startsWith('image/')) {
        avatar = `data:${r.headers.get('content-type').split(';')[0]};base64,${Buffer.from(await r.arrayBuffer()).toString('base64')}`;
        break;
      }
    } catch { /* Offline prototypes fall back to initials. */ }
    }
  }
  const opinions = updates.filter(u => u.authorId === a.id).sort((a, b) => b.publishedAt.localeCompare(a.publishedAt)).slice(0, 5).map(u => ({
    ticker: u.ticker, text: u.activityTitleZH || u.thesis, at: u.publishedAt,
    direction: u.direction, url: u.sourceURL || u.evidenceURL, horizon: u.horizon
  }));
  people.push({ id: a.id, name: a.name, handle: a.handle, score: a.score, percentile: a.platformPercentile,
    sector: a.specialty, horizon: a.horizon, style: a.style, samples: a.settledCalls,
    tickers: a.topTickers, avatar, opinions, platform: a.platform });
}
await fs.writeFile(path.join(here, 'data.js'), `// Read-only local fixture excerpt; generated 2026-09-09. Not live market data.\nwindow.DISCOVERY_PEOPLE = ${JSON.stringify(people)};\n`);
const icons = await fetch('https://unpkg.com/lucide@0.468.0/dist/umd/lucide.min.js', { signal: AbortSignal.timeout(15000) });
if (!icons.ok) throw new Error('Lucide download failed');
await fs.writeFile(path.join(here, 'lucide.min.js'), await icons.text());
console.log(JSON.stringify({ people: people.length, embeddedAvatars: people.filter(p => p.avatar).length, opinions: people.reduce((n,p) => n+p.opinions.length,0) }));
