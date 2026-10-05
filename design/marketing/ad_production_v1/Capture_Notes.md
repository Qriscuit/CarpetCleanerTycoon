# Carpet Cleaner — capture provenance

The raw gameplay recording is complete: three full restorations recorded from the current local game using Godot MovieWriter. The existing storyboard stills were framing references only. This document and `source_manifest.json` identify the source, completed capture and capture-specific setup. Final edited-video review is recorded separately by the editor.

## Source identity

- Repository HEAD: `46e9ae8ff49e0388f4b93f587658e64cfb52df80`.
- The working tree contains the previously developed cleaning, rug discovery, sound and completion changes. It is not a clean copy of the committed HEAD. The manifest records the observed status and SHA-256 hashes for 152 relevant source files, including their asset import settings and identity files.
- The production cleaning scene is `CarpetToy/scenes/production/rug_cleaning.tscn`. Its root uses `workshop.gd`; practice scenes and staged validation stills are not substitutes for this scene.
- Five files from the pinned Godot 4.7.2 stable Mono bundle are hashed. The actual capture log starts with `Godot Engine v4.7.2.stable.mono.official.ed1daf0bf`, confirming the required runtime. This provenance audit did not launch the engine itself.
- `config/features` still contains the legacy `4.6` project feature label. That metadata is not the engine version and does not permit using Godot 4.6.

## Capture-only setup

The successful capture used an isolated copy at `build/ad-capture-v2/session-001/project`. Source assets, scripts, resources, scenes and imported cache files were copied there. The original project configuration was not changed by this production setup. Rechecking all 152 original source hashes after capture found no changes since the provenance snapshot.

The isolated project's configuration sets a 1080 × 1920 viewport, a 540 × 960 preview window, viewport stretching, MovieWriter quality 0.9, 30 fps, and a 48 kHz movie audio mix. The runtime harness restores `Window.CONTENT_SCALE_MODE_VIEWPORT` after the production workshop's ready callback and before its first draw, because the workshop normally selects canvas-item scaling. This changes recording resolution and framing, not cleaning strength, progress or reward rules. The manifest hashes the isolated configuration and compares the copied source files with the source snapshot.

`workshop.gd` computes brush elapsed time using `Time.get_ticks_msec()`. Offline movie rendering can take more or less wall time than the captured 1/30-second frame. The capture driver corrected the previous stroke timestamp for each input frame using alternating 33/34 ms intervals, so speed-dependent clump motion and brushing audio follow the captured timeline. This correction is confined to the capture driver; the production script's cleaning logic was not altered.

Gameplay entered the normal input path through `InputEventScreenTouch` and `InputEventScreenDrag`, delivered to the root viewport. The driver used one movement per rendered frame and normal two-second strokes. Inspection found no direct dirty-mask seeding, coverage writes, strength changes, wallet seeding, direct soil strokes, manual physics loops, or invented rewards. The isolated ledger was reset before the first job and then accumulated real rewards. A partly cleaned opening is selected from the resulting genuinely earned progress. Editing may cut forward between real takes, but must not imply that one stroke cleans a newly dirty carpet.

The driver requires `-- --shop-test`, uses a dedicated capture ledger and audio settings, and was run with the isolated workspace profile. The capture log confirms that `--audition-audio` enabled the production effects. Music was disabled during capture to allow a continuous music bed in the edit; brush and completion effects were recorded from the game. These safeguards keep the player's real progress and audio settings separate from production capture.

## Completed raw recording

- Session: `build/ad-capture-v2/full-game-001`.
- Source movie: `restorations.avi`, 2,175,400,342 bytes.
- Video: 1080 × 1920, 30 fps, 8,360 Motion JPEG frames, 278.666667 seconds.
- Audio: stereo signed 16-bit PCM at 48 kHz, 13,376,000 sample frames. Its duration matches the video exactly at the sample/frame level. This structural check does not replace final listening review.
- Capture started at 2026-09-29 17:40:51 UTC and took 311.427028 seconds of wall time. Playback still runs at the normal recorded 30 fps; rendering wall time does not determine game speed.
- Capture completed successfully with an empty capture error field. All three jobs used starter width 1.0, power 1.0 and removal per pass 0.1. The final earned wallet was 120 coins.

| Restored rug | Accepted clearance | Reward / resulting wallet | Suction / reveal |
|---|---|---|---|
| Mint Meadow | 99.0041% | 40 / 40 coins | 54 / 72 frames |
| Sunburst | 99.0041% | 40 / 80 coins | 54 / 72 frames |
| Fox's Den | 99.0041% | 40 / 120 coins | 54 / 72 frames |

