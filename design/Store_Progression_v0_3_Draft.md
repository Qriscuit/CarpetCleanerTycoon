# Carpet Cleaner: store progression

Implemented prototype and balance draft · 20 September 2026

The game now implements the four-store loop below, including brush upgrades, water and squeegee stages. Prices are editable prototype values; timings remain unmeasured playtest targets. Workbook transfer is pending the user's source document, and the existing workbook remains unchanged. This replaces the earlier proposal to introduce wet cleaning in Store 2. See [implementation coverage](Implementation_Coverage.md) for verification and remaining work.

## The loop

Clean a rug, collect coins, then choose between a higher payout and a better tool. Enjoy the final tool for several rugs before opening the next store. Earlier stores remain owned and keep earning. No currency or tool power resets on travel.

- Finish from 85% to below 99% for the normal payout. Reach 99% for exactly twice that payout.
- Payout upgrades increase coins per rug. Tool upgrades improve the physical cleaning action and visibly change the tool.
- Bonzi works independently. His income never consumes the player's next rug.
- The main menu manages stores and Bonzi. The cleaning scene keeps its continuous rug cycle and pooled dirt.
- Four stores are authored. Extra payout levels remain available after a store is ready to leave, within the currency safety limit; additional stores are future content.

## A quiet, readable screen

| Position | Player sees | Action |
| --- | --- | --- |
| Top right | Coin icon and current gold | Coins arrive here and count up |
| Top | Existing cleanliness bar | At 85%, show `Finish` and its coin amount |
| Bottom | Rug thumbnail; 85% and 99% payouts | A separate price button buys the next payout level |
| Left edge | Equipped brush icon | Opens a narrow tool drawer with current and next models |
| Main-menu store card | Bonzi progress, final-tool use, next-store price | Opens the next store when all three are ready |

Example at level 0: show **85%: 20 to 22** and **99%: 40 to 44**, with a separate **Upgrade: 25** button. Before/after values describe earnings; only the button's value is the purchase price. The payout card, tool drawer and short labels are implemented. A first-use animation linking the rug to its payout remains planned polish.

Purchases take effect immediately on an unfinished rug without resetting dirt. Update its displayed payout and saved quote in the same transaction. An already-completed rug and its flying reward coins retain their original value. Pause brushing while the drawer is open; let coin flights finish before enabling purchases so affordability matches the visible wallet.

## Four-store arc

Each store has its own payout level. Tools keep their existing power, and later stores offer additional tiers. Store names are working names.

| Store | Cleaning and art | Opening cost | Starting 85% / 99% payout | Level 19 payout | Next-store price |
| --- | --- | ---: | ---: | ---: | ---: |
| 1. Neighborhood | Brush; mint and cream | Free | 20 / 40 | 122 / 244 | 2,000 |
| 2. High Street | Better brushes; warm wood and coral | 2,000 | 160 / 320 | 976 / 1,952 | 16,000 |
| 3. Wash House | Introduce water and squeegee | 16,000 | 1,280 / 2,560 | 7,808 / 15,616 | 128,000 |
| 4. Restoration Studio | Develop the wet-cleaning tools | 128,000 | 10,240 / 20,480 | 62,464 / 124,928 | 1,024,000* |

*Store 5's price only illustrates a possible continuation rule. The game has no Store 5 purchase or content. Current stores use the shared floating building with palette changes; separate location environments are future art work.

### Editable balance rules

For store number `n`, use scale `S = 8^(n - 1)`. For payout level `L`, starting at zero:

| Value | Formula |
| --- | --- |
| Early payout | `S * ROUND(20 * 1.10^L, 0)` |
| Full payout | `2 * early payout` |
| Next payout upgrade | `S * ROUND(25 * 1.15^L, 0)` |
| Next-store purchase | `2,000 * S` |

Levels 0–19 are the first tuning range, not a required travel gate or a hard cap. Upgrade costs grow faster than payouts, making another store increasingly attractive. A heavily upgraded old store can outpay the next store's first rug. Purchases stop before invalid arithmetic or the **9,000,000,000,000,000** currency guard; this is not a literal infinity system.

### Tool progression

Offer four paid improvements per store at **80S, 200S, 500S and 1,000S**. The starter tool is free. These are incremental purchase prices.

Store 1 progresses from the current brush through a wide head, denser bristles, crafted wood and an engraved wooden capstone. Store 2 extends the same tool family with finer mesh detail and Chinese-inspired cloud or lattice carving. Keep matte materials and rounded silhouettes. A stronger tier changes width and/or dirt removal per pass, not only its color.

