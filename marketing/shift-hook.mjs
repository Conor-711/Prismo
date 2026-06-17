import fs from 'node:fs';
const f = 'marketing/redditalpha-launch.html';
const D = 1.4; // timeline units (~1s after timeScale 1.42)
const lines = fs.readFileSync(f, 'utf8').split('\n');
let shifting = false, count = 0;
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes(".to('.s1',{autoAlpha:0,y:-46")) shifting = true;   // start at hook exit
  if (lines[i].includes('tl.timeScale(')) shifting = false;                  // stop before timeScale
  if (shifting) {
    lines[i] = lines[i].replace(/,(\d+(?:\.\d+)?)\)(;?)\s*$/, (m, num, semi) => {
      const v = Math.round((parseFloat(num) + D) * 100) / 100;
      count++; return ',' + v + ')' + semi;
    });
  }
}
fs.writeFileSync(f, lines.join('\n'));
console.log('shifted', count, 'timeline positions by +' + D);
