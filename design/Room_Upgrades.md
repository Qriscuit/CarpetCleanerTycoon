# In-level workshop upgrades

Implementation checklist for the engineering, design and asset pass:

- [x] Hover the brush 0.24 m above its working position when released.
- [x] Lower it on finger/mouse contact; lift it after release, canceled input, focus loss or opening a panel.
- [x] Keep contact/raking calculations on the carpet plane so lifting cannot clean the rug.
- [x] Use an adjustable production camera angle, currently 20 degrees from top-down with zero yaw for a straight view, and fit the entire room in the HUD's available screen area.
- [x] Author five clickable room features, each with an independent price and earnings ladder capped by its place.
- [x] Spread the three authored makeovers across each place's total levels; retain the current model between milestones.
- [x] Replace the bottom earnings purchase button with direct taps on the room.
- [x] Remove the bottom 75%/full-rug earnings readout and use its space for the diorama.
- [x] Show the selected feature, level, cost, progress toward its next transformation and one current/next Clean earnings value.
- [x] Update the current rug's earnings after a durable purchase, then animate the selected object and reveal any earned model at the compressed midpoint.
- [x] Add a circular white ring and a gently undulating white pillar fading from full alpha at its base to transparent at its top.
- [x] Preserve existing earnings investments, dirt progress and per-store saves.
- [x] Cover tap, drag, multi-touch cancellation, unaffordable offers, save rollback and phone layout.

## Model progression

| Feature | Baseline | First makeover | Second makeover | Third makeover |
| --- | --- | --- | --- | --- |
| Floor | Concrete | Maple planks | Mint checker tile | Pearl terrazzo with brass inlay |
| Corner garden | Bare pots | Little sprouts | Leafy stems | Coral flowers |
| Window | Timber frame | Painted frame | Arched trim | Brass sunroom |
| Railings | Timber rails | Mint slats | White balusters | Brass accents |
| Walls and door | Simple plaster | Mint wainscot | Ivory stone | Brass gallery |

The open-front workshop uses warm timber, mint paint, ivory, coral flowers and brass. All 20 main variants are editable mesh groups in `CarpetToy/scenes/room/upgrade_room.tscn`. The generator is `tools/generate_room_upgrades.gd`; gameplay selects the model from the accessory's actual authored milestone list for the current place. There are three upgraded models per feature, with no repeated finish labels or promised mesh changes after the final real model. Neighborhood's 50-level ladder changes its model at 15, 30 and 45; Royal Gallery's 175-level ladder changes at 50, 100 and 150. The rear wall surrounds the existing window's unobstructed rolling aperture; the right return holds an outward-ajar door. The four corner pots share one garden ladder, and both railings share another. The carpet and fringe retain a protected interaction region.

## Economy and interaction

Every feature has its own saved level, price curve and income contribution. Buying the floor never changes another feature's level or next price. The wallet is shared, and the full-clean reward is the sum of the store's base earnings and all five independently earned contributions.

Bonzi earns that same full-clean reward for every completed order in this store, including live and offline production. All five feature upgrades raise both quotes together; other stores retain their own reward. Bonzi's upgrades shorten its cycle from 120 to 90 to 60 seconds. A room purchase settles completed orders at the prior quote before applying the increase to future completions.

| Feature | First price in Store 1 | Price growth per local level | First full-clean income gain | Income growth per local level |
| --- | ---: | ---: | ---: | ---: |
| Corner garden | 25 | Place-specific geometric factor | +4 | Place-specific geometric factor |
| Floor | 40 | Place-specific geometric factor | +6 | Place-specific geometric factor |
| Window | 60 | Place-specific geometric factor | +8 | Place-specific geometric factor |
| Railings | 35 | Place-specific geometric factor | +4 | Place-specific geometric factor |
| Walls | 50 | Place-specific geometric factor | +6 | Place-specific geometric factor |

The store scales are 1, 10⁴, 10⁷, 10¹¹, 10¹⁶ and 10²³. Each place solves its geometric growth factor from its accessory level cap and final full-clean reward, so the first place ends at 400 K and the sixth reaches 400 AF. Costs depend only on the selected accessory's level. Cumulative rounded earnings contributions share the cap in proportion to first gains, with final rounding residue assigned to walls. All five completed accessories reach the exact store ceiling. [First_Shop_Balance.md](First_Shop_Balance.md) gives the six places, formulas and travel gates.

Accessory caps are 50, 75, 100, 125, 150 and 175 across the six places. Spread model changes using the actual number of upgrade meshes: 50 levels/five upgraded meshes yields 10/20/30/40/50; 175 levels/three meshes yields 50/100/150. The current three upgraded meshes use 15/30/45, 25/50/75, 30/60/90, 40/80/120, 50/100/150 and 50/100/150 respectively. The baseline mesh is separate from the number of upgrades.

The bar counts purchases toward the next real model change, resets at each change and remains full after the last available mesh. Remaining levels improve earnings with the final mesh retained. The level label and purchase action end only at the accessory's store cap. Home offers the same five ladders.

