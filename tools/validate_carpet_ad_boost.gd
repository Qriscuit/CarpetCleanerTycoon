extends SceneTree
## Verified current-carpet boosts use real disposable saved ledgers, never ads.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

class Provider extends RefCounted:
	var available := true
	var starts := true
	var requests := 0
	var job := ""
	var nonce := ""
	var callback: Callable
	func is_rewarded_ad_available() -> bool: return available
	func request_verified_reward(id: String, token: String, result: Callable) -> bool:
		requests += 1
		job = id
		nonce = token
		callback = result
		return starts
	func verify_reward_receipt(id: String, token: String, receipt: Dictionary) -> bool:
		return id == job and token == nonce and receipt.get("verified") == true
	func resolve(receipt_id: Variant, verified: bool = true, status: String = "earned") -> void:
		callback.call(job, nonce, {"receipt_id":receipt_id,"verified":verified,"status":status})

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CARPET AD: " + message)

func fresh(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/carpet_ad_%d_%s.json" % [OS.get_process_id(),label]
	paths.append(state._save_path)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	check(state.reset_progress(), label + ": isolated ledger resets")
	return state

func reload_state(state: Node) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
	replacement._test_ticks_msec = 0
	replacement._test_unix_time = state._test_unix_time
	state.free()
	root.add_child(replacement)
	replacement.set_process(false)
	check(replacement._save_enabled, "The durable current-carpet ledger reloads")
	return replacement

func snapshot(fraction: float, eligible: float = -1.0) -> Dictionary:
	var result := {"unique_clearance":fraction,"surface_clearance":fraction,"dirt_marker":"same-carpet"}
	if eligible >= 0.0: result.earned_clearance = eligible
	return result

func attach(state: Node) -> Provider:
	var provider := Provider.new()
	check(state.register_reward_ad_provider(provider), "An explicitly verified test provider registers")
	return provider

func boost(state: Node, receipt: String) -> void:
	var provider := attach(state)
	check(state.request_carpet_reward_ad(state.active_job_id), "The current carpet requests its own verified video")
	provider.resolve(receipt)
	check(state.carpet_ad_offer().boosted and not state.carpet_ad_offer().requesting, "Verified activation leaves a durable active boost")

func check_base_settlement() -> void:
	var state := fresh("base")
	var job: String = state.start_job()
	var offer: Dictionary = state.carpet_ad_offer()
	check(offer.job_id == job and offer.full_reward == 40.0 and offer.boosted_full_reward == 80.0 and not offer.boosted and not offer.available and not offer.provider_available, "Without a provider, only a locked real current-carpet offer exists")
	check(not state.request_carpet_reward_ad() and not state.request_reward_ad() and state.cash == 0.0, "No installed provider produces no fake video or reward")
	check(state.record_cleaning_progress(job,snapshot(0.75)) == 15.0 and state.reward_for_current_job(snapshot(0.75)) == 5.0, "Proportional cleaning remains15 while early Finish settles the complete20 half")
	check(state.complete_job(job) and state.cash == 20.0 and state.completed_rewards[job].amount == 20.0, "Early Finish totals20 exactly once")
	check(not state.complete_job(job) and state.cash == 20.0, "The old carpet cannot replay settlement")
	for fraction: float in [0.75,0.85,0.9899]:
		check(State.manual_reward_for(snapshot(fraction)) == 20, "Static compatibility early tier is always the half quote")
	check(State.manual_reward_for(snapshot(0.7499)) == 0 and State.manual_reward_for(snapshot(0.99)) == 40 and State.manual_reward_for(snapshot(0.75,0.0)) == 20, "Settlement thresholds stay75/99 and eligible installments do not reduce the early total")
	job = state.start_job()
	check(state.record_cleaning_progress(job,snapshot(0.25)) == 5.0 and state.reward_for_current_job(snapshot(0.99)) == 35.0, "Full settlement subtracts every already-paid cleaning coin")
	check(not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty() and state.cash == 60.0, "A normal complete carpet totals40 and reserves a fresh unboosted carpet")
	check(not state.carpet_ad_offer().boosted and state._branch().job_cleaning_paid == 0.0, "Each replacement starts with fresh paid and boost marks")
	state.free()

func check_verification_and_top_up() -> void:
	var state := fresh("verified")
	var job: String = state.start_job()
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 10.0, "Already removed dirt earns10 before watching")
	var provider := attach(state)
	var notifications: Array[String] = []
	var grants: Array[float] = []
	state.changed.connect(func(): notifications.append("changed"))
	state.carpet_ad_reward_granted.connect(func(amount: float):
		grants.append(amount)
		notifications.append("granted")
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._save_path))
		check(disk.stores["1"].job_ad_boost and disk.cash == state.cash and disk.ad_receipts.has("current-valid"), "The boost signal exposes only committed flag, receipt and money")
	)
	provider.available = false
	check(not state.request_carpet_reward_ad() and not state.carpet_ad_offer().available and provider.requests == 0, "An unavailable provider cannot start a video")
	provider.available = true
	provider.starts = false
	check(not state.request_carpet_reward_ad() and not state.carpet_ad_offer().requesting and state.carpet_ad_offer().available, "A launch failure immediately restores the available offer")
	provider.starts = true
	check(state.request_carpet_reward_ad(job) and not state.request_carpet_reward_ad(job) and state.carpet_ad_offer().requesting, "Only one verified video may be pending for the current carpet")
	provider.callback.call(job,"wrong-nonce",{"receipt_id":"forged","verified":true})
	provider.callback.call("wrong-job",provider.nonce,{"receipt_id":"forged","verified":true})
	check(state.cash == 10.0 and state.carpet_ad_offer().requesting and grants.is_empty(), "Wrong job or nonce grants nothing and preserves the genuine pending request")
	var before: Dictionary = state._capture_state()
	for status: String in ["skipped","failed","cancelled"]:
		if not state.carpet_ad_offer().requesting: check(state.request_carpet_reward_ad(job), "A stopped video can be retried")
		var count_before := notifications.size()
		provider.resolve("interrupted-" + status,true,status)
		check(state._capture_state() == before and not state.carpet_ad_offer().requesting and state.carpet_ad_offer().available and notifications.size() > count_before, "Explicit " + status + " restores READY without payout or stuck REQUESTING")
	for invalid: Variant in ["",123,"unverified"]:
		check(state.request_carpet_reward_ad(job), "A rejected receipt can request again")
		provider.resolve(invalid,not (invalid is String and invalid == "unverified"))
		check(state._capture_state() == before and state.carpet_ad_offer().available and not state.carpet_ad_offer().requesting, "An empty, malformed or unverified receipt never activates the boost")
	check(state.request_carpet_reward_ad(job), "A valid receipt gets a fresh nonce")
	notifications.clear()
	provider.resolve("current-valid")
	check(state.cash == 20.0 and state._branch().job_cleaning_paid == 20.0 and state.current_job_full_reward() == 80.0 and state._branch().job_early_reward == 20.0, "Verification tops up10 once and doubles the quote while keeping its normal base")
	check(grants == [10.0] and notifications[0] == "granted" and notifications[1] == "changed", "Cosmetic top-up is announced before general wallet sync")
	check(state.job_snapshot == before.job_snapshot and state._branch().job_cleaning_progress == 0.5, "Boosting preserves the real carpet, dirt snapshot and removal watermark")
	provider.resolve("current-valid")
	check(not state.request_carpet_reward_ad(job) and state.cash == 20.0 and grants.size() == 1, "Replayed callbacks and repeated taps cannot activate or top up twice")
	state = reload_state(state)
	check(state.active_job_id == job and state.carpet_ad_offer().boosted and not state.carpet_ad_offer().available and state.cash == 20.0 and state.current_job_full_reward() == 80.0, "The same carpet retains its2x boost across a provider-free reload")
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 0.0 and state.record_cleaning_progress(job,snapshot(0.75)) == 10.0 and state.reward_for_current_job(snapshot(0.75)) == 10.0, "Future proportional cleaning and early settlement both use the doubled half budget")
	check(not state.complete_and_start_next_job(job,snapshot(0.75)).is_empty() and state.cash == 40.0 and state.completed_rewards[job].amount == 40.0 and state.completed_rewards[job].ad_claimed, "Boosted early total40 cannot acquire a second legacy completed-receipt boost")
	check(not state.carpet_ad_offer().boosted and not state.request_reward_ad(job), "The boost ends with its carpet and remains consumed in legacy receipts")
	state.free()

