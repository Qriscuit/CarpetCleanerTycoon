# Editing the game's UI in Godot

The UI is saved as real scene nodes. Playing the game binds live values and switches existing states while retaining those authored controls. The cleaning HUD also arranges its nodes responsively using the Inspector settings described below.

## Start here

**F5** starts `scenes/production/rug_cleaning.tscn` and opens or resumes the last selected store's carpet. **Back** opens `scenes/production/floating_home.tscn`; its dock sheets live in `scenes/ui/compact_shop.tscn`. Open the menu scene and use **F6** to preview it directly. See [scene navigation](Scene_Navigation.md) for production/test organization. The detailed hub instructions below apply to the retained legacy test menu.

Open `CarpetToy/project.godot`, then open `scenes/test/shop_hub.tscn` and select **2D**. Select the `ShopHub` root and change **Editor Page** in the Inspector to preview Shop, Items, Blueprints, Bonzi, or the future shop. These pages already exist under `Shell / Layout / Pages`; each has its own scroll container and content. Editor Page is only a preview choice for this legacy test menu.

| What to edit | Where |
| --- | --- |
| Production main menu and navigation | `scenes/production/floating_home.tscn` |
| Production shop sheets and purchase review | `scenes/ui/compact_shop.tscn` |
| Legacy test shop menus and cards | `scenes/test/shop_hub.tscn` |
| In-game progress, gold counter, coin effects and Upgrade menu | `scenes/ui/cleaning_hud.tscn` |
| Completion's single Compare button | `scenes/ui/completion_reveal.tscn` |
| Art-review scene buttons | `scenes/ui/studio_hud.tscn` |
| Storefront, Bonzi, brushes and other artwork | `scenes/ui/art/*.tscn` |
| Shared palette, typography, borders and button styles | `resources/ui/mint_theme.tres` |

The 3D rug scenes contain an editable `GymUI` instance. Expand it in the scene tree to edit its children in place, or open `cleaning_hud.tscn` to change the shared HUD. The carpet art-review scene similarly contains `StudioUI`.

## Move and resize things

Controls inside a `VBoxContainer` or `HBoxContainer` are arranged by that container. Reorder them in the scene tree; change **Custom Minimum Size**, **Container Sizing**, and the container's **Theme Overrides → Constants → Separation**. Change the `Shell` MarginContainer's margins for the outer safe spacing. These are native Godot layout rules, not a script undoing your changes.

The cleaning HUD uses a compact progress/earnings header above the room and an action row below it in portrait. In landscape, Back, the prominent wallet, status and actions form a left column beside the diorama. The row is cart `UpgradeButton`, teal video `AdRewardButton`, then plain **Finish**. `FinishJobButton` appears at 75%, using a slot reserved even while hidden. The video button shows a padlock without an available provider, a play symbol when ready, a waiting state during verification and a check when the current carpet's 2× boost is active. Styles and contents remain authored scene controls; runtime composition uses the HUD root's **Responsive Layout** Inspector settings.

Edit the tool comparison cards under `UpgradeSheet / UpgradesPanel / ShopContentsScroll / ShopColumns / Contents / ToolCardsScroll / ToolCards`. The adjacent `BonziContents / BonziCardsScroll / BonziCards` holds the authored current and next Bonzi artwork, earnings and cycle labels. Wide layouts place these two offers beside each other; narrow phones stack Bonzi below the tool and scroll the whole shop through `ShopContentsScroll`. Each offer's Buy button stays outside its comparison-card scroller. Done stays in the fixed `ShopHeading` above the body. Keep the scroll regions clipped so offscreen Buy buttons cannot receive taps. `UpgradeSheet` uses Z Index 50 above `Wallet` at 30; retain that order when adjusting the shop.

