import fs from 'node:fs';
const f = 'marketing/redditalpha-launch.html';
let s = fs.readFileSync(f, 'utf8');
const b64 = fs.readFileSync('marketing/assets/bgm.mp3').toString('base64');
const uri = 'data:audio/mpeg;base64,' + b64;
if (s.includes('src="assets/bgm.mp3"')) {
  s = s.split('src="assets/bgm.mp3"').join('src="' + uri + '"');
  console.log('audio inlined', Math.round(b64.length / 1024), 'KB');
} else if (/src="data:audio\/mpeg;base64,[^"]*"/.test(s)) {
  s = s.replace(/src="data:audio\/mpeg;base64,[^"]*"/, 'src="' + uri + '"');
  console.log('audio re-inlined', Math.round(b64.length / 1024), 'KB');
} else {
  console.log('WARN: audio src not found');
}
fs.writeFileSync(f, s);
console.log('final html', Math.round(s.length / 1024), 'KB');
