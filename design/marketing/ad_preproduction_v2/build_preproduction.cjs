// Build review artifacts from existing renderer stills and the vector overlay kit.
// This script never launches Godot, records gameplay, or edits a player save.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const here = __dirname;
const root = path.resolve(here, '../../..');
const out = path.join(here, 'preview');
fs.mkdirSync(out, { recursive: true });
fs.mkdirSync(path.join(here, 'references'), { recursive: true });
const xml = s => String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const data = (file, mime) => `data:${mime};base64,${fs.readFileSync(file).toString('base64')}`;
const get = name => path.join(here, 'references', name);
const files = {
  fox_partial: 'discovery_playful_fox_partly_dirty.png',
  fox_clean: 'discovery_playful_fox_reveal_after.png',
  mint_clean: 'discovery_mint_meadow_reveal_after.png',
  sun_clean: 'discovery_sunburst_geometry_clean.png'
};
for (const name of Object.values(files)) fs.copyFileSync(path.join(root, 'art/renders', name), get(name));
const shots = [
 {id:'01',start:0,end:2,title:'Find the fox',take:'A',overlay:'hook_discovery.svg',ref:'fox_partial',crop:[35,175,330,586.6667],copy:'Find the fox.',action:'Open already brushing. A real late pass reveals an eye or muzzle.',motion:'Keep the brush head and the changing soil boundary together in the centre of the frame.',sound:'Live cloth + dirt scrape from frame one. Quiet music underneath.',note:'The reference is a partial-clean test still. The final hook needs a new take with the head beside the face.',lines:['Start mid-stroke.','Expose eye / muzzle.','Keep the contact visible.']},
 {id:'02',start:2,end:5,title:'Make the change',take:'B',overlay:'process.svg',ref:'fox_partial',crop:[0,148,390,693.3333],copy:'Brush. Reveal.',action:'Two useful passes, with a clear cut forward to later progress on this Fox.',motion:'One continuous normal-speed stroke, then a visible edit. No accelerated wipe.',sound:'Contact sound starts and stops with the visible tool.',note:'Same partial-clean reference for composition; the edited progression is still to be filmed.',lines:['Same Fox. Same brush.','Two adjacent lanes.','Visible progress cut.']},
 {id:'03',start:5,end:7.2,title:'Finish the last patch',take:'C',overlay:null,ref:'fox_clean',crop:[0,135,390,693.3333],copy:'No added copy',action:'Final effective movement, then the actual 1.8-second suction and 99% polish.',motion:'Record from before completion. Let the engine finish naturally.',sound:'Brush lifts; leave some breathing room. No invented vacuum effect.',note:'This still shows the target result, not the missing final-patch or suction footage.',lines:['Cross 99% in play.','Keep real suction.','No added text.']},
 {id:'04',start:7.2,end:9.5,title:'Enjoy the reveal',take:'C',overlay:'reveal.svg',ref:'fox_clean',crop:[0,135,390,693.3333],copy:'Fresh again.',action:'Give the clean Fox 2.3 seconds of the real reveal. No distracting new feature.',motion:'Hold the framing still. This follows shot 03 in the same source take.',sound:'One restrained completion cue at 7.2s; allow the tail to resolve.',note:'Renderer fixture confirms the look. Capture a genuine completed job for the ad.',lines:['Same uninterrupted take.','Clean Fox gets room.','One completion cue.']},
 {id:'05',start:9.5,end:12,title:'Want the next one',take:'E + F',overlay:'next_rug.svg',ref:'mint_clean',crop:[0,135,390,693.3333],copy:'What’s under the next one?',action:'Mint for 1.25 seconds, then Sunburst for 1.25 seconds.',motion:'Match the rug size and angle. Simple cuts make them separate restorations.',sound:'Quiet continuous music, with no repeated reward noise.',note:'Both are real designs. These test stills will be replaced by newly recorded full-clean reveals.',lines:['Mint → Sunburst.','1.25 seconds each.','A new discovery.']},
 {id:'06',start:12,end:15,title:'Give a clear next step',take:'G',overlay:'endcard.svg',ref:'fox_clean',crop:[25,174,340,548],copy:'Carpet Cleaner · Play now · On Google Play',action:'Keep the game name and play prompt readable for three seconds.',motion:'A clean Fox frame sits inside the vector card. A deliberate end-card hold is allowed.',sound:'Let the music resolve and fade gently. No voice-over required.',note:'Google Play availability is confirmed by the user. The exact listing URL and public-build match are pending.',lines:['A steady three seconds.','Real restored rug insert.','Google Play destination.']}
];
const vector = name => data(path.join(here, 'vectors', name), 'image/svg+xml');
function scene(s, opts={}) {
 const ref = opts.ref || s.ref;
 const crop = opts.crop || s.crop;
 const picture = data(get(files[ref]), 'image/png');
 const overlay = opts.overlay === undefined ? s.overlay : opts.overlay;
 let content;
 if (s.id === '06') {
   content = `<image width="1080" height="1920" href="${vector('endcard.svg')}"/><svg x="365" y="505" width="350" height="565" viewBox="${crop.join(' ')}" preserveAspectRatio="xMidYMid meet"><image width="390" height="844" href="${picture}"/></svg>`;
 } else {
   content = `<rect width="1080" height="1920" fill="#fffdf6"/><svg width="1080" height="1920" viewBox="${crop.join(' ')}" preserveAspectRatio="xMidYMid slice"><image width="390" height="844" href="${picture}"/></svg>`;
   if (overlay) content += `<image width="1080" height="1920" href="${vector(overlay)}"/>`;
 }
 return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1080" height="1920" viewBox="0 0 1080 1920"><title>${xml(s.title)} — reference composition, not recorded footage</title>${content}</svg>`;
}
async function saveFrame(name, svg) {
 fs.writeFileSync(path.join(out, name+'.svg'),svg);
 await sharp(Buffer.from(svg)).png().toFile(path.join(out,name+'.png'));
 return data(path.join(out,name+'.png'),'image/png');
}
async function run() {
 for (const s of shots) {
   s.frame = await saveFrame('shot_'+s.id,scene(s));
   s.frame_file = 'preview/shot_'+s.id+'.png';
 }
 const montageB = await saveFrame('shot_05b',scene(shots[4],{ref:'sun_clean',crop:[0,126,390,693.3333]}));
 const hookB = await saveFrame('hook_B',scene(shots[0],{overlay:'hook_satisfaction.svg'}));
 const hookCScene = scene(shots[0],{overlay:'hook_completion.svg',ref:'fox_clean'});
 const hookC = await saveFrame('hook_C',hookCScene.replace(/<\/svg>$/, '<rect x="116" y="1400" width="848" height="130" rx="24" fill="#fff5dd"/><text x="540" y="1455" text-anchor="middle" font-family="Arial" font-size="32" font-weight="bold" fill="#234d40">REFERENCE ONLY</text><text x="540" y="1500" text-anchor="middle" font-family="Arial" font-size="30" fill="#234d40">Last-patch take still to record</text></svg>'));
 const manifest = {
   status:'preproduction_not_footage', canvas:[1080,1920], duration_seconds:15, editorial_fps:30,
   google_play_url:null, google_play_status:'Availability confirmed by user; URL and public-build match pending',
   guide:{x:96,y:300,width:804,height:920,official:false},
   source_note:'Existing 390x844 renderer test stills. Cropped with uniform scale; no gameplay recorded. Full-clean reference states are staged fixtures.',
   shots:shots.map(({frame,...s})=>({...s,in_frame:Math.round(s.start*30),out_frame_exclusive:Math.round(s.end*30)})),
   optional_25s:[{start:0,end:9.5,beat:'Same hook, work and reveal'},{start:9.5,end:12.5,beat:'Real 80-coin Wide brush purchase'},{start:12.5,end:18.5,beat:'Real 44% wider lane proof'},{start:18.5,end:22,beat:'Pattern discovery montage'},{start:22,end:25,beat:'Title and Google Play CTA'}]
 };
 fs.writeFileSync(path.join(here,'shot_manifest.json'),JSON.stringify(manifest,null,2));
 const csv=[['shot','in_seconds','out_seconds','in_frame_30fps','out_frame_exclusive','take','copy','vector','reference_status'],...shots.map(s=>[s.id,s.start,s.end,s.start*30,s.end*30,s.take,s.copy,s.overlay||'',s.note])];
 fs.writeFileSync(path.join(here,'shot_list.csv'),csv.map(row=>row.map(v=>'"'+String(v).replaceAll('"','""')+'"').join(',')).join('\r\n'));
 let board=`<svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1640" viewBox="0 0 2560 1640"><rect width="2560" height="1640" fill="#f4f0e5"/><text x="64" y="83" font-family="Arial" font-size="49" font-weight="bold" fill="#234d40">Find the fox.</text><text x="64" y="126" font-family="Arial" font-size="24" fill="#53695f">CARPET CLEANER · 15-SECOND AD STORYBOARD · V2</text><text x="1710" y="86" font-family="Arial" font-size="23" fill="#775635">PREPRODUCTION / STILL REFERENCES</text><text x="1710" y="123" font-family="Arial" font-size="22" fill="#53695f">Gameplay recording happens in the next pass.</text>`;
 shots.forEach((s,i)=>{
  const x=64+(i%3)*824, y=170+Math.floor(i/3)*688;
  board+=`<g transform="translate(${x} ${y})"><rect width="792" height="660" rx="22" fill="#fffdf7" stroke="#d6e0d4" stroke-width="2"/><text x="23" y="42" font-family="Arial" font-weight="bold" font-size="27" fill="#234d40">${s.id} / ${s.start.toFixed(1)}–${s.end.toFixed(1)}s</text><text x="23" y="82" font-family="Arial" font-size="25" fill="#53695f">${xml(s.title)}</text><image x="22" y="105" width="290" height="516" href="${s.frame}"/><text x="337" y="145" font-family="Arial" font-size="20" font-weight="bold" fill="#ba7046">TAKE ${s.take}</text>`;
  s.lines.forEach((line,j)=>board+=`<text x="337" y="205" dy="${j*48}" font-family="Arial" font-size="25" fill="#234d40">${xml(line)}</text>`);
  board+=`<path d="M337 374h422" stroke="#d6e0d4" stroke-width="2"/><text x="337" y="416" font-family="Arial" font-size="20" fill="#63746b">${s.id==='03'?'Still shows the target result.':'Current game, staged still.'}</text><text x="337" y="452" font-family="Arial" font-size="20" fill="#63746b">Moving take still to record.</text>`;
  if(s.id==='05')board+=`<image x="642" y="480" width="90" height="160" href="${montageB}"/>`;
  board+='</g>';
 });
 board+=`<text x="64" y="1595" font-family="Arial" font-size="23" fill="#53695f">Normal-speed strokes. Visible cuts compress progress. 99% finish polish. Existing original audio. Google Play link pending.</text></svg>`;
 fs.writeFileSync(path.join(here,'Storyboard.svg'),board);
 await sharp(Buffer.from(board)).png().toFile(path.join(here,'Storyboard.png'));
 const template=fs.readFileSync(path.join(here,'preview_template.html'),'utf8');
 const payload={shots,montageB,hookB,hookC,guide:vector('safe_guide.svg')};
 fs.writeFileSync(path.join(here,'Ad_Preview.html'),template.replace('__PREVIEW_DATA__',JSON.stringify(payload).replaceAll('<','\\u003c')));
 console.log(JSON.stringify({shots:shots.length,frames:9,duration:15,storyboard:'Storyboard.png',preview:'Ad_Preview.html',recorded:false}));
}
run().catch(e=>{console.error(e);process.exit(1);});
