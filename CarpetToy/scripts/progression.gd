extends RefCounted
## Editable progression rules. All prices are incremental and use one wallet.
const Money := preload("res://scripts/money.gd")
const MAX_MONEY := Money.MAX_VALUE
const MAX_COUNTER := 9000000000000000
const STORES_PER_SECTION := 6
const SECTION_COUNT := 1
const STORE_COUNT := STORES_PER_SECTION * SECTION_COUNT
const TRAVEL_LEVEL_TARGET := 19
const CAPSTONE_JOBS := 3
const STORE_NAMES := ["Neighborhood", "High Street", "Wash House", "Restoration Studio", "Grand Arcade", "Royal Gallery"]
const STORE_SCALES := [1.0, 1e4, 1e7, 1e11, 1e16, 1e23]
const ROOM_LEVEL_CAPS := [50, 75, 100, 125, 150, 175]
const REWARD_CAPS := [4e5, 4e8, 4e12, 4e17, 4e24, 4e32]
# Neighborhood reference prices. Runtime offers use the same staged curve at
# each store's unboosted starting quote and authored full-carpet ceiling.
const TOOL_COSTS := [120, 2585, 55699, 1200000]
const TOOL_PRICE_STAGES := [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
const TOOL_PRICE_RUGS := 3.0
const TOOL_NAMES := ["Hand brush", "Wide brush", "Firm brush", "Power brush", "Master brush", "Precision brush", "Dual brush", "Pro brush", "Ultimate brush"]
const TOOL_WIDTHS := [1.0, 1.44, 1.55, 1.65, 1.75, 1.75, 1.75, 1.75, 1.75]
const TOOL_POWERS := [1.0, 1.0, 1.1, 1.25, 1.45, 1.6, 1.8, 2.0, 2.25]
const WET_NAMES := ["Wash kit", "Fresh wash kit", "Deep wash kit", "Power wash kit", "Master wash kit"]
const WET_POWERS := [1.0, 1.2, 1.45, 1.75, 2.1]
const WET_FIRST_STORE := STORES_PER_SECTION + 1

static func scale_for(store_id: int) -> float:
	return float(STORE_SCALES[store_id - 1]) if store_id >= 1 and store_id <= STORE_COUNT else 0.0

static func room_level_cap(store_id: int) -> int:
	return int(ROOM_LEVEL_CAPS[store_id - 1]) if store_id >= 1 and store_id <= STORE_COUNT else 0

static func reward_cap(store_id: int) -> float:
	return float(REWARD_CAPS[store_id - 1]) if store_id >= 1 and store_id <= STORE_COUNT else 0.0

static func section_for(store_id: int) -> int:
	return int((store_id - 1) / STORES_PER_SECTION) + 1 if store_id >= 1 else 0

static func store_in_section(store_id: int) -> int:
	return (store_id - 1) % STORES_PER_SECTION + 1 if store_id >= 1 else 0

static func section_available(section_id: int) -> bool:
	return section_id >= 1 and section_id <= SECTION_COUNT

static func section_name(section_id: int) -> String:
	return "Carpet workshops" if section_id == 1 else "Next chapter"

static func dry_stage(store_id: int, level: int) -> int:
	return maxi(0, (store_id - 1) * 4 + clampi(level, 0, 4))

static func dry_visual_tier(stage: int) -> int:
	# Nine authored brushes cover twenty-four numerical upgrades.
	return stage if stage <= 4 else mini(8, 4 + int((stage - 4) / 5))

static func dry_power(stage: int) -> float:
	return float(TOOL_POWERS[stage]) if stage <= 8 else float(TOOL_POWERS[8]) * pow(1.12, stage - 8)

static func store_name(store_id: int) -> String:
	return STORE_NAMES[store_id - 1] if store_id >= 1 and store_id <= STORE_COUNT else "Unknown store"

static func wet_base_power(store_id: int) -> float:
	# Each later wet store starts from the preceding store's capstone. Moving
	# wet cleaning to Store 2 must not make Store 3 sell four no-op upgrades.
	return pow(2.1, maxi(0, store_id - WET_FIRST_STORE))

static func _scaled_value(base: float, growth: float, level: int, store_id: int) -> float:
	if level < 0 or scale_for(store_id) == 0:
		return -1
	var raw := base * pow(growth, level)
	var scale := scale_for(store_id)
	if not is_finite(raw) or raw > float(MAX_MONEY) / float(scale):
		return -1
	var rounded := roundf(raw)
	if rounded > MAX_MONEY / scale:
		return -1
	return rounded * scale

static func early_reward(store_id: int, level: int) -> float:
	var amount := _scaled_value(20.0, 1.1, level, store_id)
	return amount if amount >= 0 and amount <= MAX_MONEY / 2 else -1

static func payout_cost(store_id: int, level: int) -> float:
	return _scaled_value(25.0, 1.15, level, store_id)

static func tool_cost(store_id: int, level: int) -> float:
	return _staged_upgrade_cost(store_id, float(TOOL_PRICE_STAGES[level]), TOOL_PRICE_RUGS) if level >= 0 and level < TOOL_PRICE_STAGES.size() else -1.0

static func _staged_upgrade_cost(store_id: int, stage: float, rugs: float) -> float:
	var starting := 40.0 * scale_for(store_id)
	var ceiling := reward_cap(store_id)
	if starting <= 0.0 or ceiling <= 0.0 or ceiling > MAX_MONEY / rugs: return -1.0
	# Fixed economic milestones stay independent of the current room level or
	# temporary rewarded boosts. Late prices therefore keep pace with the cap.
	var raw := rugs * starting * pow(ceiling / starting, stage)
	if stage >= 1.0: raw = rugs * ceiling
	var price := Money.rounded(raw)
	return price if Money.is_valid(price) and price > 0.0 else -1.0

static func new_branch(store_id: int) -> Dictionary:
	return {
		"payout_level": 0, "tool_level": 0, "hose_level": 0, "squeegee_level": 0,
		"manual_jobs": 0, "final_tool_jobs": 0,
		"room_rules_version": 4, "room_base_early": 20.0 * scale_for(store_id),
		"room_upgrades": {"floor": 0, "plants": 0, "window": 0, "railings": 0, "walls": 0},
		"room_income_origins": {"floor": 0, "plants": 0, "window": 0, "railings": 0, "walls": 0},
		"active_job_id": "", "active_rug_id": "mint_meadow", "job_snapshot": {}, "job_early_reward": 0,
		"job_cleaning_paid": 0.0, "job_cleaning_progress": 0.0,
		"job_ad_boost": false,
		"job_started_with_final_tool": false, "job_final_tool_used": false,
	}
