extends Node3D
## World-space, finite-volume presentation of water actually removed by the blade.
## A fixed pool retains the old throw when the player turns or releases the tool.

const Impact := preload("res://scripts/squeegee_water_impact.gd")
const ROWS := 16
const LANES := 7
const CAPACITY := 3
const HISTORY := 96
const GRAVITY := 9.8
const RUG_Y := 0.071
const FLOOR_Y := 0.006
const MAX_FLIGHT := 0.68
const HEAD_HALF := Vector2(0.34, 0.075)

@export_range(0.8, 2.8, 0.01) var upward_speed := 1.98
@export_range(0.5, 2.5, 0.01) var forward_speed := 1.50
@export_range(0.01, 0.06, 0.001) var sheet_thickness := 0.034
@export_range(0.0, 0.015, 0.001) var ripple_height := 0.006

class Sheet:
	extends RefCounted
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var active := false
	var feeding := false
	var started := 0.0
	var stopped := 0.0
	var deadline := 0.0
	var head := 0
	var count := 0
	var times := PackedFloat32Array()
	var origins := PackedVector3Array()
	var velocities := PackedVector3Array()
	var sides := PackedVector3Array()
	var widths := PackedFloat32Array()
	var powers := PackedFloat32Array()
	var grid := PackedVector4Array()
	var previous := PackedVector3Array()
	var landings := PackedVector3Array()
	var landed := PackedByteArray()
	var origin := Vector3.ZERO
	var velocity := Vector3.ZERO
	var side := Vector3.RIGHT
	var width := 0.68
	var power := 0.0
	var direction := Vector3.FORWARD
	# Scratch sample, reused for each longitudinal ring.
	var sample_origin := Vector3.ZERO
	var sample_velocity := Vector3.ZERO
	var sample_side := Vector3.RIGHT
	var sample_width := 0.68
	var sample_power := 0.0

	func _init() -> void:
		times.resize(HISTORY)
		origins.resize(HISTORY)
		velocities.resize(HISTORY)
		sides.resize(HISTORY)
		widths.resize(HISTORY)
		powers.resize(HISTORY)
		grid.resize(ROWS * LANES)
		previous.resize(LANES)
		landings.resize(LANES)
		landed.resize(LANES)

var impact: Node3D
var footprint: RefCounted
var sheets: Array[Sheet] = []
var enabled := false
var clock_seconds := 0.0
var current := -1
var emitted_strokes := 0
var removed_water := 0.0
var surface_texture: ImageTexture
var pixel_area := 0.0

func _ready() -> void:
	set_process(false)

func setup(rug_footprint: RefCounted, surface_pixels: PackedByteArray, mask_size: Vector2i) -> void:
	assert(sheets.is_empty(), "Allocate the water pool once")
	footprint = rug_footprint
	pixel_area = 2.0 * 3.32 / float(mask_size.x * mask_size.y)
	var pixels := surface_pixels.duplicate()
	for i in pixels.size():
		pixels[i] = 255 if pixels[i] != 0 else 0
	surface_texture = ImageTexture.create_from_image(Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_L8, pixels))
	var topology := _build_sheet_mesh()
	for slot in CAPACITY:
		var sheet := Sheet.new()
		sheet.mesh = MeshInstance3D.new()
		sheet.mesh.name = "WaterSheet%d" % (slot + 1)
		sheet.mesh.mesh = topology
		sheet.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.mesh.custom_aabb = AABB(Vector3(-6, -0.1, -6), Vector3(12, 3, 12))
		sheet.material = ShaderMaterial.new()
		sheet.material.shader = preload("res://scripts/squeegee_water.gdshader")
		sheet.material.set_shader_parameter("rug_surface", surface_texture)
		sheet.mesh.material_override = sheet.material
		add_child(sheet.mesh)
		sheets.append(sheet)
	impact = Impact.new()
	impact.name = "LandingSplashAndDroplets"
	add_child(impact)
	impact.setup(footprint, surface_texture)
	reset()

func set_enabled(value: bool) -> void:
	reset()
	enabled = value

func reset() -> void:
	current = -1
	clock_seconds = 0.0
	emitted_strokes = 0
	removed_water = 0.0
	for sheet in sheets:
		sheet.active = false
		sheet.feeding = false
		sheet.count = 0
		sheet.mesh.hide()
	if is_instance_valid(impact): impact.reset()
	set_process(false)

func end_stroke() -> void:
	if current >= 0:
		var sheet := sheets[current]
		if sheet.feeding:
			sheet.feeding = false
			sheet.stopped = clock_seconds
	current = -1

