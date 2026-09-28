# Production and test scenes

Open **Open Game Editor.cmd**, then press **F5** to play the production game. Use **F6** on a test scene for development. The launcher pins the complete **Godot 4.7.2 Mono/.NET** bundle; do not open this project with a standard build or another version. Gameplay remains GDScript.

| Folder | Scene | Purpose |
| --- | --- | --- |
| `CarpetToy/scenes/production/` | `floating_home.tscn` | Main menu; building opens or resumes a paid rug |
| `CarpetToy/scenes/production/` | `rug_cleaning.tscn` | Shared cleaning world and customer jobs |
| `CarpetToy/scenes/test/` | `shop_hub.tscn` | Original detailed menu, retained for testing |
| `CarpetToy/scenes/test/` | `rug_cleaning_gym.tscn` | Reachable from Settings → Gym; two free exercises sharing the production world |
| `CarpetToy/scenes/test/` | `starter_workshop.tscn`, `carpet_studio.tscn` | Earlier workshop and art inspection |

Reusable rugs, floor and UI remain under `scenes/` and `scenes/ui/`. Android exports include the gym and exclude the other three test scenes and the legacy menu controller.

Settings has no Done button: click/tap outside the panel or use Back/Escape to dismiss it. **Gym** opens `Routes.GYM`, using `scripts/gym.gd` and `scenes/ui/gym_hud.tscn`. **Rug 1 · Brush** contains dust and dirt pellets. **Rug 2 · Wet tools** starts after dry cleaning; holding the hose pours the continuous jet into the shared wetness mask. Natural watering advances to extraction at 99%. The Squeegee button also instantly wets the practice rug, while Water hose clears wetness for another watering test. Camera and free upgrade controls remain practice-only. See [Water Jet](Water_Jet.md) and [Squeegee Water VFX](Squeegee_Water_VFX.md). Neither exercise changes the paid job or balance.

With no overlay open, the cleaning scene's icon Back control opens the floating production menu, including direct test-gym entry or entry through the old test menu. Returning during a paid job attempts to save first; if disk persistence is temporarily unavailable, the latest snapshot is retained in memory and navigation still works.

The production cleaning scene always creates or resumes a paid rug, even when run directly. The inherited `rug_cleaning_gym.tscn` and legacy `starter_workshop.tscn` explicitly set `practice_only = true`, so test scenes cannot become paid because of stale menu state.

There is no scene reload between cleaning jobs. The active cleaning scene retains its rug meshes, soil controller and fixed 560-slot GPU dirt pool: arrival unrolls an already dust-textured rug, grows the small starter rocks and brings in the brush. Other pooled clumps stay invisible until brushed. Completion vacuums debris, rolls the rug away, shows the paid reward and refills the same pool for the next arrival. The icon Back control remains usable throughout.

Store 1 uses the lower of debris clearance and surface-dust clearance. High Street (Store 2) skips brushing and averages water and extraction only. Stores 3–4 average dry, water and extraction. Required dry and water stages must each reach 99% before advancing. Finishing at 75% or higher but below 99% pays the normal quote; 99% automatically pays double. Payment and reservation of the next job commit together before takeaway, so leaving during the transition cannot pay twice or lose the replacement job.

The cleaning HUD keeps a gold wallet at the top-right. Reusable 2D reward coins linger briefly, then fly into it. Each arrival increments the displayed balance by that coin's exact value; it does not award money again. The saved balance already contains the full reward, so leaving before the burst finishes preserves all earnings.

The **Upgrade** button opens the live tool drawer: brush upgrades in Store 1, hose and squeegee upgrades in Stores 2–4. It pauses input, soil simulation and rug transitions. Close or Back resumes the same phase; a subsequent Back returns to the main menu. Purchases do not reset the rug. Payout upgrades have a separate bottom card.

The old bug came from a fallback to `shop_hub.tscn` plus a mutable `return_home_scene` setting. Routing now uses `CarpetToy/scripts/scene_routes.gd`: use `Routes.MAIN_MENU` for all full-scene Home actions and `Routes.CLEANING` for paid jobs. Sheet close/back actions stay within the main menu. Do not add per-menu return destinations.

When renaming a production scene, update those constants, `project.godot`'s main scene, the editor launcher, builders, and validation paths. Verify navigation with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_scene_routes.gd -- --shop-test
```

This checks both authored Home button connections in paid, practice and direct-scene entry, stale legacy routing state, both old-menu launch actions, and preservation of the active rug. Run `validate_floating_home.gd` and `validate_contract.gd` with the same arguments for the full menu and save/payment checks. Save changes, then use **Build APK.cmd** to refresh the APK.
