extends Node3D
## Stage viewer: the cobblestone dungeon under the dimetric camera, at full resolution.
## Run: ./view_stage [--pitch=30] [--yaw=45] [--units] [--shot=name]
##   --pitch / --yaw   camera angles in degrees (default: sideways top-down yaw 0 pitch 40; the old isometric was yaw 45 pitch 30)
##   --units           stand a Knight, Goblin and Skeleton on the party / enemy spawns for scale
##   --shot=name       save shots/stage_<name>.png and quit (for checking)
##   --zoom=1.0        multiply the framing (smaller = closer)
##   --focus=x,z       look at this ground point instead of the arena centre (use with --zoom)

const StageScene := preload("res://view/stage_scene.gd")

var _stage


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return default


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/stage/stage.json"))
	_stage = StageScene.new()
	add_child(_stage)
	var focus := Vector2.INF
	var fa := _arg("focus", "").split(",")
	if fa.size() == 2:
		focus = Vector2(float(fa[0]), float(fa[1]))
	_stage.setup(layout, float(_arg("yaw", "-1")), float(_arg("pitch", "-1")), float(_arg("zoom", "1.0")), focus)
	if "--units" in OS.get_cmdline_user_args():
		_place_units(layout)
	if not _arg("shot", "").is_empty():
		_take_shot.call_deferred()


func _place_units(layout: Dictionary) -> void:
	var spawns: Dictionary = layout["spawns"]
	for i in 4:
		_add_unit("knight", spawns["party"][i], 90.0, "Idle", true)
	_add_unit("goblin", spawns["enemy_inside"][0], -90.0, "Idle", false)
	_add_unit("skeleton", spawns["enemy_inside"][1], -90.0, "Idle", false)
	_add_unit("goblin", {"x": 11.0, "z": 0.0}, -90.0, "Move", false)


func _add_unit(model: String, spot: Dictionary, yaw_deg: float, clip: String, sword: bool) -> void:
	var unit := (load("res://models/%s.glb" % model) as PackedScene).instantiate() as Node3D
	add_child(unit)
	unit.position = Vector3(spot["x"], 0, spot["z"])
	unit.rotation_degrees.y = yaw_deg
	var player := unit.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation(clip):
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
	if sword:
		var skel := unit.find_child("Skeleton3D", true, false) as Skeleton3D
		var weapon := (load("res://models/sword.glb") as PackedScene).instantiate() as Node3D
		var attach := BoneAttachment3D.new()
		attach.bone_name = "hand_R"
		skel.add_child(attach)
		attach.add_child(weapon)
		weapon.position = Vector3(0, 0.07, 0)
		weapon.rotation_degrees = Vector3(-40, 0, 0)
		weapon.rotate_object_local(Vector3.UP, deg_to_rad(90.0))


func _take_shot() -> void:
	DirAccess.make_dir_recursive_absolute("res://shots")
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://shots/stage_%s.png" % _arg("shot", "view"))
	get_viewport().get_texture().get_image().save_png(path)
	print("STAGE_SHOT ", path)
	get_tree().quit()
