import fs from 'node:fs';
const f = 'marketing/redditalpha-launch.html';
let s = fs.readFileSync(f, 'utf8');
const squad = `<div class="squad">
        <span class="snoo-wrap"><img class="bob" style="animation-delay:0s"   src="assets/snoo-1.png" alt=""/></span>
        <span class="snoo-wrap"><img class="bob" style="animation-delay:.2s"  src="assets/snoo-b.png" alt=""/></span>
        <span class="snoo-wrap big"><img class="bob" style="animation-delay:.4s" src="assets/snoo-a.png" alt=""/></span>
        <span class="snoo-wrap"><img class="bob" style="animation-delay:.6s"  src="assets/snoo-c.png" alt=""/></span>
        <span class="snoo-wrap"><img class="bob" style="animation-delay:.8s"  src="assets/snoo-3.png" alt=""/></span>
      </div>`;
const before = s.length;
s = s.replace(/<div class="squad">[\s\S]*?<\/div>/, squad);
if (s.length === before && !s.includes('snoo-a.png')) { console.log('WARN: squad not replaced'); }
fs.writeFileSync(f, s);
console.log('squad replaced -> snoo-1,b,a,c,3');
