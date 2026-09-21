extends RefCounted
## Instantiates each authored variant once, then swaps visibility without churn.

const TIER_SCENES: Array[PackedScene] = [
	preload("res://assets/tools/progression/tier_0_current_plastic.glb"),
	preload("res://assets/tools/progression/tier_1_wide_plastic.glb"),
	preload("res://assets/tools/progression/tier_2_dense_plastic.glb"),
	preload("res://assets/tools/progression/tier_3_crafted_wood.glb"),
	preload("res://assets/tools/progression/tier_4_engraved_wood.glb"),
	preload("res://assets/tools/progression/tier_5_cloud_lacquer.glb"),
	preload("res://assets/tools/progression/tier_6_lattice_wood.glb"),
	preload("res://assets/tools/progression/tier_7_jade_cloud.glb"),
	preload("res://assets/tools/progression/tier_8_master_lattice.glb"),
]

var brush_root: Node3D
var authored_children: Array[Node3D] = []
var variants: Array[Node3D] = []
var container: Node3D
var active_tier := -1

func setup(root: Node3D) -> void:
	assert(root != null, "A brush root is required")
	if brush_root == root and not variants.is_empty():
		return
	brush_root = root
	authored_children.clear()
	variants.clear()
	for child in root.get_children():
		if child is Node3D:
			authored_children.append(child)
	container = Node3D.new()
	container.name = "ProgressionVisuals"
	root.add_child(container)
	for i in TIER_SCENES.size():
		var model := TIER_SCENES[i].instantiate() as Node3D
		model.name = "Tier%d" % i
		model.visible = false
		container.add_child(model)
		variants.append(model)
	apply_tier(0, 1.0)

func apply_tier(tier: int, width: float) -> void:
	if brush_root == null or variants.is_empty():
		return
	var selected := clampi(tier, 0, variants.size() - 1)
	for child in authored_children:
		child.visible = false
	for i in variants.size():
		variants[i].visible = i == selected
	# Workshop owns physical and visible root width so art never double-scales it.
	brush_root.set_meta("progression_width", width)
	active_tier = selected
