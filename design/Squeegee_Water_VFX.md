# Squeegee water sheet — visual design and Godot implementation

Status: implemented in the Gym, 2026-09-21. The original design below records the intended look and reasoning. The implementation notes here describe the shipped first pass; the earlier interactive shape study remains a schematic, not a game capture.

## Implemented first pass

- `scenes/effects/squeegee_water.tscn` is an authored child of the Gym, in world space alongside the tool hierarchy. Select **SqueegeeWater** to tune upward speed, forward speed, thickness, and ripple height in the Inspector. No Houdini asset, skeleton, transparent material, fluid solver, or per-droplet physics body is required.
- `gym.gd` measures the positive increase in `extraction_coverage_total` around the existing painter call. The visual reference rate is **0.65 wet-area-equivalent m²/s**, with a 65 ms strength response. The same effective elapsed-time limits as the painter are used. Pointer gaps receive only a bounded 25–75 ms bridge; a release or a zero-removal stroke closes the source immediately.
- Three permanent **316-vertex / 444-triangle** closed sheets share topology. Each has 96 stored source poses and a 16 × 7 world-space center grid. CPU trajectory sampling feeds shader uniforms; mesh resources are not rebuilt during strokes. A turn beyond approximately 70° or a contact jump over 0.38 m starts a new segment. Ordinary old tails drain; on extreme pool overflow the oldest tail is retired immediately to keep the limit at three.
- Seven transverse trajectories test the rug and tile separately. The landing is one continuous, rounded, scalloped strip per sheet, drawn through a shared **six-instance MultiMesh** (three strips × two height layers). Each strip topology is 33 × 9 vertices. A one-time binary footprint texture, copied from the existing surface mask, clips each layer to its actual surface. It is not another mutable wetness simulation.
- One shared pool of **24 droplets** uses the existing hose droplet material. The landing gently settles over 0.20 s; droplets use short ballistic trajectories and stop on the appropriate surface. Water shadows are off. Steady motion uses three draws: sheet, splash batch, and droplet batch; three simultaneous sheets require five. These are bounded geometry/draw budgets, not measured Android performance.
- The splash is presentation only: it does **not** rewet the carpet, alter the extraction count, or affect paid progress. Reset, exercise switch, and switching away from the squeegee clear the pools. Ordinary release/focus loss lets already emitted water land. Idle processing stops completely.
- Run `scenes/test/squeegee_water_preview.tscn` with **F6** for a looping art review of actual Gym extraction. **Space** pauses/resumes the stroke, **Tab** switches oblique/overhead views, and clicking hands control back to the normal Gym. This optional scene starts with a fully wet practice rug; the normal Gym still uses hose → squeegee progression.
- `tools/validate_squeegee_water.gd` supplies renderer-backed checks for geometry, supply, screen-space dragging, rate normalization, release, reversals, both landing heights, resource bounds, reset, focus loss, idle shutdown, and paid-save isolation. Its reproducible captures are written under `art/renders/squeegee_*.png`.

The source below is the original design rationale; where starting values differ, this section and the current exported script defaults take precedence.

## The intended look

An opaque cyan **sheet jet** leaves the leading edge of the squeegee. It is a wide ribbon with a closed, shallow rectangular cross-section: a bent cuboid with softened edges and visible thickness. It rises, crests, and falls onto a broad, low **landing splash**. Gentle traveling ripples disturb its surface and edges. A few secondary droplets jump from the landing rim. The carpet behind the blade becomes visibly drier using the existing wetness mask.

The launch lip sits approximately 2.5 cm above and slightly ahead of the contact edge. Its exact position can be hidden behind the blade. The launch lip should be stable; the ripple amplitude increases after the water has left it. A thin moving highlight makes forward flow readable from the Gym's overhead camera. The splash sits at the far end of the arc, in the direction of the push; it is not a screen-space background effect.

Starting art values for a wet, ordinary forward pass:

| Property | Starting value | Purpose |
| --- | --- | --- |
| Sheet width | 0.60–0.68 m | Approximately the existing 0.68 m extraction head |
| Visible thickness | 0.02–0.04 m | Reads as a solid volume in oblique and overhead views |
| Launch clearance | 0.025 m above the carpet | Hides the join near the blade and avoids surface fighting |
| Arc rise above launch | Approximately 0.20 m | A short, relaxed throw |
| Throw relative to steady blade motion | Approximately 0.63 m | The splash stays visibly ahead of the blade |
| Flight duration | Approximately 0.42 s | Leaves time to read the arc and finish a stroke naturally |
| Lateral flare | Up to 8% by landing | A modest spread across the sheet |
| Ripple displacement | 0.004–0.008 m | Soft flowing edges without breaking the silhouette |
| Splash footprint | Approximately 0.75 m wide × 0.25–0.35 m deep | A broad, shallow landing rather than a circular hose crown |
| Splash / droplet release | 0.20 s / up to 0.40 s | Brief settling after the last sheet lands |

These are proposed tuning values, not measured physical water quantities or performance results.

## Motion and water amount

1. A stationary blade emits nothing. The current extraction painter already requires displacement.
2. Moving through wet carpet emits a broad, thick sheet. Its amount follows newly removed water.
3. Moving through nearly dry carpet gives a thinner, weaker sheet and fewer droplets. Already extracted pixels cannot repeatedly produce a full sheet.
4. Faster motion increases the throw within a controlled range. It does not create water when the carpet is dry.
5. When motion stops, new emission stops after a short input-smoothing interval. Water already emitted completes its original trajectory.
6. A sharp direction change starts a new sheet segment while the previous one drains in world space. This avoids twisting a wide ribbon through itself.

“Forward” follows the direction of travel projected onto the carpet. Preserve the currently fixed squeegee orientation in the first prototype. Across the blade, a normal push/pull produces the full-width sheet. A sideways scrape produces a narrow edge discharge. Use the existing rectangular head's projected width, rather than rotating only the model while the extraction footprint remains axis-aligned:

```text
f = normalize(planar_stroke_delta)
b = normalize(up × f)
W_projected = 2 × (half_x × |b · blade_x| + half_z × |b · blade_z|)
```

Here `half_x = 0.34 m` and `half_z = 0.075 m` match `DirtController.SQUEEGEE_HALF`. A small inset hides the source join inside the leading contact region. Full tool rotation could be a separate change if desired; it would require rotating the extraction footprint too.

## Equations

### Art shape

For a settled straight stroke, a convenient description is:

```text
C(s) = (1-s) S + s E + 4 H s (1-s) up,   0 ≤ s ≤ 1
```

`S` is the launch lip, `E` is the landing point, and `H` is the rise above the straight line joining the endpoints. This describes a parabolic arc, with endpoints fixed on their intended surfaces. It is useful for discussing and tuning the silhouette.

### Runtime flight

Use the same emission-history idea as the hose, with an upward launch and inherited blade velocity:

```text
C(a,t) = P(t-a) + [v_push f(t-a) + k v_blade(t-a) + v_up up] a
         - 0.5 g a² up
```

`a` is the age of water in flight, `P` is the launch lip's historical position, `f` is historical push direction, and `k = 1` is the initial velocity-inheritance setting. With steady blade motion, inheritance keeps the arc ahead of the moving tool. After stopping or reversing, previously emitted water continues along its old trajectory.

Start with `g = 9.8 m/s²`, `v_up = 1.98 m/s`, and `v_push = 1.50 m/s`. For a launch 0.025 m above its landing plane:

```text
T = (v_up + sqrt(v_up² + 2 g × 0.025)) / g ≈ 0.416 s
rise = v_up² / (2 g) ≈ 0.200 m
relative_forward_distance = v_push T ≈ 0.624 m
```

