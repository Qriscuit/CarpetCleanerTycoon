# Mint Meadow — carpet cleaning prototype

For a detailed explanation of the current systems, save format, equations and file locations, see the [Game Systems Reference](design/Game_Systems_Reference.md).

The [mobile performance pass](design/Mobile_Performance.md) documents the squeegee optimizations and reproducible before/after desktop timings. Phone frame-time testing remains necessary.

## Run and build

Open **Open Game Editor.cmd**, then press **F5** for the floating-store main menu. Opening, validation and exporting are pinned to **Godot 4.7.2 Mono/.NET**, using the complete bundle at `tools/godot/Godot_v4.7.2-stable_mono_win64/`, including its adjacent `GodotSharp` folder. The editor and APK launchers share a strict version/flavor check and do not fall back to a standard build or another Godot version.

Gameplay remains **GDScript**; this toolchain change does not port scripts to C#. The installed **.NET 8 SDK 8.0.400** supports this Mono editor. Android C# compilation has separate SDK/workload requirements to resolve if a C# port is requested later.

To export, save changes and double-click **Build APK.cmd**. The launcher checks dependencies and matching **4.7.2.stable.mono** templates, exports a signed debug APK, verifies its signature, and writes **build/CarpetCleaner.apk**. See the [APK recovery checklist](design/Android_APK.md) for SDK, template and signing fixes. **A fresh Mono APK was exported and signature-verified on 2026-09-25**; its exact engine, template version and SHA-256 are recorded in `build/android-build-info.txt`. Phone performance and touch feel still need device testing.

## Current game loop

Tap the floating store to clean or resume its rug. Swipe it left or right to preview stores. The bottom dock opens **Shop**, **Tools**, **Stores** and **Bonzi** sheets. Owned stores keep their own unfinished rug and upgrades; visiting another store preserves them. The main menu and rug-cleaning window are separate production scenes, driven by the selected store's data.

Clean a rug, collect coins, then choose a higher payout or a stronger tool. The cleaning HUD keeps a progress bar, persistent gold wallet, Back control, bottom payout card and left tool drawer. **Finish job** appears at 75%; at 99% the job finishes automatically for exactly twice the normal reward. The bottom upgrade offer shows only the 75% reward's current → next amount and the purchase price, without a second 99% value row. Rugs roll in, starter rocks appear, and the brush enters. On completion, debris is sucked away and the rug rolls out before the next rug arrives. There is no new-rug prompt or scene reload between jobs.

| Store | Cleaning | Starting early / full payout | Opening price |
| --- | --- | ---: | ---: |
| Neighborhood | Brush | 20 / 40 | Free |
| High Street | Water → squeegee only | 160 / 320 | 2,000 |
| Wash House | Brush → water → squeegee | 1,280 / 2,560 | 16,000 |
| Restoration Studio | Stronger wet tools | 10,240 / 20,480 | 128,000 |

These are four authored stores, using shared building geometry with palette changes. Extra payout levels continue beyond the initial 20-level tuning range, subject to a **9,000,000,000,000,000** currency guard. There is no fifth-store purchase or literal infinite-number system.

For store scale `S = 8^(store - 1)` and payout level `L`, early reward is `S × round(20 × 1.10^L)` and the next payout upgrade costs `S × round(25 × 1.15^L)`. A full clean always pays twice the early reward. Prices and pacing are prototype balance values; definitions live in [progression.gd](CarpetToy/scripts/progression.gd). See the [progression draft](design/Store_Progression_v0_3_Draft.md) and [implementation coverage](design/Implementation_Coverage.md) for scope and remaining work. The v0.2 GDD and workbook are historical; the workbook remains unchanged while the user's replacement source is pending.

## Tools, Bonzi and travel

Each tool track has four local upgrades costing **80S, 200S, 500S and 1,000S**. Store 1 increases brush width through **1.44×, 1.55×, 1.65× and 1.75×**, with later tiers also increasing cleaning strength. Store 2 now uses **hose → squeegee only**, without brushing or brush-upgrade offers. Stores 2–4 include the starter hose and squeegee and sell their upgrades separately: hose upgrades improve spread/absorption; squeegee upgrades increase extraction per pass. Squeegee offers sit beneath hose offers in portrait and beside them in the short landscape drawer. The strongest owned tool power travels with the player. Existing combined wash-kit purchases migrate to both tracks; old Store 2 brush purchases retain their dry strength and also provide equivalent hose-upgrade credit. Nine brush models remain available for existing saves and previews.

