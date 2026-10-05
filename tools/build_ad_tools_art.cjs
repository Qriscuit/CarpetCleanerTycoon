/* Illustrated triptych overlays for the third Carpet Cleaner advertisement.
 * Original vector geometry; installed rounded lettering is outlined for delivery.
 * The windows are reserved for real recorded gameplay, never illustrated actions. */
'use strict';
const fs = require('fs');
const path = require('path');
const MODULES = 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const {GlobalFonts, convertSVGTextToPath} = require(path.join(MODULES, '@napi-rs/canvas'));
const sharp = require(path.join(MODULES, 'sharp'));
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'design/marketing/ad_production_v3/art');
for (const dir of [OUT, path.join(OUT, 'editable_text'), path.join(OUT, 'previews')]) fs.mkdirSync(dir, {recursive:true});
GlobalFonts.registerFromPath('C:/Windows/Fonts/ARLRDBD.TTF', 'CarpetRounded');
GlobalFonts.registerFromPath('C:/Windows/Fonts/arialbd.ttf', 'CarpetSans');
const P = {teal:'#154D54', deep:'#103D44', mint:'#77C9AE', leaf:'#4CA78F', cream:'#FFF9E8', orange:'#F57940', gold:'#EDBA43', water:'#65D4DF'};
const panels = [
 {id:'brush', label:'Brush.', x:64, y:355, width:952, height:450, radius:38, color:P.mint, badgeWidth:316},
 {id:'hose', label:'Wash.', x:64, y:841, width:952, height:450, radius:38, color:P.water, badgeWidth:307},
 {id:'squeegee', label:'Squeegee.', x:64, y:1327, width:952, height:450, radius:38, color:'#F6A582', badgeWidth:447}
];
const defs=`<defs>
 <linearGradient id="ink" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#32636B"/><stop offset=".6" stop-color="#204E58"/><stop offset="1" stop-color="#133C46"/></linearGradient>
 <linearGradient id="mint" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#A9E5C9"/><stop offset="1" stop-color="#49AF96"/></linearGradient>
 <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#F7D573"/><stop offset="1" stop-color="#D6A139"/></linearGradient>
 <linearGradient id="coral" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFB090"/><stop offset="1" stop-color="#E5775B"/></linearGradient>
 <linearGradient id="water" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#B5F2ED"/><stop offset="1" stop-color="#3CBFCF"/></linearGradient>
 <linearGradient id="paper" x1="0" y1="0" x2=".65" y2="1"><stop stop-color="#FFFAEB"/><stop offset="1" stop-color="#F0F3DD"/></linearGradient>
 <filter id="lift" x="-40%" y="-50%" width="180%" height="220%" color-interpolation-filters="sRGB"><feDropShadow dx="0" dy="7" stdDeviation="5" flood-color="#153E44" flood-opacity=".20"/></filter>
 </defs>`;
