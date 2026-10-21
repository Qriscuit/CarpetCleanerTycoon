# Mint Meadow — carpet cleaning prototype

For a detailed explanation of the current systems, save format, equations and file locations, see the [Game Systems Reference](design/Game_Systems_Reference.md).

The [mobile performance pass](design/Mobile_Performance.md) documents the squeegee optimizations and reproducible before/after desktop timings. Phone frame-time testing remains necessary.

## Run and build

Open **Open Game Editor.cmd**, then press **F5** to open the last selected store's current carpet directly. Opening, validation and exporting are pinned to **Godot 4.7.2 Mono/.NET**, using the complete bundle at `tools/godot/Godot_v4.7.2-stable_mono_win64/`, including its adjacent `GodotSharp` folder. The editor and APK launchers share a strict version/flavor check and do not fall back to a standard build or another Godot version.

Gameplay remains **GDScript**; this toolchain change does not port scripts to C#. The installed **.NET 8 SDK 8.0.400** supports this Mono editor. Android C# compilation has separate SDK/workload requirements to resolve if a C# port is requested later.

To export, save changes and double-click **Build APK.cmd**. The launcher checks dependencies and matching **4.7.2.stable.mono** templates, exports a signed debug APK, verifies its signature, and writes **build/CarpetCleaner.apk**. See the [APK recovery checklist](design/Android_APK.md) for SDK, template and signing fixes. The latest verified build's date, exact engine, template version and SHA-256 are recorded in `build/android-build-info.txt`. Phone performance and touch feel still need device testing.

## Current game loop

App launch opens or resumes the last selected store's paid carpet. **Back** opens the floating store menu, where tapping an owned store returns to its rug and swiping left or right previews stores. The bottom dock opens **Shop**, **Tools**, **Stores** and **You**. You opens the character wardrobe. Owned stores keep their own unfinished rug and upgrades; visiting another store preserves them. The main menu and rug-cleaning window are separate production scenes, driven by the selected store's data.

Clean a rug, collect coins, then improve a room feature or buy a better tool. The cleaning HUD keeps a progress bar, a live full-clean **Per carpet** amount beneath it, a prominent gold wallet, Back control and a cart button for tools. Tap outside the shop to close it. The cart and carpet illustrations share the room accessory SVG style; Home uses the same cart. Tap the floor, corner garden, window, railings or walls for a nearby upgrade card showing the feature's level, independent price, current/next full-clean earnings and progress toward its next authored makeover. **Finish** appears at 75%; cleaning earns money progressively, early Finish settles the total at half the quote, and automatic 99% restoration settles the full quote. Rugs roll in, starter rocks appear, and the brush enters. The brush hovers when released and lowers on contact. On completion, the camera gently reveals the design with one small **Compare** button near the bottom: centered in portrait and at the lower right beside the room in landscape. Holding it shows the recorded starting appearance and pauses the short automatic transition; release restores the result. The window then opens and the rug rolls out before the next rug arrives. There is no scene reload between jobs.

| Section 1 store | Upgrades per room feature | Starting full payout | Maximum full payout |
| --- | ---: | ---: | ---: |
| Neighborhood | 50 | 40 | 400K |
| High Street | 75 | 400K | 400M |
| Wash House | 100 | 400M | 4T |
| Restoration Studio | 125 | 4T | 400AA |
| Grand Arcade | 150 | 400AA | 4AD |
| Royal Gallery | 175 | 4AD | 400AF |

The first section contains six brush-cleaning stores, using shared building geometry and distinct palettes. Each has five independent room ladders. Three authored makeovers are spread across each ladder: Store 1 at 15/30/45, Store 6 at 50/100/150. The reusable rule also supports 50 levels with five makeovers at 10/20/30/40/50. After the last mesh, remaining upgrades increase earnings without advertising another appearance. Section 2 is a locked future-content preview, even after mastering Section 1. Water mechanics remain available in the Gym for development. Currency uses bounded float64 up to `1e60`; job counters retain their separate 9-quadrillion limit. AF=`1e30`.

Room upgrades can be purchased repeatedly without waiting for their feedback animation. Each released tap buys one level, updates the next offer immediately and adds a tall-then-wide bounce from the object's current pose. Each corner pot bounces about its own saucer, keeping its location fixed through every plant tier. The white ring and pillar stay visible through rapid purchases, using one reusable effect per room feature. Milestone appearances continue to catch up during tapping; the final pulse settles when tapping stops. Affordability, each store's level cap, pending coin collection and durable saving govern purchases.

