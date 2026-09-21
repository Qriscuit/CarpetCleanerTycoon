extends Node
## The Neighborhood Shop ledger. Each reward/build is committed before it is exposed.

signal changed
signal ad_reward_granted(amount: int)

const Progression := preload("res://scripts/progression.gd")
const RewardAds := preload("res://scripts/reward_ad_service.gd")
const SAVE_VERSION := 2
const SAVE_PATH := "user://neighborhood_shop_v1.json"
const OFFLINE_CAP_SECONDS := 8.0 * 60.0 * 60.0
const MANUAL_REWARD := 20
const MANUAL_COMPLETION_THRESHOLD := 0.85
const PERFECT_REWARD := 40
const PERFECT_COMPLETION_THRESHOLD := 0.99
const ROUTINE_REWARD := 10
const COSTS := {"hand_brush": 0, "wide_brush": 80, "bonzi": 100, "bonzi_mk2": 120, "intake": 100}
const GATES := {"hand_brush": 0, "wide_brush": 8, "bonzi": 3, "bonzi_mk2": 10, "intake": 10}

var cash: int = 0
var equipped_brush: String = "hand_brush"
var manual_jobs: int = 0
var automated_jobs: int = 0
var routine_remainder: float = 0.0
var active_job_id: String = ""
var job_snapshot: Dictionary = {}
var return_reward: int = 0
var return_seconds: float = 0.0
# A scene-entry choice: free rug tests never become paid commissions on reload.
var contract_mode: bool = false
var last_error: String = ""
var active_store := 1
var stores: Dictionary = {"1": Progression.new_branch(1)}
var completed_rewards: Dictionary = {}
var ad_receipts: Dictionary = {}
var _latest_reward_job := ""
var reward_ads := RewardAds.new()
var _verified_ads_waiting: Dictionary = {}

var _owned: Dictionary = {"hand_brush": true}
var _blueprints: Dictionary = {"hand_brush": true}
var _job_serial: int = 0
var _saved_wall: float = 0.0
var _last_ticks: int = 0
var _checkpoint_ticks: int = 0
var _save_path: String = ""
var _save_enabled: bool = true
var _application_paused: bool = false
var _pause_wall: float = 0.0
var _pause_ticks: int = 0
var _pending_away_seconds: float = 0.0
# These overrides are ignored unless the process explicitly opts into isolated tests.
var _test_unix_time: float = -1.0
var _test_ticks_msec: int = -1


func _ready() -> void:
	reward_ads.verified_reward.connect(_on_verified_reward_ad)
	if _save_path.is_empty():
		_save_path = "res://.godot/shop_test_%d.json" % OS.get_process_id() if _is_test_mode() else SAVE_PATH
	_last_ticks = _now_ticks()
	_checkpoint_ticks = _last_ticks
	_saved_wall = _now_unix()
	if FileAccess.file_exists(_save_path):
		_load_state()


func _process(_delta: float) -> void:
	if not _save_enabled or _application_paused:
		return
	# Only automation scalars need rollback on a live tick; snapshots are large.
	var production_before := _capture_production()
	var old_ticks := _last_ticks
	var before_away := _capture_state() if _pending_away_seconds > 0.0 else {}
	var deliveries := _settle_elapsed()
	# Persist partial progress periodically and whole deliveries immediately.
	if deliveries > 0 or not before_away.is_empty() or _now_ticks() - _checkpoint_ticks >= 5000:
		if not _commit():
			_restore_production(production_before)
			_last_ticks = old_ticks
			if not before_away.is_empty(): _restore_state(before_away)
			return
	if deliveries > 0 or not before_away.is_empty():
		changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and not _application_paused:
		save_state()
		_pause_wall = maxf(_saved_wall, _now_unix())
		_pause_ticks = _now_ticks()
		_application_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED and _application_paused:
		_resume_application()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_state()


func _resume_application() -> void:
	# The live monotonic clock can stop during device sleep. Use the same bounded
	# wall-clock absence as a cold launch, then restart live accounting at now.
	_pending_away_seconds += clampf(_now_unix() - _pause_wall, 0.0, OFFLINE_CAP_SECONDS)
	var unsettled_live_ticks := maxi(0, _pause_ticks - _last_ticks)
	_last_ticks = _now_ticks() - unsettled_live_ticks
	_application_paused = false
	save_state() # Failed writes retain the pending absence for a single retry.


