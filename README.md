# Mint Meadow — carpet cleaning prototype

## Android APK

Save your game changes and double-click **Build APK.cmd**. It uses the bundled standard Godot 4.7.2, checks dependencies, exports a signed debug APK, verifies its signature, and writes **build/CarpetCleaner.apk**. Use **Open Game Editor.cmd** to open the matching editor. See [APK recovery checklist](design/Android_APK.md) for exact SDK paths and fixes for template, SDK, and signing errors.

## Floating shop main menu

Press **F5** to launch `CarpetToy/scenes/production/floating_home.tscn`, the light-blue main menu. Pressing the 3D shop squashes it, then releases with a small pop before starting/resuming a rug. The dock opens compact **Shop**, **Tools**, **Plans**, and **Bonzi** sheets. They show short item/status rows and review price, benefit and remaining cash before any purchase. It adapts to portrait and landscape with safe-area layout. Editable assets are in `art/blender/floating_shop.blend`; exports are in `CarpetToy/assets/floating_shop/`. See [floating home implementation](design/home-screen/IMPLEMENTATION.md) for editing, rebuilding, and validation details. Desktop layout/input checks pass; mobile device testing remains outstanding.

## Current design and economy

Production entry scenes live in `CarpetToy/scenes/production/`; the old menu, free gym, and art previews live in `CarpetToy/scenes/test/` and are excluded from Android builds. Both rug Home buttons always open the floating main menu. See [scene layout and navigation](design/Scene_Navigation.md) for the routing rules and regression check.

The brush-first metagame is documented in [GDD v0.2](Carpet_Cleaner_Tycoon_GDD_v0_2.docx) and [Economy workbook v0.2](Carpet_Cleaner_Economy_v0_2.xlsx). The Neighborhood Shop is now playable: paid rugs, permanent blueprints, item builds, Bonzi automation, optional upgrades, and saved progress. Later shops remain design proposals. The editable design source is [design/Metagame_v0_2.md](design/Metagame_v0_2.md); its “not implemented” passages describe the earlier baseline. The v0.1 GDD remains historical context.

Open **Open Godot Project.lnk**, then press **F5** for the floating main menu. The original detailed hub remains available at `CarpetToy/scenes/test/shop_hub.tscn` for development and practice-gym access. Customer jobs use the production `rug_cleaning.tscn` scene; the free gym inherits its cleaning world.

## Neighborhood Shop

Bonzi's bar shows its actual reward and cycle: **10 coins every 120s**, **90s** with Mk II, or **80s** with both automation upgrades. Coins arrive once per finished bar. In the main menu, **Settings → Reset progress → Reset** starts fresh after confirmation; **Keep playing** cancels. Reset removes earned coins, items, milestones and the active rug while preserving the free starter brush.

The floating home routes **Shop** to upgrades, **Tools** to brush equipment, **Plans** to blueprint progress, and **Bonzi** to automation and income. The building is the primary clean/resume action. Close a sheet or press Back/Escape to return home; Back dismisses a purchase review first. Controls and cards are saved in editable scene hierarchies. Menus support mouse and touch; a swipe over a build button scrolls without purchasing.

Start with a free shop, hand brush and 0 cash. Tapping the floating store opens one resumable customer rug in the separate cleaning scene. Its single percentage is the lower of debris clearance and surface-dust clearance. **Finish job** appears at 85%; finishing below 99% pays **20 coins**, while reaching 99% finishes automatically and pays **40 coins**. Both layers must meet the reward threshold. The reward and the next rug are committed in the same save transaction. Earlier economy assumptions based on 20 coins per manual rug still describe early finishes.

Debris is sucked away and the clean rug rolls out. A reusable 2D coin burst lingers briefly, then flies into the persistent gold wallet at the top-right. Each arriving coin adds its exact value to the displayed total; the saved balance already includes the whole reward. Leaving or interrupting the animation cannot duplicate or lose earnings. There is no new-rug prompt or scene reload between jobs. The icon Back control remains available during every transition and preserves the current rug or the already-reserved next job. The inherited test gym is free practice and never grants money. Paid jobs use owned tools; building the Wide Brush gives its visible model and real cleaning footprint 44% more width.

