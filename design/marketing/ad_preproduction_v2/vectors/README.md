# Carpet Cleaner vector kit

Ten actual SVG assets, all on a 1080 × 1920 canvas. The main SVGs contain outlined lettering and original vector shapes; they need no linked image or installed font to render. The matching files in `editable_text/` keep live Arial text for copy changes. No font binaries are bundled.

| File | Copy / purpose |
| --- | --- |
| `hook_discovery.svg` | Find the fox. |
| `hook_satisfaction.svg` | That clean stripe. |
| `hook_completion.svg` | One spot left. |
| `process.svg` | Brush. Reveal. |
| `reveal.svg` | Fresh again. |
| `next_rug.svg` | What’s under / the next one? |
| `upgrade.svg` | Wide brush / 44% wider strokes |
| `wordmark.svg` | CARPET / CLEANER |
| `endcard.svg` | Full cream/mint background, working title, Play now / On Google Play |
| `safe_guide.svg` | Internal composition guide only; remove before export |

Caption plates sit at x96, y306, width804. Single-line plates are 150 pixels high; the next-rug plate is 240 pixels high. The upgrade variant has a small label above its main line. Caption and wordmark painted bounds fit the internal x96–900, y300–1220 working rectangle. This guide is not an official or universal platform safe zone.

The end card is opaque. Place the selected rug footage or image above it at **x365, y505, width350, height565**. The central area is deliberately clear; the hero belongs in a separate composition layer. The CTA sits at x230, y1100, width620, height115. Google Play is plain descriptive text, not an imitated store badge. The actual store destination still needs to be attached to the finished ad.

All other primary files retain transparency. Composite them directly over gameplay at full-canvas scale. `previews/` contains half-size PNGs with alpha; `contact_sheet.png` uses a pale background only to show the full sheet clearly. The exported vectors themselves have no preview background.

`asset_manifest.json` records dimensions, alpha checks, visible bounds, copy, use, source font paths, and provenance. Lettering uses the locally installed Windows Arial Regular/Bold fonts, converted into paths with bundled `@napi-rs/canvas`; `sharp` verifies SVG rendering. The plates and end-card geometry were authored for this project without stock illustration or borrowed platform UI.

To revise copy, edit the matching live-text SVG in a vector editor, or change the source definitions in `build_vector_kit.cjs` and regenerate the entire kit. The generator can use the bundled Node runtime. Set `CARPET_NODE_MODULES` if its dependencies are installed elsewhere. Text variants need Arial or a deliberately chosen substitute; outlined versions are the portable delivery files.

Visual review: all ten assets rendered successfully, text fits without clipping, and the end card leaves the requested hero rectangle unobstructed. No gameplay was recorded and no video was rendered in this vector pass.