Store scales are `1, 1e4, 1e7, 1e11, 1e16, 1e23`. Fresh cleaning-half quotes start at `20S` and grow by five independent contributions. Plants, floor, window, railings and walls start at prices `25S`, `40S`, `60S`, `35S` and `50S`. Each bounded geometric curve reaches its configured maximum with all features upgraded. The full carpet total is twice that half quote, split between removal work and 99% restoration. The [balance reference](design/First_Shop_Balance.md) documents current curves. These are prototype assumptions, not measured retention data; earlier drafts and workbooks are historical.

## Tools, character and travel

Each store has four brush upgrades priced at early, one-third, two-thirds and maximum earnings milestones across that store's room ladder. For starting full reward `P` and maximum `R`, the prices are `round(3 * P * (R/P)^f)` at `f = 0, 1/3, 2/3, 1`. Neighborhood's prices are **120, 2,585, 55,699 and 1,200,000**. Store 1 increases width through **1.44×, 1.55×, 1.65× and 1.75×**. Later upgrades continue increasing cleaning strength while nine authored models cover the section. The strongest owned tool power travels with the player. Wet mechanics are reserved for later sections; the Gym retains independent hose and squeegee previews.

Room offers appear beside the selected object, with no persistent bottom earnings card. Every successful purchase updates the unfinished rug's quote and plays a white ground ring, fading pillar and gentle squeeze/stretch. Milestone models appear at the compressed point. The room includes walls around the window and a side door. Home's Shop tab sells all five features. Panels pause cleaning and transitions; Close or Back resumes the same phase. In compact landscape, tool comparison cards scroll while Done and Buy stay visible inside the drawer. Failed saves play no success effect. The new save namespace starts with current room rules and no migration.

The room and HUD share a responsive composition rectangle: compact status above and actions below in portrait, controls beside the full-height diorama in landscape. HUD sizing follows screen proportions, using separate phone portrait, phone landscape and tablet references; a 44-pixel action minimum is a fallback for small windows. High-resolution phones retain readable controls relative to the screen. The .90 room scale leaves wider aisles around the unchanged carpet; a 20-degree pitch from top-down and zero yaw keep the view straight, while the visible foundation gives it depth. Spacing, column width, sizing references, camera pitch/yaw and room scale can be adjusted in the Inspector. Rotation, safe insets and wallet updates retain a coherent fit; Finish appearing does not move the camera. See [UI editing](design/Editing_UI_in_Godot.md) for the settings.

The bottom-right **You** button opens a visual wardrobe over the selected store. A smooth, continuous, featureless humanoid with straight limbs rotates above **Hats** and **Color** tabs. Bare head, a dark pirate hat, and a teal beanie equip for free. Eight colors are available, with warm orange (`#F28C28`) initially. Cards apply and save immediately, with a border and checkmark showing the selection. A failed save restores the previous choice.

Drag horizontally to turn the character; slow rotation resumes two seconds after release. Back, Escape, and Android Back return focus to You. The motion setting disables automatic rotation. One isolated viewport renders at up to 30 fps and 768 pixels on its longest edge; the two home viewports sleep while the wardrobe covers them. The character stops rendering when closed, paused, or unfocused. The equipped character stays within 4,000 triangles and three material surfaces. Cards and the dock use static thumbnails.

The same character is present immediately in every paid cleaning room, wearing the saved color and hat. He rides the brush handle, tumbles off after a fast flick, gets up, dusts himself off, runs toward the moving brush, and climbs back on. During carpet changes he waits beside the rug. Panels, video, focus loss and backgrounding suspend his behavior. His actions are cosmetic and do not clean or change rewards. See [companion behavior and performance](design/Level_Companion.md).

The editable source is `art/blender/avatar.blend`. Run `tools/build_avatar.py` then `tools/rig_avatar.py` in Blender to rebuild the static wardrobe assets and the separate skinned level asset. The continuous body has one white tintable material, 2,992 triangles, a 12-bone skeleton and six authored clips. Nine simple physical bones simulate only during falls; pose animation advances at 30 Hz.

