extends Node3D
## Room improvements are authored as editable mesh groups in the scene.
## Picking is independent of physics so a floor tap can never interrupt a rug stroke.

const CATEGORIES := ["floor", "plants", "window", "railings", "walls"]
const RoomUpgrades = preload("res://scripts/room_upgrades.gd")
const UpgradeEffect = preload("res://scripts/room_upgrade_effect.gd")
signal upgrade_finished(category: String)
const UPGRADE_DURATION := 0.90
const UPGRADE_SWAP_TIME := 0.18
const UPGRADE_STRETCH_TIME := 0.38
const UPGRADE_WIDEN_TIME := 0.55
const UPGRADE_SQUASH := {"floor": Vector3(1.003, 0.94, 1.003), "plants": Vector3(1.025, 0.88, 1.025), "window": Vector3(1.01, 0.945, 1.01), "railings": Vector3(1.016, 0.92, 1.016), "walls": Vector3(1.006, 0.965, 1.006)}
const UPGRADE_STRETCH := {"floor": Vector3(0.997, 1.04, 0.997), "plants": Vector3(0.985, 1.08, 0.985), "window": Vector3(0.993, 1.035, 0.993), "railings": Vector3(0.99, 1.055, 0.99), "walls": Vector3(0.995, 1.025, 0.995)}
const UPGRADE_WIDEN := {"floor": Vector3(1.003, 0.975, 1.003), "plants": Vector3(1.032, 0.965, 1.032), "window": Vector3(1.012, 0.985, 1.012), "railings": Vector3(1.018, 0.975, 1.018), "walls": Vector3(1.009, 0.988, 1.009)}
const RETRIGGER_SPRING := 135.0
const RETRIGGER_DAMPING := 12.0
const RETRIGGER_KICK := 12.0
const UPGRADE_BASES := {"floor": -0.012, "plants": 0.035, "window": 0.10, "railings": 0.045, "walls": 0.0}
const EFFECT_RADII := {"floor": 0.40, "plants": 0.28, "window": 1.23, "railings": 0.31, "walls": 0.33}
const EFFECT_HEIGHTS := {"floor": 0.45, "plants": 1.03, "window": 1.40, "railings": 0.72, "walls": 1.70}
const GROUP_NAMES := {"floor": "Floor", "plants": "Plants", "window": "Window", "railings": "Railings", "walls": "Walls"}
const ANCHORS := {
	"floor": Vector3(-1.82, 0.025, 0.48),
	"plants": Vector3(-1.94, 0.70, 2.42),
	"window": Vector3(0.0, 0.62, -2.57),
	"railings": Vector3(2.16, 0.44, 0.15),
	"walls": Vector3(2.37, 0.85, -0.16),
}
var levels: Dictionary = {"floor": 0, "plants": 0, "window": 0, "railings": 0, "walls": 0}
var store_id := 1
var visual_tiers: Dictionary = {"floor": 0, "plants": 0, "window": 0, "railings": 0, "walls": 0}
var upgrade_effects: Dictionary = {}
var _upgrade_animations: Dictionary = {}
var _tier_transforms: Dictionary = {}
# Keep the four corner pots batched while scaling each about its own saucer.
# Surface overrides are cached once and restored after each purchase burst.
var _plant_upgrade_parts: Dictionary = {}
var _plant_upgrade_scales: Dictionary = {}
var _plant_bounce_shaders: Dictionary = {}
const PLANT_BOUNCE_CODE := """
uniform vec3 room_plant_scale = vec3(1.0);
uniform vec3 room_plant_pivot_0;
uniform vec3 room_plant_pivot_1;
uniform vec3 room_plant_pivot_2;
uniform vec3 room_plant_pivot_3;
void room_plant_bounce(inout vec3 vertex, inout vec3 normal) {
	vec3 pivot = room_plant_pivot_0;
	float closest = distance(vertex.xz, pivot.xz);
	float next = distance(vertex.xz, room_plant_pivot_1.xz);
	if (next < closest) { pivot = room_plant_pivot_1; closest = next; }
	next = distance(vertex.xz, room_plant_pivot_2.xz);
	if (next < closest) { pivot = room_plant_pivot_2; closest = next; }
	next = distance(vertex.xz, room_plant_pivot_3.xz);
	if (next < closest) { pivot = room_plant_pivot_3; }
	vertex = pivot + (vertex - pivot) * room_plant_scale;
	normal = normalize(normal / room_plant_scale);
}
"""
# World-space half extents, independent of the room's decorative x/z scale.
@export var protected_rug_half := Vector2(1.04, 1.69)
@export var protected_rug_surface_y := 0.067
var selected_upgrade := ""
var _selection: MeshInstance3D
var _pulse := 0.0
const COMPLETION_BREEZE_DURATION := 4.0
const WINDOW_OPEN_ANGLE := deg_to_rad(105.0)
var window_open_amount := 0.0
var breeze_strength := 0.0
var breeze_time := 0.0
var _breeze_active := false
var _completion_paused := false
var _window_hinges: Array[Node3D] = []
var _foliage_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	_cache_completion_parts()
	_cache_upgrade_parts()
	set_levels(levels)
	set_process(false)

