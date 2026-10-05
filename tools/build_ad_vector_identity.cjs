/* Original vector identity for Carpet Cleaner. Installed fonts are converted to
 * outlines; no font files or third-party illustrations are distributed. */
'use strict';
const fs = require('fs');
const path = require('path');
const MODULES = 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const {GlobalFonts, createCanvas, convertSVGTextToPath} = require(path.join(MODULES, '@napi-rs/canvas'));
const sharp = require(path.join(MODULES, 'sharp'));
const OUT = path.resolve(__dirname, '../design/marketing/ad_production_v2/art');
for (const p of [OUT, path.join(OUT, 'editable_text'), path.join(OUT, 'previews')]) fs.mkdirSync(p, {recursive:true});
GlobalFonts.registerFromPath('C:/Windows/Fonts/ARLRDBD.TTF', 'CarpetRounded');
GlobalFonts.registerFromPath('C:/Windows/Fonts/arialbd.ttf', 'CarpetSans');
const P = {teal:'#154D54', deep:'#103D44', mint:'#77C9AE', leaf:'#4CA78F', cream:'#FFF9E8', orange:'#F57940', gold:'#EDBA43'};
const ctx = createCanvas(1080,1920).getContext('2d');
function tx(copy,x,y,size,color,other='') {return `<text x="${x}" y="${y}" text-anchor="middle" font-family="CarpetRounded" font-size="${size}" fill="${color}" ${other}>${copy}</text>`;}
function fit(copy,preferred,maxWidth) { let size=preferred; do {ctx.font=`${size}px CarpetRounded`; if(ctx.measureText(copy).width<=maxWidth)return size; size--;}while(size>20); throw Error(copy); }
const defs=`<defs>
 <linearGradient id="tealInk" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#245C62"/><stop offset="1" stop-color="#103D44"/></linearGradient>
 <linearGradient id="leafLight" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#98D9B8"/><stop offset="1" stop-color="#55B79D"/></linearGradient>
 <linearGradient id="ribbonMint" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#C9EAB8"/><stop offset="1" stop-color="#9DD5AC"/></linearGradient>
 <linearGradient id="orangeSun" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FF9656"/><stop offset="1" stop-color="#F06C35"/></linearGradient>
 <filter id="softShadow" x="-30%" y="-35%" width="160%" height="180%"><feDropShadow dx="0" dy="10" stdDeviation="6" flood-color="#163D38" flood-opacity=".23"/></filter>
 </defs>`;