The cleaning window's **Upgrade** button opens a centered placeholder menu; purchases are not available there yet. Opening it pauses brushing, dirt motion and rug transitions. Close or Back dismisses it and resumes the same rug phase.

| Build | Blueprint milestone | Cash | Effect |
| --- | --- | --- | --- |
| Bonzi | 3 customer rugs | 100 | Routine lane: 30 completed orders/hour at 10 cash each |
| Wide Brush | 8 customer rugs | 80 | Wider manual brush |
| Bonzi Mk II | 10 customer rugs + Bonzi | 120 | Capacity 30 → 45/hour; initial demand caps output at 40 |
| Welcome Sign | 10 customer rugs + Bonzi | 100 | Demand 40 → 60/hour; with Mk II output becomes 45 |

Bonzi's lane continues during manual cleaning and across menu changes. Orders pay when completed; fractional order progress carries forward. Return earnings use the same rates, capped at eight hours per absence. The return summary shows money already credited. Blueprint ownership is permanent; built personal tools and branch modules cannot be purchased twice. High Street is a clearly marked preview, with no purchase enabled. Wet cleaning and additional shops are future work.

Versioned JSON saves live at Godot's `user://neighborhood_shop_v1.json`. Purchases, paid jobs and routine deliveries are committed atomically. Failed writes roll back transactions; unreadable or unsupported saves are preserved. Local time supports this prototype's offline production, without an anti-cheat claim.

Implementation: `scenes/test/shop_hub.tscn`, `scenes/ui/`, `resources/ui/mint_theme.tres`, `scripts/shop_hub.gd`, `scripts/ui/`, and `scripts/shop_state.gd`; paid mode and snapshots are in `scripts/workshop.gd` and `scripts/dirt_controller.gd`. Rug variants are reusable resources under `resources/rugs/`. Both owned brushes can be equipped in Items, with selection persisted across sessions. Cleaning completion automatically carries the player into the next rug, while the icon Back control can return to the main menu at any time.

Run the three management checks with the portable Godot executable and `--path CarpetToy --script ../tools/validate_shop_state.gd -- --shop-test`, then substitute `validate_contract.gd` and `validate_shop_ui.gd`. `--shop-test` isolates saves from player progress. The state suite supports `--headless`; the contract and menu suites use the graphics renderer. Menu captures are `art/renders/shop_*.png`; paid-job captures are `art/renders/contract_*.png`.

## Current feel pass

The rug rolls in from below the screen already carrying its dirt texture and unrolls at world (0,0,0). After it settles, 25 small starter rocks grow from nothing at randomly scattered positions, then the brush slides in and cleaning input becomes available. The same scene, rug meshes and 560-slot GPU dirt pool serve every subsequent rug. Each refill randomizes the clump positions while retaining the existing clump shapes, materials and resources. The remaining slots stay invisible until brushed out of the dust. Reset preserves that rug's scatter for repeatable playtesting. Contact grows a clump to its full size over approximately 0.18 seconds, then launches it. It never grows beyond 1.0 or repeats its growth until reset. The pale warm dust blend stays at 58% strength throughout arrival; it does not fade in with the rocks.

Surface cleaning takes two passes: the first removes half the dust opacity and the second restores the original material in the brush's core. The boundary is softly feathered. Many mouse/touch events in one pass do not multiply cleaning. Release and drag again, or reverse direction for at least 8 cm while holding, to begin another pass. The soft fringe of a stroke blends gradually rather than ending in a hard cut.

Density is set by CLUMP_COUNT in tools/assemble_workshop.gd. The dust_strength and dust_tint uniforms in soil_surface.gdshader control surface appearance. The dirt mesh totals 11,200 triangles in one batch; active flags avoid searching the moving-clump list for every brush contact.

## Play

Equip an owned brush in the main menu's **Tools** sheet. Once the rug has unrolled, the dirt has appeared and the brush has entered, hold the left mouse button or one finger and drag to brush. The bristles follow the rug or surrounding tile height. Practice tool selection remains available through test code; there are no tool-picker buttons in the cleaning window.

