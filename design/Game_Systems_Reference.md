# Current game systems reference

Updated: 9 October 2026. This document describes the implemented project, including six brush stores in one section, bounded room earnings, authored visual milestones and save migration. It is a code reference, not a list of proposed features. Paths are relative to this document; `res://` in Godot refers to the `CarpetToy` directory.

Section 1 has six stores with five independent accessory ladders per store. Fully upgraded carpet rewards grow from 400,000 in the first store to 400 AF in the sixth. Real makeovers are spread across each store's upgrade cap; extra income levels retain the final authored mesh. See [First_Shop_Balance.md](First_Shop_Balance.md) and [Room_Upgrades.md](Room_Upgrades.md) for current curves and pacing. The production catalog has 24 rugs; water and extraction remain available in Gym and in code for future sections.

## 1. Start here

The game has one playable section of six stores, a shared wallet, paid brush jobs, independent store upgrades, Bonzi automation, and a free Gym. The main scene is production cleaning: app launch or F5 opens or resumes the last selected store's carpet. Back opens the floating shop for store browsing and management. Section completion is tracked, but no second section can be entered until one is authored.

| Area | Main files | Responsibility |
| --- | --- | --- |
| Project startup | [project.godot](../CarpetToy/project.godot), [scene_routes.gd](../CarpetToy/scripts/scene_routes.gd) | Main scene, autoload, renderer, shared navigation destinations |
| Persistent game state | [shop_state.gd](../CarpetToy/scripts/shop_state.gd) | Wallet, stores, jobs, purchases, automation, save/load and reward validation |
| Economy rules | [progression.gd](../CarpetToy/scripts/progression.gd), [room_upgrades.gd](../CarpetToy/scripts/room_upgrades.gd) | Sections, store caps, accessory curves, visual milestones, tool strengths and Bonzi cycles |
| Home | [floating_home.tscn](../CarpetToy/scenes/production/floating_home.tscn), [floating_home.gd](../CarpetToy/scripts/floating_home.gd) | Store preview, paid-job entry, management sheets, Gym entry and settings |
| Paid cleaning | [rug_cleaning.tscn](../CarpetToy/scenes/production/rug_cleaning.tscn), [workshop.gd](../CarpetToy/scripts/workshop.gd) | Input, tool selection, recipe setup, job progress, transitions and VFX integration |
| Carpet state | [dirt_controller.gd](../CarpetToy/scripts/dirt_controller.gd) | Dirt simulation, coverage/water/extraction masks, progress and rug snapshots |
| Cleaning UI | [cleaning_hud.tscn](../CarpetToy/scenes/ui/cleaning_hud.tscn), [cleaning_hud.gd](../CarpetToy/scripts/cleaning_hud.gd), [room_upgrade_panel.gd](../CarpetToy/scripts/room_upgrade_panel.gd) | Wallet display, progress, Finish, floating accessory offers, tool drawer and coin animation |
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

`project.godot` starts `scenes/production/rug_cleaning.tscn`. The workshop reads the saved `active_store` and creates or resumes that branch's paid job and rug snapshot. Opening Gym sets `practice_only = true`; Gym never converts an exercise into a commission.

## 3. Stores, recipes and completion

### Required stages

All six stores in Section 1 require brushing. Their names are Neighborhood, High Street, Wash House, Restoration Studio, Grand Arcade and Royal Gallery. Completion is `dry = min(unique_clearance, surface_clearance)`, so removing visible clumps alone does not finish a carpet while surface dust remains.

All fractions are between 0 and 1. `WET_FIRST_STORE = 7` reserves water mechanics for future sections; `SECTION_COUNT = 1` prevents access to them today. Gym still supports water and extraction practice. The shared wet recipe code measures real carpet pixels, gates each preceding stage at 99%, and supports three washing/extraction rounds. Its first future wet store skips dry brushing; later wet recipes include it.

`dirt_controller.recommended_tool()` coordinates recipe stages; internal indices are Brush `0`, Squeegee `1`, Hose `2`. The retained wet runtime stops hose deposition at stage completion and handles airborne contacts after release. It does not add a water stage to any current paid store.

### Finish and rewards

At 75% overall completion, the player may press Finish for the normal payout. At 99%, the job automatically finishes for twice that amount. These are overall recipe percentages, not percentages of the currently selected stage.

