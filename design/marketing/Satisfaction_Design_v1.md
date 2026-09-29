# Carpet Cleaner — designing the feeling

28 September 2026 · Research, current-game audit, and proposed next slice

## The promise

**I can turn a grubby rug into something beautiful, with my own hands, at my own pace—and enjoy seeing what I restored.**

This is the proposed player promise. The trailer should let someone anticipate that experience. Coins, tools and shops give the activity continuity; their value depends on what they let the player feel and do next.

The historical design already contains this direction. [Metagame v0.2](../Metagame_v0_2.md) says the brush should remain enjoyable after automation, suggests before/after restoration records, and asks whether players voluntarily keep cleaning after Bonzi arrives. Those are useful intent signals. Its older prices, thresholds and gates are superseded and are not being reinstated here.

We have not researched Carpet Cleaner's own audience yet. The claims below distinguish external findings, current implementation facts, and design hypotheses to test.

## Why someone might choose this game

| Desired experience | What Carpet Cleaner can make distinctive | What must happen in play |
| --- | --- | --- |
| **A small, manageable restoration** | One bounded rug can become a complete, beautiful object. | The task is readable; useful strokes visibly improve it; remaining work is findable. |
| **Pleasant control and rhythm** | Broad brushing, wetting and pushing a water ridge feel different under one finger. | The tool follows the hand reliably; material response and sound follow actual contact. |
| **Discovery** | A flower, geometric motif or unusual weave emerges as the player works. | The clean result is worth seeing, and consecutive jobs offer meaningful differences. |
| **Pride in something finished** | “I brought that rug back.” | The game lets the player appreciate and optionally revisit their own before/after result. |
| **A gentle sense of growth** | A little restoration shop gains capabilities and a recognizable identity. | Progression introduces enjoyable possibilities without making the starter experience deliberately unpleasant. |

These are proposed motivations, not five proven audience segments. A player may value only one or two. Our strongest distinguishing opportunity is the combination of **textile response, attractive pattern reveals, and compact complete restorations**. We have not established competitive uniqueness or market demand for that combination.

## What the research supports

