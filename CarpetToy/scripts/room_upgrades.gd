extends RefCounted
## Five independent ladders contribute additively to each rug's earnings.
## Each store has a bounded curve and real makeovers spread across its ladders.

const Progression := preload("res://scripts/progression.gd")
const LEGACY_IDS := ["floor", "plants", "window", "railings"]
const IDS := ["floor", "plants", "window", "railings", "walls"]
const MAX_VISUAL_LEVEL := 3
const VISUAL_STEP := 5
const MAX_LEVEL := 175
const RULES_VERSION := 4
const LEVEL_GROWTH := 1.6
const MILESTONE_BOOST := 1.5
static var _growth_cache: Dictionary = {}
const ECONOMY := {
	"floor": {"cost": 40.0, "early_gain": 3.0},
	"plants": {"cost": 25.0, "early_gain": 2.0},
	"window": {"cost": 60.0, "early_gain": 4.0},
	"railings": {"cost": 35.0, "early_gain": 2.0},
	"walls": {"cost": 50.0, "early_gain": 3.0},
}
const LEGACY_ECONOMY := {
	"floor": {"early_gain": 3.0, "income_growth": 1.11},
	"plants": {"early_gain": 2.0, "income_growth": 1.10},
	"window": {"early_gain": 4.0, "income_growth": 1.12},
	"railings": {"early_gain": 2.0, "income_growth": 1.10},
}
const DEFINITIONS := {
	"floor": {
		"title": "Workshop floor",
		"description": "A beautiful workspace earns more on every rug.",
		"names": ["Concrete floor", "Maple planks", "Mint checker tile", "Pearl terrazzo"],
		"upgrade_descriptions": ["Warm maple planks replace the concrete.", "Fresh mint tiles brighten the workshop.", "Pearl terrazzo with fine brass inlay."],
	},
	"plants": {
		"title": "Corner garden",
		"description": "Grow a welcoming garden and earn more on every rug.",
		"names": ["Bare pots", "Little sprouts", "Leafy stems", "Coral flowers"],
		"upgrade_descriptions": ["Bring your pots to life with little sprouts.", "Help the sprouts grow into leafy plants.", "Fill the corners with coral blossoms."],
	},
	"window": {
		"title": "Workshop window",
		"description": "Let the light in and earn more on every rug.",
		"names": ["Timber frame", "Painted frame", "Arched trim", "Brass sunroom"],
		"upgrade_descriptions": ["Freshly painted frames bring a little color.", "Add an elegant arched window surround.", "Finish your window with warm brass details."],
	},
	"railings": {
		"title": "Workshop railings",
		"description": "Give the workshop a fine finish and earn more on every rug.",
		"names": ["Timber railings", "Mint slats", "White balusters", "Brass accents"],
		"upgrade_descriptions": ["Replace plain timber with fresh mint slats.", "Give the workshop a classic white balustrade.", "Add polished brass accents to the railings."],
	},
	"walls": {
		"title": "Workshop walls",
		"description": "Create a welcoming room and earn more on every rug.",
		"names": ["Simple plaster", "Mint wainscot", "Ivory stone", "Brass gallery"],
		"upgrade_descriptions": ["Paint the walls and add warm timber panels.", "Give the window and door a fine stone surround.", "Finish the workshop with ivory and brass details."],
	},
}


static func is_known(id: String) -> bool:
	return DEFINITIONS.has(id)


static func levels_for_branch(branch: Dictionary) -> Dictionary:
	var levels := _legacy_levels(branch)
	if int(branch.get("room_rules_version", 0)) >= 2:
		return levels
	for id: String in IDS:
		var old_level := int(levels[id])
		levels[id] = mini(old_level, MAX_VISUAL_LEVEL) * VISUAL_STEP
	return levels


static func _legacy_levels(branch: Dictionary) -> Dictionary:
	if branch.get("room_upgrades") is Dictionary:
		var saved_levels := {}
		for id: String in IDS:
			saved_levels[id] = int(branch.room_upgrades.get(id, 0))
		return saved_levels
	# Old generic earnings purchases become visible improvements, round-robin.
	# Arithmetic keeps even very old, high-level saves quick to migrate.
	var payout_level := maxi(0, int(branch.get("payout_level", 0)))
	var each := int(payout_level / LEGACY_IDS.size())
	var remainder := payout_level % LEGACY_IDS.size()
	var levels := {}
	for index in LEGACY_IDS.size():
		levels[LEGACY_IDS[index]] = each + (1 if index < remainder else 0)
	levels.walls = 0
	return levels


static func migrate_branch(store_id: int, branch: Dictionary) -> void:
	if int(branch.get("room_rules_version", 0)) == RULES_VERSION: return
	var levels := levels_for_branch(branch)
	for id: String in IDS:
		levels[id] = _migrated_level(id, int(levels[id]), store_id)
	branch.room_upgrades = levels
	branch.room_rules_version = RULES_VERSION
	# Keep the wallet and earned appearances, then rebase future carpet quotes
	# onto this store's cap. An old AF quote cannot bypass the first-store ceiling.
	branch.room_base_early = 20.0 * Progression.scale_for(store_id)
	branch.room_income_origins = {}
	for id: String in IDS: branch.room_income_origins[id] = 0
	branch.payout_level = total_levels(levels)
	if not str(branch.get("active_job_id", "")).is_empty():
		branch.job_early_reward = early_reward(store_id, branch)
	else:
		branch.job_early_reward = minf(float(branch.get("job_early_reward", 0.0)), Progression.reward_cap(store_id) / 2.0)