For current paid jobs, both dry measures must reach 75% for an early finish or 99% for the full reward.

`workshop.update_contract_status()` drives the progress meter, Finish availability and automatic finish from the same overall value. `shop_state.reward_for_current_job()` independently validates the snapshot and recomputes the recipe total; it does not trust a submitted `overall_clearance` field. The ledger rejects nonfinite/out-of-range values and later-stage progress before the preceding stage is complete. A very small numeric tolerance handles floating-point threshold arithmetic.

Each floating accessory offer shows the full carpet reward's current-to-next amount, the next purchase price, and progress toward the next authored makeover. Early finish still pays half that full amount.

### Rug appearance is separate from the recipe

[rug_definition.gd](../CarpetToy/scripts/rug_definition.gd) defines appearance and brush behavior: name, hint, tint, dust strength, removal per pass, grain direction and cross-grain efficiency. Resources are in [resources/rugs](../CarpetToy/resources/rugs):

- `mint_meadow.tres`: ten full passes with the starter brush, removing 10% of surface dust each time; dark soil at 0.94 strength. `gym_brush.tres` uses the same removal rate and opacity.
- `terracotta_flatweave.tres`: light dust, one pass.
- `indigo_weave.tres`: three passes; lengthwise brushing is more effective.
- `gym_brush.tres` and `gym_water.tres`: the two Gym exercises.

`rug_catalog.gd` provides 24 production designs, selected by the store's completed-job count. The reserved `active_rug_id` persists through reloads and purchases. Rug art is separate from the cleaning recipe; free workshop cycling and Gym selection remain separate behaviors.

## 4. Upgrade economy and tool carryover

`progression.gd` defines section size, store scales and reward/upgrade caps. `room_upgrades.gd` defines five independent accessory curves: floor, plants, window, railings and walls. For store `s`, `S = STORE_SCALES[s - 1]`; the former `8^(s - 1)` scale is retained only for legacy migration.

| Store | S | Levels per accessory | Maximum full carpet reward | Current authored makeovers |
| --- | --- | --- | --- | --- |
| 1 | `1` | 50 | 400,000 | 15, 30, 45 |
| 2 | `1e4` | 75 | 400 million | 25, 50, 75 |
| 3 | `1e7` | 100 | 4 trillion | 30, 60, 90 |
| 4 | `1e11` | 125 | `4e17` | 40, 80, 120 |
| 5 | `1e16` | 150 | `4e24` | 50, 100, 150 |
| 6 | `1e23` | 175 | 400 AF (`4e32`) | 50, 100, 150 |

Growth is solved separately for each store so maxing all five accessories reaches the exact full-reward cap. Authored makeover count comes from each accessory's definition. `visual_milestones_for()` divides the cap by that count, rounds the interval down to a multiple of five below 50 or ten at/above 50, and keeps intervals at least one. Thus 50 upgrades/five makeovers gives 10/20/30/40/50; 175/three gives 50/100/150. After the final mesh, any remaining purchases increase earnings and the offer reads **Makeovers complete**.

| Rule | Current value |
| --- | --- |
| Cleaning share | Base `20S` plus purchased accessory contributions, progressively earned during material removal; early Finish settles the unpaid remainder of this half |
| Restoration share | The same half quote, awarded only at 99% |
| Full carpet total | `2 * cleaning half quote`, bounded by the store reward cap |
| Next accessory price | Independent category base cost × store scale × solved store growth raised to its current level |
| Four incremental tool-upgrade prices | `round(3P * (R/P)^f)` at `f = 0, 1/3, 2/3, 1`, where `P=40S` and `R` is the store's full reward cap |
| Next-store opening price | `2000 * S`, based on the store being completed |
| Local Bonzi earnings required to open next store | `100 * S` |
| Qualifying paid jobs at the maximum main-tool level | 3 |

Prices are incremental. All purchases use one wallet. Each store has independent room, tool and Bonzi fields. Currency uses finite whole-valued float64 up to `1e60`; normal-sized coins remain exact, while large idle amounts use float64's relative precision. Shared `money.gd` labels K/M/B/T then AA onward, with AF=`1e30`. Integer job counters retain a separate 9-quadrillion cap. The generic `early_reward()`/`payout_cost()` formulas in `progression.gd` support legacy migration; accessory curves are authoritative.

