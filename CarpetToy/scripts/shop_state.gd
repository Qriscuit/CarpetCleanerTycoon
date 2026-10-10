extends Node
## The Neighborhood Shop ledger. Each reward/build is committed before it is exposed.

signal changed
signal ad_reward_granted(amount: float)
signal carpet_ad_reward_granted(top_up: float)

const Progression := preload("res://scripts/progression.gd")
const RewardAds := preload("res://scripts/reward_ad_service.gd")
const RugCatalog := preload("res://scripts/rug_catalog.gd")
const RoomUpgrades := preload("res://scripts/room_upgrades.gd")
const Money := preload("res://scripts/money.gd")
const SAVE_VERSION := 3
const SAVE_PATH := "user://neighborhood_shop_v1.json"
const OFFLINE_CAP_SECONDS := 8.0 * 60.0 * 60.0
const MANUAL_REWARD := 20
const MANUAL_COMPLETION_THRESHOLD := 0.75
const PERFECT_REWARD := 40
const PERFECT_COMPLETION_THRESHOLD := 0.99
const COMPLETION_EPSILON := 0.000000001
# Version-1 saves earned this historical price before their migration.
const LEGACY_ROUTINE_REWARD := 10
const COSTS := {"hand_brush": 0, "wide_brush": 80, "bonzi": 100, "bonzi_mk2": 120, "intake": 100}
const GATES := {"hand_brush": 0, "wide_brush": 8, "bonzi": 3, "bonzi_mk2": 10, "intake": 10}

var cash: float = 0.0
var equipped_brush: String = "hand_brush"
var manual_jobs: int = 0
var automated_jobs: int = 0
var routine_remainder: float = 0.0
var active_job_id: String = ""
var active_rug_id: String = RugCatalog.DEFAULT_ID
var job_snapshot: Dictionary = {}
var return_reward: float = 0.0
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
# Request context is transient; the durable receipt and branch flag commit
# together only after verification. A failed write can retry that receipt.
var _carpet_ads_requested: Dictionary = {}
var _verified_carpet_ads_waiting: Dictionary = {}

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
	reward_ads.request_finished.connect(_on_reward_ad_finished)
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


func build_cost(id: String) -> float:
	if id == "wide_brush": return Progression.tool_cost(active_store, int(_branch().tool_level))
	if id == "bonzi": return Progression.bot_cost(active_store, -1)
	if id == "bonzi_mk2": return Progression.bot_cost(active_store, 0)
	if id == "intake": return Progression.bot_cost(active_store, 1)
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

func bonzi_reward_for_store(store_id: int = -1) -> float:
	var id := active_store if store_id == -1 else store_id
	if not stores.has(str(id)): return 0
	var branch: Dictionary = stores[str(id)]
	var early := RoomUpgrades.early_reward(id, branch)
	if early <= 0 or early > Progression.MAX_MONEY / 2: return 0
	return Progression.bot_reward(id, int(branch.bonzi_tier), early * 2)


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
	if active_job_id.is_empty() or not _snapshot_matches_active_rug(snapshot) or not _saved_payment_snapshot_valid(snapshot, active_store):
		return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	job_snapshot = snapshot.duplicate(true)
	job_snapshot["rug_id"] = active_rug_id
	return _finish_transaction(before, old_ticks)


func preview_cleaning_reward(job_id: String, snapshot: Dictionary) -> float:
	# The same preview precedes the durable transaction so the HUD can reserve
	# cosmetic count-up before the general balance notification.
	if job_id.is_empty() or job_id != active_job_id or not _snapshot_matches_active_rug(snapshot): return -1.0
	var eligible := _eligible_cleaning_clearance(snapshot)
	if eligible < 0.0 or current_job_full_reward() <= 0.0: return -1.0
	var branch := _branch()
	if eligible <= float(branch.get("job_cleaning_progress", 0.0)) + COMPLETION_EPSILON: return 0.0
	var target := _cleaning_target(eligible)
	return maxf(0.0, target - float(branch.get("job_cleaning_paid", 0.0)))


func record_cleaning_progress(job_id: String, snapshot: Dictionary) -> float:
	var credited := preview_cleaning_reward(job_id, snapshot)
	if credited < 0.0:
		last_error = "This cleaning progress is invalid or belongs to another job."
		return -1.0
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	if credited > 0.0 and not _can_credit(credited):
		_restore_state(before)
		_last_ticks = old_ticks
		return -1.0
	cash += credited
	var branch := _branch()
	if credited > 0.0: branch.job_cleaning_paid = _cleaning_target(_eligible_cleaning_clearance(snapshot))
	branch.job_cleaning_progress = maxf(float(branch.get("job_cleaning_progress", 0.0)), _eligible_cleaning_clearance(snapshot))
	job_snapshot = snapshot.duplicate(true)
	job_snapshot["rug_id"] = active_rug_id
	return credited if _finish_transaction(before, old_ticks) else -1.0


func complete_job(job_id: String) -> bool:
	if job_id.is_empty() or job_id != active_job_id:
		return false
	if not _completion_snapshot_valid(job_snapshot): return false
	var reward := reward_for_current_job(job_snapshot)
	var earned := _completed_job_earnings(job_snapshot, reward)
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	if reward > 0.0 and not _can_credit(reward):
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	cash += reward
	manual_jobs += 1
	active_job_id = ""
	_record_completed_job(job_id, earned)
	_reset_job_cleaning()
	job_snapshot = {}
	active_rug_id = RugCatalog.DEFAULT_ID
	_refresh_blueprints()
	var committed := _finish_transaction(before, old_ticks)
	if committed: _verified_carpet_ads_waiting.erase(job_id)
	return committed


func complete_and_start_next_job(job_id: String, completed_snapshot: Dictionary) -> String:
	# Rewarding the finished rug and reserving its replacement are one ledger
	# transaction. A repeated tap still carries the old id and is rejected, while
	# a restart during the takeaway animation opens the already-saved next rug.
	if job_id.is_empty() or job_id != active_job_id:
		return ""
	if not _completion_snapshot_valid(completed_snapshot): return ""
	var reward := reward_for_current_job(completed_snapshot)
	var earned := _completed_job_earnings(completed_snapshot, reward)
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	if reward > 0.0 and not _can_credit(reward):
		_restore_state(before)
		_last_ticks = old_ticks
		return ""
	cash += reward
	manual_jobs += 1
	_job_serial += 1
	_record_completed_job(job_id, earned)
	active_job_id = "neighborhood-%d" % _job_serial
	job_snapshot = {}
	_prepare_job()
	_refresh_blueprints()
	if not _finish_transaction(before, old_ticks):
		return ""
	_verified_carpet_ads_waiting.erase(job_id)
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
	_carpet_ads_requested.clear()
	_verified_carpet_ads_waiting.clear()
	changed.emit()
	return true


