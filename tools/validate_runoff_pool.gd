extends SceneTree
## Direct, deterministic pool/lifetime regression. No scene, input or save writes.
const Streams := preload("res://scripts/squeegee_runoff_streams.gd")

var checks := 0
var failures := 0
var streams: Node3D


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Run this isolated validator with -- --shop-test")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func live_count() -> int:
	var count := 0
	for slot in streams.batch.instance_count:
		if streams.packet_debug(slot).active:
			count += 1
	return count


func same_resources(batch_id: int, mesh_id: int, material_id: int) -> bool:
	return streams.batch.get_instance_id() == batch_id and streams.batch.mesh.get_instance_id() == mesh_id and streams.material.get_instance_id() == material_id and streams.batch.instance_count == 16


func run() -> void:
	streams = Streams.new()
	root.add_child(streams)
	streams.setup()
	var batch_id: int = streams.batch.get_instance_id()
	var mesh_id: int = streams.batch.mesh.get_instance_id()
	var material_id: int = streams.material.get_instance_id()
	check(streams.batch.instance_count == 16, "Pool allocates exactly sixteen packet slots")
	check(not streams.is_alive() and live_count() == 0, "New pool contains no active water")
	check(not streams.node.visible and streams.batch.visible_instance_count == 0, "Empty pool is not drawn")

	# A notification alone cannot fund a packet: it needs positive power, a
	# valid planar direction and a supply timestamp within the short grace.
	streams.advance(1.0)
	streams.begin_sources(streams.clock_seconds)
	streams.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.0, streams.clock_seconds)
	streams.feed_source(Vector3.ZERO, Vector3.UP, 0.5, 0.8, streams.clock_seconds)
	streams.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.8, streams.clock_seconds - Streams.SOURCE_GRACE - 0.01)
	streams.end_sources()
	check(not streams.is_alive() and int(streams.debug_stats().emitted_packets) == 0, "Invalid, dry and stale supplies cannot emit")
	check(int(streams.debug_stats().source_updates) == 0, "Rejected non-supplies do not increment funding")
	streams.reset()

	# Distinct fixed-world mouths are farther apart than the merge tolerance.
	# Stagger births so one old slot can retire while every other slot survives.
	var origins: Array[Vector3] = []
	var directions: Array[Vector3] = []
	for slot in 16:
		if slot > 0:
			streams.advance(0.01)
		var center := Vector3(float(slot % 4) * 0.65 - 0.975, 0.071, float(floori(float(slot) / 4.0)) * 0.65 - 0.975)
		streams.begin_sources(streams.clock_seconds)
		streams.feed_source(center, Vector3.BACK, 0.5, 0.6, streams.clock_seconds)
		streams.end_sources()
		var packet: Dictionary = streams.packet_debug(slot)
		origins.append(packet.origin)
		directions.append(packet.direction)
	check(streams.is_alive() and live_count() == 16, "Sixteen separate mouths fill the fixed pool")
	check(int(streams.debug_stats().active_packets) == 16 and int(streams.debug_stats().emitted_packets) == 16, "Live and cumulative packet counts agree at capacity")
	check(streams.node.visible and streams.batch.visible_instance_count == 16, "Full pool draws its fixed instance count")

	streams.feed_source(Vector3(3.0, 0.071, 0.0), Vector3.RIGHT, 0.8, 0.8, streams.clock_seconds)
	check(int(streams.debug_stats().rejected_packets) == 1, "Seventeenth distinct source is safely rejected while full")
	check(live_count() == 16 and int(streams.debug_stats().emitted_packets) == 16, "Overflow neither grows the pool nor steals an active slot")
	var anchored := true
	for slot in 16:
		var packet: Dictionary = streams.packet_debug(slot)
		anchored = anchored and (packet.origin as Vector3).is_equal_approx(origins[slot]) and (packet.direction as Vector3).is_equal_approx(directions[slot])
	check(anchored, "Overflow leaves every active origin and direction anchored")
	check(same_resources(batch_id, mesh_id, material_id), "Saturation reuses the original mesh, material and batch")

	# Duplicate/reordered local supply while feeding must be idempotent, even
	# when its proposed center and width differ. Trail owns deduplication across
	# fully stopped packets through its persistent consumed perimeter bins.
	var first: Dictionary = streams.packet_debug(0)
	var updates: int = streams.debug_stats().source_updates
	var near_first: Vector3 = first.origin + Vector3(0.06, 0.071, 0.0)
	streams.feed_source(near_first, Vector3.BACK, 1.1, 0.9, first.supplied_at)
	streams.feed_source(near_first, Vector3.BACK, 1.1, 0.9, float(first.supplied_at) - 0.02)
	var unchanged: Dictionary = streams.packet_debug(0)
	check(int(streams.debug_stats().source_updates) == updates and int(streams.debug_stats().emitted_packets) == 16, "Duplicate and older supply timestamps cannot fund another update")
	check(is_equal_approx(float(unchanged.width), float(first.width)) and is_equal_approx(float(unchanged.supplied_at), float(first.supplied_at)), "Nonfresh feed cannot change width or extend local funding")
	check((unchanged.origin as Vector3).is_equal_approx(first.origin), "Nonfresh feed cannot move the old source")

	streams.advance(0.05)
	var before_update: Dictionary = streams.packet_debug(0)
	streams.feed_source(near_first, Vector3(0.08, 0.0, 1.0), 0.9, 0.9, streams.clock_seconds)
	var refreshed: Dictionary = streams.packet_debug(0)
	check(int(streams.debug_stats().source_updates) == updates + 1 and int(streams.debug_stats().emitted_packets) == 16, "Fresh nearby supply updates a matching packet instead of allocating")
	check((refreshed.origin as Vector3).is_equal_approx(origins[0]) and (refreshed.direction as Vector3).is_equal_approx(directions[0]), "Fresh source drift cannot move or turn water already emitted")
	check(is_equal_approx(float(refreshed.age), float(before_update.age)), "Fresh supply never restarts an existing packet's lifetime")
	check(float(refreshed.width) > float(first.width) and is_equal_approx(float(refreshed.supplied_at), streams.clock_seconds), "A real local update can widen and fund the anchored source")
	streams.begin_sources(streams.clock_seconds)
	streams.end_sources()
	check(int(streams.debug_stats().sources_this_frame) == 0, "Empty source pass does not invent supply")

	# Birth zero is offset by 25 ms. Just cross its expiry but not the second
	# packet's expiry, proving expired-slot reuse without touching live packets.
	streams.advance(Streams.LIFETIME - 0.025 + 0.005 - streams.clock_seconds)
	check(not streams.packet_debug(0).active and live_count() == 15, "Only the oldest packet retires at its own deadline")
	check(int(streams.debug_stats().active_packets) == 15 and streams.is_alive(), "Other packets keep the pool alive independently")
	streams.feed_source(Vector3(3.0, 0.071, 0.0), Vector3.RIGHT, 0.7, 0.8, streams.clock_seconds)
	var reused: Dictionary = streams.packet_debug(0)
	check(reused.active and (reused.origin as Vector3).is_equal_approx(Vector3(3.0, 0.0, 0.0)), "New source reuses the retired slot")
	check(float(reused.age) < 0.03 and float(reused.front_distance) < 0.16, "Reused slot starts with fresh age and short geometry")
	check(live_count() == 16 and int(streams.debug_stats().emitted_packets) == 17, "Reused slot restores capacity without allocating geometry")
	anchored = true
	for slot in range(1, 16):
		var packet: Dictionary = streams.packet_debug(slot)
		anchored = anchored and packet.active and (packet.origin as Vector3).is_equal_approx(origins[slot]) and (packet.direction as Vector3).is_equal_approx(directions[slot])
	check(anchored, "Slot reuse preserves every still-live packet")
	check(same_resources(batch_id, mesh_id, material_id), "Slot reuse preserves fixed renderer resources")

	# A long frame/time jump must retire all packets in one bounded advance.
	var prior_supply: float = streams.clock_seconds
	streams.advance(1000.0)
	check(not streams.is_alive() and live_count() == 0 and int(streams.debug_stats().active_packets) == 0, "Large delta retires all packets without remaining activity")
	check(not streams.node.visible and streams.batch.visible_instance_count == 0, "Large-delta expiry leaves no visible stale slots")
	streams.feed_source(Vector3(3.0, 0.071, 0.0), Vector3.RIGHT, 0.7, 0.8, prior_supply)
	check(not streams.is_alive() and int(streams.debug_stats().emitted_packets) == 17, "Expired timestamps cannot resurrect a retired packet")
	var before_negative: float = streams.clock_seconds
	streams.advance(-1.0)
	check(is_equal_approx(streams.clock_seconds, before_negative) and not streams.is_alive(), "Negative delta cannot rewind lifetime or resurrect water")

	streams.reset()
	check(not streams.is_alive() and live_count() == 0 and is_zero_approx(streams.clock_seconds), "Reset clears activity and the local clock")
	check(int(streams.debug_stats().emitted_packets) == 0 and int(streams.debug_stats().rejected_packets) == 0 and int(streams.debug_stats().source_updates) == 0, "Reset clears cumulative pool diagnostics")
	check(same_resources(batch_id, mesh_id, material_id), "Reset retains the original renderer resources")
	streams.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, 0.0)
	check(streams.is_alive() and live_count() == 1, "Fresh timestamp zero works after reset")
	streams.reset()
	check(not streams.is_alive() and live_count() == 0 and streams.batch.visible_instance_count == 0, "Reset also cancels an actively feeding packet immediately")
	check(same_resources(batch_id, mesh_id, material_id), "Repeated resets never replace the fixed pool")
	print("RUNOFF_POOL_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
