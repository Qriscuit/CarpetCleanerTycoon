# Mint Meadow — carpet cleaning prototype

## Run and build

Open **Open Game Editor.cmd**, then press **F5** for the floating-store main menu. The project uses the bundled standard Godot 4.7.2; no .NET SDK is required.

To export, save changes and double-click **Build APK.cmd**. The launcher checks dependencies, exports a signed debug APK, verifies its signature, and writes **build/CarpetCleaner.apk**. See the [APK recovery checklist](design/Android_APK.md) for SDK, template and signing fixes. **No APK was built for the current progression implementation.** Phone performance and touch feel still need device testing.

## Current game loop

Tap the floating store to clean or resume its rug. Swipe it left or right to preview stores. The bottom dock opens **Shop**, **Tools**, **Stores** and **Bonzi** sheets. Owned stores keep their own unfinished rug and upgrades; visiting another store preserves them. The main menu and rug-cleaning window are separate production scenes, driven by the selected store's data.

Clean a rug, collect coins, then choose a higher payout or a stronger tool. The cleaning HUD keeps a progress bar, persistent gold wallet, Back control, bottom payout card and left tool drawer. **Finish job** appears at 85%; at 99% the job finishes automatically. Rugs roll in, starter rocks appear, and the brush enters. On completion, debris is sucked away and the rug rolls out before the next rug arrives. There is no new-rug prompt or scene reload between jobs.

| Store | Cleaning | Starting early / full payout | Opening price |
| --- | --- | ---: | ---: |
| Neighborhood | Brush | 20 / 40 | Free |
| High Street | Stronger brushes | 160 / 320 | 2,000 |
| Wash House | Brush → water → squeegee | 1,280 / 2,560 | 16,000 |
| Restoration Studio | Stronger wet tools | 10,240 / 20,480 | 128,000 |

These are four authored stores, using shared building geometry with palette changes. Extra payout levels continue beyond the initial 20-level tuning range, subject to a **9,000,000,000,000,000** currency guard. There is no fifth-store purchase or literal infinite-number system.

For store scale `S = 8^(store - 1)` and payout level `L`, early reward is `S × round(20 × 1.10^L)` and the next payout upgrade costs `S × round(25 × 1.15^L)`. A full clean always pays twice the early reward. Prices and pacing are prototype balance values; definitions live in [progression.gd](CarpetToy/scripts/progression.gd). See the [progression draft](design/Store_Progression_v0_3_Draft.md) and [implementation coverage](design/Implementation_Coverage.md) for scope and remaining work. The v0.2 GDD and workbook are historical; the workbook remains unchanged while the user's replacement source is pending.

## Tools, Bonzi and travel

Each store has four local tool upgrades costing **80S, 200S, 500S and 1,000S**. Store 1 increases brush width through **1.44×, 1.55×, 1.65× and 1.75×**, with later tiers also increasing cleaning strength. Store 2 improves strength while retaining the 1.75× width cap. Nine distinct matte brush models cover the starter and eight dry-tool upgrades. Stores 3–4 upgrade water and extraction strength. The strongest owned tool power travels with the player; returning to an earlier store does not downgrade it.

The bottom payout card separates current/next earnings from the purchase price. A purchase updates the unfinished rug's saved quote immediately without resetting its dirt. The tool drawer shows current and next equipment and their effects. Opening the drawer pauses cleaning, dirt motion and rug transitions; Close or Back resumes the same phase. Purchases wait for reward coins to reach the displayed wallet. The first-use payout teaching animation is still planned polish.

| Bonzi tier | Incremental price | Coins per bar | Bar duration |
| --- | ---: | ---: | ---: |
| Basic | 100 in Store 1; included in later stores | 10S | 120 seconds |
| Improved | 300S | 20S | 90 seconds |
| Final | 900S | 40S | 60 seconds |

Bonzi becomes purchasable after three paid Store 1 rugs. Every owned store earns independently, including during manual cleaning and while away. Fractional deliveries carry forward; offline credit is capped at eight hours per absence. Manual payout upgrades do not alter Bonzi's displayed rate.

Opening the next store requires three things: local Bonzi earnings of **100S**, the final local tool used on **three paid rugs begun after its purchase**, and **2,000S** in the shared wallet. Only the opening price is spent. Spending never reverses the cumulative Bonzi milestone. Later stores include their basic Bonzi and required starter equipment. Reaching payout level 19 is not a travel gate.

