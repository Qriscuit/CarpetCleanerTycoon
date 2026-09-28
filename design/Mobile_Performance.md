# Mobile performance pass

27 September 2026. This pass targets the squeegee equip/first-use hitch and recurring CPU work. These are desktop measurements, not a phone frame-rate guarantee.

## Measured results

The same graphics-backed benchmark ran before and after the changes with Godot 4.7.2 Mono, GL Compatibility, an NVIDIA RTX 3070 and a 390 × 844 window. It selects the Gym wet rug, presses Squeegee, then executes 120 controlled strokes along a curved path. Individual CPU operations are timed separately from the rendered frame wait.

| Work | Before | After |
| --- | ---: | ---: |
| Gym squeegee button, complete CPU handler | 27.52 ms | 1.73 ms |
| Repeated squeegee button | 26.62 ms | 1.76 ms |
| Stroke CPU, median | 9.00 ms | 5.84 ms |
| Stroke CPU, 95th percentile | 10.98 ms | 7.22 ms |
| Splash/ridge/runoff CPU, 95th percentile | 15.62 ms | 7.99 ms |
| First effect update CPU | 12.18 ms | 5.01 ms |
| First rendered stroke frame, wall time | 35.61 ms | 17.29 ms |
| Rendered frame wall time, 95th percentile | 26.11 ms | 16.69 ms |

The frame measurements include display synchronization and scheduling. They must not be treated as isolated GPU timings. Resource-loading times are excluded from this comparison because filesystem/shader caches differ between launches. The benchmark controls effect advancement; it is a repeatable workload, not a full human playthrough.

Raw results: [before](../build/mobile_profile_before.json), [after](../build/mobile_profile_after.json). The final extracted amount, contour segment count, spill count and runoff packet state match in these two runs.

## Changes

- **Instant wetting:** `dirt_controller.prepare_extraction_stage()` copies precomputed carpet-footprint data. The Gym shortcut no longer performs distance, feathering and individual image writes for 106,496 pixels. Empty rounded corners and fringe gaps remain dry; images, textures and the dirt pool are reused.
- **Squeegee painting:** fixed sweep buffers replace four temporary arrays per stroke. Already-extracted pixels skip geometry work. Once a pixel has full blade coverage, additional rotation poses cannot increase its weight and are skipped. Cleaning strength and mask values are unchanged.
- **Water ridges:** `squeegee_water_trail.gd` caches the fixed grid positions, valid source pixels and bilinear weights during setup. Rebuilds read changing water/extraction values without recomputing the same mapping. Resolution, geometry, update cadence, ridge lifetime and runoff behavior are unchanged.
- **Upgrade UI:** mask-only progress changes no longer reconstruct the full progression view and reconfigure tool transforms. Wallet/purchase signals and phase changes still refresh equipment and purchase availability.
- **Saving:** a successful immediate checkpoint cancels its pending delayed checkpoint. A failed write retains the existing retry opportunity. Rewards, purchases, release, focus loss and scene exit still use the existing durable save rules.

The two fixed caches add approximately 0.9 MiB per active cleaning scene. No additional memory is accumulated per swipe. Cache generation happens during setup, not on first extraction. The current carpet silhouette and mask dimensions are fixed; future variable geometry must rebuild these caches with its footprint.

## Verification and reproduction

[validate_mask_optimization.gd](../tools/validate_mask_optimization.gd) compares against a frozen original painter and full-carpet wetting path. It checks masks, totals, complete snapshots, reset behavior, signals and resource identity. [validate_trail_optimization.gd](../tools/validate_trail_optimization.gd) compares sampled fields, pressure, contours and runoff against the original sampler. [validate_workshop_optimization.gd](../tools/validate_workshop_optimization.gd) checks UI refresh frequency, purchases, save/retry behavior and exact-once rewards.

Run the graphics benchmark from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/profile_mobile_cleaning.gd -- --shop-test --profile-label=local
```

This writes `build/mobile_profile_local.json`. Keep the original before/after files when making new measurements. Run graphics validators sequentially; competing windows can cancel input through normal focus handling. Always use `-- --shop-test` to isolate saves.

Existing Gym, squeegee controls, ridges, runoff, paid wet jobs, store-loop, hose and reward tests also cover shared behavior. Review assertion failures and engine logs rather than treating a final `VERIFIED` label alone as success.

This pass completed 2,765 checks across 14 targeted validators with no failures. Graphics validators ran sequentially with the pinned engine and isolated saves. This is targeted regression coverage, not a claim that every historical repository test was run.

## Fast hose motion follow-up

Rapid hose movement uses several circular stamps per direct-water tick. It also feeds multiple passive reservoirs, which can deposit in the same frame. This increases mask-painting work even though the jet and splash meshes keep their fixed sizes. The follow-up benchmark separates the contact callbacks (painting and progress UI) from the jet's visual/history work.

Run it with the same pinned graphics renderer and isolated saves:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/profile_mobile_hose.gd -- --shop-test --profile-label=local
```

