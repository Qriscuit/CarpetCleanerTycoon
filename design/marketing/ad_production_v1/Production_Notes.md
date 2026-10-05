# Carpet Cleaner — Find the fox

First cut, 29 September 2026. The 15-second film uses newly recorded gameplay from the current local game, the authored vector kit, live game effects and the existing original music.

[Watch the review](Review.html) · [Download the MP4](exports/Carpet_Cleaner_Find_the_Fox_15s_v1.mp4) · [Edit decisions](edit.json)

## The cut

| Ad time | Selected action | Treatment |
| --- | --- | --- |
| 0.00–2.00 | A late real pass through the fox's face, continuing into a reversal | “Find the fox.” The action is already underway. |
| 2.00–5.00 | Later adjacent-lane passes on the same rug | “Brush. Reveal.” A visible cut compresses the intervening work. |
| 5.00–7.20 | Last effective brushing, then the real full-completion suction | No added copy. This continues into the reveal from the same source. |
| 7.20–9.50 | The clean fox gets its own moment | “Fresh again.” The captured completion sound plays once. |
| 9.50–12.00 | Clean Mint, then clean Sunburst | “What's under the next one?” Separate restorations in a montage. |
| 12.00–15.00 | A held frame of the restored fox in the cream-and-mint card | “Carpet Cleaner / Play now / On Google Play.” |

The montage allocates 38 and 37 frames to the two rugs: the closest split of 2.5 seconds at 30 fps. The other boundaries follow the storyboard exactly. The captions fade in and settle by 12 pixels over 0.14 seconds. The end card remains steady for three seconds.

## Recording and continuity

The uncut source is [restorations.avi](../../../build/ad-capture-v2/full-game-001/restorations.avi): 8,360 frames, 4 minutes 38.67 seconds, at 1080 × 1920 and 30 fps, with stereo PCM sound. Mint, Sunburst and Fox are completed in sequence. Each reaches the production 99% threshold and earns 40 coins; the real wallet ends at 120. The starter brush remains unchanged throughout.

The capture driver sends ordinary touch input one movement per rendered frame. Godot MovieWriter exports the actual production scene with its normal simulation timing. The driver aligns the brush's input timestamp to that frame duration, since offline rendering does not necessarily take the same wall-clock time. No dirt masks, cleaning strength or rewards are fabricated. This is a capture of the game driven by scripted gestures, not a recording of a human play session or an Android performance benchmark.

The source camera/HUD use the actual production layout. Editorial crops remove most interface distractions; they preserve scale and aspect ratio. The final card uses a deliberately held captured frame. The staged storyboard stills do not appear in the finished film.

The pinned Godot **4.7.2 stable Mono/.NET** launcher was used. A separate capture copy sets the recording resolution; the original gameplay files and the player's real save were not changed. Test progress and audio preferences are isolated under `build/ad-capture-v2/`.

[Capture evidence](../../../build/ad-capture-v2/full-game-001/take_manifest.json) · [Independent capture audit](../../../build/ad-capture-v2/full-game-001/logs/independent_audit.json) · [Source provenance](Capture_Notes.md)

## Picture and sound

The export targets H.264, 1080 × 1920, 30 fps, BT.709 and AAC stereo, with the video header arranged for prompt playback. The recorded JPEG color format is explicitly decoded before compositing, then converted to BT.709 for video so the game's and vector kit's colors remain consistent. Clip intermediates use lossless compression. The original raw recording remains untouched.

Live fabric, dirt and completion effects come from the recorded game. Music was disabled during capture and added as one continuous quiet bed for the edit. The other rug reveals are muted to avoid repeating the reward sound. A two-pass loudness master targets −18 LUFS and a ceiling of −1 dB true peak. [Export measurements and exact source trims](exports/Edit_Report.json).

The [poster](stills/ad_poster.jpg) and [contact sheet](stills/Contact_Sheet.jpg) are extracted from the exported video. The [final audio mix](exports/Carpet_Cleaner_Mix.wav) and [rebuild instructions](Edit_Pipeline.md) are retained for further changes.

## Final checks

The final MP4 contains exactly 450 frames / 15.000 seconds, with intact stereo sound. Measured loudness is -18.01 LUFS and true peak is -4.61 dBTP, leaving headroom. It played through in the review browser. Final crops, all three rug designs, caption readability and decoded vector colors were checked. [Recorded checks and file hash](exports/Final_QA.json).

## Release details

The user confirmed Google Play availability. The exact store URL, listing name/icon and agreement between the public build and the shown local features still need checking when the link is supplied. This is a review export; no campaign has been created or published.

This pass delivers the main 15-second discovery cut. The longer upgrade concept and alternative openings remain in the preproduction brief for later variants.
