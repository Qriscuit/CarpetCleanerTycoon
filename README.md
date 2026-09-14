# Mint Meadow — carpet cleaning prototype

## Current design and economy

The brush-first metagame is documented in [GDD v0.2](Carpet_Cleaner_Tycoon_GDD_v0_2.docx) and [Economy workbook v0.2](Carpet_Cleaner_Economy_v0_2.xlsx). The Neighborhood Shop is now playable: paid rugs, permanent blueprints, item builds, Bonzi automation, optional upgrades, and saved progress. Later shops remain design proposals. The editable design source is [design/Metagame_v0_2.md](design/Metagame_v0_2.md); its “not implemented” passages describe the earlier baseline. The v0.1 GDD remains historical context.

Open **Open Godot Project.lnk**, then press **F5**. The main scene is `CarpetToy/scenes/shop_hub.tscn` (`ShopHub`). Its **Rug Cleaning Gym** button opens the existing `RugCleaningGym` test scene. Customer jobs use that cleaning scene in a separate paid mode.

## Neighborhood Shop

The outside hub has four menus: **Shop**, **Items**, **Blueprints**, and **Bonzi**. UI controls and grouped artwork are saved in editable Godot scene hierarchies. See [Editing UI in Godot](design/Editing_UI_in_Godot.md) for scene locations, page previews, moving elements, shared styles and live text templates. Menus support mouse and touch; a swipe over a build button scrolls without purchasing. The Clean/Resume action stays available beneath scrolling pages, and purchases show their cost and cash remaining before confirmation.

Start with a free shop, hand brush and 0 cash. **Clean a rug** starts one resumable customer job. Clear at least 90% of unique debris **and** 90% of surface dust, then choose **Finish job** for 20 cash exactly once. Leaving for the shop preserves the rug. The gym is free practice and never grants money. Paid jobs use owned tools; building the Wide Brush gives its visible model and real cleaning footprint 44% more width.

| Build | Blueprint milestone | Cash | Effect |
| --- | --- | --- | --- |
| Bonzi | 3 customer rugs | 100 | Routine lane: 30 completed orders/hour at 10 cash each |
| Wide Brush | 8 customer rugs | 80 | Wider manual brush |
| Bonzi Mk II | 10 customer rugs + Bonzi | 120 | Capacity 30 → 45/hour; initial demand caps output at 40 |
| Welcome Sign | 10 customer rugs + Bonzi | 100 | Demand 40 → 60/hour; with Mk II output becomes 45 |

Bonzi's lane continues during manual cleaning and across menu changes. Orders pay when completed; fractional order progress carries forward. Return earnings use the same rates, capped at eight hours per absence. The return summary shows money already credited. Blueprint ownership is permanent; built personal tools and branch modules cannot be purchased twice. High Street is a clearly marked preview, with no purchase enabled. Wet cleaning and additional shops are future work.

Versioned JSON saves live at Godot's `user://neighborhood_shop_v1.json`. Purchases, paid jobs and routine deliveries are committed atomically. Failed writes roll back transactions; unreadable or unsupported saves are preserved. Local time supports this prototype's offline production, without an anti-cheat claim.

Implementation: `scenes/shop_hub.tscn`, `scenes/ui/`, `resources/ui/mint_theme.tres`, `scripts/shop_hub.gd`, `scripts/ui/`, and `scripts/shop_state.gd`; paid mode and snapshots are in `scripts/workshop.gd` and `scripts/dirt_controller.gd`. Rug variants are reusable resources under `resources/rugs/`. Both owned brushes can be equipped in Items, with selection persisted across sessions. Cleaning completion has direct Next rug and Visit shop actions.

Run the three management checks with the portable Godot executable and `--path CarpetToy --script ../tools/validate_shop_state.gd -- --shop-test`, then substitute `validate_contract.gd` and `validate_shop_ui.gd`. `--shop-test` isolates saves from player progress. The state suite supports `--headless`; the contract and menu suites use the graphics renderer. Menu captures are `art/renders/shop_*.png`; paid-job captures are `art/renders/contract_*.png`.

## Current feel pass

The rug is centered at world (0,0,0), with 560 latent clumps. Positions are independently scattered with natural gaps and clusters, with randomized width, depth, height, rotation and shade. Only 25 randomly selected clumps start as visible small rocks at varied scales; the rest start at 2.5% scale. The scatter is fixed on Reset for repeatable playtesting. Contact grows a clump to its full size over approximately 0.18 seconds, then launches it. It never grows beyond 1.0 or repeats its growth until reset. A pale warm dust blend at 58% strength leaves the pattern visible before cleaning.

Surface cleaning takes two passes: the first removes half the dust opacity and the second restores the original material in the brush's core. The boundary is softly feathered. Many mouse/touch events in one pass do not multiply cleaning. Release and drag again, or reverse direction for at least 8 cm while holding, to begin another pass. The soft fringe of a stroke blends gradually rather than ending in a hard cut.

Density is set by CLUMP_COUNT in tools/assemble_workshop.gd. The dust_strength and dust_tint uniforms in soil_surface.gdshader control surface appearance. The dirt mesh totals 11,200 triangles in one batch; active flags avoid searching the moving-clump list for every brush contact.