World-space travel also includes inherited blade velocity. On a moving/turning source, find the actual surface crossing from the emitted trajectory rather than assuming a landing directly in front of the current blade.

### A thick sheet rather than a line

Sweep a rectangular cross-section along the centerline:

```text
V(s, ξ, η, t) = C(s,t) + ξ W(s,t)/2 B(s,t)
                        + [η D(s,t)/2 + ripple(s,ξ,t)] N(s,t)
```

`ξ ∈ [-1,1]` runs across the width; `η = ±1` gives the top and bottom faces; `D` is thickness. `B` is the transported width axis and `N` is perpendicular to the local tangent and width axis. Connect the top, underside, both side walls, and the start/end caps. Use parallel transport as in the hose to keep the frame stable.

For the undulation, combine two small sine waves along/across the sheet, multiplied by an envelope that is zero at the blade and reduced at the landing. Keep the width change around 2–5%, and surface displacement below approximately 8 mm. Traveling highlights follow the emission age so the flow reads from blade to splash.

## Fit to the current code

`gym.gd::apply_selected_tool_stroke()` currently delegates the squeegee to `soil.apply_squeegee_stroke()`. The shared painter updates `extraction_values`, `extraction_coverage_total`, and the existing 256 × 416 L8 wetness mask. It already caps extraction at water present in each pixel and blocks extraction before the water stage is complete.

The first integration needs no extra mask scan:

```gdscript
# Implemented Gym hook.
var before: float = soil.extraction_coverage_total
soil.apply_squeegee_stroke(world_from, world_to, elapsed)
var removed: float = maxf(0.0, soil.extraction_coverage_total - before)
squeegee_water.feed_stroke(world_from, world_to, elapsed, removed)
```

Convert the summed pixel increase into wet-area-equivalent rate:

```text
pixel_area = (2 × RUG_HALF.x / MASK_SIZE.x) × (2 × RUG_HALF.y / MASK_SIZE.y)
removed_area = removed × pixel_area
flow_drive = clamp((removed_area / effective_dt) / reference_area_rate, 0, 1)
```

The game's wetness is normalized saturation, not liters. Treat this as a visual driver. An actual volumetric estimate would need an explicit carpet absorption capacity or reference film thickness. A useful first reference rate is about 0.9 wet-area-equivalent m²/s, subject to play tuning. Ease visual strength over approximately 60–100 ms, but only allocate emission from positive removal; dry motion must not refill a visual reservoir.

The input handler calls `apply_selected_tool_stroke()` **before** updating `contact_point` and placing the mesh. Feed the effect from `world_from/world_to`, or synchronize the contact marker after placement. Reading the model transform inside the current callback would use the previous input event's pose.

Accumulate input events and emit on the visual update with a short pose history. Subdivide large motion steps at a bounded cadence; do not emit one disconnected cuboid per mouse event. Clamp velocity derived from tiny event intervals, use the same effective elapsed-time convention as the extraction painter, and impose a maximum flight duration. A release should close the emission window immediately; already allocated airborne water still lands.

## Godot implementation

Proposed new files:

| File | Responsibility |
| --- | --- |
| `CarpetToy/scripts/squeegee_water.gd` | Stroke input, extracted-water drive, fixed pose history, ballistic trajectories, lifecycle, and debug values |
| `CarpetToy/scripts/squeegee_water.gdshader` | Deform a permanent closed ribbon, gently ripple its edges/surface, and shade it in the hose's opaque cyan palette |
| `CarpetToy/scripts/squeegee_water_impact.gd` | Bounded landing patches and a shared droplet pool, with wide directional splash placement |
| `CarpetToy/scripts/squeegee_water_impact.gdshader` | Shallow elongated scalloped splash and low rim |

Attach the controller as a world-space sibling of the tools, as the hose is. Proposed public API: `setup(footprint)`, `set_enabled(bool)`, `feed_stroke(from,to,elapsed,removed)`, `end_stroke()`, `reset()`, and `debug_stats()`.

