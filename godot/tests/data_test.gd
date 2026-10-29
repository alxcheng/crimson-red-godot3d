extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://tests/data_test.gd
## Checks that the exported data is present and converts to the numbers the movement design expects.
const GameData := preload("res://sim/game_data.gd")
var _fail := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error(msg)


func _near(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	for name in ["classes", "enemies", "abilities", "talents", "tutorial", "sprite_bounds", "bh_items", "bh_rewards",
			"wave_tuning", "unit_sizes", "_meta"]:
		_check(GameData.table(name) != null, "data/%s.json missing or invalid" % name)
	# every hero and enemy has a collision radius
	for id in GameData.classes():
		_check(GameData.table("unit_sizes")["heroes"].has(id), "no radius for hero %s" % id)
	for id in GameData.enemies():
		_check(GameData.table("unit_sizes")["enemies"].has(id), "no radius for enemy %s" % id)
	# the original speeds halved (Director: slow the game's pace, PACE = 0.5)
	_check(_near(GameData.hero_speed_mps(), 3.09 * 0.5), "hero speed %f" % GameData.hero_speed_mps())
	_check(_near(GameData.enemy_speed_mps("skeleton"), 1.93 * 0.5), "skeleton speed %f" % GameData.enemy_speed_mps("skeleton"))
	_check(_near(GameData.enemy_speed_mps("goblin"), 2.36 * 0.5), "goblin speed %f" % GameData.enemy_speed_mps("goblin"))
	# the knight's auto-attack lands at 14/60 s, which is where the 3D Attack1 "Contact" marker is
	_check(_near(GameData.abilities()["KnightAutoAttack"]["delay"], 14.0 / 60.0, 0.001), "knight delay")
	_check(GameData.items().size() > 100, "items missing")
	_check(GameData.stage_layout()["spawns"]["party"].size() == 4, "stage spawns")
	print("DATA_PASS" if _fail == 0 else "DATA_FAIL: %d" % _fail)
	quit(0 if _fail == 0 else 1)