## Play

Choose **Brush**, **Squeegee**, or **Jet spray** using the illustrated, labeled buttons at the top-right in practice. Wet tools are marked as previews. The selected button stays highlighted and only its model is shown. Switching preserves the working contact point and ends any current drag. Hold the left mouse button or one finger and drag to position the equipped item. Brush bristles and the squeegee blade touch the surface; the jet nozzle points downward with 14 cm of clearance. Each tool follows the rug or surrounding tile height. Reset preserves the chosen tool.

With the brush selected, sweep beyond the carpet edges to throw dirt onto the surrounding white tiles. Strokes fling clumps mainly along positive/negative Z, with a small X spread; stroke speed affects throw strength.

Cleanliness is the percentage of unique clumps swept completely outside the rug and landed on the tiles. Each clump awards progress only once. A rounded cream card displays a filling bar with the percentage following its leading edge underneath; both transition from red through yellow and green to blue with a soft matching glow. Completion now requires 100% (all 560 clumps). Dirt lifts into the air and accelerates toward an invisible suction point above the screen over 1.8 seconds; the remaining surface dust fades away. Tool input is locked during completion. The finished carpet stays in place; coins and carpet transitions are future work. Gameplay uses a closer overhead camera, with no bottom controls. Reset remains available through the internal `reset_rug()` method for testing.
Touch uses a 72 viewport-pixel offset above the finger. A single finger owns the stroke. Releasing over UI, touch cancellation, switching tool and losing focus stop dragging. Clicking to place the brush does not sweep a path from its previous location. Tool buttons handle real touch taps while mouse emulation remains disabled. Squeegee and jet spray selection and positioning are implemented; their water/wiping effects are still future gameplay, and they do not invoke the brush's cleaning behavior.

## Mobile-conscious implementation

- Dirt: 560 instances of one 20-triangle mesh in one `MultiMeshInstance3D`; no rigid bodies, individual collision nodes or particle emitters. Only moving clumps receive simple gravity/slide updates at the physics tick. Simulation stops when they settle. Visible clumps are compacted into the existing batch on changes; off-screen instances are not submitted, while their simulation positions and earned credit remain intact. This reduces submitted geometry, not the already-single dirt draw call. Camera resizing refreshes visibility. The completion animation sleeps after finishing.
- Carpet: one opaque shader per existing mesh blends clean and dusty albedo using a 256 × 416 single-channel opacity mask (104 KiB). It updates only when stroke pixels change, at most once per rendered frame. Three CPU float arrays track coverage and the maximum contribution per pass (about 1.22 MiB). There is no extra transparent carpet layer.
- Brush contact: swept rectangle checks catch clumps between distant mouse/touch events. Clearance intersects the clump's scaled convex footprint with the rounded binding and 26 individual fringe silhouettes; empty corners and tassel gaps count as outside. Bounds checks reject distant polygons before intersections. Points and strokes are converted into rug-local coordinates.
- Floor: 576 shallow ceramic slabs with real bevel geometry and grout gaps, using one static MultiMesh batch. White material keeps the established soft studio lighting on the tools.

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

The original carpet-only inspection scene remains `CarpetToy/scenes/carpet_studio.tscn`; its Turntable/Top/Reset controls are separate from gameplay. `CarpetToy/scenes/carpet.tscn` provides the original reusable clean rug and coarse collider.

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

Validation log: `art/cleaning_validation.log`. Updated renders: `art/renders/starter_workshop_dirty.png`, `cleaning_partial.png`, and `cleaning_complete.png`.

Edge re-entry regression: run Godot with `--path CarpetToy --script ../tools/validate_dirt_reentry.gd`. It covers both fringe edges, rebrushing returned dirt, persistent completion, unique progress credit and idle sleep. Log: `art/dirt_reentry_validation.log`.

Feel checks: run Godot with `--path CarpetToy --script ../tools/validate_feel.gd`. It verifies two-pass opacity, frame-independent pass strength, feathered edges, reversal passes, one-time growth, origin placement, rounded corners, fringe gaps, the 100% threshold, reset, overhead camera locking and progress colors. Log: `art/feel_validation.log`. Comparison renders: `art/renders/two_pass_first.png`, `two_pass_second.png`, and `cleanliness_meter_0.png` through `cleanliness_meter_3.png`.

Tool selection checks: run Godot with `--path CarpetToy --script ../tools/validate_tool_selection.gd`. It dispatches mouse and real touch events to each button, verifies exclusive selection, actual mesh contact heights, floor placement, switching during drags, reset behavior and top-view touch placement. Log: `art/tool_selection_validation.log`. Pose renders: `art/renders/equipped_0.png`, `equipped_1.png`, `equipped_2.png`.

UI / vacuum checks: run Godot with `--path CarpetToy --script ../tools/validate_vacuum.gd`. Covers actual sweeps to 100%, lift then suction, off-screen culling and re-entry, one-shot completion, idle sleep, and reset during/after suction. Captures: `art/renders/vacuum_midpoint.png` and `vacuum_complete.png`. Desktop graphics validation passed; mobile GPU performance has not been benchmarked.