func check_completion_and_upgrade() -> void:
	var state := fresh("full_boost")
	var job: String = state.start_job()
	boost(state,"full-zero")
	check(state.cash == 0.0 and state._branch().job_cleaning_paid == 0.0, "Watching before any removal activates2x without manufacturing an immediate cash award")
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 20.0 and state.reward_for_current_job(snapshot(0.99)) == 60.0, "The boosted full quote subtracts its doubled first installment")
	check(not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty() and state.cash == 80.0 and state.completed_rewards[job].amount == 80.0, "Boosted99% totals exactly80")
	job = state.active_job_id
	boost(state,"early-no-removal")
	check(state.reward_for_current_job(snapshot(0.75,0.0)) == 40.0 and not state.complete_and_start_next_job(job,snapshot(0.75,0.0)).is_empty() and state.cash == 120.0, "A boosted early Finish settles40 even when deferred disappearance has not paid installments")
	job = state.active_job_id
	boost(state,"renovation")
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 20.0, "The renovation fixture has already-paid boosted work")
	state.cash = 1000.0
	check(state.save_state() and state.buy_room_upgrade("floor"), "A real priced room upgrade applies to the current carpet")
	check(state._branch().job_early_reward == 23.0 and state.current_job_full_reward() == 92.0 and state.carpet_ad_offer().boosted_full_reward == 92.0, "Renovation raises the normal base and retains the same2x multiplier")
	var cash_after: float = state.cash
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 0.0 and state.cash == cash_after, "Upgrading does not replay old removal")
	check(state.record_cleaning_progress(job,snapshot(0.75)) == 14.0 and state.reward_for_current_job(snapshot(0.99)) == 58.0, "New removal catches up at the renovated boosted rate and full settlement deducts all paid work")
	state = reload_state(state)
	check(state.current_job_full_reward() == 92.0 and state._branch().job_cleaning_paid == 34.0, "Upgraded quote and boosted paid history survive reload")
	state.stores["2"] = Rules.new_branch(2)
	check(state.select_store(2), "A separately owned store can be visited")
	state.start_job()
	check(not state.carpet_ad_offer().boosted and state.select_store(1) and state.active_job_id == job and state.carpet_ad_offer().boosted, "Travel keeps the boost local to its reserved carpet")
	check(not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty() and state.cash == cash_after + 72.0 and state.current_job_full_reward() == 46.0, "Completion pays the rest once and the next renovated carpet returns to its unboosted46 quote")
	state.free()