At 30 fps, the observed 54-frame suction and 72-frame reveal equal the expected 1.8 and 2.4 seconds for every rug. No second full sweep or early finish was needed.

The engine log contains one `ERROR:` message: “Failed to read the root certificate store,” from the Windows certificate loader. It is a nonfatal engine message, not a capture or gameplay failure. This offline recording has no certificate-store dependency; the movie and three completed paid jobs were produced successfully. No script errors or other capture failures were found.

The manifest stores SHA-256 hashes for the final capture driver, raw movie, take manifest, event log, engine log and independent audit. The raw movie hash is `6f4b8bd1e160a0015406ba50d71362f48cb03188c2956d73f7fb8408bfec7019`; the capture driver hash is `fdba3f61cd56ee64e2b80ca6d1fd9616399c1b03380762283f1721fce6fb27cd`.

## Facts checked against source

| Ad assumption | Source finding | Editing implication |
|---|---|---|
| Three rugs worth discovering | Paid jobs cycle Mint Meadow → Sunburst → Fox's Den. Identity is chosen from each store's completed manual job count and saved with the reserved job. | Reach the fox by completing the first two paid jobs in a fresh branch. Keep authentic take logs. |
| Repeated, satisfying brushing | All three dry rugs use 0.1 removal per ideal pass and 0.94 initial surface shading strength. Feathered edges or incomplete contact may need extra passes. | Ten passes is a local ideal, not a guaranteed full-rug duration. Do not claim a whole job takes 15 seconds. |
| First upgrade feels wider | Store 1's first tool upgrade costs 80 coins and changes width from 1.0 to 1.44. Power remains 1.0. | Show the wider lane if producing the upgrade cut; do not claim stronger cleaning per spot. |
| Two first jobs afford the upgrade | At Store 1 payout level zero, a full restoration earns 40 coins; early finish earns 20. No purchase or bonus is needed between two full jobs to reach 80. | Record the ledger naturally. Payout upgrades, store changes or bonus claims would change this sequence. |
| Full completion has a payoff | Accepted full completion starts at 99%; suction takes 1.8 seconds, then the full reveal holds for 2.4 seconds. Early finish is allowed at 75% and has a 1.1-second reveal. | Use an actual full restoration for the hero ending. Include enough handles for the complete suction and clean reveal. |
| Tiny soil remnants disappear | Full restoration smoothly fades shader `dust_strength` to zero during suction. Saved coverage and the reward are not rewritten. Early finish preserves visible remaining soil. | The pristine final look is real game behavior, not an editor retouch. |
| Dirt emerges with the brush | The production scene has 560 pooled clumps, a 64-slot reserve and a 0.6-second demand-triggered reclaim fade. Missed extraction is not queued at an old brush position. | Check the actual take for prompt clumps; keep both stroke and clump motion visible. |
| Existing sound supports the cut | The game has a 24-second stereo music loop, two 4-second mono brush loops, and a 0.84-second completion cue. All are 44.1 kHz, 16-bit PCM source assets. | Mix and resample once for the export; avoid adding a fictional in-game vacuum or purchase sound without labeling it as editorial sound design. |

The final edit can use crops, captions and graphic transitions, but should document any speed changes. A normal-speed opening is the preferred proof of how the game feels. The source manifest distinguishes the driver's one-based frame counter from the engine's frame index; selected edit ranges must use the encoded movie's verified mapping. Final mixed audio/video sync and playback quality remain editorial checks.

## Public release status

The user confirmed that Carpet Cleaner is available on Google Play and will provide the link. The public listing's identity and its installed build have not been checked against this local source. Use the planned “Play now / On Google Play” wording, but do not invent a destination URL, price, rating or store badge. Confirm the public build contains the advertised features before publishing the ad.

## Remaining editorial checks

1. Record selected source frame ranges and verify the encoded-frame mapping.
2. Verify that the selected opening's visible progress and clumps are synchronized with the brush.
3. Review the finished video with audio and muted, then inspect the exported file's resolution, duration, frame rate and synchronization.
4. Hash the final `Carpet_Cleaner_Find_the_Fox_15s_v1.mp4` after encoding. The editor owns that final export hash; this capture audit deliberately does not hash an in-progress output.
5. Check the supplied Google Play destination and public build before publishing. No publishing is included in this production pass.
