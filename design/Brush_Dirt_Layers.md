# Dark surface and demand-driven debris recycling

Updated 29 September 2026. This replaces the initial five-pass / timed-disappearance prototype and removes delayed clump births after brush contact.

## Player behavior

- Mint Meadow and the practice brush rug start under dark warm-brown, textured soil at 94% strength. Zero remaining dirt restores the original rug colors exactly.
- The starter brush removes 10% of surface dirt per full pass: ten passes clear a fully covered spot. The strongest current brush takes five. Feathered edges need overlapping coverage.
- Reversing direction must travel at least the brush head's depth (0.22 rug units), so tiny jitter no longer counts as repeated full-strength passes. Releasing still ends a pass; input-event frequency cannot increase its strength.
- All original clumps are immediately available. Repeated dirty strokes borrow unused clumps from anywhere in the fixed 560-slot pool instead of waiting for dust-depth bands.
- Floor debris stays visible while the player is idle or supply is plentiful. When new extraction draws down the 64-slot reserve, the oldest eligible floor clumps shrink over 0.6 seconds and return to supply.
- Pulled clumps become fully visible in the same input event as brush contact and move on the first physics tick. The earlier 0.18-second growth-before-motion delay is removed; the rug entrance reveal remains animated.
- Only settled, credited clumps fully off the rug are reclaimed. Loose dirt still on the rug remains brushable. If all slots are busy, cosmetic emissions are skipped rather than queued at old contact points. Returned slots serve current brush contact. The pool never allocates more clumps or erases uncredited live debris to make room.

These pass counts describe surface removal at a spot. Total rug time also depends on brush width, sweeping loose debris off, and the existing 75% manual / 99% automatic completion thresholds. Already-cleaned portions of saved jobs retain their earned progress.

## Why the previous change could still feel fast

The prior version counted a reversal after only 0.08 rug units; short scrubbing could rapidly remove 20% layers. Owned upgrades also retain their strength, and loose-clump removal can dominate whole-rug duration. The pale 58%-strength surface made the rug look nearly clean early. The new version changes both the visual contrast and the amount of deliberate brushing required.

## Engineering

The existing MultiMesh, mesh, node and all 560 progress identities are reused. Canonical scatter points sample newly removed surface dirt once per pass. Any free visual identity can serve an extraction point, and `credited` is never reset during reuse. Original dormant clumps remain physically brushable even when an older save already cleaned their surface, so saved debris progress cannot become stranded.

`free_slots` supplies dormant/recycled visuals. `floor_debris` preserves settlement order. `timed_debris` contains only pressure-requested fades. Launch sets visible growth and requests rendering synchronously. Motion and fades finish independently of input; idle time never creates dirt or replenishes an unused reserve. Retained settled dirt sleeps. Rebrushing cancels a fade. Swept collision remains active so fast strokes still catch dirt between input samples.

Version-1 rug snapshots retain `debris_policy: 2`, ordered floor indices and lifecycle arrays. The legacy `pending_emissions` key is written empty; valid requests in older saves are validated and discarded so returning to a job cannot replay old brush contacts. New saves preserve partial shrink, including through JSON round trips. Old elapsed-time ages are discarded when loading, so old jobs adopt retention. Malformed state is rejected before changing progress. Pause freezes work; vacuum begins at current visible sizes; water-only recipes clear dry simulation state.

## Validation

The six relevant suites below were rerun for the 29 September contact-timing fix on Godot 4.7.2 stable Mono with the actual OpenGL renderer, isolated workspace profiles and `-- --shop-test`:

| Suite | Result / relevant coverage |
| --- | --- |
| `validate_brush_recycling.gd` | 47 checks: immediate original/borrowed/recycled births, no births after release, reuse at new contact, legacy queue discard, ten-pass strength, reserve exhaustion, credit, save safety and fixed allocation |
| `validate_dirt_pool.gd` | 36 checks: immediate contact rendering/motion, animated entrance, allocation reuse, legacy scatter and snapshot compatibility |
| `validate_feel.gd` | Zero failures; ten passes, reversal protection and visible seeds launching during contact |
| `validate_cleaning.gd` | Zero failures; full sweeps, input, retained dirt and idle sleep |
| `validate_dirt_reentry.gd` | Zero failures; re-entry, pressure reclamation, permanent credit and save/resume while sliding |
| `validate_rug_transition.gd` | 29 checks, zero failures |

The contract, second-store wet and Gym integration suites also passed on the preceding 28 September revision (zero failures; 61 wet checks and 378 Gym checks).

The engine emitted its existing Windows root-certificate-store warning. No suite or script failed in the final runs.

Production-scene captures were inspected at the dirty start, after one, five and ten scripted passes, and after debris settled. They show the dark brown surface progressively revealing the original bright rug stripe. Current captures are `art/renders/dark_brush_layers_*.png`; the earlier `brush_layers_*` captures show the superseded prototype. These are scripted strokes through the real gameplay API, not a player completion recording.

Run the focused check with APPDATA and LOCALAPPDATA pointing to an isolated workspace test profile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_brush_recycling.gd -- --shop-test
```

Phone touch feel and phone performance still need hands-on validation. Whole-rug duration has not been measured; ten passes is a tuning choice, not evidence of improved retention.