static func manual_reward_for(snapshot: Dictionary) -> int:
	var debris: Variant = snapshot.get("unique_clearance")
	var surface: Variant = snapshot.get("surface_clearance")
	if not _valid_clearance(debris) or not _valid_clearance(surface):
		return 0
	# Compatibility preview for a fresh starter rug with no installments paid.
	var fraction := minf(float(debris), float(surface))
	var eligible: Variant = snapshot.get("earned_clearance",fraction)
	if not _unit_fraction(eligible) or float(eligible) > fraction + COMPLETION_EPSILON: return 0
	return PERFECT_REWARD if completion_reached(fraction,PERFECT_COMPLETION_THRESHOLD) else MANUAL_REWARD


static func completion_reached(fraction: float, threshold: float) -> bool:
	# Averaging three stages can represent exact 99% as 0.9899999999999999.
	# This tolerance is far smaller than a mask texel or a displayed percent.
	return is_finite(fraction) and fraction + COMPLETION_EPSILON >= threshold


static func _valid_clearance(value: Variant) -> bool:
	return (value is float or value is int) and completion_reached(float(value), MANUAL_COMPLETION_THRESHOLD) and float(value) <= 1.0


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
		var reward := bonzi_reward_for_store(int(key))
		if reward <= 0: continue
		var orders := float(branch.routine_remainder) + maxf(seconds, 0.0) / cycle
		var whole := int(minf(floor(orders + 0.000000001), float(Progression.MAX_COUNTER)))
		branch.routine_remainder = clampf(orders - floor(orders + 0.000000001), 0.0, 0.999999999)
		var due: int = mini(Progression.MAX_COUNTER, whole + int(branch.get("banked_orders", 0)))
		var payable := _payable_orders(due, reward)
		branch.banked_orders = due - payable
		if due > payable: last_error = "Wallet limit reached; Bonzi deliveries wait until coins are spent."
		var income := payable * reward
		cash += income
		branch.bonzi_earned = minf(Progression.MAX_MONEY, float(branch.bonzi_earned) + income)
		branch.automated_jobs = mini(Progression.MAX_COUNTER, int(branch.automated_jobs) + payable)
		delivered += payable
		automated_jobs = mini(Progression.MAX_COUNTER, automated_jobs + payable)
	routine_remainder = float(_branch().routine_remainder)
	return delivered


func _payable_orders(due: int, reward: float) -> int:
	# Compare before conversion: the spare wallet/reward ratio can exceed int64
	# at idle-game values even while the delivery count is an ordinary integer.
	var space := maxf(0.0, Progression.MAX_MONEY - cash)
	return due if float(due) * reward <= space else int(floor(space / reward))


func _finish_transaction(before: Dictionary, old_ticks: int) -> bool:
	if not _commit():
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	changed.emit()
	return true


func _capture_state() -> Dictionary:
	_sync_active_branch()
	for key: String in stores:
		var branch: Dictionary = stores[key]
		RoomUpgrades.migrate_branch(int(key), branch)
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
		"active_rug_id": active_rug_id,
		"job_snapshot": job_snapshot.duplicate(true),
		"return_reward": return_reward,
		"return_seconds": return_seconds,
		"saved_wall": _saved_wall,
		"active_store": active_store, "stores": stores.duplicate(true),
		"completed_rewards": completed_rewards.duplicate(true),
		"ad_receipts": ad_receipts.duplicate(true), "latest_reward_job": _latest_reward_job,
	}


func _restore_state(data: Dictionary) -> void:
	cash = float(data["cash"])
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
	active_rug_id = _saved_rug_id(data, job_snapshot)
	return_reward = float(data["return_reward"])
	return_seconds = float(data["return_seconds"])
	_saved_wall = float(data["saved_wall"])
	active_store = int(data.get("active_store", 1))
	if data.has("stores"):
		stores = data.stores.duplicate(true)
	else:
		_migrate_legacy_branch()
	# Existing wash-kit purchases paid for both tools. Add independent tracks
	# without charging again or replacing an unfinished rug or its dry progress.
	for key: String in stores:
		var branch: Dictionary = stores[key]
		# Old unfinished jobs had no progressive payment; retain their masks and
		# initialize the new accounting without changing the existing wallet.
		if not branch.has("job_cleaning_paid"): branch.job_cleaning_paid = 0.0
		if not branch.has("job_cleaning_progress"): branch.job_cleaning_progress = 0.0
		if not branch.has("job_ad_boost"): branch.job_ad_boost = false
		# Additive version-2 migration: old unfinished rugs remain Mint, regardless
		# of their completion count. Cosmetic ID damage must not erase work/cash.
		branch.active_rug_id = _saved_rug_id(branch, branch.job_snapshot)
		_stamp_snapshot_rug(branch.job_snapshot, branch.active_rug_id)
		var legacy_wet := int(branch.tool_level) if int(key) >= 3 else 0
		if not branch.has("hose_level"): branch.hose_level = legacy_wet
		if not branch.has("squeegee_level"): branch.squeegee_level = legacy_wet
		# Store 2's old brush purchases now count toward its main hose track.
		# Retain the original brush level/power; future hose buys do not alter it.
		if int(key) >= Progression.WET_FIRST_STORE:
			branch.hose_level = maxi(int(branch.hose_level), int(branch.tool_level))
		if int(key) >= Progression.WET_FIRST_STORE or (int(key) >= 3 and int(branch.get("room_rules_version", 0)) < RoomUpgrades.RULES_VERSION):
			branch.tool_level = int(branch.hose_level)
		if int(branch.get("room_rules_version", 0)) < RoomUpgrades.RULES_VERSION and int(key) >= 2:
			branch.tool_level = maxi(int(branch.tool_level), int(branch.hose_level))
		# Section curves retain purchased appearances and the unfinished carpet.
		RoomUpgrades.migrate_branch(int(key), branch)
	completed_rewards = data.get("completed_rewards", {}).duplicate(true)
	ad_receipts = data.get("ad_receipts", {}).duplicate(true)
	_latest_reward_job = str(data.get("latest_reward_job", ""))
	_load_active_branch()


func _commit() -> bool:
	if not _save_enabled:
		return false
	if not _bounded_money(cash) or not _bounded_integer(manual_jobs) or not _bounded_integer(automated_jobs) or not _bounded_integer(_job_serial) or not _bounded_money(return_reward):
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
	file.store_string(JSON.stringify(data, "", true, true))
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
	if not _bounded_integer(data.get("version"), 1, SAVE_VERSION):
		return false
	for key: String in ["cash", "return_reward"]:
		if not _bounded_money(data.get(key)): return false
	for key: String in ["manual_jobs", "automated_jobs", "job_serial"]:
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
	if int(data.version) >= 2 and not _valid_progression_save(data):
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
	branch.active_rug_id = active_rug_id
	branch.job_snapshot = job_snapshot
	branch.routine_remainder = routine_remainder