The benchmark performs 180 frames each of stationary pouring and rapid figure-eight motion, at the starter and maximum hose levels. It uses actual Gym input projection, fixed 1/60-second water updates and a 390 × 844 window. It writes `build/mobile_hose_profile_local.json`; this remains a repeatable desktop workload rather than a device FPS test.

Two changes address the cost:

- `apply_water_blob()` caches the exact Float32 pixel coordinates in two small axis arrays (2.6 KiB), uses conservative circular row bounds to skip empty corners, and skips feather calculations inside the solid core. The original distance test, accumulation order, per-pixel values and image conversion are retained. The frozen-painter regression covers 3,547 exact-output checks.
- Passive soaking still calculates the original stamp payloads at 10 Hz, but a fixed 12-entry FIFO distributes their callbacks across nearby frames. At 60 Hz it applies at most one passive stamp per update; at 30 Hz, two. The direct hose and splash animation are unchanged. One stationary reservoir retains its original immediate 10 Hz schedule.

The FIFO stores the original positions, radii and strengths before reservoir reuse. Pending work keeps the effect alive until drained; reset, profile changes and wet-stage completion cancel stale queued work. With six active reservoirs, the final passive callback can be about 83 ms later at stable 60 Hz. Deliberately irregular frame intervals reached 137 ms in the scheduler tests, because dispatch waits for a render update. This changes delivery timing, not the sampled passive amounts. Whole-game masks need not match on each frame: direct and passive deposits can interleave differently, and stage completion can cancel pending work. Dedicated tests compare the passive event sequence after draining, alongside bounds and cancellation behavior.

Final desktop results (same engine, renderer and hardware as the first pass):

| Hose workload | Before CPU p95 | After CPU p95 | Before CPU maximum | After CPU maximum |
| --- | ---: | ---: | ---: | ---: |
| Stationary, starter spout | 3.70 ms | 3.10 ms | 4.63 ms | 3.33 ms |
| Rapid motion, starter spout | 6.70 ms | 6.90 ms | 6.89 ms | 7.04 ms |
| Stationary, maximum spout | 10.14 ms | 8.34 ms | 10.82 ms | 8.63 ms |
| Rapid motion, maximum spout | 15.47 ms | 10.32 ms | 20.00 ms | 13.51 ms |

The maximum-spout rapid-motion frame maximum dropped from 20.76 ms to 16.69 ms including display synchronization. The starter fast-motion case has similar CPU peaks, slightly higher in this run because passive work now also lands on some direct-deposit frames. Stationary wet-mask hashes/totals match exactly. Rapid-motion results have five queued passive stamps at the end of the timed window; the new benchmark additionally drains all pending work and confirms it returns to idle. The original before file predates those extra drain statistics.

Raw measurements: [hose before](../build/mobile_hose_profile_before.json), [hose after](../build/mobile_hose_profile_after.json). The original per-pixel painter and passive event payloads are retained as independent references in [painter validation](../tools/validate_hose_painter_optimization.gd) and [scheduler validation](../tools/validate_soak_scheduling.gd). Together with the water-jet, hose-upgrade, Gym, paid wet-job, checkpoint and wet-mask suites, this follow-up passed 39,682 targeted checks across eight validators. No Android device was attached during verification.

## Remaining phone checks

No Android device was profiled in this pass. Test the signed APK on the intended phone, both immediately after launching and after sustained use. Check first equip, rapid direction changes, repeated passes on extracted pixels, high-level hose/squeegee tools, carpet-edge runoff, rotation, background/resume and paid-job completion. Record the device, refresh rate, thermal state and frame-time spikes.

Wet snapshot construction still takes about 15 ms in this desktop workload, and JSON serialization/storage time is additional. This pass removes duplicate checkpoints without weakening persistence or changing saved mask rounding. Cold shader compilation, storage stalls, thermal throttling and slower mobile CPUs/GPUs remain separate possible sources of hitching. Further changes should follow device measurements; reducing visual quality or moving save transactions to a worker requires separate validation.
