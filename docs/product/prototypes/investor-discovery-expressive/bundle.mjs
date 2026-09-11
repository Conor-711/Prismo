import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const read = name => fs.readFile(path.join(here, name), 'utf8');
let html = await read('index.html');
const css = await read('styles.css');
html = html.replace('<link rel="stylesheet" href="styles.css">', () => `<style>${css}</style>`);
for (const file of ['../investor-discovery/lucide.min.js', '../investor-discovery/data.js', '../investor-discovery-unified/evidence.js', 'share.js', 'app.js']) {
  const source = await read(file);
  html = html.replace(`<script src="${file}"></script>`, () => `<script>${source.replace(/<\/script/gi, '<\\/script')}</script>`);
}
const output = path.join(here, 'bsmart-discovery-expressive.html');
await fs.writeFile(output, html);
console.log(`Standalone HTML: ${output} (${Buffer.byteLength(html)} bytes)`);
