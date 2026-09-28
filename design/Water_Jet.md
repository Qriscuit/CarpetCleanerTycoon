# Continuous Gym water jet

Open **Settings → Gym → Rug 2 · Wet tools**. Hold the hose to pour and drag across the carpet. The stream starts at the visible outlet, reaches the surface after its flight time, forms a low undulating crown, and emits short secondary droplets. Water already in flight trails behind a moved nozzle and drains after release. The former radial charge is hidden.

The compact **Hose upgrades** section previews one improvement, **Spout Lv 1–5**, with −/+ controls. Higher levels widen the bottom of the column and its landing, soak faster, and grow a larger soft wet fringe. These previews are free, last for the current Gym visit, survive rug resets/exercise changes, and do not modify production upgrades or saves. **Squeegee** instantly fills the practice rug; **Water hose** clears wetness/extraction. Both shortcuts also discard water still in flight and passive reservoirs, including on repeated clicks.

## Runtime structure

`gym.gd` adds `NozzleSocket` at the sprayer's authored outlet pivot and reads its global position and +Z direction. The jet root is a sibling of the tools so past water stays in world space. `water_jet.gd` allocates a 96-entry pose history, one 16-ring × 10-side tube with end caps (162 vertices, 320 triangles), a material and an impact controller exactly once.

For parcel age `a`, the centerline is `nozzle_position(t-a) + exit_velocity(t-a)*a + gravity*a*a/2`. History samples are at 120 Hz, linearly interpolated within each input frame. Sixteen rings cover the visible flight interval; their centers, radii and parallel-transport side axes are passed to `water_jet.gdshader`. Triangle topology never changes. The shader creates small traveling radial waves that vanish at the nozzle, plus opaque cyan shading and longitudinal highlights. Geometry bounds cover displaced vertices for correct culling.

The flat Gym rug and surrounding tiles use analytical height-plane contact, gated by the existing rug silhouette. The column ends at the carpet or floor height rather than extending through it. Floor impacts show a splash but never paint the carpet. This controller intentionally assumes the flat Gym surface; arbitrary walls, tilted rugs or uneven terrain would require collision queries.

`water_jet_impact.gd` is the shared perimeter splash renderer used by the hose and squeegee. It allocates one open-center strip (1,161 vertices / 2,048 triangles) and a fixed 24-instance droplet MultiMesh. The hose uses a circular rim that begins just under the column edge and curls outward toward the upgrade's landing radius; the squeegee uses a rounded rectangle around all four head edges, with no airborne water column. Traveling scallops rise and settle in short, low arcs. A small immutable carpet-silhouette texture keeps the rim on the rug or surrounding floor; it is not another wetness map. Droplets retain their world-space launch points and use simple ballistic motion. The rim shrinks over 0.20 seconds after contact stops, and droplet lifetimes are capped at 0.46 seconds. The three water shaders are opaque and use no screen refraction, transparent overlays, Decal nodes or particle trails, making them suitable for the existing GL Compatibility renderer.

## Gameplay and lifecycle

The jet emits `water_contact(position, radius, strength)` at a bounded 20 Hz cadence. Moving impacts are sampled along their swept path with at most eight stamps per update, dividing strength across samples. `gym.gd` passes those events into `DirtController.apply_water_blob()`: despite its historical method name, it is the shared circular wetness brush. The existing 256 × 416 L8 texture and cumulative wet/extraction arrays remain authoritative. No second wetness texture is created.

`water_soak.gd` holds six preallocated, world-anchored capillary reservoirs. Feeding a spot increases its dwell time `t`; its radius follows `r(t) = r_direct + (r_max - r_direct) * (1 - exp(-spread_speed * t))`. Staying still therefore continues spreading wetness beyond the already-saturated center. Halo deposits use a 78% edge feather, a 0.3-second onset, and a bounded 10 Hz cadence; they increase real carpet wetness, not just a visual circle. The base passive rate is 2.4 wetness units/second, three times the earlier 0.8 rate. A separate nonlinear `passive_soak_multiplier` scales it with level; continuing to hold smoothly builds another 35% intensity between 0.3 and 1.5 seconds, then stays capped. When contact moves away, the old spot finishes a 0.7-second fading after-soak without growing further. A new distant spot starts small, rather than inheriting the old radius. Nearby deposits merge and a full pool reuses its oldest slot. Ordinary direct-contact brushes retain their existing feather.

Holding the nozzle still continues watering. Startup never wets before contact; release allows already emitted water to finish, including any final partial wetness deposit from a short tap. A rapid re-press reconnects the new stream to the surviving airborne tail and preserves its old trajectory. Full wetness locks further deposition, clears every soak reservoir and unlocks the squeegee. Reset and exercise switching clear the history, column, crown, droplets and reservoirs immediately, while ordinary release drains naturally. Changing a preview level cancels pending water but preserves the carpet's existing wetness. A stopped empty emission (a quick tap within one frame) also returns to idle. Once all effects and after-soaking end, the controller disables its process callback.