static func _migrated_level(id: String, old_level: int, store_id: int) -> int:
	var milestones := visual_milestones(id, store_id)
	var cap := Progression.room_level_cap(store_id)
	if old_level <= 0 or milestones.is_empty(): return 0
	if old_level >= 120: return cap
	if old_level >= 15:
		return milestones[-1] + roundi(float(old_level - 15) / 105.0 * float(cap - milestones[-1]))
	var tier := mini(int(old_level / VISUAL_STEP), milestones.size() - 1)
	var start := 0 if tier == 0 else milestones[tier - 1]
	return start + roundi(float(old_level % VISUAL_STEP) / float(VISUAL_STEP) * float(milestones[tier] - start))


static func total_levels(levels: Dictionary) -> int:
	var total := 0
	for id: String in IDS: total += int(levels.get(id, 0))
	return total


static func visual_count(id: String) -> int:
	if not is_known(id): return 0
	var definition: Dictionary = DEFINITIONS[id]
	return mini((definition.names as Array).size() - 1, (definition.upgrade_descriptions as Array).size())


static func visual_milestones_for(level_cap: int, authored_count: int) -> Array[int]:
	var milestones: Array[int] = []
	if level_cap <= 0 or authored_count <= 0: return milestones
	var count := mini(level_cap, authored_count)
	var interval := maxi(1, int(level_cap / count))
	# Spread real authored models across the ladder using readable milestones.
	# Fifty levels/five makeovers ->10,20,30,40,50;175/three ->50,100,150.
	var rounding := 10 if interval >= 50 else (5 if interval >= 5 else 1)
	interval = maxi(1, int(interval / rounding) * rounding)
	for tier: int in range(1, count + 1): milestones.append(tier * interval)
	return milestones


static func visual_milestones(id: String, store_id: int = 1) -> Array[int]:
	return visual_milestones_for(Progression.room_level_cap(store_id), visual_count(id))


static func visual_step_for(id: String, store_id: int = 1) -> int:
	var milestones := visual_milestones(id, store_id)
	return milestones[0] if not milestones.is_empty() else 0


static func visual_tier(id: String, level: int, store_id: int = 1) -> int:
	var tier := 0
	for milestone: int in visual_milestones(id, store_id):
		if level < milestone: break
		tier += 1
	return tier


static func next_visual_level(id: String, level: int, store_id: int = 1) -> int:
	for milestone: int in visual_milestones(id, store_id):
		if level < milestone: return milestone
	return -1


static func milestone_start(id: String, level: int, store_id: int = 1) -> int:
	var previous := 0
	for milestone: int in visual_milestones(id, store_id):
		if level < milestone: break
		previous = milestone
	return previous


static func milestone_progress(id: String, level: int, store_id: int = 1) -> float:
	var next := next_visual_level(id, level, store_id)
	if next < 0: return 1.0
	var previous := milestone_start(id, level, store_id)
	return clampf(float(level - previous) / float(next - previous), 0.0, 1.0)


static func cost(store_id: int, id: String, level: int) -> float:
	if not is_known(id) or level < 0 or level >= Progression.room_level_cap(store_id): return -1
	var rule: Dictionary = ECONOMY[id]
	var raw := float(rule.cost) * pow(growth_for(store_id), level)
	return _scaled_money(raw, store_id, Progression.MAX_MONEY)


static func early_contribution(store_id: int, id: String, level: int, origin: int = 0) -> float:
	if not is_known(id) or origin < 0 or level < origin or level > Progression.room_level_cap(store_id): return -1
	return _cumulative_gain(store_id, id, level) - _cumulative_gain(store_id, id, origin)


static func early_gain(store_id: int, id: String, purchased_level: int) -> float:
	if not is_known(id) or purchased_level < 1 or purchased_level > Progression.room_level_cap(store_id): return -1.0
	return _cumulative_gain(store_id, id, purchased_level) - _cumulative_gain(store_id, id, purchased_level - 1)


static func growth_for(store_id: int) -> float:
	if _growth_cache.has(store_id): return float(_growth_cache[store_id])
	var cap := Progression.room_level_cap(store_id)
	var scale := Progression.scale_for(store_id)
	if cap <= 0 or scale <= 0: return 1.0
	var target := (Progression.reward_cap(store_id) / (2.0 * scale) - 20.0) / 14.0
	var low := 1.0
	var high := 2.0
	for _iteration in 64:
		var middle := (low + high) / 2.0
		var cumulative := (pow(middle, cap) - 1.0) / (middle - 1.0)
		if cumulative < target: low = middle
		else: high = middle
	_growth_cache[store_id] = (low + high) / 2.0
	return float(_growth_cache[store_id])


