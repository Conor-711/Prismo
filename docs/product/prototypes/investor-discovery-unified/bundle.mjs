import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const read=name=>fs.readFile(path.join(here,name),'utf8');
const snapshot={window:{}};
vm.runInNewContext(await read('../investor-discovery/data.js'),snapshot,{timeout:1000});
const ids=new Set(snapshot.window.DISCOVERY_PEOPLE.map(p=>p.id));
const evidence=JSON.parse(await fs.readFile(path.join(here,'../../../../contracts/fixtures/smart-account-evidence.json'),'utf8'));
const compact=evidence.filter(e=>ids.has(e.authorId) && e.evidenceRole==='representative' && e.representativeTickerRank<=3).map(e=>({
  authorId:e.authorId,ticker:e.ticker,rank:e.representativeTickerRank,text:e.activityTitleZH||e.thesis,
  at:e.publishedAt,direction:e.direction,url:e.sourceURL||e.evidenceURL,
  settlement:e.settlement
}));
await fs.writeFile(path.join(here,'evidence.js'),`// Existing representative evidence, read-only snapshot.\nwindow.DISCOVERY_EVIDENCE=${JSON.stringify(compact)};\n`);
let html=await read('index.html');
const css=await read('styles.css');
html=html.replace('<link rel="stylesheet" href="styles.css">',()=>`<style>${css}</style>`);
for(const file of ['../investor-discovery/lucide.min.js','../investor-discovery/data.js','evidence.js','app.js']) {
  const source=await read(file);
  html=html.replace(`<script src="${file}"></script>`,()=>`<script>${source.replace(/<\/script/gi,'<\\/script')}</script>`);
}
await fs.writeFile(path.join(here,'bsmart-discovery-unified.html'),html);
console.log(`Standalone HTML: ${Buffer.byteLength(html)} bytes; representative records: ${compact.length}`);