func check_stale_and_replayed_results() -> void:
	var state := fresh("stale")
	var job: String = state.start_job()
	var provider := attach(state)
	check(not state.request_carpet_reward_ad("wrong-job") and provider.requests == 0, "A stale caller cannot launch a current-carpet video")
	check(state.request_carpet_reward_ad(job), "The pending completion fixture requests a video")
	check(not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty(), "The old carpet can settle before an asynchronous callback arrives")
	var before: Dictionary = state._capture_state()
	provider.resolve("too-late")
	check(state._capture_state() == before and state.cash == 40.0 and not state.carpet_ad_offer().boosted and not state.completed_rewards[job].ad_claimed, "A late current-carpet callback cannot boost its replacement or fall back to the completed receipt")
	job = state.active_job_id
	check(state.request_carpet_reward_ad(job), "A travel fixture starts in its original store")
	state.stores["2"] = Rules.new_branch(2)
	check(state.select_store(2), "The video callback is now in another store")
	state.start_job()
	before = state._capture_state()
	provider.resolve("wrong-store")
	check(state._capture_state() == before and state.select_store(1) and not state.carpet_ad_offer().boosted, "Verified callbacks are also bound to the requesting store")
	check(state.request_carpet_reward_ad(job), "The original carpet may request a new video after returning")
	provider.resolve("unique-receipt")
	check(state.carpet_ad_offer().boosted and state.ad_receipts["unique-receipt"] == job, "A current verified receipt is consumed globally")
	state.complete_and_start_next_job(job,snapshot(0.99))
	check(state.request_carpet_reward_ad(), "A new carpet starts its own request")
	before = state._capture_state()
	provider.resolve("unique-receipt")
	check(state._capture_state() == before and not state.carpet_ad_offer().boosted and state.carpet_ad_offer().available, "Reusing a signed receipt on another carpet is rejected and recovers READY")
	state.free()

