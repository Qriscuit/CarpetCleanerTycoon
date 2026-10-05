# Third ad: real tools capture

The preferred complete-job source is `build/ad-capture-v3/wet-tools-002/restorations.avi`: 1,493 frames / 49.766667 seconds at native 1080 × 1920, 30 fps. It follows a production Fox’s Den wet job from dry arrival through hose wetting, squeegee extraction, automatic full restoration and the normal clean reveal.

A matching starter-brush source is `build/ad-capture-v3/brush-band-001/restorations.avi`: 1,032 frames / 34.4 seconds, ten ordinary three-second horizontal passes across the fox’s face. It is a sample of work, not a full restoration.

## What “maximum hose” means

The production hose profile has five states indexed 0–4. Index 4 is the maximum authored spout: wet radius 0.46, maximum passive spread radius 1.20, tip radius 0.145, impact radius 0.33 and passive multiplier 3.0. The paid upgrade UI calls this **Water hose · Lv 5**, with **4/4 upgrades**.

The actual maximum paid power across all four stores is 9.261 (2.1 × 2.1²). The isolated filming ledger owns Store 4’s maximum hose and squeegee upgrades; production progression carries their power back to Store 2. Both tools therefore use their actual highest purchasable power. The hose profile and both wet powers are recorded in the event log and checked in `capture_audit.json`.

Store 2 is the existing water-only production recipe: hose → extract. The ad’s dry brush footage comes from a separate Store 1 dry job. These are distinct genuine jobs, not a claim that the shown pieces are one uninterrupted three-tool tutorial.

## Explicit setup fixture and save isolation

`tools/capture_ad_wet_tools.gd` requires `-- --shop-test --audition-audio`, writes only beneath `build/ad-capture-v3/`, and refuses a session with existing evidence. The process APPDATA/LOCALAPPDATA directories are isolated beneath the capture session. The actual player save is never opened or altered.

Before the wet scene loads, the harness initializes unlocked branches and filming money in this isolated ledger. It buys the authored hose and squeegee upgrades using production purchase methods. Two past jobs are seeded solely to select Fox’s Den from the normal rug catalog. The brush take uses the same catalog choice with an unchanged starter brush. These prepared progression states are not presented as earned during the take.

**No dirt, water or extraction mask is seeded or painted by the harness.** No direct stroke-controller calls, manual physics advancement, altered tool power, skipped gate or forced completion are used. Water arrives from the production ballistic hose and passive soak signals; extraction comes from the ordinary squeegee input path. A normal 99% overall threshold triggers the full reveal.

The isolated project snapshot copies the current game’s assets, resources, scenes and scripts. All 228 files matched the current source byte for byte (`build/ad-capture-v3/source_manifest.json`). Only the copied project’s recording resolution and movie settings differ. The pinned Godot 4.7.2 stable Mono wrapper was used.

## Normal speed and input

One ordinary screen drag is sent per rendered frame, along projected rug-local coordinates. The full first hose and squeegee strokes in take 002 each last six seconds; subsequent covering strokes last three. Both are ordinary user movement speeds, with no speed change in the source video. The starter brush performs three-second strokes with genuine lifts between passes.

As in the previous capture driver, only the preceding input timestamp is aligned to the 30 fps movie timestep (33/34 milliseconds). The production input callback otherwise uses wall-clock time, which differs during offline export. All scene time, water simulation, rendering, tool strength, masks and payout behavior run unchanged. Focus loss aborts the take. All completed sources passed without focus loss.

## Editorial candidates

Encoded video frame indices below are the logged engine-frame index. Driver frames are one higher. Use the actual frame/30 values for edit in-points, rather than the rounded driver `seconds` value.

| Take | Action | Source frames | Source seconds | Suggested crop |
| --- | --- | --- | --- | --- |
| wet-tools-002 | Central maximum hose sweep | 68–248 | 2.266667–8.266667 | Detail: x64, y700, w952, h450; full hose needs y475–1175 |
| wet-tools-002 | Central squeegee sweep | 617–797 | 20.566667–26.566667 | x64, y730, w952, h450 |
| brush-band-001 | Starter brush pass 8 | 747–837 | 24.9–27.9 | x64, y700, w952, h450 |
| brush-band-001 | Starter brush pass 9 | 844–934 | 28.133333–31.133333 | x64, y700, w952, h450 |
| brush-band-001 | Starter brush pass 10 | 941–1031 | 31.366667–34.366667 | x64, y700, w952, h450 |