func owns(id: String) -> bool:
	return bool(_owned.get(id, false))


func blueprint_known(id: String) -> bool:
	return bool(_blueprints.get(id, false))


func build_cost(id: String) -> int:
	if id == "wide_brush": return Progression.tool_cost(active_store, int(_branch().tool_level))
	if id == "bonzi": return 100 * Progression.scale_for(active_store)
	if id == "bonzi_mk2": return 300 * Progression.scale_for(active_store)
	if id == "intake": return 900 * Progression.scale_for(active_store)
	return int(COSTS.get(id, -1))


func unlock_requirement(id: String) -> int:
	return int(GATES.get(id, -1))


func equip_brush(id: String) -> bool:
	if id not in ["hand_brush", "wide_brush"] or not owns(id):
		return false
	if equipped_brush == id:
		return true
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	equipped_brush = id
	return _finish_transaction(before, old_ticks)


func build(id: String) -> bool:
	# Compatibility entry points use the same prices and atomic progression as
	# the new menus. Old buttons cannot buy a discounted duplicate upgrade.
	if id == "wide_brush":
		return buy_tool_upgrade() if not owns(id) else false
	if id == "bonzi":
		return buy_bonzi_upgrade() if int(_branch().bonzi_tier) == -1 else false
	if id == "bonzi_mk2":
		return buy_bonzi_upgrade() if int(_branch().bonzi_tier) == 0 else false
	if id == "intake":
		return buy_bonzi_upgrade() if int(_branch().bonzi_tier) == 1 else false
	return false


func output_per_hour() -> float:
	var seconds := Progression.bot_seconds(int(_branch().bonzi_tier))
	return 3600.0 / seconds if seconds > 0.0 else 0.0


func demand_per_hour() -> float:
	return 60.0 if owns("intake") else 40.0


func capacity_per_hour() -> float:
	return output_per_hour()


func bottleneck() -> String:
	if int(_branch().bonzi_tier) < 0:
		return "Build Bonzi to start routine orders"
	return "Bonzi cycle"


func seconds_to_delivery() -> float:
	var rate := output_per_hour()
	if rate <= 0.0:
		return 0.0
	var pending := maxf(0.0, float(_now_ticks() - _last_ticks) / 1000.0) * rate / 3600.0
	return maxf(0.0, (1.0 - routine_remainder - pending) * 3600.0 / rate)


func start_job() -> String:
	if not active_job_id.is_empty():
		return active_job_id
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	_job_serial += 1
	active_job_id = "neighborhood-%d" % _job_serial
	job_snapshot = {}
	_prepare_job()
	if not _finish_transaction(before, old_ticks):
		return ""
	return active_job_id


func save_job_snapshot(snapshot: Dictionary) -> bool:
	if active_job_id.is_empty():
		return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	job_snapshot = snapshot.duplicate(true)
	return _finish_transaction(before, old_ticks)


func complete_job(job_id: String) -> bool:
	if job_id.is_empty() or job_id != active_job_id:
		return false
	var reward := reward_for_current_job(job_snapshot)
	if reward == 0:
		return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	cash += reward
	manual_jobs += 1
	active_job_id = ""
	_record_completed_job(job_id, reward)
	job_snapshot = {}
	_refresh_blueprints()
	return _finish_transaction(before, old_ticks)


func complete_and_start_next_job(job_id: String, completed_snapshot: Dictionary) -> String:
	# Rewarding the finished rug and reserving its replacement are one ledger
	# transaction. A repeated tap still carries the old id and is rejected, while
	# a restart during the takeaway animation opens the already-saved next rug.
	if job_id.is_empty() or job_id != active_job_id:
		return ""
	var reward := reward_for_current_job(completed_snapshot)
	if reward == 0:
		return ""
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	cash += reward
	manual_jobs += 1
	_job_serial += 1
	_record_completed_job(job_id, reward)
	active_job_id = "neighborhood-%d" % _job_serial
	job_snapshot = {}
	_prepare_job()
	_refresh_blueprints()
	if not _finish_transaction(before, old_ticks):
		return ""
	return active_job_id


func save_state() -> bool:
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	return _finish_transaction(before, old_ticks)


func acknowledge_return() -> bool:
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	return_reward = 0
	return_seconds = 0.0
	return _finish_transaction(before, old_ticks)