func feed_stroke(from: Vector3, to: Vector3, elapsed: float, removed: float) -> void:
	var displacement := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if not enabled or sheets.is_empty() or removed <= 0.0001 or displacement.length_squared() < 0.00001:
		end_stroke()
		return
	var seconds := clampf(elapsed if elapsed > 0.0 else 1.0 / 60.0, 1.0 / 240.0, 0.08)
	var direction := displacement.normalized()
	var side := Vector3.UP.cross(direction).normalized()
	var velocity := displacement / seconds
	velocity = velocity.limit_length(3.0)
	# The painter's pixel coverage is normalized to area/second, not frame count.
	var power := clampf(removed * pixel_area / seconds / 0.65, 0.015, 1.0)
	var width := 2.0 * (HEAD_HALF.x * absf(side.x) + HEAD_HALF.y * absf(side.z))
	var leading := 0.78 * (HEAD_HALF.x * absf(direction.x) + HEAD_HALF.y * absf(direction.z))
	var origin := to + direction * leading
	origin.y = _surface_y(origin) + 0.025
	if current >= 0:
		var old := sheets[current]
		if old.direction.dot(direction) < 0.35 or old.origin.distance_to(origin) > 0.38:
			end_stroke()
	var starting := current < 0
	if starting:
		current = _available_slot()
		var fresh := sheets[current]
		fresh.active = true
		fresh.feeding = true
		fresh.started = clock_seconds - minf(seconds, 0.04)
		fresh.count = 0
		fresh.head = 0
	var sheet := sheets[current]
	sheet.origin = origin
	sheet.direction = direction
	sheet.side = side
	sheet.velocity = velocity + direction * forward_speed + Vector3.UP * upward_speed
	sheet.width = width
	sheet.power = power if starting else lerpf(sheet.power, power, 1.0 - exp(-seconds / 0.065))
	# Only bridge a short input gap funded by the latest positive extraction.
	sheet.deadline = clock_seconds + clampf(seconds * 1.4, 0.025, 0.075)
	if starting:
		sheet.origin -= displacement * minf(seconds, 0.04) / seconds
		_append_pose(sheet, sheet.started)
		sheet.origin = origin
	_append_pose(sheet, clock_seconds)
	emitted_strokes += 1
	removed_water += removed
	set_process(true)

func _process(delta: float) -> void:
	if sheets.is_empty(): return
	var step := clampf(delta, 0.0, 0.1)
	clock_seconds += step
	impact.begin_frame(step)
	var alive := false
	for slot in CAPACITY:
		var sheet := sheets[slot]
		if not sheet.active: continue
		if sheet.feeding:
			if clock_seconds > sheet.deadline:
				sheet.feeding = false
				sheet.stopped = sheet.deadline
				if current == slot: current = -1
			else:
				_append_pose(sheet, clock_seconds)
		_update_sheet(sheet, slot)
		alive = alive or sheet.active
	impact.finish_frame(step)
	set_process(alive or impact.is_alive())

func _available_slot() -> int:
	var oldest := 0
	for slot in CAPACITY:
		if not sheets[slot].active: return slot
		if sheets[slot].started < sheets[oldest].started: oldest = slot
	# Bounded even under deliberately frantic zig-zags: retire the oldest tail.
	sheets[oldest].mesh.hide()
	return oldest

func _append_pose(sheet: Sheet, time: float) -> void:
	var slot := sheet.head
	if sheet.count > 0 and absf(sheet.times[(slot - 1 + HISTORY) % HISTORY] - time) < 0.0001:
		slot = (slot - 1 + HISTORY) % HISTORY
	else:
		sheet.head = (slot + 1) % HISTORY
		sheet.count = mini(sheet.count + 1, HISTORY)
	sheet.times[slot] = time
	sheet.origins[slot] = sheet.origin
	sheet.velocities[slot] = sheet.velocity
	sheet.sides[slot] = sheet.side
	sheet.widths[slot] = sheet.width
	sheet.powers[slot] = sheet.power

func _sample_pose(sheet: Sheet, time: float) -> void:
	var older := (sheet.head - sheet.count + HISTORY) % HISTORY
	var newer := older
	for offset in range(1, sheet.count):
		newer = (sheet.head - sheet.count + offset + HISTORY) % HISTORY
		if sheet.times[newer] >= time: break
		older = newer
	var span := sheet.times[newer] - sheet.times[older]
	var weight := clampf((time - sheet.times[older]) / span, 0.0, 1.0) if span > 0.00001 else 0.0
	sheet.sample_origin = sheet.origins[older].lerp(sheet.origins[newer], weight)
	sheet.sample_velocity = sheet.velocities[older].lerp(sheet.velocities[newer], weight)
	sheet.sample_side = sheet.sides[older].lerp(sheet.sides[newer], weight).normalized()
	sheet.sample_width = lerpf(sheet.widths[older], sheet.widths[newer], weight)
	sheet.sample_power = lerpf(sheet.powers[older], sheet.powers[newer], weight)

