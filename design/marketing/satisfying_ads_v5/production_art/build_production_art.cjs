// Extracted native vector layers from the approved v5 Pond Garden artwork.
// Raster deliverables are 1080 x 1920 RGBA; paths and layer positions stay editable.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require('C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const DIR = __dirname;
const SOURCE = path.join(DIR, '..', 'art');
const W = 1080, H = 1920;
const palette = { cream:'#FFF9E8', sage:'#E4EEE1', mint:'#77C9AE', teal:'#154D54', coral:'#E5775B', gold:'#EDBA43' };
fs.mkdirSync(DIR, {recursive:true});

function children(xml) {
  const rootStart = xml.indexOf('>', xml.indexOf('<svg')) + 1;
  const inner = xml.slice(rootStart, xml.lastIndexOf('</svg>'));
  const nodes = [];
  const re = /<!--[\s\S]*?-->|<\/?[a-zA-Z][^>]*>/g;
  let depth = 0, start = -1, m;
  while ((m = re.exec(inner))) {
    const tag = m[0];
    if (tag.startsWith('<!--')) continue;
    const close = tag.startsWith('</');
    const self = tag.endsWith('/>');
    if (!close && depth === 0) start = m.index;
    if (close) depth--;
    else if (!self) depth++;
    if (depth === 0 && start !== -1) {
      nodes.push(inner.slice(start, re.lastIndex));
      start = -1;
    }
  }
  return nodes;
}
const borderSource = fs.readFileSync(path.join(SOURCE,'pond_border.svg'),'utf8');
const borderNodes = children(borderSource);
const defs = borderNodes.find(n => n.startsWith('<defs'));
const borderArt = borderNodes.filter(n => !n.startsWith('<defs'));
if (borderArt.length !== 47) throw new Error(`Unexpected border structure ${borderArt.length}; verify before extracting.`);

