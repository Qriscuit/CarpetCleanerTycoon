extends SceneTree
## Verify scene-authored art survives responsive layout and working-state changes.
## Run: Godot --headless --path CarpetToy --script ../tools/validate_editable_art.gd -- --shop-test

var failures := 0
var checks := 0

func _initialize() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(1)
		return
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	for kind: String in ["store", "bonzi", "brush", "wide_brush", "blueprint", "upgrade", "intake"]:
		var packed: PackedScene = load("res://scenes/ui/art/" + kind + ".tscn")
		verify(packed != null, kind + " loads")
		if packed == null:
			continue
		var scene: Control = packed.instantiate()
		root.add_child(scene)
		scene.size = Vector2(400, 220)
		await process_frame
		var artwork: Node2D = scene.get_node("Artwork")
		verify(artwork.get_child_count() > 0, kind + " serialized children")
		var shapes := scene.find_children("*", "Panel", true, false).size() + scene.find_children("*", "Polygon2D", true, false).size() + scene.find_children("*", "Line2D", true, false).size()
		verify(shapes > 10, kind + " native editable shapes")
		var part: Node2D = artwork.get_child(0)
		part.position = Vector2(17, 13)
		scene.size = Vector2(280, 150)
		await process_frame
		verify(part.position == Vector2(17, 13), kind + " resize preserves authored transforms")
		verify(artwork.scale.x > 0 and is_equal_approx(artwork.scale.x, artwork.scale.y), kind + " uniform aspect fit")
		if kind == "bonzi":
			var bonzi: Node2D = scene.get_node("Artwork/Robot/Bonzi")
			var rest := bonzi.position
			scene.working = true
			await process_frame
			await process_frame
			verify(bonzi.position != rest, "Bonzi working animation moves its group")
			scene.working = false
			verify(bonzi.position == rest, "Stopping Bonzi restores authored rest pose")
		print("EDITABLE ART: ", kind, " has ", shapes, " native shapes.")
		root.remove_child(scene)
		scene.free()
	print("EDITABLE ART: ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