Each current store sells four local brush upgrades, saved as levels 0–4. Global numerical stage is `(store_id - 1) * 4 + local_level`, up to 24. Nine authored brush models cover these stages through `dry_visual_tier()`; width reaches 1.75× and power continues growing by 12% per numerical stage after stage 8. The strongest owned brush remains available when revisiting earlier stores. Modern rule-4 reloads preserve the brush field independently of unused hose fields.

Gym and the future wet-store code retain independent hose/squeegee levels 0–4 with strength steps `[1.0, 1.2, 1.45, 1.75, 2.1]`. Current paid stores do not sell those upgrades. The shared mask painter has a finite strength ceiling of 16.

The effective hose shape level is the highest owned hose level. Its profile changes the visible column, impact radius, actual wetting radius, passive spread radius and spread rate together. Paid direct-flow strength is normalized in `workshop._configure_hose_upgrade()` so the profile multiplier and ledger strength are not counted twice. Gym deliberately previews the profile's own direct-flow ladder.

Dry-tool width, strength and models come from `TOOL_WIDTHS`, `TOOL_POWERS`, `dry_power()` and [tool_progression_visual.gd](../CarpetToy/scripts/tool_progression_visual.gd). Old wet purchases are credited to the corresponding brush track during rule-4 migration; their saved hose/squeegee fields are retained.

Purchasing a payout upgrade during a job updates the unpaid quote for that rug without replacing its identity or resetting progress. Buying a tool during a job applies it immediately.

## 5. Store and section completion

Travel checks belong to `shop_state.store_mastered()`, `progression_view()` and `open_next_store()`. Each store requires all five accessory ladders at its cap, all four brush upgrades, the final Bonzi tier, three paid rugs with real use of the max local brush, and `100S` local Bonzi earnings. Opening the next store also costs `2000S`. Stores displays these actual requirements; eligibility compares saved amounts.

| Unlock | Completed room levels | Required main tool | Final Bonzi tier | Qualifying paid rugs |
| --- | --- | --- | --- | --- |
| Store 1 → 2 | 250 | Four brush upgrades | Yes | 3 |
| Store 2 → 3 | 375 | Four brush upgrades | Yes | 3 |
| Store 3 → 4 | 500 | Four brush upgrades | Yes | 3 |
| Store 4 → 5 | 625 | Four brush upgrades | Yes | 3 |
| Store 5 → 6 | 750 | Four brush upgrades | Yes | 3 |

`section_progress()` counts mastered stores out of six. Mastering Store 6 completes Section 1; no seventh store or next-section purchase exists while `SECTION_COUNT = 1`. When more sections are authored, crossing a section boundary requires completion of all six preceding stores. Old owned stores remain owned after migration even when new mastery requirements are incomplete.

### What counts as one qualifying rug

1. It must be a paid job in the store whose checklist is being completed.
2. Its required main tool must be at saved level 4 when used.
3. The brush must actually reduce surface dust or push an uncredited clump off the carpet. Delayed clump clearance is also detected.
4. The job must then finish for a valid payout. Either the 75% or 99% payout qualifies.

Owning the tool, moving it off the rug, or practicing in Gym does not qualify. Upgrading to the maximum during a job qualifies if the upgraded brush is then used before finishing. The future wet path retains real hose-contact tracking for its own main-tool requirement.

`note_current_tool_used(tool_index)` records real use. `_record_completed_job()` increases `final_tool_jobs`, capped at 3, when that used job is paid. The old field name `job_started_with_final_tool` remains for save compatibility, but it is no longer a rule requiring the upgrade before the rug began.

If a store remains locked, inspect its checklist while visiting the immediately preceding store. When visiting an older owned shop, Stores provides a **View** action that visits the relevant shop and displays its checklist; it does not buy the locked shop. Bonzi earnings are local cumulative earnings, separate from opening coins. An already-owned store is entered with **Visit**.

## 6. Bonzi, live production and offline earnings

Bonzi earns automatically in every owned store, including stores the player is not currently visiting. Store 1 begins without Bonzi; three local manual jobs unlock the purchase. New later stores include the starter Bonzi.

| Bonzi state | Purchase to reach it | Payment per cycle | Cycle length |
| --- | --- | --- | --- |
| Starter | `4P` from unowned; included in new later stores | Current store's base full-clean reward | 120 seconds |
| Second tier | `round(4P * sqrt(R/P))` | Same base full-clean reward | 90 seconds |
| Third tier | `4R` | Same base full-clean reward | 60 seconds |

