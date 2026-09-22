extends RefCounted
## One spout upgrade drives shape, absorption and capillary spread together.
## The Gym previews these levels for free; this is not a shop/save upgrade.

const MAX_LEVEL := 4
# Even the starter stream gains a readable middle; later spouts scale that
# silhouette instead of jumping from a pencil-thin core straight to a splash.
const TIP_RADII := [0.068, 0.085, 0.103, 0.123, 0.145]
const IMPACT_RADII := [0.17, 0.21, 0.25, 0.29, 0.33]
const WET_RADII := [0.26, 0.30, 0.35, 0.40, 0.46]
const SPREAD_RADII := [0.52, 0.61, 0.70, 0.80, 0.90]
const SOAK_MULTIPLIERS := [1.0, 1.3, 1.65, 2.0, 2.4]
const SPREAD_SPEEDS := [0.30, 0.37, 0.44, 0.52, 0.60]


static func for_level(level: int) -> Dictionary:
	var index := clampi(level, 0, MAX_LEVEL)
	return {
		"level": index,
		"stream_tip_radius": TIP_RADII[index],
		"impact_radius": IMPACT_RADII[index],
		"wet_radius": WET_RADII[index],
		"max_spread_radius": SPREAD_RADII[index],
		"soak_multiplier": SOAK_MULTIPLIERS[index],
		"spread_speed": SPREAD_SPEEDS[index],
	}
