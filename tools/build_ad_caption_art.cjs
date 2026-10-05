// Native vector lettering and ornaments for the illustrated advertising treatment.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { GlobalFonts, convertSVGTextToPath } = require('@napi-rs/canvas');

const out = path.resolve('design/marketing/ad_production_v2/captions');
fs.mkdirSync(out, { recursive: true });
fs.mkdirSync(path.join(out, 'editable_text'), { recursive: true });
GlobalFonts.registerFromPath('C:/Windows/Fonts/ARLRDBD.TTF', 'Ad Rounded');

const defs = `<defs>
  <linearGradient id="teal" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#32636B"/><stop offset="0.48" stop-color="#204E58"/><stop offset="1" stop-color="#133C46"/>
  </linearGradient>
  <linearGradient id="mint" x1="0" y1="0" x2="1" y2="1">
    <stop stop-color="#8DDCC5"/><stop offset="1" stop-color="#41AA93"/>
  </linearGradient>
  <linearGradient id="orange" x1="0" y1="0" x2="0" y2="1">
    <stop stop-color="#F09A57"/><stop offset="1" stop-color="#DC7339"/>
  </linearGradient>
  <filter id="lift" x="-40%" y="-50%" width="180%" height="220%" color-interpolation-filters="sRGB">
    <feDropShadow dx="0" dy="9" stdDeviation="5" flood-color="#153E44" flood-opacity="0.22"/>
  </filter>
</defs>`;

function lettering(lines, opts = {}) {
  const text = lines.map(({ copy, x = 540, y, size, anchor = 'middle' }) =>
    `<text x="${x}" y="${y}" font-family="Ad Rounded" font-size="${size}" text-anchor="${anchor}" letter-spacing="-2.3">${copy}</text>`).join('');
  // The text is converted to paths after composition, retaining the editable master.
  return `<g filter="url(#lift)"><g fill="#E7DCC0" stroke="#E7DCC0" stroke-width="25" stroke-linejoin="round" transform="translate(0 4)">${text}</g><g fill="#FFFAEA" stroke="#FFFAEA" stroke-width="23" stroke-linejoin="round">${text}</g><g fill="url(#teal)">${text}</g></g>`;
}

function sprig(x, y, scale = 1, rotation = 0) {
  return `<g transform="translate(${x} ${y}) rotate(${rotation}) scale(${scale})">
    <path d="M0 38 C-18 31-38 4-28-20 C-9-22 11 3 0 38 M1 37 C9 14 35-1 47 9 C48 30 26 47 1 43" fill="#FFF9E6" stroke="#FFF9E6" stroke-width="15" stroke-linejoin="round"/>
    <path d="M0 38 C-18 31-38 4-28-20 C-9-22 11 3 0 38" fill="url(#mint)" stroke="#429783" stroke-width="2"/>
    <path d="M1 37 C9 14 35-1 47 9 C48 30 26 47 1 43" fill="url(#mint)" stroke="#429783" stroke-width="2"/>
    <path d="M-19-6 Q-8 10 0 39 M33 18 Q12 25 0 39" fill="none" stroke="#2D897C" stroke-width="3.2" stroke-linecap="round" opacity="0.64"/>
  </g>`;
}

function star(x, y, size = 23, rotation = 0) {
  return `<g transform="translate(${x} ${y}) rotate(${rotation}) scale(${size / 25})">
    <path d="M0-29 C4-7 7-4 24 0 C7 4 4 8 0 29 C-4 8-7 4-24 0 C-7-4-4-7 0-29Z" fill="#FFF8DD" stroke="#FFF8DD" stroke-width="9" stroke-linejoin="round"/>
    <path d="M0-29 C4-7 7-4 24 0 C7 4 4 8 0 29 C-4 8-7 4-24 0 C-7-4-4-7 0-29Z" fill="#FFEFAD" stroke="#E9B342" stroke-width="3" stroke-linejoin="round"/>
  </g>`;
}

