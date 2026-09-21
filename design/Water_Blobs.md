# Water blobs: first visual prototype

Open **Settings → Gym → Rug 2**, select the hose, then hold or drag over the carpet. Droplets fall, land, and join into gently moving puddles. Reset rug or switching exercises clears the water. This feature is limited to the gym; squeegee displacement and water-driven dirt removal are not implemented yet.

## Rendering and CPU budget

[water_blobs.gd](../CarpetToy/scripts/water_blobs.gd) owns two reusable MultiMeshes and one density texture:

1. A 32-slot MultiMesh draws low-poly falling droplets. The [drop vertex shader](../CarpetToy/scripts/water_drop.gdshader) calculates flight and impact squash from birth time, duration, and landing position. CPU work handles emission and landing events; there are no per-drop nodes, physics bodies, collision queries, or pairwise fluid interactions.
2. Each landing contributes three soft additive circles through the [density shader](../CarpetToy/scripts/water_density.gdshader). Only new landings are submitted to a **192×320** SubViewport. Its preserved texture stores the accumulated water, so old drops require no ongoing CPU work or redraw list. Production code performs no CPU image upload or GPU readback.
3. The existing [carpet shader](../CarpetToy/scripts/soil_surface.gdshader) reads the density five times to produce a smooth merged boundary, edge highlights, wet color, and shallow edge normals. Sub-texel UV motion animates the edge. Water shading is integrated into the carpet's existing opaque pass; it adds no transparent surface pass.

The density texture's single RGBA8 color payload is **245,760 bytes (240 KiB)**. This excludes driver allocations, framebuffer bookkeeping, meshes, and other game resources.

Current limits are **16 drops/second**, **32 airborne slots**, **96 stamp slots** (three per landing), and **at most 30 density updates/second**. A frame creates at most two drops and clamps simulation advance to 0.1 seconds, preventing a large backlog after a stall. When emission, active drops, and queued landings are all finished, the water controller disables `_process()`. The last render-completion callback finishes once; settled water has no continuing water-controller CPU callbacks. Its carpet shader still runs on the GPU.

This uses a density field to suggest merging metaballs. Evaluating every historical sphere at every carpet pixel, especially with raymarching, would make fragment cost grow with drop count. Individual physical water bodies would add simulation and object-management work. Here, storage and shader sample count stay fixed. Density saturates; this is a visual effect, not a conserved-volume fluid simulation.

## Maintenance

Tune `EMISSION_RATE`, `DROP_CAPACITY`, `FIELD_SIZE`, `FIELD_INTERVAL`, `LAUNCH_HEIGHT`, and `FLIGHT_SECONDS` in the controller. Keep `STAMP_CAPACITY` at three times the pending-landing limit. If rug dimensions change, update `RUG_SIZE` and the carpet shader's matching world-to-UV mapping together.

The gym offsets the landing point 0.20 m forward from the hose with `HOSE_LANDING_OFFSET`; this makes the short falling arc readable from the overhead camera. Match the hose's visible lift to `LAUNCH_HEIGHT` when changing it.

Tune `blob_threshold`, `blob_edge_softness`, `blob_tint`, `blob_tint_strength`, and `blob_edge_motion` in the carpet shader. Droplet color is `drop_tint`. Keep edge motion small compared with a density texel.

The stamp batch must contain only new landings before each `UPDATE_ONCE`; replaying earlier stamps would keep increasing their density. Reset uses `CLEAR_MODE_ONCE` and waits for render completion before flushing new landings. Godot documents these [SubViewport modes](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html).

Droplet birth time wraps every eight seconds because Compatibility packs [MultiMesh custom data](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html#class-multimesh-method-set-instance-custom-data) into 16-bit components. Keep the shader's matching period synchronized with `CLOCK_PERIOD`; landing clears each slot so clock wrapping cannot revive it. If trajectories expand, enlarge the custom AABB to prevent incorrect culling. Godot supports [vertex animation of MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

## Verification and device work

From the repository root, use the graphics renderer and isolated saves:

```powershell
& './tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path CarpetToy --script ../tools/validate_water_blobs.gd -- --shop-test
```

The dummy headless renderer cannot validate accumulated pixels or the visible result. Check merging, stationary pouring, reset, rug changes, idle behavior, and clock wrapping with the graphics renderer.

The September 21, 2026 rendered run passed **71 checks**, including density accumulation/connected blobs, stationary and moving input, reset, focus/HUD cancellation, clock wrap, long-frame limits, resource reuse and save preservation. The accompanying 100-frame moving-hose sample measured **52.5 μs average controller work per active callback** (5.671 ms across 108 callbacks, including final settling); the maximum across the run was 329 μs. This measures only the controller's `_process()` body on an Intel Iris Xe Windows desktop. It excludes other game CPU work, rendering-thread work, GPU time and startup. Full-frame p50/p95 were 31.9/33.8 ms with frame pacing and the existing scene included; these are not incremental water costs. Settled water produced no additional controller calls or field updates. Evidence: `art/renders/water_final_validation.log` and `water_blobs_*.png`.

Mobile measurements have not been performed. The chosen limits bound work; they do not establish a phone frame-time or battery result. Godot specifically cautions that preserved render targets and viewport textures can be costly on [mobile tile renderers](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html#mobile-tiled-renderers). Profile idle, continuous pouring, and a fully covered rug on the target devices before increasing resolution or shader complexity.
