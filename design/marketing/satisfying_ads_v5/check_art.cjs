const fs=require('fs'),path=require('path');
const deps='C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const {chromium}=require(path.join(deps,'playwright'));
async function main(){
 const data=JSON.parse(fs.readFileSync(path.join(__dirname,'storyboard_data.json'),'utf8'));
 for(const [name,shots]of Object.entries(data)){
  if(shots[0].start!==0 || shots.at(-1).end!==15)throw Error(name+' duration');
  for(let i=1;i<shots.length;i++)if(shots[i].start!==shots[i-1].end)throw Error(name+' timeline gap');
 }
 if(JSON.stringify(data.A.slice(1))!==JSON.stringify(data.B.slice(1)))throw Error('Shared body differs');
 const vectorFiles=['pond_border.svg','opening_overlay.svg','hook_overlay.svg','title_overlay.svg','cta_ribbon.svg'];
 const geometry=[];
 for(const file of vectorFiles){
  const svg=fs.readFileSync(path.join(__dirname,'art',file),'utf8');
  if(/<image\b|<text\b/.test(svg))throw Error('Display art is not portable native geometry: '+file);
  const ids=Array.from(svg.matchAll(/\bid="([^"]+)"/g),m=>m[1]);
  if(new Set(ids).size!==ids.length)throw Error('Duplicate SVG IDs in '+file);
  geometry.push({file,paths:(svg.match(/<path\b/g)||[]).length});
 }
 const browser=await chromium.launch({headless:true,channel:'msedge'});
 try{
  const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('file:///'+path.join(__dirname,'Production_Brief.html').replace(/\\/g,'/'));
  await page.evaluate(async()=>{const images=Array.from(document.images);images.forEach(i=>i.loading='eager');await Promise.all(images.map(i=>i.decode().catch(()=>{})))});
  for(const width of [1180,390]){
   await page.setViewportSize({width,height:1100});
   const result=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>document.documentElement.clientWidth+1,missing:Array.from(document.images).filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src)}));
   if(result.overflow||result.missing.length)throw Error('Brief layout/image failure '+width+JSON.stringify(result));
   await page.screenshot({path:path.join(__dirname,`Review_${width}.png`)});
  }
  if(errors.length)throw Error(errors.join('\n'));
 }finally{await browser.close()}
 const report={timeline:'Both 15s; identical 5–15s body',nativeEnding:{suction:1.8,reveal:2.4,departureToExit:1.95},nativeVectorAssets:geometry,browser:'No errors; images load; desktop and phone fit',scope:'Artwork and preproduction only; no game code or player saves touched'};
 fs.writeFileSync(path.join(__dirname,'Art_QA.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify(report));
}
main().catch(e=>{console.error(e);process.exit(1)});