All owned tiers pay the same current full rug value as the player in that store. Bonzi upgrades only shorten the cycle. Floor, plant, window, railing and wall upgrades increase its full-clean quote and live/offline Bonzi payment together. An unupgraded store pays `40 * S` per order at every owned tier. After three local rugs, Home's unowned Bonzi caption becomes Hire Bonzi and explains the automatic/offline benefit at the current hire price; this hint never spends coins or opens a modal.

`shop_state.bonzi_reward_for_store(store_id)` is the authoritative delivery quote and returns zero for unowned Bonzi. `progression_view().bonzi_reward` supplies the owned bar's current payment. The purchase preview and faster-tier offer use `progression_view().full_reward`, so they show the same coins with the next cycle length, including before Bonzi is owned. `Progression.bot_reward(store_id, tier, full_clean_reward)` requires the complete reward quote as its third argument, so callers cannot silently omit room upgrades.

`_produce(seconds)` retains fractional cycle progress per store in `routine_remainder`. Whole deliveries increment wallet balance, local `bonzi_earned`, local automated jobs and the global automated-job count. If the wallet cannot hold the next payment, deliveries remain in `banked_orders` instead of disappearing.

Live time uses monotonic ticks. Cold-launch and application-resume absence uses wall-clock time, clamped to 8 hours. Negative clock movement does not award negative time or reset the saved wall-clock high-water mark. `_load_state()` credits and commits offline earnings immediately so reopening cannot collect the same interval again. `_resume_application()` uses the same bounded absence logic when device sleep interrupts live ticking.

Delivery payments are saved immediately; partial-cycle state is checkpointed periodically, currently every five seconds. Failed saves restore the previous production state. The Home return notice reports earnings already credited; acknowledging it clears the notice, not a second payout.

Old version-1 absence is settled at its original automation rate before migration changes future rates. The legacy blueprint and build APIs remain compatibility interfaces; they are not the authority for current store pricing.

### Bonzi on the carpet

An owned Bonzi (`bonzi_tier >= 0` in the visited store) appears during paid dry brushing. The editable `scenes/tools/bonzi_cleaner.tscn` contains a circular mint/ivory chassis, face, bumper, wheels and two counterrotating front brush motors. `bonzi_visual.gd` animates the motors and a fixed twelve-puff dust MultiMesh; these visuals do not grant cleaning progress.

`bonzi_cleaner.gd` walks five overlapping lanes at 0.12 m/s and turns at 2 radians/s. It reverses the same route at the far end instead of teleporting. Contact is sampled at 20 Hz through `dirt_controller.apply_bonzi_stroke`: timed, monotonic mask removal plus one-time suction of the existing clump progress IDs. It uses a separate contact footprint and never changes the finger's pass buffers, tool width or strength. Manual mask writes also remain monotonic so an older held stroke cannot restore dust Bonzi has removed.

The workshop authorizes motion only while focused, in the cleaning phase, with the rug fully revealed and no upgrade panel, finish request or suspended simulation. Bonzi remains idle while a panel is open and hides for rug arrival, completion and departure. Its brush helper operates in all six current stores. The retained future wet path hands mixed recipes over to the hose after dry completion.

Continuous autonomous progress starts a two-second snapshot checkpoint only when the timer is stopped; finger release and Back still save immediately. Reloading restores the existing dust/debris snapshot and restarts the route without a new save field. Replacement rugs reuse the same robot and debris pools. `manual_debris_cleared` distinguishes late finger-driven debris clearance from autonomous suction, so Bonzi cannot satisfy final-tool usage requirements. Full dry completion uses the existing 99% job transaction and pays that visible carpet once. The separately timed live/offline orders share the store's full-clean value, but a visible sweep grants no extra routine-order payment. Validate with `tools/validate_bonzi_cleaner.gd -- --shop-test` and add `--bonzi-capture` for renders.

## 7. Job lifecycle, rewards and persistence

### Paid-job sequence