func _cache_upgrade_parts() -> void:
	for category: String in CATEGORIES:
		if not upgrade_effects.has(category):
			var effect := UpgradeEffect.new()
			effect.name = "%sUpgradePulse" % str(GROUP_NAMES[category])
			effect.radius = float(EFFECT_RADII[category])
			add_child(effect)
			upgrade_effects[category] = effect
		for tier: int in range(RoomUpgrades.visual_count(category) + 1):
			var path := "%s/Tier%d" % [GROUP_NAMES[category], tier]
			var model := get_node_or_null(path) as Node3D
			if model != null and not _tier_transforms.has(path):
				_tier_transforms[path] = model.transform
	_cache_plant_upgrade_parts()

func _cache_plant_upgrade_parts() -> void:
	if not _plant_upgrade_parts.is_empty(): return
	for tier: int in range(RoomUpgrades.visual_count("plants") + 1):
		var model := get_node_or_null("Plants/Tier%d" % tier) as Node3D
		if model == null: continue
		var pivots: Array[Vector3] = []
		var editable := model.get_node_or_null("EditableSource")
		if editable == null: continue
		for planter: Node in editable.get_children():
			if not planter is Node3D or not str(planter.name).begins_with("Planter_"): continue
			var saucer := planter.get_node_or_null("Saucer") as MeshInstance3D
			if saucer == null or saucer.mesh == null: continue
			var foot := model.global_transform.affine_inverse() * saucer.global_transform * Vector3(0, saucer.mesh.get_aabb().position.y, 0)
			var center: Vector3 = model.global_transform.affine_inverse() * (planter as Node3D).global_position
			pivots.append(Vector3(center.x, foot.y, center.z))
		if pivots.size() != 4: continue
		var parts: Array[Dictionary] = []
		for mesh_path: String in ["BakedModel", "Foliage/BakedModel"]:
			var mesh := model.get_node_or_null(mesh_path) as MeshInstance3D
			if mesh == null or mesh.mesh == null: continue
			var authored: Array[Material] = []
			var animated: Array[ShaderMaterial] = []
			for surface: int in mesh.mesh.get_surface_count():
				authored.append(mesh.get_surface_override_material(surface))
				var source := mesh.get_active_material(surface)
				var material := _make_plant_bounce_material(source)
				if material != null:
					for index: int in pivots.size():
						material.set_shader_parameter("room_plant_pivot_%d" % index, pivots[index])
				animated.append(material)
			parts.append({"mesh": mesh, "authored": authored, "animated": animated, "pivots": pivots, "cull_margin": mesh.extra_cull_margin})
		_plant_upgrade_parts[tier] = parts
		_plant_upgrade_scales[tier] = Vector3.ONE

func _make_plant_bounce_material(source: Material) -> ShaderMaterial:
	var animated: ShaderMaterial
	if source is StandardMaterial3D:
		if not _plant_bounce_shaders.has("opaque"):
			var shader := Shader.new()
			shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 pot_color : source_color;
