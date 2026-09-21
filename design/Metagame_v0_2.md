# CARPET CLEANER TYCOON
## Game design document v0.2 — brush, buddy, growing chain
11 September 2026 • Working design and first balance pass • Android first

## 1. The game we are making
Start with a free little shop and a hand brush. Clean customer carpets, reveal their patterns, and earn enough cash to build Bonzi, a friendly cleaner bot. Bonzi takes over routine incoming orders while the player keeps doing satisfying personal jobs. Improve useful equipment, then open a more attractive shop with more valuable carpets. Earlier shops stay owned and keep earning. The player grows from doing everything by hand to owning a carpet-cleaning chain.

The founder’s current direction is brush-first, an early Bonzi purchase, and expansion into shops with different aesthetics and higher payouts. Keeping old shops earning is confirmed. The specific prices, rates, gates, parts rules and blueprint rules below are proposals to playtest. They are not measured player behavior.

This revision replaces the opening and economy proposals in v0.1. That document is retained as history. The active two-shop plan has no energy gate, gems, research-fragment meter, random chests or recurring rent. Those earlier ideas are deferred, not additional requirements hidden behind this economy. Cash is the only spendable resource in Shop 1. Machine Parts arrive in Shop 2 and only fund optional upgrades.

The main design promise: the brush remains enjoyable after automation. Bonzi adds reliable income and companionship; he does not erase the carpet under the player’s hand.

## 2. What exists today, and what comes next
The current Godot toy has a brush interaction, thrown dirt, a two-pass dust surface, a cleanliness meter, and selectable brush/squeegee/jet models. Only the brush currently performs cleaning. There is no implemented cash, contract queue, bot production, inventory, blueprint system, shop purchase or metagame save system.

The current check mark appears when 50% of the unique dirt clumps have been moved off the carpet. Surface dust is tracked independently. That is a feel-test rule, not yet a valid contract payout signal. Do not simply attach money to the current check mark.

The first economy contract uses one honest cleanliness number: the lower of unique clump clearance and surface-mask cleaning. At 85%, a small **Finish job** button appears; at 99%, the job finishes automatically. Completion clears small leftovers, awards the fixed reward once, takes the rug away, and immediately loads the next one. Never require hunting isolated pixels. Optional continued brushing before finishing gives no extra money. No countdown, destructive failure, score loss or reward for individual dirt particles.

The economy figures assume the first rug takes 50 seconds of hands-on cleaning plus 10 seconds of handling/reveal. That is an unmeasured target. If the toy actually takes two minutes, the workbook must use that measured duration; do not claim the five-minute Bonzi target still holds.

## 3. The first half-hour
| Beat | Trigger | What the player sees or gets |
| --- | --- | --- |
| Open the doors | First launch | Neighborhood Shop, hand brush, 0 cash. No purchase screen or debt. |
| First paid carpet | Finish one brush job | +20 cash, next carpet available. Show cash only now. |
| Meet Bonzi | Finish three Shop 1 jobs | Guaranteed Bonzi blueprint; a 100-cash build goal. No parts required. |
| Build the buddy | Have 100 cash; blueprint known | After five base jobs, spend 100. Bonzi starts a separate routine lane immediately. |
| Optional first tool | Finish eight Shop 1 jobs | Wide Brush blueprint. Building costs 80 cash and is optional. |
| Preview High Street | Bonzi built | Show next shop’s look, 600 price, checklist and opening kit. |
| Ready to expand | 15 manual Shop 1 jobs, 5 automated Shop 1 deliveries, 600 cash | “Open High Street” becomes available. No compulsory maxing of upgrades. |
| Open High Street | Player chooses to buy | Keep Shop 1 producing. Receive Shop 2, its basic bot unit, jet and squeegee kit; active view changes. |

At one manual job per minute, an expansion-focused player builds Bonzi at minute 5 and opens High Street around minute 29: five opening jobs pay for Bonzi, then 24 more pay 480 cash while Bonzi earns 120. This assumes uninterrupted cleaning, base equipment, no optional spending, and immediate reward collection. The gates are already met by that time.

