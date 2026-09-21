extends RefCounted
## Editable progression rules. All prices are incremental and use one wallet.
const MAX_MONEY := 9000000000000000
const STORE_COUNT := 4
const TRAVEL_LEVEL_TARGET := 19
const CAPSTONE_JOBS := 3
const STORE_NAMES := ["Neighborhood", "High Street", "Wash House", "Restoration Studio"]
const TOOL_COSTS := [80, 200, 500, 1000]
const TOOL_NAMES := ["Hand brush", "Wide brush", "Firm brush", "Power brush", "Master brush", "Precision brush", "Dual brush", "Pro brush", "Ultimate brush"]
const TOOL_WIDTHS := [1.0, 1.44, 1.55, 1.65, 1.75, 1.75, 1.75, 1.75, 1.75]
const TOOL_POWERS := [1.0, 1.0, 1.1, 1.25, 1.45, 1.6, 1.8, 2.0, 2.25]
const WET_NAMES := ["Wash kit", "Fresh wash kit", "Deep wash kit", "Power wash kit", "Master wash kit"]
const WET_POWERS := [1.0, 1.2, 1.45, 1.75, 2.1]
const BOT_REWARDS := [10, 20, 40]
const BOT_SECONDS := [120.0, 90.0, 60.0]

static func scale_for(store_id: int) -> int:
	return int(pow(8.0, store_id - 1)) if store_id >= 1 and store_id <= STORE_COUNT else 0

static func store_name(store_id: int) -> String:
	return STORE_NAMES[store_id - 1] if store_id >= 1 and store_id <= STORE_COUNT else "Unknown store"

static func _scaled_value(base: float, growth: float, level: int, store_id: int) -> int:
	if level < 0 or scale_for(store_id) == 0:
		return -1
	var raw := base * pow(growth, level)
	var scale := scale_for(store_id)
	if not is_finite(raw) or raw > float(MAX_MONEY) / float(scale):
		return -1
	var rounded := roundi(raw)
	if rounded > MAX_MONEY / scale:
		return -1
	return rounded * scale

static func early_reward(store_id: int, level: int) -> int:
	var amount := _scaled_value(20.0, 1.1, level, store_id)
	return amount if amount >= 0 and amount <= MAX_MONEY / 2 else -1

static func payout_cost(store_id: int, level: int) -> int:
	return _scaled_value(25.0, 1.15, level, store_id)

static func tool_cost(store_id: int, level: int) -> int:
	return TOOL_COSTS[level] * scale_for(store_id) if level >= 0 and level < TOOL_COSTS.size() else -1

static func bot_cost(store_id: int, tier: int) -> int:
	if tier == -1: return 100 * scale_for(store_id)
	if tier == 0: return 300 * scale_for(store_id)
	if tier == 1: return 900 * scale_for(store_id)
	return -1

static func bot_reward(store_id: int, tier: int) -> int:
	return BOT_REWARDS[tier] * scale_for(store_id) if tier >= 0 and tier < BOT_REWARDS.size() else 0

static func bot_seconds(tier: int) -> float:
	return BOT_SECONDS[tier] if tier >= 0 and tier < BOT_SECONDS.size() else 0.0

static func new_branch(store_id: int) -> Dictionary:
	return {
		"payout_level": 0, "tool_level": 0, "bonzi_tier": -1 if store_id == 1 else 0,
		"bonzi_earned": 0, "manual_jobs": 0, "automated_jobs": 0,
		"routine_remainder": 0.0, "banked_orders": 0, "final_tool_jobs": 0,
		"active_job_id": "", "job_snapshot": {}, "job_early_reward": 0,
		"job_started_with_final_tool": false, "job_final_tool_used": false,
	}