func check_atomic_failure_and_migration() -> void:
	var state := fresh("atomic")
	var job: String = state.start_job()
	state.record_cleaning_progress(job,snapshot(0.5))
	var provider := attach(state)
	check(state.request_carpet_reward_ad(job), "The atomic save fixture starts a real verification request")
	var before: Dictionary = state._capture_state()
	var disk := FileAccess.get_file_as_string(state._save_path)
	state._save_enabled = false
	provider.resolve("retry-save")
	check(state._capture_state() == before and FileAccess.get_file_as_string(state._save_path) == disk and not state.carpet_ad_offer().boosted, "A failed commit rolls back wallet, doubled payment mark, receipt and flag together")
	state._save_enabled = true
	provider.available = false
	var requests := provider.requests
	check(state.carpet_ad_offer().available and state.request_carpet_reward_ad(job) and provider.requests == requests and state.cash == 20.0, "An already-verified result retries storage without another video or available provider")
	state = reload_state(state)
	check(state._branch().job_ad_boost and state._branch().job_cleaning_paid == 20.0 and state.ad_receipts.has("retry-save"), "Only the successful atomic retry becomes durable")
	state.free()
	state = fresh("overflow")
	job = state.start_job()
	state.record_cleaning_progress(job,snapshot(0.5))
	state.cash = Rules.MAX_MONEY
	state.save_state()
	provider = attach(state)
	state.request_carpet_reward_ad(job)
	before = state._capture_state()
	provider.resolve("wallet-overflow")
	check(state._capture_state() == before and not state.carpet_ad_offer().boosted and not state.ad_receipts.has("wallet-overflow"), "Wallet overflow retains the paid history and verified boost for a safe retry")
	state.cash = 0.0
	state.save_state()
	check(state.request_carpet_reward_ad(job) and state.cash == 10.0 and state._branch().job_cleaning_paid == 20.0, "After spending, the same verified receipt tops up only the saved10 cleaning coins")
	var valid: Dictionary = state._capture_state()
	check(state._valid_save(valid), "The boosted ledger accepts paid history up to its doubled half budget")
	for invalid: Variant in [0,1,"true",null]:
		var bad := valid.duplicate(true)
		bad.stores["1"].job_ad_boost = invalid
		check(not state._valid_save(bad), "Saved boost flags require actual booleans")
	var bad := valid.duplicate(true)
	bad.ad_receipts.clear()
	check(not state._valid_save(bad), "A saved boost needs its durable verified receipt")
	bad = valid.duplicate(true)
	bad.stores["1"].job_cleaning_paid = 41.0
	check(not state._valid_save(bad), "Even a boosted save cannot exceed its40 cleaning-half budget")
	bad = valid.duplicate(true)
	bad.stores["1"].active_job_id = ""
	check(not state._valid_save(bad), "An empty carpet reservation cannot retain an active boost")
	state.free()
	state = fresh("migration")
	job = state.start_job()
	state.record_cleaning_progress(job,snapshot(0.5))
	var legacy: Dictionary = state._capture_state()
	legacy.stores["1"].erase("job_ad_boost")
	var file := FileAccess.open(state._save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy,"",true,true))
	file.close()
	state = reload_state(state)
	check(state.active_job_id == job and state.cash == 10.0 and state.job_snapshot.dirt_marker == "same-carpet" and not state._branch().job_ad_boost and state._branch().job_cleaning_paid == 10.0, "Existing unfinished saves default unboosted while preserving cash, dirt and payment history")
	state.free()

func check_legacy_completed_compatibility() -> void:
	var state := fresh("legacy")
	var job: String = state.start_job()
	state.complete_and_start_next_job(job,snapshot(0.99))
	var provider := attach(state)
	var received: Array[float] = []
	state.ad_reward_granted.connect(func(amount: float): received.append(amount))
	check(state.reward_offer().available and state.request_reward_ad(job), "The legacy verified completed-receipt API remains compatible")
	provider.resolve("legacy-completed")
	check(state.cash == 80.0 and received == [40.0] and not state.carpet_ad_offer().boosted and not state.request_reward_ad(job), "Legacy rewards stay separate from current carpet flags and consume one receipt")
	state.free()

