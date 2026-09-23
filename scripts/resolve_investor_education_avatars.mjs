import fs from 'node:fs';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name)));
const snapshot = read('web/lib/data/smartVoice.json');
const bundled = read('ios/asset-sources/investor-education.json');
const present = new Set(bundled.authors.map(p => p.id));
const file = path.join(root, 'ios/asset-sources/investor-education-profiles.json');
const records = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file)) : {};
const channels = new Map(JSON.parse(execFileSync('sqlite3', ['-readonly', '-json', path.join(root, 'data/dev.db'),
  'SELECT channel_id,handle FROM yt_channel'], { encoding: 'utf8' })).map(p => [p.channel_id.toLowerCase(), p]));
let proxy = process.env.HTTPS_PROXY;
if (!proxy && process.platform === 'darwin') {
  const system = execFileSync('scutil', ['--proxy'], { encoding: 'utf8' });
  if (/HTTPSEnable : 1/.test(system)) proxy = `http://${system.match(/HTTPSProxy : (\S+)/)?.[1]}:${system.match(/HTTPSPort : (\d+)/)?.[1]}`;
}
const exec = promisify(execFile);
const ids = snapshot.platformBands.youtube.observedIds.filter(id => !present.has(id) && !records[id]?.url);
let cursor = 0;
async function worker() {
  while (cursor < ids.length) {
    const id = ids[cursor++], raw = snapshot.investorIndex[id], channel = channels.get(id.replace(/^youtube:/, ''));
    const handle = raw.handle || channel?.handle;
    const url = handle ? `https://www.youtube.com/${handle.startsWith('@') ? handle : '@' + handle}/about`
      : channel ? `https://www.youtube.com/channel/${channel.channel_id}/about` : null;
    try {
      if (!url) throw new Error('No identity-preserving profile URL');
      const args = ['--fail', '--silent', '--show-error', '--connect-timeout', '8', '--max-time', '25', '--max-filesize', '6000000'];
      if (proxy) args.push('--proxy', proxy);
      args.push(url);
      const html = (await exec('curl', args, { maxBuffer: 6000000 })).stdout;
      const match = html.match(/var ytInitialData = (.*?);<\/script>/s);
      if (!match) throw new Error('Public channel metadata unavailable');
      const metadata = JSON.parse(match[1]).metadata?.channelMetadataRenderer;
      if (metadata?.externalId?.toLowerCase() !== id.replace(/^youtube:/, '')) throw new Error('Channel identity mismatch');
      const avatar = metadata.avatar?.thumbnails?.at(-1)?.url;
      if (!avatar || !['yt3.googleusercontent.com', 'yt3.ggpht.com'].includes(new URL(avatar).hostname)) throw new Error('No channel avatar');
      records[id] = { platform: 'youtube', name: metadata.title, url: avatar, profileURL: url,
        channelID: metadata.externalId, checkedAt: new Date().toISOString(), method: 'Public channel metadata; exact channel ID match' };
      console.log(`Verified ${id}`);
    } catch (error) {
      records[id] = { platform: 'youtube', profileURL: url, checkedAt: new Date().toISOString(), error: error.message.slice(0, 180) };
      console.log(`Unavailable ${id}: ${error.message.slice(0, 80)}`);
    }
    fs.writeFileSync(file, JSON.stringify(records, null, 2) + '\n');
    await new Promise(resolve => setTimeout(resolve, 350));
  }
}
await Promise.all(Array.from({ length: 3 }, worker));
console.log(JSON.stringify({ attempted: ids.length, verified: Object.values(records).filter(p => p.url).length }));