This presentation is attached to the Gym only. Production stores retain their existing wet-tool behavior.

## Art and performance controls

In `water_jet.gd`: `LAUNCH_HEIGHT` is 0.50 m, `NOZZLE_RADIUS` 0.056 m matches the 0.05 m outlet scaled by 1.12, `EXIT_SPEED` 2.4 m/s, gravity 9.8 m/s², and `WET_STRENGTH_PER_SECOND` 2.6 before the upgrade multiplier. Changing outlet height or speed changes time of flight and visible lag. `MAX_FLIGHT_TIME` bounds the effect.

`water_hose_profile.gd` is the single tuning source for all five levels:

| Spout level | Bottom column radius | Landing radius | Direct wet radius | Maximum spread radius | Direct rate | Passive rate | Mature passive units/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 0.068 m | 0.17 m | 0.26 m | 0.70 m | 1.0× | 1.0× | 3.24 |
| 2 | 0.085 m | 0.21 m | 0.30 m | 0.82 m | 1.3× | 1.35× | 4.374 |
| 3 | 0.103 m | 0.25 m | 0.35 m | 0.94 m | 1.65× | 1.8× | 5.832 |
| 4 | 0.123 m | 0.29 m | 0.40 m | 1.07 m | 2.0× | 2.35× | 7.614 |
| 5 | 0.145 m | 0.33 m | 0.46 m | 1.20 m | 2.4× | 3.0× | 9.72 |

The outlet stays the same size. Column widening eases in after 18% of the flight, shows roughly half of the upgrade's added width at mid-flight, and reaches the authored contact radius by 88%. This monotone, rounded profile gives the stream a substantial middle without creating a bulb that pinches again before impact. The larger spout is therefore readable halfway to the carpet instead of appearing only as an impact flare. The HUD's width is the landing diameter. Spread approaches its cap smoothly; growth rates for levels 1–5 are 0.55, 0.69, 0.84, 1.01 and 1.20 per second. The maximum normal passive stamp is 0.972, below the shared painter's strength-1 cap, so top-level intensity is not silently clipped. All amounts remain clipped to the authoritative carpet footprint and per-pixel saturation.

The stream shader controls ripple amplitude, wave speed, color and highlight. The impact shader controls scallop and crown height. The impact controller controls droplet rate, lifetime and size. Keep the shader array length synchronized with `RING_COUNT` if mesh detail changes. Keep history duration and displacement bounds sufficient for the maximum flight.

The tube, crown and droplet batch use three water draw surfaces. Resources and node counts remain fixed across motion, release, upgrades, resets and rug changes. Frame delta, history capacity, droplets and wet-stamp work are bounded. Soaking adds no nodes, meshes or textures. It calculates at most six halo stamps per 0.1-second tick, then distributes their callbacks through a fixed FIFO: one per frame at 60 Hz, two at 30 Hz, up to six on a long frame. Positions, radii and strengths are captured at the original tick; reset, profile changes and stage completion clear pending work. The shared circular painter caches pixel coordinates and skips empty corners without changing its output. See [Mobile performance](Mobile_Performance.md) for measurements, timing tradeoffs and validation. Larger profiles still touch more mask pixels; bounded costs do not replace Android GPU/frame-time profiling.

## Verification

Run the shared **Godot 4.7.2 Mono/.NET-only** wrapper with the graphics renderer and isolated saves. It validates the complete bundle and does not select a standard build or another version:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_water_jet.gd -- --shop-test
```

The validator uses the equipped hose and checks attachment, startup, stationary contact, world-space lag, drained release, idle shutdown, carpet/floor separation, long-frame bounds, reset/switch cancellation, full-wet gate, extraction, fixed resources and preservation of paid progress. It captures portrait, landscape, a moving stream, an oblique close-up and extraction under `art/renders/water_jet_*.png`. The old `validate_water_blobs.gd` entry point forwards to this current contract.

Also run `validate_gym.gd`, `validate_tool_selection.gd` and `validate_wet_cleaning.gd` for navigation, input and shared gameplay regressions. The previous charged-blob implementation remains on disk as an unused prototype; its historical notes are in `Water_Blobs.md`.

`validate_hose_upgrades.gd` covers the spout previews, stationary growth, shared-mask absorption, anchored spreading, cancellation, idle shutdown, save isolation and phone layouts. Run it with the same renderer and `-- --shop-test` flag. Its screenshots are `art/renders/hose_upgrade_*.png`.

For a headless check of the passive contribution alone, add `--headless` before `--path`, and add `--soak-only` after `-- --shop-test`. This mode measures real shared-mask wetness at equal elapsed time for all five levels, checks the hold ramp and intensity cap, and verifies rounded-edge clipping and idle retirement without opening a window.
