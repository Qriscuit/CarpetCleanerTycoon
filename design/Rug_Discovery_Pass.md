# Three rugs worth discovering — 29 September 2026

Paid cleaning jobs now use three distinct patterns on the existing rug geometry:

| Name | Stable identity | Discovery |
| --- | --- | --- |
| Mint Meadow | `mint_meadow` | Original mint-and-cream flower design |
| Sunburst | `sunburst_geometry` | Warm geometric sun and stepped diamonds |
| Fox's Den | `playful_fox` | A large curled orange fox with a blue border |

New players see Mint → Sunburst → Fox → Mint. Each store advances its own sequence through completed manual jobs; automated orders do not consume discoveries. Early finish also advances the sequence. Existing unfinished saves keep Mint, regardless of historical job count; after completion they join the count-based sequence. This can mean one repeated Mint for an existing player.

The new designs deliberately retain the starter ten-pass cleaning, 0.94 dirt strength, geometry, rewards and 560-clump pool. Artwork appears through the real dirt mask. A broad diamond or a fox's face/tail gives partial cleaning something recognizable to expose. This implements the proposed reason to continue, but does not establish a retention lift.

## Reliable jobs and presentation

`rug_catalog.gd` holds stable paid identities. Rug definitions accept a pile texture plus optional pile, binding and fringe colors. Original material values are cached, so returning to Mint restores its exact authored appearance. Gym's existing dry and wet exercises remain independent.

The ledger saves `active_rug_id` in each store and includes `rug_id` in surface snapshots. Job reservation, payment and replacement identity share the existing atomic transaction. Failed writes roll them back together. Explicit mismatched or invalid runtime snapshot IDs are rejected before mutation. Legacy saves without IDs keep their existing Mint rug and progress. Damaged saved IDs recover from the reserved identity or valid snapshot, falling back to Mint without erasing progress or money.

The completion reveal and optional comparison retain the rug that was actually cleaned, even though the next job has already been reserved. A restored session uses its actual resumed mask for “Before this session.” Existing coverage serialization has 8-bit precision; the exact saved coverage is restored, with at most one byte difference from the original live image conversion.

## Art and mobile cost

New source assets:

- `CarpetToy/assets/carpet/patterns/sunburst_geometry.png`
- `CarpetToy/assets/carpet/patterns/playful_fox.png`

Both are 1024 × 1536 original raster textures generated with the built-in image generation tool. [The complete production prompts](Rug_Artwork_Prompts.md) are retained. Godot imports cap the longest dimension at 1024 and generate mipmaps. The existing soil shader's texture slot is reused; there are no new shader passes, fiber effects, particle systems or per-stroke art allocations. The three catalog resources are preloaded, adding bounded texture memory in exchange for avoiding art loads during rug swaps. Phone performance and thermals remain unmeasured.

## Verification

Pinned Godot 4.7.2 stable Mono/.NET; gameplay checks use `-- --shop-test` and an isolated profile under `build/rug-discovery-profile`. Renderer checks run sequentially with GL Compatibility.

| Check | Assertions | Failures |
| --- | ---: | ---: |
| Rug identity, migration, rollback and independent stores | 33 | 0 |
| Three-rug discovery, actual rendering and save/re-entry | 98 | 0 |
| Progression | 91 | 0 |
| Completion reveal | 64 | 0 |
| Dirt pool | 37 | 0 |
| Rug transitions | 30 | 0 |
| Coin rewards | 64 | 0 |
| Second-store wet cleaning | 61 | 0 |
| Total | 478 | 0 |

`tools/validate_rug_discovery.gd` writes 16 real gameplay captures to `art/renders/discovery_*.png` and a report to `art/rug_discovery_validation.json`. Captures include dirty, partly brushed, clean and before/after views. Texture and rendered-image comparisons verify different motifs beyond color changes. Checks also verify mesh, material, scene and pool reuse through a full cycle, including restoration of Mint's original materials.

The older `validate_shop_state.gd` has 12 pre-existing assertions based on obsolete upgrade prices and production rates, and incorrectly exits successfully after those assertions. An isolated copy of pre-change commit `46e9ae8ff49e0388f4b93f587658e64cfb52df80` reproduced the identical failures; evidence is under `build/rug_identity_baseline`. Those results are not counted as passes above. No game-script or shader errors occurred in the final passing suites. Desktop tooling emits the existing certificate-store diagnostic.

The required `Build APK.cmd` produced and independently signature-verified `build/CarpetCleaner.apk` at 04:10 EDT on 29 September 2026: 40.8 MiB, SHA256 `171DBE30B53F0D2B7029EF5FB81C95E4039E385B8AD2A9BA1152502AD8ECDF28`. The build uses matching 4.7.2 stable Mono templates. No Android device was connected, so this is an export verification rather than a physical-phone performance result.

## Next playtest

Watch whether players recognize the next motif during partial cleaning, continue to reach it, and use the final comparison. Compare the same short cleaning/ad sequence with the different patterns, keeping brush strength and timing constant. The key question is whether the desire to see another restoration survives once the first surprise is gone.

The restoration album remains deferred until that interest is tested. It should record meaningful completed work if built later, rather than adding a collection screen before discovery itself is compelling.