const assets = {
  hook_discovery: {
    label: 'FIND THE FOX',
    body: `<g transform="rotate(-3 470 350)">
      ${lettering([{copy:'Find the',x:145,y:347,size:113,anchor:'start'},{copy:'fox.',x:145,y:468,size:148,anchor:'start'}])}
      <path d="M499 443 Q569 462 636 442" fill="none" stroke="#FFF9E6" stroke-width="28" stroke-linecap="round"/>
      <path d="M499 440 Q569 459 636 439" fill="none" stroke="url(#orange)" stroke-width="11" stroke-linecap="round"/>
      ${sprig(746,331,1.06,10)}${star(804,418,21,8)}
    </g>`
  },
  process: {
    label: 'BRUSH. REVEAL.',
    body: `<g transform="rotate(-1.5 540 350)">
      ${lettering([{copy:'Brush. Reveal.',y:384,size:99}])}
      <path d="M360 424 Q541 436 721 418" fill="none" stroke="#FFF9E6" stroke-width="21" stroke-linecap="round"/>
      <path d="M360 423 Q541 435 721 417" fill="none" stroke="#77C9B1" stroke-width="7" stroke-linecap="round"/>
      ${star(899,300,19,-7)}
    </g>`
  },
  reveal: {
    label: 'FRESH AGAIN.',
    body: `<g transform="rotate(-2 540 350)">
      ${lettering([{copy:'Fresh again.',y:385,size:109}])}
      ${sprig(117,381,.77,-26)}${star(935,336,23,4)}
    </g>${star(122,611,20,-6)}${star(951,1090,24,8)}`
  },
  next_rug: {
    label: 'ONE MORE RUG?',
    body: `<g transform="rotate(-1.5 540 350)">
      ${lettering([{copy:'One more rug?',y:384,size:99}])}
      ${sprig(858,430,.82,56)}
      <path d="M195 424 Q297 447 399 422" fill="none" stroke="#FFF9E6" stroke-width="23" stroke-linecap="round"/>
      <path d="M195 423 Q297 446 399 421" fill="none" stroke="url(#orange)" stroke-width="8" stroke-linecap="round"/>
    </g>`
  }
};

async function main() {
  const previewItems = [];
  let i = 0;
  for (const [name, { body, label }] of Object.entries(assets)) {
    const editable = `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><title>${label}</title>${defs}${body}</svg>`;
    const outlined = convertSVGTextToPath(editable).toString();
    fs.writeFileSync(path.join(out, 'editable_text', `${name}.svg`), editable, 'utf8');
    fs.writeFileSync(path.join(out, `${name}.svg`), outlined, 'utf8');
    await sharp(Buffer.from(outlined)).png().toFile(path.join(out, `${name}.png`));
    const panel = Buffer.from(`<svg width="540" height="360"><rect width="540" height="360" fill="#CEE8DB"/><path d="M0 300 Q180 270 280 313 T540 305 V360 H0Z" fill="#AFCDBB"/><text x="28" y="330" font-family="Arial" font-size="16" fill="#204E58">${label} · VECTOR OVERLAY</text></svg>`);
    const caption = await sharp(Buffer.from(outlined)).extract({left:0,top:160,width:1080,height:580}).resize(540,290).png().toBuffer();
    const frame = await sharp(panel).composite([{ input:caption,left:0,top:0 }]).png().toBuffer();
    previewItems.push({input:frame,left:(i%2)*560+20,top:Math.floor(i/2)*380+20});
    i++;
  }
  await sharp({create:{width:1140,height:780,channels:4,background:'#fff7e6'}}).composite(previewItems).png().toFile(path.join(out,'Caption_Art_Contact.png'));
  const shots = [['hook_discovery','qa_hook.png'],['process','qa_process.png'],['reveal','qa_reveal.png'],['next_rug','qa_next.png']];
  if (shots.every(([,file]) => fs.existsSync(path.join(out,file)))) {
    const panels = [];
    for (let shot = 0; shot < shots.length; shot++) {
      const [name,file] = shots[shot];
      const composite = await sharp(path.join(out,file)).composite([{input:path.join(out,`${name}.png`),left:0,top:0}]).png().toBuffer();
      await sharp(composite).png().toFile(path.join(out,`${name}_gameplay_preview.png`));
      panels.push({input:await sharp(composite).resize(324,576).png().toBuffer(),left:shot*340+16,top:16});
    }
    await sharp({create:{width:1376,height:608,channels:4,background:'#fff7e6'}}).composite(panels).png().toFile(path.join(out,'Gameplay_Caption_Contact.png'));
  }
  fs.writeFileSync(path.join(out,'README.md'), '# Illustrated caption art\n\nFour transparent 1080 × 1920 SVG overlays. All display lettering is outlined, with editable type masters in `editable_text/`. Palette and rounded die-cut forms follow the original illustrated storyboard. The design intentionally leaves the central cleaning action uncovered. Gold glints on the restored-rug overlay are decorative graphic art.\n\nRegenerate with `tools/build_ad_caption_art.cjs` using the bundled Node runtime.\n', 'utf8');
  console.log(JSON.stringify({output:out,assets:Object.keys(assets)}));
}
main().catch(error => { console.error(error); process.exit(1); });
