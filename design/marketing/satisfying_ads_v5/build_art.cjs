// Original editable vector lettering and ribbon art for the Pond Garden ad.
const fs=require('fs');
const path=require('path');
const deps='C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const {GlobalFonts,createCanvas,convertSVGTextToPath}=require(path.join(deps,'@napi-rs/canvas'));
const out=__dirname, artDir=path.join(out,'art');
fs.mkdirSync(path.join(artDir,'editable_text'),{recursive:true});
GlobalFonts.registerFromPath('C:/Windows/Fonts/segoescb.ttf','PondScript');
GlobalFonts.registerFromPath('C:/Windows/Fonts/ARLRDBD.TTF','PondRound');
const ctx=createCanvas(1080,1920).getContext('2d');
const P={cream:'#FFF9E8',mint:'#77C9AE',teal:'#154D54',coral:'#E5775B',gold:'#EDBA43'};
const defs=`<defs>
 <linearGradient id="ink5" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#377D7A"/><stop offset="1" stop-color="#123E48"/></linearGradient>
 <linearGradient id="ribbon5" x1="0" y1="0" x2=".4" y2="1"><stop stop-color="#F4AF8B"/><stop offset=".5" stop-color="#E98666"/><stop offset="1" stop-color="#D45D49"/></linearGradient>
 <linearGradient id="ribbonLight5" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#FFDDAD"/><stop offset=".5" stop-color="#F3BF83"/><stop offset="1" stop-color="#E59868"/></linearGradient>
 <filter id="paperLift5" x="-30%" y="-40%" width="160%" height="190%"><feDropShadow dx="0" dy="9" stdDeviation="3" flood-color="#154D54" flood-opacity=".18"/></filter>
 </defs>`;