A slower active pace also works. At 50% cleaning time after Bonzi, expansion is about minute 45. A guided return path does the minimum 15 manual jobs, then waits: approximately 15 minutes of hands-on/session work and 70 minutes away, opening around minute 85. “Idle-only from first launch” is not possible: the player must first earn Bonzi and meet the manual gate. After eight hours away at the base Shop 1 rate, 2,400 cash is claimable, but an unmet manual gate still blocks expansion.

These are pacing scenarios, not deadlines. There is no punishment for staying in the starter shop. The workbook exposes the assumptions and the difference between continuous rate estimates and completed-order payouts.

## 4. The layers inside each shop
Each shop is a small diorama behind a focused management panel. The player need not walk an avatar through rooms.

| Layer | Function | First appearance |
| --- | --- | --- |
| Personal cleaning pad | One selected carpet; owned tools; guaranteed manual payout | First launch |
| Routine intake | Incoming ordinary rugs; displays customer demand per hour | Bonzi reveal |
| Bonzi’s work lane | Cleans routine orders at a fixed capacity; small visible work loop | Bonzi purchase |
| Finishing station | Caps completed wet-service orders; absent for dry brush recipes | High Street opening |
| Tool bench | Personal tools, permanent blueprints, optional machine modules | First blueprint |
| Shop front and decor | New environment, signage and later cosmetic choices | Visible from launch; purchases optional |
| Expansion card | Next location, fixed price, checklist and included equipment | Bonzi purchase |

The early management decision is “clean faster, improve routine output, or save for the next place.” Limit Shop 1 to a few visible choices. Do not introduce staff wages, durability, consumable soap, electricity bills, storage micromanagement or mandatory decoration scores.

Routine production is capacity-limited: orders/hour = minimum of demand, cleaner capacity and finishing capacity. Omit finishing entirely when the recipe does not need it. Only completed automated orders pay. A continuous progress counter may run between deliveries; carry its fractional progress across saves. Average cash/hour = orders/hour × routine payout. Cash figures are net game rewards; no operating deductions are modeled.

Manual commissions and automated routine orders are separate pools. Taking a personal carpet never steals an order from Bonzi, pauses his lane or consumes its capacity. Routine order animations represent production; they are not an endless queue the player has to clear. Demand is a maximum hourly supply, not an accumulating backlog.

## 5. Shops, prices and reasons to move
| Shop | Opening price | Visual identity / new play | Manual cash / cycle | Base routine cash/hour |
| --- | --- | --- | --- | --- |
| 1. Neighborhood Shop | Free | Cozy mint-and-cream tiles; small dusty rugs; brush | 20 / 60 sec | 300 after Bonzi |
| 2. Busy High Street | 600 | Coral storefront, sunny windows; washable household rugs; jet + squeegee | 60 / 70 sec | 750 |
| 3. Restoration Studio | 6,000 | Indigo and warm timber; decorative rugs; localized treatment and pile work | 150 / 110 sec | 1,560 |
| 4. Commercial Workshop | 40,000 | Teal industrial bay; broad rugs; wide equipment | 350 / 140 sec | 4,200 |
| 5. Flagship Atelier | 180,000 | Cream and gold showroom; showcase rugs; integrated rig | 900 / 190 sec | 9,000 |

Shops 1–2 define the playable economy slice. Shops 3–5 and their numbers are planning placeholders. Each new shop raises authored contract value and adds a visible capability; higher payout is not calculated from total chain income. Existing rug difficulty and payout remain unchanged after expansion.

Shop 2 requires 15 manual jobs and 5 routine deliveries in Shop 1, plus Bonzi and the cash price. Shop 3 requires 12 manual jobs and 20 routine deliveries in Shop 2, including its jet/squeegee certification. Shop 4 requires 15 manual jobs and 30 routine deliveries in Shop 3, including its restoration certification. Shop 5 requires 18 manual jobs and 40 routine deliveries in Shop 4, including its broad-cleaning certification. Counts are local to the preceding shop, never lifetime totals from easier rugs. Certification is one guaranteed authored job included within the manual count, with normal payout. No reputation currency is spent.

Each opening price bundles the premises, local basic automated unit, necessary starter service tools, any required starter finishing station and their permanent blueprints. No setup timer or surprise second invoice. The next shop’s required abilities are therefore usable at zero remaining cash. Optional tools, modules and cosmetics cost extra. Prior equipment and cash remain owned; no trade-in, reset, resale or prestige in this slice.

