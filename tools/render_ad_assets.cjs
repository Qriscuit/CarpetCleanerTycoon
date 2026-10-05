// Rasterize the authored vector kit; composite only an actual recorded game frame.
const fs = require('fs');
const sharp = require('sharp');
const job = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
async function main() {
  let image = sharp(job.source).resize(1080, 1920).ensureAlpha();
  if (job.kind === 'endcard') {
    const [x, y, width, height] = job.slot;
    const mask = Buffer.from(`<svg width="${width}" height="${height}"><rect width="${width}" height="${height}" rx="24" fill="white"/></svg>`);
    const hero = await sharp(job.hero).resize(width, height, {fit: 'contain', background: '#fffaf0'})
      .composite([{input: mask, blend: 'dest-in'}]).png().toBuffer();
    const shadow = Buffer.from(`<svg width="1080" height="1920"><defs><filter id="s" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="12"/></filter></defs><rect x="${x}" y="${y + 9}" width="${width}" height="${height}" rx="24" fill="#234d40" opacity="0.17" filter="url(#s)"/></svg>`);
    image = image.composite([{input: shadow, left: 0, top: 0}, {input: hero, left: x, top: y}]);
  }
  await image.png().toFile(job.output);
}
main().catch(error => { console.error(error); process.exit(1); });
