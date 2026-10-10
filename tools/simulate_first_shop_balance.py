"""Six-store curve reference and first-shop pacing; never accesses game saves.

Uses Decimal geometric curves, cumulative early-income rounding and exact caps.
First-shop pacing models assumed manual rug times, room purchases and Bonzi speed,
not measured gameplay or the separate brush/service travel requirements.
Run: python tools/simulate_first_shop_balance.py [--json]
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from decimal import Decimal, ROUND_HALF_UP, getcontext
from fractions import Fraction
import json
import math

getcontext().prec = 90
STORE_NAMES = ("Neighborhood", "High Street", "Wash House", "Restoration Studio",
               "Grand Arcade", "Royal Gallery")
STORE_SCALES = (1, 10**4, 10**7, 10**11, 10**16, 10**23)
LEVEL_CAPS = (50, 75, 100, 125, 150, 175)
REWARD_CAPS = (4 * 10**5, 4 * 10**8, 4 * 10**12, 4 * 10**17, 4 * 10**24, 4 * 10**32)
MAX_LEVEL = LEVEL_CAPS[0]
BASE_FULL_REWARD = 40
OFFLINE_CAP = 8 * 3600
BOT_SECONDS = (120, 90, 60)
BOT_COSTS = (160, 16000, 1600000)
FEATURES = {
    "floor": (40, 6),
    "plants": (25, 4),
    "window": (60, 8),
    "railings": (35, 4),
    "walls": (50, 6),
}
SUFFIXES = ("", "K", "M", "B", "T", "AA", "AB", "AC", "AD", "AE", "AF", "AG")
CHECKPOINTS = (5, 15, 30, 45, 50)


def round_coins(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_HALF_UP))


def geometric_growth(scale: int, cap: int, reward_cap: int) -> Decimal:
    target = (Decimal(reward_cap) / (2 * scale) - 20) / 14
    low, high = Decimal(1), Decimal(2)
    for _ in range(160):
        middle = (low + high) / 2
        total = (middle**cap - 1) / (middle - 1)
        if total < target:
            low = middle
        else:
            high = middle
    return (low + high) / 2


def make_curve(store_index: int) -> dict:
    scale, cap, reward_cap = (STORE_SCALES[store_index], LEVEL_CAPS[store_index],
                              REWARD_CAPS[store_index])
    growth = geometric_growth(scale, cap, reward_cap)
    available = reward_cap // 2 - 20 * scale
    budgets = {}
    for name, (_, full_gain) in FEATURES.items():
        budgets[name] = (available - sum(budgets.values()) if name == "walls"
                         else round_coins(Decimal(available) * full_gain / 28))
    prices, marginals, contributions = {}, {}, {}
    for name, (price, full_gain) in FEATURES.items():
        prices[name] = tuple(scale * round_coins(Decimal(price) * growth**level)
                             for level in range(cap))
        cumulative = [0]
        for level in range(1, cap + 1):
            cumulative.append(budgets[name] if level == cap else min(
                budgets[name], scale * round_coins(Decimal(full_gain) / 2
                    * (growth**level - 1) / (growth - 1))))
        contributions[name] = tuple(cumulative)
        marginals[name] = tuple(2 * (cumulative[level] - cumulative[level - 1])
                                for level in range(1, cap + 1))
    return {"scale": scale, "cap": cap, "reward_cap": reward_cap, "growth": growth,
            "prices": prices, "marginals": marginals, "contributions": contributions}


CURVES = tuple(make_curve(index) for index in range(6))
GROWTH = CURVES[0]["growth"]
PRICES = CURVES[0]["prices"]
MARGINALS = CURVES[0]["marginals"]


def compact(value: int) -> str:
    if value < 1000:
        return str(value)
    exponent = min((len(str(abs(value))) - 1) // 3, len(SUFFIXES) - 1)
    return f"{Decimal(value) / (Decimal(1000)**exponent):.3f} {SUFFIXES[exponent]}"


@dataclass
class Shop:
    manual_seconds: int = 60
    reserve_starter_bot: bool = True
    now: float = 0.0
    wallet: int = 0
    levels: dict[str, int] = field(default_factory=lambda: dict.fromkeys(FEATURES, 0))
    full_reward: int = BASE_FULL_REWARD
    manual_jobs: int = 0
    bot_jobs: int = 0
    bot_tier: int = -1
    next_manual: float = 0.0
    next_bot: float = math.inf
    purchases: int = 0
    bot_purchase_times: list[float] = field(default_factory=list)
    milestone_times: dict[int, float] = field(default_factory=dict)
    largest_wait: float = 0.0
    last_purchase: float = 0.0

    def __post_init__(self) -> None:
        self.next_manual = float(self.manual_seconds)

    def rate(self, manual: bool) -> Fraction:
        return (Fraction(1, self.manual_seconds) if manual else Fraction(0)) + (
            Fraction(1, BOT_SECONDS[self.bot_tier]) if self.bot_tier >= 0 else Fraction(0))

    def spend(self, manual: bool) -> None:
        """Greedy affordable income-per-second ROI; stable feature-order ties.

        Optional tutorial policy reserves the starter bot's 160 coins after the
        third paid manual rug. Subsequent purchases use ordinary affordable ROI.
        This models player choices, not a new automatic game purchase.
        """
        while True:
            if self.reserve_starter_bot and self.bot_tier < 0 and self.manual_jobs >= 3:
                if self.wallet < BOT_COSTS[0]:
                    return
                self.buy_bot()
                continue
            candidates: list[tuple[Fraction, int, str]] = []
            rate = self.rate(manual)
            for index, (name, level) in enumerate(self.levels.items()):
                if level < MAX_LEVEL and PRICES[name][level] <= self.wallet:
                    candidates.append((Fraction(MARGINALS[name][level], PRICES[name][level]) * rate,
                                       -index, name))
            new_tier = self.bot_tier + 1
            if new_tier < len(BOT_SECONDS) and (new_tier > 0 or self.manual_jobs >= 3):
                if BOT_COSTS[new_tier] <= self.wallet:
                    old_rate = Fraction(1, BOT_SECONDS[self.bot_tier]) if self.bot_tier >= 0 else Fraction(0)
                    delta_rate = Fraction(1, BOT_SECONDS[new_tier]) - old_rate
                    candidates.append((Fraction(self.full_reward, BOT_COSTS[new_tier]) * delta_rate,
                                       -len(FEATURES), "bot"))
            if not candidates:
                return
            _, _, name = max(candidates)
            if name == "bot":
                self.buy_bot()
                continue
            level = self.levels[name]
            self.wallet -= PRICES[name][level]
            self.full_reward += MARGINALS[name][level]
            self.levels[name] = level + 1
            self.purchases += 1
            self.largest_wait = max(self.largest_wait, self.now - self.last_purchase)
            self.last_purchase = self.now
            for milestone in CHECKPOINTS:
                if milestone not in self.milestone_times and min(self.levels.values()) >= milestone:
                    self.milestone_times[milestone] = self.now

    def buy_bot(self) -> None:
        fraction = 0.0 if self.bot_tier < 0 else max(0.0, min(1.0,
            1.0 - (self.next_bot - self.now) / BOT_SECONDS[self.bot_tier]))
        self.bot_tier += 1
        self.wallet -= BOT_COSTS[self.bot_tier]
        self.next_bot = self.now + (1.0 - fraction) * BOT_SECONDS[self.bot_tier]
        self.bot_purchase_times.append(self.now)

    def next_payment(self, manual: bool = True) -> bool:
        at = min(self.next_manual if manual else math.inf, self.next_bot)
        if not math.isfinite(at):
            return False
        self.now = at
        reward = self.full_reward  # Settle all work before any upgrade at this instant.
        if manual and self.next_manual <= at + 1e-8:
            self.wallet += reward
            self.manual_jobs += 1
            self.next_manual += self.manual_seconds
        if self.next_bot <= at + 1e-8:
            self.wallet += reward
            self.bot_jobs += 1
            self.next_bot += BOT_SECONDS[self.bot_tier]
        self.spend(manual)
        return True

    def active_until(self, target: float) -> None:
        while min(self.next_manual, self.next_bot) <= target:
            self.next_payment(True)
        self.now = target

    def return_after(self, absent_seconds: float) -> dict:
        before = self.wallet
        jobs = 0
        credited_seconds = min(max(absent_seconds, 0.0), OFFLINE_CAP)
        if self.bot_tier >= 0:
            cycle = BOT_SECONDS[self.bot_tier]
            fraction = max(0.0, min(1.0, 1.0 - (self.next_bot - self.now) / cycle))
            total = fraction + credited_seconds / cycle
            jobs = math.floor(total + 1e-9)
            fraction = max(0.0, total - jobs)
            self.wallet += jobs * self.full_reward
            self.bot_jobs += jobs
            self.now += absent_seconds
            self.next_bot = self.now + (1.0 - fraction) * cycle
        else:
            self.now += absent_seconds
        earned = self.wallet - before
        purchases_before = self.purchases
        self.spend(False)
        return {
            "credited_seconds": credited_seconds, "completed_bot_rugs": jobs,
            "earned": earned, "earned_display": compact(earned),
            "return_purchases": self.purchases - purchases_before,
            "full_reward_after": self.full_reward,
            "full_reward_after_display": compact(self.full_reward),
            "levels_after": self.levels.copy(),
        }


def continuous(manual_seconds: int, reserve: bool = True) -> dict:
    shop = Shop(manual_seconds=manual_seconds, reserve_starter_bot=reserve)
    for _ in range(100000):
        if min(shop.levels.values()) == MAX_LEVEL:
            break
        assert shop.next_payment(True)
    else:
        raise AssertionError("Unbounded first-shop completion")
    return {
        "manual_seconds": manual_seconds, "starter_bot_reservation": reserve,
        "seconds_to_cap": shop.now, "hours_to_cap": round(shop.now / 3600, 3),
        "manual_rugs": shop.manual_jobs, "bot_rugs": shop.bot_jobs,
        "feature_purchases": shop.purchases, "full_reward": shop.full_reward,
        "max_wait_between_purchases_seconds": shop.largest_wait,
        "bot_purchase_times_seconds": shop.bot_purchase_times,
        "all_features_reach_level_at_seconds": shop.milestone_times,
    }


def dropoff(active_minutes: int, reserve: bool = True) -> dict:
    shop = Shop(manual_seconds=60, reserve_starter_bot=reserve)
    shop.active_until(active_minutes * 60)
    before = {
        "active_minutes": active_minutes, "starter_bot_reservation": reserve,
        "bot_tier_at_dropoff": shop.bot_tier, "reward_at_dropoff": shop.full_reward,
        "reward_at_dropoff_display": compact(shop.full_reward),
        "levels_at_dropoff": shop.levels.copy(), "wallet_at_dropoff": shop.wallet,
    }
    before["return_after_8h"] = shop.return_after(OFFLINE_CAP)
    before["return_after_next_12h"] = shop.return_after(12 * 3600)
    return before


def idle_visits() -> dict:
    shop = Shop(manual_seconds=60, reserve_starter_bot=True)
    shop.active_until(5 * 60)
    visits = 0
    milestone_visits: dict[int, int] = {}
    while min(shop.levels.values()) < MAX_LEVEL and visits < 100:
        shop.return_after(OFFLINE_CAP)
        visits += 1
        for milestone in CHECKPOINTS:
            if milestone not in milestone_visits and min(shop.levels.values()) >= milestone:
                milestone_visits[milestone] = visits
    assert shop.purchases == MAX_LEVEL * len(FEATURES)
    return {"initial_active_minutes": 5, "return_interval_hours": 8,
            "returns_to_cap": visits, "wall_clock_days": round(shop.now / 86400, 3),
            "all_features_reach_level_after_return": milestone_visits,
            "full_reward": shop.full_reward}



def visual_milestones(cap: int, upgrades: int = 3) -> tuple[int, ...]:
    interval = max(1, cap // min(cap, upgrades))
    rounding = 10 if interval >= 50 else 5 if interval >= 5 else 1
    interval = max(1, interval // rounding * rounding)
    return tuple(interval * tier for tier in range(1, min(cap, upgrades) + 1))


def store_summary(index: int) -> dict:
    curve = CURVES[index]
    return {"store_id": index + 1, "section_id": 1, "store_name": STORE_NAMES[index],
            "scale": curve["scale"], "cap_each": curve["cap"],
            "room_purchases": curve["cap"] * len(FEATURES),
            "starting_full_reward": 40 * curve["scale"],
            "starting_full_display": compact(40 * curve["scale"]),
            "max_full_reward": curve["reward_cap"],
            "max_full_display": compact(curve["reward_cap"]),
            "growth": str(curve["growth"]),
            "model_milestones": visual_milestones(curve["cap"]),
            "mechanic": "brush", "opening_coins": 2000 * curve["scale"],
            "bonzi_earned_target": 100 * curve["scale"]}

def report() -> dict:
    milestones = []
    for level in CHECKPOINTS:
        full = BASE_FULL_REWARD + sum(sum(gains[:level]) for gains in MARGINALS.values())
        milestones.append({"level_each": level, "purchases_total": level * len(FEATURES),
                           "full_reward": full, "display": compact(full),
                           "next_price_min": min(PRICES[name][level] for name in FEATURES) if level < MAX_LEVEL else None,
                           "next_price_max": max(PRICES[name][level] for name in FEATURES) if level < MAX_LEVEL else None})
    maximum = milestones[-1]["full_reward"]
    return {
        "parameters": {"income_growth": str(GROWTH), "price_growth": str(GROWTH),
                       "cap_each": MAX_LEVEL, "first_shop_full_reward_cap": REWARD_CAPS[0],
                       "base_full_reward": BASE_FULL_REWARD,
                       "feature_price_and_first_full_gain": FEATURES,
                       "rounding": "half-up cumulative early contributions; final budgets close exactly to cap; full=2*early",
                       "notation": {suffix: f"1e{index * 3}" for index, suffix in enumerate(SUFFIXES) if suffix}},
        "balanced_milestones": milestones,
        "max_full_reward": maximum, "max_full_reward_display": compact(maximum),
        "section_stores": [store_summary(index) for index in range(6)],
        "max_60s_bot_per_hour": compact(maximum * 60),
        "max_60s_bot_8h_return": compact(maximum * 480),
        "continuous": [continuous(seconds) for seconds in (40, 60, 120, 162)],
        "dropoffs": [dropoff(minutes) for minutes in (5, 15, 60)],
        "unguided_5min_dropoff": dropoff(5, False),
        "idle_returns": idle_visits(),
    }


def validate(result: dict) -> None:
    assert result["max_full_reward"] == REWARD_CAPS[0] == 400000
    assert sum(FEATURES[name][1] for name in FEATURES) == 28
    for name, (price, first_gain) in FEATURES.items():
        assert PRICES[name][0] == price and MARGINALS[name][0] == first_gain
        assert all(gain > 0 and gain % 2 == 0 for gain in MARGINALS[name])
        assert all(PRICES[name][i + 1] > PRICES[name][i] for i in range(MAX_LEVEL - 1))
    for index, curve in enumerate(CURVES):
        assert 40 * curve["scale"] + 2 * sum(
            values[-1] for values in curve["contributions"].values()) == REWARD_CAPS[index]
        if index:
            assert 40 * curve["scale"] == REWARD_CAPS[index - 1]
        assert all(gain > 0 for values in curve["marginals"].values() for gain in values)
    assert visual_milestones(50, 5) == (10, 20, 30, 40, 50)
    assert visual_milestones(175, 3) == (50, 100, 150)
    for profile in result["continuous"]:
        assert profile["feature_purchases"] == MAX_LEVEL * len(FEATURES)
        assert profile["full_reward"] == result["balanced_milestones"][-1]["full_reward"]
    for profile in result["dropoffs"]:
        assert profile["bot_tier_at_dropoff"] >= 0
        assert profile["return_after_next_12h"]["credited_seconds"] == OFFLINE_CAP


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print the complete deterministic report")
    args = parser.parse_args()
    result = report()
    validate(result)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for store in result["section_stores"]:
            print(store["store_name"] + ":", store["starting_full_display"], "->",
                  store["max_full_display"], ";", store["cap_each"], "levels per accessory")
        print("First-shop maximum:", result["max_full_reward_display"], "per full rug")
        print("Max Bonzi:", result["max_60s_bot_per_hour"], "/hour;", result["max_60s_bot_8h_return"], "/8h")
        for row in result["balanced_milestones"]:
            print("Balanced level", row["level_each"], ":", row["display"])
        for row in result["continuous"]:
            print("Continuous", row["manual_seconds"], "s manual:", row["hours_to_cap"], "hours; milestones", row["all_features_reach_level_at_seconds"])
        for row in result["dropoffs"]:
            print("Dropoff", row["active_minutes"], "min:", row["reward_at_dropoff_display"], "per rug; return", row["return_after_8h"])
        print("Unguided 5-minute dropoff:", result["unguided_5min_dropoff"])
        print("Idle visits:", result["idle_returns"])