One named Bonzi is the companion and face of the automation system. The first purchase includes his basic chassis. Later stores receive standard local cleaner units under Bonzi’s supervision. His character can accompany the active view while those units keep working. Do not imply that a single movable machine is simultaneously installed in multiple stores. Branch modules stay with their branch; personal tools and blueprint knowledge travel with the player.

### Exact expansion transaction
1. The next-shop card is revealed, then eligible when the service checklist is met, then affordable when cash is sufficient.
2. The player may keep cleaning or upgrading indefinitely. Selection of an already owned shop is free and does not reset production.
3. “Open shop” shows one purchase summary: price, what is included, cash remaining, and old shops continuing to earn.
4. Finish or explicitly pause the active carpet. Keep one resumable personal job across the chain; a new manual job requires completing or abandoning it. Abandonment grants nothing and does not reroll the offer.
5. Settle old production at old rates; atomically debit cash, grant shop/kit, start its production clock and save. Repeated input cannot buy twice.
6. Switch to the new shop after a short opening reveal. Show its first compatible carpet. On failure, keep the old state and money. Never grant catch-up production to a store for time before it existed.

## 6. Items, parts and blueprints
| Thing | What it means | How it is earned / spent |
| --- | --- | --- |
| Cash | Shared spendable money | Manual jobs and completed routine orders; buys shops, items and upgrades |
| Blueprint | Permanent permission to build one design | Guaranteed job milestones, certification or opening bundles; never spent |
| Owned personal tool | A built tool available at any owned shop | Free starter/bundle or one cash build; cannot build duplicate personal copies |
| Local machine module | A named upgrade to one branch unit | Cash, and parts for later modules; fixed prerequisite ladder |
| Machine Parts | One shared integer crafting resource | One per completed rewarded manual job in Shop 2 onward; spent on optional modules |
| Service record | Local manual and automated completion counts, certification flags | Automatically recorded; never spent or reduced |
| Cosmetic | Optional appearance choice | Later authored rewards or cash offers; no production bonus in this slice |

The blueprint answers “can I make it?” Cash and parts answer “can I afford to make or improve it?” An item is the usable result. Do not give the player fragments of blueprints as a second parts currency in this version. No random drop is required to progress.

Bonzi blueprint: awarded after three paid Shop 1 carpets; build 100 cash, zero parts. Wide Brush blueprint: after eight paid Shop 1 carpets; build 80 cash, zero parts. It makes the same starter rug’s target cleaning time fall from 50 to 40 seconds; the handling time stays 10 seconds. Its wider footprint must be visible in play. Later rugs are not silently made harder to cancel this improvement.

Bonzi Mk II branch module: after ten paid Shop 1 carpets and Bonzi built; costs 120 cash, zero parts; raises cleaner capacity from 30 to 45 orders/hour. Demand stays 40, so actual production rises only from 30 to 40. A 100-cash intake upgrade raises demand to 60; with Mk II installed, output reaches 45. Buying intake first gives no immediate income gain and must show that clearly.

High Street optional modules: cleaner 30→45 for 900 cash + 6 parts; finishing 36→48 for 600 cash + 4 parts; intake 40→60 for 750 cash. Their blueprints unlock at six local paid jobs. Suggested order is cleaner, finishing, intake, but none is required for expansion. Six High Street jobs provide exactly six parts: building the cleaner then requires four more eligible jobs to afford the finishing module. Routine income grants cash only; there is no parts catch-up or paid parts shortcut in the slice.

Parts have no inventory cap, random rarity, expiry or repair use. Starter-shop jobs and free replays yield no parts. Show parts only when High Street opens. A duplicate blueprint grant is a harmless no-op, not a reason to create a conversion economy. Every build/upgrade grants its result and charges all resources in one saved transaction. All listed upgrade costs are incremental, not total-to-level prices. Modules are one-time purchases; no infinite level formula yet.

Later tool families remain design territory: foam brush, pile rake, compact/wide twin-brush machine, rotary cleaner, extraction wand and integrated rig. A new family needs a distinct physical action or a meaningful combination of mastered steps. Mandatory capabilities arrive through opening/certification guarantees; optional variants can use whole blueprints plus cash/parts. Prices for those optional variants remain unset until their interactions exist.