func check_file_failure_and_provider_replacement() -> void:
	var state := fresh("file_failure")
	var job: String = state.start_job()
	state.record_cleaning_progress(job,snapshot(0.5))
	state._branch().bonzi_tier = 0
	state.save_state()
	var provider := attach(state)
	state.request_carpet_reward_ad(job)
	var before: Dictionary = state._capture_state()
	var disk := FileAccess.get_file_as_string(state._save_path)
	var real_path: String = state._save_path
	var old_ticks: int = state._last_ticks
	state._test_ticks_msec += 120000
	state._test_unix_time += 120.0
	state._save_path = "res://.godot/carpet_ad_missing_%d/ledger.json" % OS.get_process_id()
	provider.resolve("real-file-retry")
	check(state._capture_state() == before and state._last_ticks == old_ticks and FileAccess.get_file_as_string(real_path) == disk, "A real file-open failure rolls back both ad top-up and elapsed independent Bonzi income")
	check(state.complete_and_start_next_job(job,snapshot(0.75)).is_empty() and state._capture_state() == before, "A subsequent failed completion cannot consume the waiting verified receipt")
	state._save_path = real_path
	var requests := provider.requests
	check(state.request_carpet_reward_ad(job) and provider.requests == requests and state.cash == 60.0 and state.automated_jobs == 1 and state._branch().job_cleaning_paid == 20.0, "Storage recovery commits one Bonzi order and one verified top-up without replaying either")
	state = reload_state(state)
	check(state.cash == 60.0 and state.carpet_ad_offer().boosted and state.automated_jobs == 1, "The recovered real file contains the entire committed transaction")
	state.free()
	state = fresh("provider_replaced")
	job = state.start_job()
	var old_provider := attach(state)
	state.request_carpet_reward_ad(job)
	provider = attach(state)
	check(not state.carpet_ad_offer().requesting and state.carpet_ad_offer().available, "Replacing a provider cancels its pending nonce and restores READY")
	old_provider.resolve("replaced-provider")
	check(not state.carpet_ad_offer().boosted and not state.ad_receipts.has("replaced-provider"), "The replaced provider's callback cannot activate a current request")
	check(state.request_carpet_reward_ad(job), "The new provider receives a fresh request")
	provider.resolve("new-provider")
	check(state.carpet_ad_offer().boosted and state.ad_receipts.has("new-provider"), "Only the new provider's verified nonce activates the carpet")
	state.free()

func check_large_boost() -> void:
	var state := fresh("large")
	for store: int in range(2,7): state.stores[str(store)] = Rules.new_branch(store)
	var branch: Dictionary = state.stores["6"]
	Room.migrate_branch(6,branch)
	for id: String in Room.IDS: branch.room_upgrades[id] = Rules.room_level_cap(6)
	branch.payout_level = Room.total_levels(branch.room_upgrades)
	check(state.select_store(6), "The actual sixth-store max economy is selected")
	var job: String = state.start_job()
	check(state.current_job_full_reward() == 4e32 and state.record_cleaning_progress(job,snapshot(0.25)) > 0.0, "The normal400AF quote pays an initial finite installment")
	var original_paid: float = state._branch().job_cleaning_paid
	boost(state,"large-boost")
	check(state.current_job_full_reward() == 8e32 and state._branch().job_cleaning_paid == original_paid * 2.0 and state.cash == original_paid * 2.0, "A verified AF boost doubles saved paid money and the complete quote without int64 conversion")
	for step: int in range(26,100):
		var delta: float = state.record_cleaning_progress(job,snapshot(float(step) / 100.0))
		check(delta >= 0.0 and is_finite(delta) and delta == floorf(delta) and state._branch().job_cleaning_paid <= 4e32, "Every AF installment remains finite and within the doubled half budget")
	state = reload_state(state)
	check(state.current_job_full_reward() == 8e32 and state._branch().job_cleaning_paid == 4e32 and state.record_cleaning_progress(job,snapshot(0.99)) == 0.0, "AF boost and exact first-half endpoint persist without payment replay")
	check(not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty() and absf(state.cash / 8e32 - 1.0) < 1e-14 and state.completed_rewards[job].amount == 8e32 and state.current_job_full_reward() == 4e32, "AF full settlement totals the doubled quote once and clears the multiplier on the next carpet")
	state.free()

func run() -> void:
	check_base_settlement()
	check_verification_and_top_up()
	check_completion_and_upgrade()
	check_stale_and_replayed_results()
	check_atomic_failure_and_migration()
	check_legacy_completed_compatibility()
	check_file_failure_and_provider_replacement()
	check_large_boost()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("CARPET_AD_BOOST_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