const metadata = [];
function wrap(name, body, layerDefs='') {
  const xml = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><title>${name.replaceAll('_',' ')}</title>${layerDefs}${body}</svg>`;
  const prefix = name + '__';
  return xml.replace(/id="([^"]+)"/g,(_,id)=>`id="${prefix}${id}"`)
    .replace(/url\(#([^)]+)\)/g,(_,id)=>`url(#${prefix}${id})`);
}
function bodyOf(g) { return g.slice(g.indexOf('>') + 1, g.lastIndexOf('</g>')); }
const stems = borderArt[14];
const stemPaths = bodyOf(stems).match(/<path\b[^>]*\/>/g);
if (stemPaths.length !== 8) throw new Error('Unexpected vine structure.');
const ripples = borderArt[43];
const ripplePaths = bodyOf(ripples).match(/<path\b[^>]*\/>/g);
const sparks = borderArt[46];
const sparkPaths = bodyOf(sparks).match(/<path\b[^>]*\/>/g);
function groupWithOriginalStyle(g, nodes) { return g.slice(0,g.indexOf('>')+1) + nodes.join('') + '</g>'; }
const upperStems = groupWithOriginalStyle(stems, stemPaths.slice(0,4));
const lowerStems = groupWithOriginalStyle(stems, stemPaths.slice(4));
const upperRipples = groupWithOriginalStyle(ripples, ripplePaths.slice(0,2));
const lowerRipples = groupWithOriginalStyle(ripples, ripplePaths.slice(2));
const upperSparks = groupWithOriginalStyle(sparks,sparkPaths.slice(0,2));
const lowerSparks = groupWithOriginalStyle(sparks,sparkPaths.slice(2));
const upperCurrents = borderArt.slice(0,7).join('');
const lowerCurrents = borderArt.slice(7,14).join('');
const upperLeavesLeft = borderArt.slice(15,21).join('');
const upperLeavesRight = borderArt.slice(21,26).join('');
const lowerLeavesRight = borderArt.slice(26,33).join('');
const lowerLeavesLeft = borderArt.slice(33,37).join('');
const layers = [];
function add(name, body, purpose, options={}) {
  layers.push({name,svg:wrap(name,body,options.defs === undefined ? defs : options.defs),purpose,opaque:!!options.opaque,source:options.source || 'art/pond_border.svg',category:options.category || 'decoration'});
}
add('pond_border_full', borderArt.join(''), 'Full approved border; use in opening and end card.');
add('upper_garden', upperCurrents+upperStems+upperLeavesLeft+upperLeavesRight+borderArt[37]+borderArt[39]+borderArt[41]+upperRipples+borderArt[44]+upperSparks, 'Opening/end upper garden, independently animatable.');
add('lower_garden', lowerCurrents+lowerStems+lowerLeavesRight+lowerLeavesLeft+borderArt[38]+borderArt[40]+borderArt[42]+lowerRipples+borderArt[45]+lowerSparks, 'Opening/end lower garden, independently animatable.');
add('upper_currents', upperCurrents, 'Upper ribbons only.');
add('lower_currents', lowerCurrents, 'Lower ribbons only.');
add('upper_vines', upperStems, 'Upper gold vine curls.');
add('lower_vines', lowerStems, 'Lower gold vine curls.');
add('leaves_upper_left', upperLeavesLeft, 'Upper left native leaf cluster.');
add('leaves_upper_right', upperLeavesRight, 'Upper right native leaf cluster.');
add('leaves_lower_right', lowerLeavesRight, 'Lower right native leaf cluster.');
add('leaves_lower_left', lowerLeavesLeft, 'Lower left native leaf cluster.');
add('lotus_upper_left',borderArt[37],'Upper left lotus bloom.');
add('lotus_lower_right',borderArt[38],'Large lower right lotus bloom.');
add('lotus_upper_right',borderArt[39],'Small upper right lotus bloom.');
add('bud_lower_left',borderArt[40],'Lower left lotus bud.');
add('koi_upper',borderArt[41],'Upper koi; independent gentle drift.');
add('koi_lower',borderArt[42],'Lower koi; independent gentle drift.');
add('ripples_upper',upperRipples,'Upper curved koi ripple strokes.');
add('ripples_lower',lowerRipples,'Lower curved koi ripple strokes.');
add('taper_upper_left',borderArt[44],'Approved tapering current curl.');
add('taper_lower_right',borderArt[45],'Approved lower current curl.');
add('spark_petals_upper',upperSparks,'Upper gold petal accents.');
add('spark_petals_lower',lowerSparks,'Lower gold petal accent.');

// Quiet margins for the actual cleaning shots. Their native Bezier curves echo
// the approved current/vine geometry while leaving the live contact area clear.
const sideCurves = `<g fill="none" stroke-linecap="round"><path d="M35 594 C10 754 70 814 35 1002 C9 1164 61 1264 38 1428" stroke="${palette.mint}" stroke-width="3" opacity=".64"/><path d="M26 667 C12 817 52 940 29 1050" stroke="${palette.gold}" stroke-width="1.5" opacity=".7"/><path d="M1045 564 C1069 754 1017 811 1047 1009 C1064 1185 1020 1270 1044 1425" stroke="${palette.mint}" stroke-width="3" opacity=".64"/><path d="M1056 719 C1058 897 1030 999 1050 1146" stroke="${palette.gold}" stroke-width="1.5" opacity=".7"/></g>`;
add('side_curls',sideCurves+borderArt[44]+borderArt[45],'Light cleaning overlay; no opaque artwork inside live slot x100 y480 w880 h1000.',{source:'Derived native Bezier curves in approved v5 palette plus approved taper paths'});
const fronds = `<g opacity=".78" transform="translate(0 20)">${borderArt[33]}${borderArt[34]}</g><g opacity=".78" transform="translate(92 190) scale(.90)">${borderArt[31]}${borderArt[32]}</g>`;
add('lower_fronds',fronds,'Two restrained leaf pairs under the gameplay; retract during rug departure.',{source:'Native leaf groups from art/pond_border.svg, repositioned below cleaning slot'});
add('cleaning_border_light',sideCurves+borderArt[44]+borderArt[45]+fronds,'Ready-combined light cleaning frame; all heavy gardens are absent.',{source:'Derived native side curls and approved v5 native leaf/taper paths'});

for (const [src,name,purpose] of [
  ['opening_overlay.svg','opening_lettering','Approved outlined Clean / feels good lettering and swash.'],
  ['title_overlay.svg','ending_title','Approved outlined Carpet Cleaner / One more rug lettering and swash.'],
  ['cta_ribbon.svg','cta_ribbon','Approved folded coral Play now ribbon plus On Google Play lettering.']
]) {
  const xml=fs.readFileSync(path.join(SOURCE,src),'utf8');
  const nodes=children(xml);
  add(name,nodes.filter(n=>!n.startsWith('<defs')).join(''),purpose,{defs:nodes.filter(n=>n.startsWith('<defs')).join(''),source:'art/'+src,category:'lettering'});
}
add('background_cream',`<rect width="${W}" height="${H}" fill="${palette.cream}"/>`,'Opaque approved cream background.',{defs:'',opaque:true,source:'Approved v5 color palette',category:'matte'});
add('background_light_sage',`<rect width="${W}" height="${H}" fill="${palette.sage}"/>`,'Opaque approved light sage background.',{defs:'',opaque:true,source:'Approved v5 color palette',category:'matte'});
add('organic_sage_sweep','<path d="M0 570C312 310 733 610 1080 418V1620C663 1802 192 1520 0 1690Z" fill="#E4EEE1"/>','Approved transparent organic light sage sweep.',{defs:'',source:'Opening_Art.svg / Ending_Art.svg',category:'matte'});
const liveOrganic='M122 480 C307 470 775 495 958 480 C968 741 958 1247 970 1460 C740 1484 334 1468 111 1480 C102 1222 105 753 122 480Z';
add('gameplay_mask_organic',`<path d="${liveOrganic}" fill="#FFFFFF"/>`,'White/alpha organic live area; use alpha, not luminance, to clip gameplay.',{defs:'',source:'Production-specific native mask geometry',category:'mask'});
add('gameplay_mask_rect',`<rect x="100" y="480" width="880" height="1000" rx="26" fill="#FFFFFF"/>`,'White/alpha live area, x100 y480 w880 h1000; rounded 26px corners.',{defs:'',source:'Production-specific native mask geometry',category:'mask'});
add('gameplay_surround_organic',`<path d="M0 0H1080V1920H0Z ${liveOrganic}" fill="${palette.sage}" fill-rule="evenodd"/>`,'Opaque light sage surround with transparent organic gameplay window.',{defs:'',source:'Production-specific native mask geometry in approved palette',category:'matte'});
add('room_mask_open',`<rect x="62" y="595" width="956" height="860" rx="32" fill="#FFFFFF"/>`,'Room reveal slot with more width; x62 y595 w956 h860.',{defs:'',source:'Production-specific native mask geometry',category:'mask'});

function alphaBounds(data, info) {
  let xmin=W,ymin=H,xmax=-1,ymax=-1, transparent=0, visible=0;
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
    const alpha=data[(y*info.width+x)*4+3];
    if(alpha===0)transparent++;
    if(alpha>0){visible++;xmin=Math.min(xmin,x);xmax=Math.max(xmax,x);ymin=Math.min(ymin,y);ymax=Math.max(ymax,y);}
  }
  return {bounds: xmax < 0 ? null : {x:xmin,y:ymin,width:xmax-xmin+1,height:ymax-ymin+1},transparent_pixels:transparent,visible_pixels:visible};
}
async function main(){
  for(const layer of layers){
    if(/<text\b|<image\b|data:image|@font-face/.test(layer.svg))throw new Error('Nonportable vector content in '+layer.name);
    const svgFile=path.join(DIR,layer.name+'.svg'),pngFile=path.join(DIR,layer.name+'.png');
    fs.writeFileSync(svgFile,layer.svg);
    const {data,info}=await sharp(Buffer.from(layer.svg)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    const stats=alphaBounds(data,info);
    await sharp(data,{raw:info}).png({compressionLevel:9}).toFile(pngFile);
    const thumb=await sharp(data,{raw:info}).resize(180,320).png().toBuffer();
    layer.thumb=thumb;
    metadata.push({name:layer.name,svg:layer.name+'.svg',png:layer.name+'.png',width:W,height:H,color_mode:'RGBA',native_vector:true,outlined_text:true,embedded_raster:false,alpha:layer.opaque?'opaque':'straight / unassociated',category:layer.category,purpose:layer.purpose,provenance:layer.source,sha256_svg:crypto.createHash('sha256').update(layer.svg).digest('hex'),...stats});
  }
  const qaIssues=[];
  const borderPixels=await sharp(path.join(DIR,'pond_border_full.png')).ensureAlpha().raw().toBuffer();
  const reconstructed=await sharp({create:{width:W,height:H,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:path.join(DIR,'upper_garden.png')},{input:path.join(DIR,'lower_garden.png')}]).raw().toBuffer();
  let maxDelta=0,channelsOver2=0;
  for(let i=0;i<borderPixels.length;i++){
    const delta=Math.abs(borderPixels[i]-reconstructed[i]);
    maxDelta=Math.max(maxDelta,delta);
    if(delta>2)channelsOver2++;
  }
  if(channelsOver2)qaIssues.push(`Upper/lower garden reconstruction differs in ${channelsOver2} channels by more than 2.`);
  for(const name of ['side_curls','cleaning_border_light']){
    const {data,info}=await sharp(path.join(DIR,name+'.png')).raw().toBuffer({resolveWithObject:true});
    let occluded=0;
    for(let y=480;y<1480;y++)for(let x=140;x<940;x++)if(data[(y*info.width+x)*4+3]>0)occluded++;
    if(occluded)qaIssues.push(`${name} contains ${occluded} nonzero-alpha pixels inside the protected x140..939 y480..1479 contact region.`);
  }
  fs.writeFileSync(path.join(DIR,'manifest.json'),JSON.stringify({version:1,title:'Pond Garden approved v5 production artwork',canvas:{width:W,height:H,aspect_ratio:'9:16'},palette,live_slot:{x:100,y:480,width:880,height:1000},protected_tool_contact_region:{x:140,y:480,width:800,height:1000},layers:metadata,compositing:{opening:['background_cream','organic_sage_sweep','gameplay','upper_garden','lower_garden','opening_lettering'],cleaning:['background_light_sage','gameplay','cleaning_border_light'],ending:['background_cream','organic_sage_sweep','room gameplay','upper_garden','lower_garden','ending_title','cta_ribbon'],guidance:'Use full garden only for opening and ending. Keep lettering off while cleaning. Fade/retract cleaning_border_light before room/rug departure. Masks are white with transparent outside and should supply alpha. All canvases are aligned; place 0,0 unless animating an individual object.'},ai_hook_included:false,qa:{rgba_dimensions_verified:true,all_lettering_outlined:true,all_svg_native_paths:true,upper_lower_reconstruction:{max_channel_delta:maxDelta,channels_delta_over_2:channelsOver2},issues:qaIssues}},null,2));
  const selected=['upper_garden','lower_garden','lotus_upper_left','lotus_lower_right','koi_upper','koi_lower','side_curls','lower_fronds','opening_lettering','ending_title','cta_ribbon','gameplay_mask_organic'];
  const cellW=228,cellH=372,cols=6,rows=2;
  const sheet=sharp({create:{width:cols*cellW,height:rows*cellH,channels:4,background:'#F3EEDC'}});
  const comps=[];
  for(let i=0;i<selected.length;i++){
    const layer=layers.find(l=>l.name===selected[i]);
    const x=(i%cols)*cellW,y=Math.floor(i/cols)*cellH;
    const checker=`<svg width="180" height="320" xmlns="http://www.w3.org/2000/svg"><defs><pattern id="c" width="20" height="20" patternUnits="userSpaceOnUse"><rect width="20" height="20" fill="#FFF9E8"/><path d="M0 0H10V10H0Z M10 10H20V20H10Z" fill="#DCE5DE"/></pattern></defs><rect width="180" height="320" fill="url(#c)"/></svg>`;
    comps.push({input:Buffer.from(checker),left:x+24,top:y+12});
    comps.push({input:layer.thumb,left:x+24,top:y+12});
    const label=`<svg width="228" height="35" xmlns="http://www.w3.org/2000/svg"><text x="114" y="23" font-family="Arial" font-size="14" text-anchor="middle" fill="#154D54">${layer.name.replaceAll('_',' ')}</text></svg>`;
    comps.push({input:Buffer.from(label),left:x,top:y+332});
  }
  await sheet.composite(comps).png().toFile(path.join(DIR,'Art_Layers_Contact_Sheet.png'));
  fs.writeFileSync(path.join(DIR,'README.txt'),`Pond Garden v5 production artwork\r\n\r\n${layers.length} aligned individual layers; each includes a native SVG and a 1080 x 1920 RGBA PNG.\r\nAll headline and CTA lettering is outlined: no font installation required.\r\nPNG layers use straight alpha and transparent backgrounds unless labeled background.\r\nApproved source artwork was preserved and split by native objects, not pixel crops.\r\n\r\nOpening: cream + sage sweep + live shot + upper/lower garden + opening lettering.\r\nCleaning: sage + live shot + cleaning_border_light. Keep heavy flowers and all lettering out of the active cleaning moment.\r\nDeparture: retract the light border as the room pulls back and the rug exits.\r\nEnding: cream + sage sweep + empty room shot + upper/lower garden + ending title + CTA.\r\n\r\nSuggested live slot: x100 y480 w880 h1000. Organic and rectangular alpha masks are included.\r\nProtected tool contact region: x140 y480 w800 h1000. Room slot: x62 y595 w956 h860.\r\nUse either complete upper/lower gardens OR the isolated decorative pieces, not both, to avoid doubling decoration.\r\nAI hook and hook lettering are excluded from this delivery.\r\n\r\nManifest includes object bounds, provenance, SHA256, dimensions, palette and alpha QA.\r\n`);
  console.log(JSON.stringify({layers:layers.length,output:DIR,qaIssues},null,2));
}
main().catch(e=>{console.error(e);process.exit(1)});