uniform float pot_metallic;
uniform float pot_roughness;
uniform float pot_specular;
""" + PLANT_BOUNCE_CODE + """
void vertex() { room_plant_bounce(VERTEX, NORMAL); }
void fragment() {
	ALBEDO = pot_color.rgb;
	METALLIC = pot_metallic;
	ROUGHNESS = pot_roughness;
	SPECULAR = pot_specular;
}
"""
			_plant_bounce_shaders.opaque = shader
		animated = ShaderMaterial.new()
		animated.shader = _plant_bounce_shaders.opaque
		animated.set_shader_parameter("pot_color", source.albedo_color)
		animated.set_shader_parameter("pot_metallic", source.metallic)
		animated.set_shader_parameter("pot_roughness", source.roughness)
		animated.set_shader_parameter("pot_specular", source.metallic_specular)
	elif source is ShaderMaterial and source.shader != null:
		var key: int = source.shader.get_instance_id()
		if not _plant_bounce_shaders.has(key):
			# Preserve the authored foliage deformation first, then scale its
			# bent vertices locally about the matching pot's stationary foot.
			var code: String = source.shader.code
			var start := code.find("void vertex()")
			if start < 0: return null
			var brace := code.find("{", start)
			var depth := 1
			var end := brace + 1
			while end < code.length() and depth > 0:
				if code[end] == "{": depth += 1
				elif code[end] == "}": depth -= 1
				end += 1
			if depth != 0: return null
			code = code.substr(0, end - 1) + "\n\troom_plant_bounce(VERTEX, NORMAL);\n" + code.substr(end - 1)
			code = code.substr(0, start) + PLANT_BOUNCE_CODE + code.substr(start)
			var shader := Shader.new()
			shader.code = code
			_plant_bounce_shaders[key] = shader
		animated = source.duplicate() as ShaderMaterial
		animated.shader = _plant_bounce_shaders[key]
		_foliage_materials.append(animated)
	else:
		return null
	animated.resource_local_to_scene = true
	return animated

func _animate_plants(amount: Vector3) -> void:
	var tier := int(visual_tiers.plants)
	_plant_upgrade_scales[tier] = amount
	for part: Dictionary in _plant_upgrade_parts.get(tier, []):
		var mesh: MeshInstance3D = part.mesh
		# Shader deformation does not enlarge the CPU-side baked bounds.
		mesh.extra_cull_margin = float(part.cull_margin) + 0.15
		for surface: int in part.animated.size():
			var material: ShaderMaterial = part.animated[surface]
			if material == null: continue
			material.set_shader_parameter("room_plant_scale", amount)
			mesh.set_surface_override_material(surface, material)

func upgrade_scale(category: String) -> Vector3:
	if category == "plants": return _plant_upgrade_scales.get(int(visual_tiers.plants), Vector3.ONE)
	var path := "%s/Tier%d" % [GROUP_NAMES[category], int(visual_tiers[category])]
	var model := get_node_or_null(path) as Node3D
	if model == null or not _tier_transforms.has(path): return Vector3.ONE
	return (model.transform * (_tier_transforms[path] as Transform3D).affine_inverse()).basis.get_scale()

func is_upgrade_active(category: String = "") -> bool:
	return not _upgrade_animations.is_empty() if category.is_empty() else _upgrade_animations.has(category)

func play_upgrade(category: String, new_levels: Dictionary, world_anchor: Vector3 = Vector3.INF, previous_levels: Dictionary = {}) -> void:
	if not CATEGORIES.has(category):
		return
	_cache_upgrade_parts()
	# The ledger emits changed synchronously. Explicit prior levels keep a model
	# hidden until the compressed point, even when a caller already synced it.
	var old_level := int(previous_levels.get(category, levels.get(category, 0)))
	if is_upgrade_active(category):
		var animation: Dictionary = _upgrade_animations[category]
		# An additional purchase adds energy to the existing motion. The model's
		# pose is retained when the button is tapped again.
		animation.time = 0.0
		animation.impulse_velocity = minf(float(animation.impulse_velocity) + RETRIGGER_KICK, 16.0)
		if not bool(animation.pending_swap):
			animation.swap_time = 0.0
		animation.pending_swap = true
	else:
		_restore_category_transform(category)
		# Mark this feature active before syncing levels, so its model cannot
		# change before the compressed swap point.
		_upgrade_animations[category] = {
			"time": 0.0, "cycle_time": 0.0, "swap_time": 0.0,
			"pending_swap": true, "impulse": 0.0, "impulse_velocity": 0.0,
		}
		_show_tier(category, RoomUpgrades.visual_tier(category, old_level, store_id))
	set_levels(new_levels)
	var anchor := world_anchor if world_anchor.is_finite() else anchor_world(category)
	anchor.y = to_global(Vector3(0, 0.035, 0)).y
	upgrade_effects[category].start(anchor, float(EFFECT_RADII[category]), float(EFFECT_HEIGHTS[category]))
	set_process(true)

func cancel_upgrade_effects() -> void:
	var active_ids: Array = _upgrade_animations.keys()
	_upgrade_animations.clear()
	for category: String in CATEGORIES:
		_restore_category_transform(category)
		_show_tier(category, RoomUpgrades.visual_tier(category, int(levels[category]), store_id))
		if upgrade_effects.has(category):
			upgrade_effects[category].stop()
	for category: String in active_ids:
		upgrade_finished.emit(category)
	set_process(_breeze_active or not selected_upgrade.is_empty())

func _show_tier(category: String, visible_tier: int) -> void:
	visual_tiers[category] = visible_tier
	var group := get_node_or_null(str(GROUP_NAMES[category]))
	if group == null:
		return
	for tier: int in range(RoomUpgrades.visual_count(category) + 1):
		var model := group.get_node_or_null("Tier%d" % tier) as Node3D
		if model != null:
			model.visible = tier == visible_tier

func _restore_category_transform(category: String) -> void:
	for tier: int in range(RoomUpgrades.visual_count(category) + 1):
		var path := "%s/Tier%d" % [GROUP_NAMES[category], tier]
		var model := get_node_or_null(path) as Node3D
		if model != null and _tier_transforms.has(path):
			model.transform = _tier_transforms[path]
	if category == "plants":
		for tier: int in _plant_upgrade_parts:
			_plant_upgrade_scales[tier] = Vector3.ONE
			for part: Dictionary in _plant_upgrade_parts[tier]:
				part.mesh.extra_cull_margin = float(part.cull_margin)
				for surface: int in part.authored.size():
					part.mesh.set_surface_override_material(surface, part.authored[surface])

func _upgrade_amount(category: String, time: float) -> Vector3:
	var amount := Vector3.ONE
	if time <= UPGRADE_SWAP_TIME:
		amount = Vector3.ONE.lerp(UPGRADE_SQUASH[category], smoothstep(0.0, UPGRADE_SWAP_TIME, time))
	elif time <= UPGRADE_STRETCH_TIME:
		amount = (UPGRADE_SQUASH[category] as Vector3).lerp(UPGRADE_STRETCH[category], smoothstep(UPGRADE_SWAP_TIME, UPGRADE_STRETCH_TIME, time))
	elif time <= UPGRADE_WIDEN_TIME:
		amount = (UPGRADE_STRETCH[category] as Vector3).lerp(UPGRADE_WIDEN[category], smoothstep(UPGRADE_STRETCH_TIME, UPGRADE_WIDEN_TIME, time))
	else:
		amount = (UPGRADE_WIDEN[category] as Vector3).lerp(Vector3.ONE, smoothstep(UPGRADE_WIDEN_TIME, UPGRADE_DURATION, time))
	return amount

func _advance_upgrade_impulse(animation: Dictionary, delta: float) -> void:
	# Fixed-size integration is stable even when one rendered frame is long.
	# A single bounded spring per category replaces queued tweens or pulses.
	var remaining := minf(delta, UPGRADE_DURATION)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		var offset := float(animation.impulse)
		var velocity := float(animation.impulse_velocity)
		velocity += (-RETRIGGER_SPRING * offset - RETRIGGER_DAMPING * velocity) * step
		offset += velocity * step
		if offset > 1.1:
			offset = 1.1
			velocity = minf(velocity, 0.0)
		elif offset < -0.7:
			offset = -0.7
			velocity = maxf(velocity, 0.0)
		animation.impulse = offset
		animation.impulse_velocity = velocity
		remaining -= step

func _animate_upgrade(category: String, time: float, impulse: float = 0.0) -> void:
	var amount := _upgrade_amount(category, time)
	# A positive impulse goes tall and narrow; its damped return crosses into
	# a wider shape. Floors and structural pieces use smaller safe movement.
	var tall_amount := float((UPGRADE_STRETCH[category] as Vector3).y) - 1.0
	var wide_amount := float((UPGRADE_WIDEN[category] as Vector3).x) - 1.0
	amount += Vector3(-wide_amount * impulse, tall_amount * impulse, -wide_amount * impulse)
	if category == "plants":
		_animate_plants(amount)
		return
	# The window's hinges still rotate in their own local space. The rug and
	# structural foundation are siblings and never inherit purchase motion.
	var pivot := Vector3(0, float(UPGRADE_BASES[category]), 0)
	var path := "%s/Tier%d" % [GROUP_NAMES[category], int(visual_tiers[category])]
	var model := get_node_or_null(path) as Node3D
	if model != null and _tier_transforms.has(path):
		var deform := Transform3D(Basis.from_scale(amount), pivot - pivot * amount)
		model.transform = deform * (_tier_transforms[path] as Transform3D)

func _process_upgrades(delta: float) -> void:
	for category: String in _upgrade_animations.keys():
		var animation: Dictionary = _upgrade_animations[category]
		animation.time = minf(float(animation.time) + delta, UPGRADE_DURATION)
		animation.cycle_time = minf(float(animation.cycle_time) + delta, UPGRADE_DURATION)
		_advance_upgrade_impulse(animation, delta)
		if bool(animation.pending_swap):
			# This clock is not restarted by rapid taps. A milestone always reveals
			# the latest paid tier rather than an old queued purchase.
			animation.swap_time = float(animation.swap_time) + delta
		if bool(animation.pending_swap) and float(animation.swap_time) >= UPGRADE_SWAP_TIME:
			_show_tier(category, RoomUpgrades.visual_tier(category, int(levels[category]), store_id))
			animation.pending_swap = false
		_animate_upgrade(category, float(animation.cycle_time), float(animation.impulse))
		upgrade_effects[category].update_phase(float(animation.time) / UPGRADE_DURATION)
		if float(animation.time) >= UPGRADE_DURATION:
			_restore_category_transform(category)
			_show_tier(category, RoomUpgrades.visual_tier(category, int(levels[category]), store_id))
			upgrade_effects[category].stop()
			_upgrade_animations.erase(category)
			upgrade_finished.emit(category)

func _cache_completion_parts() -> void:
	if not _window_hinges.is_empty():
		return
	for tier: int in range(4):
		for side: String in ["LeftHinge", "RightHinge"]:
			var hinge := get_node_or_null("Window/Tier%d/%s" % [tier, side]) as Node3D
			if hinge != null:
				_window_hinges.append(hinge)
		var foliage := get_node_or_null("Plants/Tier%d/Foliage/BakedModel" % tier) as MeshInstance3D
		if foliage == null:
			continue
		for surface: int in foliage.mesh.get_surface_count():
			var material := foliage.mesh.surface_get_material(surface) as ShaderMaterial
			if material != null and not _foliage_materials.has(material):
				_foliage_materials.append(material)

func set_window_open_amount(amount: float) -> void:
	window_open_amount = clampf(amount, 0.0, 1.0)
	_cache_completion_parts()
	for hinge: Node3D in _window_hinges:
		var closed_basis: Basis = hinge.get_meta("closed_basis", Basis.IDENTITY)
		var side := float(hinge.get_meta("hinge_side", 1.0))
		# Rotate around the authored vertical side edge. Keeping the closed
		# basis outside the rotation fixes its bottom and top throughout the swing.
		hinge.basis = closed_basis * Basis(Vector3.UP, -side * WINDOW_OPEN_ANGLE * window_open_amount)

func window_clear_aperture_world() -> Dictionary:
	# Conservative horizontal corridor through all decorative frame tiers.
	# The aperture remains clear only while both moving leaves are fully open.
	return {
		"width": 3.06 * global_basis.x.length(),
		"bottom": to_global(Vector3(0, 0.13, -2.64)).y,
		"top": to_global(Vector3(0, 1.23, -2.64)).y,
		"plane_z": to_global(Vector3(0, 0.11, -2.64)).z,
	}

func start_completion_breeze() -> void:
	_cache_completion_parts()
	breeze_time = 0.0
	breeze_strength = 0.0
	_breeze_active = true
	_completion_paused = false
	_update_foliage_breeze()
	set_process(true)

func set_completion_paused(paused: bool) -> void:
	_completion_paused = paused

func reset_completion_motion() -> void:
	cancel_upgrade_effects()
	set_window_open_amount(0.0)
	breeze_time = 0.0
	breeze_strength = 0.0
	_breeze_active = false
	_completion_paused = false
	_update_foliage_breeze()
	set_process(not selected_upgrade.is_empty())

func _update_foliage_breeze() -> void:
	for material: ShaderMaterial in _foliage_materials:
		material.set_shader_parameter("breeze_time", breeze_time)
		material.set_shader_parameter("breeze_strength", breeze_strength)

func set_levels(values: Dictionary, active_store_id: int = -1) -> void:
	if active_store_id >= 1 and active_store_id != store_id:
		cancel_upgrade_effects()
		store_id = active_store_id
	for category: String in CATEGORIES:
		levels[category] = clampi(int(values.get(category, 0)), 0, RoomUpgrades.Progression.room_level_cap(store_id))
		if not is_upgrade_active(category):
			_show_tier(category, RoomUpgrades.visual_tier(category, int(levels[category]), store_id))

func anchor_world(category: String) -> Vector3:
	return to_global(ANCHORS.get(category, Vector3.ZERO))

func geometry_fit_bounds_local(include_open_window: bool = false) -> AABB:
	# The right wall and shallow outward door use a narrow extra foundation
	# ledge. Include the open casements when fitting the departure view.
	var back := -4.40 if include_open_window else -3.25
	return AABB(Vector3(-2.50, -0.21, back), Vector3(5.0, 1.99, 2.93 - back))


func anchor_world_near(category: String, camera: Camera3D, screen_point: Vector2) -> Vector3:
	if not screen_point.is_finite() or camera == null:
		return anchor_world(category)
	var candidates: Array[Vector3] = []
	if category == "plants":
		for side: float in [-1.0, 1.0]:
			for end: float in [-1.0, 1.0]:
				candidates.append(to_global(Vector3(side * 1.94, 0.70, end * 2.42)))
	elif category == "walls":
		for local: Vector3 in [Vector3(-2.225, 0.85, -2.86), Vector3(2.225, 0.85, -2.86), Vector3(0, 1.58, -2.86), Vector3(2.37, 0.85, -0.16), Vector3(2.37, 0.85, -2.05)]:
			candidates.append(to_global(local))
	elif category in ["floor", "railings"]:
		var origin := camera.project_ray_origin(screen_point)
		var direction := camera.project_ray_normal(screen_point)
		var height := 0.025 if category == "floor" else 0.44
		var hit := to_local(origin + direction * ((to_global(Vector3(0, height, 0)).y - origin.y) / direction.y))
		if category == "floor":
			return to_global(Vector3(clampf(hit.x, -2.20, 2.20), height, clampf(hit.z, -2.80, 2.80)))
		return to_global(Vector3(signf(hit.x) * 2.16, height, clampf(hit.z, -1.70, 1.70)))
	else:
		return anchor_world(category)
	var nearest := anchor_world(category)
	var distance := INF
	for candidate: Vector3 in candidates:
		var candidate_distance := camera.unproject_position(candidate).distance_squared_to(screen_point)
		if candidate_distance < distance:
			distance = candidate_distance
			nearest = candidate
	return nearest

func pick_upgrade(camera: Camera3D, screen_position: Vector2) -> String:
	if camera == null or not is_inside_tree():
		return ""
	var world_ray_origin := camera.project_ray_origin(screen_position)
	var world_ray_direction := camera.project_ray_normal(screen_position)
	# Protect the carpet at its actual surface height. Projecting a fringe tap
	# onto the lower floor shifts it behind the rug with the pitched camera.
	if absf(world_ray_direction.y) > 0.00001:
		var distance_to_rug := (protected_rug_surface_y - world_ray_origin.y) / world_ray_direction.y
		var rug_hit := world_ray_origin + world_ray_direction * distance_to_rug
		if distance_to_rug > 0.0 and absf(rug_hit.x) < protected_rug_half.x and absf(rug_hit.z) < protected_rug_half.y:
			return ""
	var ray_origin := to_local(world_ray_origin)
	var ray_direction := global_basis.inverse() * world_ray_direction
	if absf(ray_direction.y) < 0.00001:
		return ""
	var distance_to_floor := -ray_origin.y / ray_direction.y
	if distance_to_floor <= 0.0:
		return ""
	var floor_hit := ray_origin + ray_direction * distance_to_floor
	var nearest := INF
	var chosen := ""
	var boxes: Array[Dictionary] = [
		{"id": "window", "box": AABB(Vector3(-1.79, 0.02, -3.24), Vector3(3.58, 1.5, 0.78))},
		{"id": "railings", "box": AABB(Vector3(-2.28, 0.0, -1.85), Vector3(0.35, 0.55, 3.7))},
		{"id": "railings", "box": AABB(Vector3(1.93, 0.0, -1.85), Vector3(0.35, 0.55, 3.7))},
		{"id": "walls", "box": AABB(Vector3(-2.415, 0.0, -2.97), Vector3(0.38, 1.70, 0.23))},
		{"id": "walls", "box": AABB(Vector3(2.035, 0.0, -2.97), Vector3(0.38, 1.70, 0.23))},
		{"id": "walls", "box": AABB(Vector3(-2.42, 1.44, -2.97), Vector3(4.84, 0.27, 0.23))},
		{"id": "walls", "box": AABB(Vector3(2.245, 0.0, -2.94), Vector3(0.31, 1.56, 2.98))},
	]
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			boxes.append({"id": "plants", "box": AABB(Vector3(side * 1.94 - 0.32, 0.0, end * 2.42 - 0.32), Vector3(0.64, 0.94, 0.64))})
	for target: Dictionary in boxes:
		var hit: Variant = (target["box"] as AABB).intersects_ray(ray_origin, ray_direction)
		if hit is Vector3:
			var distance: float = ray_origin.distance_squared_to(hit)
			if distance < nearest:
				nearest = distance
				chosen = str(target["id"])
	if not chosen.is_empty():
		return chosen
	if absf(floor_hit.x) > 2.25 or absf(floor_hit.z) > 2.9:
		return ""
	return "floor"

func set_selected(category: String, world_anchor: Vector3 = Vector3.INF) -> void:
	selected_upgrade = category if CATEGORIES.has(category) else ""
	if selected_upgrade.is_empty():
		clear_selection()
		return
	if _selection == null:
		_selection = MeshInstance3D.new()
		_selection.name = "UpgradeSelectionRing"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.15
		ring.outer_radius = 0.185
		ring.rings = 24
		ring.ring_segments = 6
		_selection.mesh = ring
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color("ffd482")
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_selection.material_override = glow
		_selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_selection)
	_selection.position = (to_local(world_anchor) if world_anchor.is_finite() else ANCHORS[selected_upgrade]) + Vector3(0, 0.025, 0)
	_selection.visible = true
	_pulse = 0.0
	set_process(true)

func clear_selection() -> void:
	selected_upgrade = ""
	if _selection != null:
		_selection.visible = false
	set_process(_breeze_active or is_upgrade_active())

func _process(delta: float) -> void:
	if _selection != null and not selected_upgrade.is_empty() and not _completion_paused:
		_pulse += delta
		_selection.scale = Vector3.ONE * (1.0 + 0.09 * sin(_pulse * 4.5))
	if _breeze_active and not _completion_paused:
		breeze_time = minf(breeze_time + delta, COMPLETION_BREEZE_DURATION)
		var progress := breeze_time / COMPLETION_BREEZE_DURATION
		breeze_strength = smoothstep(0.0, 0.1, progress) * pow(1.0 - progress, 1.35)
		_breeze_active = breeze_time < COMPLETION_BREEZE_DURATION
		_update_foliage_breeze()
	if is_upgrade_active() and not _completion_paused:
		_process_upgrades(delta)
	set_process(_breeze_active or not selected_upgrade.is_empty() or is_upgrade_active())