The central wet shots move fully across the rug. Trimming about 0.7 seconds from each end emphasizes the on-rug contact and avoids the off-rug approach. Keeping wider source context in the hose’s dedicated hero shot makes its long body recognizable; the narrow stacked strip can emphasize the nozzle, stream and wet area.

Take 001 is the shorter alternative: hose central sweep 2.266667–5.266667; squeegee central sweep 17.566667–20.566667. It completes in 43.766667 seconds. The smoke take is diagnostic only and uses Mint Meadow.

Native stills are stored under each take’s `stills/` directory. In take 002, `hose_center_frame.png` and `squeegee_center_frame.png` are exact middle-frame exports. The source AVI is MJPEG, full range, tagged bt470bg (BT.601 family) plus stereo PCM 48 kHz; decode that matrix/range before compositing and convert RGB explicitly to BT.709 limited range for the final MP4. Do not merely retag source YUV as BT.709.

Game music was disabled and effects enabled for capture. The current game provides brush and completion audio; do not assume these wet tools already have a complete bespoke water sound bed. Keep any editorial music or added sound design identified separately from recorded gameplay audio.

## Validation

`build/ad-capture-v3/capture_audit.json` contains probes, SHA-256 hashes, actual tool settings, normal-input stroke starts and checks for every source. All checks pass. The preferred wet take reached 99.0011299% overall clearance through production input and earned the production full reward of 320 coins. All recording processes have exited.

Preferred wet source SHA-256: `8383640a0e876aa284bdc92a8f17ff51dd77970648d48a97168f567df95526c5`.

Brush source SHA-256: `2fd2495e4084cc1345e0102ed69d9eb44408da3a43266d4c0c6bd6bd8de083d0`.

### Preferred wet take phase boundaries

- ARRIVING: source frame 0, 0.000000 seconds.
- GROWING: source frame 30, 1.000000 seconds.
- TOOL_ENTERING: source frame 42, 1.400000 seconds.
- CLEANING: source frame 50, 1.666667 seconds.
- VACUUMING: source frame 1342, 44.733333 seconds.
- REVEAL: source frame 1396, 46.533333 seconds.
- DEPARTING: source frame 1468, 48.933333 seconds.


## Revised panel takes: visible tools at the first frame

For the final split composition, use **wet-tools-003** and **brush-band-002**. A narrower real gesture (rug-local x −0.65 to +0.65) keeps the tool head inside the landscape crop immediately. The prior full-width sources remain available for hero shots, edge runoff and the natural completed reveal.

In wet-tools-003, only the first central hose and squeegee gestures use these compact bounds; each lasts 6.5 seconds. All other hose covering gestures are unchanged. The production hose genuinely reaches the normal 99% gate before the squeegee becomes available. This take stops after its central squeegee sample; it does **not** claim a completed job or manually force a reveal. Use wet-tools-002 for the full-restoration payoff.

- **Hose panel:** source frames 68–263, 2.266667–8.766667 seconds. Suggested six-second clip: **2.566667–8.566667**.
- **Squeegee panel:** source frames 632–827, 21.066667–27.566667 seconds. Suggested six-second clip: **21.366667–27.366667**.
- **Brush panel:** all ten ordinary three-second starter passes now use x±0.65. Pass 9 starts at 28.133333 and pass 10 starts at 31.366667. Suggested six-second clip: **28.2–34.2**.

Wet003 is 828 frames / 27.6 seconds; brush002 is 1,032 frames / 34.4 seconds. All panel-take audit checks pass. The new option is `--ad-panel-sweep=1`; wet003 additionally uses `--ad-center-seconds=6.5`. The normal film-speed/timestamp policy and isolated-save protection are unchanged.

wet-tools-003 SHA-256: `d30aa3eaf31e2bdee6cc4b56b3f79cd8ad22c00019c75511587377624b00c7e0`.

brush-band-002 SHA-256: `bfe2fb8a72236d13557cc7346857ee26340802ffc262f1850aebf9f189de45cd`.
