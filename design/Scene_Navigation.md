# Production and test scenes

Press **F5** to play the production game. Use **F6** on a test scene for development.

| Folder | Scene | Purpose |
| --- | --- | --- |
| `CarpetToy/scenes/production/` | `floating_home.tscn` | Main menu; building opens or resumes a paid rug |
| `CarpetToy/scenes/production/` | `rug_cleaning.tscn` | Shared cleaning world and customer jobs |
| `CarpetToy/scenes/test/` | `shop_hub.tscn` | Original detailed menu, retained for testing |
| `CarpetToy/scenes/test/` | `rug_cleaning_gym.tscn` | Reachable from Settings → Gym; two free exercises sharing the production world |
| `CarpetToy/scenes/test/` | `starter_workshop.tscn`, `carpet_studio.tscn` | Earlier workshop and art inspection |

Reusable rugs, floor and UI remain under `scenes/` and `scenes/ui/`. Android exports include the gym and exclude the other three test scenes and the legacy menu controller.

Settings has no Done button: click/tap outside the panel or use Back/Escape to dismiss it. **Gym** opens `Routes.GYM`. The gym uses `scripts/gym.gd` and the authored `scenes/ui/gym_hud.tscn` overlay. **Rug 1 · Brush** contains dust and dirt pellets and allows only the brush; completion repeats the same exercise. **Rug 2 · Wet tools** starts after dry cleaning and reuses the production wetness and extraction state. Holding or moving the hose fills a radial indicator beside its nozzle; each completed charge launches a large three-lobed drop, followed by a pooled splash and broad dark wet circle. The squeegee remains disabled until 99% water coverage, then the hose locks and the squeegee removes water through that same mask. See [water feedback and extraction](Water_Blobs.md). Both exercises can be reset or switched without touching the player's paid job or balance.

With no overlay open, the cleaning scene's icon Back control opens the floating production menu, including direct test-gym entry or entry through the old test menu. Returning during a paid job attempts to save first; if disk persistence is temporarily unavailable, the latest snapshot is retained in memory and navigation still works.

The production cleaning scene always creates or resumes a paid rug, even when run directly. The inherited `rug_cleaning_gym.tscn` and legacy `starter_workshop.tscn` explicitly set `practice_only = true`, so test scenes cannot become paid because of stale menu state.

There is no scene reload between cleaning jobs. The active cleaning scene retains its rug meshes, soil controller and fixed 560-slot GPU dirt pool: arrival unrolls an already dust-textured rug, grows the small starter rocks and brings in the brush. Other pooled clumps stay invisible until brushed. Completion vacuums debris, rolls the rug away, shows the paid reward and refills the same pool for the next arrival. The icon Back control remains usable throughout.

The lower of debris clearance and surface-dust clearance determines the reward. Finishing at 85% or higher but below 99% pays 20 coins; 99% or higher finishes automatically and pays 40. Payment and reservation of the next job are committed together before takeaway, so leaving during the transition cannot pay twice or lose the replacement job.

The cleaning HUD keeps a gold wallet at the top-right. Reusable 2D reward coins linger briefly, then fly into it. Each arrival increments the displayed balance by that coin's exact value; it does not award money again. The saved balance already contains the full reward, so leaving before the burst finishes preserves all earnings.

The **Upgrade** button opens a centered placeholder menu within the cleaning scene, with no purchases available yet. It pauses brushing, soil simulation and rug transitions. Close or Back dismisses the menu and resumes the same phase; a subsequent Back returns to the main menu. Opening this menu does not create another cleaning scene or reset the rug.

The old bug came from a fallback to `shop_hub.tscn` plus a mutable `return_home_scene` setting. Routing now uses `CarpetToy/scripts/scene_routes.gd`: use `Routes.MAIN_MENU` for all full-scene Home actions and `Routes.CLEANING` for paid jobs. Sheet close/back actions stay within the main menu. Do not add per-menu return destinations.

When renaming a production scene, update those constants, `project.godot`'s main scene, the editor launcher, builders, and validation paths. Verify navigation with:

```powershell
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_scene_routes.gd -- --shop-test
```

This checks both authored Home button connections in paid, practice and direct-scene entry, stale legacy routing state, both old-menu launch actions, and preservation of the active rug. Run `validate_floating_home.gd` and `validate_contract.gd` with the same arguments for the full menu and save/payment checks. Save changes, then use **Build APK.cmd** to refresh the APK.
