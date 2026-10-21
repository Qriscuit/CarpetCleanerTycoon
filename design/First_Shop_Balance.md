# First section: six carpet workshops

The first section contains six places. The first place starts with a 40-coin
full-clean reward and stops at **400,000 coins per full carpet** when every room
accessory is fully upgraded. Larger number groups arrive progressively across
later places; the sixth place reaches **400 AF**. All six currently use brush
cleaning. A future section can introduce water jets, other locations or eras, but
no second section is playable in this build.

## Store progression

| Place | Starting full-clean reward | Maximum full-clean reward | Levels per accessory | Purchases across five accessories | Model upgrade levels |
| --- | ---: | ---: | ---: | ---: | --- |
| Neighborhood | 40 | 400 K | 50 | 250 | 15, 30, 45 |
| High Street | 400 K | 400 M | 75 | 375 | 25, 50, 75 |
| Wash House | 400 M | 4 T | 100 | 500 | 30, 60, 90 |
| Restoration Studio | 4 T | 400 AA | 125 | 625 | 40, 80, 120 |
| Grand Arcade | 400 AA | 4 AD | 150 | 750 | 50, 100, 150 |
| Royal Gallery | 4 AD | 400 AF | 175 | 875 | 50, 100, 150 |

Each next place begins at the preceding place's mastered reward. Its own room
ladder then grows farther, so the first place teaches the loop at a modest scale
and later places accelerate. The names are current identifiers; bespoke eras,
store scenery and new mechanics remain a separate content pass.

The shared wallet can exceed a store's reward cap. A reward cap limits the value
of one carpet in that place, not the player's accumulated coins. Early completion
at 75% settles the first half, including any cleaning coins already paid. Half
the full-clean amount is earned progressively during removal, normalized to the
99% target; Finish pays the unpaid part of that half. Full restoration settles
the other half too. Thus a fresh 40-coin carpet yields 20 total for an early
finish and 40 total at 99%. An optional verified video doubles only the current
carpet's quote. Store caps and upgrade prices use the base quote. Income comes
from the player's paid cleaning work; there is no idle or offline production.

## Independent accessory ladders

| Accessory | First price in Neighborhood | First full-clean increase |
| --- | ---: | ---: |
| Floor | 40 | +6 |
| Plants | 25 | +4 |
| Window | 60 | +8 |
| Railings | 35 | +4 |
| Walls | 50 | +6 |

Buying one accessory changes only its local level, next price and contribution.
All five contribute to the same carpet value. One purchase of every accessory
raises the first place's full-clean reward from 40 to 68 coins. Brush improvements remain separate purchases. Avatar starter colors and hats are free.

For store scale `S`, ladder cap `N` and full-clean cap `R`, solve a geometric growth
factor `g` so:

```text
(g^N - 1) / (g - 1) = (R / (2*S) - 20) / 14
price at current level L = S * round(first_price * g^L)
early contribution at purchased level L = S * round(first_early_gain * (g^L - 1)/(g - 1))
full-clean reward = 2 * (20*S + sum(all accessory early contributions))
```

The first early gains are 3, 2, 4, 2 and 3. Contributions use cumulative rounding,
so the purchase gain is the difference between its new and old contribution.
Each accessory receives its weighted share of the final reward budget; walls
receive any final rounding residue. Completing all five therefore produces the
exact stated cap, without overshooting it. The production rules are in
`CarpetToy/scripts/progression.gd` and `CarpetToy/scripts/room_upgrades.gd`.

With all five Neighborhood accessories at the same level, the full-clean reward
is 236 at level 5, 1,592 at level 15, 17,636 at level 30, 183,540 at level 45 and
400,000 at level 50. These are curve checkpoints, rather than a required purchase
order. A player can improve the accessories in any order.

## Brush prices

Four brush upgrades span each place's starting, early, middle and maximum earning
range. Prices are fixed by place and tier; room improvements or a temporary
carpet reward boost do not change an offer's price.

For starting full-carpet quote `P = 40*S` and maximum full-carpet quote `R`:

```text
brush price = round(3 * P * (R/P)^t), with t = 0, 1/3, 2/3, 1
```