Implemented Store 1 widths are **1.44x, 1.55x, 1.65x and 1.75x** the starter; strength multipliers are **1.00x, 1.10x, 1.25x and 1.45x**. Store 2 holds width at 1.75x and raises strength to **1.60x, 1.80x, 2.00x and 2.25x**. The highest owned dry-tool power travels with the player, including when revisiting older stores. Nine authored brush variants cover starter through final Store 2 tier.

For Stores 3–4, the four improvements apply to the wet tool set. Each required starter tool is included in the store purchase. The playable prototype advances from brushing to water to squeegee. Dry clearance is the lower of debris and surface clearance; the wet-job meter averages dry, water and extraction progress. Water requires 99% dry clearance, and extraction requires 99% water coverage. Thus 85% overall allows an early finish partway through extraction; 99% completes automatically. Wet strength scales through **1.20x, 1.45x, 1.75x and 2.10x**; Store 4 starts from the previous capstone's strength. Wet balance and device feel still need measurement.

### Bonzi and travel

| Local Bonzi tier | Incremental price | Coins per completed bar | Bar duration |
| --- | ---: | ---: | ---: |
| Basic | 100 in Store 1; included in later openings | 10S | 120 seconds |
| Improved | 300S | 20S | 90 seconds |
| Final | 900S | 40S | 60 seconds |

Bonzi becomes purchasable after three paid Store 1 rugs. His upgrades are optional. Show the payout per bar and its seconds together. The manual payout button affects manual rugs; Bonzi has his own clearly displayed rates.

Travel requires all three:

1. Bonzi has earned **100S in this store**, including valid offline deliveries. Spending never reduces this cumulative record.
2. The store's final tool is owned and actually used on **three local paid rugs begun after its purchase**. An early finish counts; the rug already underway at purchase and replayed completions do not.
3. The wallet holds **2,000S**, charged once when the player chooses to open the next store.

Older-store income contributes to the shared wallet, but not another store's Bonzi milestone. Keep the existing eight-hour offline cap, fractional delivery progress and one-time crediting. Store purchases preserve earlier shops and include the new location's basic unit and required starter equipment.

## Ads and pacing

An optional rewarded-ad provider adapter and ledger path are implemented. A verified completion can grant one extra payout for the completed rug: a full clean worth 40 can gain an extra 40. The offer is tied to a job, with duplicate-receipt protection; cancellations and failures keep earned coins intact. Ad income does not count as Bonzi income or extra jobs. **No ad SDK, provider or IDs are configured, as requested**, so the production offer is hidden. Provider integration and real ad playback remain untested. Ads never gate travel or normal progression.

Balance the normal route with zero ads. Initial full-rug cycle targets, including handling, are **60 to 27 seconds in Store 1**, **27 to 19 in Store 2**, **52 to 32 in Store 3**, and **32 to 22 in Store 4**. These are unmeasured targets; the wet sequence adds actions without weakening the brush.

The workbook should compare early finishes, full finishes and a mixed route. Track actual purchases, wallet carryover, whole Bonzi deliveries and the three final-tool rugs. Test a player returning with eight hours of chain income: large savings may make purchases immediate, and this is a tuning consideration rather than an excuse to erase earned money.

## Implementation status

| Area | Current state | Remaining |
| --- | --- | --- |
| Definitions and workbook | Store rules live in `progression.gd`; four-store economy implemented | Transfer and tune the supplied workbook when available |
| Economy and saves | Shared wallet, local levels, all-store Bonzi, travel gates and per-store rugs; v1 migration and transaction rollback | Longer-session balance and real-device testing |
| Cleaning UI | Payout purchases and tool drawer update the current rug without resetting dirt | First-use payout teaching animation |
| Tool art and travel | Nine brush meshes, real width/strength upgrades, store swipes and visits | Further location art and feel tuning |
| Wet stores | Sequential brush, water and squeegee gameplay with saved masks | Wet pacing and device feedback |
| Optional ads | Verified-provider adapter, one-time bonus ledger and UI hook | SDK/provider/IDs and real playback, when supplied |

Two production scenes are driven by the selected store's data. Rug transitions, the fixed dirt pool and cosmetic reward particles are retained. Only one rug simulation runs; inactive stores retain snapshots. Expansion beyond the four authored stores and current numeric guard needs additional content and a large-number strategy. No APK was built for this implementation pass.

## Workbook layout

Use the supplied document as the starting point. Aim for five concise views: **Loop & Stores**, **Balance**, **Upgrades**, **Pacing**, and **Build Plan**. Put editable inputs beside their formulas, keep prices as numbers, freeze headers and use readable column widths. Keep detailed calculations separate from the short player-facing descriptions. Do not carry forward the old blueprint/parts complexity or Store 2 wet-cleaning requirement unless deliberately retained.