A store's mastery requires all five capped accessories, its final brush, final Bonzi tier, three paid rugs using that brush and its local Bonzi earnings target. Mastery gates the next place; all six mastered places complete the first section. Additional sections remain unavailable until their content is authored. All six current places use brush cleaning.

Legacy generic investments retain their round-robin mapping to the original four features; walls start at 0. Room rules version 4 remaps historical 5/10/15 model milestones onto the corresponding new milestones, and maps the old refinement tail through 120 into the remaining local levels. Fully purchased old accessories remain complete. Wallet coins, ownership, active rug and dirt are preserved; future earnings and the unpaid quote rebase to the new store ceiling. A historical first-shop AF reward becomes at most 400 K. The rules marker prevents repeated migration. `payout_level` remains a derived compatibility count.

Room panels pause cleaning and water effects. Touch purchases commit on release; swipes, canceled gestures and extra fingers cannot buy. The panel's purchase/close controls stay fixed while its details can scroll on short screens. Back/Escape or a tap outside the floating card closes it before returning to cleaning. The remaining brush/tool button still opens tool improvements.

## Purchase motion and VFX

Every successful in-level purchase plays a 0.90-second animation, including non-milestone levels. A single purchase squeezes at 0.18 seconds, stretches tall at 0.38 seconds, then widens gently and settles to its exact authored transform. At a milestone, the new model replaces the old one at the compressed point and continues the same animation. Repeated purchases add a bounded bounce from the current pose, rather than snapping the object back to its starting pose. Each plant tier retains its fixed root; cached vertex materials deform each pot and its foliage around that pot's authored saucer foot. The four corner positions stay fixed, including during milestone swaps and rapid retriggers, and the normal foliage breeze continues. Original materials and culling margins restore after the pulse. The floor uses particularly subtle decoration-only scaling; the carpet, cleaning masks, foundation and interaction footprint do not move.

A white circular ground ring surrounds the selected footprint. An upright, unshaded white cylinder rises from the same base; alpha and emission decrease continuously with height, reaching zero alpha at the top. Its radius and surface gently undulate. Both effects fade in and out through the purchase motion. They use reusable meshes and one effect instance per feature, with no per-frame resource creation or fluid simulation.

Buy remains available during feedback whenever the next durable offer is affordable and coin collection has finished. Each released tap purchases exactly one level and immediately updates the price, earnings preview and milestone count. The glow stays visible and each tap adds another tall-then-wide bounce; one reusable animation and effect per feature keep rapid tapping bounded. Milestone swaps run independently of retriggers so continuous tapping cannot indefinitely delay the latest model or finish. Insufficient coins and a completed accessory still disable Buy. Closing the card does not cancel the visual reward or block another feature's offer. Focus loss pauses both object motion and shader waves, and reset/scene exit cancels the effect and restores exact transforms. A failed save spends no coins and adds no success pulse; any previous successful purchase continues its feedback. Existing opening-window hinges and completion foliage breeze remain independent.

## Review and validation

Use only the pinned Godot 4.7.2 stable Mono bundle through `tools/run_godot.ps1`. PowerShell callers should pass an argument array so the literal `--` separator reaches Godot.

Focused checks: `validate_room_upgrades.gd` (models and store-specific milestones), `validate_room_economy.gd` (independent prices/income, migration, save rollback and caps), `validate_room_interaction.gd` (input/UI), `validate_room_upgrade_vfx.gd` (animation, focus pause, reset and reusable effects), `validate_rapid_room_upgrades.gd` (real rapid touches, current quotes and purchase safety gates), `validate_home_room_ladders.gd` (real Home-sheet touches and phone layouts), and `validate_brush_lift.gd`. All gameplay runs require `-- --shop-test`. Add `--room-capture` to room interaction validation to render the starting workshop, individual offers, phone layouts and final tiers into `art/renders/`.

`validate_bonzi_earnings.gd` checks shared full-clean rewards, all five room purchases, Bonzi speed tiers, independent stores, offline income, save rollback and wallet limits. `validate_bonzi_earnings_ui.gd` checks actual Bonzi-sheet touches and dynamic reward previews in portrait and landscape; `--bonzi-earnings-capture` saves both layouts.

`tools/preview_room_upgrades.gd` opens a disposable workshop with 5,000 test coins for hands-on review; it requires `-- --shop-test` and never uses the player's save. Mobile device performance and physical touch feel still need a device playtest.

## Completion motion pass

