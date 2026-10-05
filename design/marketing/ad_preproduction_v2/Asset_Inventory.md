# Fox discovery ad — asset inventory

29 September 2026. Preproduction only: this audit reads the existing files and runtime behavior. It does not record footage, edit audio, or generate a trailer. Paths below are relative to the repository root.

## Audio ready for a recording pass

These four files are the sources actually loaded by `CarpetToy/scripts/game_audio.gd`. Their WAV headers and PCM samples were read again for this inventory. All are uncompressed signed 16-bit PCM at 44,100 Hz, with no samples reaching full scale. Peak and RMS values describe source files, not the final gameplay mix or a loudness-normalized ad.

| Source | Duration / frames | Channels | Peak / RMS dBFS | Use |
| --- | --- | --- | --- | --- |
| `CarpetToy/assets/audio/quiet_shop_music_loop.wav` | 24.00 s / 1,058,400 | Stereo | −11.37 / −22.75 | Quiet original music; eight 4/4 bars at 80 BPM |
| `CarpetToy/assets/audio/brush_fabric_loop.wav` | 4.00 s / 176,400 | Mono | −10.75 / −23.16 | Continuous soft fabric contact |
| `CarpetToy/assets/audio/brush_soil_loop.wav` | 4.00 s / 176,400 | Mono | −12.77 / −24.58 | Soil-removal layer, fading as the contacted patch clears |
| `CarpetToy/assets/audio/restoration_complete.wav` | 0.84 s / 37,044 | Mono | −14.89 / −25.68 | Restrained one-shot resolution for a full restoration |

The `.wav.import` sidecars preserve PCM (`compress/mode=0`) and do not normalize, trim, or downsample. Runtime copies explicitly loop music and brush sources from frame 0 to the complete frame count; the completion cue never loops. Loop sources have continuous boundary synthesis rather than a baked ending. The completion cue has silence at its endpoints.

Provenance is recorded in `design/audio_sketches/README.md`, `audio_manifest_v2.json`, `completion_cue_manifest.json`, and the offline source `tools/synthesize_game_audio.py`: original additive composition and filtered-noise synthesis, with no downloaded samples, external recordings, or external audio-generation model. No separate third-party audio license or attribution file was found among these assets. This is a provenance inventory, not a claim that an external music license was purchased.

Listening comparisons are in `design/audio_sketches/quiet_shop_music_v2_audition.wav` (14 s) and `brush_dirty_to_clean_v2_audition.wav` (9.1 s, six strokes). They contain deliberate beginnings/endings and are not runtime loops. The older `*_sketch.wav` files are the earlier grainier pass and should not be selected accidentally for this edit. The v2 files passed numerical checks; phone-speaker balance and subjective mix approval still need listening.

## What the game actually sounds like

- Four reusable playback voices; no audio synthesis runs during play.
- Fabric follows real brush contact and speed. Soil plays only while the current action removes dirt, weighted by the local remaining soil. Already-clean contact retains the softer fabric layer. Stationary input expires after 75 ms; gain attack/release is approximately 25/45 ms.
- Music gain targets are 0.40 at Home and 0.22 while cleaning, with another ×0.72 reduction during active brushing. These are linear gains applied to the already quiet source file.
- The completion cue plays at linear gain 0.52 when the full-restoration reveal starts, after suction. It does not play for early finish. Effects mute, focus loss, application pause and leaving the audio context stop it; returning focus does not replay it.
- There is no dedicated coin, purchase, rug-unroll, vacuum, hose, or squeegee sound asset in this four-voice system. The old storyboard's coin ticks and tool-arrival sounds were directions, not shipped recordings. Do not describe them as existing audio or add a metallic debris tick that revives the rejected graininess.

For a recording session, use the pinned `tools/run_godot.ps1` launcher and retain `-- --shop-test --audition-audio`. `--shop-test` isolates the audio preference file to `res://.godot/audio_test_<process-id>.cfg` and, by default, sets physical playback gain to zero while still exercising playback nodes. `--audition-audio` opts that isolated run back into audible output; it does not bypass Music/Sound settings or focus handling. `--audition-audio` alone does not establish an isolated game save. Keep APPDATA/LOCALAPPDATA in the recording's workspace profile as required for test gameplay.

For clean stems in a later edit, the existing WAVs can be mixed separately instead of layering them over an already audible gameplay recording. Decide which source supplies each sound before assembly so brush and completion events are not doubled. No stem recording or remix was made for this inventory.

## Picture sources and what each proves

| Files | Verified size | Appropriate use / limitation |
| --- | --- | --- |
| `art/renders/discovery_playful_fox_dirty.png`, `discovery_playful_fox_partly_dirty.png` | 390 × 844 | Current Fox appearance and strong dark-to-pattern contrast. Partial view was made with real brush strokes in a controlled test. It is a still, not evidence of real-time job duration. |
| `art/renders/discovery_playful_fox_clean.png` | 390 × 844 | Clean motif/art reference. The validator stages a fully clean mask; it is not the record of a naturally completed job. |
| `art/renders/discovery_playful_fox_reveal_before.png`, `discovery_playful_fox_reveal_after.png` | 390 × 844 | Actual runtime comparison/reveal presentation, reached from a controlled completion fixture. Good layout references; record a real completion for the ad. |
| `art/renders/discovery_mint_meadow_*.png`, `discovery_sunburst_geometry_*.png` | 390 × 844 | Other real pattern renders; the Sunburst reveal is deliberately an early finish at 75%, not a full restoration. Its resumed/Before-this-session views should not be labeled the rug's original arrival. |
| `art/renders/completion_full_after_portrait.png`, `completion_full_before_portrait.png`, `completion_early_finish.png` | 390 × 844 | Current finishing UI and 99%-acceptance polish. These are completion-test fixtures. The full portrait pair shows Mint, not Fox. |
| `art/renders/completion_full_after_landscape.png` | 844 × 390 | Layout validation, not a vertical ad source. |
| `design/marketing/references/01_home.png` through `07_clean_rug_fixture.png` | 720 × 1280 | Older v1 storyboard references. All are marked staged in `capture_manifest.json`; use as historical shot guidance. |
| `design/marketing/Storyboard_15s_v1.png` | Concept board | Generated illustration of shot intent, not captured gameplay. |

