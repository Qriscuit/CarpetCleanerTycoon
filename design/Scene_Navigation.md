# Production and test scenes

Press **F5** to play the production game. Use **F6** on a test scene for development.

| Folder | Scene | Purpose |
| --- | --- | --- |
| `CarpetToy/scenes/production/` | `floating_home.tscn` | Main menu; building opens or resumes a paid rug |
| `CarpetToy/scenes/production/` | `rug_cleaning.tscn` | Shared cleaning world and customer jobs |
| `CarpetToy/scenes/test/` | `shop_hub.tscn` | Original detailed menu, retained for testing |
| `CarpetToy/scenes/test/` | `rug_cleaning_gym.tscn` | Free practice; inherits the production world so art fixes stay shared |
| `CarpetToy/scenes/test/` | `starter_workshop.tscn`, `carpet_studio.tscn` | Earlier workshop and art inspection |

Reusable rugs, floor and UI remain under `scenes/` and `scenes/ui/`. Android exports exclude `scenes/test/*` and the legacy menu controller.

Both cleaning **Home** buttons always open the floating production menu. This includes running the gym directly, finishing a rug, or entering through the old test menu. Returning during a paid job still saves progress first; a failed save keeps the player in the rug.

The old bug came from a fallback to `shop_hub.tscn` plus a mutable `return_home_scene` setting. Routing now uses `CarpetToy/scripts/scene_routes.gd`: use `Routes.MAIN_MENU` for all full-scene Home actions and `Routes.CLEANING` for paid jobs. Sheet close/back actions stay within the main menu. Do not add per-menu return destinations.

When renaming a production scene, update those constants, `project.godot`'s main scene, the editor launcher, builders, and validation paths. Verify navigation with:

```powershell
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_scene_routes.gd -- --shop-test
```

This checks both authored Home button connections in paid, practice and direct-scene entry, stale legacy routing state, both old-menu launch actions, and preservation of the active rug. Run `validate_floating_home.gd` and `validate_contract.gd` with the same arguments for the full menu and save/payment checks. Save changes, then use **Build APK.cmd** to refresh the APK.
