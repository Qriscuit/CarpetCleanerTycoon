# Carpet Cleaner gameplay capture driver

`capture_ad_gameplay.gd` records production play through ordinary touch input. It requires `--shop-test`, refuses an existing output ledger or event log, and confines its output to a new session directory beneath `build/ad-capture-v2/`. It never touches a normal player save.

The driver does not write dirt masks, grant coins, invoke completion, increase brush strength, skip arrival/reveal animations, call the dirt controller's stroke methods, or manually advance physics. A new session earns Mint Meadow, Sunburst and Fox's Den in order. An optional resume starts from a previously earned checkpoint copied into a new isolated session.

## Recording

Use the pinned Godot 4.7.2 stable Mono wrapper. Engine-side movie options go **before** the `--` separator; capture arguments go **after** it along with `--shop-test --audition-audio`.

Godot's movie writer locks the output dimensions at engine startup. The recording pass therefore uses an isolated project copy whose initial viewport is 1080 × 1920 and visible window is 540 × 960. The source game's project settings remain unchanged. After the production Workshop enters the tree, the harness reapplies that capture viewport size and viewport stretch mode, allowing the actual HUD and camera to perform their normal layout.

On this Windows wrapper, an argument of the form `--ad-output=S:/Game Projects/...` was split at the space even when passed as one quoted PowerShell argument. Use a space-free resource path relative to the isolated project instead. For a project at `build/ad-capture-v2/session-001/project`, `--ad-output=res://../../full-game-001` resolves to the appropriate sibling session.

## Driver arguments

| Argument | Default | Meaning |
| --- | --- | --- |
| `--ad-capture-mode=smoke` or `full` | `full` | Smoke ends after a short ordinary gameplay sample; full waits for the requested paid restorations and departure. |
| `--ad-output=...` | Workspace `build/ad-capture-v2/session-001` | New session directory. Existing evidence is not overwritten. |
| `--ad-fps=30` | `30` | Must match the engine's `--fixed-fps` setting. |
| `--ad-rug-count=1` to `3` | `3` | Required full restorations in this run. |
| `--ad-smoke-seconds=10` | `10` | Smoke sample duration. |
| `--ad-max-frames=12600` | `fps × 420` | Bounded stop if expected completion fails. |
| `--ad-resume-from=...` | Empty | Existing earned checkpoint under the same capture root; copied before loading. |

## Native timing and input

The harness sends one `InputEventScreenDrag` per rendered frame through the viewport's `push_input` method. Finger positions come from rug-local positions projected by the production camera, accounting for the game's actual touch contact offset. Each full-length stroke takes two seconds, with a 0.16-second lift. The starting brush remains at its normal width and removal strength. Four overlapping lanes each receive ten distinct passes. A second sweep is available only if production completion has not occurred; two unsuccessful rounds abort with an error.

One narrow clock adaptation is necessary for deterministic movie export: the production pointer callback reads wall-clock milliseconds, while Godot's movie writer advances fixed simulation time even if rendering is slower or faster than real time. Immediately before each movement event, the harness sets only the preceding brush-input timestamp to one movie frame ago, alternating 33 and 34 milliseconds at 30 fps. No physics delta, scene timer, brush strength, mask, particle rule or payout is changed. This keeps visible movement, dirt response and brush sound at ordinary playback speed.

The driver keeps in-game music off through the existing setting and effects on, so the editor can add one continuous original music bed. `--audition-audio` is essential because test mode otherwise mutes physical audio. Focus loss aborts a take instead of presenting silently suspended gameplay as a valid recording. Keep the recording window focused until the process exits.

## Evidence and edit selection

- `logs/events.jsonl` is flushed after every event. It records the game phase, actual rug and job IDs, progress, each stroke's direction/pass/lane, checkpoints and reveal starts.
- `take_manifest.json` records success/failure, timing policy, all events, full-restoration acceptance, real payouts and balances.
- `saves/ledger.json` and `saves/audio.cfg` are the isolated production save and audio preferences.
- `checkpoints/` holds copies of earned saves after arrival, each completed lane and each paid restoration. A restoration-paid checkpoint can already contain the next reserved job because that is the production ledger's behavior.
- `stills/` contains native render captures during real clean reveals, labeled by rug ID. These are distinct from the preproduction fixture references.

`engine_frame` is the engine's process-frame index; `frame` is the driver's frame counter. In the successful 10-second smoke run, the engine index is one less than the driver count. Confirm the first-frame relationship against the actual movie before using the log as an edit decision list. Do not assume the human-readable `seconds` field alone establishes an exact encoded video in-point.

For Fox opening candidates, filter `stroke_start` entries with `fox_hook_candidate: true`. The first two lanes cross the face. Passes 5–10 are marked for review; the strongest visual moment still needs human-size inspection. The final entry into `VACUUMING` proves that the normal automatic threshold was crossed. `hero_reveal_start` identifies the normal 2.4-second clean appreciation beat. Neither an early Finish press nor a manually cleared fixture can satisfy the full-restoration check.

The successful smoke sample is `build/ad-capture-v2/smoke-game-004`: 300 driver frames, 10 seconds, three completed normal strokes plus part of a fourth, with 11.313% surface clearance. Its purpose is input, render and audio setup verification, not a claim that a whole rug takes ten seconds. The full-session manifest is the authority for subsequent completions.

## Verified full session

`build/ad-capture-v2/full-game-001` completed successfully in 8,360 driver frames at 30 fps. All three rugs reached the normal 99% rule at 99.0040935% accepted clearance, paid 40 coins each, and left the expected balances of 40, 80 and 120. Every rug retained starter width 1.0, power 1.0 and removal 0.1 per pass. No second sweep round was required. Each completion preserved 54 frames of suction and 72 frames of reveal.

The independent source/log audit is `logs/independent_audit.json`. Reveal engine-frame ranges are Mint `[2687,2759)`, Sunburst `[5475,5547)`, and Fox `[8263,8335)`. Fox's final suction begins at engine frame 8209. First-lane face passes 9 and 10 begin at engine frames 6164 and 6229; adjacent-lane passes 9 and 10 begin at 6814 and 6879. Each complete stroke spans 60 frames. These are selection candidates, not an instruction to omit visual review or to treat a 15-second advertisement as a continuous whole restoration.