Bonzi shows the existing three-paid-carpet hiring gate, actual incremental cost, affordability and maximum speed. Its purchase uses the same saved store progression as management. A tap or click outside the shop closes it without cleaning the carpet underneath. Dragging, canceled gestures and a second finger cancel that dismissal; swiping across the shop scrolls its contents, including when the swipe begins on a button.

Change **Layout Edge**, **Layout Gap**, **Earnings Gap**, **Landscape Rail Width**, **Progress Max Width**, **Progress Height**, **Earnings Height**, **Action Height**, **Wallet Height**, **World Gutter** and **Landscape Aspect Threshold** to tune placement without device-specific offsets. `layout_metrics()` and `workshop_view_rect()` expose those same rectangles to the camera. Changing a child offset alone changes the editor snapshot, while these settings control the live responsive arrangement.

The same **Responsive Layout** group contains three sizing references:

| Setting | Default | What it controls |
| --- | ---: | --- |
| **Phone Portrait Width** | 390 | Logical short-side reference for elongated portrait screens |
| **Phone Landscape Height** | 360 | Logical short-side reference for elongated landscape screens |
| **Tablet Short Side** | 640 | Logical short-side reference for squarer screens |

Lower reference values make the HUD larger relative to the screen; higher values leave more space for the room. The layout blends from the tablet reference to the appropriate phone reference as the safe area's long-to-short-side ratio increases from 1.45 to 1.75. These are design references, independent of the display's native pixel resolution.

Current authored sizes below use HUD units before responsive scaling. Edit label typography in `cleaning_hud.tscn` through **Theme Overrides → Font Sizes**.

| Control | Current size | Text and artwork |
| --- | --- | --- |
| Back and cart | 56 × 56 | SVG icons |
| Cleaning progress | Up to 340 wide, 44 high for dry cleaning | Percentage font size 24 with a one-unit outline |
| Per carpet | Up to 280 wide, 48 high | Amount font size 26, dark caption size 16 and 32 × 32 icon |
| Wallet | 68 high, width follows the amount | Amount font size 32 and 42 × 42 coin |
| Finish | 104 wide, 56 high | Plain Finish label, font size 20 |
| Video 2× | 96 wide, 56 high | Teal style and authored vector lock/play/check artwork |

**Earnings Gap** remains 6 units between progress and the Per carpet plaque. The wet stage uses a taller progress area and percentage font size 22.

For room proportions, select `UpgradeRoom` in `scenes/production/rug_cleaning.tscn` and adjust its x/z scale. Its current .90 scale leaves floor aisles around the unchanged carpet. Select the scene root, `RugCleaningWindow`, for **Room View Pitch From Top** and **Room View Yaw Degrees**, which control the orthographic angle throughout cleaning, reveal and departure. The camera fits the room's closed/open bounds into the available rectangle; rug meshes and cleaning masks remain independent of decorative room scale.

The cleaning controller requests sensor orientation on mobile and uses an expanding 720×1000 reference canvas while active. Portrait and landscape therefore receive additional logical space instead of stretching or cropping the rug.

The HUD scales independently from the safe area's short side and the selected sizing reference, keeping its text and controls proportional on high-resolution phones. A separate fallback ensures a 56-unit action is at least 44 physical screen pixels tall in small windows; this minimum does not set the normal phone scale. The shared layout reserves a separate rectangle for the room camera. The gold counter adapts to wider totals within a stable composition, and coin flights follow its live position after rotation.

Completion uses only a **Compare** button, authored at 148×56 with font size 20 in `completion_reveal.tscn`. It sits at the bottom center in portrait and at the lower right in landscape. Its root exposes the same phone/tablet sizing references plus **Layout Edge** and **Rug Gutter**. Holding Compare pauses the automatic reveal and shows the recorded starting rug; release restores the result. The camera uses `rug_view_rect()` above the portrait action or in the full-height area to its left in landscape. Landscape frames the complete room without shrinking the cleaning carpet; portrait retains the gentle reveal push. Full and early completion retain their 2.4-second and 1.1-second automatic pauses.

