import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const read = name => fs.readFile(path.join(here, name), 'utf8');
let html = await read('index.html');
const styles = await read('styles.css');
html = html.replace('<link rel="stylesheet" href="styles.css">', () => `<style>${styles}</style>`);
function script(source) { return `<script>${source.replace(/<\/script/gi, '<\\/script')}</script>`; }
for (const file of ['lucide.min.js', 'data.js', 'app.js']) {
  const source = await read(file);
  html = html.replace(`<script src="${file}"></script>`, () => script(source));
}
await fs.writeFile(path.join(here, 'bsmart-investor-discovery.html'), html);
console.log(`Standalone HTML: ${Buffer.byteLength(html)} bytes`);
