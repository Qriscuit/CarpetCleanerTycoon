extends RefCounted
## Shared paid-job and practice identities. Keep IDs stable when art or names change.

const DEFAULT_ID := "mint_meadow"
# Stillwater replaces the retired Whale slot; append other new designs so the
# remaining existing identities keep their discovery positions.
# Art is loaded only for the current carpet, never preloaded as a whole catalog.
const IDS := [
	DEFAULT_ID, "sunburst_geometry", "playful_fox",
	"moonlit_owl", "koi_garden", "stillwater_pond", "woodland_hare",
	"peacock_palace", "tiger_bloom", "mushroom_glade", "sun_moon_tapestry",
	"wildflower_meadow",
	"sleepy_cat", "river_otter", "honey_bear", "red_panda",
	"lemon_branch", "paper_boats", "desert_sun", "moon_moth",
	"misty_tea_garden", "quiet_cove", "moonlit_greenhouse", "ramen_neko",
]
const SAVED_ID_REPLACEMENTS := {"celestial_whale": "stillwater_pond"}
const NAMES := {
	"mint_meadow": "Mint Meadow",
	"sunburst_geometry": "Sunburst",
	"playful_fox": "Fox's Den",
	"moonlit_owl": "Moonlit Owl",
	"koi_garden": "Koi Garden",
	"stillwater_pond": "Stillwater Pond",
	"woodland_hare": "Woodland Hare",
	"peacock_palace": "Peacock Palace",
	"tiger_bloom": "Tiger in Bloom",
	"mushroom_glade": "Mushroom Glade",
	"sun_moon_tapestry": "Sun & Moon",
	"wildflower_meadow": "Wildflower Meadow",
	"sleepy_cat": "Sunday Cat",
	"river_otter": "River Daydream",
	"honey_bear": "Honey Bear",
	"red_panda": "Red Panda Nap",
	"lemon_branch": "Lemon Afternoon",
	"paper_boats": "Paper Boats",
	"desert_sun": "Desert Sunrise",
	"moon_moth": "Moon Moth",
	"misty_tea_garden": "Misty Tea Garden",
	"quiet_cove": "Quiet Cove",
	"moonlit_greenhouse": "Moonlit Greenhouse",
	"ramen_neko": "Ramen Neko",
}
const TEXTURES := {
	"mint_meadow": "res://assets/carpet/mint_meadow_mint_meadow_albedo.png",
	"sunburst_geometry": "res://assets/carpet/patterns/sunburst_geometry.png",
	"playful_fox": "res://assets/carpet/patterns/playful_fox.png",
	"moonlit_owl": "res://assets/carpet/patterns/moonlit_owl.png",
	"koi_garden": "res://assets/carpet/patterns/koi_garden.png",
	"stillwater_pond": "res://assets/carpet/patterns/stillwater_pond.png",
	"woodland_hare": "res://assets/carpet/patterns/woodland_hare.png",
	"peacock_palace": "res://assets/carpet/patterns/peacock_palace.png",
	"tiger_bloom": "res://assets/carpet/patterns/tiger_bloom.png",
	"mushroom_glade": "res://assets/carpet/patterns/mushroom_glade.png",
	"sun_moon_tapestry": "res://assets/carpet/patterns/sun_moon_tapestry.png",
	"wildflower_meadow": "res://assets/carpet/patterns/wildflower_meadow.png",
	"sleepy_cat": "res://assets/carpet/patterns/sleepy_cat.png",
	"river_otter": "res://assets/carpet/patterns/river_otter.png",
	"honey_bear": "res://assets/carpet/patterns/honey_bear.png",
	"red_panda": "res://assets/carpet/patterns/red_panda.png",
	"lemon_branch": "res://assets/carpet/patterns/lemon_branch.png",
	"paper_boats": "res://assets/carpet/patterns/paper_boats.png",
	"desert_sun": "res://assets/carpet/patterns/desert_sun.png",
	"moon_moth": "res://assets/carpet/patterns/moon_moth.png",
	"misty_tea_garden": "res://assets/carpet/patterns/misty_tea_garden.png",
	"quiet_cove": "res://assets/carpet/patterns/quiet_cove.png",
	"moonlit_greenhouse": "res://assets/carpet/patterns/moonlit_greenhouse.png",
	"ramen_neko": "res://assets/carpet/patterns/ramen_neko.png",
}


static func is_known(id: Variant) -> bool:
	return id is String and id in IDS


static func resolve_saved_id(id: Variant) -> String:
	if is_known(id): return id
	return SAVED_ID_REPLACEMENTS.get(id, "") if id is String else ""


static func id_for_completed_jobs(completed_jobs: int) -> String:
	return IDS[maxi(0, completed_jobs) % IDS.size()]


static func display_name(id: String) -> String:
	return NAMES.get(id, NAMES[DEFAULT_ID])


static func definition_path(id: String) -> String:
	return "res://resources/rugs/%s.tres" % (id if is_known(id) else DEFAULT_ID)


static func load_definition(id: String) -> Resource:
	return load(definition_path(id))


static func texture_path(id: String) -> String:
	return TEXTURES.get(id, TEXTURES[DEFAULT_ID])
