# Current game systems reference

Updated: 28 September 2026. This document describes the implemented project, including the Store 2 recipe, Store 3 unlock fixes, mobile performance pass and ten-pass dark surface cleaning with demand-driven debris recycling. It is a code reference, not a list of proposed features. Paths are relative to this document; `res://` in Godot refers to the `CarpetToy` directory.

## 1. Start here

The game has four stores, a shared wallet, paid cleaning jobs, independent store upgrades, Bonzi automation, and a free Gym. The main scene is the floating shop. Paid jobs use one cleaning scene whose required tools depend on the active store.

| Area | Main files | Responsibility |
| --- | --- | --- |
| Project startup | [project.godot](../CarpetToy/project.godot), [scene_routes.gd](../CarpetToy/scripts/scene_routes.gd) | Main scene, autoload, renderer, shared navigation destinations |
| Persistent game state | [shop_state.gd](../CarpetToy/scripts/shop_state.gd) | Wallet, stores, jobs, purchases, automation, save/load and reward validation |
| Economy rules | [progression.gd](../CarpetToy/scripts/progression.gd) | Prices, payout formulas, tool strengths, store names and Bonzi cycles |
| Home | [floating_home.tscn](../CarpetToy/scenes/production/floating_home.tscn), [floating_home.gd](../CarpetToy/scripts/floating_home.gd) | Store preview, paid-job entry, management sheets, Gym entry and settings |
| Paid cleaning | [rug_cleaning.tscn](../CarpetToy/scenes/production/rug_cleaning.tscn), [workshop.gd](../CarpetToy/scripts/workshop.gd) | Input, tool selection, recipe setup, job progress, transitions and VFX integration |
| Carpet state | [dirt_controller.gd](../CarpetToy/scripts/dirt_controller.gd) | Dirt simulation, coverage/water/extraction masks, progress and rug snapshots |
| Cleaning UI | [cleaning_hud.tscn](../CarpetToy/scenes/ui/cleaning_hud.tscn), [cleaning_hud.gd](../CarpetToy/scripts/cleaning_hud.gd) | Wallet display, progress, Finish, payout upgrades, tool drawer and coin animation |
| Management UI | [compact_shop.tscn](../CarpetToy/scenes/ui/compact_shop.tscn), [compact_shop.gd](../CarpetToy/scripts/compact_shop.gd) | Shop, Tools, Stores and Bonzi sheets |
| Gym | [rug_cleaning_gym.tscn](../CarpetToy/scenes/test/rug_cleaning_gym.tscn), [gym.gd](../CarpetToy/scripts/gym.gd), [gym_hud.gd](../CarpetToy/scripts/gym_hud.gd) | Repeatable free exercises, tool previews, instant wet/dry shortcuts and camera toggle |
| Hose | [water_jet.gd](../CarpetToy/scripts/water_jet.gd), [water_hose_profile.gd](../CarpetToy/scripts/water_hose_profile.gd), [water_soak.gd](../CarpetToy/scripts/water_soak.gd) | Water flight/contact, visible stream, upgrade shape and passive soaking |
| Squeegee | [squeegee_motion.gd](../CarpetToy/scripts/squeegee_motion.gd), [squeegee_water.gd](../CarpetToy/scripts/squeegee_water.gd), [squeegee_water_trail.gd](../CarpetToy/scripts/squeegee_water_trail.gd) | Movement direction, blade splash, cleared-path ridges and edge-spill sources |
| Runoff | [squeegee_runoff_streams.gd](../CarpetToy/scripts/squeegee_runoff_streams.gd) and its [shader](../CarpetToy/scripts/squeegee_runoff_streams.gdshader) | Long, outward-moving, finite-lifetime water ribbons |

## 2. Startup, navigation and ownership

`ShopState` is the autoload declared in `project.godot`. There is one persistent ledger across scene changes. Scenes read it through `/root/ShopState`; they do not own separate wallets.

`scene_routes.gd` supplies three live destinations:

- `MAIN_MENU`: `scenes/production/floating_home.tscn`.
- `CLEANING`: `scenes/production/rug_cleaning.tscn`.
- `GYM`: `scenes/test/rug_cleaning_gym.tscn`.

Home previews both owned and locked stores. Tapping an owned store enters or resumes its job; tapping a locked preview opens Stores. Opening a store is separate from visiting it: `open_next_store()` checks milestones and spends coins once, whereas `select_store()` only switches to an owned branch. Each branch retains its own active job and unfinished rug snapshot.

`floating_home.gd` lazily creates the compact management sheet. Its tabs are internally named `shop`, `items`, `plans` and `bonzi`; `plans` is the visible **Stores** tab. The old names of reusable rows, such as `wide_brush` or `intake`, are UI identifiers, not proof that those old purchases are still offered there.

Opening the production cleaning scene directly also creates or resumes a paid job. Opening Gym sets `practice_only = true`; Gym never converts an exercise into a commission.

## 3. Stores, recipes and completion

### Required stages

| Store | Name | Required stages | Overall completion |
| --- | --- | --- | --- |
| 1 | Neighborhood | Brush | `dry` |
| 2 | High Street | Water, then squeegee | `(water + extraction) / 2` |
| 3 | Wash House | Brush, water, then squeegee | `(dry + water + extraction) / 3` |
| 4 | Restoration Studio | Brush, water, then squeegee | `(dry + water + extraction) / 3` |