func _load_active_branch() -> void:
	var branch := _branch()
	active_job_id = str(branch.active_job_id)
	job_snapshot = branch.job_snapshot.duplicate(true)
	active_rug_id = _saved_rug_id(branch, job_snapshot)
	_stamp_snapshot_rug(job_snapshot, active_rug_id)
	routine_remainder = float(branch.routine_remainder)


static func _saved_rug_id(record: Dictionary, snapshot: Dictionary) -> String:
	# The reserved branch identity is authoritative if recognized. A snapshot
	# can recover an absent/damaged ID. Retired art switches to its replacement
	# without changing the reservation or saved dirt/water; old saves stay Mint.
	var reserved: String = RugCatalog.resolve_saved_id(record.get("active_rug_id"))
	if not reserved.is_empty(): return reserved
	var captured: String = RugCatalog.resolve_saved_id(snapshot.get("rug_id"))
	return captured if not captured.is_empty() else RugCatalog.DEFAULT_ID

static func _stamp_snapshot_rug(snapshot: Dictionary, rug_id: String) -> void:
	# An empty snapshot means a reserved, not-yet-spawned rug. Keep that marker.
	if not snapshot.is_empty(): snapshot["rug_id"] = rug_id


func _snapshot_matches_active_rug(snapshot: Dictionary) -> bool:
	if not RugCatalog.is_known(active_rug_id):
		last_error = "The current rug identity is unavailable. Reopen this job to restore it."
		return false
	# Old snapshots and legacy callers have no ID. New explicit IDs must match
	# the reservation so stale artwork cannot overwrite or finish another rug.
	if snapshot.has("rug_id") and (not RugCatalog.is_known(snapshot["rug_id"]) or snapshot["rug_id"] != active_rug_id):
		last_error = "This progress belongs to a different rug."
		return false
	return true


func _prepare_job() -> void:
	var branch := _branch()
	_reset_job_cleaning()
	# Reserve the art in the same transaction as the job. Reloading, upgrades,
	# ad rewards and failed writes cannot reroll the customer's unfinished rug.
	active_rug_id = RugCatalog.id_for_completed_jobs(int(branch.manual_jobs))
	branch.job_early_reward = RoomUpgrades.early_reward(active_store, branch)
	branch.job_started_with_final_tool = _travel_tool_level(branch, active_store) == 4
	branch.job_final_tool_used = false


func _reset_job_cleaning() -> void:
	_branch().job_cleaning_paid = 0.0
	_branch().job_cleaning_progress = 0.0
	_branch().job_ad_boost = false


func note_current_tool_used(tool_index: int = -1) -> void:
	# Use after a mid-job purchase counts; ownership or earlier activity alone
	# never does. Runtime callers pass the tool that actually affected the rug.
	var required_tool := 2 if active_store >= Progression.WET_FIRST_STORE else 0
	if tool_index == -1: tool_index = required_tool
	if active_job_id.is_empty() or tool_index != required_tool:
		return
	var branch := _branch()
	if _travel_tool_level(branch, active_store) == 4:
		branch.job_started_with_final_tool = true
		branch.job_final_tool_used = true


func _record_completed_job(job_id: String, reward: float) -> void:
	var branch := _branch()
	branch.manual_jobs = int(branch.manual_jobs) + 1
	if bool(branch.job_started_with_final_tool) and bool(branch.job_final_tool_used):
		branch.final_tool_jobs = mini(Progression.CAPSTONE_JOBS, int(branch.final_tool_jobs) + 1)
	completed_rewards[job_id] = {"amount": reward, "store_id": active_store, "ad_claimed": reward <= 0.0 or bool(branch.get("job_ad_boost", false))}
	_latest_reward_job = job_id


func reward_for_current_job(snapshot: Dictionary) -> float:
	if not _completion_snapshot_valid(snapshot): return 0.0
	if completion_reached(_job_clearance(snapshot), PERFECT_COMPLETION_THRESHOLD):
		# Restoration settles the exact full quote, including any last unpaid
		# cleaning coins, while already-paid coins cannot be paid a second time.
		return maxf(0.0,current_job_full_reward() - float(_branch().get("job_cleaning_paid", 0.0)))
	# Choosing Finish at75% settles the complete cleaning half; the installments
	# already received are deducted, and restoration still requires99%.
	return maxf(0.0,current_job_full_reward() / 2.0 - float(_branch().get("job_cleaning_paid", 0.0)))


func current_job_full_reward() -> float:
	if active_job_id.is_empty(): return 0.0
	var half := float(_branch().job_early_reward)
	var multiplier := 2.0 if bool(_branch().get("job_ad_boost", false)) else 1.0
	return half * 2.0 * multiplier if half > 0.0 and _bounded_money(half, 0.0, Progression.MAX_MONEY / (2.0 * multiplier)) else 0.0


func _completion_snapshot_valid(snapshot: Dictionary) -> bool:
	return not active_job_id.is_empty() and _snapshot_matches_active_rug(snapshot) and current_job_full_reward() > 0.0 and _eligible_cleaning_clearance(snapshot) >= 0.0 and completion_reached(_job_clearance(snapshot), MANUAL_COMPLETION_THRESHOLD)


func _completed_job_earnings(snapshot: Dictionary, remaining: float) -> float:
	return current_job_full_reward() if completion_reached(_job_clearance(snapshot), PERFECT_COMPLETION_THRESHOLD) else float(_branch().get("job_cleaning_paid", 0.0)) + remaining


func _cleaning_target(fraction: float) -> float:
	var half := current_job_full_reward() / 2.0
	return half if completion_reached(fraction, PERFECT_COMPLETION_THRESHOLD) else floorf(half * clampf(fraction / PERFECT_COMPLETION_THRESHOLD, 0.0, 1.0))


func _eligible_cleaning_clearance(snapshot: Dictionary, store_id: int = -1) -> float:
	if not _payment_snapshot_fractions_valid(snapshot): return -1.0
	var actual := cleaning_clearance_for_snapshot(snapshot, store_id)
	if actual < 0.0: return -1.0
	var eligible: Variant = snapshot.get("earned_clearance", actual)
	if not _unit_fraction(eligible) or float(eligible) > actual + COMPLETION_EPSILON: return -1.0
	if snapshot.has("cleaning_pending_clearance") and float(snapshot.cleaning_pending_clearance) > actual + COMPLETION_EPSILON: return -1.0
	return minf(float(eligible), actual)


static func _payment_snapshot_fractions_valid(snapshot: Dictionary) -> bool:
	for key: String in ["unique_clearance", "surface_clearance", "water_clearance", "extraction_clearance", "earned_clearance", "cleaning_pending_clearance"]:
		if snapshot.has(key) and not _unit_fraction(snapshot[key]): return false
	return true


