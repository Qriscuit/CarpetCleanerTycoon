# Dark surface and demand-driven debris recycling

Updated 28 September 2026. This replaces the initial five-pass / timed-disappearance prototype.

## Player behavior

- Mint Meadow and the practice brush rug start under dark warm-brown, textured soil at 94% strength. Zero remaining dirt restores the original rug colors exactly.
- The starter brush removes 10% of surface dirt per full pass: ten passes clear a fully covered spot. The strongest current brush takes five. Feathered edges need overlapping coverage.
- Reversing direction must travel at least the brush head's depth (0.22 rug units), so tiny jitter no longer counts as repeated full-strength passes. Releasing still ends a pass; input-event frequency cannot increase its strength.
- All original clumps are immediately available. Repeated dirty strokes borrow unused clumps from anywhere in the fixed 560-slot pool instead of waiting for dust-depth bands.
- Floor debris stays visible while the player is idle or supply is plentiful. When new extraction draws down the 64-slot reserve, the oldest eligible floor clumps shrink over 0.6 seconds and return to supply. Already-requested replacements emerge as those slots become free.
- Only settled, credited clumps fully off the rug are reclaimed. Loose dirt still on the rug remains brushable. The queue holds at most 64 pending emissions if supply runs out; it never allocates more clumps or erases uncredited live debris to make room.

These pass counts describe surface removal at a spot. Total rug time also depends on brush width, sweeping loose debris off, and the existing 75% manual / 99% automatic completion thresholds. Already-cleaned portions of saved jobs retain their earned progress.

## Why the previous change could still feel fast

The prior version counted a reversal after only 0.08 rug units; short scrubbing could rapidly remove 20% layers. Owned upgrades also retain their strength, and loose-clump removal can dominate whole-rug duration. The pale 58%-strength surface made the rug look nearly clean early. The new version changes both the visual contrast and the amount of deliberate brushing required.

## Engineering

The existing MultiMesh, mesh, node and all 560 progress identities are reused. Canonical scatter points sample newly removed surface dirt once per pass. Any free visual identity can serve an extraction point, and `credited` is never reset during reuse. Original dormant clumps remain physically brushable even when an older save already cleaned their surface, so saved debris progress cannot become stranded.

`free_slots` supplies dormant/recycled visuals. `floor_debris` preserves settlement order. `timed_debris` contains only pressure-requested fades. `pending_emissions` bridges an exhausted pool and remains bounded to 64. Motion, fades and existing requests finish independently of input; idle time never starts new extraction or replenishes an unused reserve. Retained settled dirt sleeps. Rebrushing cancels a fade, and prior pending requests can obtain replacement supply after settlement.

Version-1 rug snapshots add `debris_policy: 2`, ordered floor indices and bounded pending requests to the previous lifecycle arrays. New saves preserve partial shrink and queued extraction, including through JSON round trips. Old elapsed-time ages are discarded when loading, so old jobs adopt retention. Malformed state is rejected before changing progress. Pause freezes work; vacuum begins at current visible sizes; water-only recipes clear all dry queues.

## Validation

All nine suites passed on Godot 4.7.2 stable Mono with the actual OpenGL renderer, isolated workspace profiles and `-- --shop-test`:

| Suite | Result / relevant coverage |
| --- | --- |
| `validate_brush_recycling.gd` | 42 checks: ten-pass strength, global borrowing, reserve exhaustion, bounded queues, same-pass/clean-stroke protection, smooth shrink, pause, JSON resume, migration, malformed saves, canceled-fade recovery, fixed allocation |
| `validate_dirt_pool.gd` | 33 checks: allocation reuse, legacy scatter and snapshot compatibility |
| `validate_feel.gd` | Zero failures; ten passes, short-reversal protection, genuine reversal accumulation, seed growth |
| `validate_cleaning.gd` | Zero failures; full sweeps, input, retained dirt and idle sleep |
| `validate_dirt_reentry.gd` | Zero failures; re-entry, pressure reclamation, permanent credit and save/resume while sliding |
| `validate_contract.gd` | Zero failures; reward and completion behavior |
| `validate_rug_transition.gd` | 29 checks, zero failures |
| `validate_second_store_wet.gd` | 61 checks, zero failures |
| `validate_gym.gd` | 378 checks, zero failures |

The engine emitted its existing Windows root-certificate-store warning. No suite or script failed in the final runs.

Production-scene captures were inspected at the dirty start, after one, five and ten scripted passes, and after debris settled. They show the dark brown surface progressively revealing the original bright rug stripe. Current captures are `art/renders/dark_brush_layers_*.png`; the earlier `brush_layers_*` captures show the superseded prototype. These are scripted strokes through the real gameplay API, not a player completion recording.

Run the focused check with APPDATA and LOCALAPPDATA pointing to an isolated workspace test profile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_brush_recycling.gd -- --shop-test
```

Phone touch feel and phone performance still need hands-on validation. Whole-rug duration has not been measured; ten passes is a tuning choice, not evidence of improved retention.