All fractions are between 0 and 1. `dry = min(unique_clearance, surface_clearance)`, so removing visible clumps alone does not finish dry cleaning while surface dust remains. Water and extraction fractions are averages over real carpet pixels, excluding empty corners and fringe gaps.

Store 2 uses `workshop.water_only_recipe = true` and `soil.set_recipe(true, true)`. The saved flag is `skip_dry_stage`. Its dry mask is cleared and its dirt clumps are hidden; dry cleaning contributes nothing to its progress. Existing wet/extraction data is retained when loading an older Store 2 job. A new Store 2 rug begins dry with the hose selected.

The next stage becomes available when the preceding stage reaches 99%:

- Store 2: hose until water coverage reaches 0.99, then squeegee.
- Stores 3 and 4: brush until both dry measures reach 0.99; hose until water reaches 0.99; then squeegee.
- Paid tool selection cannot bypass this order. `dirt_controller.recommended_tool()` decides the available tool; internal indices are Brush `0`, Squeegee `1`, Hose `2`.

The hose stops depositing water when its stage completes. Tool changes are coordinated with stroke release, including the case where the final airborne water contact arrives after release.

### Finish and rewards

At 75% overall completion, the player may press Finish for the normal payout. At 99%, the job automatically finishes for twice that amount. These are overall recipe percentages, not percentages of the currently selected stage.

For example, in Store 2 with `water = 0.99`, the normal payout becomes available at `extraction = 0.51`: `(0.99 + 0.51) / 2 = 0.75`. Both stages at 0.99 produce 99% overall completion. This preserves the requirement to water the whole rug before extraction while allowing early completion during extraction.

`workshop.update_contract_status()` drives the progress meter, Finish availability and automatic finish from the same overall value. `shop_state.reward_for_current_job()` independently validates the snapshot and recomputes the recipe total; it does not trust a submitted `overall_clearance` field. The ledger rejects nonfinite/out-of-range values and later-stage progress before the preceding stage is complete. A very small numeric tolerance handles floating-point threshold arithmetic.

The payout upgrade UI shows only the normal **75%** payout, its current-to-next amount and purchase cost. The 99% reward is still calculated as double; it is not a second price that the player must buy.

### Rug appearance is separate from the recipe

[rug_definition.gd](../CarpetToy/scripts/rug_definition.gd) defines appearance and brush behavior: name, hint, tint, dust strength, removal per pass, grain direction and cross-grain efficiency. Resources are in [resources/rugs](../CarpetToy/resources/rugs):

- `mint_meadow.tres`: ten full passes with the starter brush, removing 10% of surface dust each time; dark soil at 0.94 strength. `gym_brush.tres` uses the same removal rate and opacity.
- `terracotta_flatweave.tres`: light dust, one pass.
- `indigo_weave.tres`: three passes; lengthwise brushing is more effective.
- `gym_brush.tres` and `gym_water.tres`: the two Gym exercises.

The three production rug resources are not three independent stages. Current paid entry selects Mint Meadow and repeats that selected rug; the store determines which cleaning stages it requires. Free workshop cycling and Gym selection are separate behaviors.

## 4. Upgrade economy and tool carryover

`progression.gd` is the primary balance file. For store `s`, let `S = 8^(s - 1)`, and let `p` be that store's payout-upgrade count.

| Rule | Current value |
| --- | --- |
| Normal job payout | `S * round(20 * 1.1^p)` |
| Perfect job payout | `2 * normal payout` |
| Next payout-upgrade price | `S * round(25 * 1.15^p)` |
| Four incremental tool-upgrade prices | `[80, 200, 500, 1000] * S` |
| Next-store opening price | `2000 * S`, based on the store being completed |
| Local Bonzi earnings required to open next store | `100 * S` |
| Qualifying paid jobs at the maximum main-tool level | 3 |

Prices are incremental, not cumulative labels. All purchases use the same wallet. Each store has independent payout, tool and Bonzi fields. Maximum money is `9,000,000,000,000,000`; calculations and save validation enforce that bound.

Store 1's main upgrade is the brush. From Store 2 onward, the main upgrade is the **hose**, with the **squeegee** as an independent purchase below it in portrait or beside it in the short landscape drawer. Four purchases take each wet tool from displayed Lv 1 to Lv 5; saved levels run from 0 to 4. `buy_tool_upgrade()` deliberately routes to `buy_hose_upgrade()` in wet stores.

Hose and squeegee strength steps are `[1.0, 1.2, 1.45, 1.75, 2.1]`. Wet stores have base multipliers `1`, `2.1` and `4.41` for Stores 2, 3 and 4. Effective strength is the strongest applicable owned upgrade, calculated separately for each tool. It does not decrease when revisiting an earlier store. Maximum current wet strength is 9.261; the mask painter has a finite safety ceiling of 16.

The effective hose shape level is the highest owned hose level. Its profile changes the visible column, impact radius, actual wetting radius, passive spread radius and spread rate together. Paid direct-flow strength is normalized in `workshop._configure_hose_upgrade()` so the profile multiplier and ledger strength are not counted twice. Gym deliberately previews the profile's own direct-flow ladder.

Dry-tool width, strength and models come from `TOOL_WIDTHS`, `TOOL_POWERS` and [tool_progression_visual.gd](../CarpetToy/scripts/tool_progression_visual.gd). The code retains legacy Store 2 brush tiers and their assets for existing owners. New Store 2 hose purchases do **not** increase the old brush field. Do not remove that compatibility data simply because the current Store 2 UI no longer sells brushes.

