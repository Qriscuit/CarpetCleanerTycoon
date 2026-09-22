# Water drops, charge, and extraction

Historical charged-drop prototype. The Gym now uses the [continuous water jet](Water_Jet.md); the implementation below remains unused for reference. The old validator command forwards to the current jet tests.

Open **Settings → Gym → Rug 2** and hold or drag the hose over the carpet. A radial ring beside the nozzle fills before every release. Each completed charge launches one large, connected three-lobed drop; it falls, produces a short broad splash, and is absorbed as a dark wet circle. Wet 99% of the carpet to lock the hose and unlock the squeegee, then drag the squeegee across the rug to pull the visible water back out. **Reset rug** or switching exercises clears the lesson.

The Gym starts this exercise after dry cleaning, but it uses the same wetness, extraction, shader, and stage rules as a production wet job. Its actions remain local to the practice scene and never modify the player's paid rug, balance, or save.

## Charge, fall, and splash

[water_blobs.gd](../CarpetToy/scripts/water_blobs.gd) owns only the timing and pooled presentation:

1. The hose charges at **1.5 releases per second**, so the ring takes about **0.667 seconds** to fill. The first drop waits for a complete cycle just like every later drop; releasing early clears and hides the indicator. The authored [Gym HUD](../CarpetToy/scenes/ui/gym_hud.tscn) uses one radial `TextureProgressBar` whose ring texture is created once by [gym_hud.gd](../CarpetToy/scripts/gym_hud.gd).
2. A **16-slot drop MultiMesh** draws low-poly falling drops with a **0.095–0.125 m** base radius. The [drop vertex shader](../CarpetToy/scripts/water_drop.gdshader) deforms each sphere into one watertight three-lobed shell. Broad bulges orbit inside the silhouette, the shell stretches during its 0.42-second fall, and it squashes near impact. This suggests three balls rolling under one membrane without cloth, soft-body, rigid-body, or fluid simulation.
3. A **16-slot splash MultiMesh** reuses horizontal quads. The [splash shader](../CarpetToy/scripts/water_splash.gdshader) expands and fades a stylized crown for 0.30 seconds. Its footprint is 1.28 times the eventual **0.30–0.38 m** wet radius. Drops and splashes create no per-effect nodes and perform no collision or pairwise-fluid work.
4. When the splash finishes, the visual controller emits its world position and radius. [gym.gd](../CarpetToy/scripts/gym.gd) forwards that result to `DirtController.apply_water_blob()`; the visual controller owns no carpet texture or gameplay wetness state.

The controller advances at most 0.1 seconds after a stalled frame and permits at most two queued births in one callback, so a long frame cannot replay an unbounded stream. Both MultiMeshes retain fixed capacity across resets and exercise changes. `_process()` stops after emission and all active falls and splashes finish.

## One wetness mask for water and extraction

[dirt_controller.gd](../CarpetToy/scripts/dirt_controller.gd) is the single authority for water. Its existing **256 × 416 L8 wetness texture** is approximately 104 KiB before driver bookkeeping and is already part of the production cleaning controller. The Gym does not allocate a separate absorption mask.

For each absorbed blob, `apply_water_blob()` visits only the circle's pixel bounding box. A solid center and feathered edge add to the compact `water_values` array without exceeding the amount of cleaned carpet at that pixel. The corresponding L8 pixels darken through the existing [opaque carpet shader](../CarpetToy/scripts/soil_surface.gdshader). There is no second full-color wet albedo and no extra Gym wet-layer sample.

The stage gate uses cumulative applied-water coverage. Before it reaches **99%**, the squeegee button is disabled, direct squeegee selection is rejected, and the dirt controller independently treats extraction strokes as no-ops. Once the threshold is reached, the hose locks and the squeegee unlocks. Extraction increases `extraction_values`; the displayed wetness is `water_values - extraction_values`, so each stroke clears the same L8 mask that the drops darkened. Applied coverage stays cumulative during extraction, preventing the squeegee from relocking midway through the stage.

The wetness texture uploads only when application or extraction changes pixels. Settled water performs no water-visual callbacks, although ordinary input-driven squeegee strokes still update the shared production texture as needed.

## Why a mask instead of another carpet texture

A second full-color carpet texture would duplicate albedo memory and add a color-texture sample merely to show a darker version of the same fibers. The L8 mask stores only **where** water remains. One grayscale lookup controls darkness, roughness, and specular response against the carpet color already being rendered, so every rug retains its underlying fibers and palette.

Using the production mask also keeps the visual result, the 99% gate, saved production progress, and squeegee extraction derived from the same data. The large charged-drop presentation is currently Gym-specific, but its absorption result follows the production wet-cleaning path.

## Maintenance

Tune `EMISSION_RATE`, `DROP_RADIUS_MIN`, `DROP_RADIUS_MAX`, `WET_RADIUS_MIN`, `WET_RADIUS_MAX`, `SPLASH_RADIUS_SCALE`, `LAUNCH_HEIGHT`, `FLIGHT_SECONDS`, and `SPLASH_SECONDS` in the water controller. The radial indicator derives its duration from `EMISSION_RATE`, so gameplay timing and UI cannot drift. Keep `DROP_CAPACITY` and `SPLASH_CAPACITY` fixed unless device profiling establishes a need to change them.

The Gym offsets landings 0.28 m forward from the hose through `HOSE_LANDING_OFFSET`, keeping the larger fall and splash visible from the overhead camera. Match the hose's visible lift to `LAUNCH_HEIGHT` when changing it. Tune the connected-shell motion and `drop_tint` in the drop shader, and tune `splash_tint`, crown shape, expansion, and fade in the splash shader.

`WET_STAGE_TARGET` in the dirt controller is the authoritative water-to-squeegee boundary. UI copy, button state, tool selection, and extraction all call the controller's stage helpers rather than maintaining another threshold. If rug dimensions change, update the dirt controller's `RUG_HALF` and the carpet shader's matching world-to-UV mapping together.

Birth time wraps every eight seconds because Compatibility packs [MultiMesh custom data](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html#class-multimesh-method-set-instance-custom-data) into 16-bit components. Keep both shaders' matching period synchronized with `CLOCK_PERIOD`; completion clears each slot so clock wrapping cannot revive it. If trajectories expand, enlarge the custom AABBs to prevent incorrect culling. Godot supports [vertex animation of MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

## Verification and device work

From the repository root, use the graphics renderer and isolated saves:

```powershell
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_water_blobs.gd -- --shop-test
```

The water validator covers the radial charge, delayed first birth, larger size ranges, ordered fall/splash/absorption lifecycle, shared wet-mask changes, the 99% squeegee lock, extraction from that same mask, reset and exercise switching, clock wrap, long-frame limits, resource reuse, and save preservation. `validate_gym.gd` covers the corresponding tool and HUD restrictions, while `validate_wet_cleaning.gd` protects the shared production stage rules. The dummy headless renderer cannot validate the visible drop and splash shaders, so inspect the generated `art/renders/water_*.png` captures as part of the graphics run.

Fixed pools, one existing L8 wetness texture, one carpet lookup, and idle shutdown bound the design, but they are not phone frame-time or battery measurements. Profile charge, continuous pouring, a nearly saturated rug, and active extraction on target Android devices before increasing pool sizes, mask resolution, shader complexity, or effect cadence.
