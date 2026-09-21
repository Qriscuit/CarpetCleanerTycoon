# Floating shop — Blender and Godot implementation

**F5** launches `CarpetToy/scenes/production/floating_home.tscn`, now the main menu. Open that scene and use **F6** to preview it directly.

## Editable source and exported assets

Open `art/blender/floating_shop.blend` in Blender 4.3 or later. The `FloatingShop` collection contains 71 individually named parts: foundation, garden, walls, rounded roof, striped awning, window rugs, arched doorway, rug medallion, side/back windows, shrubs and rolled rug. Bevel modifiers remain editable.

The file also contains `BrushIcon`, `BlueprintIcon`, `BonziIcon`, `CoinIcon` and `SettingsIcon` collections. These are hidden initially so the shop is easy to inspect; enable their viewport/render visibility in the Outliner. The Studio collection contains the camera and softbox lights.

`CarpetToy/assets/floating_shop/` contains six GLBs and matching transparent PNG renders made from the Blender geometry. The source stays modular; export copies are joined to reduce draw calls. The shop has 30,032 triangles and is about 783 KB. `manifest.json` records all asset triangle counts.

The center building in Godot is the actual `FloatingShop.glb`, rendered through an independent transparent 3D viewport. Navigation uses the Blender-rendered PNGs. These are native Godot buttons with editable style resources. The light-blue background pattern is resolution-independent Godot drawing.

## New home scene

- `SkyPattern`: pale blue background and sparse bubbles, sparkles and swishes.
- `BuildingView / ShopViewport / ShopStudio`: imported shop, camera, lights, floating shadow and rotation pivot.
- `ShopTap`: mouse/touch/keyboard target that compresses the 3D shop while held and plays a 0.22-second release pop before starting/resuming the paid rug. All button styles, including disabled and focus, are transparent. The persistent caption beneath the house is removed. Canceled presses reset; repeated taps cannot start multiple transitions.
- `TopBar`: live coin balance and settings, with compact large-number display.
- `Dock`: Shop, Tools, Plans and Bonzi, each with an icon and one short caption. Shop opens upgrades; Tools equips brushes; Plans shows unlock progress and routes found blueprints to Shop; Bonzi shows automation and income.
- `Management`: hosts `scenes/ui/compact_shop.tscn`, a native compact sheet. Close, outside tap or Back returns home. Back closes purchase review first. Purchase reviews show cost, effect and remaining cash; owned/locked states and purchase/equip actions use the existing ledger. Sheets fit content and scroll on short screens.
- `SettingsSheet`: toggle shop rotation/bobbing or reset progress. Reset opens a confirmation; Keep playing or Back cancels it. Confirmation atomically clears coins, milestones, upgrades, owned tools, the active rug, and automation progress, keeping only the free starter brush. A failed write preserves progress. Motion preference lasts for the current session and is retained when resetting.
- `ReturnNotice`: acknowledges already-credited away earnings and disappears after acknowledgement.

Scene layout and behavior live in `CarpetToy/scripts/floating_home.gd`. The root's `Animate Shop` and `Rotation Speed Degrees` properties control animation. `Preview Safe Insets` simulates left/top/right/bottom insets for layout inspection.

The scene temporarily uses an expanding 390-unit short-side canvas and restores the prior window scaling when leaving. On mobile it requests sensor orientation while this home is active, then restores the previous orientation when leaving. Top controls and dock respect the device safe area; the model fits both available dimensions and remains framed through a full rotation. Portrait and landscape retain separate control positions rather than stretching a screenshot.

The cleaning scene's icon Back control always returns to the production floating home, including direct gym entry. The original hub is a test scene. Bonzi's panel and purchase review show coins per bar duration: 10 coins every 120s at base, 90s with Mk II, or 80s with Mk II and Welcome Sign. The countdown shows the next +10 payout. Reward amounts and the save format are unchanged.

Suspended income uses bounded wall-clock absence, like reopening the app, so a stopped live timer does not lose phone sleep time. Failed saves retain that bounded absence for retry without exposing uncommitted coins. Automated fixtures test this separately from the UI labeling issue.

## Validation

`tools/validate_floating_home.gd` checks the configured main scene, ten portrait/landscape sizes from 320×568 through 1024×768, full-rotation framing, safe areas, balances, away acknowledgement, mouse/touch navigation, compact purchase review/cancellation, swipe rejection, exact-once purchases, tool equipment, blueprint routing, Bonzi income, press/pop animation, paid-job launch, return and rug resumption. The legacy shop UI and paid contract suites also pass.

`validate_home_settings.gd` covers reset confirmation, cancellation, repeated/canceled touch, save failures, compact portrait/landscape layouts, transparent house states and the cycle-based income label. `validate_automation_reset.gd` covers all three payout intervals, simulated sleep, duplicate resume, the offline cap, retry failures, full reset rollback, and reopening after reset. Always pass `-- --shop-test`; the tests do not reset the player's save.

Captures are saved under `art/renders/floating_home_*.png`. The graphics driver is Intel Iris Xe, using Godot GL Compatibility. This verifies desktop viewport behavior; Android/iOS export, device orientation handling and actual mobile performance still require real-device testing. This environment emits a root-certificate-store warning on startup, unrelated to these offline rendering checks.

## Rebuild

From the repository root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.3\blender.exe' --background --python tools/build_floating_shop.py
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path CarpetToy --editor --import
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path CarpetToy --script ../tools/assemble_floating_home.gd
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path CarpetToy --script ../tools/assemble_compact_shop.gd
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_floating_home.gd -- --shop-test
```

The builders overwrite this new Blender source, its exports, and the new scene. They are reproducible authoring utilities; do not rerun them over manual edits you want to keep. Ordinary play never runs a builder. Tests use isolated saves and must include `-- --shop-test`.
