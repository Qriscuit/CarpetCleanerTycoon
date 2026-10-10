extends SceneTree
## Natural runoff retirement cues, caller-owned progress and cancellation.
## Requires the pinned Mono toolchain and -- --shop-test; headless is supported.
const Streams := preload("res://scripts/squeegee_runoff_streams.gd")
const Routes := preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var events: Array[Dictionary] = []
var pool: Node
var game: Node
var water: Node
var event_before_hidden := false

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Runoff timing validation requires -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RUNOFF TIMING: " + message)

func collect_event(packet_id: int, target: float) -> void:
	for slot in Streams.CAPACITY:
		var packet: Dictionary = pool.packet_debug(slot)
		if packet.active and int(packet.packet_id) == packet_id:
			event_before_hidden = true
	events.append({"id": packet_id, "target": target})

func advance_water(seconds: float) -> void:
	for _frame in ceili(seconds * 60.0):
		water._process(1.0 / 60.0)
	water.set_process(false)

func extract(a: Vector3, b: Vector3, target: float) -> void:
	var soil: Node = game.soil
	for step in 50:
		var start := a.lerp(b, float(step) / 50.0)
		var finish := a.lerp(b, float(step + 1) / 50.0)
		var before: float = soil.extraction_coverage_total
		soil.apply_squeegee_stroke(start, finish, 1.0 / 60.0)
		water.feed_stroke(start, finish, 1.0 / 60.0, maxf(0.0, soil.extraction_coverage_total - before), Vector3.BACK, 0.8, target)
		water._process(1.0 / 60.0)
		water.set_process(false)
	water.end_stroke()
	water.set_process(false)
	advance_water(0.12)

func prepare() -> void:
	game.reset_rug()
	game.select_rug(1)
	game._on_practice_tool_pressed(1)
	water.set_process(false)
	pool = water.trail.streams

func validate_pool() -> void:
	pool = Streams.new()
	root.add_child(pool)
	pool.setup()
	pool.runoff_retired.connect(collect_event)
	var batch_id: int = pool.batch.get_instance_id()
	var mesh_id: int = pool.batch.mesh.get_instance_id()
	pool.advance(3.0)
	check(events.is_empty(), "No supplied water means no retirement credit")
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.0, pool.clock_seconds, 1.0)
	pool.feed_source(Vector3.ZERO, Vector3.UP, 0.5, 1.0, pool.clock_seconds, 1.0)
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 1.0, pool.clock_seconds - 1.0, 1.0)
	pool.advance(3.0)
	check(events.is_empty() and not pool.is_alive(), "Dry, invalid and stale supplies cannot earn a disappearance")
	pool.reset()
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, pool.clock_seconds, 0.20)
	var original: Dictionary = pool.packet_debug(0)
	check(original.active and int(original.packet_id) > 0 and is_equal_approx(original.progress_target, 0.20), "A funded ribbon stores the supplied progress target")
	check(events.is_empty(), "Emitting water does not immediately retire it")
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, original.supplied_at, 0.95)
	check(is_equal_approx(pool.packet_debug(0).progress_target, 0.20), "A duplicate supply cannot raise the progress target")
	pool.advance(0.10)
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, pool.clock_seconds, 0.40)
	pool.advance(0.10)
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, pool.clock_seconds, 0.30)
	check(int(pool.packet_debug(0).packet_id) == int(original.packet_id) and is_equal_approx(pool.packet_debug(0).progress_target, 0.40), "Fresh updates preserve one ribbon identity and monotonic target")
	pool.advance(Streams.LIFETIME - float(pool.packet_debug(0).age) - 0.001)
	check(events.is_empty() and pool.packet_debug(0).active, "Credit waits until the ribbon's terminal disappearance")
	pool.advance(0.002)
	check(events.size() == 1 and int(events[0].id) == int(original.packet_id) and is_equal_approx(events[0].target, 0.40), "Natural disappearance emits exactly one latest target")
	check(not event_before_hidden and not pool.is_alive() and not pool.node.visible, "The retirement signal observes already hidden geometry")
	pool.advance(10.0)
	check(events.size() == 1, "Later idle time cannot repeat a retired reward cue")
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, pool.clock_seconds, 0.70)
	var canceled_id: int = pool.packet_debug(0).packet_id
	pool.reset()
	pool.advance(3.0)
	check(events.size() == 1, "Reset cancels active ribbons without a retirement signal")
	pool.feed_source(Vector3.ZERO, Vector3.BACK, 0.5, 0.6, pool.clock_seconds, 0.10)
	check(int(pool.packet_debug(0).packet_id) > canceled_id and is_equal_approx(pool.packet_debug(0).progress_target, 0.10), "Slot reuse after reset has a new identity and no old target")
	pool.advance(3.0)
	check(events.size() == 2 and is_equal_approx(events[1].target, 0.10), "Fresh post-reset water retires only its fresh target")
	pool.reset()
	events.clear()
	var expected: Dictionary = {}
	for slot in Streams.CAPACITY:
		var origin := Vector3(float(slot) * 0.65, 0.071, 0.0)
		var target := float(slot + 1) / float(Streams.CAPACITY)
		pool.feed_source(origin, Vector3.BACK, 0.5, 0.6, pool.clock_seconds, target)
		var id: int = pool.packet_debug(slot).packet_id
		expected[id] = target
	pool.feed_source(Vector3(-2.0, 0.071, 0.0), Vector3.LEFT, 0.5, 0.6, pool.clock_seconds, 1.0)
	check(pool.batch.instance_count == 16 and int(pool.rejected_packets) == 1, "Tracking never grows or steals from the fixed sixteen-ribbon pool")
	pool.advance(3.0)
	check(events.size() == expected.size(), "A full pool emits one cue per naturally disappearing ribbon")
	for event: Dictionary in events:
		check(expected.has(event.id) and is_equal_approx(expected.get(event.id, -1.0), event.target), "Every terminal target stays paired with its ribbon identity")
		check(event.target >= 0.0 and event.target <= 1.0, "Retirement targets remain normalized")
		if expected.has(event.id): expected.erase(event.id)
	check(expected.is_empty(), "No capacity overflow or cancellation manufactures a cue")
	check(pool.batch.get_instance_id() == batch_id and pool.batch.mesh.get_instance_id() == mesh_id, "Targets reuse the original batch and mesh")
	pool.free()
	pool = null
	events.clear()