1. `start_job()` resumes the branch's active job or assigns a new unique job ID and payout quote.
2. `workshop._ready()` configures the store recipe, restores its snapshot and starts rug arrival.
3. Cleaning modifies the existing soil/mask state. Cleared brush dirt fades in 0.6 seconds; its permanent disappearance IDs gate payable dry progress. Wet payments follow natural runoff retirement, with a durable pending removal watermark for interrupted/interior effects. Hose water alone never earns money. A 0.2-second one-shot timer batches `record_cleaning_progress()` transactions that save the mask and paid share together; release and Back checkpoint immediately.
4. `finish_rug()` reserves the remaining cosmetic count-up and asks `complete_and_start_next_job()` to settle the total at half the current quote for an early 75% Finish, or the full quote at 99%, subtracting already-paid cleaning money. It reserves the next carpet atomically. The wallet counts during suction, before Compare hides the cleaning HUD.
5. Only after that transaction succeeds does the completed rug vacuum/roll away and the next rug arrive.
6. The next rug reuses the existing scene, meshes and dirt pool; it is not a fresh scene load.

A second tap with the old job ID cannot pay again. A process restart during the departure animation opens the already-reserved replacement. If the transaction fails, the current rug remains available and the UI can retry; it does not animate away an unpaid job. [rug_roll.gd](../CarpetToy/scripts/rug_roll.gd) and the vertex deformation in [soil_surface.gdshader](../CarpetToy/scripts/soil_surface.gdshader) implement the roll.

The wallet animation never grants currency. `show_cleaning_reward()` counts already-saved money over 0.24 seconds with a 6% pulse, merging frequent credits without allocating particles. Purchases immediately show the durable post-spend balance. The existing fixed 24-coin pool remains for legacy/ad presentations; it cannot limit progressive payments. A job's `job_cleaning_paid` and `job_cleaning_progress` prevent duplicate credit after replay, reload or store travel. Mid-carpet renovations increase the current quote; only new removal progress triggers any catch-up. At 99%, total earned money still equals the displayed full carpet quote.

`carpet_ad_offer()` describes the current carpet's video state; `request_carpet_reward_ad()` requests a provider-verified receipt for that exact job and store. A successful transaction doubles its full quote, sets `job_ad_boost`, doubles any already-paid cleaning share and records the receipt together. The separate `carpet_ad_reward_granted` signal animates only that durable top-up. Early/full totals are 40/80 for a base 40 carpet. Skips, failures, a wrong nonce, stale job/store, reused receipt or failed save cannot grant a boost. Verified failed writes can retry without another video. The production button uses `set_carpet_ad_offer()` with HIDDEN, LOCKED, READY, REQUESTING and ACTIVE states; free practice hides it. No ad SDK or provider is configured, so paid carpets show LOCKED. Pending videos suspend soil, Bonzi, purchases and wallet presentation; focus return preserves that pause. The legacy completed-job ad API remains available for detached callers, but the live cleaning button requests the current carpet.

After suction, `completion_reveal.gd` presents only a small **Compare** button, centered at the bottom in portrait and placed at the lower right in landscape. Full restoration pauses for 2.4 seconds and early finish for 1.1 seconds before automatic departure. Holding Compare shows the recorded starting appearance and pauses the timer; release, canceled gestures, a second finger or focus loss restore the actual result. Release leaves at least 0.9 seconds to view it again. `rug_view_rect()` reserves the 148×56 action and its safe spacing while retaining the shared 20-degree pitch and zero yaw. Portrait retains the gentle reveal push; landscape fits the complete room into the full-height area beside Compare, preserving the cleaning carpet's scale. The reveal uses the same proportional phone/tablet scale as the cleaning HUD. `continue_now()` remains available to internal callers, with no visible Next control.

Before the rug curls and departs, both upright casements swing outward around their complete vertical side edges. The fixed frame matches their closed pose; top and bottom hinge points remain attached throughout opening and closing. All four window tiers retain the same clear rug corridor and exact closed reset. `validate_window_edge_hinges.gd` checks the actual authored vertices and hinge lines; `--window-hinge-capture` saves production-angle closed/half/open previews.

### Save layout

The ledger writes version **3** JSON with full float precision to `user://neighborhood_shop_v1.json`. The filename retains `v1` for continuity. On Windows, `user://` lives under Godot's `app_userdata` directory; use the resolved user-data directory when locating it.

Global fields include cash, active store, job serial, aggregate manual/automated counts, legacy ownership/blueprints, offline-return data, completed reward records and ad receipts. `stores` maps owned string IDs `"1"` through `"6"` to branches. Each branch contains:

- `payout_level`, `tool_level`, `hose_level`, `squeegee_level`, `bonzi_tier`.
- `room_rules_version` (currently 4), `room_upgrades`, `room_base_early`, `room_income_origins`.
- `bonzi_earned`, `manual_jobs`, `automated_jobs`, `routine_remainder`, `banked_orders`, `final_tool_jobs`.
- `active_job_id`, `job_snapshot`, `job_early_reward`, `job_started_with_final_tool`, `job_final_tool_used`.
- `job_cleaning_paid`, `job_cleaning_progress`: whole-valued paid money and the eligible removal high-water mark for this carpet, both initially zero for old unfinished saves.
- `job_ad_boost`: one verified 2× video boost for this active carpet, initially false for older saves and reset for the replacement. Timed Bonzi orders use the base room quote.

Purchases, store switches and rewards capture state before mutation. `_commit()` writes a temporary JSON file, flushes it, then renames it over the ledger. `_finish_transaction()` restores the captured state if the commit fails. Unreadable or unsupported saves are preserved and further saving is disabled rather than overwriting them with defaults. A player-requested reset is a separate, confirmed operation in Home settings.

`_restore_state()` accepts prior outer ledger versions 1/2 and migrates old accessory rules to rule 4. The wallet, owned stores, paid rewards, robot tiers, counters and rug identity/state are retained. Purchased visual tiers move to equivalent milestones on the new cap; historical progress after the last mesh maps into the remaining earnings levels. Old wet investments contribute to the corresponding brush track. Unpaid rug quotes are recalculated within the store's new ceiling; an old first-store AF quote is not grandfathered into future payments. Modern rule-4 branches are left on their current curve, including on rollback/reload. Version-1 historical absence still uses `LEGACY_ROUTINE_REWARD = 10`; future orders use the dynamic full-clean quote.

### Rug snapshots

`dirt_controller.make_snapshot()` produces a version-1 **rug snapshot**, independent of the outer version-3 ledger. It contains clump positions, velocities, growth, clearing/credit state, original scatter positions, recipe flags and base64 byte masks for coverage and, when applicable, water and extracted water. Masks are quantized to 8-bit values. `restore_snapshot()` validates lengths, finite values and `extracted <= water` before rebuilding the state.

Paired fields `recycled` and `debris_age` preserve free slots and partial fades. The existing `debris_policy: 2` marker and legacy `floor_debris` remain readable; old cleared floor clumps now resume a natural 0.6-second fade. Additive `retired_credits` flags retain each original disappearance even when its visual slot is emitted again. `earned_clearance` and `cleaning_pending_clearance` carry eligible and pending monetary removal targets. The legacy `pending_emissions` key is written empty; old requests are validated and discarded to prevent obsolete births. Validation rejects malformed arrays and retirement without an original credit before modifying live progress. Original positions, masks and motion remain preserved.

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

Landing fully outside earns a slot's one-time cleaning-progress credit. After settling, cleared floor dirt naturally shrinks away over 0.6 seconds. Each original slot receives one permanent disappearance credit when that fade finishes; the cleaning payout uses the lower of disappeared-clump clearance and actual surface clearance. Reusing a visual slot cannot repeat its original payment. Completed fades return slots to supply without emitting anything; subsequent current brush contact can reuse them. Full-pool cosmetic emissions are skipped instead of replayed later. Launch makes a clump fully visible and requests rendering during the input event; physics moves it on the first tick without a growth wait. Clean strokes and idle time create no new demand. Rebrushing cancels a fade while the clump is in contact. Pause freezes work, vacuum starts from current visible sizes, and water-only recipes clear the dry state. Physics sleeps after motion and fades finish. See [implementation and validation](Brush_Dirt_Layers.md).

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

Production cleaning uses an orthographic camera with adjustable pitch/yaw, currently 20 degrees from top-down and zero yaw for a straight view. It fits room geometry to the HUD's shared world rectangle. Portrait has a compact header and bottom actions; landscape places the controls beside a full-height diorama. The wider room leaves clear floor aisles around the unchanged carpet, and its foundation is visible above the surrounding ground. Finish retains its reserved slot when hidden, and wallet text does not change the camera fit. The **Gym** has the top/angled camera toggle. [gym_camera.gd](../CarpetToy/scripts/gym_camera.gd) fits these views into the HUD-safe region; all use the same ray-based input.