| Evidence | Finding relevant to this decision | What it does not establish |
| --- | --- | --- |
| [Vuorre et al., 2024, PowerWash Simulator](https://ora.ox.ac.uk/objects/uuid%3A399a3c8f-711f-4168-9008-5d762d8a4570), [Oxford account](https://www.oii.ox.ac.uk/new-study-reveals-positive-mood-changes-during-video-game-play-finds-oxford-team/) | Naturalistic analysis of 8,695 players and 67,328 sessions found a small average increase in self-reported mood during play. This is unusually relevant genre evidence. | Observational, self-selected adult PC players, one game, no comparison activity. It cannot identify which cleaning mechanic caused the change, establish a health benefit, or predict our mobile audience. |
| [Kao et al., CHI 2024](https://people.csail.mit.edu/dkao/pdf/3613904.3642656.pdf) | In a preregistered action-RPG experiment with 1,699 participants, feedback tied to successful actions benefited motivational experience. Amplifying effects was not reliably beneficial and could harm it. Curiosity was associated with enjoyment and voluntary play. | Hidden rug patterns, louder swishes and additional particles were not tested. Random feedback variation did not simply create curiosity. Our takeaway is to make action and result legible, then test meaningful discoveries. |
| [Ryan, Rigby & Przybylski, 2006](https://selfdeterminationtheory.org/SDT/documents/2006_RyanRigbyPrzybylski_MandE.pdf) | Four studies link perceived competence and autonomy with enjoyment and preferences; intuitive controls relate to these experiences. | It does not follow that any extra choice, faster tool or upgrade tree will improve retention. Choices must let the player do something they value. |
| [Klimmt, Hartmann & Frey, 2007](https://pubmed.ncbi.nlm.nih.gov/18085976/) | An online experiment with 500 participants supports the importance of perceiving one's effects on the game world; control has a more complex relationship with enjoyment. | It does not support removing every challenge or making all jobs complete instantly. A worthwhile action and a reliable response can coexist with gentle mastery. |
| [Ballou & Deterding, CHI PLAY 2023](https://selfdeterminationtheory.org/wp-content/uploads/2024/01/2023_BallouDeterding_IJustWanted.pdf) | Interviews with 12 players describe how unexpected need frustration changes expectations and engagement. | Small qualitative study, not a prevalence estimate. It is a reason to investigate frustration, and to avoid treating persistence or completion alone as evidence of enjoyment. |
| [Singhal & Schneider, CHI 2021](https://uwaterloo.ca/haptic-experience-lab/projects/juicy-haptic-design-vibrotactile-embellishments-can-improve) | A within-participant study with 38 people found benefits on several experience ratings from haptic feedback in Breakout variants; stronger embellishment was not uniformly better. | Dedicated setup and another genre. Optional phone haptics need device testing; this is not evidence for vibrating continuously during every stroke. |
| [Daneels & Maes, 2025](https://eludamos.org/index.php/eludamos/article/view/7938) | Survey of 277 cozy-game players identifies motives including agency, escapism, meaningful emotions and narrative interest. | Self-report across cozy games. A customer thank-you, album or caring story is a plausible direction, not a proven cause of attachment in Carpet Cleaner. |

FuturLab also explicitly describes its own design approach as protecting satisfaction and reducing friction throughout the experience. That is useful [primary developer practice](https://www.futurlab.co.uk/), not independent evidence that copying a particular feature will work here.

There is no basis here for a universal “dopamine loop” explanation. A more useful design account is: **my action causes a pleasant change; the change has a recognizable purpose; I can appreciate the result; another appealing possibility follows.**

## Where the current game weakens that promise

### 1. Cleaning can seem to create more mess

**Current fact:** around 560 clumps are tracked, but only 25 are initially visible at partial size. Others become visible and grow when brushed. Starter dust clears over two core passes, and its pale overlay already exposes much of the pattern. A cleaned stripe can therefore coexist with newly apparent debris.

**Likely experience to test:** the player sees effort reveal more obligations instead of clearly reducing disorder. This could also read as pleasing dirt being lifted; we should compare footage and play rather than assume every growing clump is bad.

**Proposed change:** make all counted dirt perceptually explainable before contact. Try recognizable fine grit that gathers into small visible piles ahead of the brush, with a clean track behind it. Shorten or remove the delayed enlargement that looks like new dirt appearing. Prototype this with the existing pooled visual system, not a physical fluid or particle rewrite.

Preserve two passes only if they look like distinct positive changes: first loosens/lifts visible dust, second exposes a cleaner and more vivid surface. An ordinary rug may instead work best in one pass. Compare feel before selecting the tuning.

**Pass condition:** someone viewing the opening muted at phone size can point to what improved and where the dirt went. No unexplained new clumps appear inside an otherwise finished track.

### 2. Visible effort and the progress number can disagree

**Current fact:** dry completion uses the lower of surface clearance and credited debris clearance. A substantial stripe can be clean while the number barely moves because debris remains on the rug. The initial instruction function does nothing. Debris can physically re-enter after it has already earned permanent clearance credit.

**Proposed change:** first improve the material behavior and the legibility of remaining work. A brief contextual cue can distinguish lifting dust from sweeping loosened debris over an edge. A restrained, optional residue highlight can help with the last patch. Keep loose dirt moving out of the area the player has visibly finished.

Do not inflate the displayed percentage independently of the real completion/reward rules. If the combined measure remains confusing, test a different presentation and revise gameplay and ledger semantics together. Adding two permanent competing meters is not the default solution.

**Pass condition:** when progress stalls, a new player can show what remains to do. Completion does not require repeated guesses on an apparently clean rug.

**A further prototype worth testing:** give a rug two or three natural local accomplishments, such as its border, central flower and fringe. When a genuinely restored region is complete, a brief material settle or restrained sound can acknowledge it. The player still chooses the order; no new score, compulsory path or money per particle is needed. This may make progress meaningful before the entire rug is finished. Region definitions must follow actual cleaning state, survive save/resume, and avoid announcing a finished area while visible counted debris remains there. This is a new feature hypothesis; success-dependent feedback research does not specifically prove that regional cues will improve this game.

### 3. The rug needs to respond like a textile

**Current fact:** the rug has a woven appearance, dirt/wetness shading and rolling geometry. There is no stroke-direction fiber grooming in its current shader. Cleaning audio and haptic implementation were not found. The water/extraction visuals already provide a useful material-response foundation.

**Proposed addition:** prototype a subtle brushed-nap response: fibers appear compressed beneath the tool and settle into a directional light/dark sweep behind it. Keep this subtle, clearly distinct from dirt, and independent of reward progress. It must not become an extra mandatory finishing chore or simulate lag in the controls.

Pair the material response with contact-driven sound: dry bristles and little grit ticks; a sustained wet flow; a fuller extraction swish as real water leaves; a soft endpoint when the ridge clears the edge. Feedback should vary with the material actually affected, not merely finger speed. Optional haptics come after the visual/audio version works.

**Why this belongs specifically to Carpet Cleaner:** a groomed fiber direction is a textile pleasure, while extraction turns a waterlogged rug into a dry, vivid surface. These are stronger identity cues than generic sparkle effects.

**Pass condition:** players can distinguish brushing from wet extraction through sound and material response. Clean/dry passes do not produce dirt-removal/water-removal effects. Groomed shading is never mistaken for a dirty patch. Phone performance remains acceptable on measured target devices.

### 4. Completion currently leads quickly into the next obligation

**Current fact:** full cleaning automatically completes at 99%. The game commits the reward and starts vacuuming, then rolls the rug away. Coins are shown as the next rug begins. There is no dedicated finished-rug phase. Authored vacuum, departure and arrival durations already total approximately 4.4 seconds between control spans; that is a code timing estimate, not a device measurement.

**Proposed addition:** use part of that existing transition time to present the restored rug. Let the tool leave the composition, make the final cleaning sound resolve, show the intact pattern, and associate its payout with it. Test roughly 0.6–1.0 seconds as a first tuning range, with smooth continuation; do not simply tack an unskippable cinematic onto every job.

An optional before/after view can revisit the actual starting state and result. An inexpensive prototype can store the rug identity and starting dirt parameters and render a comparison on demand. A persistent album should come after players demonstrate that they value revisiting results; account for storage, save format and mobile memory before saving images per job.

Implementation detail that matters to this promise: the existing vacuum already fades surface dust and removes visible clumps even after a 75% early finish (`dirt_controller.gd:204`, `:333`). A new before/after result should use the actual **pre-vacuum completion snapshot**, or reserve the perfect-restoration presentation for 99% completion. Inserting the same hero reveal after every vacuum would make early and full restorations look identical. Keep their presentation and existing payouts distinct.

**Pass condition:** players notice their finished work, and the result feels connected to the last gesture and payment. Existing atomic rewards and safe Back navigation remain correct. Early 75% completion must not show a fabricated perfect-clean result or silently grant the full-clean payout.

### 5. Another rug currently offers little new discovery

**Current fact:** paid play repeats Mint Meadow. There are other resources, but these currently change tint and cleaning parameters on shared art/geometry; switching the resource alone does not create three wholly different patterns.

**Proposed addition:** author a small set of genuinely different motifs. Give each a composition that rewards partial discovery and looks good when fully restored. Vary the interesting work: a broad dusty region, a visible concentrated patch, or an edge that produces a satisfying extraction finish. Variation should change what the player enjoys, not just increase the required number of passes.

Later, let the player pick between two jobs for an appealing motif or cleaning action. Keep that selection occasional and quick. A remembered restoration, a short customer acknowledgment or the earlier album idea can supply meaning if players want it; a full character/story system is unnecessary for the first test.

**Pass condition:** after a few completed rugs, players can name something they look forward to revealing or doing on the next one. Saved job identity and progress survive leaving and resuming.

### 6. Progression needs to expand the pleasure

**Current fact:** the first brush upgrade is genuinely 1.44× wider, with unchanged cleaning strength. Wet tools already introduce a different action, but arrive in Store 2 behind four brush upgrades, three max-tool jobs, Bonzi earnings and an opening cost. Time to reach them is unmeasured.

**Keep the wider brush when:** a broad, clean lane feels more deliberate and satisfying; it reduces repetitive coverage that players dislike; its appearance and response communicate growing capability.

**Reconsider it when:** the only noticeable benefit is that the enjoyable part ends sooner, or the player wants it mainly to escape unpleasant starter cleaning. A faster completion time by itself cannot distinguish these cases.

Pair a tool with work that makes its quality meaningful. A wider brush belongs on a broad area where one continuous lane feels good. A hose/squeegee pairing offers wetting, gathering and release. A possible later detail tool could groom fringe or handle narrow motifs, but should be tested as an optional enjoyable action rather than a gate every job must contain.

The lowest-cost way to explore wet interest is a guided use of the existing practice content after a first successful restoration. If that improves the opening, design a real introductory wet job before using wet cleaning as the acquisition promise. Changing free stage order would require coordinated gameplay and ledger work: the current paid recipe intentionally rejects out-of-order extraction.

**Pass condition:** after trying both versions on comparable rugs, the player can describe an experiential difference and chooses which they enjoy. Measure “felt good,” “felt easy,” and “wanted it over” separately.

## The first build slice

Build a **single restoration that is enjoyable with the money display temporarily hidden in a test session**. This is a diagnostic condition, not a proposed removal of the economy from production.

1. **Make the stroke trustworthy:** improve dust contrast, clarify gathered dirt, reduce confusing clump emergence, make the remaining task readable.
2. **Make contact feel physical:** add success-linked brush audio; compare a restrained nap/grooming prototype against plain surface cleaning. Keep the version that helps.
3. **Make finishing valuable:** replace part of handling time with the clean reveal; connect the payout to this result; prototype an optional real before/after comparison.
4. **Give continuation a reason:** add a second distinct authored motif, then compare wanting another rug with the current repeated design. Add an album only if people value preserving the result.
5. **Test progression in that context:** compare the real wider brush and the existing wet tools. Promote the improvement that expands enjoyment; do not use tool purchases to compensate for an unsatisfying base interaction.

Scope for this slice is one excellent interaction and a second appealing restoration. New locations, extra currencies, full customer stories, a large tool catalog, physical fluid simulation and persistent screenshot collections are not prerequisites.

## How the trailer changes

Keep the successful storyboard's visual structure, but strengthen the emotional purpose of its middle. The leading creative hypothesis becomes:

**Mess → a stroke I want to make → a pattern worth revealing → a finished result I am proud of → another restoration I want to try.**

| Time | Satisfaction-led candidate | What it promises |
| --- | --- | --- |
| **0–2 s** | A continuous, honest stroke exposes vivid pattern while grit gathers ahead. Keep the original clean-stripe hook. | “I want to do that.” |
| **2–5 s** | A second deliberate pass reveals the flower/motif. Let real bristle/texture feedback carry the scene. | “My action changes this object.” |
| **5–8 s** | Clear the final patch, let the whole restored rug sit, then briefly show its actual before/after. Small real payout, secondary to the result. | “Look what I brought back.” |
| **8–12 s** | A different real rug rolls in and a pass begins to reveal its design. Alternatively test the original wider-brush proof here with the rest held stable. | Discovery version: “What will the next one become?” Upgrade version: “A better-feeling way to restore it.” |
| **12–15 s** | Title and release-appropriate CTA over continuing gameplay. Possible copy: **“Bring it back to beautiful.”** | A clear restoration promise. |

This is a proposed variant, not a declaration that it will outperform the upgrade ad. It requires actual paid pattern variety, finish presentation and before/after support before filming those promises. Preserve the v1 illustrated board; test this revised middle against it. Use the longer cut to show earned equipment and later wet tools with truthful unlock context.

The behavioral message should be visible without the words “satisfying” or “relaxing.” The first stroke, dirt movement, material change and finished reveal must demonstrate it.

## Playtesting the feeling

Start with a small formative group, such as 6–8 people unfamiliar with the project, including both existing cleaning-game players and interested newcomers. This is for finding problems and language, not estimating market demand or statistical retention lift.

- Compare baseline and revised versions on comparable short rugs; alternate their order across participants. Keep rewards and unrelated content consistent. If testing a complete revised slice, treat it as a package; later isolate components to understand which caused an improvement.
- Observe without explaining the desired feeling. Ask “What changed when you brushed there?”, “What do you think remains?”, and afterward “Which moment did you most want to repeat?” Avoid telling them the feature is supposed to be satisfying.
- Separately ask for ease of control, sensory pleasantness, satisfaction with the finished object and desire to try another job. Simple 1–7 ratings can aid discussion; these are local prototype measures, not a validated clinical or motivation instrument.
- Offer another rug or the option to stop without an additional test reward. Ask why they chose it. Watch for curiosity about the pattern, enjoying the tool, wanting a payout, or merely wanting to finish an irritating task.
- Note clean-area brushing and pauses at the result, then ask why: these could indicate enjoying the material, inspecting their work, or being confused. Behavior alone is ambiguous.
- Inspect the last section of a job: repeated ineffective strokes, invisible residue, unclear stage changes, and whether the auto-transition interrupts appreciation.
- Reject additions that increase session length but worsen frustration. Keep material details only if they add something people can perceive on the target phone without disrupting control or frame pacing.

No research above provides an ideal rug duration, reveal duration, upgrade multiplier or haptic strength. Those must be selected through our own tests.

## Implementation evidence and review status

Current source was reviewed; production gameplay has not been modified by this research pass. The existing eight staged engine captures in [references](references/capture_manifest.json) support the visual audit, but are not user studies or a phone-performance test.

| Finding | Current source |
| --- | --- |
| Original enjoyable-brush intent, album idea | `design/Metagame_v0_2.md:12`, `:149`, `:163` |
| Initial visible/latent debris, growth and direction | `CarpetToy/scripts/dirt_controller.gd:140–153`, `:382–428`, `:505–509` |
| First-pass amount and grain rules | `CarpetToy/scripts/rug_definition.gd:6–16`; three files under `CarpetToy/resources/rugs/` |
| Pale dust and wet shading, no stroke-grooming field | `CarpetToy/scripts/soil_surface.gdshader:11–13`, `:45–55` |
| Combined progress and physical re-entry | `CarpetToy/scripts/dirt_controller.gd:646–654`, `:513–515` |
| No opening instruction | `CarpetToy/scripts/workshop.gd:646–648` |
| Completion, payout presentation and handling phases | `CarpetToy/scripts/workshop.gd:713–744`, `:794–804`, `:820–866`, `:892–947`; `dirt_controller.gd:8` |
| Paid rug restriction and practice-only cycling | `CarpetToy/scripts/workshop.gd:164`, `:674–675`, `:927–938` |
| Upgrade widths and wet entry gates | `CarpetToy/scripts/progression.gd:8–16`; `shop_state.gd:695–709` |
| No audio/haptic implementation found | Search of active scripts/scenes/resources for audio players/server and handheld vibration; no matching implementation. |

Related: [original storyboard and capture plan](Trailer_Storyboard_v1.md). This brief refines its motivation and prioritization; it does not invalidate the useful coin/upgrade sequence or quietly change the game's economy.