The shop's Clean/Resume action and bottom navigation sit outside scrolling content. Keep that separation so a long blueprint list does not hide the way back. The Notice panel has a real layout slot below the header; it never covers a purchase or cleaning button.

## Text and live values

Edit ordinary `Label.text` and `Button.text` directly. Static authored text survives gameplay and state refreshes.

Shop text containing `{cash}`, `{cost}`, `{rugs_left}`, or similar braces is an editable **format template**. Keep the placeholder when you want the live number, and change the words around it. The braces may be visible in editor preview; playing substitutes the actual values. Item cards keep their own templates, and their root **Item Id** connects them to the existing economy. The `item_card.gd` **Editor State** selector previews the saved Locked, Need Cash, Ready, Owned and Equipped groups without purchasing anything; use **As authored** when arranging the normal scene.

For the cleaning HUD, select `GymUI` to edit **Progress Colors** and **Responsive Layout** in the Inspector. `FinishJobButton` is saved hidden and appears at 75% combined cleanliness. **Per carpet** below progress shows the current full-clean reward and updates after accessory purchases. All six current stores use brushes; wet-tool rows are retained for future content, and the Gym has separate free previews. There are no contract, rug-picker or completion-card groups in the production HUD.

Some text is factual state: wallet totals, build cost, equipped item, delivery countdown and cleaning percentages. The game updates those fields deliberately. Prices and unlock requirements remain in `shop_state.gd`; changing a visual caption does not change the economy.

## Artwork and shared styles

Every illustration is a reusable scene containing an `Artwork` subtree. The storefront has groups for its facade, sign, window, door, awning and planters. Bonzi has editable body, face and brush parts. Move nodes, change polygons or Panel style colors, hide parts, or insert your own assets. These shapes exist in the editor, including before the game runs.

`illustration_layout.gd` only centers and scales the top-level `Artwork` group inside its Control. Edit the **illustration root's rectangle** to move/resize the whole asset, and edit **children inside Artwork** to change its design. Individual part transforms survive resizing. Bonzi's **Working** property animates a designated group around its authored pose. Disable Working to inspect a still pose.

The shared Theme has named variations such as `PrimaryButton`, `SecondaryButton`, `NavButton`, `Card`, `SoftCard`, `BlueCard`, `Title` and `Body`. Edit these once for consistent changes, or add a local Theme Override to a specific node. Use **Make Unique** before modifying a shared style when you only want one card to change.

## Keep the connections intact

Keep nodes with the `%` unique-name mark: controllers find those names even if you move them inside their scene. Keep `metadata/action` and `metadata/show_when` values on functional card controls; they connect an authored button or state group to its behavior. You can freely edit their appearance, text and container ordering. Renaming a unique node, moving it outside its owning scene, deleting action metadata, or adding a new economy item requires updating the corresponding binding.

The one-off illustration generator is for initial authoring only and skips existing scenes by default. Normal play never runs it. Do not force-regenerate edited artwork unless you intend to replace those edits.

## Usability and progression in this pass

- Larger, separated targets and stronger text contrast; scroll gestures cancel button taps.
- Fixed Clean/Resume action, persistent page scroll, and Back/Escape navigation.
- Purchases show cost, effect and cash remaining before building.
- Goals explain the next customer-rug milestone or cash shortfall; optional upgrades are identified as optional.
- Both owned brushes can be equipped for free; the choice survives saving and reloading.
- Completion removes the finished rug and opens the next rug automatically, without a prompt or a trip through the shop.
- Practice and future wet-tool previews are clearly labeled; practice does not pay money.
- The future shop is a preview, not a cash sink or an unreachable active progression goal.

Use **F5** to start production cleaning and **F6** to preview the selected scene. The validation scripts check that edited text, margins and asset positions survive startup and data refresh. They use `--shop-test` so they do not change player saves. Desktop portrait and wide layouts are verified; Android device ergonomics still need a real-device playtest.
