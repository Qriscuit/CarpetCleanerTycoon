// Illustrated blocking boards, not fabricated gameplay footage.
const fs=require('fs'),path=require('path');
const deps='C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const out=__dirname,root=path.resolve(out,'../../..');
const P={cream:'#FFF9E8',mint:'#77C9AE',teal:'#154D54',coral:'#E5775B',gold:'#EDBA43',water:'#65D4DF'};
const body=[
 {start:5,end:6.8,title:'One last clean edge',scene:'patch',note:'A visible cut to the real final patch. Finish at normal speed.',source:'Shared real gameplay'},
 {start:6.8,end:8.6,title:'The finish settles',scene:'suction',note:'Preserve the complete 1.8-second native suction.',source:'Native suction · 1.8 seconds'},
 {start:8.6,end:11,title:'Enjoy what you restored',scene:'clean',note:'Hold the complete native clean reveal, without ad lettering.',source:'Native reveal · 2.4 seconds'},
 {start:11,end:11.84,title:'The room opens up',scene:'room-open',note:'Pull back 0.42s, then open the casements for 0.42s.',source:'Real room and window'},
 {start:11.84,end:12.49,title:'A lovely little curl',scene:'room-roll',note:'The rug curls up naturally, with the room fully visible.',source:'Native curl · 0.65 seconds'},
 {start:12.49,end:12.95,title:'Out through the window',scene:'room-exit',note:'The rolled rug leaves the workshop and clears the frame.',source:'Native exit · 0.46 seconds'},
 {start:12.95,end:15,title:'One more rug',scene:'room-end',note:'Hold the real empty room. Curved title and coral ribbon appear.',source:'Editorial frame hold + SVG art'}
];
const A=[{start:0,end:5,title:'The first satisfying lane',scene:'lane',note:'One uninterrupted real final-round pass under the opening art.',source:'Real gameplay · final round 3/3'},...body];
const B=[{start:0,end:5,title:'One perfect pull',scene:'ai-lane',note:'AI illustration: begin moving, clear one lane, land on the real pose.',source:'AI hook · 5 seconds'},...body];
function esc(s){return s.replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
function svgBody(file,prefix){let s=fs.readFileSync(path.join(out,'art',file),'utf8');s=s.slice(s.indexOf('>',s.indexOf('<svg'))+1,s.lastIndexOf('</svg>'));return s.replace(/id="([^"]+)"/g,(_,id)=>`id="${prefix}${id}"`).replace(/url\(#([^)]+)\)/g,(_,id)=>`url(#${prefix}${id})`)}
function flowerpot(x,y){return `<g transform="translate(${x} ${y})"><ellipse cy="20" rx="31" ry="28" fill="#7B8F73" opacity=".2"/><ellipse cy="10" rx="29" ry="25" fill="#C4B68A" stroke="#F8F0CE" stroke-width="4"/><ellipse cy="5" rx="24" ry="19" fill="#716A48"/><path d="M-3 11C-32 8-38-28-19-35C-4-28 1-4-3 11Z" fill="#89B681"/><path d="M0 10C-4-28 21-51 31-30C34-11 13 7 0 10Z" fill="#527F69"/><path d="M1 12C-4-8-20-9-22 3C-16 18-5 22 1 12Z" fill="#B0CB85"/><path d="M2 13C8-8 30-12 30 3C20 17 12 20 2 13Z" fill="#77A577"/><path d="M0 8C-13-23 4-35 12-18C14-4 7 8 0 8Z" fill="#D5DB9A"/></g>`}
function blade(x,y){return `<g transform="translate(${x} ${y})"><path d="M-17-105C-43-85-23-54-33-29C-47-3-25 13-32 46C-42 76-22 101-13 106L22 106C46 88 24 59 32 33C46 11 25-12 33-40C42-68 29-94 18-106Z" fill="${P.water}"/><path d="M-23-85C-32-53-17-45-26-15C-35 12-16 40-26 77" fill="none" stroke="#B7EFE4" stroke-width="6"/><rect x="-10" y="-96" width="22" height="192" rx="8" fill="${P.coral}"/><path d="M14-94V94" stroke="#C7AD62" stroke-width="5"/><path d="M-122 0H0" stroke="#E1D9AC" stroke-width="14" stroke-linecap="round"/><path d="M-126 0H-103" stroke="#2E8B78" stroke-width="17" stroke-linecap="round"/></g>`}
function rug(x,y,w,h,texture,clipName,extra=''){
 return `<defs><clipPath id="${clipName}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="24"/></clipPath></defs><rect x="${x-5}" y="${y+7}" width="${w+10}" height="${h}" rx="26" fill="#1E4D48" opacity=".22"/><g stroke="#C4B887" stroke-width="11" stroke-linecap="round">${Array.from({length:12},(_,i)=>{const px=x+23+i*(w-46)/11;return `<path d="M${px} ${y-14}V${y+2} M${px} ${y+h-2}V${y+h+14}"/>`}).join('')}</g><image href="${texture}" x="${x}" y="${y}" width="${w}" height="${h}" clip-path="url(#${clipName})"/><g clip-path="url(#${clipName})">${extra}</g>`;
}
function room(scene,texture){
 let s=`<g id="workshop-illustration"><rect x="181" y="614" width="720" height="889" rx="3" fill="#557C6F" opacity=".25"/><rect x="171" y="598" width="720" height="889" fill="#E7E6C6"/>`;
 for(let row=0;row<10;row++)for(let col=0;col<8;col++)s+=`<rect x="${195+col*84}" y="${630+row*82}" width="84" height="82" fill="${(row+col)%2?'#E7E7CF':'#BFDCC7'}"/>`;
 s+=`<rect x="184" y="610" width="694" height="864" fill="none" stroke="#F6F1D5" stroke-width="8"/><path d="M194 728V1453H866V728" fill="none" stroke="#F5ECC1" stroke-width="9" stroke-linejoin="round"/><path d="M171 602H891" stroke="#A9B593" stroke-width="28"/><path d="M185 588H880" stroke="#E3E4CA" stroke-width="24"/>`;
 const open=scene!=='room-clean';
 if(open)s+=`<path d="M255 590L226 481L273 571L530 571L530 590Z M807 590L842 480L795 571L533 571L533 590Z" fill="#A0C6B2" stroke="#DBDFC5" stroke-width="9"/><path d="M251 590L224 480 M808 590L844 480" stroke="#91A99A" stroke-width="7"/>`;
 s+=`<rect x="237" y="602" width="590" height="101" fill="#ADC2AE" stroke="#E3DDB5" stroke-width="13"/><path d="M239 638H826 M239 675H826 M530 607V695" stroke="#EEE4BC" stroke-width="12"/><path d="M177 698H234 M826 698H885" stroke="#A8B698" stroke-width="15"/>`;
 s+=flowerpot(222,729)+flowerpot(843,729)+flowerpot(219,1435)+flowerpot(847,1435);
 if(scene==='room-open'||scene==='room-clean')s+=rug(350,814,366,549,texture,'roomrug');
 if(scene==='room-roll')s+=`<defs><clipPath id="rolled-rug-clip"><rect x="350" y="814" width="366" height="277" rx="20"/></clipPath></defs><g stroke="#C4B887" stroke-width="8" stroke-linecap="round">${Array.from({length:10},(_,i)=>`<path d="M${365+i*37} 801V818"/>`).join('')}</g><image href="${texture}" x="350" y="814" width="366" height="549" clip-path="url(#rolled-rug-clip)"/><path d="M350 1080Q533 1059 716 1080V1153Q533 1167 350 1153Z" fill="#164B52"/><ellipse cx="350" cy="1117" rx="16" ry="37" fill="#23666B"/><path d="M363 1089Q531 1070 702 1089" fill="none" stroke="#559790" stroke-width="4"/>`;
 if(scene==='room-exit')s+=`<path d="M350 613Q533 601 716 613V681Q533 690 350 681Z" fill="#164B52"/><ellipse cx="350" cy="647" rx="16" ry="34" fill="#23666B"/><path d="M363 621Q531 607 702 621" fill="none" stroke="#559790" stroke-width="4"/>`;
 return s+'</g>';
}
function makeFrame(scene,texture){
 const clip='rug'+scene.replace(/-/g,''),isRoom=scene.startsWith('room');
 let s=`<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><title>Pond Garden — ${scene} composition concept</title><rect width="1080" height="1920" fill="#FFF9E8"/><path d="M0 570C312 310 733 610 1080 418V1620C663 1802 192 1520 0 1690Z" fill="#E4EEE1"/>`;
 if(isRoom)s+=room(scene,texture);else{
  let dirt='',x=540;
  if(scene==='lane'||scene==='ai-lane')dirt=`<rect x="245" y="545" width="590" height="291" fill="#22281D" opacity=".58"/><rect x="245" y="1035" width="590" height="395" fill="#22281D" opacity=".58"/><rect x="${x}" y="836" width="${835-x}" height="199" fill="#22281D" opacity=".58"/><path d="M245 837H${x} M245 1034H${x}" stroke="${P.water}" stroke-width="11"/>`;
  if(scene==='patch')dirt=`<rect x="738" y="593" width="85" height="188" rx="15" fill="#22281D" opacity=".58"/>`;
  s+=rug(245,545,590,885,texture,clip,dirt);
  if(scene==='lane'||scene==='ai-lane')s+=blade(x,936);
  if(scene==='patch')s+=blade(744,682);
  if(scene==='suction')s+=`<g fill="#95896A"><circle cx="794" cy="632" r="6"/><circle cx="811" cy="669" r="4"/><circle cx="828" cy="693" r="3"/></g>`;
 }
 s+=svgBody('pond_border.svg','border-');
 if(scene==='lane')s+=svgBody('opening_overlay.svg','opening-');
 if(scene==='ai-lane')s+=svgBody('hook_overlay.svg','hook-');
 if(scene==='room-end')s+=svgBody('title_overlay.svg','title-')+svgBody('cta_ribbon.svg','cta-');
 return s+'</svg>';
}
function lines(copy,x,y,font=19,max=36){let row='',rows=[];for(const word of copy.split(' ')){if((row+' '+word).trim().length>max&&row){rows.push(row);row=word}else row=(row+' '+word).trim()}if(row)rows.push(row);return `<text x="${x}" y="${y}" font-family="Arial" font-size="${font}" fill="${P.teal}">${rows.map((r,i)=>`<tspan x="${x}" dy="${i?font*1.35:0}">${esc(r)}</tspan>`).join('')}</text>`}
async function main(){
 fs.mkdirSync(path.join(out,'panels'),{recursive:true});
 const texture='data:image/jpeg;base64,'+(await sharp(path.join(root,'CarpetToy/assets/carpet/patterns/stillwater_pond.png')).resize(590,885).jpeg({quality:86}).toBuffer()).toString('base64');
 const data={};
 for(const [letter,shots]of[['A',A],['B',B]]){
  let board=`<svg xmlns="http://www.w3.org/2000/svg" width="1520" height="1820" viewBox="0 0 1520 1820"><title>Storyboard ${letter} — Pond Garden with workshop departure</title><rect width="1520" height="1820" fill="#FFF9E8"/><path d="M1050 0C1205 67 1400 0 1520 120V0Z" fill="#C9E2CF"/><path d="M980 7C1170 117 1371 34 1510 139" fill="none" stroke="#EDBA43" stroke-width="2"/>${lines(letter==='A'?'A / Clean feels good.':'B / One perfect pull.',40,63,36,80)}${lines(letter==='A'?'15 seconds of genuine gameplay + illustrated art':'5-second AI hook + identical 10-second gameplay ending',40,106,22,100)}${lines('Illustrated shot blocking. Actual capture will retain the game’s rug, workshop, tools and native exit.',40,144,18,140)}`;
  data[letter]=[];
  for(let i=0;i<shots.length;i++){
   const shot=shots[i],source=makeFrame(shot.scene,texture),x=40+(i%4)*370,y=195+Math.floor(i/4)*770;
   fs.writeFileSync(path.join(out,'panels',`${letter}${i+1}.svg`),source);
   const jpeg=await sharp(Buffer.from(source)).resize(360,640).jpeg({quality:80}).toBuffer();
   await sharp(Buffer.from(source)).resize(540,960).png().toFile(path.join(out,'panels',`${letter}${i+1}.png`));
   board+=`<g transform="translate(${x} ${y})">${lines(`${shot.start.toFixed(2)}–${shot.end.toFixed(2)}s`,0,0,23)}<image x="0" y="17" width="325" height="577.778" href="data:image/jpeg;base64,${jpeg.toString('base64')}"/>${lines(shot.title,0,626,21,31)}${lines(shot.source,0,655,16,40)}${lines(shot.note,0,686,18,35)}</g>`;
   data[letter].push({...shot,image:'data:image/jpeg;base64,'+jpeg.toString('base64')});
  }
  board+=lines('Same 5–15s body · 1.8s suction · 2.4s reveal · 1.95s room/window departure · empty-room CTA hold',40,1778,19,140)+'</svg>';
  fs.writeFileSync(path.join(out,`Storyboard_${letter}.svg`),board);
  await sharp(Buffer.from(board)).png().toFile(path.join(out,`Storyboard_${letter}.png`));
 }
 fs.writeFileSync(path.join(out,'storyboard_data.json'),JSON.stringify(data,null,2));
 const opening=await sharp(path.join(out,'panels/A1.png')).png().toBuffer(),ending=await sharp(path.join(out,'panels/A8.png')).png().toBuffer();
 await sharp({create:{width:1120,height:1020,channels:4,background:'#FFF9E8'}}).composite([{input:opening,left:10,top:20},{input:ending,left:570,top:20}]).png().toFile(path.join(out,'Art_Preview.png'));
 console.log('Built revised illustrated storyboards with room, window, curl, exit and empty-room ending.');
}
main().catch(e=>{console.error(e);process.exit(1)});
