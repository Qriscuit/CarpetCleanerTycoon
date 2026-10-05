extends Resource
## Shared geometry for now; each resource owns its appearance and cleaning recipe.
@export var rug_id := ""
@export var display_name := "Mint Meadow"
@export_multiline var cleaning_hint := "Brush in two passes."
## Pattern replaces only the pile's authored albedo, never binding or fringe.
## Empty textures and transparent colors preserve the mesh's original material.
@export var pattern_texture: Texture2D
@export var pile_color := Color.TRANSPARENT
@export var binding_color := Color.TRANSPARENT
@export var fringe_color := Color.TRANSPARENT
@export var surface_tint := Color.WHITE
@export_range(0.0, 1.0) var dust_strength := 0.58
@export_range(0.01, 1.0) var removal_per_pass := 0.5
## Zero allows all directions. Otherwise strokes along this rug-local axis work best.
@export var grain_axis := Vector2.ZERO
@export_range(0.1, 1.0) var cross_grain_efficiency := 1.0

func stroke_efficiency(direction: Vector2) -> float:
	if grain_axis.is_zero_approx():
		return 1.0
	return lerpf(cross_grain_efficiency, 1.0, absf(direction.normalized().dot(grain_axis.normalized())))
