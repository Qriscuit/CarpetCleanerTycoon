const fs = require('fs');
const path = require('path');
const deps='C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const viz='C:/Users/Hurshuuuuuu/.codex/visualizations/2026/10/13/01a135c7-8741-7c02-9c16-5a639146ef11';
const fragment=path.join(viz,'satisfying-clean-storyboards.html');
const data=JSON.parse(fs.readFileSync(path.join(__dirname,'storyboard_data.json'),'utf8'));
let html=fs.readFileSync(fragment,'utf8');
html=html.replace(/(<script type="application\/json" id="clean-storyboard-data">)[\s\S]*?(<\/script>)/,(_,a,b)=>a+JSON.stringify(data)+b);
fs.writeFileSync(fragment,html);
for(const [name,shots] of Object.entries(data)){
  if(shots[0].start!==0 || shots.at(-1).end!==15) throw new Error(name+' duration');
  for(let i=1;i<shots.length;i++) if(shots[i-1].end!==shots[i].start) throw new Error(name+' discontinuity');
}
if(JSON.stringify(data.A.slice(1))!==JSON.stringify(data.B.slice(3))) throw new Error('Shared body differs');
if(Buffer.byteLength(html)>1000000) throw new Error('Visualization too large');
console.log('Both timelines cover 0–15s; shared bodies are identical; inline data refreshed.');
if(process.argv.includes('--browser')) (async()=>{
  const {chromium}=require(path.join(deps,'playwright'));
  const browser=await chromium.launch({headless:true,channel:'msedge'});
  try {
  const page=await browser.newPage();
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto('file:///'+path.join(viz,'storyboards-preview.html').replace(/\\/g,'/'));
  const frame=page.frames().find(f=>f!==page.mainFrame());
  await frame.locator('#clean-preview-a').waitFor();
  for(const width of [736,320]){
    await page.setViewportSize({width,height:1200});
    await page.waitForTimeout(150);
    const overflow=await frame.evaluate(()=>document.documentElement.scrollWidth>document.documentElement.clientWidth+1);
    if(overflow) {
      const over = await frame.evaluate(()=>Array.from(document.querySelectorAll('*')).map(e=>({tag:e.tagName,cls:e.className,left:e.getBoundingClientRect().left,right:e.getBoundingClientRect().right})).filter(e=>e.right>document.documentElement.clientWidth+1));
      console.log(JSON.stringify({over:over.slice(0,12), dimensions:await frame.evaluate(()=>({docWidth:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth,bodyWidth:document.body.clientWidth,bodyScroll:document.body.scrollWidth,svgWidth:document.querySelector('.clean-timeline').clientWidth,svg:document.querySelector('.clean-timeline').outerHTML}))}));
      await page.screenshot({path:path.join(__dirname,`Preview_${width}.png`),fullPage:true});
      throw new Error('Horizontal overflow at '+width);
    }
    await page.screenshot({path:path.join(__dirname,`Preview_${width}.png`),fullPage:true});
  }
  await frame.locator('#clean-time').fill('12');
  await frame.locator('#clean-time').dispatchEvent('input');
  if(!(await frame.locator('#clean-shot-a').textContent()).includes('Enjoy the clean')) throw new Error('Scrub failed');
  if(!(await frame.locator('#clean-shot-b').textContent()).includes('Enjoy the clean')) throw new Error('Shared scrub failed');
  if(errors.length) throw new Error(errors.join('\n'));
  console.log('Desktop and 320px layouts fit; timeline interaction passes; no browser errors.');
  const brief=await browser.newPage();
  await brief.goto('file:///'+path.join(__dirname,'Production_Brief.html').replace(/\\/g,'/'));
  await brief.evaluate(async()=>{
    const imgs=Array.from(document.images);
    imgs.forEach(i=>i.loading='eager');
    await Promise.all(imgs.map(i=>i.decode().catch(()=>{})));
  });
  for(const width of [1180,390]){
    await brief.setViewportSize({width,height:1100});
    const overflow=await brief.evaluate(()=>document.documentElement.scrollWidth>document.documentElement.clientWidth+1);
    const missing=await brief.evaluate(()=>Array.from(document.images).filter(i=>!i.complete || i.naturalWidth===0).map(i=>i.src));
    if(overflow || missing.length) throw new Error('Brief layout or images at '+width+': '+missing.join(', '));
    await brief.screenshot({path:path.join(__dirname,`Brief_${width}.png`)});
  }
  console.log('Production brief fits desktop and phone; board images load.');
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1});
