const fs=require('fs'),path=require('path');
const deps='C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const {chromium}=require(path.join(deps,'playwright'));
async function main(){
 const browser=await chromium.launch({headless:true,channel:'msedge'});
 try{
  const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('file:///'+path.join(__dirname,'Review.html').replace(/\\/g,'/'));
  for(const width of [1060,390]){
   await page.setViewportSize({width,height:1100});
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>document.documentElement.clientWidth+1);
   if(overflow)throw Error('Review overflows at '+width);
   await page.screenshot({path:path.join(__dirname,`Finished_Review_${width}.png`),fullPage:true});
  }
  const playback=await page.evaluate(async()=>{
   const videos=Array.from(document.querySelectorAll('video'));
   return await Promise.all(videos.map(async v=>{
    v.muted=true;v.playbackRate=1;
    const ended=new Promise((resolve,reject)=>{
     v.addEventListener('ended',()=>resolve({id:v.id,duration:v.duration,ended:v.ended,width:v.videoWidth,height:v.videoHeight,error:v.error?.message||null}),{once:true});
     v.addEventListener('error',()=>reject(Error(v.error?.message||'Video error')),{once:true});
     setTimeout(()=>reject(Error('Playback did not finish: '+v.id)),25000);
    });
    await v.play();return await ended;
   }));
  });
  if(errors.length)throw Error(errors.join('\n'));
  const report={playback,layout:'Desktop and390px fit; both videos play to completion at normal rate',browser:'Edge headless',errors};
  fs.writeFileSync(path.join(__dirname,'exports/Playback_QA.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
 }finally{await browser.close()}
}
main().catch(e=>{console.error(e);process.exit(1)});
