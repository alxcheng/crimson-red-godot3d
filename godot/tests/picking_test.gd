extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://tests/picking_test.gd
## Unit picking under the dimetric camera: the body, the feet, a margin, overlap, and misses.
const StageScene := preload("res://view/stage_scene.gd")
const Picking := preload("res://view/picking.gd")
var _fail := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error(msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# a real-sized viewport, so pixel tolerances mean what they mean on screen
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	root.add_child(vp)
	var stage = StageScene.new()
	vp.add_child(stage)
	stage.setup(JSON.parse_string(FileAccess.get_file_as_string("res://models/stage/stage.json")))
	await process_frame
	var cam: Camera3D = stage.camera
	var a := {"id": 1, "pos": Vector2(-2.0, 0.0), "radius": 0.45, "height": 1.95}
	var b := {"id": 2, "pos": Vector2(3.0, 1.0), "radius": 0.35, "height": 1.4}
	var list := [a, b]
	var feet_a := cam.unproject_position(Vector3(-2.0, 0.0, 0.0))
	var mid_a := cam.unproject_position(Vector3(-2.0, 1.0, 0.0))
	var head_a := cam.unproject_position(Vector3(-2.0, 1.9, 0.0))
	_check(Picking.pick(cam, list, mid_a) == 1, "the middle of the body should pick the unit")
	_check(Picking.pick(cam, list, feet_a) == 1, "the feet should pick the unit")
	_check(Picking.pick(cam, list, head_a) == 1, "the head should pick the unit")
	_check(Picking.pick(cam, list, head_a + Vector2(0, -9)) == 1, "just above the head should still pick (margin)")
	_check(Picking.pick(cam, list, mid_a + Vector2(10, 0)) == 1, "a few pixels beside the body should still pick (margin)")
	_check(Picking.pick(cam, list, mid_a + Vector2(80, 0)) == -1, "well away from any unit should pick nothing")
	_check(Picking.pick(cam, list, cam.unproject_position(Vector3(0.5, 0, -3.0))) == -1, "empty floor should pick nothing")
	# the old test (ground point inside the collision circle) would have missed the visible body: prove the body works
	var ground_under_mid = stage.ground_at(mid_a)
	_check(ground_under_mid.distance_to(Vector2(-2.0, 0.0)) > 0.45, "the floor point under the body should be OUTSIDE the collision circle (the bug this fixes)")
	# overlap: a unit standing in front (closer to the camera) of another wins where their bodies overlap
	var front := {"id": 3, "pos": Vector2(-1.2, 0.8), "radius": 0.45, "height": 1.95}   # +x, +z = nearer the camera
	var behind := {"id": 4, "pos": Vector2(-1.7, 0.2), "radius": 0.45, "height": 1.95}
	var overlap_point := cam.unproject_position(Vector3(-1.45, 1.0, 0.5))
	var r := Picking.pick(cam, [behind, front], overlap_point)
	_check(r == 3, "the front-most unit should win where bodies overlap, got %d" % r)
	# precise click on the rear unit's exposed side still picks the rear unit
	var rear_only := cam.unproject_position(Vector3(-1.7, 2.0, 0.2))   # the rear unit's head, above the front unit's
	var r2 := Picking.pick(cam, [behind, front], rear_only)
	_check(r2 == 4, "a click on the rear unit's own body should pick it, got %d" % r2)
	print("PICKING_PASS" if _fail == 0 else "PICKING_FAIL: %d" % _fail)
	quit(0 if _fail == 0 else 1)
