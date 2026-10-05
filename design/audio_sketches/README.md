# Carpet Cleaner audio auditions

## Restoration completion cue

`CarpetToy/assets/audio/restoration_complete.wav` is a quiet, original 0.84-second three-note resolution for the full-restoration reveal. It has smooth attacks and releases, no noise layer, and silence at the clip boundaries. It is mono PCM16 at 44.1 kHz (37,044 frames, approximately 72 KiB of PCM). The import sidecar explicitly preserves PCM and the runtime stream explicitly disables looping.

`GameAudio.play_completion()` uses a fourth reusable voice. It respects the effects switch and muted test mode, rejects calls while inactive or unfocused, and stops immediately on effects mute, context exit, application pause or focus loss. Returning focus or unmuting does not replay an old cue. The workshop owns when this method is called: once for a full restoration, never for early finish. Existing v2 music and brush loops are retained unchanged.

The same offline generator creates this asset. `completion_cue_manifest.json` records successful source readback, finite samples, zero clipping and silent boundaries. This verifies the file, not subjective sound quality; final in-game and phone listening remain necessary.

## Second pass: smoother integrated loops

The v2 pass responds to feedback that the first music and brush sketches sounded grainy. The original auditions below remain unchanged for comparison.

- `quiet_shop_music_v2_audition.wav`: 14-second preview with a gentle beginning and ending. Music attacks are softer, the upper harmonics are quieter and exactly in tune, and reflections are restrained.
- `brush_dirty_to_clean_v2_audition.wav`: six smoother synthetic textile strokes. The discrete gritty ticks are removed; both layers have much less high-frequency energy. Successive strokes reduce the soil layer while retaining fabric contact.

The runtime loops are integrated through `game_audio.gd` and are in `CarpetToy/assets/audio/`:

| Asset | Length | Channels | Forward-loop interval, in sample frames |
| --- | --- | --- | --- |
| `quiet_shop_music_loop.wav` | 24 seconds | Stereo | 0–1,058,400 |
| `brush_fabric_loop.wav` | 4 seconds | Mono | 0–176,400 |
| `brush_soil_loop.wav` | 4 seconds | Mono | 0–176,400 |

All three are 44.1 kHz, 16-bit PCM WAV. Circular synthesis wraps note tails, reflections, filtered noise and slow modulation across the boundary. The files do not add silence or an ending fade at the loop point. The audio controller enables forward looping on its stream copies; checked-in import sidecars retain uncompressed PCM. The standalone audition files deliberately do not loop.

The three runtime files total approximately 4.71 MiB of PCM data. Synthesis runs offline, so the game only needs ordinary audio playback. Compressed music can be considered after the mix is approved; these WAVs preserve a straightforward editable source for the prototype.

`tools/synthesize_game_audio.py` deterministically regenerates v2 using Python and NumPy. `audio_manifest_v2.json` records file readback, clipping, spectrum and loop-boundary checks. All files contain finite samples with zero clipping. Every loop boundary's adjacent-sample change is below its normal interior 99.9th-percentile change. This checks abrupt splices, not subjective sound quality. These assets have not been independently listened to by the generator; listening in the running game and on Android remains necessary.

### Integration starting points

The current integration and completion sound are recorded in [Completion payoff](../Completion_Payoff.md). [Fiber and audio pass](../Fiber_Audio_Pass.md) records the earlier experiment; the fiber effect has since been removed. The suggestions below remain useful tuning guidance rather than exact current mixer settings.

- Use the fabric and soil files as two continuous layers, faded with actual contact and motion. Do not restart either file for each input event or clump.
- Start with music at −12 dB, fabric at −4 dB and soil at −8 dB relative to the supplied files, then adjust by listening. These are starting values, not a calibrated loudness specification.
- Use a short smooth attack and release to avoid gain clicks. Retain fabric on clean carpet and reduce soil according to the current local dirt/contact result.
- Keep pitch variation small, if used. Large or frequently randomized pitch shifts can reintroduce roughness.
- Provide independent music/effects controls. A user choosing silence should not lose visual information.
- Check phone speakers as well as headphones. The darker brush texture could need some upper-midrange restored for small speakers; do not equate a lower high-frequency measurement with a better final sound.

## Original first-pass auditions

These are standalone listening sketches, not integrated game assets or final mixes.

- `quiet_shop_music_sketch.wav`: 14-second original instrumental sketch, 80 BPM, stereo. Gentle synthesized plucks and pads. It has an ending and is not a seamless loop.
- `brush_dirty_to_clean_sketch.wav`: 9.1-second synthetic sound study, mono. Six brush strokes move from gritty to softer texture. It is not a recording of a real brush and is not a seamless gameplay loop.

Both were composed and synthesized locally using additive synthesis and filtered noise, with no downloaded music or sound samples. Files are 44.1 kHz, 16-bit PCM WAV. The accompanying manifest records signal checks; listening and in-game mixing remain necessary.

## Proposed gameplay direction

Keep music quiet and provide separate music and effects controls. Prototype a continuous cloth/bristle layer that follows actual brush contact and speed, plus a grit layer driven by actual dirt removal. Fade grit as each patch becomes clean while retaining a soft grooming sound. Match sound, material response, and optional haptics to the same current brush contact.

A real brush-on-carpet recording can replace or complement the synthetic texture after auditioning. Production assets need seamless edits, volume balancing, device listening checks, and an Android performance/latency check before integration is considered finished.
