# Recorded-gameplay editing handoff

The edit is assembled from fresh motion takes. Raw recordings are never overwritten. The existing preproduction stills must not be used as gameplay footage.

Installed encoder: FFmpeg/FFprobe 5.1.2, with libx264, AAC, FFV1 and PCM support. Recommended capture master is MKV with FFV1 video and PCM audio when the capture route supports it. H.264 CRF 16 / veryfast with PCM in MKV is a lighter alternative. Preserve the full original recordings. Capture at a stable native portrait resolution and normal game speed. Turn off in-game music when collecting sound effects so a single continuous music bed can be edited underneath. Do not double the completion sound.

`tools/build_ad_video.py` accepts an edit JSON whose paths are relative to the JSON. Each live shot supplies `source`, `in` in seconds and `frames` at 30 fps. Optional `crop` is `[x,y,width,height]` in source pixels. A crop is applied before a uniform scale; no aspect stretching or speed changes are supported. `audio` is `source` or `mute`. A separately captured synchronized source can be supplied with `audio_source` and `audio_in`. Captions reference the outlined SVGs. The internal guide is prohibited in exported art.

The last shot uses `kind: "endcard"`, with an actual clean Fox take and timestamp. Its `crop` isolates the actual rug. The editor extracts one frame and places it into the existing vector end card. This three-second hold is intentional; gameplay shots must move.

The original music bed is added once. `audio_events` is optional and should remain empty when the real completion sound is present in source audio. If an isolated cue is required, include it once at the real reveal onset and mute its original occurrence. Never place the brush loop under footage indiscriminately: visible contact governs the source sound.

The pipeline renders lossless shot intermediates, concatenates at exact frame boundaries, mixes original audio, masters the final mix to a conservative −18 LUFS / −1 dBTP target, and exports 1080×1920, 30 fps H.264/AAC MP4 with fast start. Output includes the WAV mix and an edit report with source hashes, trims, timeline frames and codec metadata. Loudness targets are production choices, not platform requirements. Review the completed mix on headphones and a phone before publication.

Caption overlays fade in and settle upward by 12 pixels over 0.14 seconds. Set a clip's `overlay_intro_seconds` to another duration, or zero for a static caption. This animates only the authored caption; gameplay remains at its original speed and starts immediately. The end card stays steady. Final-video review exports are written to `stills/ad_poster.jpg` at 8.3 seconds and `stills/Contact_Sheet.jpg` with six extracted frames. Override `poster_time` or `review_frame_times` in the edit if the selected moments change.

For the 15-second plan, use 60 + 90 + 66 + 69 + 38 + 37 + 90 frames. The 38/37-frame montage pair approximates 1.25 seconds per rug while preserving a 450-frame master. Final source trims may change to protect real completion timing; keep the total at 450 frames.

Run with the bundled Python runtime and Sharp's Node modules available in `NODE_PATH`. First use `--validate-only` to check all take ranges and crop bounds. Then render and inspect representative frames, playback, sound synchronization, and the exported duration. This document is a production handoff; it does not claim any footage has already been recorded.

```powershell
$env:NODE_PATH = 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules'
& 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/build_ad_video.py design/marketing/ad_production_v1/edit.json --node 'C:/Users/Hurshuuuuuu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
```

The bundled Node executable must be passed explicitly on this host: the unrelated system Node installation cannot load the sandboxed bundled Sharp directory reliably. The end-card hero receives rounded corners and a light shadow so any retained gameplay floor reads as an intentional picture panel. The actual rug pixels remain unchanged.

Color processing is explicit. The captured AVI reports full-range JPEG YUV with a BT.601 (`bt470bg`) matrix. Each take is decoded using that actual matrix/range into RGB; caption PNGs and the end-card art are composited in RGB. Only then does the pipeline convert the completed image into limited-range BT.709 YUV. Both the lossless intermediates and H.264 master carry matching BT.709 metadata. It does not relabel BT.601 values as BT.709. Source matrix/range choices are recorded per clip and may be overridden only for a source with incorrect or absent metadata.

Review frames decode the finished BT.709 video into RGB PNGs, then Pillow makes the JPEG copies. This avoids a misleading direct FFmpeg JPEG export whose matrix interpretation could hide a master color mismatch. The corrected diagnostic's decoded PNG palette samples are within two 8-bit channel values of the authored vector colors: mint `(189,224,195)` → `(188,222,194)`, cream `(255,245,221)` → `(253,244,219)`, green `(35,77,64)` → `(34,76,62)`. This confirms the diagnostic's matrix handling and ordinary 8-bit round-trip tolerance; it is not a claim of exact lossless color in the compressed final ad.

An isolated two-second encoder check at `build/ad_pipeline_test` used a standard color-test pattern and sine tone, not game footage. It confirmed exact 60-frame 1080×1920 output, intact two-second AAC audio, BT.709 metadata, SVG compositing and a measured −18.01 LUFS result. This diagnostic is not an ad asset. A full edit still requires its own picture and sound review.
