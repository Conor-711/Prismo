import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'contracts/fixtures/smart-account-updates.json'), 'utf8'));
const examples = [
  { id: 'fef17e16-4307-5863-9cc3-b360d468e118', shortName: 'Coach Mak', title: '关注突破，也明确失效边界' },
  { id: 'd212cddf-459f-56ef-9165-3876df3e1178', shortName: 'Peter DiCarlo', title: '减持空头，等待下一次阻力测试' },
  { id: 'b8f47a12-16e6-570a-9a9f-4beb5e24cd89', shortName: 'Bobby Plewniak', title: '估值之外，仍需基本面支撑' },
];
function asset(file) {
  const type = { '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml' }[path.extname(file)];
  if (!type) throw new Error(`Unsupported image: ${file}`);
  return `data:${type};base64,${fs.readFileSync(file).toString('base64')}`;
}
const data = examples.map(example => {
  const record = catalog.find(row => row.id === example.id);
  if (!record) throw new Error(`Missing fixture ${example.id}`);
  const hash = crypto.createHash('sha256').update(record.authorAvatarURL).digest('hex');
  const logoDir = path.join(root, `ios/BSmart/Assets.xcassets/Ticker_${record.ticker}.imageset`);
  const contents = JSON.parse(fs.readFileSync(path.join(logoDir, 'Contents.json'), 'utf8'));
  const logoFile = contents.images.find(image => image.filename)?.filename;
  return {
    ...example, authorName: record.authorName, ticker: record.ticker, companyName: record.companyName,
    summary: record.activityTitleZH, direction: record.direction, horizon: record.horizon,
    originalText: record.originalText, sourceURL: record.sourceURL,
    percentile: Math.ceil(record.platformPercentile * 100), publishedAt: record.publishedAt,
    date: new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'Asia/Shanghai' }).format(new Date(record.publishedAt)),
    avatar: asset(path.join(root, `ios/BSmart/Assets.xcassets/AuthorAvatar_${hash}.imageset/avatar.jpg`)),
    logo: asset(path.join(logoDir, logoFile)), platformImage: asset(path.join(root, 'web/public/platform/x.png')),
  };
});
const dataScript = `// Generated from existing project fixtures.\nconst COVER_DATA = ${JSON.stringify(data)};\n`;
fs.writeFileSync(path.join(here, 'data.js'), dataScript);
const script = file => `<script>${fs.readFileSync(file, 'utf8').replace(/<\/script/gi, '<\\/script')}</script>`;
const html = fs.readFileSync(path.join(here, 'index.html'), 'utf8')
  .replace('<link rel="stylesheet" href="styles.css">', () => `<style>${fs.readFileSync(path.join(here, 'styles.css'), 'utf8')}</style>`)
  .replace('<script src="../investor-discovery/lucide.min.js"></script>', () => script(path.join(here, '../investor-discovery/lucide.min.js')))
  .replace('<script src="data.js"></script>', () => script(path.join(here, 'data.js')))
  .replace('<script src="app.js"></script>', () => script(path.join(here, 'app.js')));
fs.writeFileSync(path.join(here, 'opinion-cover-options.html'), html);
console.log(`Bundled 3 concepts, 3 source examples: ${Buffer.byteLength(html)} bytes, no external dependencies.`);