The bottom payout card separates current/next earnings from the purchase price. A purchase updates the unfinished rug's saved quote immediately without resetting its dirt. The tool drawer shows current and next equipment and their effects. Opening the drawer pauses cleaning, dirt motion and rug transitions; Close or Back resumes the same phase. Purchases wait for reward coins to reach the displayed wallet. The first-use payout teaching animation is still planned polish.

| Bonzi tier | Incremental price | Coins per bar | Bar duration |
| --- | ---: | ---: | ---: |
| Basic | 100 in Store 1; included in later stores | 10S | 120 seconds |
| Improved | 300S | 20S | 90 seconds |
| Final | 900S | 40S | 60 seconds |

Bonzi becomes purchasable after three paid Store 1 rugs. Every owned store earns independently, including during manual cleaning and while away. Fractional deliveries carry forward; offline credit is capped at eight hours per absence. Manual payout upgrades do not alter Bonzi's displayed rate.

Opening the next store requires local Bonzi earnings of **100S**, all four local brush upgrades in Store 1 or hose upgrades in Stores 2–3, **three paid rugs using that max-level tool**, and **2,000S** in the wallet. The current rug counts if you buy the final upgrade and then use it; stationary hose contact counts too. Only the opening price is spent. The Stores sheet lists each requirement and its current count. Shop 3 specifically needs the max hose, three qualifying Shop 2 jobs, 800 local Bonzi coins and 16,000 opening coins. Squeegee upgrades and payout level 19 are not travel gates. Existing completed-job credit is retained.

**Settings → Reset progress → Reset** clears the wallet, stores, tools, automation and active rugs after confirmation. **Keep playing** cancels. A fresh save retains the free starter brush and Neighborhood store.

**Settings → Gym** opens free practice from the main menu. Click or tap outside Settings to dismiss it, or use Back/Escape. In the gym, **Rug 1 · Brush** tests surface dust and dirt pellets with the brush. **Rug 2 · Wet tools** begins after the dry-cleaning stage: hold the hose to pour a continuous opaque cyan jet, then drag it across the rug. New water follows the nozzle while water already in flight trails behind; contact creates a scalloped splash crown, small droplets and a dark wet patch. Releasing drains the airborne tail. Tap **Squeegee** to instantly wet the entire rug and practice extraction; tap **Water hose** to clear wetness/extraction and start watering again. Tapping the equipped tool repeats its setup. Natural watering still advances to extraction at 99%; production stage gates are unchanged. Switch exercises or use **Reset rug** to start fresh. Practice awards no coins and preserves the active paid rug; Back returns to the main menu.

Use the compact **Hose upgrades → Spout −/+** controls to compare five free Gym levels. The **Squeegee −/+** controls directly below independently preview five extraction strengths. The coherent column begins widening above mid-flight, carries roughly half of its added width through the middle, and joins the larger landing without a pinched section. Passive soaking starts at **3× its previous base rate**, gains nonlinear level multipliers of **1 / 1.35 / 1.8 / 2.35 / 3**, and smoothly builds another **35%** during a 1.5-second hold. The HUD's Soak multiplier compares passive rates to the new Lv 1. Upgrades also increase direct absorption and spread growth speed. Wet spots stay on the carpet and briefly finish soaking after you move away. Your preview levels and camera survive tool-button resets during the visit; it costs no coins and does not change production upgrades.

The Gym jet uses one permanent **16-ring × 10-side tube**, one opaque impact mesh and a **24-slot droplet MultiMesh**. A fixed 96-pose nozzle history drives its ballistic centerline; a vertex shader supplies gentle traveling surface waves. Carpet contact deposits water over a **0.26–0.46 m wet radius** at bounded 20 Hz cadence. Six reusable reservoirs add soft spreading at 10 Hz, approaching **0.70–1.20 m radius** with sustained contact. Both write to the existing **256 × 416 L8 wetness mask**, which the squeegee also clears. Resources are reused and processing stops after the tail, droplets and brief after-soak finish. See [continuous jet architecture and tuning](design/Water_Jet.md). These bounded costs are not a measured Android performance claim.

The Gym squeegee has a **low, outward-curling splash around all four edges of its head**—no airborne water column or forward sheet. The opaque cyan rim gently undulates, with small droplets leaving the perimeter. The blade, extraction footprint and rectangular splash follow the same smoothed drag heading; the model's 180° front/back correction remains in place. Actual newly extracted water drives the effect, so dry or stationary passes produce no new splash. The moving head still uses one fixed perimeter mesh and 24 pooled droplets.

