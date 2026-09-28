extends RefCounted
## A few anchored capillary reservoirs, not a fluid simulation. The carpet owns
## the actual wet mask; this component only emits bounded, soft soak deposits.

signal soak_contact(world_position: Vector3, radius: float, strength: float)

const CAPACITY := 6
const DEPOSIT_INTERVAL := 0.10
const AFTER_SOAK_SECONDS := 0.70
const FEED_RAMP_SECONDS := 0.30
const HALO_STRENGTH_PER_SECOND := 2.40
const HOLD_RAMP_SECONDS := 1.50
const HOLD_STRENGTH_BOOST := 1.35
const MERGE_RADIUS_FRACTION := 0.45
const PENDING_CAPACITY := CAPACITY * 2

var footprint: RefCounted
var positions := PackedVector3Array()
var fed_durations := PackedFloat64Array()
var last_feed_times := PackedFloat64Array()
var radii := PackedFloat32Array()
var active := PackedByteArray()
var wet_radius := 0.26
var max_spread_radius := 0.70
var spread_speed := 0.55
var passive_soak_multiplier := 1.0
var clock_seconds := 0.0
var deposit_accumulator := 0.0
var emitted_events := 0
var generation := 0
var pending_positions := PackedVector3Array()
var pending_radii := PackedFloat32Array()
var pending_strengths := PackedFloat64Array()
var pending_head := 0
var pending_count := 0


func _init() -> void:
	positions.resize(CAPACITY)
	fed_durations.resize(CAPACITY)
	last_feed_times.resize(CAPACITY)
	radii.resize(CAPACITY)
	active.resize(CAPACITY)
	pending_positions.resize(PENDING_CAPACITY)
	pending_radii.resize(PENDING_CAPACITY)
	pending_strengths.resize(PENDING_CAPACITY)


func setup(rug_footprint: RefCounted) -> void:
	footprint = rug_footprint
	reset()


func set_profile(profile: Dictionary) -> void:
	# A queued stamp belongs to the profile that calculated it. Tool/profile
	# changes must not deliver an old-level deposit on a later render update.
	generation += 1
	_clear_pending()
	wet_radius = clampf(float(profile.get("wet_radius", 0.26)), 0.01, 1.5)
	max_spread_radius = clampf(float(profile.get("max_spread_radius", 0.70)), wet_radius, 1.5)
	spread_speed = clampf(float(profile.get("spread_speed", 0.55)), 0.01, 4.0)
	passive_soak_multiplier = clampf(float(profile.get("passive_soak_multiplier", 1.0)), 0.0, 5.0)
	for slot in CAPACITY:
		if active[slot] != 0:
			radii[slot] = _radius_for_duration(fed_durations[slot])


func feed(position: Vector3, duration: float) -> void:
	if duration <= 0.0 or footprint == null:
		return
	if not footprint.contains_point(Vector2(position.x, position.z)):
		return
	var slot := _find_slot(position)
	if active[slot] == 0 or clock_seconds - last_feed_times[slot] >= AFTER_SOAK_SECONDS:
		_start_slot(slot, position)
	elif positions[slot].distance_squared_to(position) > pow(wet_radius * MERGE_RADIUS_FRACTION, 2.0):
		# Full pool: reuse the oldest reservoir without dragging its grown area.
		_start_slot(slot, position)
	fed_durations[slot] += duration
	last_feed_times[slot] = clock_seconds
	radii[slot] = _radius_for_duration(fed_durations[slot])