- Keep the configured cleaning camera angle, currently 20 degrees from top-down with zero yaw. Portrait moves in by only 10%, keeping the whole rug and fringe visible. Landscape retains the carpet's cleaning scale and frames the full room beside the lower-right Compare button.
- Blur the world gently during the 0.42-second camera move; the small Compare button stays sharp. The design is sharp throughout the appreciation/compare pause.
- Pull back through a 0.42-second blur to show the room and open window tips.
- Open both window casements outward over 0.42 seconds before curling the rug. All four frames and their casements stand upright; each leaf rotates around its complete vertical side edge, keeping both endpoints attached and staying above the floor. Every tier has an unobstructed 2.754 m opening for the unchanged 2.12 m-wide rug.
- Curl the rug over 0.65 seconds with a small 0.13 m lift over the sill, then move it through the window over 0.46 seconds. Once the rug has cleared, ease the camera back to its exact cleaning frame over 0.42 seconds while the window closes. The replacement rolls into a stationary view.
- Begin the departure camera move from the actual current frame, including internal continuation during the reveal zoom. Keep the same scene and dirt batch between rugs; never switch camera framing instantaneously at the replacement boundary.
- Add a four-second, fading breeze to leaves, stems and flowers. Weighted vertex deformation bends the foliage while pots stay fixed; no skeleton or Blender dependency is needed.
- Clear blur and reset room motion on reset, Back and replacement. Focus loss pauses completion motion; holding Compare immediately gives a sharp, still view.

Animation checks: `validate_completion_focus.gd`, `validate_room_animation.gd`, `validate_window_edge_hinges.gd`, `validate_completion_choreography.gd`, and the existing `validate_completion_reveal.gd`. The hinge check samples the actual side-stile vertices and full hinge line through outward opening and closing, checks floor/corridor clearance and exact reset, and renders closed/half/open poses with `--window-hinge-capture`. The integrated completion check samples the actual roll deformation for aperture clearance and verifies all four window tiers. Add `--window-only` to the generator's isolated-save arguments to rebuild the window while retaining the other saved room assets.

`tools/preview_completion_sequence.gd` automatically demonstrates a completion, then leaves a fresh rug playable using a disposable save. Add `--completion-video` and run Godot with `--fixed-fps 30` to capture frames for a review clip.

## Floating station offers

The visual reference is [Eatventure's station card](https://henamap.doorblog.jp/archives/19561973.html): a compact white panel placed near the station, bold level numbers, a blue progress bar and a prominent coin-cost button. The workshop version uses original editable SVG artwork and the game's ivory, mint, blue and brass palette.

- Place the card beside the actual selected item with a pointer connecting the offer to the room. Corner plants and both railings use the instance nearest the tap; floor taps use their own position. Reproject that point when the viewport changes.
- Keep the diorama visible behind the card. The transparent outside area still catches input so buying cannot accidentally brush the rug.
- Show the current and next level and one prominent `Clean 40 → 44` earnings row, using the full-restoration reward. Remove the transformation description, early/full earnings table and wallet row. The main action displays the exact next price from the save ledger.
- Show a 28-unit-tall blue bar with the selected feature's current purchases and interval toward its next real model. It advances only for that feature, resets after a model change, and remains full after its last available model. Remaining income purchases retain the completed model bar until the separate economic cap. Remove `COINS SAVED`, `Ready!` and next-look text.
- The normalized progress bar uses the ledger's `milestone_progress`, independently of wallet balance. The button still enables only when the durable offer is affordable and coin collection has finished. This introduces no extra currency or upgrade timer.
- Keep the floating card at 272 × 212 logical units. Show extra text only while collecting coins or when saving fails.
- Use compact placement above, below or beside the item, clamped to the device safe area. Retain reachable purchase and close controls on short screens.
- Fit the normal camera to the closed room's actual geometry inside the HUD's shared `workshop_view_rect()`. Portrait uses a compact progress/earnings header and bottom action row; landscape groups controls in a left column beside a full-height diorama. Finish has a permanent reserved slot, so appearing at 75% does not move the camera. Wallet text and hidden completion HUDs retain the same world reservation. The cart opens the tools and Bonzi shop. The configured angle is shared by cleaning, reveal and open-window departure.

## Responsive composition

The room instance uses .90 x/z scale with its original vertical scale. This widens the floor aisles around the unchanged 2.12 × 3.44 carpet; accessories, picking boxes and individual pot pivots follow the room transform. The camera's 20-degree pitch from top-down and zero yaw keep the view straight. Lowering the surrounding ground beneath the foundation exposes the miniature's plinth and shadow. No authored upgrade meshes or saved ladders change.

HUD spacing, progress height, action size, landscape column width and world gutter are inspector settings. `layout_metrics()` reports the safe area and UI/world rectangles in viewport coordinates; the camera fits authored room bounds to that world rectangle. Camera pitch and yaw are workshop inspector settings and use one basis throughout rug exchanges. Touch targets retain at least 44 physical pixels independently of the world viewport's reference resolution. This supports rotation, safe insets and new room proportions without hand-coded offsets for each device.

Validate with `tools/validate_floating_room_ui.gd` and `tools/validate_diorama_camera.gd`, plus the existing room interaction and completion checks. Add `--floating-capture` to the floating UI check for rendered examples. `tools/validate_rapid_room_upgrades.gd` checks real repeated touch purchases; `--rapid-upgrade-capture` renders the current, tall and wider poses with Buy still enabled. `tools/validate_rapid_upgrade_visuals.gd` stresses all five tracks through the place's level cap at 50 taps per second while checking current-pose continuity, latest finish, bounded resource reuse and exact settling. `tools/validate_camera_continuity.gd`, run at `--fixed-fps 30`, checks every rendered camera step across both normal and early-skip rug exchanges in portrait and landscape.