func validate_real_water() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	var saved: Dictionary = state._capture_state().duplicate(true)
	var save_bytes := FileAccess.get_file_as_bytes(state._save_path)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	water = game.squeegee_water
	water.runoff_retired.connect(collect_event)
	prepare()
	check(not pool.is_alive() and events.is_empty(), "Pouring practice water does not create retirement rewards")
	extract(Vector3(-0.45, 0.067, -0.70), Vector3(-0.45, 0.067, 0.65), 0.25)
	advance_water(3.0)
	check(not pool.is_alive() and events.is_empty(), "Interior extraction alone invents no off-carpet runoff cue")
	extract(Vector3(-0.45, 0.067, 0.65), Vector3(-0.45, 0.067, 1.65), 0.35)
	check(pool.is_alive() and events.is_empty(), "Real edge extraction starts visible runoff before any payment cue")
	var clock_before: float = pool.clock_seconds
	water._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	advance_water(5.0)
	check(is_equal_approx(pool.clock_seconds, clock_before) and events.is_empty(), "Background time pauses runoff and cannot retire progress")
	water._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	water.set_process(false)
	advance_water(3.0)
	check(not events.is_empty() and not event_before_hidden, "Resumed natural disappearance forwards through the real water/trail hierarchy")
	var latest := 0.0
	for event: Dictionary in events: latest = maxf(latest, event.target)
	check(is_equal_approx(latest, 0.35), "Edge runoff includes the supplied eligible interior-plus-edge watermark")
	var after_count := events.size()
	water.trail.notify_extraction(Vector3(-0.45, 0.067, 1.65), 100.0, 0.90)
	advance_water(3.0)
	check(events.size() == after_count and not pool.is_alive(), "A notification with unchanged extraction arrays cannot create or pay runoff")
	prepare()
	extract(Vector3(0.45, 0.067, 0.70), Vector3(0.45, 0.067, 1.65), 0.60)
	check(pool.is_alive(), "Fresh extraction starts a cancelable runoff ribbon")
	water.reset()
	advance_water(3.0)
	check(events.size() == after_count and not pool.is_alive(), "Water reset forwards no canceled retirement and leaves no delayed cue")
	check(state._capture_state() == saved and FileAccess.get_file_as_bytes(state._save_path) == save_bytes, "Free Gym visual timing preserves paid state and save bytes")
	game.free()
	current_scene = null
	game = null
	water = null
	pool = null

func run() -> void:
	validate_pool()
	await validate_real_water()
	print("RUNOFF_EARNINGS_TIMING_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