With the brush selected, sweep beyond the carpet edges to throw dirt onto the surrounding white tiles. Strokes fling clumps mainly along positive/negative Z, with a small X spread; stroke speed affects throw strength.

The single bar reports the lower of debris clearance and surface-dust clearance, with its percentage centered inside. Each clump awards debris progress only once; both layers must reach 85% for **Finish job** or 99% for automatic completion. Early finishes pay 20 coins; 99% or higher pays 40. The bar transitions from red through yellow and green to blue with a matching glow. On completion the brush disappears, dirt lifts and accelerates toward suction above the screen over 1.8 seconds, and remaining surface dust fades away. The clean carpet then rolls up and exits before the same scene presents the next rug. Reward coins briefly linger before flying into the persistent top-right wallet, which counts their values as they arrive. Input resumes after the replacement rug, starter rocks and brush finish entering. Reset remains available through the internal `reset_rug()` method for testing.

Touch uses a 72 viewport-pixel offset above the finger. A single finger owns the stroke. Releasing over UI, touch cancellation, switching tool and losing focus stop dragging. Clicking to place the brush does not sweep a path from its previous location. The cleaning HUD contains an icon Back control, the percentage bar, a persistent gold wallet, an **Upgrade** button and the conditional **Finish job** button. Actions use release-based touch handling while mouse emulation remains disabled. Back closes the Upgrade menu first; otherwise it returns to the main menu, including during arrival, suction and departure. Squeegee and jet spray model selection remains available to test code, but their water/wiping effects are future gameplay and they do not invoke the brush's cleaning behavior.

## Mobile-conscious implementation

- Dirt: a fixed pool of 560 instances of one 20-triangle mesh in one `MultiMeshInstance3D`; no rigid bodies, individual collision nodes or particle emitters. The same slots, mesh, mask texture and materials are reused for each rug, with a fresh scatter after takeaway. Only moving clumps receive simple gravity/slide updates at the physics tick. Simulation stops when they settle. Visible clumps are compacted into the existing batch on changes; off-screen instances are not submitted, while their simulation positions and earned credit remain intact. This reduces submitted geometry, not the already-single dirt draw call. Camera resizing refreshes visibility. The completion animation sleeps after finishing.
- Carpet: one opaque shader per existing mesh blends clean and dusty albedo using a 256 × 416 single-channel opacity mask (104 KiB). It updates only when stroke pixels change, at most once per rendered frame. Three CPU float arrays track coverage and the maximum contribution per pass (about 1.22 MiB). There is no extra transparent carpet layer.
- Brush contact: swept rectangle checks catch clumps between distant mouse/touch events. Clearance intersects the clump's scaled convex footprint with the rounded binding and 26 individual fringe silhouettes; empty corners and tassel gaps count as outside. Bounds checks reject distant polygons before intersections. Points and strokes are converted into rug-local coordinates.
- Floor: 576 shallow ceramic slabs with real bevel geometry and grout gaps, using one static MultiMesh batch. White material keeps the established soft studio lighting on the tools.
- Reward coins: reusable 2D visuals briefly linger, then travel to the wallet. Their arrivals update only the displayed balance; the ledger awards the whole 20- or 40-coin reward once before the animation begins.

Android APK export and device performance are not yet tested. Clumps do not collide with one another or the two display tools; their motion is an inexpensive visual simulation.

## Code and assets

- Input, brush positioning and UI: `CarpetToy/scripts/workshop.gd`
- Clump motion, progress and cleaning mask: `CarpetToy/scripts/dirt_controller.gd`
- Surface blend: `CarpetToy/scripts/soil_surface.gdshader`
- Rounded rug and fringe boundary: `CarpetToy/scripts/rug_footprint.gd`
- Tile scene: `CarpetToy/scenes/tiled_floor.tscn`
- Scene authoring: `tools/assemble_workshop.gd`
- Blender carpet source: `art/blender/mint_meadow.blend`
- Blender tools source: `art/blender/starter_tools.blend`
- Portable GLBs: `CarpetToy/assets/carpet/` and `CarpetToy/assets/tools/`