HUD layouts account for safe insets, portrait/landscape space and mobile orientation changes. The cleaning HUD chooses its scale from screen proportions: **Phone Portrait Width** defaults to 390 logical units, **Phone Landscape Height** to 360, and **Tablet Short Side** to 640. The safe area's long-to-short-side ratio blends the tablet reference into the selected phone reference between 1.45 and 1.75. Lower reference values enlarge the HUD; higher values leave more room for the diorama. This keeps high-resolution phone text and controls proportional to the screen rather than letting native pixel count shrink them.

The scale is `max(safe_short_side / reference_short_side, 44 / (56 * pixels_per_unit))`, where `pixels_per_unit` maps viewport units to window pixels. The second term is a minimum-touch fallback that keeps a 56-unit action at least 44 physical pixels tall. HUD scaling is independent of the expanding 720×1000 world reference canvas; the camera consumes the resulting `workshop_view_rect()` while carpet geometry stays unchanged. Runtime `_layout()` methods still position authored controls, so changing a scene offset alone may not change the final runtime layout. Use [Editing_UI_in_Godot.md](Editing_UI_in_Godot.md) for the sizing and spacing settings.

Before scaling, the dry progress percentage uses font size 24 with a one-unit outline. The Per carpet plaque is 48 units high and up to 280 wide, with amount font size 26, dark caption size 16 and a 6-unit gap below progress. The footer reserves cart 56×56, video 96×56 and Finish 104×56 with 12-unit gaps. Finish always has its plain name and font size 20. The wallet retains font size 32 and a 42×42 coin. These defaults remain authored in `cleaning_hud.tscn` and composed by `cleaning_hud.gd`.

The cleaning upgrade drawer pauses cleaning and transitions, blocks background input and restores focus when closed. `ShopContentsScroll / ShopColumns` contains the tool and Bonzi offers, placed beside each other in wide layouts and stacked in narrow portrait. Each offer has authored current/next artwork, statistics and its own purchase action outside its comparison-card scroller; Done stays fixed above the body. A released tap outside closes the shop, while canceled drags or multiple fingers retain it without cleaning underneath. `UpgradeSheet` renders above the wallet. All six current stores show brush upgrades; the retained wet drawer layout belongs to future wet stores. Floating accessory offers count purchases toward the next real visual milestone and show **Makeovers complete** after the last mesh. Management Stores displays section progress, the current unlock checklist, store rows and opening purchase. Opening has a confirmation panel.

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
| Economy, sections and mastery | [validate_section_progression.gd](../tools/validate_section_progression.gd), [validate_room_economy.gd](../tools/validate_room_economy.gd), [validate_first_shop_mastery.gd](../tools/validate_first_shop_mastery.gd), [validate_progression.gd](../tools/validate_progression.gd) |
| Authored makeovers and accessory interaction | [validate_visual_milestones.gd](../tools/validate_visual_milestones.gd), [validate_room_interaction.gd](../tools/validate_room_interaction.gd), [validate_rapid_room_upgrades.gd](../tools/validate_rapid_room_upgrades.gd), [validate_workshop_walls.gd](../tools/validate_workshop_walls.gd) |
| Current paid recipes and transitions | [validate_store_loop.gd](../tools/validate_store_loop.gd), [validate_contract.gd](../tools/validate_contract.gd), [validate_rug_transition.gd](../tools/validate_rug_transition.gd), [validate_completion_choreography.gd](../tools/validate_completion_choreography.gd) |
| Saves, automation and rewards | [validate_shop_state.gd](../tools/validate_shop_state.gd), [validate_automation_reset.gd](../tools/validate_automation_reset.gd), [validate_coin_rewards.gd](../tools/validate_coin_rewards.gd) |
| Bonzi's autonomous brush | [validate_bonzi_cleaner.gd](../tools/validate_bonzi_cleaner.gd): ownership, real dust/debris, pauses, checkpoints, reward and wet-stage handoff |
| Layout, navigation and touch | [validate_wet_upgrade_ui.gd](../tools/validate_wet_upgrade_ui.gd), [validate_editable_hud.gd](../tools/validate_editable_hud.gd), [validate_shop_ui.gd](../tools/validate_shop_ui.gd), [validate_scene_routes.gd](../tools/validate_scene_routes.gd), [validate_home_settings.gd](../tools/validate_home_settings.gd), [validate_brush_input.gd](../tools/validate_brush_input.gd) |
| Dirt and cleaning masks | [validate_cleaning.gd](../tools/validate_cleaning.gd), [validate_brush_recycling.gd](../tools/validate_brush_recycling.gd), [validate_dirt_pool.gd](../tools/validate_dirt_pool.gd), [validate_dirt_reentry.gd](../tools/validate_dirt_reentry.gd), [validate_wet_cleaning.gd](../tools/validate_wet_cleaning.gd), [validate_rotated_squeegee.gd](../tools/validate_rotated_squeegee.gd) |
| Gym, hose and squeegee | [validate_gym.gd](../tools/validate_gym.gd), [validate_hose_upgrades.gd](../tools/validate_hose_upgrades.gd), [validate_water_jet.gd](../tools/validate_water_jet.gd), [validate_squeegee_controls.gd](../tools/validate_squeegee_controls.gd) |
| Ridges and runoff | [validate_squeegee_trail.gd](../tools/validate_squeegee_trail.gd), [validate_squeegee_runoff.gd](../tools/validate_squeegee_runoff.gd), [validate_runoff_pool.gd](../tools/validate_runoff_pool.gd), [validate_long_runoff.gd](../tools/validate_long_runoff.gd) |