Purchasing a payout upgrade during a job updates the unpaid quote for that rug without replacing its identity or resetting progress. Buying a tool during a job applies it immediately.

## 5. Store unlock requirements and the third-shop fix

Travel checks belong to `shop_state.progression_view()` and `open_next_store()`. The Stores sheet summarizes the named tool, paid-job count, local Bonzi earnings and opening coins in two compact lines. Completed displayed counters stop at their target; incomplete counters remain exact, so 15,999 coins cannot round up to a 16,000-coin requirement. The full balances and qualification explanation remain in tooltips, using `travel_requirements` and `travel_blockers` from the ledger.

| Unlock | Required main tool in current store | Qualifying paid rugs | Bonzi coins earned in current store | Coins spent to open |
| --- | --- | --- | --- | --- |
| Store 1 → Store 2 | Brush: 4 upgrades | 3 | 100 | 2,000 |
| Store 2 → Store 3 | Hose: 4 upgrades / displayed Lv 5 | 3 | 800 | 16,000 |
| Store 3 → Store 4 | Hose: 4 upgrades / displayed Lv 5 | 3 | 6,400 | 128,000 |

The last store has no next-store purchase. Payout level is **not** currently a travel requirement, despite the compatibility `TRAVEL_LEVEL_TARGET` constant and `payout_level_target` view field remaining in the code. Maximum squeegee level is also not a travel requirement.

### What counts as one qualifying rug

1. It must be a paid job in the store whose checklist is being completed.
2. Its required main tool must be at saved level 4 when used.
3. That tool must actually change the rug: a brush reduces surface dust or pushes an uncredited clump off the carpet, or a hose contact increases the wet mask. Delayed clump clearance is also detected.
4. The job must then finish for a valid payout. Either the 75% or 99% payout qualifies.

Owning the tool, moving it off the rug, using the wrong tool, or practicing in Gym does not qualify. Holding a hose still **does** qualify if its direct or passive contact wets the carpet. Upgrading to the maximum during a job also qualifies if the upgraded tool is then used before finishing. If the water stage was already complete before the upgrade, use the hose on the next rug.

`note_current_tool_used(tool_index)` records real use. `_record_completed_job()` increases `final_tool_jobs`, capped at 3, when that used job is paid. The old field name `job_started_with_final_tool` remains for save compatibility, but it is no longer a rule requiring the upgrade before the rug began.

The previous Store 3 gate still checked Store 2's brush field even though wet tools had separate upgrades. It also missed stationary hose usage and excluded jobs upgraded midway. Current checks use `_travel_tool_level()`, which selects the hose in wet stores, and actual contact notifications from `workshop._apply_hose_water()`.

Existing Store 2 brush investment is credited toward the hose level by taking the greater of the saved hose and legacy brush levels. Existing qualifying counts and paid purchases are retained. This is a compatibility migration, not a free unlock of every store.

If a store remains locked, inspect its checklist while visiting the immediately preceding store. When visiting an older owned shop, Stores provides a **View** action that visits the relevant shop and displays its checklist; it does not buy the locked shop. Bonzi earnings are local cumulative earnings, not total wallet income. The opening price is separate: earning 800 Bonzi coins in Store 2 does not replace the 16,000-coin opening price. An already-owned store should be entered with **Visit**, not bought again.

## 6. Bonzi, live production and offline earnings

Bonzi earns automatically in every owned store, including stores the player is not currently visiting. Store 1 begins without Bonzi; three local manual jobs unlock the purchase. New later stores include the starter Bonzi.

| Bonzi state | Purchase to reach it | Payment per cycle | Cycle length |
| --- | --- | --- | --- |
| Starter | `100 * S` from unowned; included in new later stores | `10 * S` | 120 seconds |
| Second tier | `300 * S` | `20 * S` | 90 seconds |
| Third tier | `900 * S` | `40 * S` | 60 seconds |

`_produce(seconds)` retains fractional cycle progress per store in `routine_remainder`. Whole deliveries increment wallet balance, local `bonzi_earned`, local automated jobs and the global automated-job count. If the wallet cannot hold the next payment, deliveries remain in `banked_orders` instead of disappearing.

Live time uses monotonic ticks. Cold-launch and application-resume absence uses wall-clock time, clamped to 8 hours. Negative clock movement does not award negative time or reset the saved wall-clock high-water mark. `_load_state()` credits and commits offline earnings immediately so reopening cannot collect the same interval again. `_resume_application()` uses the same bounded absence logic when device sleep interrupts live ticking.

Delivery payments are saved immediately; partial-cycle state is checkpointed periodically, currently every five seconds. Failed saves restore the previous production state. The Home return notice reports earnings already credited; acknowledging it clears the notice, not a second payout.

Old version-1 absence is settled at its original automation rate before migration changes future rates. The legacy blueprint and build APIs remain compatibility interfaces; they are not the authority for current store pricing.

## 7. Job lifecycle, rewards and persistence

### Paid-job sequence

