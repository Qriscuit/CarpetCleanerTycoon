# Completion payoff — 29 September 2026

The fiber experiment has been removed. Music and the smoother brush audio remain. This pass gives the player a moment to appreciate the rug they actually restored.

## Experience

The existing loose-dirt suction finishes first, then the tools and cleaning HUD give way to a clear view of the unrolled rug. Portrait framing brings the rug forward; landscape places the controls beside it so the rug can remain tall.

- **Full restoration:** the existing 99% completion threshold leads to a 2.4-second “Rug restored” reveal, the earned payout, and a restrained 0.84-second completion sound. The reveal does not claim an invented 100% result.
- **Early finish:** the existing 75% eligibility remains. “Job finished” shows the actual earned percentage and payout for 1.1 seconds, without the full-restoration sound. Residual surface dirt remains visible.
- **Next rug:** skips the hold and continues the existing roll/departure sequence. Repeated presses do not create another transition or payout.
- **Hold to compare:** shows the rug's recorded starting appearance while held, pauses the automatic hold, and restores the actual result on release. Touch cancellation, a second finger, keyboard release and focus loss restore the result too. After release there is at least 0.9 seconds to appreciate it again.
- **Back:** retains its existing return-to-shop behavior. The committed reward and reserved next job are preserved.

This gives the work a visible answer: the same carpet, restored through the player's actions. The ending can be captured directly for a trailer. Early finishing remains valid without being presented as full restoration.

## Truthful comparison and completion

Completion records the recipe-aware clearance before vacuum, and the HUD preserves that earned result. At the user's subsequent request, accepted full restorations (99%+) now fade residual dry soil strength to zero during suction, so the reveal has no tiny leftover dirt patches. Early finishes preserve their dirt strength and residual surface dirt. Masks, saved progress, wetness, payout thresholds and economy remain unchanged; the final polish is a presentation allowance at the existing full-restoration tolerance.

`rug_comparison.gd` records the actual coverage/wetness images, dirt strength and rendered dirt-scatter buffer when the rug becomes ready. Hold-to-compare swaps texture bindings, the existing MultiMesh's rendered buffer and the captured material dirt strengths. Release restores the polished After, or the residual dirt of an early finish. It never restores gameplay snapshots or changes dirt arrays, saved progress, tool usage, rewards or the next job. Camera and rug lighting remain the same for both views. A resumed rug is labeled **Before this session**, because its recording begins on re-entry rather than pretending to recover an earlier session's original appearance.

The comparison reuses two fixed 256 × 416 L8 textures across rugs (208 KiB raw GPU texture data together) and bounded before/after buffers for the existing 560-instance dirt pool. It needs no screenshot readback, additional 3D viewport, continuous recording, fiber map or new particle system. Resource allocation/upload happens on arrival; holding Compare introduces no per-frame copying. These architectural bounds are not a phone performance measurement.

Full completion already commits the reward and reserves the next job before suction starts. The reveal is cosmetic and never calls the completion transaction. Failed saves leave the current rug playable and do not enter the reveal. Existing `animate_rug_changes=false` test/instant-presentation behavior still bypasses the hold.

## Audio

`restoration_complete.wav` is original offline synthesis: a short, soft harmonic resolution, mono 44.1 kHz PCM16, no borrowed recordings. It has smooth endpoints and zero clipped samples. One additional reusable non-looping voice plays it only for the full-restoration reveal. The home preference is now labeled **Sound**, covering brush effects and completion. Muting, backgrounding or leaving the audio context stops the cue; focus return does not replay it. The current system has four fixed voices.

Signal and lifecycle checks establish correct playback behavior, not subjective listening quality. Phone speaker balance and actual audio latency still need device listening.

## Verification

Completed: 64 reveal checks, 71 audio checks, 30 transition checks, 64 coin-reward checks and 31 wet-cleaning checks, all with zero failures. The contract and brush-feel suites also reported zero failures. A fresh 38.5 MiB Android debug APK exported with matching Mono templates and passed independent signature verification; build identity is in `build/android-build-info.txt`. No physical phone was connected.

All gameplay checks use Godot **4.7.2 stable Mono/.NET**, GL Compatibility and `-- --shop-test`; test APPDATA/LOCALAPPDATA are isolated under `build/completion-profile`.

`tools/validate_completion_reveal.gd` now checks actual 99% and 75% coverage masks, full-only residual-soil fade, original dirt scatter and strength, comparison restoration, input cancellation, Enter-to-compare, notch-safe portrait/landscape layouts, large rewards, repeated finish/skip, save failure/retry, automatic advance, Back and re-entry. Its updated full-polish run passed 78 checks. It writes real renderer captures to `art/renders/completion_*.png`.

The updated audio validator checks the fourth voice, non-looping cue, natural ending, independent mute settings, focus/pause behavior and fixed voice reuse. Contract, coin-reward, rug-transition, brushing and wet-mask regressions cover the shared flow. Desktop runs emit the existing certificate-store diagnostic; no game-script or shader errors are acceptable.

Run graphics checks sequentially through `tools/run_godot.ps1`. Use **Build APK.cmd** for a matching Android build. Physical Android playback, sustained frame time and thermal behavior remain unmeasured without a connected device.