static func _gain_budget(store_id: int, id: String) -> float:
	var available := Progression.reward_cap(store_id) / 2.0 - 20.0 * Progression.scale_for(store_id)
	if id != IDS[-1]: return roundf(available * float(ECONOMY[id].early_gain) / 14.0)
	# Assign rounding residue to the final feature so all five hit the exact cap.
	for other: String in IDS:
		if other != id: available -= _gain_budget(store_id, other)
	return roundf(available)


static func _cumulative_gain(store_id: int, id: String, level: int) -> float:
	if level == 0: return 0.0
	if level == Progression.room_level_cap(store_id): return _gain_budget(store_id, id)
	var growth := growth_for(store_id)
	var raw := float(ECONOMY[id].early_gain) * (pow(growth, level) - 1.0) / (growth - 1.0)
	return minf(_gain_budget(store_id, id), _scaled_money(raw, store_id, Progression.MAX_MONEY / 2.0))


static func _scaled_money(raw: float, store_id: int, maximum: float) -> float:
	var scale := Progression.scale_for(store_id)
	if scale <= 0 or not is_finite(raw) or raw < 0.0 or raw > float(maximum) / float(scale): return -1
	var rounded := roundf(raw)
	return rounded * scale if rounded <= maximum / scale else -1


static func early_reward(store_id: int, branch: Dictionary) -> float:
	if int(branch.get("room_rules_version", 0)) != RULES_VERSION:
		return _previous_early_reward(store_id, branch)
	var total := float(branch.room_base_early)
	var levels: Dictionary = branch.room_upgrades
	var origins: Dictionary = branch.room_income_origins
	var all_maxed := true
	for id: String in IDS:
		all_maxed = all_maxed and int(levels[id]) == Progression.room_level_cap(store_id)
		var contribution := early_contribution(store_id, id, int(levels[id]), int(origins[id]))
		if contribution < 0 or contribution > Progression.MAX_MONEY / 2 - total: return -1
		total += contribution
	if all_maxed: return Progression.reward_cap(store_id) / 2.0
	return minf(total, Progression.reward_cap(store_id) / 2.0) if total > 0 and total <= Progression.MAX_MONEY / 2 else -1


static func next_id(levels: Dictionary) -> String:
	var selected: String = IDS[0]
	for id: String in IDS:
		if int(levels.get(id, 0)) < int(levels.get(selected, 0)):
			selected = id
	return selected


static func tier_name(id: String, level: int, store_id: int = 1) -> String:
	if not is_known(id): return ""
	var names: Array = DEFINITIONS[id].names
	return str(names[visual_tier(id, level, store_id)])


static func next_description(id: String, level: int, store_id: int = 1) -> String:
	if not is_known(id): return ""
	if level >= Progression.room_level_cap(store_id):
		return "This feature is fully upgraded."
	var next := next_visual_level(id, level, store_id)
	if next < 0:
		return "All room makeovers are complete. Remaining upgrades increase carpet earnings."
	var tier := visual_tier(id, level, store_id)
	return "%s At level %d." % [str(DEFINITIONS[id].upgrade_descriptions[tier]), next]


static func valid_saved_levels(value: Variant, payout_level: int, rules_version: int = RULES_VERSION) -> bool:
	var expected: Array = IDS if rules_version >= 3 else LEGACY_IDS
	if not value is Dictionary or value.size() != expected.size(): return false
	var total := 0
	for id: String in expected:
		var level: Variant = value.get(id)
		if not (level is float or level is int) or not is_finite(float(level)): return false
		if float(level) != floorf(float(level)) or float(level) < 0.0 or float(level) > float(payout_level): return false
		total += int(level)
	return total == payout_level


static func _previous_early_reward(store_id: int, branch: Dictionary) -> float:
	var version := int(branch.get("room_rules_version", 0))
	if version not in [2, 3]:
		return Progression.early_reward(store_id, int(branch.get("payout_level", 0)))
	var total := float(branch.get("room_base_early", 0.0))
	var scale := pow(8.0, store_id - 1)
	var ids: Array = IDS if version == 3 else LEGACY_IDS
	for id: String in ids:
		if version == 3:
			for level in range(int(branch.room_income_origins[id]) + 1, int(branch.room_upgrades[id]) + 1):
				var gain := roundf(float(ECONOMY[id].early_gain) * pow(LEVEL_GROWTH, level - 1) * pow(MILESTONE_BOOST, int(level / VISUAL_STEP))) * scale
				if not is_finite(gain) or gain > Progression.MAX_MONEY / 2.0 - total: return -1.0
				total += gain
			continue
		var rule: Dictionary = LEGACY_ECONOMY[id]
		var origin := int(branch.room_income_origins[id])
		var count := int(branch.room_upgrades[id]) - origin
		var growth := float(rule.income_growth)
		var raw := float(rule.early_gain) * pow(growth, origin) * (pow(growth, count) - 1.0) / (growth - 1.0)
		var gain := roundf(raw) * scale
		if gain < 0.0 or gain > Progression.MAX_MONEY / 2.0 - total: return -1.0
		total += gain
	return total
