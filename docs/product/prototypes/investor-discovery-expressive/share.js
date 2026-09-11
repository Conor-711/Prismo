/* Share images are a read-only projection of the same local author snapshot. */
window.ExpressiveShare = (() => {
  const colors = { mint: '#d5ffd6', ice: '#d7e6ff', lilac: '#eee1f9' };
  const fonts = '-apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif';
  const images = new Map();
  let revision = 0;
  let ready = Promise.resolve();
  function loadImage(src) {
    if (!src) return Promise.resolve(null);
    if (!images.has(src)) images.set(src, new Promise(resolve => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      img.src = src;
    }));
    return images.get(src);
  }
  function font(ctx, size, weight = 500) { ctx.font = `${weight} ${size}px ${fonts}`; }
  function label(ctx, text, x, y, size = 28, weight = 500, color = '#14231b') {
    font(ctx, size, weight); ctx.fillStyle = color; ctx.fillText(text, x, y);
  }
  function lines(ctx, value, x, y, width, size, lineHeight, maxLines, weight = 500) {
    font(ctx, size, weight);
    const chars = [...String(value)];
    let line = '', row = 0;
    while (chars.length && row < maxLines) {
      const char = chars.shift();
      if (ctx.measureText(line + char).width > width && line) {
        if (row === maxLines - 1) {
          while (ctx.measureText(line + '…').width > width) line = line.slice(0, -1);
          ctx.fillText(line + '…', x, y + row * lineHeight);
          return;
        }
        ctx.fillText(line, x, y + row * lineHeight); row++; line = char;
      } else line += char;
    }
    if (line && row < maxLines) ctx.fillText(line, x, y + row * lineHeight);
  }
  function name(ctx, text, x, y, width, maxSize = 78, maxLines = 2) {
    let size = maxSize;
    while (size > 36) { font(ctx, size, 700); if (ctx.measureText(text).width <= width) break; size -= 2; }
    ctx.fillStyle = '#14231b'; lines(ctx, text, x, y, width, size, size * 1.15, maxLines, 700);
  }
  function line(ctx, y) { ctx.fillStyle = '#14231b33'; ctx.fillRect(65, y, 950, 2); }
  function avatar(ctx, person, image, x, y, size) {
    ctx.save(); ctx.beginPath(); ctx.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2); ctx.clip();
    ctx.fillStyle = '#38574a'; ctx.fillRect(x, y, size, size);
    if (image) {
      const side = Math.min(image.width, image.height);
      ctx.drawImage(image, (image.width - side) / 2, (image.height - side) / 2, side, side, x, y, size, size);
    } else {
      ctx.textAlign = 'center'; label(ctx, [...person.name.replace(/^@/, '')][0] || '?', x + size / 2, y + size * .66, size * .43, 650, '#e3f8e8'); ctx.textAlign = 'left';
    }
    ctx.restore();
  }
  function top(ctx, text) {
    label(ctx, 'b', 65, 93, 49, 800); label(ctx, 'Smart', 96, 93, 49, 800);
    ctx.textAlign = 'right'; label(ctx, text, 1015, 86, 22, 650); ctx.textAlign = 'left'; line(ctx, 124);
  }
  function footer(ctx, detail, type) {
    line(ctx, 1285);
    label(ctx, detail, 65, 1330, 23, 500, '#405d4a');
    label(ctx, 'X · 数据快照 2026.09.09 · 非实时排名', 65, 1370, 22, 500, '#405d4a');
    ctx.textAlign = 'right'; label(ctx, type, 1015, 1370, 20, 650); ctx.textAlign = 'left';
  }
  function rank(person) { return `Top ${(person.percentile * 100).toFixed(1)}%`; }
  function draw(model) {
    const mine = ++revision;
    const canvas = document.getElementById('poster');
    ready = (async () => {
      const temp = document.createElement('canvas'); temp.width = 1080; temp.height = 1440;
      const ctx = temp.getContext('2d');
      ctx.fillStyle = colors[model.theme] || colors.mint; ctx.fillRect(0, 0, 1080, 1440);
      const p = model.person;
      const picture = await loadImage(p.avatar);
      if (model.kind === 'lineup') {
        const people = model.followed.slice(model.page * 6, model.page * 6 + 6);
        const imgs = await Promise.all(people.map(p => loadImage(p.avatar)));
        top(ctx, 'MY RESEARCH LINEUP');
        label(ctx, '我的研究阵容', 65, 234, 73, 700);
        label(ctx, `${model.followed.length} 位投资者 / 我选择关注的视角`, 68, 296, 29, 500, '#405d4a');
        if (!people.length) {
          label(ctx, '还没有追踪的投资者', 65, 670, 49, 600);
          label(ctx, '我的阵容，留给自己的选择。', 65, 731, 30, 500, '#405d4a');
        }
        if (people.length === 1) {
          const person = people[0];
          avatar(ctx, person, imgs[0], 365, 378, 350);
          ctx.textAlign = 'center';
          name(ctx, person.name, 540, 843, 930, 76, 1);
          label(ctx, `${model.sectorLabel(person.sector)} · ${rank(person)}`, 540, 916, 31, 500, '#405d4a');
          label(ctx, String(person.score), 540, 1085, 127, 550);
          label(ctx, 'Score / X 平台排名', 540, 1141, 27, 500, '#405d4a');
          ctx.textAlign = 'left';
        } else if (people.length <= 3) {
          const stride = people.length === 2 ? 395 : 278;
          people.forEach((person, i) => {
            const y = 398 + i * stride;
            avatar(ctx, person, imgs[i], 65, y, 168);
            name(ctx, person.name, 269, y + 56, 510, 44, 1);
            label(ctx, model.sectorLabel(person.sector), 272, y + 112, 27, 500, '#405d4a');
            label(ctx, rank(person), 272, y + 155, 27, 600);
            ctx.textAlign = 'right'; label(ctx, String(person.score), 1010, y + 75, 70, 600); label(ctx, 'Score', 1010, y + 121, 22, 500); ctx.textAlign = 'left';
            if (i < people.length - 1) line(ctx, y + stride - 38);
          });
        } else {
          people.forEach((person, i) => {
            const x = i % 2 === 0 ? 292 : 787, y = 364 + Math.floor(i / 2) * 294;
            avatar(ctx, person, imgs[i], x - 78, y, 156);
            ctx.textAlign = 'center';
            name(ctx, person.name, x, y + 203, 435, 36, 1);
            label(ctx, `${rank(person)} · Score ${person.score}`, x, y + 247, 25, 550, '#405d4a');
            ctx.textAlign = 'left';
          });
        }
        footer(ctx, '个人关注名单，不代表作者合作或背书；历史评分不保证未来表现。', `${model.page + 1} / ${Math.max(1, Math.ceil(model.followed.length / 6))}`);
      } else if (model.kind === 'opinion') {
        const o = model.opinion;
        top(ctx, 'A PERSPECTIVE WORTH READING');
        if (o) {
          label(ctx, o.ticker, 65, 335, 151, 750);
          const direction = o.direction === 'bullish' ? '看多' : o.direction === 'bearish' ? '看空' : '中性';
          label(ctx, `${direction} / ${o.at.slice(0, 10)}`, 72, 415, 37, 650);
          line(ctx, 465); label(ctx, '观点摘要', 68, 522, 25, 500, '#405d4a');
          ctx.fillStyle = '#14231b'; lines(ctx, o.text, 65, 598, 950, 45, 72, 6, 600);
        } else {
          label(ctx, '暂无近期观点', 65, 390, 70, 650);
          label(ctx, '当前作者的快照未包含近期观点。', 65, 470, 33, 500, '#405d4a');
        }
        avatar(ctx, p, picture, 65, 1075, 108); name(ctx, p.name, 202, 1120, 715, 48, 1);
        label(ctx, `${rank(p)} · Score ${p.score} · X 平台排名`, 205, 1175, 27, 500, '#405d4a');
        label(ctx, p.handle, 205, 1220, 24, 500, '#405d4a');
        footer(ctx, '结构化摘要，非作者逐字原文；历史评分不保证未来表现。', 'PERSPECTIVE');
      } else {
        top(ctx, 'SMART ACCOUNT / DISCOVERY');
        label(ctx, '投资者名片', 65, 214, 28, 650, '#405d4a');
        avatar(ctx, p, picture, 65, 276, 245);
        ctx.textAlign = 'right'; label(ctx, String(p.score), 1010, 440, 157, 550); label(ctx, 'Score', 1005, 505, 33, 500); ctx.textAlign = 'left';
        name(ctx, p.name, 65, 650, 950);
        label(ctx, p.handle, 68, 769, 30, 500, '#405d4a');
        line(ctx, 818);
        label(ctx, rank(p), 65, 915, 76, 650); label(ctx, 'X 平台排名', 68, 960, 24, 500, '#405d4a');
        label(ctx, `${p.samples}`, 710, 915, 76, 650); label(ctx, '已结算判断', 714, 960, 24, 500, '#405d4a');
        line(ctx, 1003);
        label(ctx, `${model.sectorLabel(p.sector)} / ${model.styleLabel(p.style)}`, 65, 1070, 32, 600);
        label(ctx, p.tickers.slice(0, 5).join('  ·  '), 65, 1130, 28, 500, '#405d4a');
        label(ctx, '发现，不止于知名度。', 65, 1230, 35, 650);
        footer(ctx, '平台内排名，非实际账户收益；历史评分不保证未来表现。', 'PROFILE');
      }
      if (mine !== revision) return;
      canvas.getContext('2d').drawImage(temp, 0, 0);
      canvas.setAttribute('aria-label', model.kind === 'lineup' ? `我的研究阵容，${model.followed.length} 位已追踪投资者，第 ${model.page + 1} 页` : `${p.name} ${model.kind === 'opinion' ? '观点卡' : '人物名片'}，Score ${p.score}，${rank(p)}`);
    })();
    return ready;
  }
  async function download(filename) {
    await ready;
    const canvas = document.getElementById('poster');
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    if (!blob) throw new Error('无法生成图片');
    const url = URL.createObjectURL(blob), link = document.createElement('a');
    link.href = url; link.download = `${filename}.png`; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }
  return { draw, download, get ready() { return ready; } };
})();