**Settings → Reset progress → Reset** clears the wallet, stores, tools, automation and active rugs after confirmation. **Keep playing** cancels. A fresh save retains the free starter brush and Neighborhood store.

**Settings → Gym** opens free practice from the main menu. Click or tap outside Settings to dismiss it, or use Back/Escape. In the gym, **Rug 1 · Brush** tests surface dust and dirt pellets with the brush. **Rug 2 · Wet tools** begins after the dry-cleaning stage: hold the hose to pour a continuous opaque cyan jet, then drag it across the rug. New water follows the nozzle while water already in flight trails behind; contact creates a scalloped splash crown, small droplets and a dark wet patch. Releasing drains the airborne tail. Wet 99% of the carpet to unlock the squeegee, then drag it to pull water from the same wetness display. Switch exercises or use **Reset rug** to start fresh. Practice awards no coins and preserves the active paid rug; Back returns to the main menu.

Use the compact **Hose upgrades → Spout −/+** controls to compare five free Gym levels. The coherent column now begins widening above mid-flight, carries roughly half of its added width through the middle, and joins the larger landing without a pinched section. Upgrading also increases absorption speed and grows a larger wet fringe while you hold still. Wet spots stay on the carpet and briefly finish soaking after you move away. Your preview level survives rug resets during the visit; it costs no coins and does not change production upgrades.

The Gym jet uses one permanent **16-ring × 10-side tube**, one opaque impact mesh and a **24-slot droplet MultiMesh**. A fixed 96-pose nozzle history drives its ballistic centerline; a vertex shader supplies gentle traveling surface waves. Carpet contact deposits water over a **0.26–0.46 m wet radius** at bounded 20 Hz cadence. Six reusable reservoirs add soft spreading at 10 Hz, approaching **0.52–0.90 m radius** with sustained contact. Both write to the existing **256 × 416 L8 wetness mask**, which the squeegee also clears. Resources are reused and processing stops after the tail, droplets and brief after-soak finish. See [continuous jet architecture and tuning](design/Water_Jet.md). These bounded costs are not a measured Android performance claim.

## Cleaning and rewards

For dry rugs, the meter uses the lower of debris clearance and surface-dust clearance. Wet rugs average dry, water and extraction progress. Water starts after 99% dry clearance; squeegeeing starts after 99% water coverage. The tool advances between stages. Early completion at 85% therefore permits some remaining extraction; 99% completes the whole job automatically. The ledger validates the required stages rather than trusting a displayed percentage.

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

Use the portable Godot executable and isolated saves. In PowerShell:

```powershell
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path CarpetToy --script ../tools/validate_progression.gd -- --shop-test
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path CarpetToy --script ../tools/validate_wet_cleaning.gd -- --shop-test
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_store_loop.gd -- --shop-test
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_gym.gd -- --shop-test
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_water_jet.gd -- --shop-test
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_hose_upgrades.gd -- --shop-test
```

The progression suite covers prices, travel, migration, offline income, transaction failures, numerical limits and verified-ad receipt handling. Wet checks cover stage gates, strokes, masks and saved progress. Store-loop checks exercise production scenes, purchases, swipes, tools and wet recipes.

The gym check exercises Settings entry/dismissal, both rug selectors, tool restrictions, reset and transition cancellation, touch input, portrait/landscape layouts, and preservation of the existing paid rug/save. It captures both exercises under `art/renders/`. Use the graphics renderer for this check.

Run `validate_rug_transition.gd`, `validate_dirt_pool.gd`, `validate_coin_rewards.gd` and `validate_cleaning.gd` with the graphics renderer and the same isolated-save arguments for transitions, resource reuse, wallet animation and input regressions. The headless dummy renderer does not preserve MultiMesh instance data. Logs and captures are under `art/`; see [implementation coverage](design/Implementation_Coverage.md) for which evidence supports each feature.

`tools/assemble_workshop.gd` rebuilds authored scene content; it is not needed for ordinary play or tests. It replaces the generated workshop scene, so only run it intentionally. Reload external changes in Godot, or restart the editor if a cached MultiMesh reports an instance-format warning.