## 7. Why upgrades are choices
The base starter shop produces 30 orders/hour × 10 cash = 300/hour. Mk II alone produces 40 × 10 = 400/hour: the 120-cash purchase repays its cost in 1.2 hours of production. Intake after Mk II adds another 50/hour and repays its 100 cost in 2 hours. Intake before Mk II produces no gain. Show actual income change, not just a machine’s theoretical speed.

The Wide Brush costs four starter payouts. At the target duration it raises uninterrupted manual earning rate from 1,200 to 1,440 cash/hour. Its cash payback is about 20 minutes of active cleaning; its immediate reward is a better-feeling, broader tool. It is not a mandatory gate to Bonzi or High Street.

The expansion-focused route is allowed to skip every optional upgrade. The long-return player may prefer faster routine production. An optimizer may find a best cash route; do not pretend every purchase has equal value. Playtest whether players still want the brush for its feel. If every upgrade is ignored, adjust cost or physical payoff rather than forcing all upgrades into the expansion checklist.

The workbook’s Upgrades sheet models bottlenecks in purchase order and shows cash-only payback. Parts and blueprint gates are additional acquisition effort, not included in those payback hours. Pacing scenarios deliberately exclude optional purchases so the baseline remains understandable.

## 8. Production, absence and return
Online and offline use the same base production rates. Production is not counted twice. While online, completed automatic orders credit cash immediately. On return, one chain-wide summary settles all owned automated branches; repeated claiming cannot duplicate a payout. No Bonzi means no routine earnings in Shop 1.

Proposed offline cap: eight hours per absence, chain-wide. Process min(elapsed absence, eight hours) for each store that existed at departure. Maintain the partial order remainder; whole completed orders pay and count toward automated service milestones. No purchases, blueprint unlocks, manual jobs or new shop openings happen automatically during an absence. The cap applies only to offline catch-up, not to uninterrupted online production.

On a rate change, settle elapsed production first using the old rate. The remainder is stored in orders, not cash, so raising capacity does not reprice previous cash. A system clock moving backward earns zero new time. Use a validated time source before commercial rewards matter; local-save time is sufficient for a clearly labeled prototype, not an anti-cheat guarantee.

At the base rates, eight hours with Shops 1–2 automated yields (300 + 750) × 8 = 8,400 cash. That can cover Shop 3’s 6,000 price, but only after the player has completed High Street’s manual gate and certification. This is intentional: returning should create a meaningful purchase, while each new technique still gets played. Later economy scope must test whether cash becomes surplus too quickly.

## 9. UI plan for the next implementation pass
| Surface | Information and actions | State or feedback requirement |
| --- | --- | --- |
| Cleaning HUD | One combined cleanliness bar; icon Back; conditional Finish job | Show Finish at 85%, auto-finish at 99%, award once, then open the next rug |
| Next-goal card | Bonzi first, then next shop; current progress and missing requirement | One goal at a time; allow optional upgrades without losing it |
| Shop overview | Manual job button; routine rate; Bonzi animation; bottleneck | “No bot yet,” producing, or demand/cleaner/finishing limited |
| Upgrade drawer | Current→next appearance, cost, parts, exact income/time change | Blueprint locked, affordable, short of resources, owned/maxed |
| Blueprint reveal | What unlocked and the build price | Owning blueprint is visibly different from owning tool |
| Shops selector | Current/owned/next location, income, aesthetics, checklist | Locked, eligible, affordable, owned; earlier shops stay selectable |
| Open-shop summary | Fixed cost, included tools/unit, cash left | Finish/pause current job; one transactional purchase |
| Return summary | Hours credited, capped time, per-shop cash and total | One collection action; no stack of individual store popups |

No separate blueprint-inventory screen is necessary in Shop 1. Put the blueprint state on the relevant item card. Parts appear beside cash only when they have a use. First-time rewards and shop reveals can be skipped after their essential message is shown.

Save data required before purchase UI: wallet; owned shops; local modules; owned personal tools; permanent blueprints; local manual and automated counts; certifications; active shop; active job ID/recipe/masks and paid flag; production timestamps/remainders; completed grant/purchase IDs; save version. Recipe availability must check actual usable capabilities. Cash cannot go negative, duplicate taps cannot duplicate builds, and a resumed job pays once.