1. `start_job()` resumes the branch's active job or assigns a new unique job ID and payout quote.
2. `workshop._ready()` configures the store recipe, restores its snapshot and starts rug arrival.
3. Cleaning modifies the existing soil/mask state. A one-shot timer batches snapshot saves; releasing a stroke and leaving also save progress.
4. `finish_rug()` checks readiness, reserves the cosmetic coin display and asks `complete_and_start_next_job()` to pay the rug and reserve its replacement in one transaction.
5. Only after that transaction succeeds does the completed rug vacuum/roll away and the next rug arrive.
6. The next rug reuses the existing scene, meshes and dirt pool; it is not a fresh scene load.

A second tap with the old job ID cannot pay again. A process restart during the departure animation opens the already-reserved replacement. If the transaction fails, the current rug remains available and the UI can retry; it does not animate away an unpaid job. [rug_roll.gd](../CarpetToy/scripts/rug_roll.gd) and the vertex deformation in [soil_surface.gdshader](../CarpetToy/scripts/soil_surface.gdshader) implement the roll.

Coins flying into the HUD are visual feedback only. `cleaning_hud.gd` uses a fixed pool of 24 coin sprites and tracks reserved/queued display amounts. The ledger has already credited the real wallet before coin arrival. Animation must never directly grant currency.

### Save layout

The ledger writes version **2** JSON to `user://neighborhood_shop_v1.json`. The filename retains `v1` for continuity; that suffix is not the current schema version. On normal Windows Godot installations, `user://` is under the application's Godot `app_userdata` directory. Use Godot's resolved user-data directory when locating it instead of guessing from a different project's name.

Global fields include cash, active store, job serial, aggregate manual/automated counts, legacy ownership/blueprints, offline-return data, completed reward records and ad receipts. `stores` maps string IDs `"1"` through `"4"` to branches. Each branch contains:

- `payout_level`, `tool_level`, `hose_level`, `squeegee_level`, `bonzi_tier`.
- `bonzi_earned`, `manual_jobs`, `automated_jobs`, `routine_remainder`, `banked_orders`, `final_tool_jobs`.
- `active_job_id`, `job_snapshot`, `job_early_reward`, `job_started_with_final_tool`, `job_final_tool_used`.

Purchases, store switches and rewards capture state before mutation. `_commit()` writes a temporary JSON file, flushes it, then renames it over the ledger. `_finish_transaction()` restores the captured state if the commit fails. Unreadable or unsupported saves are preserved and further saving is disabled rather than overwriting them with defaults. A player-requested reset is a separate, confirmed operation in Home settings.

`_restore_state()` migrates old saves. Missing wet-tool fields in old later-store wash-kit purchases are seeded from their paid legacy tier. Store 2's old brush level contributes to its hose credit. Saved Store 2 rugs are normalized to the two-stage recipe when loaded by the workshop; only obsolete dry work is removed, not saved water/extraction.

### Rug snapshots

`dirt_controller.make_snapshot()` produces a version-1 **rug snapshot**, independent of the outer version-2 ledger. It contains clump positions, velocities, growth, clearing/credit state, original scatter positions, recipe flags and base64 byte masks for coverage and, when applicable, water and extracted water. Masks are quantized to 8-bit values for storage. `restore_snapshot()` validates lengths, finite values and `extracted <= water` before rebuilding the state.

Paired fields `recycled` and `debris_age` preserve free slots and partially faded floor debris. The `debris_policy: 2` marker, ordered `floor_debris` indices and bounded `pending_emissions` preserve demand-driven reclamation. Validation rejects impossible free/fading states, invalid indices and malformed requests before modifying live progress. Old elapsed-time ages are discarded so old saves adopt indefinite retention; original positions and progress remain. For snapshots also missing scatter baselines, untouched uncredited sources recover their anchor from their saved position. Only already-requested fades and emissions continue after resume.

Do not change the mask dimensions, pool size or snapshot fields without considering migration. Cosmetic splashes, trails, emitted parcels and runoff are not saved. On re-entry they restart; the authoritative carpet state persists.

### Test-save isolation

Always append `-- --shop-test` for gameplay validation. `ShopState` then uses `res://.godot/shop_test_<process id>.json`, and test clock overrides are permitted only in this mode. Gym exercises do not pay rewards, spend upgrade coins or replace a paid snapshot. The shared autoload's normal Bonzi automation can still run while the player is in Gym.

## 8. Cleaning simulation and rendering

### Authoritative carpet state

`dirt_controller.gd` owns the cleaning arrays. Rendering reads these arrays; a splash does not itself clean or re-wet the rug.

| State | Meaning |
| --- | --- |
| `coverage_values` | Remaining dry surface dirt per pixel |
| `water_values` | Amount deposited per pixel, limited by loosened/cleaned surface |
| `extraction_values` | Amount removed per pixel, never greater than deposited water |
| Visible wetness | `clamp(water_values - extraction_values, 0, 1)` |
| `surface_pixels` | Which mask pixels are actual carpet surface |
| Clump arrays and `credited` | Finite debris simulation and one-time progress credit |

The mask is 256 × 416. [rug_footprint.gd](../CarpetToy/scripts/rug_footprint.gd) defines the rounded body and 26 tassels. This shared footprint controls mask eligibility, dirt leaving the rug, hose contact and visual clipping. Changing rug geometry requires updating this footprint and the coordinate assumptions together.

The production dirt batch contains 560 pooled clumps, drawn as a `MultiMesh`. Brushing checks a swept head between input positions so fast input does not skip clumps. Surface cleaning is pass-based: each pixel takes the strongest coverage in a pass, rather than gaining extra cleaning merely because the input delivered more events. A meaningful reversal starts another pass. Removal is weighted by rug grain efficiency and tool strength.