A **low water ridge now lingers around the cleared path**, outlining the combined cleaned area rather than drawing a separate border around every swipe. Overlapping passes merge, so an old ridge does not remain across the middle of the newly cleared area. Carpet ridges linger for eight seconds after the latest sampled extraction increase, then gently fade over two seconds. At the carpet boundary, a short joining apron feeds **broad matte-blue floor streams** with rounded ends, gentle curves and moving cyan accents. Streams rush outward at **5.2 m/s**, travel up to **12.6 m**, and thin away during the final **0.85 seconds** of their **2.5-second** lifetime. This longer range preserves full-camera exit with the expanded Gym upgrade panel. The trailing edge follows the water outward; no permanent floor pattern remains. Cleaning elsewhere cannot renew an old exit: only fresh local extraction supplies it.

A fixed sampled grid and reused strip batch update the carpet contour only when dirty, at most 10 times per second. A 128-bin perimeter map groups adjacent exits into broad mouths; **one extra MultiMesh with 16 reusable streams** handles the long flow, using **18 × 7 vertices per stream**. Streams stay world-anchored, use an opaque matte shader, and need no fluid solver, refraction or new nodes per swipe. All of this is visual only: it never rewets the carpet, redistributes water or changes extraction progress. The hose retains its falling column and circular impact. These are bounded implementation costs, not measured phone performance.

Tap **Angle / Top** to switch between angled and overhead orthographic views with the same mouse/touch controls. For an immediate Godot preview, open `CarpetToy/scenes/test/squeegee_water_preview.tscn` and press **F6**: a 12-second loop makes back-and-forth passes through one channel, then pushes its end beyond the tasselled edge to show runoff. **Space** pauses/resumes, **Tab** changes camera, and clicking returns to manual practice without changing your view. Tune the moving head's **SqueegeeWater → Splash Reach** (default 0.17 m) and **Splash Height** (default 0.085 m) in the Inspector. See [squeegee visual design and implementation](design/Squeegee_Water_VFX.md).

## Cleaning and rewards

Store 1 uses dry rugs: its meter is the lower of debris and surface-dust clearance. Store 2 starts clean and dry with the hose, then the squeegee; its meter is `(water + extraction) / 2`. Stores 3–4 retain brushing, watering and extraction, with a three-stage average. In those stores watering requires 99% dry clearance; in every wet store extraction requires 99% water coverage. The tool advances between stages. Early completion at 75% permits some remaining extraction; 99% automatically pays double. The ledger validates the recipe and stage order rather than trusting a displayed percentage. Existing Store 2 snapshots retain water/extraction progress and remove only the obsolete dry stage.

Hold the left mouse button or one finger and drag once the brush arrives. Touch uses a 72 viewport-pixel offset above the finger. One finger owns the stroke; release, cancellation, tool changes and loss of focus end it. Placement never sweeps an unintended path from the previous position. Sweep beyond the rug edges to throw clumps onto the surrounding tile.

The starter brush removes surface dust over two core passes with feathered edges. Many events in one pass do not multiply cleaning; releasing or reversing direction begins another pass. Upgraded strength improves this action. Wet recipes track applied water and extraction in reusable arrays, render their difference through one wetness mask, and save both progress layers alongside the dry state.

The reward and the next rug are saved atomically before the takeaway animation. Reusable 2D coins linger, then fly into the top-right wallet; each adds its exact value to the **displayed** total. Actual earnings are already durable. Leaving during the animation cannot duplicate or lose them. Back remains available during arrival, cleaning, suction and departure; it closes an open drawer first. The legacy test gym awards no money.

Optional rewarded-ad integration is prepared, but **no ad SDK, provider or IDs are configured**, as requested. Its offer stays hidden without an available provider. A verified provider completion can add one extra completed-rug payout, once per job; skipped or failed ads cannot remove earned money. Ads are not required for upgrades or travel. Real ad playback is not yet tested.

## Saved progress and navigation

Version 2 JSON data uses the existing `user://neighborhood_shop_v1.json` path. Migration preserves existing cash, tools, Bonzi, the current rug and fractional automation progress without reducing owned power or output. Purchases, rewards and travel use atomic saves with rollback on failure. Offline income uses local time; this prototype makes no anti-cheat claim.