function wrap(title,body){return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><title>${title}</title>${defs}${body}</svg>`}
function tx(copy,x,y,size,family='PondRound',attrs=''){return `<text x="${x}" y="${y}" text-anchor="middle" font-family="${family}" font-size="${size}" ${attrs}>${copy}</text>`}
function fit(s,size,width,family='PondRound'){while(size>15){ctx.font=`${size}px ${family}`;if(ctx.measureText(s).width<=width)return size;size--}return size}
function curved(s,x,y,size,width,amplitude=32){
 size=fit(s,size,width);ctx.font=`${size}px PondRound`;
 const advances=[...s].map(c=>ctx.measureText(c).width), total=advances.reduce((a,b)=>a+b,0);
 let pos=-total/2;
 return [...s].map((c,i)=>{
   const mid=pos+advances[i]/2, t=mid/(total/2), rise=amplitude*t*t, angle=2*amplitude*mid/((total/2)**2)*180/Math.PI;
   pos+=advances[i];
   return tx(c,x+mid,y+rise,size,'PondRound',`transform="rotate(${angle.toFixed(2)} ${x+mid} ${y+rise})"`);
 }).join('');
}
function ink(text,stroke=20){return `<g filter="url(#paperLift5)"><g transform="translate(0 7)" fill="#4C9783" stroke="#FFF9E8" stroke-width="${stroke+5}" paint-order="stroke fill" stroke-linejoin="round">${text}</g><g fill="url(#ink5)" stroke="#FFF9E8" stroke-width="${stroke}" paint-order="stroke fill" stroke-linejoin="round">${text}</g></g>`}
const swash=`<path d="M319 458C458 424 603 461 719 430C795 409 813 410 841 426C805 413 794 449 727 459C604 477 468 449 352 470C311 478 288 494 271 508C286 487 292 469 319 458Z" fill="#77C9AE"/><path d="M339 477C469 451 624 494 765 459" fill="none" stroke="#EDBA43" stroke-width="3" stroke-linecap="round"/>`;
const opening=ink(tx('Clean',612,296,fit('Clean',206,690,'PondScript'),'PondScript','transform="rotate(-6 612 260)"'),17)+ink(curved('feels good.',590,397,83,690,21),10)+swash;
const hook=ink(tx('One perfect',592,276,fit('One perfect',135,810,'PondScript'),'PondScript','transform="rotate(-4 592 246)"'),14)+ink(curved('pull.',605,403,122,485,13),13)+swash;
const title=ink(curved('Carpet',595,276,153,690,22),18)+ink(curved('Cleaner',574,427,158,850,17),18)+`<path d="M312 492C458 458 683 515 796 472C735 525 462 493 312 512Z" fill="#77C9AE"/><g fill="#154D54">${tx('One more rug.',566,550,49,'PondScript','transform="rotate(-3 566 525)"')}</g>`;
const ribbon=`<g id="coral-ribbon-cta" filter="url(#paperLift5)">
 <path d="M290 1505C256 1518 221 1519 180 1503L218 1570L175 1621C243 1633 280 1604 308 1585Z M787 1490C838 1471 870 1472 915 1484L880 1550L927 1600C864 1611 812 1582 784 1568Z" fill="#C95D48" stroke="#FFF9E8" stroke-width="7" stroke-linejoin="round"/>
 <path d="M290 1505L308 1585L328 1565Z M787 1490L784 1568L754 1552Z" fill="#8F3D35"/>
 <path d="M284 1498C439 1463 628 1507 791 1485L800 1593C642 1620 454 1577 293 1607Z" fill="url(#ribbon5)" stroke="#FFF9E8" stroke-width="9" stroke-linejoin="round"/>
 <path d="M299 1513C449 1483 627 1524 778 1500" fill="none" stroke="url(#ribbonLight5)" stroke-width="5" stroke-linecap="round"/>
 <g fill="#FFF9E8" stroke="#A94438" stroke-width="2" paint-order="stroke fill">${curved('Play now',539,1570,64,410,-8)}</g>
 <g fill="#154D54">${tx('On Google Play',540,1658,28)}</g>
 </g>`;
function outline(source){let n=0;return source.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g,element=>{
  const converted=convertSVGTextToPath(wrap('Letter outlines',element)).toString('utf8');
  let inner=converted.slice(converted.indexOf('>',converted.indexOf('<svg'))+1,converted.lastIndexOf('</svg>'));
  const prefix=`v5letters${n++}_`;
  return inner.replace(/id="([^"]+)"/g,(_,id)=>`id="${prefix}${id}"`).replace(/url\(#([^)]+)\)/g,(_,id)=>`url(#${prefix}${id})`);
})}
async function main(){
 for(const [name,body] of [['opening_overlay.svg',opening],['hook_overlay.svg',hook],['title_overlay.svg',title],['cta_ribbon.svg',ribbon]]){
  const editable=wrap(name,body),display=outline(editable);
  fs.writeFileSync(path.join(artDir,'editable_text',name),editable);
  fs.writeFileSync(path.join(artDir,name),display);
  await sharp(Buffer.from(display)).resize(540,960).png().toFile(path.join(artDir,name.replace('.svg','.png')));
 }
 const border=fs.readFileSync(path.join(artDir,'pond_border.svg'),'utf8');
 const inner=source=>source.slice(source.indexOf('>',source.indexOf('<svg'))+1,source.lastIndexOf('</svg>'));
 for(const [name,body] of [['Opening_Art.svg',opening],['Ending_Art.svg',title+ribbon]]){
  const composed=wrap(name,`<rect width="1080" height="1920" fill="#FFF9E8"/><path d="M0 570C312 310 733 610 1080 418V1620C663 1802 192 1520 0 1690Z" fill="#E4EEE1"/>${inner(border)}${body}`);
  const display=outline(composed);fs.writeFileSync(path.join(out,name),display);
  await sharp(Buffer.from(display)).resize(540,960).png().toFile(path.join(out,name.replace('.svg','.png')));
 }
 console.log('Created curved lettering, swashes and folded coral CTA as native SVG paths.');
}
main().catch(e=>{console.error(e);process.exit(1)});