Opening the next store requires every room feature at its cap, all four local brush upgrades, **three paid rugs using the max brush**, and **2,000S** in the wallet. Upgrading and using the brush during the current rug counts. Only the opening price is spent. The Stores sheet lists the checklist and section mastery count. All six stores must be mastered to complete the section; unavailable sections cannot be opened.

**Settings → Reset progress → Reset** clears the wallet, stores, tools, appearance and active rugs after confirmation. **Keep playing** cancels. A fresh save starts with zero coins, the free starter brush, Neighborhood, and an orange character with no hat.

**Settings → Gym** opens free practice from the main menu. Click or tap outside Settings to dismiss it, or use Back/Escape. In the gym, **Rug 1 · Brush** tests surface dust and dirt pellets with the brush. **Rug 2 · Wet tools** begins after the dry-cleaning stage: hold the hose to pour a continuous opaque cyan jet, then drag it across the rug. New water follows the nozzle while water already in flight trails behind; contact creates a scalloped splash crown, small droplets and a dark wet patch. Releasing drains the airborne tail. Tap **Squeegee** to instantly wet the entire rug and practice extraction; tap **Water hose** to clear wetness/extraction and start watering again. Tapping the equipped tool repeats its setup. Natural watering still advances to extraction at 99%; production stage gates are unchanged. Switch exercises or use **Reset rug** to start fresh. Practice awards no coins and preserves the active paid rug; Back returns to the main menu.

Use the compact **Hose upgrades → Spout −/+** controls to compare five free Gym levels. The **Squeegee −/+** controls directly below independently preview five extraction strengths. The coherent column begins widening above mid-flight, carries roughly half of its added width through the middle, and joins the larger landing without a pinched section. Passive soaking starts at **3× its previous base rate**, gains nonlinear level multipliers of **1 / 1.35 / 1.8 / 2.35 / 3**, and smoothly builds another **35%** during a 1.5-second hold. The HUD's Soak multiplier compares passive rates to the new Lv 1. Upgrades also increase direct absorption and spread growth speed. Wet spots stay on the carpet and briefly finish soaking after you move away. Your preview levels and camera survive tool-button resets during the visit; it costs no coins and does not change production upgrades.

The Gym jet uses one permanent **16-ring × 10-side tube**, one opaque impact mesh and a **24-slot droplet MultiMesh**. A fixed 96-pose nozzle history drives its ballistic centerline; a vertex shader supplies gentle traveling surface waves. Carpet contact deposits water over a **0.26–0.46 m wet radius** at bounded 20 Hz cadence. Six reusable reservoirs add soft spreading at 10 Hz, approaching **0.70–1.20 m radius** with sustained contact. Both write to the existing **256 × 416 L8 wetness mask**, which the squeegee also clears. Resources are reused and processing stops after the tail, droplets and brief after-soak finish. See [continuous jet architecture and tuning](design/Water_Jet.md). These bounded costs are not a measured Android performance claim.

The Gym squeegee has a **low, outward-curling splash around all four edges of its head**—no airborne water column or forward sheet. The opaque cyan rim gently undulates, with small droplets leaving the perimeter. The blade, extraction footprint and rectangular splash follow the same smoothed drag heading; the model's 180° front/back correction remains in place. Actual newly extracted water drives the effect, so dry or stationary passes produce no new splash. The moving head still uses one fixed perimeter mesh and 24 pooled droplets.

A **low water ridge now lingers around the cleared path**, outlining the combined cleaned area rather than drawing a separate border around every swipe. Overlapping passes merge, so an old ridge does not remain across the middle of the newly cleared area. Carpet ridges linger for eight seconds after the latest sampled extraction increase, then gently fade over two seconds. At the carpet boundary, a short joining apron feeds **broad matte-blue floor streams** with rounded ends, gentle curves and moving cyan accents. Streams rush outward at **5.2 m/s**, travel up to **12.6 m**, and thin away during the final **0.85 seconds** of their **2.5-second** lifetime. This longer range preserves full-camera exit with the expanded Gym upgrade panel. The trailing edge follows the water outward; no permanent floor pattern remains. Cleaning elsewhere cannot renew an old exit: only fresh local extraction supplies it.

