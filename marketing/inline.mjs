import fs from 'node:fs';
const dir = 'marketing/assets';
const html = 'marketing/redditalpha-launch.html';
const map = {
  'assets/logo.png':'logo.png',
  'assets/reddit_logo.png':'reddit_logo.png',
  'assets/keith.png':'keith.png',
  'assets/wsbgod.png':'wsbgod.png',
  'assets/serenity.png':'serenity.png',
  'assets/snoo-1.png':'snoo-1.png',
  'assets/snoo-2.png':'snoo-2.png',
  'assets/snoo-3.png':'snoo-3.png',
  'assets/snoo-4.png':'snoo-4.png',
  'assets/snoo-a.png':'snoo-a.png',
  'assets/snoo-b.png':'snoo-b.png',
  'assets/snoo-c.png':'snoo-c.png',
  'assets/icon.png':'icon.png',
};
let s = fs.readFileSync(html, 'utf8');
let total = 0, n = 0;
for (const [ref, name] of Object.entries(map)) {
  let p = dir + '/min/' + name;
  if (!fs.existsSync(p)) p = dir + '/' + name;
  if (!fs.existsSync(p)) { console.log('MISSING', name); continue; }
  const b64 = fs.readFileSync(p).toString('base64');
  const uri = 'data:image/png;base64,' + b64;
  const hits = s.split('src="' + ref + '"').length - 1;
  s = s.split('src="' + ref + '"').join('src="' + uri + '"');
  total += b64.length; n += hits;
  console.log(`inlined ${name}  (${Math.round(b64.length/1024)}KB, ${hits} ref)`);
}
fs.writeFileSync(html, s);
console.log(`DONE. replaced ${n} srcs · final html ${Math.round(s.length/1024)}KB`);
