# Completion payoff — updated 9 October 2026

The fiber experiment has been removed. Music and the smoother brush audio remain. This pass gives the player a moment to appreciate the rug they actually restored.

## Experience

The existing loose-dirt suction finishes first, then the tools and cleaning HUD give way to a clear view of the unrolled rug. The only completion UI is a small blue **Compare** button near the bottom, centered in portrait and at the lower right in landscape. Landscape shows the complete room at the cleaning carpet's scale in the full-height area beside the button; portrait retains its gentle reveal push. Both layouts leave safe spacing around the action.

- **Full restoration:** the existing 99% completion threshold leads to a 2.4-second clear reveal and a restrained 0.84-second completion sound. Its reward is already committed; the result advances automatically after the pause.
- **Early finish:** the existing 75% eligibility remains, followed by a 1.1-second automatic pause without the full-restoration sound. Residual surface dirt remains visible.
- **Compare:** holding the button shows the rug's recorded starting appearance, pauses the automatic hold, and restores the actual result on release. Touch cancellation, a second finger, keyboard release, rotation and focus loss restore the result too. After release there is at least 0.9 seconds to appreciate it again.
- **Back:** retains its existing return-to-shop behavior. The committed reward and reserved next job are preserved.

This gives the work a visible answer: the same carpet, restored through the player's actions. The ending can be captured directly for a trailer. Early finishing remains valid without being presented as full restoration.

## Truthful comparison and completion

Completion records the recipe-aware clearance before vacuum, and the HUD preserves that earned result. At the user's subsequent request, accepted full restorations (99%+) now fade residual dry soil strength to zero during suction, so the reveal has no tiny leftover dirt patches. Early finishes preserve their dirt strength and residual surface dirt. Masks, saved progress, wetness, payout thresholds and economy remain unchanged; the final polish is a presentation allowance at the existing full-restoration tolerance.

`rug_comparison.gd` records the actual coverage/wetness images, dirt strength and rendered dirt-scatter buffer when the rug becomes ready. Hold-to-compare swaps texture bindings, the existing MultiMesh's rendered buffer and the captured material dirt strengths. Release restores the polished result, or the residual dirt of an early finish. It never restores gameplay snapshots or changes dirt arrays, saved progress, tool usage, rewards or the next job. Camera and rug lighting remain the same for both views. A resumed rug's recording begins on re-entry and therefore represents the start of that visit.

The comparison reuses two fixed 256 × 416 L8 textures across rugs (208 KiB raw GPU texture data together) and bounded before/after buffers for the existing 560-instance dirt pool. It needs no screenshot readback, additional 3D viewport, continuous recording, fiber map or new particle system. Resource allocation/upload happens on arrival; holding Compare introduces no per-frame copying. These architectural bounds are not a phone performance measurement.

The current earnings flow pays up to half of the full quote as removed dirt fades away or extracted runoff retires. Full restoration at 99% pays the other half plus any unpaid cleaning share, then reserves the next job before suction starts. A 40-coin carpet therefore earns up to 20 during cleaning and totals 40 at full restoration. Early Finish at 75% settles the unpaid remainder of the cleaning half, totaling 20. Its button always reads **Finish**, without a price.

The video button between Shop and Finish offers 2× for the current carpet. A verified reward doubles both early and full totals and tops up cleaning money already paid. The doubled Per carpet quote remains visible during suction; the next carpet starts without the boost. No provider is configured in this build, so the button is visibly locked. Pending verification pauses cleaning, purchases and wallet presentation until the provider responds.

Each wallet payment counts up over 0.24 seconds with a restrained 6% pulse. The final payment animates while the cleaning HUD remains visible during suction. Focus loss pauses the dirt simulation, vacuum and wallet presentation together. The reveal is cosmetic and never calls the completion transaction. Failed saves leave the current rug playable and do not enter the reveal. Existing `animate_rug_changes=false` test/instant-presentation behavior still bypasses the hold.

## Audio

`restoration_complete.wav` is original offline synthesis: a short, soft harmonic resolution, mono 44.1 kHz PCM16, no borrowed recordings. It has smooth endpoints and zero clipped samples. One additional reusable non-looping voice plays it only for the full-restoration reveal. The home preference is now labeled **Sound**, covering brush effects and completion. Muting, backgrounding or leaving the audio context stops the cue; focus return does not replay it. The current system has four fixed voices.

Signal and lifecycle checks establish correct playback behavior, not subjective listening quality. Phone speaker balance and actual audio latency still need device listening.

## Verification

Earlier implementation verification included 64 reveal checks, 71 audio checks, 30 transition checks, 64 coin-reward checks and 31 wet-cleaning checks, all with zero failures. The contract and brush-feel suites also reported zero failures. The current build identity is recorded in `build/android-build-info.txt`; that file determines the delivered APK version. No physical phone was connected for these desktop checks.

All gameplay checks use Godot **4.7.2 stable Mono/.NET**, GL Compatibility and `-- --shop-test`; test APPDATA/LOCALAPPDATA are isolated under `build/completion-profile`.

`tools/validate_completion_reveal.gd` now checks actual 99% and 75% coverage masks, full-only residual-soil fade, original dirt scatter and strength, comparison restoration, input cancellation, Enter-to-compare, notch-safe portrait/landscape layouts, large rewards, repeated internal continuation, save failure/retry, automatic advance, Back and re-entry. It also checks complete landscape room framing and carpet scale, including 591×1280, 390×844 and 844×390 physical windows on the production 720×1000 reference canvas. It writes real renderer captures to `art/renders/completion_*.png`.

The simplified Compare pass completed 289 reveal checks, 274 rendered camera-continuity checks, 77 large-money checks and 60 late-game UI checks with zero failures.

The original split-earnings pass added 52 real-renderer integration checks and 2,046 rendered wallet checks, all with zero failures. That historical pass used proportional early settlement. The current fixed-half early Finish passed 53 incremental renderer checks, 244 split-payment ledger checks and 289 reveal checks with zero failures. The current-carpet video ledger passed 203 checks, its responsive HUD passed 643 renderer checks, and the real button/pause/payment flow passed 32 renderer checks, all with zero failures. Coverage includes verified 40/80 boosted totals, previously earned top-ups, skipped videos, replay protection, save failures, 400AF-scale rewards, focus changes and replacement-carpet reset.

The updated audio validator checks the fourth voice, non-looping cue, natural ending, independent mute settings, focus/pause behavior and fixed voice reuse. Contract, coin-reward, rug-transition, brushing and wet-mask regressions cover the shared flow. Desktop runs emit the existing certificate-store diagnostic; no game-script or shader errors are acceptable.

Run graphics checks sequentially through `tools/run_godot.ps1`. Use **Build APK.cmd** for a matching Android build. Physical Android playback, sustained frame time and thermal behavior remain unmeasured without a connected device.