Debris uses bounded velocities, gravity, friction and an active list. All original dirt is brushable immediately, with 25 visible starter seeds. Fixed source positions also sample actual surface removal once per pass; when their own clump is already out, they can borrow any available slot. Visual identity and extraction location can therefore differ while each slot's progress credit stays permanent. Reversals require at least 0.22 rug units or twice the head's half-depth, whichever is larger.

Landing fully outside earns a slot's one-time progress credit. Settled floor debris stays indefinitely. New dirty extraction demand that draws down the 64-slot reserve starts 0.6-second shrink animations on the oldest eligible settled, credited floor clumps. Free and currently fading slots together replenish the reserve; up to 64 pending requests bridge an exhausted pool. Completed fades return slots to supply and serve existing requests without awarding further credit. Clean strokes and idle time create no new demand. Rebrushing cancels reclamation; existing pending requests can request replacement supply after the clump settles again. Pause freezes work, vacuum starts from current visible sizes, and water-only recipes clear the dry queues. Settled retained debris requires no physics processing. See [implementation and validation](Brush_Dirt_Layers.md).

`soil_surface.gdshader` combines the rug texture, tint, coverage and wetness. Wetness darkens the carpet and adjusts roughness/specular response. It also contains the roll deformation, so UVs remain associated with the undeformed rug during transitions.

### Hose water

`water_jet.gd` is a bounded procedural tube, not a skeleton or a fluid solver. It allocates one mesh with 16 axial rings and 10 radial sides, plus caps. A 96-entry emission history sampled at 1/120-second intervals records the nozzle positions and velocities. Samples advance approximately as `p(age) = origin + velocity * age + 0.5 * gravity * age^2`. Previously emitted water therefore follows its own flight instead of instantly rotating with the nozzle.

Current constants include exit speed 2.4, gravity `(0, -9.8, 0)`, a maximum flight time of 0.65 seconds and direct deposit interval 0.05 seconds. Contacts distinguish the carpet surface from the floor. Only valid carpet contacts emit gameplay wetting events. `workshop._on_water_contact()` passes those into the mask; pointer movement itself does not paint hose water.

The stream broadens along its length, beginning at normalized distance 0.18 and reaching its full widening at 0.88. [water_jet.gdshader](../CarpetToy/scripts/water_jet.gdshader) adds small moving silhouette ripples and painted highlights. This is opaque stylized water, not transparent refractive water.

The hose profile is the main tuning table:

| Saved level / displayed level | Wet radius | Maximum passive radius | Passive strength multiplier | Spread speed |
| --- | --- | --- | --- | --- |
| 0 / Lv 1 | 0.26 | 0.70 | 1.00 | 0.55 |
| 1 / Lv 2 | 0.30 | 0.82 | 1.35 | 0.69 |
| 2 / Lv 3 | 0.35 | 0.94 | 1.80 | 0.84 |
| 3 / Lv 4 | 0.40 | 1.07 | 2.35 | 1.01 |
| 4 / Lv 5 | 0.46 | 1.20 | 3.00 | 1.20 |

`water_soak.gd` maintains at most six stationary soaking reservoirs. Their radius approaches the profile maximum as `lerp(wet_radius, max_radius, 1 - exp(-spread_speed * fed_duration))`. Passive deposits occur every 0.10 seconds. Strength ramps in over 0.30 seconds, gains up to a 1.35 hold boost by 1.50 seconds and fades out over 0.70 seconds after feeding stops. Thus keeping the hose in one place increases coverage and absorption, while leaving a finite after-soak rather than a permanent emitter.

### Squeegee direction and extraction

`squeegee_motion.gd` filters planar movement intent. It ignores tiny jitter, retains the last heading at rest, uses a 0.070-second response, caps turn speed at 14 radians/second and caps interpreted speed at 2.5 world units/second. The same heading controls the model, rotated extraction footprint and splash orientation.

`dirt_controller.apply_squeegee_stroke()` paints the swept, rotated rectangular blade, including intermediate rotation samples. Extraction is time/strength weighted and capped by actual water. The base extraction-rate constant is 7.4. `workshop.apply_selected_tool_stroke()` measures the resulting positive extraction delta and uses it to supply VFX. Passing over dry or already-extracted pixels supplies no new splash water.

### Blade splash, path ridges and runoff

The current squeegee effect has **no forward airborne column, cuboid sheet or distant landing point**. It consists of three visual-only parts:

1. **Blade perimeter:** `squeegee_water.gd` uses the shared [water_jet_impact.gd](../CarpetToy/scripts/water_jet_impact.gd) in rectangular mode. Water curls outward on all four sides. The hose uses the same effect in circular mode around its impact.
2. **Cleared-path boundary:** `squeegee_water_trail.gd` reads the extraction arrays and builds a union contour around the cleared region. It does not add a separate ridge for every historical stroke. A 65 × 105 sampling grid and at most 2,048 strip instances bound its cost. Rebuilds are limited to one per 0.10 seconds while changed. Ridges linger for 8 seconds and fade over 2 seconds after fresh supply stops.
3. **Water leaving the rug:** positive local extraction near the perimeter supplies grouped edge mouths and `squeegee_runoff_streams.gd`. Up to four mouths feed a pool of 16 broad ribbons. Ribbons move outward at 5.2 world units/second, travel up to 12.6 units, start fading at 1.65 seconds and expire at 2.50 seconds. Sources stop after a short grace period; old extraction or unrelated movement cannot keep them alive indefinitely.

