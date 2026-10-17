# Dark surface and retained cleaning debris

Updated 13 October 2026. Dry cleaning earns money as dirt is pulled from the fabric, while loose dirt fills the existing visual pool.

## Player behavior

- Mint Meadow and the practice brush rug start under dark warm-brown, textured soil at 94% strength. Fully removing soil restores the original rug colors.
- The starter brush removes 10% of surface dirt per full pass: ten passes clear a fully covered spot. The strongest current brush takes five. Feathered edges need overlapping coverage.
- Reversing direction must travel at least the brush head's depth (0.22 rug units). Releasing ends a pass; input-event frequency cannot increase its strength.
- All original clumps are immediately available. Repeated dirty strokes borrow unused clumps from anywhere in the fixed 560-slot pool.
- Pulled clumps become fully visible during brush contact and move on the first physics tick. The rug entrance reveal remains animated.
- Cleared floor debris stays full-sized after settling outside the rug. Fresh dirty strokes reclaim settled debris only when more pool slots are needed, using the existing 0.6-second shrink and 64-slot reserve.
- Dry-cleaning income follows surface-mask removal, independently of particle landing, disappearance or collection. Wallet updates use the existing 0.20-second batching and whole-coin count-up. Rebrushing clean fabric earns nothing.
- Only settled, credited clumps fully off the rug are reclaimed. Loose dirt on the rug remains brushable. If all slots are busy, cosmetic emissions are skipped; cleaning and income continue. Returned slots serve current contact without delayed births.

Total rug time depends on brush width, sweeping loose debris off, and the existing 75% manual / 99% automatic completion thresholds. Cleaning pays its existing share progressively; full restoration settles the remaining share. The total carpet quote is unchanged.

## Engineering

The existing MultiMesh, mesh, node and all 560 progress identities are reused. Canonical scatter points sample newly removed surface dirt once per pass. Any free visual identity can serve an extraction point, and `credited` is never reset during reuse. Original dormant clumps remain physically brushable even when an older save already cleaned their surface.

`free_slots` supplies dormant/recycled visuals, `floor_debris` holds settled clumps available for reclamation, and `timed_debris` carries only requested fades. Motion and requested fades finish independently of input; idle time never starts additional fades or creates dirt. Rebrushing cancels a fade until the clump is cleared again. Swept collision catches fast strokes.

`retired_credits` tracks visual retirement only. `removed_dry_clearance()` reports surface-mask removal. The durable paid watermark prevents duplicate income when clumps land, fade, return to the rug or reuse a slot. Saved `dry_cleaning_clearance` anchors income to the restored mask, so L8 rounding cannot invent payable work; only subsequent surface removal advances it. Dry-shop payment uses surface cleanliness; completion still uses both loose-debris clearance and surface cleanliness. Wet runoff keeps its existing earnings timing.

Version-1 rug snapshots retain `debris_policy: 2` and lifecycle arrays. Retained floor dirt stays visible across reloads. Already-started partial shrink survives JSON reload, while older elapsed-time ages become retained debris. Hidden credited clumps recover their retirement mark. The legacy `pending_emissions` key stays empty; old requests are validated and discarded. Malformed arrays are rejected before changing progress. Pause freezes work; vacuum begins at visible sizes; water-only recipes clear dry simulation state. Masks, eligible cleaning progress and paid money commit together.

## Validation

Use Godot 4.7.2 stable Mono through the pinned wrapper and isolate every gameplay run with `-- --shop-test`. Dirt mesh and visibility checks require the real renderer.

- `validate_incremental_cleaning.gd`: actual brush extraction, immediate count-up and timer payment before dirt motion, all 560 slots visible, full-pool cleaning income, idle retention, reload idempotence, save failure/retry, focus pause, completion and free Gym isolation.
- `validate_split_cleaning_ledger.gd`: surface-based dry income before physical clearance, unchanged completion gates and full quote, replay/reload idempotence, atomic writes and malformed progress rejection.
- `validate_brush_recycling.gd`: demand-triggered bounded fades, retained floor, fresh-contact reuse, fixed allocation, full-pool income, pause and JSON compatibility.
- `validate_cleaning.gd`, `validate_dirt_pool.gd`, and `validate_dirt_reentry.gd`: input, rendering, motion, physical progress, entrance reveal, re-entry and idle sleep.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_brush_recycling.gd -- --shop-test
```