func _saved_payment_snapshot_valid(snapshot: Dictionary, store_id: int) -> bool:
	if not _payment_snapshot_fractions_valid(snapshot): return false
	# Old snapshots can omit every added payment field. New fields always
	# require genuine removal fractions, including in inactive saved shops.
	if snapshot.has("earned_clearance") or snapshot.has("cleaning_pending_clearance"):
		return _eligible_cleaning_clearance(snapshot, store_id) >= 0.0
	return true


func cleaning_clearance_for_snapshot(snapshot: Dictionary, store_id: int = -1) -> float:
	# Water applied is preparation. Only removed dry dirt and extraction earn
	# the cleaning half; the remaining half is reserved for full restoration.
	for key: String in ["unique_clearance", "surface_clearance"]:
		if not _unit_fraction(snapshot.get(key)): return -1.0
	var dry := minf(float(snapshot.unique_clearance),float(snapshot.surface_clearance))
	var id := active_store if store_id < 0 else store_id
	if id < Progression.WET_FIRST_STORE: return dry
	if snapshot.get("wet_recipe") != true: return -1.0
	for key: String in ["water_clearance", "extraction_clearance"]:
		if not _unit_fraction(snapshot.get(key)): return -1.0
	var water := float(snapshot.water_clearance)
	var extraction := float(snapshot.extraction_clearance)
	var skip_dry := id == Progression.WET_FIRST_STORE
	if snapshot.get("skip_dry_stage",false) != skip_dry: return -1.0
	var cycle := 0
	var count := 1
	if snapshot.has("wash_cycle_count") or snapshot.has("wash_cycle"):
		if not _bounded_integer(snapshot.get("wash_cycle_count"),3,3) or not _bounded_integer(snapshot.get("wash_cycle"),0,2): return -1.0
		cycle = int(snapshot.wash_cycle)
		count = 3
	if not skip_dry and (water > 0.0 or cycle > 0) and not completion_reached(dry,PERFECT_COMPLETION_THRESHOLD): return -1.0
	if extraction > 0.0 and not completion_reached(water,PERFECT_COMPLETION_THRESHOLD): return -1.0
	var removed := (0.0 if skip_dry else dry) + float(cycle) * PERFECT_COMPLETION_THRESHOLD + minf(extraction, PERFECT_COMPLETION_THRESHOLD)
	var fraction := removed / float(count + (0 if skip_dry else 1))
	return PERFECT_COMPLETION_THRESHOLD if completion_reached(fraction, PERFECT_COMPLETION_THRESHOLD) else clampf(fraction,0.0,PERFECT_COMPLETION_THRESHOLD)


func _job_clearance(snapshot: Dictionary) -> float:
	for key: String in ["unique_clearance", "surface_clearance"]:
		if not _unit_fraction(snapshot.get(key)): return -1.0
	var dry := minf(float(snapshot.unique_clearance), float(snapshot.surface_clearance))
	if active_store < Progression.WET_FIRST_STORE: return dry
	if snapshot.get("wet_recipe") != true: return -1.0
	for key: String in ["water_clearance", "extraction_clearance"]:
		if not _unit_fraction(snapshot.get(key)): return -1.0
	var water := float(snapshot.water_clearance)
	var extraction := float(snapshot.extraction_clearance)
	if snapshot.has("wash_cycle_count") or snapshot.has("wash_cycle"):
		var count: Variant = snapshot.get("wash_cycle_count")
		var cycle: Variant = snapshot.get("wash_cycle")
		if not (count is int or count is float) or not is_finite(float(count)) or float(count) != 3.0:
			return -1.0
		if not (cycle is int or cycle is float) or not is_finite(float(cycle)) or float(cycle) != floorf(float(cycle)) or float(cycle) < 0.0 or float(cycle) > 2.0:
			return -1.0
		var skip_dry: bool = active_store == Progression.WET_FIRST_STORE
		if snapshot.get("skip_dry_stage", false) != skip_dry:
			return -1.0
		if not skip_dry and (water > 0.0 or int(cycle) > 0) and not completion_reached(dry, PERFECT_COMPLETION_THRESHOLD):
			return -1.0
		if extraction > 0.0 and not completion_reached(water, PERFECT_COMPLETION_THRESHOLD):
			return -1.0
		# A paid finish requires the third squeegee round. The old early-finish
		# option applies within that last extraction, never to earlier rounds.
		if int(cycle) != 2 or not completion_reached(water, PERFECT_COMPLETION_THRESHOLD) or not completion_reached(extraction, MANUAL_COMPLETION_THRESHOLD):
			return -1.0
		var wet_work := float(int(cycle) * 2) + water + extraction
		var fraction := wet_work / 6.0 if skip_dry else (dry + wet_work) / 7.0
		return fraction if completion_reached(extraction, PERFECT_COMPLETION_THRESHOLD) else minf(fraction, 0.989)
	# High Street is a water -> extract lesson. Its dry mask is preserved in
	# snapshots but does not contribute to completion or unlock a third stage.
	if active_store == Progression.WET_FIRST_STORE:
		if snapshot.get("skip_dry_stage") != true: return -1.0
		if extraction > 0.0 and not completion_reached(water, PERFECT_COMPLETION_THRESHOLD): return -1.0
		return (water + extraction) / 2.0
	if snapshot.get("skip_dry_stage", false) != false: return -1.0
	# Wet work follows dry -> wash -> extract. Reject fabricated later-stage
	# progress and recompute the meter rather than trusting an overall field.
	if water > 0.0 and dry < PERFECT_COMPLETION_THRESHOLD: return -1.0
	if extraction > 0.0 and water < PERFECT_COMPLETION_THRESHOLD: return -1.0
	return (dry + water + extraction) / 3.0