function svg(title,body) {return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><title>${title}</title>${defs}${body}</svg>`;}
function sparkle(x,y,r=36,angle=0) {
 const d=`M0 ${-r} C${r*.2} ${-r*.2} ${r*.2} ${-r*.2} ${r*.66} 0 C${r*.2} ${r*.16} ${r*.18} ${r*.2} 0 ${r} C${-r*.2} ${r*.18} ${-r*.2} ${r*.2} ${-r*.66} 0 C${-r*.2} ${-r*.2} ${-r*.18} ${-r*.2} 0 ${-r} Z`;
 return `<g transform="translate(${x} ${y}) rotate(${angle})"><path d="${d}" fill="${P.cream}" stroke="${P.cream}" stroke-width="13" stroke-linejoin="round"/><path d="${d}" fill="#FFF7CB" stroke="${P.gold}" stroke-width="5" stroke-linejoin="round"/></g>`;
}
function leaves(x,y,scale=1,mirror=1,angle=0) {
 return `<g transform="translate(${x} ${y}) rotate(${angle}) scale(${scale*mirror} ${scale})">
  <path d="M8 25 C-20 -40 -88 -77 -104 -51 C-121 -15 -68 27 -4 36 C-70 32 -117 69 -94 87 C-66 108 -22 83 13 42 C31 91 71 107 79 78 C90 41 43 4 8 25Z" fill="${P.cream}" stroke="${P.cream}" stroke-width="19" stroke-linejoin="round"/>
  <path d="M8 27 C-9 -33 -81 -68 -98 -47 C-112 -19 -68 21 8 35Z" fill="url(#leafLight)" stroke="${P.leaf}" stroke-width="3"/>
  <path d="M3 34 C-63 29 -106 62 -89 78 C-67 98 -23 75 11 39Z" fill="#58B59A" stroke="${P.leaf}" stroke-width="3"/>
  <path d="M15 31 C39 20 76 53 72 77 C66 97 37 77 15 31Z" fill="#72C8AB" stroke="${P.leaf}" stroke-width="3"/>
  <path d="M-81 -37 Q-27 -13 12 37 M-79 74 Q-27 57 12 37 M14 34 L60 76" fill="none" stroke="#378F7C" stroke-width="4" stroke-linecap="round"/>
  <path d="M-82 -48 Q-42 -51 -11 -20" fill="none" stroke="#C4EACD" stroke-width="6" stroke-linecap="round" opacity=".75"/>
 </g>`;
}
const titleLines = [['Carpet',510,192,740],['Cleaner',680,190,835]];
const titleText=(fill,stroke,width)=>titleLines.map(([copy,y,size,max])=>tx(copy,540,y,fit(copy,size,max),fill,`stroke="${stroke}" stroke-width="${width}" stroke-linejoin="round" paint-order="stroke fill"`)).join('');
const logo = `<g id="carpet-cleaner-logo" transform="rotate(-3 540 535)" filter="url(#softShadow)">
 <g transform="translate(0 9)">${titleText('#67977B',P.cream,33)}</g>
 ${titleText('url(#tealInk)',P.cream,30)}
 ${titleText('url(#tealInk)','url(#tealInk)',2)}
 </g>`;
const ribbon=`<g id="one-more-rug-ribbon" transform="rotate(-3 540 770)" filter="url(#softShadow)">
 <path d="M277 714 Q529 699 804 714 L819 807 Q538 835 264 812Z" fill="url(#ribbonMint)" stroke="${P.cream}" stroke-width="20" stroke-linejoin="round"/>
 <path d="M287 727 Q538 713 793 727" fill="none" stroke="#E7F3CC" stroke-width="8" stroke-linecap="round"/>
 ${tx('One more rug.',540,788,58,P.teal)}
 ${leaves(260,750,.92,1,2)}${leaves(820,731,.82,-1,-13)}
 </g>`;
const cta=`<g id="play-now-cta" filter="url(#softShadow)">
 <rect x="247" y="1191" width="586" height="164" rx="82" fill="#D86335" stroke="${P.cream}" stroke-width="18"/>
 <rect x="247" y="1183" width="586" height="157" rx="79" fill="url(#orangeSun)"/>
 <path d="M310 1197 H770" stroke="#FFBE84" stroke-width="9" stroke-linecap="round" opacity=".72"/>
 ${tx('Play now',540,1259,62,P.cream)}
 ${tx('On Google Play',540,1308,33,P.cream)}
 </g>`;
const decor=`<g id="decorative-clean-sparkles">${sparkle(180,858,38,-3)}${sparkle(879,1007,39,2)}${sparkle(858,328,31,-8)}${sparkle(235,1100,20,3)}</g>`;
const assets=[
 ['logo.svg',logo,'Chunky rounded outlined title'],
 ['ribbon.svg',ribbon,'Mint leaf ribbon'],
 ['cta.svg',cta,'Orange text call to action; no platform badge'],
 ['sparkles.svg',decor,'Small decorative vector sparkles'],
 ['endcard_title.svg',logo+ribbon,'Rounded title and mint leaf ribbon'],
 ['endcard_cta.svg',cta,'Orange call to action, separate motion layer'],
 ['endcard_sparkles.svg',decor,'Separate motion layer of decorative sparkles'],
 ['endcard_overlay.svg',decor+logo+ribbon+cta,'Transparent vector identity above a real full-size rug'],
];
function outlineTextOnly(source) {
 // Preserve native SVG illustration gradients and filters. Converting a whole
 // document through a text outliner can otherwise flatten away SVG effects.
 let index=0;
 return source.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g, textElement=>{
  const outlined=convertSVGTextToPath(svg('Text outline',textElement)).toString('utf8');
  let inner=outlined.slice(outlined.indexOf('>',outlined.indexOf('<svg'))+1,outlined.lastIndexOf('</svg>'));
  const prefix=`outlined${index++}_`;
  inner=inner.replace(/id="([^"]+)"/g,(_,id)=>`id="${prefix}${id}"`).replace(/url\(#([^)]+)\)/g,(_,id)=>`url(#${prefix}${id})`).replace(/xlink:href="#([^"]+)"/g,(_,id)=>`xlink:href="#${prefix}${id}"`);
  return inner;
 });
}
async function run(){
 const manifest={canvas:[1080,1920],palette:P,fonts:'Outlined from locally installed Arial Rounded MT Bold and Arial Bold; no font binaries copied.',provenance:'Original SVG geometry authored for this Carpet Cleaner ad. Decoration only, not gameplay.',assets:[]};
 for(const [name,body,description] of assets){
  const editable=svg(name,body); const output=Buffer.from(outlineTextOnly(editable)); const outputText=output.toString('utf8');
  if(/<text(?:\s|>)/.test(outputText))throw Error('Unoutlined text '+name);
  if(/<image(?:\s|>)/.test(outputText))throw Error('Raster embedded in vector '+name);
  fs.writeFileSync(path.join(OUT,'editable_text',name),editable); fs.writeFileSync(path.join(OUT,name),output);
  await sharp(output).resize(540,960).png().toFile(path.join(OUT,'previews',name.replace('.svg','.png')));
  const {data,info}=await sharp(output).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let x0=1080,y0=1920,x1=-1,y1=-1,clearPixels=0;
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
   const alpha=data[(y*info.width+x)*4+3];
   if(alpha===0)clearPixels++;
   if(alpha>2){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}
  }
  if(clearPixels===0)throw Error('Overlay is opaque '+name);
  manifest.assets.push({file:name,description,outlined:true,transparent:true,clearPixels,paintBounds:{x:x0,y:y0,width:x1-x0+1,height:y1-y0+1}});
 }
 const background=path.resolve(__dirname,'../build/ad-capture-v2/full-game-001/stills/playful_fox_clean_reveal.png');
 if(fs.existsSync(background)){
  const frame=await sharp(background).extract({left:90,top:210,width:900,height:1600}).resize(1080,1920).png().toBuffer();
  const overlay=await sharp(path.join(OUT,'endcard_overlay.svg')).png().toBuffer();
  const composed=await sharp(frame).composite([{input:overlay}]).png().toBuffer();
  await sharp(composed).resize(540,960).png().toFile(path.join(OUT,'previews','endcard_on_game.png'));
 }
 fs.writeFileSync(path.join(OUT,'identity_manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 console.log(JSON.stringify({output:OUT,assets:assets.map(a=>a[0])}));
}
run().catch(error=>{console.error(error);process.exit(1);});