func reset_progress() -> bool:
	var before := _capture_state()
	var old_ticks := _last_ticks
	var old_pending := _pending_away_seconds
	var old_enabled := _save_enabled
	_restore_state({
		"cash": 0, "equipped_brush": "hand_brush", "manual_jobs": 0,
		"automated_jobs": 0, "routine_remainder": 0.0,
		"owned": {"hand_brush": true}, "blueprints": {"hand_brush": true},
		"job_serial": 0, "active_job_id": "", "job_snapshot": {},
		"return_reward": 0, "return_seconds": 0.0, "saved_wall": _now_unix(),
		"stores": {"1": Progression.new_branch(1)}, "active_store": 1,
		"completed_rewards": {}, "ad_receipts": {}, "latest_reward_job": "",
	})
	_last_ticks = _now_ticks()
	_pending_away_seconds = 0.0
	_save_enabled = true
	if not _commit():
		_restore_state(before)
		_last_ticks = old_ticks
		_pending_away_seconds = old_pending
		_save_enabled = old_enabled
		return false
	contract_mode = false
	reward_ads.cancel_pending()
	_verified_ads_waiting.clear()
	changed.emit()
	return true


static func manual_reward_for(snapshot: Dictionary) -> int:
	var debris: Variant = snapshot.get("unique_clearance")
	var surface: Variant = snapshot.get("surface_clearance")
	if not _valid_clearance(debris) or not _valid_clearance(surface):
		return 0
	# The dirtier layer determines completion, regardless of the finish trigger.
	return PERFECT_REWARD if minf(float(debris), float(surface)) >= PERFECT_COMPLETION_THRESHOLD else MANUAL_REWARD


static func _valid_clearance(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= MANUAL_COMPLETION_THRESHOLD and float(value) <= 1.0


func _refresh_blueprints() -> void:
	for id: String in GATES:
		if manual_jobs < int(GATES[id]):
			continue
		if id in ["bonzi_mk2", "intake"] and not owns("bonzi"):
			continue
		_blueprints[id] = true


func _settle_elapsed() -> int:
	# A late save while paused may retry older earnings, but cannot consume sleep
	# as live time. The new absence is settled only by _resume_application.
	var now := _pause_ticks if _application_paused else _now_ticks()
	var seconds := maxf(0.0, float(now - _last_ticks) / 1000.0)
	_last_ticks = now
	_sync_active_branch()
	var cash_before := cash
	var away_delivered := _produce(_pending_away_seconds)
	if _pending_away_seconds > 0.0:
		return_reward += cash - cash_before
		return_seconds += _pending_away_seconds
	return away_delivered + _produce(seconds)


func _produce(seconds: float) -> int:
	var delivered := 0
	for key: String in stores:
		var branch: Dictionary = stores[key]
		var tier: int = int(branch.bonzi_tier)
		var cycle := Progression.bot_seconds(tier)
		if cycle <= 0.0: continue
		var orders := float(branch.routine_remainder) + maxf(seconds, 0.0) / cycle
		var whole := int(floor(orders + 0.000000001))
		branch.routine_remainder = maxf(0.0, orders - float(whole))
		var due: int = whole + int(branch.get("banked_orders", 0))
		var reward := Progression.bot_reward(int(key), tier)
		var payable := mini(due, int((Progression.MAX_MONEY - cash) / reward))
		branch.banked_orders = due - payable
		if due > payable: last_error = "Wallet limit reached; Bonzi deliveries wait until coins are spent."
		var income := payable * reward
		cash += income
		branch.bonzi_earned = mini(Progression.MAX_MONEY, int(branch.bonzi_earned) + income)
		branch.automated_jobs = mini(Progression.MAX_MONEY, int(branch.automated_jobs) + payable)
		delivered += payable
		automated_jobs = mini(Progression.MAX_MONEY, automated_jobs + payable)
	routine_remainder = float(_branch().routine_remainder)
	return delivered


func _finish_transaction(before: Dictionary, old_ticks: int) -> bool:
	if not _commit():
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	changed.emit()
	return true


func _capture_state() -> Dictionary:
	_sync_active_branch()
	return {
		"version": SAVE_VERSION,
		"cash": cash,
		"equipped_brush": equipped_brush,
		"manual_jobs": manual_jobs,
		"automated_jobs": automated_jobs,
		"routine_remainder": routine_remainder,
		"owned": _owned.duplicate(true),
		"blueprints": _blueprints.duplicate(true),
		"job_serial": _job_serial,
		"active_job_id": active_job_id,
		"job_snapshot": job_snapshot.duplicate(true),
		"return_reward": return_reward,
		"return_seconds": return_seconds,
		"saved_wall": _saved_wall,
		"active_store": active_store, "stores": stores.duplicate(true),
		"completed_rewards": completed_rewards.duplicate(true),
		"ad_receipts": ad_receipts.duplicate(true), "latest_reward_job": _latest_reward_job,
	}


func _restore_state(data: Dictionary) -> void:
	cash = int(data["cash"])
	manual_jobs = int(data["manual_jobs"])
	automated_jobs = int(data["automated_jobs"])
	routine_remainder = float(data["routine_remainder"])
	_owned = data["owned"].duplicate(true)
	_blueprints = data["blueprints"].duplicate(true)
	# Older version-1 saves always used the wide brush once owned. Preserve that
	# choice on migration, and recover an invalid saved selection to the free brush.
	var selection: Variant = data.get("equipped_brush", "wide_brush" if owns("wide_brush") else "hand_brush")
	equipped_brush = selection if selection is String and selection in ["hand_brush", "wide_brush"] and owns(selection) else "hand_brush"
	_job_serial = int(data["job_serial"])
	active_job_id = str(data["active_job_id"])
	job_snapshot = data["job_snapshot"].duplicate(true)
	return_reward = int(data["return_reward"])
	return_seconds = float(data["return_seconds"])
	_saved_wall = float(data["saved_wall"])
	active_store = int(data.get("active_store", 1))
	if data.has("stores"):
		stores = data.stores.duplicate(true)
	else:
		_migrate_legacy_branch()
	completed_rewards = data.get("completed_rewards", {}).duplicate(true)
	ad_receipts = data.get("ad_receipts", {}).duplicate(true)
	_latest_reward_job = str(data.get("latest_reward_job", ""))
	_load_active_branch()


func _commit() -> bool:
	if not _save_enabled:
		return false
	if not _bounded_integer(cash) or not _bounded_integer(manual_jobs) or not _bounded_integer(automated_jobs) or not _bounded_integer(_job_serial) or not _bounded_integer(return_reward):
		last_error = "This transaction exceeds the supported wallet range."
		return false
	var data := _capture_state()
	# Retain the wall-clock high water mark if the device clock moves backward.
	data["saved_wall"] = maxf(_saved_wall, _pause_wall if _application_paused else _now_unix())
	var temp_path := _save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "Could not save shop progress (%s)." % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Could not write shop progress (%s)." % error_string(write_error)
		return false
	# One rename replaces the old ledger only after the complete next ledger is flushed.
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(_save_path))
	if rename_error != OK:
		last_error = "Could not commit shop progress (%s)." % error_string(rename_error)
		return false
	_saved_wall = float(data["saved_wall"])
	_checkpoint_ticks = _now_ticks()
	_pending_away_seconds = 0.0
	last_error = ""
	return true


