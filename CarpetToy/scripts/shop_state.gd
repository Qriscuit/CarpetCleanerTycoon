extends Node
## The Neighborhood Shop ledger. Each reward/build is committed before it is exposed.

signal changed

const SAVE_VERSION := 1
const SAVE_PATH := "user://neighborhood_shop_v1.json"
const OFFLINE_CAP_SECONDS := 8.0 * 60.0 * 60.0
const MANUAL_REWARD := 20
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

var _owned: Dictionary = {"hand_brush": true}
var _blueprints: Dictionary = {"hand_brush": true}
var _job_serial: int = 0
var _saved_wall: float = 0.0
var _last_ticks: int = 0
var _checkpoint_ticks: int = 0
var _save_path: String = ""
var _save_enabled: bool = true
var _application_paused: bool = false
# These overrides are ignored unless the process explicitly opts into isolated tests.
var _test_unix_time: float = -1.0
var _test_ticks_msec: int = -1


func _ready() -> void:
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
	# A live tick only changes these scalars. Keep the large rug snapshot out of
	# this per-frame path; _commit captures it only when a save is actually due.
	var old_cash := cash
	var old_automated_jobs := automated_jobs
	var old_remainder := routine_remainder
	var old_ticks := _last_ticks
	var deliveries := _settle_elapsed()
	# Persist partial progress periodically and whole deliveries immediately.
	if deliveries > 0 or _now_ticks() - _checkpoint_ticks >= 5000:
		if not _commit():
			cash = old_cash
			automated_jobs = old_automated_jobs
			routine_remainder = old_remainder
			_last_ticks = old_ticks
			return
	if deliveries > 0:
		changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		save_state()
		_application_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED and _application_paused:
		_resume_application()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_state()


func _resume_application() -> void:
	var before := _capture_state()
	# If a write fails, discarded hours must not reappear as uncapped online time.
	var retry_ticks := maxi(_last_ticks, _now_ticks() - int(OFFLINE_CAP_SECONDS * 1000.0))
	_settle_elapsed()
	_application_paused = false
	_finish_transaction(before, retry_ticks)


func owns(id: String) -> bool:
	return bool(_owned.get(id, false))


func blueprint_known(id: String) -> bool:
	return bool(_blueprints.get(id, false))


func build_cost(id: String) -> int:
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
	if not COSTS.has(id) or owns(id) or not blueprint_known(id):
		return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed() # The old machine works at the old rate right up to this purchase.
	if cash < build_cost(id):
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	cash -= build_cost(id)
	_owned[id] = true
	if id == "wide_brush":
		equipped_brush = id
	_refresh_blueprints()
	return _finish_transaction(before, old_ticks)


func output_per_hour() -> float:
	return minf(demand_per_hour(), capacity_per_hour())


func demand_per_hour() -> float:
	return 60.0 if owns("intake") else 40.0


func capacity_per_hour() -> float:
	if not owns("bonzi"):
		return 0.0
	return 45.0 if owns("bonzi_mk2") else 30.0


func bottleneck() -> String:
	if not owns("bonzi"):
		return "Build Bonzi to start routine orders"
	if demand_per_hour() < capacity_per_hour():
		return "Customer demand"
	return "Cleaner capacity"


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
	if not _valid_clearance(job_snapshot.get("unique_clearance", 0.0)) or not _valid_clearance(job_snapshot.get("surface_clearance", 0.0)):
		return false
	var before := _capture_state()
	var old_ticks := _last_ticks
	_settle_elapsed()
	cash += MANUAL_REWARD
	manual_jobs += 1
	active_job_id = ""
	job_snapshot = {}
	_refresh_blueprints()
	return _finish_transaction(before, old_ticks)


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


func _valid_clearance(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.9 and float(value) <= 1.0


func _refresh_blueprints() -> void:
	for id: String in GATES:
		if manual_jobs < int(GATES[id]):
			continue
		if id in ["bonzi_mk2", "intake"] and not owns("bonzi"):
			continue
		_blueprints[id] = true


func _settle_elapsed() -> int:
	var now := _now_ticks()
	var seconds := maxf(0.0, float(now - _last_ticks) / 1000.0)
	if _application_paused:
		seconds = minf(seconds, OFFLINE_CAP_SECONDS)
	_last_ticks = now
	var delivered := _produce(seconds)
	if _application_paused and owns("bonzi"):
		return_reward += delivered * ROUTINE_REWARD
		return_seconds += seconds
	return delivered


func _produce(seconds: float) -> int:
	var orders := routine_remainder + maxf(seconds, 0.0) * output_per_hour() / 3600.0
	var whole := int(floor(orders + 0.000000001))
	routine_remainder = maxf(0.0, orders - float(whole))
	automated_jobs += whole
	cash += whole * ROUTINE_REWARD
	return whole


func _finish_transaction(before: Dictionary, old_ticks: int) -> bool:
	if not _commit():
		_restore_state(before)
		_last_ticks = old_ticks
		return false
	changed.emit()
	return true


func _capture_state() -> Dictionary:
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


func _commit() -> bool:
	if not _save_enabled:
		return false
	var data := _capture_state()
	# Retain the wall-clock high water mark if the device clock moves backward.
	data["saved_wall"] = maxf(_saved_wall, _now_unix())
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
	if owns("bonzi") and elapsed > 0.0:
		return_reward += _produce(elapsed) * ROUTINE_REWARD
		return_seconds += elapsed
	# Save the credited return immediately, so reopening cannot collect it again.
	if not _commit():
		_restore_state(before)
		_save_enabled = false


func _valid_save(data: Dictionary) -> bool:
	if data.get("version") != SAVE_VERSION:
		return false
	for key: String in ["cash", "manual_jobs", "automated_jobs", "job_serial", "return_reward"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) != floor(float(value)):
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