The shared perimeter splash allocates one 128-segment, 9-row open-center strip and 24 pooled droplets. It clips against the carpet silhouette and supports rug/floor heights. Its animated crest shapes are in [water_jet_impact.gdshader](../CarpetToy/scripts/water_jet_impact.gdshader).

Runoff geometry is world-anchored after emission. It does not follow the moving tool and does not leave a permanent pattern outside the rug. Its shader uses opaque matte colors, moving broad bands, rounded ends and a floor-color fade rather than a growing transparent-particle field. The runoff renderer has deliberately expanded bounds because streams travel well outside the carpet.

All three are presentation. The game removes water through the extraction mask; it does not simulate a conserved volume of liquid being transported across neighboring pixels. Do not use visible ridge height or runoff size as the authoritative progress value.

Changing tool, resetting/replacing a rug, leaving the scene, opening upgrades or losing application focus cancels stale emitters. Release lets the appropriate short-lived visual tails finish. Pool allocation occurs during setup, not for each swipe.

## 9. Input, cameras and UI layout

Mouse and touch share the same world-space cleaning implementation. `workshop.move_brush_to_screen()` projects a camera ray onto the rug plane and clamps tool reach. Touch applies a `(0, -72)` screen-space contact offset so the finger does not cover the tool. Initial placement is not a sweep from the tool's parked position.

Touch-to-mouse emulation is disabled in `project.godot`. The scripts explicitly route touch: a gesture belongs to either the HUD or the rug; dragging off a button cancels the tap. A second finger cancels cleaning and prevents the gesture from becoming a stray purchase. Focus loss, Back, modals and scene departure terminate active strokes.

Production cleaning currently uses the overhead orthographic view. Its framing reserves the Finish/payout band before Finish appears, so reaching 75% does not change the zoom. The **Gym** has the top/angled camera toggle. [gym_camera.gd](../CarpetToy/scripts/gym_camera.gd) fits either orthographic camera into the same HUD-safe region; both use the same ray-based input, not separate control mappings.

HUD layouts account for safe insets, portrait/landscape space and mobile orientation changes. Runtime `_layout()` methods in the HUD scripts still position authored controls, so changing a scene offset alone may not change the final runtime layout. Use [Editing_UI_in_Godot.md](Editing_UI_in_Godot.md) for the editor workflow.

The cleaning upgrade drawer pauses cleaning and transitions, blocks background input and restores focus when closed. Store 1 shows the brush upgrade. Wet stores show the hose as the main comparison without a duplicate hose row; the squeegee upgrade is below it in portrait and in the adjacent column in landscape. Management Stores puts its unlock checklist first in the scroll area, followed by the store rows and opening purchase. Opening has a confirmation panel.

## 10. Gym behavior

The Gym scene inherits the production cleaning scene and replaces its HUD in `gym._ready()`. It uses the same masks, hose, squeegee motion and VFX implementations, so tests there exercise shared behavior rather than a separate visual mockup.

- Rug 1 is the brush exercise.
- Rug 2 starts after dry cleaning and practices water followed by extraction. Its visible meter reports the current wet stage, unlike the paid overall-recipe meter.
- Pressing **Hose** on Rug 2 resets it to clean and dry, even if the hose was already selected.
- Pressing **Squeegee** resets and fully wets Rug 2 so extraction can be tested immediately.
- Hose and squeegee level controls are free previews, not paid upgrades. They do not reset rug progress merely because the preview level changes.
- Camera selection and upgrade previews are retained across practice resets as implemented by Gym; practice does not reserve replacement paid jobs.

These explicit button shortcuts are intentionally separate from internal tool selection. Automatically advancing from hose to squeegee must not refill the rug or erase the player's progress.

## 11. Scene and asset authoring

Edit live scenes in [CarpetToy/scenes](../CarpetToy/scenes). Production scenes are in `production`; reusable HUDs in `ui`; the reusable squeegee effect is [effects/squeegee_water.tscn](../CarpetToy/scenes/effects/squeegee_water.tscn). Test scenes include the Gym, carpet studio and VFX preview. A scene being under `test` does not necessarily mean it is unreachable from the game: Gym is a supported navigation destination.

The production cleaning scene contains `RugDisplay`, `Dirty/SoilClumps`, carpet meshes, `StarterTools/LargeBrush`, `StarterTools/Squeegee`, `StarterTools/JetSpray`, camera, floor and authored UI. `workshop._ensure_wet_runtime()` creates/reuses the shared water runtime and nozzle socket when a wet recipe needs them. The squeegee model's authored correction and its runtime yaw serve different purposes; do not reverse extraction direction to compensate for a mesh orientation problem.

Source and imported assets are separated:

- [art/blender](../art/blender): Blender source files for carpet, tools and floating shop.
- [CarpetToy/assets/carpet](../CarpetToy/assets/carpet): imported carpet model and textures.
- [CarpetToy/assets/tools](../CarpetToy/assets/tools): brush, squeegee, hose and progression models.
- [CarpetToy/assets/dirt](../CarpetToy/assets/dirt): soil mesh, textures and materials.
- [CarpetToy/assets/floating_shop](../CarpetToy/assets/floating_shop): home models and UI artwork.
- [CarpetToy/assets/ui](../CarpetToy/assets/ui), [CarpetToy/scenes/ui/art](../CarpetToy/scenes/ui/art), [mint_theme.tres](../CarpetToy/resources/ui/mint_theme.tres): icons, editable illustration scenes and theme.
- [art/renders](../art/renders): generated review captures, not the gameplay source of truth.

