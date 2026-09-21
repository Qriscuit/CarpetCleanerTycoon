# Current implementation coverage

20 September 2026 · Four-store progression prototype

The playable loop is implemented across the existing floating main menu and rug-cleaning scene. This document separates code and desktop validation from balance targets, unfinished polish and external setup. The existing workbook is untouched while the user's source document is pending. **No APK was built for this implementation pass.**

## Request to implementation

Paths below are relative to the repository; script names are under `CarpetToy/scripts/` and validators under `tools/`.

| Request | Implemented behavior and main files | Verification |
| --- | --- | --- |
| Separate home and cleaning, with store selection | `floating_home.gd`, `compact_shop.gd`, `workshop.gd`: tap enters the selected store; swipes preview stores; owned stores retain separate rugs. Two entry scenes remain under `scenes/production/`. | `validate_store_loop.gd`; existing scene-route checks |
| Continuous rugs without dirt-instance churn | `workshop.gd`, `dirt_controller.gd`: dusty rug rolls in, 25 starter rocks grow, then the brush arrives; suction and rollaway lead to the next rug using the same 560-slot pool. Latent rocks appear through brushing. | `validate_dirt_pool.gd`, `validate_rug_transition.gd`, `validate_cleaning.gd` |
| Early or full completion and reliable rewards | `shop_state.gd`, `workshop.gd`: 85% allows early finish; 99% completes automatically. Starter rewards are 20/40; every later full reward stays exactly twice early. Next-rug reservation and earnings commit together. | `validate_progression.gd`, `validate_coin_rewards.gd`, `validate_rug_transition.gd` |
| Coins visibly reach the wallet | `cleaning_hud.gd`: reusable coin burst lingers then flies to the top-right wallet. Exact per-coin values update display only; interruption cannot duplicate or lose saved rewards. | `validate_coin_rewards.gd`; production transition checks |
| Choose payout or equipment upgrades | `progression.gd`, `shop_state.gd`, `cleaning_hud.gd`: bottom payout card separates reward previews from price; left drawer compares tools. Purchases immediately update the unfinished rug's quote or tool behavior without resetting it. | `validate_progression.gd`, `validate_store_loop.gd`; HUD/coin regression checks |
| Better-looking tools with real effects | `tool_progression_visual.gd`, `assets/tools/progression/`, `tools/build_progression_tools.py`: nine matte brush variants, from plastic through crafted wood and patterned capstones. Dry width grows to 1.75×; strength continues to 2.25×. Highest owned power persists across visits. | Progression and store-loop checks; authored model assets |
| Bonzi income in understandable units | `progression.gd`, `shop_state.gd`, `compact_shop.gd`: each bar shows coins and seconds. Basic/improved/final rates are 10S/120s, 20S/90s and 40S/60s. All owned stores earn independently, with fractional carry and an eight-hour offline cap. | `validate_progression.gd` |
| Earn, use the final tool, then travel | `shop_state.gd`: local cumulative Bonzi earnings of 100S, three paid rugs begun after the final-tool purchase and actually using it, and 2,000S travel cash. Spending does not reverse milestone progress. | `validate_progression.gd`, `validate_store_loop.gd` |
| Four stores; brush first, wet techniques later | `progression.gd`, `workshop.gd`, `dirt_controller.gd`, `soil_surface.gdshader`: Stores 1–2 use brushes; 3–4 add water then squeegee. Later stages are gated, their masks save, and the combined meter drives early/full rewards. | `validate_wet_cleaning.gd`, progression and store-loop checks |
| Preserve old progress and prevent duplicate credit | `shop_state.gd`: v1 migration preserves cash, owned power, Bonzi, current rug and clock state. Atomic saves roll back failed purchases, travel and rewards. Per-store snapshots support revisiting. | Migration, rollback/retry, repeat-job and offline cases in `validate_progression.gd` |
| Optional reward ads without forced gates | `reward_ad_service.gd`, `shop_state.gd`: provider availability, verified receipt, one bonus per completed job and duplicate protection; bonus matches the completed payout. Offer is hidden without a provider. | Mock-provider success, cancellation, duplicate and failed-save retry checks in `validate_progression.gd`; no real ad playback |
| Quiet, responsive UI and reset | `floating_home.gd`, `compact_shop.gd`, `cleaning_hud.gd`: short labels, icon actions, wallet, compact purchase views and safe-area layout. Drawers pause cleaning and transitions. Main-menu Settings resets progress after confirmation. | Desktop layout/input and store-loop/HUD checks; device testing remains |

`S = 8^(store_id - 1)`. Definitions and current proposed prices are in [the progression draft](Store_Progression_v0_3_Draft.md) and `CarpetToy/scripts/progression.gd`.

## Verification limits and remaining work

- **Implemented scope:** four authored stores and payout levels beyond the first 20-level tuning range. Level 19 is neither a cap nor a travel requirement. Store 4 has no next-store purchase. Arithmetic rejects values beyond **9,000,000,000,000,000**; this is not literal infinite progression.
- **Balance:** prices, brush speed and wet-kit strength are tunable prototype values. Full-cycle timing targets are unmeasured. Long-session pacing, carryover from several passive stores and eight-hour returns need playtesting; no elapsed-time completion promise is established by seeded travel tests.
- **Mobile:** desktop graphics checks cover routes, input, layout and resource reuse. They do not establish performance or feel on every phone. Real-device touch, safe areas, rotation, memory and GPU measurements remain, followed by an explicitly requested APK build.
- **Ads:** the provider adapter and bonus ledger are ready. No SDK, provider or ad IDs are configured, as requested. Real playback, platform integration and provider verification need completion when those details are supplied; all ordinary progression works without ads.
- **Polish:** the first-use animation teaching the rug-to-payout relationship is not implemented. Stores currently share the floating building with palette changes; more location art and wet-tool feedback can follow device playtests.
- **Workbook:** wait for the user's source document before editing or transferring numbers. The existing spreadsheet and older GDD remain historical references, not a current implementation checklist.

Run validators with `--shop-test` to isolate saves; graphics suites need the real renderer for MultiMesh assertions. Suite names describe behavior checks, not a count of devices or playthroughs. Current run logs and captures live in `art/`; final run results belong in the delivery report rather than a stale fixed total here.
