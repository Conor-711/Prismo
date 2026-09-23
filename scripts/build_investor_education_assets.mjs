import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require(process.env.SHARP_PATH || 'sharp');
const root = path.resolve(import.meta.dirname, '..');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file)));
const output = path.join(root, 'output/design/investor-education');
const cache = path.join(output, 'avatar-cache');
const resources = path.join(root, 'ios/BSmart/Resources');
fs.mkdirSync(cache, { recursive: true });
fs.mkdirSync(resources, { recursive: true });
const exec = promisify(execFile);
const snapshot = read('web/lib/data/smartVoice.json');
const catalogue = read('ios/asset-sources/author-avatars.json').avatars;
const profiles = read('contracts/fixtures/smart-accounts.json');
const metadata = JSON.parse(execFileSync('sqlite3', ['-readonly', '-json', path.join(root, 'data/dev.db'),
  "SELECT author_id,handle,name,avatar_url FROM author_profile WHERE source='x'"], { encoding: 'utf8' }));
const byID = new Map(metadata.map(p => [p.author_id, p]));
const profileByID = new Map(profiles.map(p => [p.id, p]));
const youtubeAvatars = new Map(JSON.parse(execFileSync('sqlite3', ['-readonly', '-json', path.join(root, 'data/dev.db'),
  "SELECT handle,url FROM author_avatar WHERE source='youtube'"], { encoding: 'utf8' })).map(p => [p.handle.toLowerCase().replace(/^@/, ''), p.url]));
const redditAvatars = read('contracts/fixtures/reddit-author-avatars.json');
const platformNames = { x: 'X', youtube: 'YouTube', reddit: 'Reddit' };
const resolvedFile = path.join(root, 'ios/asset-sources/investor-education-profiles.json');
const redditResolvedFile = path.join(root, 'ios/asset-sources/investor-education-reddit-profiles.json');
const resolved = { ...(fs.existsSync(resolvedFile) ? JSON.parse(fs.readFileSync(resolvedFile)) : {}),
  ...(fs.existsSync(redditResolvedFile) ? JSON.parse(fs.readFileSync(redditResolvedFile)) : {}) };
