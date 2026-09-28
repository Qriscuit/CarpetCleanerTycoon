extends SceneTree
## Frozen 10 Hz soak payloads versus bounded FIFO dispatch across render updates.
const Soak := preload("res://scripts/water_soak.gd")
const Footprint := preload("res://scripts/rug_footprint.gd")
const Profile := preload("res://scripts/water_hose_profile.gd")
const SPOTS := [Vector3(-0.65, 0, -0.8), Vector3(0, 0, -0.8), Vector3(0.65, 0, -0.8), Vector3(-0.65, 0, 0.8), Vector3(0, 0, 0.8), Vector3(0.65, 0, 0.8)]
var checks := 0
var failures := 0

class OriginalSoak:
	extends "res://scripts/water_soak.gd"

	func update(delta: float) -> void:
		# Original synchronous dispatcher as of 2026-09-27.
		var step := clampf(delta, 0.0, 0.10)
		if step <= 0.0:
			return
		clock_seconds += step
		var living := false
		for slot in CAPACITY:
			if active[slot] == 0:
				continue
			if clock_seconds - last_feed_times[slot] >= AFTER_SOAK_SECONDS:
				active[slot] = 0
			else:
				living = true
		if not living:
			deposit_accumulator = 0.0
			return
		deposit_accumulator += step
		if deposit_accumulator + 0.000001 < DEPOSIT_INTERVAL:
			return
		var elapsed := DEPOSIT_INTERVAL
		deposit_accumulator = maxf(0.0, deposit_accumulator - DEPOSIT_INTERVAL)
		var emission_generation := generation
		for slot in CAPACITY:
			if active[slot] == 0:
				continue
			var since_feed := maxf(0.0, clock_seconds - last_feed_times[slot])
			var fade := 1.0 - smoothstep(0.0, AFTER_SOAK_SECONDS, since_feed)
			var strength := _strength_per_second(fed_durations[slot]) * elapsed * fade
			if strength <= 0.000001:
				continue
			emitted_events += 1
			soak_contact.emit(positions[slot], radii[slot], strength)
			if generation != emission_generation:
				return

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Refusing to run without --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func make_soak(original: bool = false) -> RefCounted:
	var soak := OriginalSoak.new() if original else Soak.new()
	soak.setup(Footprint.new())
	soak.set_profile(Profile.for_level(Profile.MAX_LEVEL))
	return soak

func record(soak: RefCounted, events: Array, timing: Dictionary = {}) -> void:
	soak.soak_contact.connect(func(position: Vector3, radius: float, strength: float):
		events.append({"position": position, "radius": radius, "strength": strength, "time": soak.clock_seconds, "step": timing.get("step", 0.1)})
	)

func disconnect_recorders(soak: RefCounted) -> void:
	# Recording callbacks capture the RefCounted source for its timestamp.
	# Break that test-only reference cycle before each fixture is released.
	for connection in soak.soak_contact.get_connections():
		soak.soak_contact.disconnect(connection.callable)

func compare_events(actual: Array, original: Array, label: String, immediate: bool = false) -> void:
	check(actual.size() == original.size(), "No lost or duplicated stamps: " + label)
	var largest_delay := 0.0
	for i in mini(actual.size(), original.size()):
		check(actual[i].position == original[i].position and actual[i].radius == original[i].radius and actual[i].strength == original[i].strength, "Exact FIFO payload %d: %s" % [i, label])
		var delay: float = actual[i].time - original[i].time
		largest_delay = maxf(largest_delay, delay)
		# A render update can overshoot the nominal deadline; there is no work
		# opportunity between those updates. Fixed-rate cases remain <100 ms.
		check(delay >= -0.000001 and delay <= 0.100001 + float(actual[i].step), "At most one tick plus render granularity %d: %s" % [i, label])
		if immediate:
			check(delay == 0.0, "Stationary single reservoir retains immediate cadence %d: %s" % [i, label])
	print("SOAK_SCHEDULING profile=%s events=%d max_delay_ms=%.3f" % [label, actual.size(), largest_delay * 1000.0])

func feed_fixture(soak: RefCounted, frame: int, step: float, reuse: bool, single: bool) -> void:
	if single:
		soak.feed(Vector3.ZERO, step)
	elif reuse:
		# Different positions overwrite full-pool slots while old stamps wait.
		for i in 3:
			var angle := float(frame * 3 + i) * 0.37
			soak.feed(Vector3(cos(angle) * 0.77, 0.0, sin(angle) * 1.27), maxf(step, 0.008))
	else:
		for spot in SPOTS:
			soak.feed(spot, step)

