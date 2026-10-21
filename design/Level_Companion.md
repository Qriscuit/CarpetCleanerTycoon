# In-level player companion

The player character appears immediately in every paid cleaning room, including a fresh Neighborhood save. The wardrobe's saved color and hat are shared with this character. This version establishes physical and animated behavior; experience levels, growth, the customer handoff, boosts, autonomous cleaning and offline work are not implemented.

## Behavior and integration

`CarpetToy/scripts/workshop.gd` owns one `level_companion.gd` instance per paid room. No companion is created in the developer Gym. The existing brush world transform supplies a seat halfway along its handle; orthonormalizing the seat basis prevents brush-width upgrades from stretching the character. Pointer pickup, tool changes and focus restoration reset motion history so a discontinuous placement is not interpreted as a fling.

The state sequence is `RIDING -> FALLING -> GETTING_UP -> DUSTING -> RUNNING -> CLIMBING -> RIDING`. Fast horizontal tool motion accumulates strain; normal movement and vertical brush hovering do not. The fall uses nine jointed physical bones. Settling or a 2.8-second timeout hands the pose to the get-up animation through a short blend. The character dusts himself off, follows the current tool location, and blends position and orientation into the climb and seated pose. A reseating grace period prevents an immediate second fall.

While the carpet arrives, completes or departs, he waits in a fixed corner pose with animation and physics asleep. The upgrades drawer, pending rewarded video, focus loss, app suspension and tree pause suspend behavior. A suspended ragdoll retains its pose and bounded velocity for resumption. Leaving the room stops simulation, and ordinary scene destruction frees its resources and disconnects the appearance signal. This behavior never calls cleaning or reward APIs.

## Assets and rendering cost

- Editable source: `art/blender/avatar.blend`; generators: `tools/build_avatar.py`, then `tools/rig_avatar.py` using Blender's background Python runner.
- Level asset: `CarpetToy/assets/character/avatar_rig.glb`; authoring contract: `rig.json`. Static wardrobe assets remain separate.
- One connected 2,992-triangle white body, 12 bones and at most four normalized skin influences per vertex. Pirate-equipped total: 3,632 triangles and three material surfaces.
- Six clips: `idle`, `ride`, `run`, `get_up`, `dust_off`, `climb`. The controller explicitly loops idle, ride and run on its private animation copies; the other actions play once. Animation sampling is capped at 30 Hz.
- The character uses the existing room camera, lights and viewport. It adds no viewport, dynamic light, real-time character shadow or per-frame node/material creation. Hats attach to the animated head bone.
- Nine capsule bodies and a private floor/boundary collision layer are created once. No self-collision, carpet contact callbacks, dirt interaction or persistent ragdoll simulation. Zero bodies simulate while riding, parked or suspended.
- Godot physical bones require a unit-scale skeleton. The instance bakes display scale into mesh vertices, bone rests, skin bind translations and position animation tracks once at setup; imported assets are left unchanged. This prevents the animated-to-physics handoff from changing the character's size.

The default display scale is 0.32. `fling_speed` and `fling_strain_seconds` are exported on `level_companion.gd`; the starting thresholds are 6.5 world units/second and 0.07 accumulated strain seconds. The workshop defines the seat, walking bounds and parked spot. These are gameplay tuning values, not phone performance guarantees.

## Validation

Use only the pinned Godot 4.7.2 stable Mono/.NET launcher and isolated test saves:

```powershell
$taskArgs = @('--headless','--path','CarpetToy','--script','../tools/validate_level_companion.gd','--','--shop-test')
& '.\tools\run_godot.ps1' @taskArgs
```

`validate_level_companion.gd` covers the state cycle, moving targets, real mouse/touch input, edge falls, rig scale, pause/resume, selected appearance, six paid stores, cold reload and resource reuse. `validate_manual_only.gd` verifies that companion activity does not earn money or remove dirt. Graphical regressions include `validate_brush_lift.gd`, `validate_brush_input.gd`, `validate_carpet_video_flow.gd` and `validate_avatar_ui.gd`. The asset audit is `tools/validate_avatar_assets.py`.

Real rendered inspection uses the production room in portrait and landscape plus close views of sitting, tumbling, recovery and climbing with a head-mounted hat. Captures are local QA artifacts under `art/renders/avatar/level_*` and `companion_detail_*`; they are not shipping textures.

`tools/profile_level_companion.gd` compares the same desktop room with the character hidden, seated, falling/recovering and parked. Run it with graphics (`--rendering-method gl_compatibility`) and `-- --shop-test`; it writes `build/level_companion_profile.json`. It fixes the viewport at 390x844, caps the game at 60 fps and freezes soil to isolate the comparison. Godot monitor timings include the engine and desktop scheduling and are not a phone battery measurement. Measure Android frame times, thermals, memory and battery on target hardware before claiming device savings.

### Desktop comparison, 17 October 2026

Final GL Compatibility run on the RTX 3070 desktop, 390x844 at a 60 fps cap, recorded the following total room costs. The body was bare-headed for this comparison.

| State | Peak draw calls | Visible triangles | Simulating companion bodies | Median engine physics time |
| --- | ---: | ---: | ---: | ---: |
| Character hidden | 82 | 18,744 | 0 | 0.027 ms |
| Riding | 83 | 21,736 | 0 | 0.098 ms |
| Fall and recovery | 83 | 21,736 | 9 peak | 0.208 ms |
| Parked | 83 | 21,736 | 0 | 0.019 ms |

Median desktop frame time stayed near 16.66 ms in every state. Fall/recovery physics p95 was 1.113 ms. Small differences near the idle floor are measurement noise, not savings claims. These results show one additional body draw and bounded temporary physics work in this desktop scene; they do not predict performance on a particular phone.

Final targeted validation passed 96 companion checks, 33 manual-only checks, 25 brush-lift checks, 946 cleaning/input checks, 30 video-flow checks and 2,091 wardrobe UI checks, with no failures. The final close-up captures include the smoothed seated hips and local-pose recovery blend. Room views cover 390x844, 844x390, 720x1000, 1000x600, 1080x2340 and 1536x2048; final images are in `art/renders/avatar/companion_final/`.
