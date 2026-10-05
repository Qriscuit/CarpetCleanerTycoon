# First session: earn a change you can feel

Status: design proposal, grounded in the current game. This pass implements only the requested full-restoration dirt cleanup; it does not silently change introductory jobs, progression prices or wet-tool unlocks.

The intended experience is: make a visible change with one gesture, finish something recognisable, earn a wider brush, then feel its broader cleaning lane. Whether that produces satisfaction has to be observed in play.

## What the current game actually does

Fresh players arrive at Home and tap the shop to begin Mint Meadow. There is no first-job recipe or displayed gesture hint. All three paid patterns use the same ten-pass soil recipe. The first wide brush costs 80 coins; full restoration pays 40, while an early finish at 75% pays 20. Two full restorations already fund it. The production purchase is not subject to the old eight-job blueprint gate.

The first width upgrade changes the cleaning lane from 0.61 to 0.8784 world units: a genuine 44% increase. Its cleaning strength stays at 1.0, so each spot still needs the same passes. Copy should promise wider strokes, not stronger cleaning or a guaranteed 44% reduction in completion time.

The prominent cleaning-screen offer is currently the 25-coin earnings upgrade. The brush benefit is behind an icon drawer and expressed with multiplier symbols. If the player spends their first 40 on earnings, they retain 15; the next full rug pays 44, leaving 59. That pushes the first width upgrade to the third full rug. The first-session presentation should make the brush goal clear while keeping other purchases available.

## Recommended opening

| Moment | Player experience | Proposed change |
| --- | --- | --- |
| Enter | I know what to do first. | A clear “Clean your first rug” action on fresh Home, with one tap into Mint. Resume existing jobs normally. |
| Learn | My first movement makes a visible difference. | One short back-and-forth gesture on the rug, labelled “Sweep back and forth.” Dismiss on the first effective stroke; do not block input. |
| Complete | I uncovered a recognisable design. | A bounded introductory dirty area over Mint's motif, with generous lanes and no tiny isolated edge targets. Keep the rich dark starting soil and current completion reveal. |
| See the goal | Another restoration gets me a useful brush. | Show “Wide brush · 40 / 80” after a first full finish, updated from the actual wallet. Give this goal the prominent slot during the introduction; earnings upgrades remain accessible. |
| Earn it | I understand what I am buying. | After a second full finish, offer “Wide brush · 44% wider strokes · 80.” No forced purchase or required ad. |
| Feel it | The next stroke clears a visibly wider lane. | Apply the existing real width and visual-size upgrade, return to the rug, and use a broad intact lane. Hold dirt depth and job work area steady across the purchase. |
| Explore | There is another satisfying action to try. | After using the wider brush, offer an optional “Try washing” route to the existing free hose/squeegee exercise. Preserve the paid rug and return to it afterwards. |

Use the next patterns to reward curiosity: Mint, then Sunburst, then Fox. The second and third jobs should have comparable work area and soil recipe so the new brush's benefit is not hidden by a simultaneous difficulty increase. Early finish remains legitimate: its lower reward makes the goal take longer, without a failure message or mandatory full-clean tutorial gate.

## Introductory effort: the part to test

My first prototype would shorten the opening through a smaller dirty work area while preserving repeated brushing. It retains the tactile act the player came for and reduces how long the first commitment lasts. The existing rug geometry can stay; a central soil band can reveal the flower as it clears.

This needs a real job work region, not just clearing half the mask on arrival. Progress must start at 0% of the assigned work and reach 100% when that work is cleaned. Dirt sources must be inside that region, otherwise invisible or distant clumps can block completion. Job identity, starting region and recipe must survive save/re-entry. Existing unfinished jobs should not be converted into introductory jobs.

Separately compare four versus ten passes on the same introductory work area. Keep art, rewards, sound, starting darkness and brush size equal. This is a tuning experiment, not evidence that either count is already correct. If ten passes produces repetition without additional enjoyment, lower introductory depth and reserve heavier soil for later jobs. Do not make an easier introductory recipe abruptly become harder immediately after the wider-brush purchase.

A literal smaller rug would require adjusting geometry, bounds, camera, tool contact and mask calculations; the current cleaner assumes fixed extents. It is a larger change than it first appears.

## Wet-tool taste

Wet tools are currently freely available through Home → Settings → Gym → rug 2. The mechanics exist; the route is obscure. A later contextual invitation can open the appropriate practice exercise directly. Keep its full debug-like tier controls out of the introductory presentation, keep rewards and ownership unchanged, and provide an obvious return to the saved paid job. Test demand for washing before changing store unlock requirements.

## What would count as improvement

Start with observed playtests. Record whether players understand the first gesture unaided, recognise the emerging motif, find the finish understandable, locate and buy the brush, and notice its wider lane. Watch for repeated attempts to clean already-clean areas or lingering searches for tiny remaining dirt. Ask one neutral question after play: “How did the amount of brushing feel?” Follow up on their answer without suggesting that more effort ought to feel better.

For an eventual instrumented experiment, distinguish active brush-contact time from menu time, idle time and time spent admiring the reveal. Track voluntary continuation, early finishing, abandonment at each stage, purchase and actual use of the upgrade. Longer total play time by itself cannot distinguish enjoyment from friction. Test the introductory work area first, then pass count, then the wet invitation; avoid changing all three together and attributing the result to one of them.

## Build order

1. One gesture hint and a clearly labelled first brush goal, with saved dismissal and accurate wallet progress.
2. A persistent introductory job recipe/work region, followed by a comparable job on which to enjoy the upgrade.
3. Playtest pass depth and voluntary continuation; tune from those observations.
4. Optional direct wet-tool preview using the existing practice mechanics.

This follows the platform guidance to teach one action at a time through play and introduce complexity when relevant. Apple also recommends keeping onboarding optional and allowing self-directed play. These are design principles, not proof of a Carpet Cleaner retention result. [Apple: Onboarding for Games](https://developer.apple.com/app-store/onboarding-for-games/).

## Implemented now: full-restoration cleanup

At the existing 99% full-restoration threshold, successful completion fades all residual dry soil shading to zero during the 1.8-second suction. The reveal therefore has no leftover dry dirt specks on the pile, binding or fringe. An early finish retains its remaining dirt. Failed completion saves leave the visible dirt and playable job intact.

Before comparison restores the captured starting dirt strength and coverage; release restores the fully polished result. New rugs and practice resets restore their normal dirt strength. The finish tolerance is a presentation allowance: earned coverage, saved progress, completion percentage, payouts and wetness remain unchanged. No new shader pass, mesh or per-frame texture allocation is added.

Verification: 78 completion checks, 98 three-rug discovery checks, 64 coin-reward checks, 30 transition checks and 61 wet-store checks passed (331 total, zero failures), using pinned Godot 4.7.2 stable Mono and `-- --shop-test` with isolated profile `build/first-session-profile`. Real before, polished-after and early-finish captures were inspected. The editor import refreshed a stale UID cache warning before the final wet-store check; source resource IDs were already correct. The environment's existing certificate-store diagnostic remains.
