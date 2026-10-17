// Preproduction illustrations only. No game state, gameplay timing or footage is modified.
const fs = require('fs');
const path = require('path');
const modules = 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp = require(path.join(modules, 'sharp'));
const out = __dirname;
const root = path.resolve(out, '../../..');
const P = { cream:'#FFF9E8', mint:'#77C9AE', teal:'#154D54', coral:'#E5775B', gold:'#EDBA43', water:'#65D4DF', floor:'#F2F5EC' };
const esc = s => s.replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
const shotsA = [
 {start:0,end:5,title:'One perfect lane',scene:'lane',copy:'Clean feels good.',note:'An uninterrupted real pass. The koi reappears exactly beneath the blade.',sound:'Soft swish; quiet music.',source:'Real gameplay · final wash 3/3'},
 {start:5,end:7,title:'Over the edge',scene:'edge',copy:'',note:'Continue toward the binding. Blue water curls over the edge onto the floor.',sound:'Soft water pull, added editorially.',source:'Real gameplay · shared body'},
 {start:7,end:8.8,title:'The last little patch',scene:'patch',copy:'',note:'A visible cut forward. Finish the final small area at normal gameplay speed.',sound:'One contact swish, then lift.',source:'Real gameplay · shared body'},
 {start:8.8,end:10.6,title:'The finish settles',scene:'suction',copy:'',note:'Keep the native 1.8-second suction. Tools give way to the restored rug.',sound:'Music breathes; no invented reward blast.',source:'Real gameplay · native finish'},
 {start:10.6,end:13,title:'Enjoy the clean',scene:'clean',copy:'',note:'The complete 2.4-second native reveal. Leave the koi and lotus unobstructed.',sound:'Actual completion cue, once.',source:'Real gameplay · native reveal'},
 {start:13,end:15,title:'Your next clean',scene:'cta',copy:'Carpet Cleaner',note:'Hold a real clean frame. Small title and Play now over the rug.',sound:'Quiet musical resolve.',source:'Real clean frame · editorial hold'}
];
const shotsB = [
 {start:0,end:.4,title:'Already moving',scene:'ai-start',copy:'',note:'The first frame is already in motion. A coral blade meets muted residue.',sound:'Immediate gentle water swish.',source:'AI hook · illustrated concept'},
 {start:.4,end:3.8,title:'The perfect pull',scene:'ai-lane',copy:'One perfect pull.',note:'One continuous left-to-right pass. The exact koi pattern emerges in one lane.',sound:'One long, soft swish.',source:'AI hook · illustrated concept'},
 {start:3.8,end:5,title:'Land in the game',scene:'ai-match',copy:'',note:'Settle into the gameplay crop and exact blade pose. Cut on contact at 5s.',sound:'Carry the swish across the cut.',source:'AI hook · matching end frame'},
 ...shotsA.slice(1)
];
function textLines(s,x,y,size=21,width=28,color=P.teal) {
 let words=s.split(' '), rows=[], row='';
 for (const word of words) { if ((row+' '+word).trim().length>width && row) {rows.push(row);row=word;} else row=(row+' '+word).trim(); }
 if(row) rows.push(row);
 return `<text x="${x}" y="${y}" font-family="Arial, sans-serif" font-size="${size}" fill="${color}">${rows.map((v,i)=>`<tspan x="${x}" dy="${i?size*1.35:0}">${esc(v)}</tspan>`).join('')}</text>`;
}
function blade(x,y,water=true) {
 return `<g transform="translate(${x} ${y}) scale(.6)">${water?`<path d="M-22-126 Q-52-93-33-62 Q-54-28-34 4 Q-55 40-34 72 Q-48 101-22 128 L24 128 Q48 96 29 63 Q47 29 28-4 Q47-37 28-70 Q47-104 23-127Z" fill="${P.water}"/><path d="M-18-117 Q-36-87-22-61 Q-37-25-22 6 Q-37 39-22 69 Q-34 98-17 117" fill="none" stroke="#ADDDD5" stroke-width="8"/>`:''}<rect x="-15" y="-119" width="32" height="238" rx="11" fill="${P.coral}"/><rect x="12" y="-116" width="8" height="232" rx="4" fill="${P.gold}"/><path d="M-150 0H-10" stroke="#D9D5AA" stroke-width="18" stroke-linecap="round"/><path d="M-146 0H-115" stroke="#318E7B" stroke-width="21" stroke-linecap="round"/></g>`;
}
function frame(scene,art,copy) {
 const id='c'+scene.replace(/-/g,'');
 const ai=scene.startsWith('ai');
 let base=`<svg xmlns="http://www.w3.org/2000/svg" width="540" height="960" viewBox="0 0 540 960"><title>${esc(scene)} storyboard concept</title><defs><clipPath id="${id}"><rect x="70" y="185" width="400" height="600" rx="28"/></clipPath></defs><rect width="540" height="960" fill="${ai?'#F4EEDA':P.floor}"/>`;
 if(!ai) base+=`<g stroke="#CFDAD0" stroke-width="2">${[0,135,270,405,540].map(x=>`<path d="M${x} 0V960"/>`).join('')}${[80,215,350,485,620,755,890].map(y=>`<path d="M0 ${y}H540"/>`).join('')}</g>`;
 if(ai) base+=`<path d="M0 92Q200 20 540 122V0H0Z M0 860Q250 940 540 831V960H0Z" fill="#E1E8D0"/>`;
 base+=`<rect x="70" y="192" width="400" height="600" rx="30" fill="#637566"/>`;
 base+=`<g stroke="#C5BE8D" stroke-width="11" stroke-linecap="round">${[100,139,178,217,256,295,334,373,412,451].map(x=>`<path d="M${x} 171V187 M${x} 784V801"/>`).join('')}</g><image href="${art}" x="70" y="185" width="400" height="600" clip-path="url(#${id})"/>`;
 if(['lane','ai-lane','ai-start','ai-match'].includes(scene)) {
  const x=scene==='ai-start'?124:scene==='ai-lane'?282:scene==='ai-match'?337:282;
  base+=`<g clip-path="url(#${id})"><rect x="70" y="185" width="400" height="270" fill="#1F231A" opacity=".60"/><rect x="70" y="603" width="400" height="182" fill="#1F231A" opacity=".60"/><rect x="${x}" y="455" width="${470-x}" height="148" fill="#1F231A" opacity=".60"/><path d="M70 458H${x} M70 600H${x}" stroke="${P.water}" stroke-width="8" fill="none"/></g>${blade(x,529)}`;
 } else if(scene==='edge') {
  base+=`<g clip-path="url(#${id})"><rect x="70" y="185" width="400" height="300" fill="#23271D" opacity=".55"/><rect x="70" y="631" width="400" height="154" fill="#23271D" opacity=".55"/><path d="M70 487H450 M70 629H450" stroke="${P.water}" stroke-width="8"/></g><path d="M456 488Q528 496 539 518V612Q502 649 455 631Z" fill="${P.water}"/>${blade(450,558)}`;
 } else if(scene==='patch') {
  base+=`<rect x="342" y="210" width="99" height="190" rx="20" fill="#282A20" opacity=".58"/>${blade(350,306)}`;
 } else if(scene==='suction') {
  base+=`<g fill="#8C8767" opacity=".8"><circle cx="437" cy="360" r="9"/><circle cx="452" cy="407" r="6"/><circle cx="467" cy="458" r="4"/></g>`;
 }
 if(!ai && !['clean','cta','suction','lane'].includes(scene)) base+=`<rect x="155" y="83" width="230" height="38" rx="19" fill="${P.cream}"/><text x="270" y="108" text-anchor="middle" font-family="Arial" font-size="19" fill="${P.teal}">Final wash · 3/3</text>`;
 if(copy && scene!=='cta') base+=`<rect x="80" y="105" width="380" height="58" rx="29" fill="${P.cream}"/><text x="270" y="142" text-anchor="middle" font-family="Arial Rounded MT Bold,Arial" font-size="29" fill="${P.teal}">${esc(copy)}</text>`;
 if(scene==='cta') base+=`<rect x="101" y="92" width="338" height="64" rx="29" fill="${P.cream}"/><text x="270" y="134" text-anchor="middle" font-family="Arial Rounded MT Bold,Arial" font-size="32" fill="${P.teal}">Carpet Cleaner</text><rect x="160" y="827" width="220" height="65" rx="32" fill="${P.coral}"/><text x="270" y="855" text-anchor="middle" font-family="Arial" font-size="25" fill="#FFF9E8">Play now</text><text x="270" y="877" text-anchor="middle" font-family="Arial" font-size="15" fill="#FFF9E8">On Google Play</text>`;
 return base+'</svg>';
}
async function main(){
 fs.mkdirSync(path.join(out,'panels'),{recursive:true});
 const art='data:image/jpeg;base64,'+(await sharp(path.join(root,'CarpetToy/assets/carpet/patterns/stillwater_pond.png')).resize(540,810).jpeg({quality:85}).toBuffer()).toString('base64');
 const all=[];
 for(const [letter,shots] of [['A',shotsA],['B',shotsB]]){
  const cols=letter==='A'?3:4, cw=340, margin=40, width=cols*cw+margin*2, height=1740;
  let board=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><title>Storyboard ${letter} — satisfying cleaning</title><rect width="${width}" height="${height}" fill="${P.cream}"/>${textLines(letter==='A'?'A / A little moment of clean':'B / One perfect pull',40,55,32,70)}${textLines(letter==='A'?'15 seconds of real gameplay':'5 seconds AI hook + 10 seconds real gameplay',40,94,21,100)}${textLines('Concept panels using actual rug art. Fresh moving captures and AI hook are still to be produced.',40,125,17,130)}`;
  const entries=[];
  for(let i=0;i<shots.length;i++){
   const shot=shots[i], source=frame(shot.scene,art,shot.copy), x=margin+(i%cols)*cw, y=160+Math.floor(i/cols)*750;
   const panelPath=path.join(out,'panels',`${letter}${i+1}.svg`);
   fs.writeFileSync(panelPath,source);
   const jpg=await sharp(Buffer.from(source)).resize(270,480).jpeg({quality:72}).toBuffer();
   board+=`<g transform="translate(${x} ${y})"><text x="0" y="0" font-family="Arial" font-size="23" fill="${P.teal}">${shot.start.toFixed(1)}–${shot.end.toFixed(1)}s</text><image href="data:image/jpeg;base64,${jpg.toString('base64')}" x="0" y="15" width="300" height="533.333"/>${textLines(shot.title,0,582,22,28)}${textLines(shot.source,0,610,15,39)}${textLines(shot.note,0,638,17,35)}</g>`;
   entries.push({...shot,image:'data:image/jpeg;base64,'+jpg.toString('base64')});
  }
  board+=textLines('Shared 5–15s body · native 1.8s suction + 2.4s reveal · normal-speed contact · staged concept art, not footage',40,1711,17,130)+'</svg>';
  fs.writeFileSync(path.join(out,`Storyboard_${letter}.svg`),board);
  await sharp(Buffer.from(board)).png().toFile(path.join(out,`Storyboard_${letter}.png`));
  all.push(entries);
 }
 fs.writeFileSync(path.join(out,'storyboard_data.json'),JSON.stringify({A:all[0],B:all[1]},null,2));
 console.log('Built both editable storyboard posters and 14 concept panels.');
}
main().catch(e=>{console.error(e);process.exit(1)});
