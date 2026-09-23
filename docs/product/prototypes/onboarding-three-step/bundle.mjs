import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const authorID='1940360837547565056';
// Reuse the shipped Swift projection rather than derive a second price history.
const bundled=JSON.parse(execFileSync('python3',['-c',
  'import plistlib,json,sys; d=plistlib.load(open(sys.argv[1],"rb")); r=next(x for x in d["stories"] if x["account"]["id"]==sys.argv[2]); print(json.dumps(r,default=str))',
  path.join(root,'ios/BSmart/Resources/representative-stories.plist'),authorID],{encoding:'utf8'}));
const accounts=JSON.parse(fs.readFileSync(path.join(root,'contracts/fixtures/smart-accounts.json'),'utf8'));
const account=accounts.find(x=>x.id===authorID);
const evidence=JSON.parse(fs.readFileSync(path.join(root,'contracts/fixtures/smart-account-evidence.json'),'utf8'));
const updates=JSON.parse(fs.readFileSync(path.join(root,'contracts/fixtures/smart-account-updates.json'),'utf8'));
const update=updates.filter(x=>x.authorId===authorID&&x.ticker===bundled.ticker).sort((a,b)=>b.publishedAt.localeCompare(a.publishedAt))[0];
if(update?.sourcePostId!=='2091843192639672553'||account.handle!=='@aleabitoreddit'||bundled.ticker!=='AAOI')throw Error('Review example copy when its source changes');
const image=(file,mime)=>`data:${mime};base64,${fs.readFileSync(path.join(root,file)).toString('base64')}`;
const avatarHash=createHash('sha256').update(account.avatarURL).digest('hex');
const logoDirectory=`ios/BSmart/Assets.xcassets/Ticker_${bundled.ticker}.imageset`;
const logoFile=JSON.parse(fs.readFileSync(path.join(root,logoDirectory,'Contents.json'),'utf8')).images.find(x=>x.filename).filename;
const calls=bundled.calls.map(call=>({...call,sourceURL:call.sourceURL.relative,
  originalText:evidence.find(e=>e.id.toLowerCase()===call.id.toLowerCase())?.originalText??null}));
const first=calls[0];
const story={id:account.id,name:account.name,handle:account.handle,ticker:bundled.ticker,company:'应用光电',
  percentile:Math.ceil(account.platformPercentile*100),reference:first.price,referenceDay:first.priceDay,
  publishedDay:first.day,endDay:bundled.cutoff,peak:bundled.peak.value,peakDay:bundled.peak.day,
  peakChange:(bundled.peak.value/first.price-1)*100,candles:bundled.prices.map(p=>[p.day,p.value]),calls,
  avatar:image(`ios/BSmart/Assets.xcassets/AuthorAvatar_${avatarHash}.imageset/avatar.jpg`,'image/jpeg'),
  logo:image(`${logoDirectory}/${logoFile}`,{'.png':'image/png','.svg':'image/svg+xml','.jpg':'image/jpeg'}[path.extname(logoFile)])};
const data={story,update,brand:image('ios/BSmart/Assets.xcassets/BSmartWordmark.imageset/wordmark.png','image/png'),atlas:image('ios/BSmart/Resources/InvestorEducationAtlas.jpg','image/jpeg')};
fs.writeFileSync(path.join(here,'data.js'),'const DEMO = '+JSON.stringify(data)+';');
let html=fs.readFileSync(path.join(here,'index.html'),'utf8');
html=html.replace('<link rel="stylesheet" href="styles.css">',()=>`<style>${fs.readFileSync(path.join(here,'styles.css'),'utf8')}</style>`);
for(const source of ['../investor-discovery/lucide.min.js','data.js','app.js'])html=html.replace(`<script src="${source}"></script>`,()=>`<script>${fs.readFileSync(path.join(here,source),'utf8').replace(/<\/script/gi,'<\\/script')}</script>`);
fs.writeFileSync(path.join(here,'bsmart-onboarding.html'),html);
console.log(JSON.stringify({file:path.join(here,'bsmart-onboarding.html'),bytes:Buffer.byteLength(html),author:story.name,viewpoint:update.publishedAt}));