The inspected discovery/completion portrait images are **390:844, not 9:16**. They are suitable for planning, not masters to stretch into a 1080 × 1920 export. Record fresh vertical footage at the intended aspect, with consistent composition and safe-area planning. Retain their current large-rug framing where practical.

The old 720 × 1280 stripe image visibly uses lighter soil than the current dark layer. Its storyboard also says the starter needs two passes; the current production recipe is ten passes with 0.94 dust strength. Its old clean-rug fixture manually clears dry/wet masks, hides tools, and displays a staged 100% HUD. Its upgrade captures seed money: `04_first_upgrade.png` is the real 1.44× first wider brush, while `04_upgraded_brush.png` is the 1.75× maximum width. Those are not interchangeable. None should serve as current timing, dirt contrast, or natural progression evidence.

The current full finish accepts 99% and fades residual dry-soil shading to zero during the 1.8-second suction. It preserves actual earned progress and payouts. Early finish keeps its residual dirt. The ad can use that clean reveal as real current behavior; it should not imply that a 75% early finish has the same pristine outcome. Optional Before compares the captured arrival for the same rug, or the actual session-entry state when resumed.

## Pattern identity and art provenance

| Rug name | Stable ID | Pattern source |
| --- | --- | --- |
| Mint Meadow | `mint_meadow` | `CarpetToy/assets/carpet/mint_meadow_mint_meadow_albedo.png` is the imported material source; `mint_meadow_albedo.png` is the authored source. Geometry/art generation is recorded in `tools/build_carpet.py` and `art/asset_manifest.json`. |
| Sunburst | `sunburst_geometry` | `CarpetToy/assets/carpet/patterns/sunburst_geometry.png` |
| Fox's Den | `playful_fox` | `CarpetToy/assets/carpet/patterns/playful_fox.png` |

The two new source PNGs are 1024 × 1536. They were generated with the built-in image tool; exact prompts and date are retained in `design/Rug_Artwork_Prompts.md`. They are in-game pile textures on the existing mesh, not concept artwork substituted for gameplay. Their importer caps the longest dimension at 1024 and supplies mipmaps. No new fibers or new rug geometry are involved.

Paid jobs rotate Mint → Sunburst → Fox per store. Fox is not the first rug for a fresh save. Select or reach Fox in an explicitly isolated capture setup, then keep that stable ID through the cleaning, completion and comparison. Do not match-cut a Fox cleaning stroke into the current Mint completion still. The actual comparison retains the completed rug even though the ledger has already reserved the next design.

## Sound direction for the Fox discovery cut

Use the current softer material sound as the foreground. Begin with contact already happening, so the first visible brush movement and first audible scrape share an onset. A partial ear or cream cheek appearing beneath the dirt should carry the hook without a loud impact or mystery sting.

During the brushing section, keep fabric continuous within each visible gesture and reduce the soil layer only as real dirt removal diminishes. An edit to later progress may compress time, but should have a matching sound edit rather than a scrape continuing after the brush leaves. Keep the opening action at real speed. Additional passes are part of the game's promise and should not be hidden inside one impossibly effective stroke.

Leave a small acoustic pause as the brush lifts and suction finishes. Align the existing 0.84-second completion cue with the clean Fox reveal, not with an unrelated title appearance or the last dirty stroke. Let it resolve once. A brief optional comparison can use the existing music bed without inventing another reward sound.

Music can sit quietly beneath the material action, using its 0.75-second beat / 3-second bar as a loose edit guide. For a 15-second cut, choose a musically coherent source segment by listening; the loop already contains wrapped tails at frame zero. Add a short entry envelope if needed and a gentle final fade in the edit rather than hard-cutting the sustained bed. Brush loops can wrap at their 4-second boundaries, but editorial contact envelopes must still match the visible gesture. Keep the full completion cue tail intact. These are instructions for the future mix, not changes to the game files.

Keep the transformation legible with audio muted. Source sample peaks do not establish perceived ad loudness; approve the finished mix through headphones and phone speakers after picture is locked.

## Title and destination

Use **Carpet Cleaner** as the review-cut working game title and **Fox's Den** only when naming this rug. The current project window title is `Carpet Cleaner • Mint Meadow`; it should not cause the Fox ad to label its fox pattern Mint Meadow. The user has now confirmed Google Play availability, superseding the old board's unknown-release assumption. The vector review end card uses **Play now** with **On Google Play**. The actual store URL and listing identity remain to be verified before attaching the finished ad's destination. The kit uses original text treatment, not a platform badge or an invented rating.

## Next recording inputs

Record the current Fox job in the same isolated session from partial discovery through full finish, retaining the dirty arrival for its real comparison. Capture clean source footage at the final vertical aspect; keep the source audio route intentional. Record a short silent version too, or mute the approved edit for readability review. The existing stills, original loops and completion cue are enough for preproduction; fresh motion footage and a listened-to final mix are the remaining assets.
