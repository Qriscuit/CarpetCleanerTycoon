# Floating shop — Blender and Godot implementation

Use **Open Game Editor.cmd** for the pinned **Godot 4.7.2 Mono/.NET** editor. **F5** launches `CarpetToy/scenes/production/rug_cleaning.tscn`, creating or resuming the last selected store's carpet. The cleaning Back button opens `CarpetToy/scenes/production/floating_home.tscn` for browsing stores and managing upgrades. Open that menu scene and use **F6** to preview it directly. The full Mono bundle includes `GodotSharp`; the installed .NET 8 SDK 8.0.400 supports the editor, while gameplay remains GDScript.

## Editable source and exported assets

Open `art/blender/floating_shop.blend` in Blender 4.3 or later. The `FloatingShop` collection contains 71 individually named parts: foundation, garden, walls, rounded roof, striped awning, window rugs, arched doorway, rug medallion, side/back windows, shrubs and rolled rug. Bevel modifiers remain editable.

The file also contains `BrushIcon`, `BlueprintIcon`, `CoinIcon` and `SettingsIcon` collections. These are hidden initially so the shop is easy to inspect; enable their viewport/render visibility in the Outliner. The Studio collection contains the camera and softbox lights.

`CarpetToy/assets/floating_shop/` contains the current GLBs and matching transparent PNG renders made from the Blender geometry. The source stays modular; export copies are joined to reduce draw calls. The shop has 30,032 triangles and is about 783 KB. `manifest.json` records all asset triangle counts.

The center building in Godot is the actual `FloatingShop.glb`, rendered through an independent transparent 3D viewport. Navigation uses the Blender-rendered PNGs. These are native Godot buttons with editable style resources. The light-blue background pattern is resolution-independent Godot drawing.

## New home scene

- `SkyPattern`: pale blue background and sparse bubbles, sparkles and swishes.
- `BuildingView / ShopViewport / ShopStudio`: imported shop, camera, lights, floating shadow and rotation pivot.
- `ShopTap`: mouse/touch/keyboard target that compresses the 3D shop while held and plays a 0.22-second release pop before starting/resuming the paid rug. All button styles, including disabled and focus, are transparent. The persistent caption beneath the house is removed. Canceled presses reset; repeated taps cannot start multiple transitions.
- `TopBar`: live coin balance and settings, with compact large-number display.
- `Dock`: Shop, Tools, Stores and the bottom-right Avatar entry. The first three open management; Avatar opens a separate customization menu with a rotating 3D toy figure and horizontal Colors/Hats tabs.
- `Management`: hosts `scenes/ui/compact_shop.tscn`, a native compact sheet. Close, outside tap or Back returns home. Back closes purchase review first. Purchase reviews show cost, effect and remaining cash; owned/locked states and purchases use the current ledger. Sheets fit content and scroll on short screens.
- `SettingsSheet`: toggle shop rotation/bobbing or reset progress. Reset opens a confirmation; Keep playing or Back cancels it. Confirmation atomically clears current coins, milestones, upgrades, active rugs and appearance, restoring Neighborhood, the free starter brush and orange/no hat. A failed write preserves progress. Motion preference lasts for the current session and is retained when resetting.
- `AvatarMenu`: `scenes/ui/avatar_customization.tscn`; eight colors and three hat choices are free and global. The authored white body is tinted per instance; the same appearance equips the visual companion in every paid cleaning room. Appearance saves atomically through `set_appearance(color_id, hat_id)`.

Scene layout and behavior live in `CarpetToy/scripts/floating_home.gd`. The root's `Animate Shop` and `Rotation Speed Degrees` properties control animation. `Preview Safe Insets` simulates left/top/right/bottom insets for layout inspection.

The scene temporarily uses an expanding 390-unit short-side canvas and restores the prior window scaling when leaving. On mobile it requests sensor orientation while this home is active, then restores the previous orientation when leaving. Top controls and dock respect the device safe area; the model fits both available dimensions and remains framed through a full rotation. Portrait and landscape retain separate control positions rather than stretching a screenshot.

The cleaning scene's icon Back control returns to the production floating home, including direct Gym entry. The old detailed hub and robot UI are retired. Current progress uses schema 1 at `user://carpet_cleaner_v1.json`; the former `neighborhood_shop_v1.json` remains untouched and unread. Neither idle time nor background/resume produces income. The paid-room companion rides the brush, can fall under fast tool motion, then gets up, dusts off, runs back and climbs aboard. It remains visual only, with no cleaning strength, earnings or unlock effect. Customer handoffs, character XP and growth are not implemented. The menu preview remains independent of the in-level rig; see [Level Companion](../Level_Companion.md).

## Store swipe motion

The 2026-10-05 carousel revision slides the current floating store and its shadow beyond the actual game-window edge while the next store enters from the opposite edge. Navigation takes 0.62 seconds with cubic easing and a subtle temporary lean. The wallet, store caption, settings and navigation dock stay in place.

Two authored, fitted transparent 3D viewports are reused: `BuildingView` is the current store and `IncomingBuildingView` supplies the incoming store. Both use the same imported mesh resources, with separate tint materials. The incoming viewport renders only during a slide and is disabled when idle. Resizing or changing safe-area insets preserves slide progress and recomputes the horizontal travel distance.

`SkyPattern` now draws a continuous diagonal pastel gradient. Neighborhood uses blue, High Street mint, Wash House lavender, and Restoration peach. `set_store_blend(from_store, to_store, progress)` interpolates both gradient endpoints as the stores slide; the quiet bubbles, sparkles and swishes remain.

Mouse and touch swipes, plus keyboard arrows, use the same carousel. Further swipes during a slide queue the latest requested destination. Tapping a moving store cannot start a cleaning job. Focus loss or opening a sheet settles the destination cleanly, including a newer owned-store selection already committed by the management sheet. Browsing a locked store preserves ownership and the active paid branch; selecting an owned store retains the ledger's existing atomic save behavior. The Animate Shop setting continues to control idle rotation and bobbing.

`tools/validate_store_swipe.gd` validates production input, full-window geometry, color blending, rapid navigation, ownership and reload, cancellation, resize, focus loss, material reuse and entry into the paid cleaning route. `tools/capture_store_swipe.gd` produces actual renderer captures in portrait and landscape. Both require the pinned Godot 4.7.2 Mono runner and `-- --shop-test`. The current animation preview is `art/renders/store_swipe_preview.gif`.
## Validation

`tools/validate_floating_home.gd`, `validate_home_settings.gd` and `validate_avatar_ui.gd` are current graphics regression entry points for navigation, reset, appearance, input and layout. `validate_avatar_state.gd` passed 116 headless checks on 17 October 2026, including free combinations, reload, failed writes, reset and preservation of the unused old namespace. Nine targeted ledger suites completed 13,152 checks with zero failures. These are targeted checks, not a claim that every graphics suite or device was tested.

Always use the pinned Godot 4.7.2 Mono wrapper and `-- --shop-test`; current state runs also isolate APPDATA. Captures remain under `art/renders/`. Desktop graphics and APK signature checks do not establish Android orientation handling, touch feel or actual mobile performance.

## Rebuild

From the repository root, use the shared version-gated Mono/.NET runner for every Godot command:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.3\blender.exe' --background --python tools/build_floating_shop.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --editor --import
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/assemble_floating_home.gd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/assemble_compact_shop.gd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_floating_home.gd -- --shop-test
```

The builders overwrite this new Blender source, its exports, and the new scene. They are reproducible authoring utilities; do not rerun them over manual edits you want to keep. Ordinary play never runs a builder. Tests use isolated saves and must include `-- --shop-test`.
