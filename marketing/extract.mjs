import fs from 'node:fs';
const h = fs.readFileSync('marketing/redditalpha-launch.html', 'utf8');
const css = h.slice(h.indexOf('<style>') + 7, h.indexOf('</style>'));
const stage = h.slice(h.indexOf('<div id="stageWrap">'), h.indexOf('<audio'));
// build() body for reference when porting to the Remotion driver
const bs = h.indexOf('function build(){');
const be = h.indexOf('\n}', h.indexOf('return tl;'));
const build = h.slice(bs, be + 2);
fs.writeFileSync('marketing/remotion-content.js',
  'export const CSS = ' + JSON.stringify(css) + ';\n' +
  'export const STAGE_HTML = ' + JSON.stringify(stage) + ';\n');
fs.writeFileSync('marketing/_build_ref.txt', build);
console.log('css', css.length, 'chars; stage', stage.length, 'chars; build', build.length, 'chars');