Scripts such as [build_carpet.py](../tools/build_carpet.py), [build_tools.py](../tools/build_tools.py), [build_progression_tools.py](../tools/build_progression_tools.py), [build_floating_shop.py](../tools/build_floating_shop.py) and the `assemble_*.gd` tools are authoring/generation utilities. Do not run them as part of an ordinary UI edit: they may recreate assets or scenes and overwrite editor work. Inspect their outputs and intended scope before regeneration. Godot's `.godot` directory is generated cache/test data, not authored source.

## 12. Engine, running and Android builds

The required engine is **Godot 4.7.2 stable Mono/.NET**. Gameplay is GDScript; this engine requirement does not imply a C# rewrite. The compatibility feature string in `project.godot` is not the launcher version check.

Use [Open Game Editor.cmd](../Open%20Game%20Editor.cmd) to open the editor and [Build APK.cmd](../Build%20APK.cmd) to export Android. Both use [godot_toolchain.ps1](../tools/godot_toolchain.ps1), which checks the exact version, required `GodotSharp` files, and a .NET 8-or-newer SDK. It refuses fallback engines from PATH. Matching `4.7.2.stable.mono` export templates are required.

From the repository root, an isolated model check can be run as:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_store_unlock.gd -- --shop-test
```

For rendering/input validators, omit `--headless` when they require a visible renderer. Run GUI validators sequentially: another window taking focus can legitimately cancel the stroke being tested. Always keep `-- --shop-test`.

[build_android.ps1](../tools/build_android.ps1) validates configured Android SDK/JDK files and matching templates, exports a debug APK to staging, verifies its signature independently and replaces [build/CarpetCleaner.apk](../build/CarpetCleaner.apk) only after success. It records launcher, engine and signature logs in `build`. It does not install or launch the APK on a device. `-CheckOnly` checks build prerequisites without exporting. See [Android_APK.md](Android_APK.md) for environment details and troubleshooting.

The renderer is GL Compatibility. Fixed pools, shared meshes, mask textures and disabled idle processing limit allocation and draw overhead. These implementation choices are not a substitute for Android device profiling.

The [September 27 performance pass](Mobile_Performance.md) adds exact full-wet footprint buffers, reusable squeegee sweep arrays and cached ridge sampling. It also avoids full upgrade-view refreshes on mask-only changes and cancels duplicate successful save checkpoints. The report includes before/after measurements, equivalence tests and remaining phone checks.

## 13. Validation map and current limits

The scripts below are regression entry points, not claims that every script was rerun when this document was written. Inspect assertion failures and engine logs, not only the process exit code or a final `VERIFIED` label.

| Concern | Validators in `tools/` |
| --- | --- |
| Economy and progression | [validate_progression.gd](../tools/validate_progression.gd), [validate_wet_upgrades.gd](../tools/validate_wet_upgrades.gd), [validate_store_unlock.gd](../tools/validate_store_unlock.gd) |
| Store recipes and transitions | [validate_second_store_wet.gd](../tools/validate_second_store_wet.gd), [validate_store_loop.gd](../tools/validate_store_loop.gd), [validate_contract.gd](../tools/validate_contract.gd), [validate_rug_transition.gd](../tools/validate_rug_transition.gd) |
| Saves, automation and rewards | [validate_shop_state.gd](../tools/validate_shop_state.gd), [validate_automation_reset.gd](../tools/validate_automation_reset.gd), [validate_coin_rewards.gd](../tools/validate_coin_rewards.gd) |
| Layout, navigation and touch | [validate_wet_upgrade_ui.gd](../tools/validate_wet_upgrade_ui.gd), [validate_editable_hud.gd](../tools/validate_editable_hud.gd), [validate_shop_ui.gd](../tools/validate_shop_ui.gd), [validate_scene_routes.gd](../tools/validate_scene_routes.gd), [validate_home_settings.gd](../tools/validate_home_settings.gd), [validate_brush_input.gd](../tools/validate_brush_input.gd) |
| Dirt and cleaning masks | [validate_cleaning.gd](../tools/validate_cleaning.gd), [validate_brush_recycling.gd](../tools/validate_brush_recycling.gd), [validate_dirt_pool.gd](../tools/validate_dirt_pool.gd), [validate_dirt_reentry.gd](../tools/validate_dirt_reentry.gd), [validate_wet_cleaning.gd](../tools/validate_wet_cleaning.gd), [validate_rotated_squeegee.gd](../tools/validate_rotated_squeegee.gd) |
| Gym, hose and squeegee | [validate_gym.gd](../tools/validate_gym.gd), [validate_hose_upgrades.gd](../tools/validate_hose_upgrades.gd), [validate_water_jet.gd](../tools/validate_water_jet.gd), [validate_squeegee_controls.gd](../tools/validate_squeegee_controls.gd) |
| Ridges and runoff | [validate_squeegee_trail.gd](../tools/validate_squeegee_trail.gd), [validate_squeegee_runoff.gd](../tools/validate_squeegee_runoff.gd), [validate_runoff_pool.gd](../tools/validate_runoff_pool.gd), [validate_long_runoff.gd](../tools/validate_long_runoff.gd) |

Known limits and distinctions:

- The earlier validation baseline has 12 failures in `validate_shop_state.gd` tied to old Bonzi economy expectations. Do not describe the whole repository suite as green until that legacy suite is reconciled with the current progression rules.
- [reward_ad_service.gd](../CarpetToy/scripts/reward_ad_service.gd) is a provider adapter, not an installed advertising SDK. No configured provider means no ad availability or reward. A provider must support availability, request and receipt verification; the ledger prevents duplicate job rewards/receipt reuse.
- A successful desktop validation or APK signature check does not establish frame rate, thermal behavior, touch feel or lifecycle correctness on every Android device. Device profiling and playtesting remain necessary.
- VFX timing and color are stylized. There is no general fluid solver, mass-conserving water transport or persistent off-carpet puddle simulation.
- Historical `water_blobs` and older `squeegee_water_*` implementations/tests may remain in the repository. The active runtime follows the references in `workshop._ensure_wet_runtime()` and `squeegee_water.setup()`; a similarly named old file is not necessarily active.

## 14. Where to make common changes

| Desired change | Edit or inspect |
| --- | --- |
| Finish percentage or perfect threshold | `shop_state.gd`: `MANUAL_COMPLETION_THRESHOLD`, `PERFECT_COMPLETION_THRESHOLD`; verify workshop and ledger tests together |
| Store 2 stage requirements | `workshop.gd`: recipe setup/restore; `dirt_controller.gd`: `set_recipe()`, `recommended_tool()`, `overall_clearance()`; `shop_state.gd`: `_job_clearance()` |
| Store unlock requirements | `shop_state.gd`: `progression_view()`, `_travel_tool_level()`, `note_current_tool_used()`, `open_next_store()`; `progression.gd`: `CAPSTONE_JOBS` |
| Explain lock requirements in UI | `compact_shop.gd`: `refresh()` Stores branch; `compact_shop.tscn`: `TravelGoals` |
| Job payout, upgrade costs, Bonzi rates | `progression.gd`; ledger transaction tests must still pass |
| Preserve or migrate paid upgrades | `shop_state.gd`: `_restore_state()`, `_valid_progression_save()`; avoid ad hoc writes to the player's JSON |
| Hose width, passive spread and level scaling | `water_hose_profile.gd`: arrays and `for_level()`; `water_soak.gd`: radius/strength functions |
| Hose middle width or flight shape | `water_jet.gd`: widening constants, flight/history sampling; `water_jet.gdshader`: silhouette modulation |
| Squeegee responsiveness | `squeegee_motion.gd`: response, turn/speed limits; `workshop.gd`: `place_selected_tool()` |
| Actual extraction rate/footprint | `dirt_controller.gd`: `EXTRACTION_RATE`, `SQUEEGEE_HALF`, `apply_squeegee_stroke()` |
| Four-sided blade splash shape | `squeegee_water.gd`: exported reach/height; `water_jet_impact.gd` and its shader |
| Ridge duration, density or height | `squeegee_water_trail.gd`: grid, capacity, rebuild/linger/fade constants; shared impact shader |
| Runoff speed, length or fade | `squeegee_runoff_streams.gd`: `SPEED`, `MAX_DISTANCE`, `LIFETIME`, `FADE_START`; corresponding shader |
| Dirt removal per pass or directional grain | `resources/rugs/*.tres`, `rug_definition.stroke_efficiency()`, `dirt_controller.paint_stroke()` |
| Carpet shape/fringe | Carpet source mesh and `rug_footprint.gd`, plus mask/world-size assumptions in soil and VFX |
| Touch offset and reach | `workshop.gd`: `TOUCH_CONTACT_OFFSET`, limits, `move_brush_to_screen()` |
| Gym camera | `gym.gd`: `set_camera_angle()`; `gym_camera.gd`: `frame()` and fit bounds |
| Paid HUD positions or upgrade layout | `scenes/ui/cleaning_hud.tscn` and `cleaning_hud.gd`: `_layout()` |
| Gym wet/dry shortcut behavior | `gym.gd`: `_on_practice_tool_pressed()`; do not put resets in ordinary `select_tool()` |
| Main menu and settings | `floating_home.tscn`, `floating_home.gd`; management uses `compact_shop` |
| Engine or export selection | `tools/godot_toolchain.ps1`, launchers and `tools/build_android.ps1`; preserve the strict Mono version requirement |

## 15. Other documentation

[Implementation_Coverage.md](Implementation_Coverage.md) tracks feature coverage and validation. [Store_Progression_v0_3_Draft.md](Store_Progression_v0_3_Draft.md) provides economy context, despite its historical filename. [Scene_Navigation.md](Scene_Navigation.md), [Water_Jet.md](Water_Jet.md) and [Squeegee_Water_VFX.md](Squeegee_Water_VFX.md) cover narrower systems. [home-screen/IMPLEMENTATION.md](home-screen/IMPLEMENTATION.md) and [Editing_UI_in_Godot.md](Editing_UI_in_Godot.md) describe authored UI work.

[Metagame_v0_2.md](Metagame_v0_2.md) and [Water_Blobs.md](Water_Blobs.md) describe earlier designs. Where older prose mentions an 85% finish threshold, a three-stage Store 2, brush-based Store 2 travel, or a forward squeegee water column, that is not the current behavior. Resolve disagreements against the active scene references and code documented above.
