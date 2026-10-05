# Fiber and audio pass — 29 September 2026

Historical record: the user rejected the fiber look after trying this pass. Its runtime textures, shading, grooming work and dedicated test were subsequently removed. The revised music and brush audio remain. See [Completion payoff](Completion_Payoff.md) for the current implementation; the measurements and APK described below belong to this earlier experiment.

Implemented in gameplay and included in the signed debug APK at `build/CarpetCleaner.apk`.

## Player-facing changes

- The music has softer attacks and quieter upper harmonics. Brush sounds use smoother continuous fabric and soil layers, without the original discrete grit ticks.
- Music continues between home and cleaning, at a quieter cleaning level. Brushing ducks it further. Home Settings has independent Music and Brush switches, persisted separately from progression.
- Brush audio follows current movement and carpet contact. Actual dirt removal adds the soil layer; already-clean carpet retains soft fabric contact. Bare floor, release, tool change, cancellation, focus loss and scene exit stop contact audio. Stationary input expires without requiring another input event.
- Existing authored fiber normal detail is restored on the pile. Directional grooming shading follows each stroke, appears as that local patch becomes clean (25%–90% reveal), and is reduced while wet. Opposite strokes create restrained light/dark nap. Binding and fringe do not acquire grooming stripes.
- Cosmetic grooming does not change dirt accounting, coins, cleaning difficulty or saves. It resets on a new rug or saved-game resume. Normal detail remains attached during the existing rug-roll animation.

Haptics remain a later step. This pass concentrates on audio and the visible material response.

## Implementation and resource budget

`game_audio.gd` owns three reused playback voices. The original WAV assets were composed/synthesized offline, with no downloaded recordings. Import sidecars explicitly preserve PCM16 rather than Godot's default lossy WAV compression. Runtime loop intervals cover every source frame. Combined PCM is approximately 4.71 MiB. Smooth gain ramps avoid abrupt contact transitions; music and effects are not restarted per input event. The runtime mix is deliberately restrained and still needs listening on the intended phone.

The surface uses the existing opaque mesh and render pass. A fixed 128 × 208 RGBA8 nap image uses 104 KiB on the CPU and 104 KiB raw texture data, plus a 26 KiB pile mask and small coordinate caches. It uploads at most once per changed frame; there is no idle grooming work. Fully dirty regions skip the extra nap/normal texture reads. `soil.set_fiber_effect_enabled(false)` disables both grooming work and its shader effect for comparisons.

The existing 1024 × 1536 normal map is mipmapped but not VRAM-compressed (roughly 8 MiB including mip levels). It was already referenced by the authored material; the new shader actually samples it. The small nap map is therefore not a statement of the entire material's memory use. Directional shading uses a fixed light-direction approximation for the present shop lighting.

## Measured desktop comparison

Godot 4.7.2 stable Mono/.NET, GL Compatibility, NVIDIA RTX 3070, 390 × 844 viewport. Four alternating off/on/on/off runs, 96 controlled frames each, grooming an already-clean rug. This isolates the incremental material interaction; it is not a full-session phone benchmark.

| Work | Fibers off | Fibers on |
| --- | --- | --- |
| Stroke CPU median | 0.715–0.717 ms | 1.172–1.178 ms |
| Stroke CPU p95 | 0.746–0.793 ms | 1.267–1.276 ms |
| Surface-upload CPU median | 0.001 ms | 0.022 ms |
| Rendered frame wall-time median | 16.664–16.665 ms | 16.665 ms |

The observed CPU increment is approximately 0.48 ms including upload. Frame wall time includes synchronization and scheduling, so unchanged 60 Hz pacing does not establish zero GPU cost. No Android phone was connected; device frame time, thermal behavior, sound latency, speaker balance and moving-texture shimmer remain unmeasured.

The rendered comparison found no pixel difference in the fully dirty sample region, while the clean sample region changed by approximately 3.13% mean RGB intensity. Reversing grooming changed the clean region again. Actual captures are in `art/renders/fiber_*.png`, and paired measurements are in `build/fiber_profile.json`.

## Verification

All gameplay validation used the pinned launcher and `-- --shop-test`, with APPDATA/LOCALAPPDATA under `build/fiber-audio-profile`. Player progression and audio preferences were isolated. Audio tests exercise real playback nodes with physical output muted; `--audition-audio` additionally enables sound for an interactive test.

- Fiber validation: 39 checks, 0 failures. Includes immediate direction, local reveal, clean-patch accounting, no-op and idle uploads, quality-off behavior, pile scope, roll tangents, reset/resume and rendered comparisons.
- Audio validation: 58 checks, 0 failures. Includes PCM source/frame bounds, three reused voices, actual mouse/touch routes, valid tool changes, cancellation, focus/background lifecycle, persisted independent switches and 320 × 568 / 844 × 390 settings layouts.
- Existing regressions: home settings 79 checks; rug transition 29; wet cleaning 31; dirt pool 36; cleaning/input and brush-feel suites each reported zero failures. The ten-pass cleaning and immediate dirt contact remain intact.
- Android debug export: 38.4 MiB, signature verified using matching 4.7.2 Mono templates. The builder records the pinned engine's existing EditorSettings shutdown diagnostic after successful export. Test runs also emit the environment's certificate-store diagnostic; no game-script or shader errors remained.

The tests caught and fixed redundant texture uploads caused by comparing rounded color bytes against the image writer's truncated bytes. Audio tests also enforce PCM imports so compressed byte lengths cannot produce incorrect loop bounds.

Reproduce the new checks sequentially:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_fiber_feel.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_game_audio.gd -- --shop-test
```

For listening previews, use `design/audio_sketches/quiet_shop_music_v2_audition.wav` and `brush_dirty_to_clean_v2_audition.wav`. These have an ending and are not the continuous runtime assets. Signal/readback/loop-boundary checks passed; subjective listening remains part of tuning.