Known limits and distinctions:

- The earlier 12 ShopState baseline failures were reconciled with the staged upgrade economy; the current focused ShopState pass completed 229 checks with zero failures. This does not establish that every unrelated repository check was run.
- [reward_ad_service.gd](../CarpetToy/scripts/reward_ad_service.gd) is a provider adapter, not an installed advertising SDK. No configured provider means no ad availability or reward. A provider must support availability, request and receipt verification; the ledger prevents duplicate job rewards/receipt reuse.
- A successful desktop validation or APK signature check does not establish frame rate, thermal behavior, touch feel or lifecycle correctness on every Android device. Device profiling and playtesting remain necessary.
- VFX timing and color are stylized. There is no general fluid solver, mass-conserving water transport or persistent off-carpet puddle simulation.
- Historical `water_blobs` and older `squeegee_water_*` implementations/tests may remain in the repository. The active runtime follows the references in `workshop._ensure_wet_runtime()` and `squeegee_water.setup()`; a similarly named old file is not necessarily active.

## 14. Where to make common changes

| Desired change | Edit or inspect |
| --- | --- |
| Finish percentage or perfect threshold | `shop_state.gd`: `MANUAL_COMPLETION_THRESHOLD`, `PERFECT_COMPLETION_THRESHOLD`; verify workshop and ledger tests together |
| Current section size, store caps or future wet boundary | `progression.gd`: `STORES_PER_SECTION`, `SECTION_COUNT`, `ROOM_LEVEL_CAPS`, `REWARD_CAPS`, `WET_FIRST_STORE`; recipe setup/restore remains in `workshop.gd` |
| Store and section unlock requirements | `shop_state.gd`: `store_mastered()`, `section_progress()`, `progression_view()`, `note_current_tool_used()`, `open_next_store()` |
| Accessory visual milestones | `room_upgrades.gd`: definitions and `visual_milestones_for()`; add matching authored tiers to `scenes/room/upgrade_room.tscn` |
| Explain lock requirements in UI | `compact_shop.gd`: `refresh()` Stores branch; `compact_shop.tscn`: `TravelGoals` |
| Job payout, upgrade costs, Bonzi rates | `progression.gd` and `room_upgrades.gd`; ledger transaction tests must still pass |
| Bonzi's on-rug model, motion and cleaning | `scenes/tools/bonzi_cleaner.tscn`, `bonzi_visual.gd`, `bonzi_cleaner.gd`, `dirt_controller.gd`: `apply_bonzi_stroke()`; validate simultaneous manual brushing |
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

[Metagame_v0_2.md](Metagame_v0_2.md), [Store_Progression_v0_3_Draft.md](Store_Progression_v0_3_Draft.md) and [Water_Blobs.md](Water_Blobs.md) contain historical designs. Earlier four-store wet progression, optional room mastery, first-store AF earnings and five-purchase finish refinements are superseded by the six-store section rules above. Resolve disagreements against active code and current cap/milestone documentation.
