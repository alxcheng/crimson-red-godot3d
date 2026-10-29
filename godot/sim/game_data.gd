extends RefCounted
## Read access to the game's data, exported from the 2D game by `./export_data` into res://data/*.json,
## plus the unit conversions between the 2D game's pixels and the 3D game's metres.
## Static: no autoload needed. Tables are loaded once and cached.

const PX_PER_M := 23.3                  # [tuned] hero 1.8 m tall: the Knight is ~42 px on screen in the 2D game
const PX_PER_SPEED := 30.0              # the 2D game: MOVE_SPEED x 30 = pixels per second

static var _cache := {}


static func table(name: String) -> Variant:
	if not _cache.has(name):
		var path := "res://data/%s.json" % name
		var text := FileAccess.get_file_as_string(path)
		assert(not text.is_empty(), "missing data file %s (run ./export_data)" % path)
		_cache[name] = JSON.parse_string(text)
	return _cache[name]


static func classes() -> Dictionary:
	return table("classes")["CLASSES"]


static func enemies() -> Dictionary:
	return table("enemies")["ENEMIES"]


## The Wizard's skill tree (hand-authored, 3D side): data/wizard_talents.json.
static func wizard_talents() -> Dictionary:
	return table("wizard_talents")


static func abilities() -> Dictionary:
	return table("abilities")


static func items() -> Dictionary:
	var all: Dictionary = table("bh_items")["ITEMS"].duplicate()
	all.merge(table("armor_tiers")["ITEMS"])
	all.merge(table("weapon_tiers")["ITEMS"])                  # and the weapon tiers
	for id in table("weapon_tiers")["OVERRIDES"]:              # equal-DPS powers for the Battleheart starter weapons
		var row: Dictionary = all[id].duplicate()
		row.merge(table("weapon_tiers")["OVERRIDES"][id], true)
		all[id] = row                  # the 3D side's armor tiers 2-10
	return all


## Shop entries of the 3D-side items: {id, minLevel, maxLevel}.
static func extra_shop() -> Array:
	return table("armor_tiers")["SHOP"] + table("weapon_tiers")["SHOP"]


static func stage_layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://models/stage/stage.json"))


## Everyone's move speed is this fraction of the 2D game's (Director: the pace of the game should slow down, halve it).
const PACE := 0.5


## Metres per second for a MOVE_SPEED stat value.
static func speed_mps(move_speed: float) -> float:
	return move_speed * PX_PER_SPEED / PX_PER_M * PACE


static func hero_speed_mps() -> float:
	return speed_mps(table("classes")["HERO_MOVE_SPEED"])


static func enemy_speed_mps(enemy_id: String) -> float:
	return speed_mps(enemies()[enemy_id]["moveSpeed"])


## Collision radius in metres (hand-authored in data/unit_sizes.json).
static func hero_radius(class_id: String) -> float:
	return table("unit_sizes")["heroes"][class_id]


static func enemy_radius(enemy_id: String) -> float:
	return table("unit_sizes")["enemies"][enemy_id]