const wrap=(name,body)=>`<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><title>${name}</title>${defs}${body}</svg>`;
function text(copy,x,y,size,attrs='') { return `<text x="${x}" y="${y}" font-family="CarpetRounded" font-size="${size}" text-anchor="middle" ${attrs}>${copy}</text>`; }
function display(copy,x,y,size) {
 const t=text(copy,x,y,size,'letter-spacing="-1.7"');
 return `<g filter="url(#lift)"><g fill="#DCDAC0" stroke="#DCDAC0" stroke-width="22" stroke-linejoin="round" transform="translate(0 4)">${t}</g><g fill="${P.cream}" stroke="${P.cream}" stroke-width="19" stroke-linejoin="round">${t}</g><g fill="url(#ink)">${t}</g></g>`;
}
function sprig(x,y,scale=1,rotation=0) {
 return `<g transform="translate(${x} ${y}) rotate(${rotation}) scale(${scale})">
  <path d="M1 21 C-35 18-61-9-51-30 C-26-38-1-10 1 21 M4 23 C14-5 41-21 54-5 C60 18 33 34 4 28 M0 27 C-18 18-45 24-45 39 C-29 55-7 41 0 27" fill="${P.cream}" stroke="${P.cream}" stroke-width="12" stroke-linejoin="round"/>
  <path d="M1 21 C-35 18-61-9-51-30 C-26-38-1-10 1 21 M4 23 C14-5 41-21 54-5 C60 18 33 34 4 28" fill="url(#mint)" stroke="#479B83" stroke-width="2.5"/>
  <path d="M0 27 C-18 18-45 24-45 39 C-29 55-7 41 0 27" fill="#6FC1A6" stroke="#479B83" stroke-width="2.5"/>
  <path d="M-36-18 Q-18-3 1 24 M38 2 Q20 12 4 25 M-32 35 L0 26" fill="none" stroke="#3C937F" stroke-width="3" stroke-linecap="round"/>
  <path d="M-40-25 Q-24-25-13-12" fill="none" stroke="#D4F0D9" stroke-width="4" stroke-linecap="round"/>
 </g>`;
}
function star(x,y,r=22,rotation=0) {
 return `<g transform="translate(${x} ${y}) rotate(${rotation}) scale(${r/25})"><path d="M0-29 C4-7 7-4 24 0 C7 4 4 8 0 29 C-4 8-7 4-24 0 C-7-4-4-7 0-29Z" fill="#FFF7CC" stroke="${P.cream}" stroke-width="12" stroke-linejoin="round"/><path d="M0-29 C4-7 7-4 24 0 C7 4 4 8 0 29 C-4 8-7 4-24 0 C-7-4-4-7 0-29Z" fill="#FFF1B4" stroke="${P.gold}" stroke-width="3" stroke-linejoin="round"/></g>`;
}
function brushIcon() {
 const bristles = Array.from({length:8},(_,i)=>`<path d="M${-35+i*10} 37 v13" stroke="${i%3===0?'#D5AE63':'#E6D4A6'}" stroke-width="8" stroke-linecap="round"/>`).join('');
 return `<g transform="rotate(13)">${bristles}<rect x="-43" y="17" width="86" height="29" rx="9" fill="#2D8D7B"/><rect x="-44" y="13" width="88" height="27" rx="9" fill="url(#mint)" stroke="#348F7B" stroke-width="2"/><path d="M-32 18 H29" fill="none" stroke="#CBEDD9" stroke-width="4" stroke-linecap="round"/><rect x="-10" y="6" width="20" height="26" rx="7" fill="#4DA18B"/><path d="M0 21 V-43" stroke="#C6CAA4" stroke-width="13" stroke-linecap="round"/><path d="M-2 17 V-43" stroke="#F5EDCE" stroke-width="10" stroke-linecap="round"/><rect x="-8" y="-53" width="16" height="27" rx="8" fill="#73CBB1"/><path d="M-3-45 V-34" stroke="#BAE8D2" stroke-width="3" stroke-linecap="round"/></g>`;
}
function hoseIcon() {
 // Match the in-game mint handheld sprayer: short ivory lance, green collar,
 // gold outlet and connector, chunky green grip. No invented machine or tank.
 return `<g transform="rotate(29)"><path d="M4-35 C28-59 52-36 39-13" fill="none" stroke="#2F8877" stroke-width="7" stroke-linecap="round"/><rect x="-7" y="-54" width="18" height="14" rx="4" fill="url(#gold)"/><rect x="-13" y="-44" width="26" height="34" rx="7" fill="#2E8575"/><rect x="-7" y="-39" width="13" height="17" rx="4" fill="#77CBAF"/><rect x="-21" y="-16" width="42" height="41" rx="12" fill="url(#mint)" stroke="#3A947D" stroke-width="2"/><rect x="-15" y="-9" width="30" height="19" rx="5" fill="#B3E2D1"/><path d="M0 24 V47" stroke="#EDE8C8" stroke-width="11" stroke-linecap="round"/><rect x="-12" y="37" width="24" height="20" rx="6" fill="#258C7C"/><rect x="-16" y="49" width="32" height="13" rx="5" fill="url(#gold)"/><path d="M-7 64 Q-21 80-13 87 Q0 96 13 87 Q21 80 7 64Z" fill="url(#water)" stroke="#46B7C4" stroke-width="2"/><path d="M-3 69 L-6 84" stroke="#D6FCED" stroke-width="4" stroke-linecap="round"/></g>`;
}
function squeegeeIcon() {
 return `<g transform="rotate(-12)"><rect x="-49" y="35" width="98" height="9" rx="4" fill="#30515B"/><rect x="-49" y="17" width="98" height="22" rx="8" fill="url(#coral)" stroke="#D7755F" stroke-width="2"/><path d="M-32 34 H32" fill="none" stroke="#FFF0D6" stroke-width="4" stroke-linecap="round"/><ellipse cx="0" cy="23" rx="12" ry="10" fill="#348E79"/><path d="M0 21 V-43" stroke="#C6CAA4" stroke-width="13" stroke-linecap="round"/><path d="M-2 17 V-43" stroke="#F4EBD0" stroke-width="10" stroke-linecap="round"/><rect x="-8" y="-50" width="16" height="28" rx="8" fill="url(#coral)"/><circle cx="0" cy="-51" r="8" fill="#328C78"/></g>`;
}
const iconBodies={brush:brushIcon(),hose:hoseIcon(),squeegee:squeegeeIcon()};
const background=`<rect width="1080" height="1920" fill="url(#paper)"/>
 <path d="M0 0 H1080 V116 Q881 55 749 111 T447 104 T0 188Z" fill="#E2EDCE"/>
 <path d="M0 75 Q182 21 300 99 T598 106 T1080 68" fill="none" stroke="#D0DFB9" stroke-width="3"/>
 <path d="M0 1794 Q170 1694 300 1818 T696 1804 T1080 1831 V1920 H0Z" fill="#DCEBCC"/>
 <path d="M0 1859 Q171 1764 340 1880 T773 1847 T1080 1898" fill="none" stroke="#BDD7BC" stroke-width="3"/>
 <path d="M33 449 C-7 647 46 729 31 849 S-6 1123 34 1267 S9 1492 37 1650 M1045 489 C1090 713 1028 797 1052 991 S1027 1303 1057 1501" fill="none" stroke="#D6E1BD" stroke-width="3" stroke-linecap="round"/>
 ${sprig(73,111,.85,33)}${sprig(995,1746,.70,-64)}${star(991,105,16,5)}${star(59,1848,16,-9)}
 ${panels.map(p=>`<rect x="${p.x-6}" y="${p.y+10}" width="${p.width+12}" height="${p.height+4}" rx="${p.radius+5}" fill="#BCD1B8" opacity=".72"/><rect x="${p.x}" y="${p.y}" width="${p.width}" height="${p.height}" rx="${p.radius}" fill="#D9E3CA"/>`).join('')}`;