## 10. Core feel, art and content rules retained
Keep the carpet large in a portrait-friendly fixed overhead or shallow-angle view. Drag to clean, use large tool buttons, offset touch contact above the finger, and stop strokes on release, tool change or lost focus. There is no need for player-controlled camera motion during a contract.

Use matte vinyl toy forms, chunky rounded tools, soft contact shadows and a restrained cheerful palette. Rugs retain woven detail; water and foam must read through texture and shape as well as color. Workshop changes should be recognizable even before reading the shop name. Bonzi needs a readable working motion and a small celebration, without blocking the cleaning area.

Ordinary rugs use one meaningful stage in the opening and two or three when later tools arrive. Do not force every unlocked tool into every job. Permanently unlock any fictional soap/treatment recipe; no disposable chemicals are needed. Target short opening rugs, later two-to-four-minute jobs and a five-minute maximum content target. Resume work instead of imposing expiry timers.

Customer rugs go home. An optional restoration album keeps before/after images and pattern swatches. It does not require pretending the player owns every customer’s rug. Earlier shops can offer optional album discovery; no forced daily branch tour.

Keep one active carpet simulation, bounded effects and simple background production. Target 30 fps on the selected lower-tier Android test device, with 60 where practical. Actual device performance remains untested. Do not implement physical fluid simulation, full storefront traversal, competitive rankings, pet rosters or mandatory prestige for this proof.

## 11. Scope, validation and decisions after testing
Build in this order: one paid brush contract with reliable save/reward; Bonzi and elapsed-time production; the starter optional brush/module; Shop 2 purchase and retained Shop 1 income; wet-service recipe and certification; parts/modules; then the return summary and two-shop balancing pass. Prove the jet/squeegee interaction before calling the two-shop slice complete. No game UI or runtime economy is implemented by this document update.

| Test | Starting hypothesis | What would change the design |
| --- | --- | --- |
| First reward and completion | Players understand Finish and do not hunt tiny residue | Tune coverage aid/threshold before enlarging rugs |
| Bonzi timing | 4–7 minutes of active opening play | Reprice from measured rug duration if outside range |
| Expansion timing | Roughly 25–40 minutes for continuous base play | Adjust price or payouts if the starter repeats feel stale |
| Upgrade clarity | Player can explain which station limits output | Simplify stations or improve the before/after preview |
| Automation value | Player notices the buddy and chooses to return | Adjust routine rate and visible feedback, not extra currencies |
| Manual value | Player voluntarily cleans after Bonzi arrives | Improve physical upgrades and rug variety before reward inflation |
| Return economy | Eight hours offers a useful purchase; service gates remain clear | Tune prices/cap if multiple chapters feel skipped or cash has no use |
| Ownership and recovery | Old shops produce; purchases and job rewards survive reload exactly once | Fix state accounting before adding more content |

Record actual cleaning duration, handling time, first Bonzi time, first expansion time, cash source/sink, skipped upgrades, active/passive cash share, local gate progress and return claims. Small playtests establish comprehension and feel, not market viability. No monetization balance is assumed here.

Decisions still to test: whether the 85% manual and 99% automatic thresholds feel right; desired strength of manual gates; whether parts create a meaningful optional choice; the Wide Brush’s actual time saving; final shop aesthetics and Bonzi art; whether the longer chain needs more than five authored destinations. Shop 3–5 prices and timings should not be production commitments yet.

## 12. Companion workbook
Carpet_Cleaner_Economy_v0_2.xlsx is the adjustable numeric model. Read Me explains the sheets; Assumptions, Shops and blue input cells hold tuning values; formulas calculate output, costs, pacing and offline claims. The first two shops are the slice baseline. Later shops are placeholders. The current written examples reflect the default workbook values; if the balance changes, regenerate or revise the examples before implementation.

Pacing is an average-rate estimate with whole manual job rounding. It includes carried cash between shop purchases and local job/delivery gates, but assumes no optional upgrades, no ad rewards, no parts spending, and online production without an offline cap. The separate Offline sheet handles bounded absence. A deterministic starter-route check validates completed-order arithmetic for the default first expansion.