A fixed sampled grid and reused strip batch update the carpet contour only when dirty, at most 10 times per second. A 128-bin perimeter map groups adjacent exits into broad mouths; **one extra MultiMesh with 16 reusable streams** handles the long flow, using **18 × 7 vertices per stream**. Streams stay world-anchored, use an opaque matte shader, and need no fluid solver, refraction or new nodes per swipe. All of this is visual only: it never rewets the carpet, redistributes water or changes extraction progress. The hose retains its falling column and circular impact. These are bounded implementation costs, not measured phone performance.

Tap **Angle / Top** to switch between angled and overhead orthographic views with the same mouse/touch controls. For an immediate Godot preview, open `CarpetToy/scenes/test/squeegee_water_preview.tscn` and press **F6**: a 12-second loop makes back-and-forth passes through one channel, then pushes its end beyond the tasselled edge to show runoff. **Space** pauses/resumes, **Tab** changes camera, and clicking returns to manual practice without changing your view. Tune the moving head's **SqueegeeWater → Splash Reach** (default 0.17 m) and **Splash Height** (default 0.085 m) in the Inspector. See [squeegee visual design and implementation](design/Squeegee_Water_VFX.md).

## Cleaning and rewards

All six first-section stores use dry rugs: the meter is the lower of debris and surface-dust clearance. Half of the full **Per carpet** amount is earned progressively as removed dirt disappears. The wallet counts up over 0.24 seconds with a subtle pulse. Early Finish at 75% brings the carpet's total to half the quote, subtracting anything already paid; full restoration at 99% brings the total to the full quote. A 40-coin rug therefore earns 20 in total when finished early or 40 when fully cleaned. Finish shows only its name, with no amount. Wet recipes pay for extraction after runoff leaves, never for pouring water. Their code and free practice remain available for future sections.

Hold the left mouse button or one finger and drag once the brush arrives. Touch uses a 72 viewport-pixel offset above the finger. One finger owns the stroke; release, cancellation, tool changes and loss of focus end it. Placement never sweeps an unintended path from the previous position. Sweep beyond the rug edges to throw clumps onto the surrounding tile.

Mint Meadow and the practice brush rug begin under a **dark brown soil layer at 94% strength**. The starter brush removes 10% per full pass, taking **ten core passes** to reveal the original color fully; feathered edges need overlapping coverage. Input event frequency does not multiply cleaning, and a reversal must travel at least the brush head's depth (0.22 rug units). Upgraded strength still helps: the strongest brush clears a fully covered spot in five passes.

All hidden clumps are available immediately, and repeated dirty strokes can draw unused slots from across the **560-clump pool**. Pulled clumps become fully visible during brush contact and move on the first physics tick. Cleared clumps naturally shrink away over **0.6 seconds** after settling outside the rug. Their original disappearance credit persists even when a visual slot is reused. If the pool is temporarily full, no late spawn is queued: returned slots wait for current brush contact. See [brush layers and recycling](design/Brush_Dirt_Layers.md).

Wet recipes track applied water and extraction in reusable arrays, render their difference through one wetness mask, and save both progress layers alongside the dry state.

Cleaning credits are saved atomically with their carpet masks and job-local paid watermark, batched at most once every 0.2 seconds. The final unpaid amount and next rug are saved together before takeaway. The completion count-up runs while the wallet is still visible during suction. Returning, restarting or reusing a particle cannot pay the same work again. Purchases can spend already-saved cleaning money while its brief display animation finishes. Back closes an open drawer first; free Gym never pays for practice work.

The teal **Video 2×** button sits between the cart and Finish. **No ad SDK, provider or IDs are configured**, so paid carpets show its locked state. A connected provider's verified completion doubles that current carpet once, including a saved top-up for cleaning money already earned. Its full Per carpet quote changes too: a base 40 carpet becomes 80, paying 40 for early Finish or 80 for full cleaning. The boost and paid money survive reload and reset for the next carpet. Pending video pauses cleaning, purchases and wallet presentation; skipped or failed videos grant no boost. No mock video provider is included in production.

## Saved progress and navigation

Version 1 JSON uses **`user://carpet_cleaner_v1.json`**. Existing players start fresh; the previous save is left untouched and unread, so no final offline payout occurs. There is no income timer or offline earnings. Global appearance stores stable `color_id` and `hat_id` values; invalid loaded choices fall back to orange and bare head. Purchases, manual rewards, travel and appearance use atomic saves with rollback on failure. `set_appearance(color_id, hat_id)` emits `appearance_changed` only after a successful save.

