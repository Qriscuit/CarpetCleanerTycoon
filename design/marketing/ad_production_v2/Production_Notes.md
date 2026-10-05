# Carpet Cleaner — The illustrated cut

29 September 2026 · Version 2 · 15-second portrait ad

[Watch](Review.html) · [MP4](exports/Carpet_Cleaner_Illustrated_15s_v2.mp4) · [Six exported frames](stills/Contact_Sheet.jpg)

This revision restores the visual character of the original illustrated storyboard: rounded teal lettering with generous cream outlines, softly shaded mint leaves, small gold sparkles, and an orange play button. Every graphic is authored as editable vector art. The actual recorded game remains the main picture.

## What changed

- The plain caption boxes become expressive cream-edged lettering, with small botanical and brush-stroke accents.
- The clean reveal receives a restrained illustrated celebration.
- The two-rug montage asks “One more rug?” in the same visual style.
- The ending keeps the restored fox rug full-size. A large title and leaf ribbon arrive first, followed by the play button. The held real game frame slowly enlarges by 2% over three seconds; the lettering stays stable while the small gold accents drift slightly.
- Caption entrances settle gently into position. The first hook is visible on frame one.

## Picture and timing

| Time | Action | Artwork |
| --- | --- | --- |
| 0–2 s | A real late-stage brush pass reveals the fox | “Find the fox.” |
| 2–5 s | Adjacent brush passes | “Brush. Reveal.” |
| 5–7.2 s | Final brushing and the real completion suction | No extra caption |
| 7.2–9.5 s | Restored fox rug | “Fresh again.” |
| 9.5–12 s | Restored Mint and Sunburst rugs | “One more rug?” |
| 12–15 s | Held real fox frame, gently enlarged | “Carpet Cleaner / One more rug. / Play now / On Google Play” |

The same source trims, normal gameplay speed, live brush effects, completion sound, and original music are retained from version 1. This is an art revision, not a new capture or a change to the game. Visible cuts condense the longer restorations. The final three seconds deliberately hold a recorded frame; they do not imply new gameplay camera behavior.

[Exact edit](edit.json) · [Original capture provenance](../ad_production_v1/Capture_Notes.md) · [Independent capture audit](../../../build/ad-capture-v2/full-game-001/logs/independent_audit.json)

## Editable artwork

- [Combined endcard](art/endcard_overlay.svg)
- [Title and leaf ribbon](art/endcard_title.svg)
- [Play button](art/endcard_cta.svg)
- [Gold accents](art/endcard_sparkles.svg)
- [Opening caption](captions/hook_discovery.svg), [brushing caption](captions/process.svg), [clean reveal](captions/reveal.svg), [next rug](captions/next_rug.svg)

Production SVG lettering is converted to paths for reliable rendering. Editable text versions are in `art/editable_text/` and `captions/editable_text/`. The artwork contains no embedded raster graphics. Source-generation helpers are `tools/build_ad_vector_identity.cjs` and `tools/build_ad_caption_art.cjs` at the repository root.

## Export and review

1080 × 1920, 30 fps, 450 frames / 15 seconds, H.264 video with AAC stereo. Source footage is decoded using its recorded color metadata, artwork is composed in RGB, then the finished frames are explicitly converted to BT.709 video. Live effects and music use the existing two-pass loudness master targeting −18 LUFS.

[Export report](exports/Edit_Report.json) · [Final checks](exports/Final_QA.json) · [Audio mix](exports/Carpet_Cleaner_Mix.wav)

The exported video was checked at phone size and played to completion in the browser. The comparison switch and direct endcard jump were verified. Local video review uses `tools/serve_ad_review.py` for reliable seeking; the review is available at `http://127.0.0.1:8768/Review.html` while that server is running.

Version 1 is preserved and can be selected on the review page. Google Play availability was confirmed by the user; the store URL and public build still need checking when supplied. This is a local review export; nothing has been published.