const header=`<g transform="rotate(-2 540 214)">${display('Three tools.',540,225,104)}
 <path d="M255 276 Q540 265 825 274 L830 325 Q540 339 251 328Z" fill="#CBE7BE" stroke="${P.cream}" stroke-width="8" stroke-linejoin="round"/>
 ${text('One beautiful reveal.',540,310,55,`fill="${P.teal}" letter-spacing="-1"`)}
 ${sprig(223,274,.59,-12)}${sprig(851,272,.59,36)}${star(900,196,22,-6)}${star(168,222,16,4)}
 </g>`;
function label(p) {
 const cy=p.y+43;
 const hoseNote=p.id==='hose'?`<g filter="url(#lift)"><rect x="658" y="${p.y+16}" width="324" height="49" rx="25" fill="#FFF9E8"/><circle cx="682" cy="${p.y+40}" r="7" fill="#E7B543"/>${text('MAX-LEVEL HOSE',823,p.y+51,28,`fill="${P.teal}" letter-spacing=".5"`)}</g>`:'';
 return `<g id="label-${p.id}"><g filter="url(#lift)"><path d="M129 ${p.y+3} H${91+p.badgeWidth} Q${121+p.badgeWidth} ${p.y+3} ${121+p.badgeWidth} ${p.y+39} Q${121+p.badgeWidth} ${p.y+76} ${91+p.badgeWidth} ${p.y+76} H128Z" fill="${P.cream}"/><circle cx="137" cy="${cy}" r="53" fill="${P.cream}"/><circle cx="137" cy="${cy}" r="43" fill="${p.color}" opacity=".35"/><g transform="translate(137 ${cy}) scale(.64)">${iconBodies[p.id]}</g>${text(p.label,209+(p.badgeWidth-145)/2,p.y+57,57,`fill="url(#ink)" letter-spacing="-1"`)}</g>${hoseNote}</g>`;
}
const frame=panels.map(p=>`<rect x="${p.x}" y="${p.y}" width="${p.width}" height="${p.height}" rx="${p.radius}" fill="none" stroke="${P.cream}" stroke-width="13"/><rect x="${p.x-6}" y="${p.y-6}" width="${p.width+12}" height="${p.height+12}" rx="${p.radius+6}" fill="none" stroke="#A9C1AC" stroke-width="2"/><path d="M${p.x+37} ${p.y+p.height-14} H${p.x+p.width-37}" stroke="${P.cream}" stroke-width="2" stroke-linecap="round" opacity=".72"/>`).join('');
const labels=panels.map(label).join('');
const decorations=`${star(995,824,15,7)}${sprig(69,1310,.32,-40)}${star(1006,1792,17,-5)}`;
function outlineText(source) {
 let index=0;
 return source.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g,element=>{
  const out=convertSVGTextToPath(wrap('Outlined display lettering',element)).toString('utf8');
  let inner=out.slice(out.indexOf('>',out.indexOf('<svg'))+1,out.lastIndexOf('</svg>'));
  const prefix=`glyph${index++}_`;
  return inner.replace(/id="([^"]+)"/g,(_,id)=>`id="${prefix}${id}"`).replace(/url\(#([^)]+)\)/g,(_,id)=>`url(#${prefix}${id})`).replace(/xlink:href="#([^"]+)"/g,(_,id)=>`xlink:href="#${prefix}${id}"`);
 });
}
async function write(name,body,transparent=true) {
 const editable=wrap(name,body), outlined=outlineText(editable);
 if(/<text(?:\s|>)/.test(outlined)||/<image(?:\s|>)/.test(outlined))throw Error('Nonvector export '+name);
 fs.writeFileSync(path.join(OUT,'editable_text',name+'.svg'),editable);
 fs.writeFileSync(path.join(OUT,name+'.svg'),outlined);
 await sharp(Buffer.from(outlined)).png().toFile(path.join(OUT,name+'.png'));
 await sharp(Buffer.from(outlined)).resize(540,960).png().toFile(path.join(OUT,'previews',name+'.png'));
 return {file:name+'.svg',raster:name+'.png',transparent,outlined:true};
}
async function main() {
 const assets=[];
 for(const [name,body,transparent] of [
  ['background',background,false],['overlay',frame+header+labels+decorations,true],
  ['header',header,true],['frames',frame+decorations,true],['labels',labels,true],
  ...panels.map(p=>['label_'+p.id,label(p),true])
 ])assets.push(await write(name,body,transparent));
 for(const p of panels)assets.push(await write('icon_'+p.id,`<g transform="translate(540 960) scale(5)">${iconBodies[p.id]}</g>`));
 // White rounded windows are supplied separately for compositing actual footage.
 for(const p of panels){
  const mask=`<svg xmlns="http://www.w3.org/2000/svg" width="${p.width}" height="${p.height}" viewBox="0 0 ${p.width} ${p.height}"><rect width="${p.width}" height="${p.height}" rx="${p.radius}" fill="white"/></svg>`;
  fs.writeFileSync(path.join(OUT,'mask_'+p.id+'.svg'),mask);
  await sharp(Buffer.from(mask)).png().toFile(path.join(OUT,'mask_'+p.id+'.png'));
 }
 // Preview deliberately labels the empty apertures rather than fabricating gameplay.
 const placeholders=panels.map(p=>`<g>${text('RECORDED '+(p.id==='hose'?'MAX HOSE':p.id.toUpperCase()),540,p.y+250,41,'fill="#6B9288" letter-spacing="2"')}${text('Gameplay window',540,p.y+294,29,'fill="#8AA297"')}</g>`).join('');
 const preview=wrap('Three tools illustrated composition — placeholders',background+placeholders+frame+header+labels+decorations);
 await sharp(Buffer.from(outlineText(preview))).png().toFile(path.join(OUT,'previews','Layout_Preview.png'));
 const layout={canvas:[1080,1920],background:'background.svg',overlay:'overlay.svg',alphaOverlay:'overlay.png',panels:panels.map(({badgeWidth,color,...p})=>({...p,mask:'mask_'+p.id+'.png',label:'label_'+p.id+'.svg',suggestedActiveContact:[540,p.y+260],captionSafeTop:p.y+95})),title:'Three tools. One beautiful reveal.',palette:P,fonts:'Outlined Arial Rounded MT Bold and Arial Bold; editable text source retained, no font binaries distributed.',provenance:'Original vector illustration of the actual mint brush, mint handheld sprayer and coral squeegee; transparent windows require real recorded gameplay. Decorative artwork only.',endcard:'Use the approved v2 endcard logo, One more rug ribbon, and Play now / On Google Play CTA.',assets};
 fs.writeFileSync(path.join(OUT,'layout.json'),JSON.stringify(layout,null,2)+'\n');
 fs.writeFileSync(path.join(OUT,'README.md'),'# Illustrated three-tool artwork\n\n1080 × 1920 portrait composition with three vertically stacked real-gameplay windows.\n\nWindows: x 64, width 952, height 450; y 355, 841 and 1327; corner radius 38. Composite `background.png`, the three masked gameplay crops, then `overlay.png`. The tool label occupies approximately the first 90 pixels of each window; frame the real contact action below it. `header`, `frames`, `labels`, and individual labels are also exported independently for optional motion.\n\nAll display SVGs contain outlined lettering and native vector paths; no raster footage is embedded. Editable lettering masters are in `editable_text`. The icons follow the actual game tools: mint brush with ivory handle, mint handheld hose sprayer with ivory lance and gold outlet, coral squeegee with ivory handle. The small hose badge accurately identifies the max-level equipment being shown; it makes no statement about availability at the start.\n\nThe approved v2 endcard remains the recommended ending. The layout preview has labeled placeholders, not simulated footage. Regenerate with `tools/build_ad_tools_art.cjs`.\n','utf8');
 console.log(JSON.stringify({output:OUT,panels:layout.panels,assets:assets.length}));
}
main().catch(error=>{console.error(error);process.exit(1);});
