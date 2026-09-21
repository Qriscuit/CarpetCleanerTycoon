extends SceneTree
func _initialize() -> void:
	var home := load("res://scenes/production/floating_home.tscn").instantiate() as Control
	load("res://../tools/home_settings_authoring.gd").decorate(home)
	var packed := PackedScene.new()
	assert(packed.pack(home) == OK)
	assert(ResourceSaver.save(packed,"res://scenes/production/floating_home.tscn") == OK)
	home.free()
	quit()