const previousFile = path.join(root, 'ios/asset-sources/investor-education.json');
const previousFailures = new Set(fs.existsSync(previousFile) ? JSON.parse(fs.readFileSync(previousFile)).unavailable : []);
let proxy = process.env.HTTPS_PROXY;
if (!proxy && process.platform === 'darwin') {
  const system = execFileSync('scutil', ['--proxy'], { encoding: 'utf8' });
  if (/HTTPSEnable : 1/.test(system)) proxy = `http://${system.match(/HTTPSProxy : (\S+)/)?.[1]}:${system.match(/HTTPSPort : (\d+)/)?.[1]}`;
}
const candidates = Object.keys(platformNames).flatMap(platform => {
  const band = snapshot.platformBands[platform];
  const ranked = new Map(band.rankedIds.map((id, i) => [id, i + 1]));
  return band.observedIds.map(id => {
    const raw = snapshot.investorIndex[id], profile = profileByID.get(id), p = byID.get(id);
    const handle = (raw.handle || '').toLowerCase().replace(/^@|^u\//, '');
    const url = resolved[id]?.url || (platform === 'x' ? p?.avatar_url || raw.avatar : platform === 'youtube'
      ? youtubeAvatars.get(id.replace(/^youtube:/, '')) || youtubeAvatars.get(handle) || profile?.avatarURL
      : redditAvatars[handle]);
    return { id, platform, name: resolved[id]?.name || profile?.name || p?.name || raw.name, url,
      rank: ranked.get(id) || 0, handle: p?.handle || raw.handle || '' };
  }).filter(p => {
    try { return ['pbs.twimg.com', 'yt3.ggpht.com', 'yt3.googleusercontent.com', 'i.redd.it', 'www.redditstatic.com', 'styles.redditmedia.com'].includes(new URL(p.url).hostname); }
    catch { return false; }
  });
});
const results = [], failures = [];
let cursor = 0, finished = 0;
async function worker() {
  while (cursor < candidates.length) {
    const p = candidates[cursor++], filename = path.join(cache, `${p.id}.jpg`);
    try {
      if (previousFailures.has(p.id) && !resolved[p.id]?.url && !fs.existsSync(filename) && !process.argv.includes('--retry-unavailable')) {
        failures.push(p.id);
        finished++;
        continue;
      }
      if (!fs.existsSync(filename)) {
        let bytes;
        const local = catalogue[p.url];
        if (local?.status === 'bundled') {
          const folder = path.join(root, 'ios/BSmart/Assets.xcassets', `AuthorAvatar_${local.key}.imageset`);
          const asset = JSON.parse(fs.readFileSync(path.join(folder, 'Contents.json'))).images.find(i => i.filename);
          bytes = fs.readFileSync(path.join(folder, asset.filename));
        } else {
          const args = ['--fail', '--silent', '--show-error', '--connect-timeout', '5', '--max-time', '16', '--max-filesize', '3000000'];
          if (proxy) args.push('--proxy', proxy);
          // Search-index snapshots may contain expired Reddit image-transform signatures.
          // The same public original asset remains at the verified path without transforms.
          const downloadURL = new URL(p.url);
          if (downloadURL.hostname === 'styles.redditmedia.com') downloadURL.search = '';
          args.push(downloadURL.href);
          bytes = (await exec('curl', args, { encoding: 'buffer', maxBuffer: 3000000 })).stdout;
        }
        await sharp(bytes, { limitInputPixels: 16000000 }).rotate().resize(64, 64, { fit: 'cover' }).jpeg({ quality: 80 }).toFile(filename);
      }
      await sharp(filename).metadata();
      results.push({ ...p, filename });
    } catch { failures.push(p.id); }
    finished++;
    if (finished % 100 === 0) console.log(`Avatars ${finished}/${candidates.length}; ready ${results.length}; unavailable ${failures.length}`);
  }
}
await Promise.all(Array.from({ length: 6 }, worker));
const order = new Map(candidates.map((p, i) => [p.id, i]));
results.sort((a, b) => order.get(a.id) - order.get(b.id));
const selected = Object.keys(platformNames).flatMap(platform => results.filter(p => p.platform === platform).slice(0, 1000));
const columns = 32, tile = 64, rows = Math.ceil(selected.length / columns);
const atlas = path.join(resources, 'InvestorEducationAtlas.jpg');
await sharp({ create: { width: columns * tile, height: rows * tile, channels: 3, background: '#080b0d' } })
  .composite(selected.map((p, i) => ({ input: p.filename, left: i % columns * tile, top: Math.floor(i / columns) * tile })))
  .jpeg({ quality: 83 }).toFile(atlas);
const allEvidence = read('contracts/fixtures/smart-account-evidence.json');
const evidence = allEvidence.find(e => e.id === '8d028d61-dcc2-530b-9cb5-ee372297beb7');
const author = profiles.find(p => p.id === evidence.authorId);
const s = evidence.settlement;
if (!(s.contribution > 0 && s.tickerReturnPercent > 0)) throw new Error('Education example must have an existing positive contribution');
const value = {
  snapshotDate: snapshot.updatedAt,
  columns, tile, atlasWidth: columns * tile, atlasHeight: rows * tile,
  platforms: Object.entries(platformNames).map(([id, name]) => {
    const band = snapshot.platformBands[id];
    return { id, name, totalObserved: band.totalCount, rankedCount: band.rankedCount,
      selectedCount: Math.floor(band.rankedCount * .25),
      authors: selected.map((p, tile) => ({ ...p, tile })).filter(p => p.platform === id)
        .map(p => ({ id: p.id, name: p.name, rank: p.rank, tile: p.tile })) };
  }),
  example: { id: evidence.id, authorID: author.id, authorName: author.name, handle: author.handle,
    avatarURL: author.avatarURL, rank: author.platformRank, percentile: author.platformPercentile,
    settledCalls: author.settledCalls, ticker: evidence.ticker,
    publishedAt: evidence.publishedAt, sourceURL: evidence.evidenceURL,
    summaryZH: 'AI 不只需要 GPU，也需要内存和存储。我看好 SNDK，并计划长期持有。',
    summaryEN: 'AI needs more than GPUs. It needs memory and storage. I see SNDK as a beneficiary and plan to hold.',
    entryDay: s.entryDay, exitDay: s.exitDay, entryPrice: s.entryPrice, exitPrice: s.exitPrice,
    returnPercent: s.tickerReturnPercent, contribution: s.contribution, horizon: s.horizon,
    source: evidence.priceEvidence.source,
    candles: evidence.priceEvidence.candles.filter(c => c.day >= '2025-11-03' && c.day <= s.exitDay).map(c => ({ day: c.day, close: c.close })) }
};
const json = path.join(output, 'education-data.json');
fs.writeFileSync(json, JSON.stringify(value, null, 2));
execFileSync('plutil', ['-convert', 'xml1', '-o', path.join(resources, 'InvestorEducation.plist'), json]);
const provenance = { generatedAt: new Date().toISOString(), snapshotDate: snapshot.updatedAt,
  available: results.length, bundled: selected.length, unavailable: failures,
  atlasBytes: fs.statSync(atlas).size, decodedAtlasBytes: columns * tile * rows * tile * 4,
  platforms: value.platforms.map(({ authors, ...p }) => ({ ...p, portraits: authors.length,
    missingAuthorIDs: snapshot.platformBands[p.id].observedIds.filter(id => !authors.some(author => author.id === id)) })),
  authors: selected.map(({ filename, ...p }, tile) => ({ ...p, tile })) };
fs.writeFileSync(path.join(root, 'ios/asset-sources/investor-education.json'), JSON.stringify(provenance, null, 2));
console.log(JSON.stringify({ bundled: selected.length, available: results.length, failures: failures.length,
  atlasBytes: provenance.atlasBytes, decodedAtlasBytes: provenance.decodedAtlasBytes, platforms: provenance.platforms }));