func update(delta: float) -> void:
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
	else:
		deposit_accumulator += step
		if deposit_accumulator + 0.000001 >= DEPOSIT_INTERVAL:
			# Calculate exactly the original 0.1-second stamps at their original
			# tick. Snapshot payloads before pool reuse can move a reservoir.
			deposit_accumulator = maxf(0.0, deposit_accumulator - DEPOSIT_INTERVAL)
			for slot in CAPACITY:
				if active[slot] == 0:
					continue
				var since_feed := maxf(0.0, clock_seconds - last_feed_times[slot])
				var fade := 1.0 - smoothstep(0.0, AFTER_SOAK_SECONDS, since_feed)
				var strength := _strength_per_second(fed_durations[slot]) * DEPOSIT_INTERVAL * fade
				if strength <= 0.000001:
					continue
				assert(pending_count < PENDING_CAPACITY, "Passive soak queue exceeded its fixed bound")
				var tail := (pending_head + pending_count) % PENDING_CAPACITY
				pending_positions[tail] = positions[slot]
				pending_radii[tail] = radii[slot]
				pending_strengths[tail] = strength
				pending_count += 1
	# Spread expensive mask painting across render updates: one stamp at 60 Hz,
	# two at 30 Hz, at most six after a long frame. The service rate is at least
	# six per tick, so two ticks of fixed storage cover uneven frame boundaries.
	# A single stationary reservoir still paints immediately at its 10 Hz tick.
	var budget := clampi(ceili(CAPACITY * step / DEPOSIT_INTERVAL), 1, CAPACITY)
	var emission_generation := generation
	while pending_count > 0 and budget > 0:
		var head := pending_head
		pending_head = (pending_head + 1) % PENDING_CAPACITY
		pending_count -= 1
		budget -= 1
		emitted_events += 1
		soak_contact.emit(pending_positions[head], pending_radii[head], pending_strengths[head])
		# The final deposit can complete the carpet, synchronously resetting us.
		if generation != emission_generation:
			return


func reset() -> void:
	generation += 1
	_clear_pending()
	clock_seconds = 0.0
	deposit_accumulator = 0.0
	emitted_events = 0
	active.fill(0)
	fed_durations.fill(0.0)
	last_feed_times.fill(0.0)
	radii.fill(0.0)


func is_alive() -> bool:
	if pending_count > 0:
		return true
	for slot in CAPACITY:
		if active[slot] != 0:
			return true
	return false


func debug_stats() -> Dictionary:
	var active_spots := 0
	var largest_radius := 0.0
	var longest_feed := 0.0
	for slot in CAPACITY:
		if active[slot] == 0:
			continue
		active_spots += 1
		largest_radius = maxf(largest_radius, radii[slot])
		longest_feed = maxf(longest_feed, fed_durations[slot])
	return {
		"capacity": CAPACITY,
		"active_spots": active_spots,
		"max_radius": largest_radius,
		"max_fed_duration": longest_feed,
		"max_strength_per_second": _strength_per_second(longest_feed),
		"passive_soak_multiplier": passive_soak_multiplier,
		"emitted_events": emitted_events,
		"pending_events": pending_count,
		"pending_capacity": PENDING_CAPACITY,
		"processing": active_spots > 0 or pending_count > 0,
		"after_soak_seconds": AFTER_SOAK_SECONDS,
	}


func _clear_pending() -> void:
	pending_head = 0
	pending_count = 0


func _find_slot(position: Vector3) -> int:
	var nearest := -1
	var nearest_distance := pow(wet_radius * MERGE_RADIUS_FRACTION, 2.0)
	var available := -1
	var oldest := 0
	for slot in CAPACITY:
		if active[slot] == 0 or clock_seconds - last_feed_times[slot] >= AFTER_SOAK_SECONDS:
			if available == -1:
				available = slot
			continue
		var distance := positions[slot].distance_squared_to(position)
		if distance <= nearest_distance:
			nearest = slot
			nearest_distance = distance
		if last_feed_times[slot] < last_feed_times[oldest]:
			oldest = slot
	if nearest != -1:
		return nearest
	return available if available != -1 else oldest


func _start_slot(slot: int, position: Vector3) -> void:
	active[slot] = 1
	positions[slot] = position
	fed_durations[slot] = 0.0
	last_feed_times[slot] = clock_seconds
	radii[slot] = wet_radius


func _radius_for_duration(duration: float) -> float:
	return lerpf(wet_radius, max_spread_radius, 1.0 - exp(-spread_speed * duration))


func _strength_per_second(duration: float) -> float:
	var onset := smoothstep(0.0, FEED_RAMP_SECONDS, duration)
	var hold_boost := lerpf(1.0, HOLD_STRENGTH_BOOST, smoothstep(FEED_RAMP_SECONDS, HOLD_RAMP_SECONDS, duration))
	return HALO_STRENGTH_PER_SECOND * passive_soak_multiplier * onset * hold_boost
