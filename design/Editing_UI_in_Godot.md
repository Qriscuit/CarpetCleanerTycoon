# Editing the game's UI in Godot

The UI is now saved as real scene nodes. Playing the game binds live values and switches existing states; it does not regenerate the menus, replace their controls, or reset their positions.

## Start here

For the current game, open `scenes/production/floating_home.tscn`; its dock sheets live in `scenes/ui/compact_shop.tscn`. **F5** starts this production menu. See [scene navigation](Scene_Navigation.md) for production/test organization. The detailed hub instructions below apply to the retained legacy test menu.

Open `CarpetToy/project.godot`, then open `scenes/test/shop_hub.tscn` and select **2D**. Select the `ShopHub` root and change **Editor Page** in the Inspector to preview Shop, Items, Blueprints, Bonzi, or the future shop. These pages already exist under `Shell / Layout / Pages`; each has its own scroll container and content. Editor Page is only a preview choice; the game starts at the shop.

| What to edit | Where |
| --- | --- |
| Production main menu and navigation | `scenes/production/floating_home.tscn` |
| Production shop sheets and purchase review | `scenes/ui/compact_shop.tscn` |
| Legacy test shop menus and cards | `scenes/test/shop_hub.tscn` |
| In-game rug HUD, progress card, tool buttons and completion actions | `scenes/ui/cleaning_hud.tscn` |
| Art-review scene buttons | `scenes/ui/studio_hud.tscn` |
| Storefront, Bonzi, brushes and other artwork | `scenes/ui/art/*.tscn` |
| Shared palette, typography, borders and button styles | `resources/ui/mint_theme.tres` |

The 3D rug scenes contain an editable `GymUI` instance. Expand it in the scene tree to edit its children in place, or open `cleaning_hud.tscn` to change the shared HUD. The carpet art-review scene similarly contains `StudioUI`.

## Move and resize things

Controls inside a `VBoxContainer` or `HBoxContainer` are arranged by that container. Reorder them in the scene tree; change **Custom Minimum Size**, **Container Sizing**, and the container's **Theme Overrides → Constants → Separation**. Change the `Shell` MarginContainer's margins for the outer safe spacing. These are native Godot layout rules, not a script undoing your changes.

For free placement, the cleaning HUD's `Heading`, `CleaningProgress`, `LeftRail`, `ToolRail`, and `HomeButton` are independently anchored controls. Move their offsets in the 2D view or Inspector. Their anchors keep them attached to their screen corner on resize. The progress value stays inside its card instead of following a scripted horizontal position.

The shop's Clean/Resume action and bottom navigation sit outside scrolling content. Keep that separation so a long blueprint list does not hide the way back. The Notice panel has a real layout slot below the header; it never covers a purchase or cleaning button.

## Text and live values

Edit ordinary `Label.text` and `Button.text` directly. Static authored text survives gameplay and state refreshes.

Shop text containing `{cash}`, `{cost}`, `{rugs_left}`, or similar braces is an editable **format template**. Keep the placeholder when you want the live number, and change the words around it. The braces may be visible in editor preview; playing substitutes the actual values. Item cards keep their own templates, and their root **Item Id** connects them to the existing economy. The `item_card.gd` **Editor State** selector previews the saved Locked, Need Cash, Ready, Owned and Equipped groups without purchasing anything; use **As authored** when arranging the normal scene.

For the cleaning HUD, select `GymUI` to edit **Live Text** templates and **Progress Colors** in the Inspector. Toggle the eye icon on the saved `ContractCard` and `CompletionCard` groups to inspect those layouts. In play, the controller chooses the appropriate state.

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
- Completion offers Next rug immediately, without requiring a return through the shop.
- Practice and future wet-tool previews are clearly labeled; practice does not pay money.
- The future shop is a preview, not a cash sink or an unreachable active progression goal.

Use **F5** to play the hub and **F6** to preview the selected scene. The validation scripts check that edited text, margins and asset positions survive startup and data refresh. They use `--shop-test` so they do not change player saves. Desktop portrait and wide layouts are verified; Android device ergonomics still need a real-device playtest.