Production entry scenes are `CarpetToy/scenes/production/floating_home.tscn` and `rug_cleaning.tscn`. The reachable gym remains at `CarpetToy/scenes/test/rug_cleaning_gym.tscn` and is included in Android exports. The legacy hub test entry now instances the production home; asset previews remain excluded. Gameplay Back controls return to the floating home. See [scene navigation](design/Scene_Navigation.md).

## Reused assets and simulation

- The same rug scene, meshes and **560-slot dirt pool** serve successive jobs. Scatter is randomized per new rug; snapshots preserve existing scatter. No dirt node instances are recreated per refill.
- Rugs enter already dust-textured. After unrolling, **25 starter rocks** grow; the other slots remain invisible until brushing brings them out. Reveal animation does not change earned progress. The brush enters after the starter rocks.
- Dirt uses one 20-triangle mesh in a `MultiMeshInstance3D`. Only moving clumps simulate motion; a separate timed list handles the brief disappearance fades. Processing sleeps when movement and fading finish. Visible instances are compacted into the existing batch. No clump rigid bodies or per-clump collision nodes are used.
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
| Avatar catalog and wardrobe | `CarpetToy/scripts/avatar_catalog.gd`, `avatar_customization.gd`, `avatar_preview.gd`, `CarpetToy/scenes/ui/avatar_customization.tscn` |
| Blender sources | `art/blender/floating_shop.blend`, `mint_meadow.blend`, `starter_tools.blend`, `progression_tools.blend`, `avatar.blend` |

The original rug is 2 × 3 m plus fringe, with 3,176 triangles and 1024 × 1536 textures. The reusable clean rug remains `CarpetToy/scenes/carpet.tscn`; its inspection scene is in `scenes/test/`. See [floating-home implementation](design/home-screen/IMPLEMENTATION.md) for the original menu asset workflow.

## Verify

Use the shared **4.7.2 Mono/.NET-only** runner and isolated saves. In PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_avatar_state.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_avatar_ui.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_progression.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_upgrade_price_progression.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_carpet_ad_boost.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --rendering-method gl_compatibility --script ../tools/validate_carpet_ad_hud.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --rendering-method gl_compatibility --script ../tools/validate_carpet_video_flow.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_store_unlock.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_wet_cleaning.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_wet_upgrades.gd -- --shop-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_second_store.gd -- --shop-test
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

The progression suite covers prices, manual travel requirements, transaction failures, numerical limits and verified-ad receipt handling. Avatar tests cover appearance persistence, fresh-save isolation, idle wallets, touch input, framing and rendering budgets. Run `python tools/validate_avatar_assets.py` with Python 3 to check the exported body is one connected, watertight surface and verify geometry, material and hat-placement budgets. Wet checks cover stage gates, strokes, masks and saved progress. Store-loop checks exercise production scenes, purchases, swipes, tools and wet recipes.

The upgrade-price suite checks staged prices and real purchase debits. The carpet-ad ledger suite checks verified boosts, saved progress and payout totals. The HUD suite uses a graphics renderer to check the three-button row, physical touch bounds and state artwork. The video-flow suite uses graphics and a test-only provider to verify pending-video pause gates and current-carpet payouts.

The gym check exercises Settings entry/dismissal, both rug selectors, tool restrictions, reset and transition cancellation, touch input, portrait/landscape layouts, and preservation of the existing paid rug/save. It captures both exercises under `art/renders/`. Use the graphics renderer for this check.

Run `validate_rug_transition.gd`, `validate_dirt_pool.gd`, `validate_brush_recycling.gd`, `validate_coin_rewards.gd` and `validate_cleaning.gd` with the graphics renderer and the same isolated-save arguments for transitions, resource reuse, demand-driven debris recycling, wallet animation and input regressions. The headless dummy renderer does not preserve MultiMesh instance data. Logs and captures are under `art/`; see [implementation coverage](design/Implementation_Coverage.md) for which evidence supports each feature.

`tools/assemble_workshop.gd` rebuilds authored scene content; it is not needed for ordinary play or tests. It replaces the generated workshop scene, so only run it intentionally. Reload external changes in Godot, or restart the editor if a cached MultiMesh reports an instance-format warning.