Allocate an `ArrayMesh` once. Use 16 stations along the arc and 7 samples across its width, with top, bottom, side faces, and caps. With separate vertices along face seams, that is approximately **316 vertices and 444 triangles per sheet**. Encode longitudinal position, across-width position, and face identity in the mesh attributes. Upload the sampled frames/width/thickness through shader uniforms. Do not rebuild the mesh every frame.

Keep a fixed pool of up to **three sheet instances**: one current sheet plus two draining segments for quick reversals. Share mesh and shader resources; each instance has its own parameters. On overflow, retire the oldest draining segment with a short finish rather than growing the pool. Preserve a fixed **96-sample pose history** and bounded flight age, following the hose's existing approach.

Use the carpet and tile heights already present in `water_jet.gd` (`0.071` and `0.006`). For the wider sheet, test across-width lanes at the landing: a carpet edge can have one portion landing on the rug while another continues down to tile. Clamp/truncate each lane at its own surface crossing; split the associated contact patch by surface. Do not stretch a single elevated splash across the carpet edge or let the ribbon continue through the surface.

The hose's circular crown is useful reference code, but scaling its entire controller would also distort world-space droplets. Give the squeegee an elongated landing mesh and directional droplet launches. Reuse `water_jet_droplet.gdshader` and the fixed `MultiMesh` pooling pattern. Start with **24 droplets total**, not 24 for every draining sheet. Use a small shared pool of splash patches so old impacts can finish when the tool turns.

Normal steady use would render one sheet, one splash batch, and one droplet batch. Quick turns may add up to two draining sheet surfaces. Keep all materials opaque, shadows off for the water, appropriate deformation bounds on the meshes, and stop processing after the last sheet/splash/droplet expires. This is a proposed bounded budget; actual Android frame cost still needs measurement during implementation.

## Gameplay decision for review

Recommended first version: the thrown water is a visual representation of extraction. It splashes, thins, and disappears; it does **not** add wetness back to the landing point. This preserves the existing relaxing wet-then-extract loop and lets each pass leave progress behind.

If the intended mechanic is instead to push real water across the carpet and eventually off its edge, that requires redistribution: remove water under the blade, deposit the same amount ahead, and count only water leaving the carpet as extracted. The current `extraction_values` represent cumulative removal, so that alternative needs a gameplay/mask redesign, not just an extra splash callback. Decide this explicitly before implementing that version.

## Build and review sequence

1. Create the fixed closed ribbon and a fixed-pose oblique preview. Confirm its thickness, width, crest, and read from the actual overhead Gym camera.
2. Drive it from measured extraction and historical blade motion. Verify stationary/dry behavior, input event timing, steady pushing, release, reversal, and a short wet stroke.
3. Add lane-aware rug/floor landing, a broad scalloped patch, and the shared droplets. Test near every carpet edge and corner.
4. Bind Gym reset/exercise switch/tool change/scene exit. Reset cancels everything; ordinary release lets existing water settle. Preserve the existing wetness texture and paid-save isolation.
5. Tune ordinary/fast/nearly dry passes visually, then profile on the target device. Add focused integration checks for water-dependent emission, old trajectories surviving release, bounded resources, landing positions, reset, and the shared extraction gate.

## References

Current project sources: `CarpetToy/scripts/gym.gd`, `workshop.gd`, `dirt_controller.gd`, `water_jet.gd`, `water_jet_impact.gd`, and `design/Water_Jet.md`.

Godot 4.6 documents the relevant building blocks: [ArrayMesh construction](https://docs.godotengine.org/en/4.6/tutorials/3d/procedural_geometry/arraymesh.html), [spatial vertex shaders](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html), and [MultiMesh batching](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html). The geometry, tuning values, lifecycle, and integration proposal above are specific design choices for this project.