static func _unit_fraction(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0


func _highest_dry_tier() -> int:
	return Progression.dry_visual_tier(_highest_dry_stage())


func _highest_dry_stage(proposed_store: int = -1, proposed_level: int = -1) -> int:
	var tier := 0
	for key: String in stores:
		var store_id := int(key)
		if store_id < Progression.WET_FIRST_STORE:
			var level := proposed_level if store_id == proposed_store else int(stores[key].tool_level)
			tier = maxi(tier, Progression.dry_stage(store_id, level))
	return tier


func _wet_level(branch: Dictionary, store_id: int, kind: String) -> int:
	var legacy := int(branch.tool_level) if store_id >= Progression.WET_FIRST_STORE and kind == "hose" else 0
	var level := int(branch.get(kind + "_level", legacy))
	# tool_level is retained as the later stores' hose/travel compatibility key.
	return maxi(level, legacy) if kind == "hose" else level


func _travel_tool_level(branch: Dictionary, store_id: int) -> int:
	return _wet_level(branch, store_id, "hose") if store_id >= Progression.WET_FIRST_STORE else int(branch.tool_level)


func _wet_power(kind: String, proposed_store: int = -1, proposed_level: int = -1) -> float:
	var power := 1.0
	for key: String in stores:
		var store_id := int(key)
		if store_id < Progression.WET_FIRST_STORE: continue
		var level := proposed_level if store_id == proposed_store else _wet_level(stores[key], store_id, kind)
		power = maxf(power, float(Progression.WET_POWERS[level]) * Progression.wet_base_power(store_id))
	return power


func store_mastered(store_id: int) -> bool:
	if not stores.has(str(store_id)): return false
	var branch: Dictionary = stores[str(store_id)]
	RoomUpgrades.migrate_branch(store_id, branch)
	for id: String in RoomUpgrades.IDS:
		if int(branch.room_upgrades[id]) < Progression.room_level_cap(store_id): return false
	return _travel_tool_level(branch, store_id) == 4 and int(branch.bonzi_tier) == 2 and int(branch.final_tool_jobs) >= Progression.CAPSTONE_JOBS and float(branch.bonzi_earned) >= 100.0 * Progression.scale_for(store_id)


func section_progress(section_id: int = 1) -> Dictionary:
	var completed := 0
	var first := (section_id - 1) * Progression.STORES_PER_SECTION + 1
	if Progression.section_available(section_id):
		for id in range(first, first + Progression.STORES_PER_SECTION):
			if store_mastered(id): completed += 1
	var complete := Progression.section_available(section_id) and completed == Progression.STORES_PER_SECTION
	return {
		"section_id": section_id, "completed": completed, "total": Progression.STORES_PER_SECTION,
		"complete": complete, "available": Progression.section_available(section_id),
		"next_available": complete and Progression.section_available(section_id + 1),
	}


func progression_view() -> Dictionary:
	var branch := _branch()
	RoomUpgrades.migrate_branch(active_store, branch)
	var scale := Progression.scale_for(active_store)
	var level := int(branch.payout_level)
	var local_tool := _travel_tool_level(branch, active_store)
	var tier := _highest_dry_tier()
	var stage := _highest_dry_stage()
	var next_stage := _highest_dry_stage(active_store, mini(local_tool + 1, 4)) if active_store < Progression.WET_FIRST_STORE else stage
	var next_tier := Progression.dry_visual_tier(next_stage)
	var compatibility_offer := room_upgrade_view(RoomUpgrades.next_id(room_upgrade_levels()))
	var early := float(compatibility_offer.early_reward)
	var next_early := float(compatibility_offer.next_early)
	var payout_price := float(compatibility_offer.cost)
	var tool_price := Progression.tool_cost(active_store, local_tool)
	var bot_tier := int(branch.bonzi_tier)
	var bot_price := Progression.bot_cost(active_store, bot_tier)
	var wet_unlocked := active_store >= Progression.WET_FIRST_STORE
	var hose_level := _wet_level(branch, active_store, "hose")
	var squeegee_level := _wet_level(branch, active_store, "squeegee")
	var hose_cost: float = Progression.tool_cost(active_store, hose_level) if wet_unlocked else -1.0
	var squeegee_cost: float = Progression.tool_cost(active_store, squeegee_level) if wet_unlocked else -1.0
	var effective_hose_level := 0
	for key: String in stores:
		if int(key) >= Progression.WET_FIRST_STORE:
			effective_hose_level = maxi(effective_hose_level, _wet_level(stores[key], int(key), "hose"))
	var hose_power := _wet_power("hose")
	var squeegee_power := _wet_power("squeegee")
	var next_hose_power := _wet_power("hose", active_store, mini(hose_level + 1, 4)) if wet_unlocked else hose_power
	var next_squeegee_power := _wet_power("squeegee", active_store, mini(squeegee_level + 1, 4)) if wet_unlocked else squeegee_power
	var hose_profile := preload("res://scripts/water_hose_profile.gd")
	var owned: Array[int] = []
	for key: String in stores: owned.append(int(key))
	owned.sort()
	var next_section := Progression.section_for(active_store + 1)
	var has_next := active_store < Progression.STORE_COUNT and Progression.section_available(next_section)
	if next_section != Progression.section_for(active_store):
		has_next = has_next and bool(section_progress(Progression.section_for(active_store)).complete)
	var target := 100 * scale
	var travel := 2000 * scale
	var room_target := Progression.room_level_cap(active_store) * RoomUpgrades.IDS.size()
	var room_complete := level >= room_target
	var gate := store_mastered(active_store)
	var travel_tool_name := "Water hose" if wet_unlocked else "Brush"
	var requirements: Array[String] = [
		"Room upgrades: %d/%d" % [level, room_target],
		"%s upgrades: %d/4" % [travel_tool_name, local_tool],
		"Paid rugs using the max %s: %d/%d" % [travel_tool_name.to_lower(), mini(int(branch.final_tool_jobs), Progression.CAPSTONE_JOBS), Progression.CAPSTONE_JOBS],
		"Bonzi upgrades: %d/3" % [bot_tier + 1],
		"Bonzi earned here: %s/%s coins" % [Money.format(float(branch.bonzi_earned)), Money.format(target)],
		"Opening coins: %s/%s" % [Money.format(cash), Money.format(travel)],
	]
	var blockers: Array[String] = []
	if not room_complete: blockers.append(requirements[0])
	if local_tool < 4: blockers.append(requirements[1])
	if int(branch.final_tool_jobs) < Progression.CAPSTONE_JOBS: blockers.append(requirements[2])
	if bot_tier < 2: blockers.append(requirements[3])
	if float(branch.bonzi_earned) < target: blockers.append(requirements[4])
	if cash < travel: blockers.append(requirements[5])
	var next_name: String = "Maxed" if local_tool == 4 else ("Water hose · Lv %d" % (hose_level + 2) if wet_unlocked else "%s · Lv %d" % [Progression.TOOL_NAMES[next_tier], local_tool + 2])
	return {
		"store_id": active_store, "store_name": Progression.store_name(active_store), "owned_store_ids": owned,
		"section_id": Progression.section_for(active_store), "store_in_section": Progression.store_in_section(active_store),
		"section_progress": section_progress(Progression.section_for(active_store)),
		"reward_cap": Progression.reward_cap(active_store), "store_mastered": gate,
		"room_level_cap": Progression.room_level_cap(active_store), "room_level_target": room_target,
		"payout_level": level, "early_reward": early, "full_reward": early * 2,
		"next_early": next_early, "next_full": next_early * 2 if next_early > 0 else -1,
		"payout_cost": payout_price, "can_upgrade_payout": payout_price >= 0 and cash >= payout_price,
		"tool_level": local_tool, "global_tool_tier": tier,
		"next_global_tool_tier": next_tier,
		"tool_name": "Water hose · Lv %d" % (hose_level + 1) if wet_unlocked else Progression.TOOL_NAMES[tier],
		"next_tool_name": next_name, "tool_cost": tool_price,
		"tool_width": Progression.TOOL_WIDTHS[tier], "tool_power": Progression.dry_power(stage),
		"next_tool_width": Progression.TOOL_WIDTHS[next_tier], "next_tool_power": Progression.dry_power(next_stage),
		"can_upgrade_tool": tool_price >= 0 and cash >= tool_price,
		"wet_unlocked": wet_unlocked,
		"hose_level": hose_level, "squeegee_level": squeegee_level,
		"effective_hose_level": effective_hose_level,
		"hose_cost": hose_cost, "squeegee_cost": squeegee_cost,
		"can_upgrade_hose": hose_cost >= 0 and cash >= hose_cost,
		"can_upgrade_squeegee": squeegee_cost >= 0 and cash >= squeegee_cost,
		"hose_power": hose_power, "next_hose_power": next_hose_power,
		"hose_radius": hose_profile.WET_RADII[effective_hose_level],
		"next_hose_radius": hose_profile.WET_RADII[maxi(effective_hose_level, mini(hose_level + 1, 4))],
		"squeegee_power": squeegee_power, "next_squeegee_power": next_squeegee_power,
		"wet_tool_level": hose_level, "wet_power": maxf(hose_power, squeegee_power),
		"next_wet_power": maxf(next_hose_power, squeegee_power),
		"bonzi_tier": bot_tier, "bonzi_reward": bonzi_reward_for_store(),
		"bonzi_seconds": Progression.bot_seconds(bot_tier), "bonzi_cost": bot_price,
		"bonzi_earned": float(branch.bonzi_earned), "bonzi_target": target,
		"can_upgrade_bonzi": bot_price >= 0 and cash >= bot_price and (bot_tier >= 0 or int(branch.manual_jobs) >= 3),
		"local_jobs": int(branch.manual_jobs), "final_tool_jobs": int(branch.final_tool_jobs), "final_tool_target": Progression.CAPSTONE_JOBS,
		"travel_cost": travel, "can_travel": has_next and not stores.has(str(active_store + 1)) and gate and cash >= travel,
		"has_next_store": has_next, "travel_ready": gate, "next_store_name": Progression.store_name(active_store + 1),
		"travel_tool_name": travel_tool_name, "travel_tool_level": local_tool, "travel_tool_target": 4,
		"travel_blockers": blockers, "travel_requirements": "\n".join(requirements),
		"payout_level_target": room_target,
	}


func buy_payout_upgrade() -> bool:
	# Compatibility for old callers; the player buys the features in the room.
	return buy_room_upgrade(RoomUpgrades.next_id(room_upgrade_levels()))


func room_upgrade_levels() -> Dictionary:
	return RoomUpgrades.levels_for_branch(_branch())


func room_upgrade_view(id: String) -> Dictionary:
	if not RoomUpgrades.is_known(id): return {}
	RoomUpgrades.migrate_branch(active_store, _branch())
	var branch := _branch()
	var levels := room_upgrade_levels()
	var level := int(levels[id])
	var cap := Progression.room_level_cap(active_store)
	var next_level := mini(level + 1, cap)
	var early := RoomUpgrades.early_reward(active_store, branch)
	var origin := int(branch.room_income_origins[id])
	var contribution := RoomUpgrades.early_contribution(active_store, id, level, origin)
	var next_contribution := RoomUpgrades.early_contribution(active_store, id, next_level, origin)
	var gain := RoomUpgrades.early_gain(active_store, id, next_level) if next_level > level else 0.0
	var next_early := minf(Progression.reward_cap(active_store) / 2.0, early + gain) if early > 0 and contribution >= 0 and next_contribution >= 0 and gain >= 0 else -1.0
	var next_all_maxed := next_level == cap
	for other: String in RoomUpgrades.IDS:
		if other != id and int(levels[other]) < cap: next_all_maxed = false
	if next_all_maxed: next_early = Progression.reward_cap(active_store) / 2.0
	if gain > Progression.MAX_MONEY / 2.0 - early: next_early = -1.0
	# A low-level feature remains buyable beside an AF-valued feature even when
	# its tiny immediate gain is below float64's display/accounting precision.
	var price := RoomUpgrades.cost(active_store, id, level) if gain > 0 and next_early > 0 else -1.0
	var visual_level := RoomUpgrades.visual_tier(id, level, active_store)
	var next_visual_level := RoomUpgrades.next_visual_level(id, level, active_store)
	var definition: Dictionary = RoomUpgrades.DEFINITIONS[id]
	return {
		"id": id, "title": str(definition.title),
		"description": RoomUpgrades.next_description(id, level, active_store),
		"benefit": str(definition.description),
		"store_id": active_store, "level": level, "next_level": next_level,
		"max_level": cap, "maxed": level >= cap,
		"visual_level": visual_level,
		"next_visual_level": next_visual_level,
		"next_visual_tier": mini(visual_level + 1, RoomUpgrades.visual_count(id)),
		"visual_step": RoomUpgrades.visual_step_for(id, active_store),
		"upgrades_to_visual": next_visual_level - level if next_visual_level >= 0 else 0,
		"milestone_progress": RoomUpgrades.milestone_progress(id, level, active_store),
		"max_visual_level": RoomUpgrades.visual_count(id),
		"refinement": next_visual_level < 0 and level < cap,
		"current_name": RoomUpgrades.tier_name(id, level, active_store),
		"next_name": RoomUpgrades.tier_name(id, next_level, active_store),
		"cost": price, "can_upgrade": price >= 0 and cash >= price and _save_enabled,
		"early_reward": early, "full_reward": early * 2,
		"next_early": next_early, "next_full": next_early * 2 if next_early > 0 else -1,
		"early_contribution": contribution, "next_early_contribution": next_contribution,
		"contribution": contribution * 2, "next_contribution": next_contribution * 2 if next_contribution >= 0 else -1,
		"wallet_before": cash, "wallet_after": cash - price if price >= 0 else cash,
	}


func buy_room_upgrade(id: String) -> bool:
	if not RoomUpgrades.is_known(id):
		last_error = "That room improvement is unavailable."
		return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	var view := room_upgrade_view(id)
	if not bool(view.can_upgrade):
		_restore_state(before)
		_last_ticks = old_ticks
		last_error = "Room improvement unavailable or not enough coins."
		return false
	var branch := _branch()
	var levels := room_upgrade_levels()
	levels[id] = int(levels[id]) + 1
	cash -= float(view.cost)
	branch.room_upgrades = levels
	branch.payout_level = RoomUpgrades.total_levels(levels)
	# The rug in front of the player earns the new amount immediately. Its
	# identity, dirt, water and paid reward history are not changed by renovation.
	if not active_job_id.is_empty(): branch.job_early_reward = float(view.next_early)
	return _finish_transaction(before, old_ticks)


func buy_tool_upgrade() -> bool:
	return buy_hose_upgrade() if active_store >= Progression.WET_FIRST_STORE else _buy_progression("tool")


func buy_hose_upgrade() -> bool:
	return _buy_progression("hose")


func buy_squeegee_upgrade() -> bool:
	return _buy_progression("squeegee")


func buy_bonzi_upgrade() -> bool:
	return _buy_progression("bonzi")


func _buy_progression(kind: String) -> bool:
	if kind == "payout": return buy_payout_upgrade()
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	var view := progression_view()
	var allowed: bool = bool(view.get("can_upgrade_" + kind, false))
	var price: float = float(view.get(kind + "_cost", -1))
	if not allowed or price < 0:
		_restore_state(before)
		_last_ticks = old_ticks
		last_error = "Upgrade unavailable or not enough coins."
		return false
	cash -= price
	var branch := _branch()
	if kind == "tool":
		branch.tool_level = int(branch.tool_level) + 1
		if active_store < Progression.WET_FIRST_STORE:
			_owned.wide_brush = true
			equipped_brush = "wide_brush"
	elif kind in ["hose", "squeegee"]:
		branch[kind + "_level"] = int(view[kind + "_level"]) + 1
		if kind == "hose" and active_store >= Progression.WET_FIRST_STORE:
			branch.tool_level = int(branch.hose_level)
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
		if not bool(view.has_next_store):
			last_error = "You already own the final store."
		elif stores.has(str(active_store + 1)):
			last_error = "%s is already open. Choose Visit to enter it." % str(view.next_store_name)
		else:
			last_error = "To open %s:\n%s" % [str(view.next_store_name), "\n".join(view.travel_blockers)]
		return false
	cash -= float(view.travel_cost)
	_sync_active_branch()
	active_store += 1
	stores[str(active_store)] = Progression.new_branch(active_store)
	_load_active_branch()
	return _finish_transaction(before, old_ticks)


func select_store(store_id: int) -> bool:
	if store_id < 1 or store_id > Progression.STORE_COUNT or not Progression.section_available(Progression.section_for(store_id)) or not stores.has(str(store_id)): return false
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
	branch.bonzi_earned = minf(Progression.MAX_MONEY, float(automated_jobs) * LEGACY_ROUTINE_REWARD)
	branch.routine_remainder = routine_remainder
	branch.active_job_id = active_job_id
	branch.active_rug_id = active_rug_id
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
	cash = float(before.cash)
	automated_jobs = int(before.automated_jobs)
	for key: String in before.branches:
		var values: Array = before.branches[key]
		var branch: Dictionary = stores[key]
		branch.routine_remainder = values[0]
		branch.automated_jobs = values[1]
		branch.bonzi_earned = values[2]
		branch.banked_orders = values[3]
	routine_remainder = float(_branch().routine_remainder)


func _can_credit(amount: float) -> bool:
	if not _bounded_money(amount, 1.0) or amount > Progression.MAX_MONEY - cash:
		last_error = "Reward exceeds the supported wallet range."
		return false
	return true


func reward_offer() -> Dictionary:
	var offer: Dictionary = completed_rewards.get(_latest_reward_job, {})
	return {"job_id": _latest_reward_job, "amount": float(offer.get("amount", 0)), "available": not offer.is_empty() and not bool(offer.get("ad_claimed", false)) and reward_ads.is_rewarded_ad_available()}


func reward_ad_available() -> bool:
	return bool(reward_offer().available)


func carpet_ad_offer() -> Dictionary:
	var job := active_job_id
	var boosted := bool(_branch().get("job_ad_boost", false))
	var quote := current_job_full_reward()
	var provider_available := reward_ads.is_rewarded_ad_available()
	var requesting: bool = not job.is_empty() and reward_ads.is_pending(job) and _carpet_ads_requested.get(job, -1) == active_store
	var retry: Dictionary = _verified_carpet_ads_waiting.get(job, {})
	var verified_retry := not retry.is_empty() and int(retry.store_id) == active_store and not ad_receipts.has(str(retry.receipt_id))
	var boosted_quote := quote if boosted else quote * 2.0
	var valid_quote := quote > 0.0 and _bounded_money(boosted_quote)
	return {
		"job_id": job, "store_id": active_store, "boosted": boosted,
		"provider_available": provider_available, "requesting": requesting,
		"available": not job.is_empty() and not boosted and not requesting and valid_quote and _save_enabled and (provider_available or verified_retry),
		"full_reward": quote, "boosted_full_reward": boosted_quote if valid_quote else 0.0,
		"top_up": 0.0 if boosted else float(_branch().get("job_cleaning_paid", 0.0)),
	}


func request_carpet_reward_ad(job_id: String = "") -> bool:
	var id := active_job_id if job_id.is_empty() else job_id
	var offer := carpet_ad_offer()
	if id.is_empty() or id != active_job_id or not bool(offer.available): return false
	if _verified_carpet_ads_waiting.has(id):
		var verified: Dictionary = _verified_carpet_ads_waiting[id]
		if not ad_receipts.has(str(verified.receipt_id)):
			return _apply_verified_carpet_reward(id, verified)
		_verified_carpet_ads_waiting.erase(id)
	_carpet_ads_requested[id] = active_store
	var started: bool = reward_ads.request_reward(id)
	if not started: _carpet_ads_requested.erase(id)
	changed.emit()
	return started


func _on_reward_ad_finished(job_id: String) -> void:
	# Legacy completed-receipt flights keep their original ad-then-changed
	# notification pair; only the current-carpet button needs request states.
	if not _carpet_ads_requested.has(job_id): return
	_carpet_ads_requested.erase(job_id)
	changed.emit()


func _on_verified_carpet_reward(job_id: String, receipt_id: String) -> void:
	var requested_store := int(_carpet_ads_requested.get(job_id, -1))
	if job_id != active_job_id or requested_store != active_store or bool(_branch().get("job_ad_boost", false)) or ad_receipts.has(receipt_id): return
	var verified := {"store_id": requested_store, "receipt_id": receipt_id}
	_verified_carpet_ads_waiting[job_id] = verified
	_apply_verified_carpet_reward(job_id, verified)


func _apply_verified_carpet_reward(job_id: String, verified: Dictionary) -> bool:
	var receipt_id := str(verified.receipt_id)
	if job_id != active_job_id or int(verified.store_id) != active_store or bool(_branch().get("job_ad_boost", false)) or ad_receipts.has(receipt_id): return false
	var quote := current_job_full_reward()
	if quote <= 0.0 or not _bounded_money(quote * 2.0): return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	var branch := _branch()
	var top_up := float(branch.get("job_cleaning_paid", 0.0))
	if top_up > 0.0 and not _can_credit(top_up):
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	cash += top_up
	branch.job_cleaning_paid = top_up * 2.0
	branch.job_ad_boost = true
	ad_receipts[receipt_id] = job_id
	if not _commit():
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	_verified_carpet_ads_waiting.erase(job_id)
	_carpet_ads_requested.erase(job_id)
	# Reserve cosmetic count-up before general balance synchronization. The
	# verified receipt, doubled paid mark and boost flag are already durable.
	carpet_ad_reward_granted.emit(top_up)
	changed.emit()
	return true


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
	if _carpet_ads_requested.has(job_id):
		_on_verified_carpet_reward(job_id, receipt_id)
		return
	if not completed_rewards.has(job_id) or bool(completed_rewards[job_id].ad_claimed) or ad_receipts.has(receipt_id): return
	_verified_ads_waiting[job_id] = receipt_id
	var amount: float = float(completed_rewards[job_id].amount)
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


static func _bounded_integer(value: Variant, minimum: int = 0, maximum: int = Progression.MAX_COUNTER) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _bounded_money(value: Variant, minimum: float = 0.0, maximum: float = Progression.MAX_MONEY) -> bool:
	return Money.is_valid(value, minimum) and float(value) <= maximum and float(value) == floorf(float(value))


func _valid_progression_save(data: Dictionary) -> bool:
	if not _bounded_money(data.get("cash")) or not _bounded_integer(data.get("active_store"), 1, Progression.STORE_COUNT): return false
	if not _saved_payment_snapshot_valid(data.job_snapshot, int(data.active_store)): return false
	if not data.get("stores") is Dictionary or not data.stores.has("1") or not data.stores.has(str(int(data.active_store))): return false
	if data.stores.size() > Progression.STORE_COUNT: return false
	for key: Variant in data.stores:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 1 or int(key) > Progression.STORE_COUNT: return false
		for earlier in range(1, int(key)):
			if not data.stores.has(str(earlier)): return false
		var branch: Variant = data.stores[key]
		if not branch is Dictionary: return false
		if not _bounded_integer(branch.get("tool_level"), 0, 4) or not _bounded_integer(branch.get("bonzi_tier"), -1, 2): return false
		for wet_field: String in ["hose_level", "squeegee_level"]:
			if branch.has(wet_field) and not _bounded_integer(branch[wet_field], 0, 4): return false
		for field: String in ["bonzi_earned", "job_early_reward"]:
			if not _bounded_money(branch.get(field)): return false
		if branch.has("job_ad_boost") and not branch.job_ad_boost is bool: return false
		var boosted := bool(branch.get("job_ad_boost", false))
		if boosted:
			if str(branch.get("active_job_id", "")).is_empty() or float(branch.job_early_reward) > Progression.MAX_MONEY / 4.0: return false
			if not data.get("ad_receipts") is Dictionary or not data.ad_receipts.values().has(branch.active_job_id): return false
		if branch.has("job_cleaning_paid") or branch.has("job_cleaning_progress"):
			if not _bounded_money(branch.get("job_cleaning_paid"),0.0,float(branch.job_early_reward) * (2.0 if boosted else 1.0)) or not _unit_fraction(branch.get("job_cleaning_progress")): return false
			if str(branch.get("active_job_id", "")).is_empty() and (float(branch.job_cleaning_paid) != 0.0 or float(branch.job_cleaning_progress) != 0.0): return false
		for field: String in ["payout_level", "manual_jobs", "automated_jobs", "final_tool_jobs", "banked_orders"]:
			if not _bounded_integer(branch.get(field)): return false
		var rules_version := int(branch.get("room_rules_version", 0))
		if branch.has("room_upgrades") and not RoomUpgrades.valid_saved_levels(branch.room_upgrades, int(branch.payout_level), rules_version): return false
		if branch.has("room_rules_version"):
			if not _bounded_integer(branch.room_rules_version, 2, RoomUpgrades.RULES_VERSION): return false
			var scale := Progression.scale_for(int(key)) if rules_version == RoomUpgrades.RULES_VERSION else pow(8.0, int(key) - 1)
			var income_cap := Progression.reward_cap(int(key)) / 2.0 if rules_version == RoomUpgrades.RULES_VERSION else Progression.MAX_MONEY / 2.0
			if not branch.has("room_upgrades") or not _bounded_money(branch.get("room_base_early"), 20.0 * scale, income_cap): return false
			var saved_ids: Array = RoomUpgrades.IDS if rules_version >= 3 else RoomUpgrades.LEGACY_IDS
			if not branch.get("room_income_origins") is Dictionary or branch.room_income_origins.size() != saved_ids.size(): return false
			for id: String in saved_ids:
				var level_cap := Progression.room_level_cap(int(key)) if rules_version == RoomUpgrades.RULES_VERSION else (120 if rules_version == 3 else 15)
				if not _bounded_integer(branch.room_upgrades[id], 0, level_cap): return false
				if not _bounded_integer(branch.room_income_origins.get(id), 0, int(branch.room_upgrades[id])): return false
			if RoomUpgrades.early_reward(int(key), branch) <= 0: return false
		else:
			# Checkpoint fields without their marker must never be mistaken for an
			# old save and remigrated into another investment or visual award.
			if branch.has("room_base_early") or branch.has("room_income_origins"): return false
			if Progression.early_reward(int(key), int(branch.payout_level)) <= 0: return false
		if not _unit_fraction(branch.get("routine_remainder")) or float(branch.routine_remainder) >= 1.0: return false
		if not branch.get("active_job_id") is String or not branch.get("job_snapshot") is Dictionary: return false
		if not _saved_payment_snapshot_valid(branch.job_snapshot, int(key)): return false
		if not branch.get("job_started_with_final_tool") is bool or not branch.get("job_final_tool_used") is bool: return false
		if not str(branch.active_job_id).is_empty() and (float(branch.job_early_reward) <= 0 or float(branch.job_early_reward) > Progression.MAX_MONEY / 2): return false
		if rules_version == RoomUpgrades.RULES_VERSION and float(branch.job_early_reward) > Progression.reward_cap(int(key)) / 2.0: return false
	if not data.get("completed_rewards") is Dictionary or not data.get("ad_receipts") is Dictionary or not data.get("latest_reward_job") is String: return false
	for job: Variant in data.completed_rewards:
		var offer: Variant = data.completed_rewards[job]
		if not job is String or not offer is Dictionary: return false
		if not _bounded_money(offer.get("amount")) or not _bounded_integer(offer.get("store_id"), 1, Progression.STORE_COUNT) or not offer.get("ad_claimed") is bool: return false
		if float(offer.amount) == 0.0 and not bool(offer.ad_claimed): return false
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
	var payable := _payable_orders(whole, LEGACY_ROUTINE_REWARD)
	var income := payable * LEGACY_ROUTINE_REWARD
	routine_remainder = maxf(0.0, orders - float(whole))
	_branch().routine_remainder = routine_remainder
	_branch().banked_orders = whole - payable
	_branch().bonzi_earned = minf(Progression.MAX_MONEY, float(_branch().bonzi_earned) + income)
	_branch().automated_jobs = mini(Progression.MAX_COUNTER, int(_branch().automated_jobs) + payable)
	automated_jobs = mini(Progression.MAX_COUNTER, automated_jobs + payable)
	cash += income