The original mint/cream/coral rug has 3,176 triangles across binding, pile and fringe. Its body measures 2 × 3 m; fringe extends to about 3.32 m. Albedo and woven normal maps are 1024 × 1536. The brush has 2,108 triangles, squeegee 500 and jet spray 868; each tool has one mesh surface and palette material. Source generation scripts are `tools/build_carpet.py` and `tools/build_tools.py`.

The original carpet-only inspection scene remains `CarpetToy/scenes/test/carpet_studio.tscn`; its Turntable/Top/Reset controls are separate from gameplay. `CarpetToy/scenes/carpet.tscn` provides the original reusable clean rug and coarse collider.

## Rebuild and verify

Use the portable standard Godot executable in `tools/godot/`. The previous desktop .NET build required a missing .NET SDK; this GDScript project does not need it.

From this workspace in PowerShell:

```powershell
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/assemble_workshop.gd
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_cleaning.gd
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_workshop.gd
```

Use the graphics renderer for scene assembly and MultiMesh validation: the installed headless dummy renderer does not preserve saved instance buffers. Rebuilding replaces the authored workshop scene. Reload external changes in Godot; if its resource hot-reloader logs an instance-format warning, restart the editor to clear its old cached MultiMeshes.

`validate_cleaning.gd` checks mouse/touch projection, slow and fast strokes, both fling directions, touch ownership, release/focus handling, tile and carpet contact heights, whole-clump clearance, full-560 clearance, reset and idle sleep. `validate_brush_input.gd` forwards to this suite. Live mouse sweeps were also verified in the local editor.

Run `validate_rug_transition.gd` and `validate_dirt_pool.gd` with `--path CarpetToy --script ../tools/<suite>.gd -- --shop-test` using the graphics renderer. The transition suite exercises the production roll-in, dirt growth, brush entry, suction, departure, reward and next-rug sequence, plus Back during transitions. The pool suite checks resource identity across twelve refills, randomized scatter, saved-state restoration and reveal behavior. Both require the renderer because their assertions use MultiMesh data. The existing contract, vacuum, cleaning, feel, dirt re-entry, tool-selection and editable-HUD suites set `animate_rug_changes = false` before entering the scene so their physics, input and save checks remain independent of animation timing; production defaults to animated transitions.

Run `validate_coin_rewards.gd` with the same renderer and isolated-save arguments to check both reward amounts, exact per-coin increments, automation income during flight, phone rotation, safe areas, the Upgrade modal, save failure, and leaving during a celebration. Its screenshots are `art/renders/coins_*.png`.

Validation log: `art/cleaning_validation.log`. Updated renders: `art/renders/starter_workshop_dirty.png`, `cleaning_partial.png`, and `cleaning_complete.png`.

Edge re-entry regression: run Godot with `--path CarpetToy --script ../tools/validate_dirt_reentry.gd`. It covers both fringe edges, rebrushing returned dirt, persistent completion, unique progress credit and idle sleep. Log: `art/dirt_reentry_validation.log`.

Feel checks: run Godot with `--path CarpetToy --script ../tools/validate_feel.gd`. It verifies two-pass opacity, frame-independent pass strength, feathered edges, reversal passes, one-time growth, origin placement, rounded corners, fringe gaps, combined progress, reset, overhead camera locking and progress colors. Log: `art/feel_validation.log`. Comparison renders: `art/renders/two_pass_first.png`, `two_pass_second.png`, and `cleanliness_meter_0.png` through `cleanliness_meter_3.png`.

Tool selection checks: run Godot with `--path CarpetToy --script ../tools/validate_tool_selection.gd`. It verifies the hidden picker, selection through gameplay code, exclusive model visibility, actual mesh contact heights, floor placement, switching during drags, reset behavior and top-view touch placement. Log: `art/tool_selection_validation.log`. Pose renders: `art/renders/equipped_0.png`, `equipped_1.png`, `equipped_2.png`.

UI / vacuum checks: run Godot with `--path CarpetToy --script ../tools/validate_vacuum.gd`. Covers the 85% Finish action, lift then suction, off-screen culling and re-entry, automatic practice-rug replacement, idle sleep, and reset during suction. Desktop graphics validation passed; mobile GPU performance has not been benchmarked.