func run_fixture(label: String, steps: Array, reuse: bool = false, single: bool = false) -> void:
	var actual := make_soak()
	var reference := make_soak(true)
	var actual_events: Array = []
	var reference_events: Array = []
	var timing := {"step": 0.0}
	record(actual, actual_events, timing)
	record(reference, reference_events)
	var peak_pending := 0
	var peak_dispatch := 0
	for frame in 420:
		var delta: float = steps[frame % steps.size()]
		var step := clampf(delta, 0.0, 0.1)
		timing.step = step
		for soak in [actual, reference]:
			feed_fixture(soak, frame, step, reuse, single)
		var before := actual_events.size()
		reference.update(delta)
		actual.update(delta)
		var dispatched := actual_events.size() - before
		var budget := clampi(ceili(Soak.CAPACITY * step / Soak.DEPOSIT_INTERVAL), 1, Soak.CAPACITY) if step > 0.0 else 0
		peak_dispatch = maxi(peak_dispatch, dispatched)
		peak_pending = maxi(peak_pending, actual.pending_count)
		check(dispatched <= budget, "Bounded per-update mask work: %s frame%d" % [label, frame])
		check(actual.pending_count >= 0 and actual.pending_count <= Soak.PENDING_CAPACITY and actual.pending_positions.size() == Soak.PENDING_CAPACITY, "Fixed queue storage: %s frame%d" % [label, frame])
		check(actual.clock_seconds == reference.clock_seconds and actual.deposit_accumulator == reference.deposit_accumulator, "Original calculation tick: %s frame%d" % [label, frame])
		check(actual.positions == reference.positions and actual.radii == reference.radii and actual.fed_durations == reference.fed_durations and actual.active == reference.active, "Original reservoir state: %s frame%d" % [label, frame])
	for frame in 80:
		timing.step = 1.0 / 60.0
		reference.update(1.0 / 60.0)
		actual.update(1.0 / 60.0)
	check(not actual.is_alive() and actual.pending_count == 0 and not actual.debug_stats().processing, "Reservoirs and final queued stamps retire: " + label)
	check(actual.emitted_events == actual_events.size(), "Emission counter counts dispatch, not queue creation: " + label)
	compare_events(actual_events, reference_events, label, single)
	print("SOAK_BUDGET profile=%s max_dispatched=%d peak_pending=%d" % [label, peak_dispatch, peak_pending])
	disconnect_recorders(actual)
	disconnect_recorders(reference)

func prime_pending(soak: RefCounted) -> void:
	for spot in SPOTS:
		soak.feed(spot, 0.5)
	for frame in 6:
		soak.update(1.0 / 60.0)
	check(soak.pending_count == 5, "Six-reservoir tick leaves five queued after first 60 Hz dispatch")

func check_lifecycle() -> void:
	for action in ["reset", "setup", "profile"]:
		var soak := make_soak()
		var events: Array = []
		record(soak, events)
		prime_pending(soak)
		var before := events.size()
		var old_generation: int = soak.generation
		if action == "reset":
			soak.reset()
		elif action == "setup":
			soak.setup(null)
		else:
			soak.set_profile(Profile.for_level(0))
		check(soak.pending_count == 0 and soak.generation > old_generation, "Queued stamps invalidated on " + action)
		soak.update(0.001)
		check(events.size() == before, "No stale queued stamp after " + action)
		if action != "profile":
			check(not soak.is_alive(), "Reset/setup invalidation sleeps")
		disconnect_recorders(soak)
	for action in ["reset", "profile", "setup"]:
		var soak := make_soak()
		var state := {"count": 0}
		soak.soak_contact.connect(func(_p: Vector3, _r: float, _s: float):
			state.count += 1
			if action == "reset":
				soak.reset()
			elif action == "profile":
				soak.set_profile(Profile.for_level(0))
			else:
				soak.setup(null)
		)
		for spot in SPOTS:
			soak.feed(spot, 0.5)
		soak.update(0.1)
		check(state.count == 1 and soak.pending_count == 0, "Synchronous " + action + " cancels remaining callbacks")
		disconnect_recorders(soak)
	var soak := make_soak()
	var events: Array = []
	record(soak, events)
	for spot in SPOTS:
		soak.feed(spot, 0.5)
	soak.clock_seconds = 0.64
	soak.deposit_accumulator = 0.09
	soak.update(1.0 / 60.0)
	check(soak.pending_count == 5, "Queue can remain close to reservoir expiry")
	soak.update(0.06)
	check(soak.active.count(1) == 0 and soak.pending_count == 1 and soak.is_alive() and soak.debug_stats().processing, "Pending stamps keep effect alive after reservoir expiry")
	var before := events.size()
	var old_clock: float = soak.clock_seconds
	soak.update(0.0)
	soak.update(-1.0)
	check(events.size() == before and soak.pending_count == 1 and soak.clock_seconds == old_clock, "Zero/negative delta neither advances nor drains")
	soak.update(1.0 / 60.0)
	check(events.size() == 6 and not soak.is_alive() and soak.pending_count == 0, "Last queued stamp drains after all reservoirs expire")
	soak.reset()
	for spot in SPOTS:
		soak.feed(spot, 0.5)
	before = events.size()
	soak.update(20.0)
	check(is_equal_approx(soak.clock_seconds, 0.1) and events.size() - before == 6 and soak.pending_count == 0, "Long delta clamps to original one-tick/six-stamp maximum")
	soak.reset()
	soak.feed(Vector3(4, 0, 4), 0.5)
	soak.update(0.1)
	check(not soak.is_alive() and soak.emitted_events == 0, "Off-carpet feeds cannot create queued deposits")
	disconnect_recorders(soak)

func run() -> void:
	for fps in [15.0, 30.0, 60.0, 120.0]:
		run_fixture("six_spots_%dHz" % int(fps), [1.0 / fps])
		run_fixture("single_%dHz" % int(fps), [1.0 / fps], false, true)
	run_fixture("jitter", [0.001, 0.031, 0.016, 0.071, 0.033, 0.005, 0.099])
	run_fixture("zero_long_delta", [0.0, 0.016, 0.35, 0.001, -0.1, 0.1, 0.009])
	run_fixture("rapid_pool_reuse", [1.0 / 60.0], true)
	run_fixture("jitter_pool_reuse", [0.001, 0.031, 0.016, 0.071, 0.033, 0.005, 0.099], true)
	check_lifecycle()
	print("SOAK_SCHEDULING_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