func _load_state() -> void:
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		_reject_save("Shop save could not be read.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary) or not _valid_save(parsed):
		_reject_save("Shop save is unreadable or from an unsupported version; the original file was preserved.")
		return
	_restore_state(parsed)
	var before := _capture_state()
	var elapsed := clampf(_now_unix() - _saved_wall, 0.0, OFFLINE_CAP_SECONDS)
	if elapsed > 0.0:
		var cash_before := cash
		if int(parsed.version) == 1:
			_produce_legacy_absence(parsed, elapsed)
		else:
			_produce(elapsed)
		return_reward += cash - cash_before
		return_seconds += elapsed
	# Save the credited return immediately, so reopening cannot collect it again.
	if not _commit():
		_restore_state(before)
		_save_enabled = false


func _valid_save(data: Dictionary) -> bool:
	if data.get("version") != 1 and data.get("version") != SAVE_VERSION:
		return false
	for key: String in ["cash", "manual_jobs", "automated_jobs", "job_serial", "return_reward"]:
		var value: Variant = data.get(key)
		if not _bounded_integer(value):
			return false
	for key: String in ["routine_remainder", "return_seconds", "saved_wall"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	if float(data["routine_remainder"]) >= 1.0:
		return false
	for key: String in ["owned", "blueprints", "job_snapshot"]:
		if not (data.get(key) is Dictionary):
			return false
	for key: String in ["owned", "blueprints"]:
		for id: Variant in data[key]:
			if not COSTS.has(id) or not (data[key][id] is bool):
				return false
	if data["owned"].get("hand_brush") != true or data["blueprints"].get("hand_brush") != true:
		return false
	if not (data.get("active_job_id") is String):
		return false
	if int(data.version) == SAVE_VERSION and not _valid_progression_save(data):
		return false
	return true


func _reject_save(message: String) -> void:
	_save_enabled = false
	last_error = message
	push_warning(message)


func _is_test_mode() -> bool:
	return "--shop-test" in OS.get_cmdline_user_args()


func _now_unix() -> float:
	if _is_test_mode() and _test_unix_time >= 0.0:
		return _test_unix_time
	return Time.get_unix_time_from_system()


func _now_ticks() -> int:
	if _is_test_mode() and _test_ticks_msec >= 0:
		return _test_ticks_msec
	return Time.get_ticks_msec()


func _branch() -> Dictionary:
	return stores[str(active_store)]


func _sync_active_branch() -> void:
	if not stores.has(str(active_store)): return
	var branch := _branch()
	branch.active_job_id = active_job_id
	branch.job_snapshot = job_snapshot
	branch.routine_remainder = routine_remainder


func _load_active_branch() -> void:
	var branch := _branch()
	active_job_id = str(branch.active_job_id)
	job_snapshot = branch.job_snapshot.duplicate(true)
	routine_remainder = float(branch.routine_remainder)


func _prepare_job() -> void:
	var branch := _branch()
	branch.job_early_reward = Progression.early_reward(active_store, int(branch.payout_level))
	branch.job_started_with_final_tool = int(branch.tool_level) == 4
	branch.job_final_tool_used = false


func note_current_tool_used() -> void:
	# Saved with the next snapshot/completion. A purchase midway through an
	# already-started rug cannot retroactively count toward the capstone gate.
	if not active_job_id.is_empty() and bool(_branch().job_started_with_final_tool):
		_branch().job_final_tool_used = true


func _record_completed_job(job_id: String, reward: int) -> void:
	var branch := _branch()
	branch.manual_jobs = int(branch.manual_jobs) + 1
	if bool(branch.job_started_with_final_tool) and bool(branch.job_final_tool_used):
		branch.final_tool_jobs = mini(Progression.CAPSTONE_JOBS, int(branch.final_tool_jobs) + 1)
	completed_rewards[job_id] = {"amount": reward, "store_id": active_store, "ad_claimed": false}
	_latest_reward_job = job_id


func reward_for_current_job(snapshot: Dictionary) -> int:
	if active_job_id.is_empty(): return 0
	var fraction := _job_clearance(snapshot)
	if fraction < MANUAL_COMPLETION_THRESHOLD: return 0
	var quote: int = int(_branch().job_early_reward)
	if quote <= 0 or quote > Progression.MAX_MONEY / 2: return 0
	return quote * 2 if fraction >= PERFECT_COMPLETION_THRESHOLD else quote


func _job_clearance(snapshot: Dictionary) -> float:
	for key: String in ["unique_clearance", "surface_clearance"]:
		if not _unit_fraction(snapshot.get(key)): return -1.0
	var dry := minf(float(snapshot.unique_clearance), float(snapshot.surface_clearance))
	if active_store < 3: return dry
	if snapshot.get("wet_recipe") != true: return -1.0
	for key: String in ["water_clearance", "extraction_clearance"]:
		if not _unit_fraction(snapshot.get(key)): return -1.0
	var water := float(snapshot.water_clearance)
	var extraction := float(snapshot.extraction_clearance)
	# Wet work follows dry -> wash -> extract. Reject fabricated later-stage
	# progress and recompute the meter rather than trusting an overall field.
	if water > 0.0 and dry < PERFECT_COMPLETION_THRESHOLD: return -1.0
	if extraction > 0.0 and water < PERFECT_COMPLETION_THRESHOLD: return -1.0
	return (dry + water + extraction) / 3.0


static func _unit_fraction(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0


func _highest_dry_tier() -> int:
	var tier := 0
	for key: String in stores:
		var store_id := int(key)
		if store_id <= 2:
			tier = maxi(tier, (store_id - 1) * 4 + int(stores[key].tool_level))
	return mini(tier, 8)


func progression_view() -> Dictionary:
	var branch := _branch()
	var scale := Progression.scale_for(active_store)
	var level := int(branch.payout_level)
	var local_tool := int(branch.tool_level)
	var tier := _highest_dry_tier()
	var next_tier := maxi(tier, mini(8, (active_store - 1) * 4 + mini(local_tool + 1, 4))) if active_store <= 2 else tier
	var early := Progression.early_reward(active_store, level)
	var next_early := Progression.early_reward(active_store, level + 1)
	var payout_price := Progression.payout_cost(active_store, level) if next_early > 0 else -1
	var tool_price := Progression.tool_cost(active_store, local_tool)
	var bot_tier := int(branch.bonzi_tier)
	var bot_price := Progression.bot_cost(active_store, bot_tier)
	var wet_level := local_tool if active_store >= 3 else 0
	var effective_wet := 1.0
	for key: String in stores:
		if int(key) >= 3:
			var stage := int(stores[key].tool_level)
			var stage_power: float = Progression.WET_POWERS[stage] * (2.1 if int(key) == 4 else 1.0)
			effective_wet = maxf(effective_wet, stage_power)
	var owned: Array[int] = []
	for key: String in stores: owned.append(int(key))
	owned.sort()
	var has_next := active_store < Progression.STORE_COUNT
	var target := 100 * scale
	var travel := 2000 * scale
	var gate := int(branch.bonzi_earned) >= target and local_tool == 4 and int(branch.final_tool_jobs) >= Progression.CAPSTONE_JOBS
	var next_name: String = "Maxed" if local_tool == 4 else (Progression.WET_NAMES[local_tool + 1] if active_store >= 3 else Progression.TOOL_NAMES[(active_store - 1) * 4 + local_tool + 1])
	return {
		"store_id": active_store, "store_name": Progression.store_name(active_store), "owned_store_ids": owned,
		"payout_level": level, "early_reward": early, "full_reward": early * 2,
		"next_early": next_early, "next_full": next_early * 2 if next_early > 0 else -1,
		"payout_cost": payout_price, "can_upgrade_payout": payout_price >= 0 and cash >= payout_price,
		"tool_level": local_tool, "global_tool_tier": tier,
		"next_global_tool_tier": next_tier,
		"tool_name": Progression.WET_NAMES[local_tool] if active_store >= 3 else Progression.TOOL_NAMES[tier],
		"next_tool_name": next_name, "tool_cost": tool_price,
		"tool_width": Progression.TOOL_WIDTHS[tier], "tool_power": Progression.TOOL_POWERS[tier],
		"next_tool_width": Progression.TOOL_WIDTHS[next_tier], "next_tool_power": Progression.TOOL_POWERS[next_tier],
		"can_upgrade_tool": tool_price >= 0 and cash >= tool_price,
		"wet_tool_level": wet_level, "wet_power": effective_wet,
		"next_wet_power": maxf(effective_wet, float(Progression.WET_POWERS[mini(local_tool + 1, 4)]) * (2.1 if active_store == 4 else 1.0)) if active_store >= 3 else effective_wet,
		"bonzi_tier": bot_tier, "bonzi_reward": Progression.bot_reward(active_store, bot_tier),
		"bonzi_seconds": Progression.bot_seconds(bot_tier), "bonzi_cost": bot_price,
		"bonzi_earned": int(branch.bonzi_earned), "bonzi_target": target,
		"can_upgrade_bonzi": bot_price >= 0 and cash >= bot_price and (bot_tier >= 0 or int(branch.manual_jobs) >= 3),
		"local_jobs": int(branch.manual_jobs), "final_tool_jobs": int(branch.final_tool_jobs), "final_tool_target": Progression.CAPSTONE_JOBS,
		"travel_cost": travel, "can_travel": has_next and not stores.has(str(active_store + 1)) and gate and cash >= travel,
		"has_next_store": has_next, "travel_ready": gate, "next_store_name": Progression.store_name(active_store + 1),
		"payout_level_target": Progression.TRAVEL_LEVEL_TARGET,
	}


func buy_payout_upgrade() -> bool:
	return _buy_progression("payout")


func buy_tool_upgrade() -> bool:
	return _buy_progression("tool")


func buy_bonzi_upgrade() -> bool:
	return _buy_progression("bonzi")


func _buy_progression(kind: String) -> bool:
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	var view := progression_view()
	var allowed: bool = bool(view.get("can_upgrade_" + kind, false))
	var price: int = int(view.get(kind + "_cost", -1))
	if not allowed or price < 0:
		_restore_state(before)
		_last_ticks = old_ticks
		last_error = "Upgrade unavailable or not enough coins."
		return false
	cash -= price
	var branch := _branch()
	if kind == "payout":
		branch.payout_level = int(branch.payout_level) + 1
		# The visible rug is always present. Buying its earnings upgrade rebases
		# only the unpaid quote, without changing dirt or the job identity.
		if not active_job_id.is_empty(): branch.job_early_reward = int(view.next_early)
	elif kind == "tool":
		branch.tool_level = int(branch.tool_level) + 1
		if active_store <= 2:
			_owned.wide_brush = true
			equipped_brush = "wide_brush"
	else:
		branch.bonzi_tier = int(branch.bonzi_tier) + 1
		if active_store == 1:
			_owned.bonzi = true
			if int(branch.bonzi_tier) >= 1: _owned.bonzi_mk2 = true
			if int(branch.bonzi_tier) >= 2: _owned.intake = true
	_refresh_blueprints()
	return _finish_transaction(before, old_ticks)


func open_next_store() -> bool:
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	var view := progression_view()
	if not bool(view.can_travel):
		_restore_state(before)
		_last_ticks = old_ticks
		last_error = "Complete this store's travel goals and save the opening price."
		return false
	cash -= int(view.travel_cost)
	_sync_active_branch()
	active_store += 1
	stores[str(active_store)] = Progression.new_branch(active_store)
	_load_active_branch()
	return _finish_transaction(before, old_ticks)


func select_store(store_id: int) -> bool:
	if not stores.has(str(store_id)): return false
	if store_id == active_store: return true
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	_sync_active_branch()
	active_store = store_id
	_load_active_branch()
	return _finish_transaction(before, old_ticks)


func _migrate_legacy_branch() -> void:
	active_store = 1
	var branch := Progression.new_branch(1)
	branch.tool_level = 1 if owns("wide_brush") else 0
	branch.bonzi_tier = 1 if owns("bonzi_mk2") or (owns("bonzi") and owns("intake")) else (0 if owns("bonzi") else -1)
	branch.manual_jobs = manual_jobs
	branch.automated_jobs = automated_jobs
	branch.bonzi_earned = mini(Progression.MAX_MONEY, automated_jobs * ROUTINE_REWARD)
	branch.routine_remainder = routine_remainder
	branch.active_job_id = active_job_id
	branch.job_snapshot = job_snapshot.duplicate(true)
	branch.job_early_reward = MANUAL_REWARD if not active_job_id.is_empty() else 0
	stores = {"1": branch}


func _capture_production() -> Dictionary:
	var result := {"cash": cash, "automated_jobs": automated_jobs, "branches": {}}
	for key: String in stores:
		var branch: Dictionary = stores[key]
		result.branches[key] = [branch.routine_remainder, branch.automated_jobs, branch.bonzi_earned, branch.banked_orders]
	return result


func _restore_production(before: Dictionary) -> void:
	cash = int(before.cash)
	automated_jobs = int(before.automated_jobs)
	for key: String in before.branches:
		var values: Array = before.branches[key]
		var branch: Dictionary = stores[key]
		branch.routine_remainder = values[0]
		branch.automated_jobs = values[1]
		branch.bonzi_earned = values[2]
		branch.banked_orders = values[3]
	routine_remainder = float(_branch().routine_remainder)


func _can_credit(amount: int) -> bool:
	if amount <= 0 or amount > Progression.MAX_MONEY - cash:
		last_error = "Reward exceeds the supported wallet range."
		return false
	return true


func reward_offer() -> Dictionary:
	var offer: Dictionary = completed_rewards.get(_latest_reward_job, {})
	return {"job_id": _latest_reward_job, "amount": int(offer.get("amount", 0)), "available": not offer.is_empty() and not bool(offer.get("ad_claimed", false)) and reward_ads.is_rewarded_ad_available()}


func reward_ad_available() -> bool:
	return bool(reward_offer().available)


func register_reward_ad_provider(provider: Object) -> bool:
	if not reward_ads.configure(provider): return false
	changed.emit()
	return true


func request_reward_ad(job_id: String = "") -> bool:
	var id := _latest_reward_job if job_id.is_empty() else job_id
	if not completed_rewards.has(id) or bool(completed_rewards[id].ad_claimed): return false
	if _verified_ads_waiting.has(id):
		_on_verified_reward_ad(id, str(_verified_ads_waiting[id]))
		return bool(completed_rewards[id].ad_claimed)
	return reward_ads.request_reward(id)


func _on_verified_reward_ad(job_id: String, receipt_id: String) -> void:
	if not completed_rewards.has(job_id) or bool(completed_rewards[job_id].ad_claimed) or ad_receipts.has(receipt_id): return
	_verified_ads_waiting[job_id] = receipt_id
	var amount: int = int(completed_rewards[job_id].amount)
	if not _can_credit(amount): return
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	cash += amount
	completed_rewards[job_id].ad_claimed = true
	ad_receipts[receipt_id] = job_id
	if not _commit():
		_restore_state(before)
		_last_ticks = old_ticks
		return
	_verified_ads_waiting.erase(job_id)
	# The durable balance is available now. Let the HUD reserve its cosmetic
	# coin count-up before the general balance notification synchronizes it.
	ad_reward_granted.emit(amount)
	changed.emit()


static func _bounded_integer(value: Variant, minimum: int = 0, maximum: int = Progression.MAX_MONEY) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum


func _valid_progression_save(data: Dictionary) -> bool:
	if not _bounded_integer(data.get("cash")) or not _bounded_integer(data.get("active_store"), 1, 4): return false
	if not data.get("stores") is Dictionary or not data.stores.has("1") or not data.stores.has(str(int(data.active_store))): return false
	if data.stores.size() > 4: return false
	for key: Variant in data.stores:
		if not key is String or key not in ["1", "2", "3", "4"]: return false
		for earlier in range(1, int(key)):
			if not data.stores.has(str(earlier)): return false
		var branch: Variant = data.stores[key]
		if not branch is Dictionary: return false
		if not _bounded_integer(branch.get("tool_level"), 0, 4) or not _bounded_integer(branch.get("bonzi_tier"), -1, 2): return false
		for field: String in ["payout_level", "bonzi_earned", "manual_jobs", "automated_jobs", "final_tool_jobs", "banked_orders", "job_early_reward"]:
			if not _bounded_integer(branch.get(field)): return false
		if Progression.early_reward(int(key), int(branch.payout_level)) <= 0: return false
		if not _unit_fraction(branch.get("routine_remainder")) or float(branch.routine_remainder) >= 1.0: return false
		if not branch.get("active_job_id") is String or not branch.get("job_snapshot") is Dictionary: return false
		if not branch.get("job_started_with_final_tool") is bool or not branch.get("job_final_tool_used") is bool: return false
		if not str(branch.active_job_id).is_empty() and (int(branch.job_early_reward) <= 0 or int(branch.job_early_reward) > Progression.MAX_MONEY / 2): return false
	if not data.get("completed_rewards") is Dictionary or not data.get("ad_receipts") is Dictionary or not data.get("latest_reward_job") is String: return false
	for job: Variant in data.completed_rewards:
		var offer: Variant = data.completed_rewards[job]
		if not job is String or not offer is Dictionary: return false
		if not _bounded_integer(offer.get("amount"), 1) or not _bounded_integer(offer.get("store_id"), 1, 4) or not offer.get("ad_claimed") is bool: return false
	for receipt: Variant in data.ad_receipts:
		if not receipt is String or not data.ad_receipts[receipt] is String: return false
	return true


func _produce_legacy_absence(legacy: Dictionary, seconds: float) -> void:
	# Settle the saved version-1 interval at its original rate. Migration may
	# improve the future bot, but never reprices orders from before migration.
	var owned: Dictionary = legacy.owned
	if not bool(owned.get("bonzi", false)): return
	var capacity := 45.0 if bool(owned.get("bonzi_mk2", false)) else 30.0
	var demand := 60.0 if bool(owned.get("intake", false)) else 40.0
	var orders := float(_branch().routine_remainder) + seconds * minf(capacity, demand) / 3600.0
	var whole := floori(orders + 0.000000001)
	var payable := mini(whole, int((Progression.MAX_MONEY - cash) / ROUTINE_REWARD))
	var income := payable * ROUTINE_REWARD
	routine_remainder = maxf(0.0, orders - float(whole))
	_branch().routine_remainder = routine_remainder
	_branch().banked_orders = whole - payable
	_branch().bonzi_earned = mini(Progression.MAX_MONEY, int(_branch().bonzi_earned) + income)
	_branch().automated_jobs = mini(Progression.MAX_MONEY, int(_branch().automated_jobs) + payable)
	automated_jobs = mini(Progression.MAX_MONEY, automated_jobs + payable)
	cash += income
