# Audio sources for the next edit

These are byte-for-byte copies of the game's current runtime sources, packaged on 29 September 2026. They were not edited, normalized, compressed, or mixed for this pack. Source and copied SHA256 hashes were compared and matched for all four files.

All sources are original offline additive composition / filtered-noise synthesis from `tools/synthesize_game_audio.py`, with no downloaded samples or external recordings. Provenance and signal checks are recorded in `design/audio_sketches/README.md`, `design/audio_sketches/audio_manifest_v2.json`, and `design/audio_sketches/completion_cue_manifest.json`. These paths are relative to the repository root.

| Pack file | Original path from repository root | Format / duration |
| --- | --- | --- |
| [quiet_shop_music_loop.wav](quiet_shop_music_loop.wav) | `CarpetToy/assets/audio/quiet_shop_music_loop.wav` | Stereo PCM16, 44.1 kHz, 24.00 s loop |
| [brush_fabric_loop.wav](brush_fabric_loop.wav) | `CarpetToy/assets/audio/brush_fabric_loop.wav` | Mono PCM16, 44.1 kHz, 4.00 s loop |
| [brush_soil_loop.wav](brush_soil_loop.wav) | `CarpetToy/assets/audio/brush_soil_loop.wav` | Mono PCM16, 44.1 kHz, 4.00 s loop |
| [restoration_complete.wav](restoration_complete.wav) | `CarpetToy/assets/audio/restoration_complete.wav` | Mono PCM16, 44.1 kHz, 0.84 s one-shot |

SHA256, identical for each source and its packaged copy:

```text
quiet_shop_music_loop.wav
3915A38A70818FD21849C4B752BC3782CB415C229F8ADC231E15578A22FAF69C

brush_fabric_loop.wav
975E7A9D089A711850B6BB831E3E5FB7EF83828813A986307D789FE73B9D0D23

brush_soil_loop.wav
5B349BC0C009AE80AFD7A826A4EAC67D2A73A43C1FA8ECD2CF5A9926DDEF816B

restoration_complete.wav
11990AB2482F6C1E6CEE2F61639A3051E86760809B5BB458EF57E593FAA79EA5
```

The local storyboard preview is silent. Use these files during the subsequent edit, with fabric/soil tied to actual visible contact and the completion cue aligned once to the full-restoration reveal. Avoid doubling sounds already captured in gameplay audio. Final synchronization, mix and phone listening are still to be done; see [Asset Inventory](../Asset_Inventory.md) for loop handling and runtime behavior.