Production entry scenes are `CarpetToy/scenes/production/floating_home.tscn` and `rug_cleaning.tscn`. The reachable gym remains at `CarpetToy/scenes/test/rug_cleaning_gym.tscn` and is included in Android exports. The old detailed hub and asset previews remain excluded. Gameplay Back controls return to the floating home. See [scene navigation](design/Scene_Navigation.md).

## Reused assets and simulation

- The same rug scene, meshes and **560-slot dirt pool** serve successive jobs. Scatter is randomized per new rug; snapshots preserve existing scatter. No dirt node instances are recreated per refill.
- Rugs enter already dust-textured. After unrolling, **25 starter rocks** grow; the other slots remain invisible until brushing brings them out. Reveal animation does not change earned progress. The brush enters after the starter rocks.
- Dirt uses one 20-triangle mesh in a `MultiMeshInstance3D`. Only moving clumps simulate; visible instances are compacted into the existing batch. No clump rigid bodies or per-clump collision nodes are used.
- The existing rug shader uses a 256 × 416 dirt-opacity mask. Wet recipes reuse one additional 256 × 416 L8 wetness mask for both application and extraction; contact checks follow the rounded rug and fringe rather than an oversized rectangle.
- The tile floor uses one static MultiMesh; brush variants are instantiated once and switched by visibility. Reward coins are also reused.

These checks establish resource reuse and desktop behavior, not a phone frame-rate or memory benchmark. Clump motion remains a lightweight visual simulation without clump-to-clump collisions.

## Source and assets

| Area | Source |
| --- | --- |
| Definitions, save ledger and ad adapter | `CarpetToy/scripts/progression.gd`, `shop_state.gd`, `reward_ad_service.gd` |
| Main menu and management sheets | `CarpetToy/scripts/floating_home.gd`, `compact_shop.gd` |
| Rug flow, input and HUD | `CarpetToy/scripts/workshop.gd`, `cleaning_hud.gd` |
| Dirt, wet layers and rug boundary | `CarpetToy/scripts/dirt_controller.gd`, `soil_surface.gdshader`, `rug_footprint.gd` |
| Brush tiers | `CarpetToy/scripts/tool_progression_visual.gd`, `CarpetToy/assets/tools/progression/`, `tools/build_progression_tools.py` |
| Blender sources | `art/blender/floating_shop.blend`, `mint_meadow.blend`, `starter_tools.blend`, `progression_tools.blend` |

The original rug is 2 × 3 m plus fringe, with 3,176 triangles and 1024 × 1536 textures. The reusable clean rug remains `CarpetToy/scenes/carpet.tscn`; its inspection scene is in `scenes/test/`. See [floating-home implementation](design/home-screen/IMPLEMENTATION.md) for the original menu asset workflow.

## Verify

Use the shared **4.7.2 Mono/.NET-only** runner and isolated saves. In PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_progression.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_store_unlock.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_wet_cleaning.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_wet_upgrades.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_second_store_wet.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_wet_upgrade_ui.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_store_loop.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_gym.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_water_jet.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_squeegee_water.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_squeegee_trail.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_squeegee_runoff.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_long_runoff.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_runoff_pool.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_squeegee_controls.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_rotated_squeegee.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_hose_upgrades.gd -- --shop-test
```

The progression suite covers prices, travel, migration, offline income, transaction failures, numerical limits and verified-ad receipt handling. Wet checks cover stage gates, strokes, masks and saved progress. Store-loop checks exercise production scenes, purchases, swipes, tools and wet recipes.

The gym check exercises Settings entry/dismissal, both rug selectors, tool restrictions, reset and transition cancellation, touch input, portrait/landscape layouts, and preservation of the existing paid rug/save. It captures both exercises under `art/renders/`. Use the graphics renderer for this check.

Run `validate_rug_transition.gd`, `validate_dirt_pool.gd`, `validate_coin_rewards.gd` and `validate_cleaning.gd` with the graphics renderer and the same isolated-save arguments for transitions, resource reuse, wallet animation and input regressions. The headless dummy renderer does not preserve MultiMesh instance data. Logs and captures are under `art/`; see [implementation coverage](design/Implementation_Coverage.md) for which evidence supports each feature.

`tools/assemble_workshop.gd` rebuilds authored scene content; it is not needed for ordinary play or tests. It replaces the generated workshop scene, so only run it intentionally. Reload external changes in Godot, or restart the editor if a cached MultiMesh reports an instance-format warning.
