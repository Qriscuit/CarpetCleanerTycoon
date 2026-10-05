/* Original Carpet Cleaner ad overlay geometry. No external assets or fonts copied.
 * Rebuild: bundled node build_vector_kit.cjs
 * Optional: CARPET_NODE_MODULES points to a directory containing @napi-rs/canvas and sharp.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const modules = process.env.CARPET_NODE_MODULES || 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const { GlobalFonts, createCanvas, convertSVGTextToPath } = require(path.join(modules, '@napi-rs/canvas'));
const sharp = require(path.join(modules, 'sharp'));
const OUT = __dirname;
const EDITABLE = path.join(OUT, 'editable_text');
const PREVIEWS = path.join(OUT, 'previews');
for (const directory of [OUT, EDITABLE, PREVIEWS]) fs.mkdirSync(directory, {recursive:true});
const regularFont = 'C:/Windows/Fonts/arial.ttf';
const boldFont = 'C:/Windows/Fonts/arialbd.ttf';
if (!GlobalFonts.registerFromPath(regularFont, 'Arial') || !GlobalFonts.registerFromPath(boldFont, 'Arial')) throw new Error('Arial fonts are required to outline this kit.');
const P = {cream:'#FFF5DD',mint:'#BDE0C3',green:'#234D40',coral:'#D9793E',gold:'#E7B748'};
const SAFE = {x:96,y:300,width:804,height:920};
const ctx = createCanvas(1080,1920).getContext('2d');
function xml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function text(s,x,y,size=72,fill=P.green,weight='700',anchor='start',extras='') {
  return `<text x="${x}" y="${y}" font-family="Arial" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}" fill="${fill}" ${extras}>${xml(s)}</text>`;
}
function fittedSize(s,preferred,maxWidth) {
  let size=preferred;
  do {ctx.font=`bold ${size}px Arial`; if(ctx.measureText(s).width<=maxWidth) return size; size--; } while(size>36);
  throw new Error('Copy does not fit: '+s);
}
function svg(name,body,desc='') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920" role="img" aria-labelledby="title desc"><title id="title">${xml(name)}</title><desc id="desc">${xml(desc)}</desc>${body}</svg>`;
}
function plate(height=150) {
  return `<rect x="96" y="306" width="804" height="${height}" rx="40" fill="${P.cream}"/><rect x="118" y="340" width="9" height="${height-68}" rx="4.5" fill="${P.gold}"/>`;
}
function caption(copy) {
  const lines=copy.split('\n');
  const height=lines.length===1?150:240;
  const size=Math.min(...lines.map(line=>fittedSize(line,72,700)));
  return plate(height)+lines.map((line,i)=>text(line,155,lines.length===1?405:399+i*84,size)).join('');
}
const items = [
  {file:'hook_discovery.svg',copy:'Find the fox.',use:'Primary discovery opening',alpha:true,body:caption('Find the fox.')},
  {file:'hook_satisfaction.svg',copy:'That clean stripe.',use:'Alternative opening: same footage/body, satisfying-action hook',alpha:true,body:caption('That clean stripe.')},
  {file:'hook_completion.svg',copy:'One spot left.',use:'Alternative opening: last real patch of dirt',alpha:true,body:caption('One spot left.')},
  {file:'process.svg',copy:'Brush. Reveal.',use:'Process beat',alpha:true,body:caption('Brush. Reveal.')},
  {file:'reveal.svg',copy:'Fresh again.',use:'Full-restoration reveal',alpha:true,body:caption('Fresh again.')},
  {file:'next_rug.svg',copy:'What’s under\nthe next one?',use:'Curiosity beat for the next distinct rug',alpha:true,body:caption('What’s under\nthe next one?')},
  {file:'upgrade.svg',copy:'Wide brush\n44% wider strokes',use:'Optional upgrade beat; actual first brush width increase',alpha:true,body:plate(178)+text('Wide brush',155,352,30,P.green,'400')+text('44% wider strokes',155,432,fittedSize('44% wider strokes',64,700))},
  {file:'wordmark.svg',copy:'CARPET\nCLEANER',use:'Compact working game title, independent transparent overlay',alpha:true,body:text('CARPET',142,389,100)+text('CLEANER',142,489,100)},
];
const endcard = `<rect width="1080" height="1920" fill="${P.cream}"/>
<path d="M0 0H1080V154C891 209 750 121 600 164C391 224 245 157 0 240Z" fill="${P.mint}"/>
<path d="M0 1560C251 1419 552 1610 738 1528C855 1476 944 1472 1080 1496V1920H0Z" fill="${P.mint}"/>
<path d="M0 1684C206 1590 412 1747 675 1664C853 1608 938 1673 1080 1635" fill="none" stroke="${P.cream}" stroke-width="20"/>
${text('CARPET',540,365,110,P.green,'700','middle')}
${text('CLEANER',540,469,110,P.green,'700','middle')}
<rect x="230" y="1100" width="620" height="115" rx="35" fill="${P.green}"/>
${text('Play now',540,1156,48,P.cream,'700','middle')}
${text('On Google Play',540,1190,25,P.cream,'400','middle')}`;
items.push({file:'endcard.svg',copy:'CARPET\nCLEANER\nPlay now\nOn Google Play',use:'Full background title/CTA. Root compositor overlays hero footage at x365 y505 w350 h565. Empty central artwork space.',alpha:false,body:endcard});
const guide = `<path d="M0 0H1080V1920H0Z M96 300V1220H900V300Z" fill="${P.coral}" fill-opacity="0.24" fill-rule="evenodd"/>
<rect x="96" y="300" width="804" height="920" fill="none" stroke="${P.coral}" stroke-width="4" stroke-dasharray="16 12"/>
${text('INTERNAL GUIDE — DO NOT EXPORT',540,113,39,P.green,'700','middle')}
${text('Working text / focal-detail area',540,179,31,P.green,'400','middle')}
${text('x 96–900  ·  y 300–1220',540,230,31,P.green,'400','middle')}
${text('Not an official platform safe zone',540,1315,34,P.green,'700','middle')}`;
items.push({file:'safe_guide.svg',copy:'INTERNAL GUIDE — DO NOT EXPORT\nWorking text / focal-detail area\nx 96–900 · y 300–1220\nNot an official platform safe zone',use:'Internal framing aid; remove from all exports. Never a claim of placement approval.',alpha:true,body:guide});

async function rasterBounds(svgBuffer) {
  const {data,info}=await sharp(svgBuffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let minX=1080,minY=1920,maxX=-1,maxY=-1,transparentPixels=0;
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
    const a=data[(y*info.width+x)*4+3];
    if(a===0)transparentPixels++;
    if(a>0){minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
  }
  return {paint_bounds:{x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1},transparent_pixels:transparentPixels};
}
async function run() {
  const records=[];
  for(const item of items){
    const editable=svg(item.file.replace('.svg',''),item.body,item.use+' Copy: '+item.copy);
    const outlined=convertSVGTextToPath(editable);
    if(/<text(?:\s|>)/.test(outlined.toString('utf8')))throw new Error('Unconverted text in '+item.file);
    fs.writeFileSync(path.join(EDITABLE,item.file),editable+'\n');
    fs.writeFileSync(path.join(OUT,item.file),outlined);
    await sharp(outlined).resize(540,960).png().toFile(path.join(PREVIEWS,item.file.replace('.svg','.png')));
    const bounds=await rasterBounds(outlined);
    if(item.alpha&&bounds.transparent_pixels===0)throw new Error('Missing transparency '+item.file);
    if(!item.alpha&&bounds.transparent_pixels!==0)throw new Error('Unexpected end card transparency');
    if(!['endcard.svg','safe_guide.svg'].includes(item.file)){
      const b=bounds.paint_bounds;
      if(b.x<SAFE.x||b.y<SAFE.y||b.x+b.width>SAFE.x+SAFE.width||b.y+b.height>SAFE.y+SAFE.height)throw new Error('Overlay leaves working area '+item.file+JSON.stringify(b));
    }
    records.push({file:item.file,editable_source:'editable_text/'+item.file,preview:'previews/'+item.file.replace('.svg','.png'),copy:item.copy,use:item.use,dimensions:[1080,1920],transparent_background:item.alpha,outlined_text:true,...bounds});
  }
  const manifest={version:1,purpose:'Actual editable vector artwork for a 15-second Carpet Cleaner discovery ad; no footage captured.',canvas:[1080,1920],palette:P,working_guide:{...SAFE,official_platform_template:false},hero_footage_slot:{x:365,y:505,width:350,height:565},font:{family:'Arial',weights:['400','700'],sources:[regularFont,boldFont],provenance:'Locally installed Windows Arial. Font binaries are not copied or distributed. Primary SVGs contain outlined glyph paths; editable_text variants refer to Arial and require it or a chosen replacement for faithful reflow.'},art_provenance:'Original geometric plates and end-card shapes authored for this project in build_vector_kit.cjs. No stock illustration, store badge, platform interface, logo imitation, ratings or external image assets.',generation:{node:process.version,tools:['@napi-rs/canvas GlobalFonts + convertSVGTextToPath','sharp SVG raster readback'],checks:['All 10 primary SVGs have no live text elements','All SVGs rasterize at1080×1920','Caption/wordmark painted bounds fit internal working rectangle','Transparent overlays retain empty alpha outside their content','End card is fully opaque','Half-size PNG previews generated for visual review']},assets:records};
  fs.writeFileSync(path.join(OUT,'asset_manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  const thumbW=270,thumbH=480,gap=18,cols=5,rows=2;
  const layers=[];
  for(let i=0;i<items.length;i++){
    const thumb=await sharp(path.join(OUT,items[i].file)).resize(thumbW,thumbH).flatten({background:'#D8E2DC'}).png().toBuffer();
    layers.push({input:thumb,left:gap+(i%cols)*(thumbW+gap),top:gap+Math.floor(i/cols)*(thumbH+gap)});
  }
  await sharp({create:{width:cols*thumbW+(cols+1)*gap,height:rows*thumbH+(rows+1)*gap,channels:3,background:'#FFFFFF'}}).composite(layers).png().toFile(path.join(PREVIEWS,'contact_sheet.png'));
  console.log(JSON.stringify({generated:records.length,manifest:path.join(OUT,'asset_manifest.json'),files:records.map(r=>({file:r.file,bounds:r.paint_bounds}))},null,2));
}
run().catch(error=>{console.error(error);process.exitCode=1;});