A brush costs about three carpets at its intended earning milestone.
Neighborhood's exact prices are 120, 2,585, 55,699 and 1,200,000.

| Place | Four brush prices |
| --- | --- |
| Neighborhood | 120 / 2.6 K / 55.7 K / 1.2 M |
| High Street | 1.2 M / 12 M / 120 M / 1.2 B |
| Wash House | 1.2 B / 25.9 B / 557 B / 12 T |
| Restoration Studio | 12 T / 557 T / 25.9 AA / 1.2 AB |
| Grand Arcade | 1.2 AB / 258.5 AB / 55.7 AC / 12 AD |
| Royal Gallery | 12 AD / 5.6 AE / 2.6 AF / 1.2 AG |

The table uses the game's compact display rounding. Actual purchases use whole
currency values from the formula, including float-safe values beyond int64.
Current prices and room curves are unchanged by removal of automated income.
The former automated-income simulator and its historical pacing output do not
describe the current manual loop.

## Mastery and travel

A place is complete when all five accessories reach that place's level cap,
its four brush upgrades are bought, and three paid rugs have used that place's
maximum brush. Opening the following place additionally requires and spends
`2000*S` coins. No automation purchase or earnings target remains. Revisiting an
owned place is free and restores its exact unfinished rug and accessory levels.

The first section completes only after all six places are mastered. Ownership
alone does not count as completion. The section system checks that a following
section has authored content as well as a completed preceding section. Completing
Royal Gallery currently shows section completion and a locked future chapter;
it cannot create or enter an imaginary seventh store.

## Appearance milestones

Each accessory currently has a baseline model plus three upgraded models.
Spread its three actual model changes across that place's ladder using the
milestones in the table. Keep the current model between milestones. After the
last authored model, remaining purchases continue increasing earnings without
claiming another appearance change.

The general rule uses the available upgrade model count: 50 levels and five
upgraded meshes gives 10, 20, 30, 40 and 50; 175 levels and three upgraded meshes
gives 50, 100 and 150. Intervals use readable multiples of five, or ten when the
raw interval reaches fifty. The bar advances toward the next real mesh change,
resets at that change, then tracks the remaining level count against the economic
cap after the final model is earned. Only the actual cap shows Fully upgraded
and a full completed bar.

## Fresh save and appearance

The game starts fresh in `user://carpet_cleaner_v1.json` using ledger schema 1.
The former `neighborhood_shop_v1.json` is left untouched and is never read,
imported or refunded. Its wallet, purchases and offline interval do not carry over.
New saves retain manual work, room and brush levels, selected store, paid reward
records and global appearance. Loading or returning from the background grants
no money and makes no cleaning progress.

The avatar customization menu opens from the main menu's bottom-right entry.
Eight colors and three hat choices are free; the default is orange with no hat.
Appearance has no price, earnings multiplier or store-unlock requirement.
The selected figure is always available as a visual companion in paid rooms:
it rides the brush, can fall from fast tool motion, and returns to its seat.
This behavior leaves manual cleaning, reward caps, prices and travel gates
unchanged. Customer handoffs, character XP and growth are not implemented.

## Validation

Use the pinned Godot 4.7.2 stable Mono bundle through `tools/run_godot.ps1`, with
`-- --shop-test` for every gameplay check. Disposable ledgers cover all six places,
real purchases through every cap, exact reward ceilings, brush-only recipes,
mastery gates, future-section locks, failed-save rollback and current save/reload.

Focused suites: `validate_section_progression.gd`, `validate_first_shop_mastery.gd`,
`validate_room_economy.gd`, `validate_progression.gd` and `validate_store_loop.gd`.
`validate_upgrade_price_progression.gd` checks every price stage, actual purchases,
affordability, failure rollback and retained ownership across all six places.
The current curve is deterministic; pacing and touch feel still need device
playtests before treating a particular completion time as a design promise.

On 17 October 2026, the current nine headless ledger suites completed 13,152
checks with zero failures, including 3,568 six-store progression checks and 116
appearance-state checks. These runs used the pinned runner, isolated APPDATA
and `-- --shop-test`; they do not establish a repository-wide or device result.