func _update_sheet(sheet: Sheet, slot: int) -> void:
	var youngest := 0.0 if sheet.feeding else maxf(0.0, clock_seconds - sheet.stopped)
	var oldest := minf(MAX_FLIGHT, clock_seconds - sheet.started)
	if youngest >= MAX_FLIGHT or oldest <= youngest:
		sheet.active = false
		sheet.mesh.hide()
		return
	sheet.landed.fill(0)
	var living_lanes := LANES
	for row in ROWS:
		var age := lerpf(youngest, oldest, float(row) / float(ROWS - 1))
		_sample_pose(sheet, clock_seconds - age)
		var center := sheet.sample_origin + sheet.sample_velocity * age + Vector3.DOWN * (0.5 * GRAVITY * age * age)
		var fullness := sqrt(sheet.sample_power)
		var width := sheet.sample_width * lerpf(0.60, 1.0, fullness) * (1.0 + 0.08 * minf(age / 0.42, 1.0))
		var thickness := (0.006 + sheet_thickness * fullness) * 0.5
		for lane in LANES:
			var point := center + sheet.sample_side * width * (float(lane) / float(LANES - 1) - 0.5)
			var half_thickness := thickness
			if sheet.landed[lane] == 0:
				var contact := _crossing(sheet.previous[lane] if row > 0 else point, point)
				if contact.y > -5.0:
					sheet.landed[lane] = 1
					sheet.landings[lane] = contact
					if row == 0:
						living_lanes -= 1
					else:
						impact.contact(slot * LANES + lane, contact, sheet.sample_side, width / float(LANES - 1), sheet.sample_power)
				sheet.previous[lane] = point
			if sheet.landed[lane] != 0:
				point = sheet.landings[lane]
				half_thickness = 0.001
			sheet.grid[row * LANES + lane] = Vector4(point.x, point.y, point.z, half_thickness)
	if living_lanes == 0:
		sheet.active = false
		sheet.mesh.hide()
		return
	sheet.material.set_shader_parameter("grid_points", sheet.grid)
	sheet.material.set_shader_parameter("water_clock", fmod(clock_seconds, 100.0))
	sheet.material.set_shader_parameter("fallback_forward", sheet.direction)
	sheet.material.set_shader_parameter("ripple_height", ripple_height)
	sheet.mesh.show()

func _surface_y(point: Vector3) -> float:
	return RUG_Y if footprint.contains_point(Vector2(point.x, point.z)) else FLOOR_Y

func _crossing(from: Vector3, to: Vector3) -> Vector3:
	if to.y > RUG_Y: return Vector3(0, -10, 0)
	if from.y > RUG_Y and to.y <= RUG_Y:
		var at := from.lerp(to, (from.y - RUG_Y) / maxf(from.y - to.y, 0.00001))
		if footprint.contains_point(Vector2(at.x, at.z)):
			at.y = RUG_Y
			return at
	if to.y <= _surface_y(to):
		var plane := _surface_y(to)
		var at := from.lerp(to, clampf((from.y - plane) / maxf(from.y - to.y, 0.00001), 0.0, 1.0))
		at.y = plane
		return at
	return Vector3(0, -10, 0)

func debug_stats() -> Dictionary:
	var active := 0
	var feeding := 0
	for sheet in sheets:
		active += int(sheet.active)
		feeding += int(sheet.feeding)
	return {"active_sheets": active, "feeding_sheets": feeding, "capacity": CAPACITY,
		"emitted_strokes": emitted_strokes, "removed_water": removed_water,
		"vertices_per_sheet": 316, "triangles_per_sheet": 444,
		"processing": is_processing(), "impact": impact.debug_stats() if is_instance_valid(impact) else {}}

func _build_sheet_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var offsets := PackedVector2Array()
	var indices := PackedInt32Array()
	# Six closed faces. UV addresses the shared center grid; UV2.x chooses
	# the upper/lower skin. Separate seams keep the cuboid's softened bevel read.
	for face in 6:
		var columns := LANES if face < 2 or face >= 4 else 2
		var rows := ROWS if face < 4 else 2
		var base := vertices.size()
		for r in rows:
			for c in columns:
				var u := float(c) / float(columns - 1)
				var v := float(r) / float(rows - 1)
				var lift := 1.0 if face == 0 else -1.0
				var normal := Vector3.UP if face == 0 else Vector3.DOWN
				if face == 2 or face == 3:
					lift = u * 2.0 - 1.0
					u = 0.0 if face == 2 else 1.0
					normal = Vector3.LEFT if face == 2 else Vector3.RIGHT
				elif face >= 4:
					lift = v * 2.0 - 1.0
					v = 0.0 if face == 4 else 1.0
					normal = Vector3.FORWARD if face == 4 else Vector3.BACK
				vertices.append(Vector3(u, lift * 0.01, v))
				normals.append(normal)
				uvs.append(Vector2(u, v))
				offsets.append(Vector2(lift, 0))
		for r in range(rows - 1):
			for c in range(columns - 1):
				var a := base + r * columns + c
				indices.append_array(PackedInt32Array([a, a + columns, a + 1, a + 1, a + columns, a + columns + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = offsets
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
