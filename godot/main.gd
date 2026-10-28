extends Node3D
# Test viewer: one rigged unit on a stage. Two models (knight, mannequin) share one skeleton and
# one set of animations; two looks (ps1, pixel) are render presets.
# Keys: 1-5 animation, SPACE next animation, arrows turn, P switch look, M switch model.
# Command line (after `--`):  --model=knight|mannequin  --look=ps1|pixel --angle=25
#   --shots  saves 3 PNGs per animation to shots/ and quits       (for checking)
#   --turn   saves level front/side/back views and a face close-up (for checking)
#   --sequence saves 24 evenly spaced frames of Idle, Move and Attack1 (for checking)

const MODELS := {
	"knight": {"path": "res://models/knight.glb", "sword": true},
	"mannequin": {"path": "res://models/mannequin.glb", "sword": false},
}
const CLIPS := ["Idle", "Move", "Attack1", "TakeHit", "Death"]
const LOOPING := ["Idle", "Move"]
const SWORD_PATH := "res://models/sword.glb"
const HAND_BONE := "hand_R"
const HAND_OFFSET := Vector3(0, 0.07, 0)        # hand bone length: from the wrist to the palm
const SWORD_ROTATION := Vector3(-40, 0, 0)     # [tuned] glTF blade is +Y; tilt forward/up from the palm instead of back/down.

# Render presets. size = the internal render resolution (scaled up with nearest filtering).
const LOOPS_NOTE := "ps1: textured-era look, dither + vertex snap. pixel: huge pixels, soft real shadows."
const LOOKS := {
	"ps1": {
		"size": Vector2i(400, 225), "post": true, "ps1_models": true,
		"bg": Color(0, 0, 0), "ambient": Color(1, 1, 1), "ambient_energy": 0.4,
		"sun_shadow": false, "floor": Color(0.14, 0.03, 0.03), "disc": false,
		"cam_pos": Vector3(0, 4.2, 3.2), "cam_target": Vector3(0, 0.9, 0), "fov": 30.0,
	},
	"pixel": {
		"size": Vector2i(96, 54), "post": false, "ps1_models": false,
		"bg": Color(0.56, 0.62, 0.92), "ambient": Color(0.15, 0.2, 1.0), "ambient_energy": 0.8,
		"sun_shadow": true, "floor": Color(0.52, 0.57, 0.92), "disc": true,
		"cam_pos": Vector3(0, 2.3, 5.2), "cam_target": Vector3(0, 0.95, 0), "fov": 32.0,
	},
}

var _model := "knight"
var _look := "ps1"
var _unit: Node3D
var _player: AnimationPlayer
var _label: Label
var _clip := 0
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _floor_mat: StandardMaterial3D
var _disc: MeshInstance3D
var _world: SubViewport
var _post_rect: TextureRect
var _model_shader: Shader = load("res://shaders/ps1_model.gdshader")
var _post_shader: Shader = load("res://shaders/ps1_post.gdshader")


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return default


func _ready() -> void:
	_model = _arg("model", "knight")
	_look = _arg("look", "ps1")
	_build_view()
	_build_stage()
	_load_unit()
	_apply_look()
	if "--turn" in OS.get_cmdline_user_args():
		_take_turnaround()
	elif "--sequence" in OS.get_cmdline_user_args():
		_take_sequence()
	elif "--shots" in OS.get_cmdline_user_args():
		_take_shots()
	else:
		_play(0)


func _build_view() -> void:
	# 3D renders into a small SubViewport; a full-window TextureRect shows it, scaled with
	# nearest filtering and (for the ps1 look) run through the post shader.
	_world = SubViewport.new()
	_world.msaa_3d = Viewport.MSAA_DISABLED
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_world)
	var layer := CanvasLayer.new()
	add_child(layer)
	_post_rect = TextureRect.new()
	_post_rect.texture = _world.get_texture()
	_post_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_post_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_post_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_post_rect)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)


func _build_stage() -> void:
	_cam = Camera3D.new()
	_world.add_child(_cam)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, 50, 0)
	_sun.shadow_blur = 0.0
	_world.add_child(_sun)

	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = _env
	_world.add_child(we)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	_floor_mat = StandardMaterial3D.new()
	plane.material = _floor_mat
	ground.mesh = plane
	_world.add_child(ground)

	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.4
	cyl.height = 0.02
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.66, 0.7, 0.96)
	cyl.material = dm
	_disc.mesh = cyl
	_disc.position.y = 0.012
	_world.add_child(_disc)


func _load_unit() -> void:
	if _unit:
		_unit.queue_free()
	var def: Dictionary = MODELS[_model]
	_unit = (load(def["path"]) as PackedScene).instantiate()
	_world.add_child(_unit)
	_unit.rotation_degrees.y = float(_arg("angle", "25"))
	_player = _unit.find_child("AnimationPlayer", true, false)
	for clip in CLIPS:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = \
				Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		else:
			push_warning("missing animation: " + clip)
	if def["sword"]:
		var skel := _unit.find_child("Skeleton3D", true, false) as Skeleton3D
		var attach := BoneAttachment3D.new()
		attach.bone_name = HAND_BONE
		skel.add_child(attach)
		var sword := (load(SWORD_PATH) as PackedScene).instantiate() as Node3D
		attach.add_child(sword)
		sword.position = HAND_OFFSET
		sword.rotation_degrees = SWORD_ROTATION


func _apply_look() -> void:
	var look: Dictionary = LOOKS[_look]
	var size: Vector2i = look["size"]
	_world.size = size
	var pm := ShaderMaterial.new()
	pm.shader = _post_shader
	pm.set_shader_parameter("internal_size", Vector2(size))
	_post_rect.material = pm if look["post"] else null
	_env.background_color = look["bg"]
	_env.ambient_light_color = look["ambient"]
	_env.ambient_light_energy = look["ambient_energy"]
	_sun.shadow_enabled = look["sun_shadow"]
	_floor_mat.albedo_color = look["floor"]
	_disc.visible = look["disc"]
	_cam.fov = look["fov"]
	_cam.position = look["cam_pos"]
	_cam.look_at(look["cam_target"])
	for node in _world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == _disc or mi.get_parent() == _world:
			continue
		for i in mi.mesh.get_surface_count():
			if not look["ps1_models"]:
				mi.set_surface_override_material(i, null)
				continue
			var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
			var m := ShaderMaterial.new()
			m.shader = _model_shader
			m.set_shader_parameter("snap_resolution", Vector2(size))
			if base:
				m.set_shader_parameter("albedo", base.albedo_color)
			mi.set_surface_override_material(i, m)
	_update_label()


func _update_label() -> void:
	_label.text = "%s / %s / %s   (1-5 anim, SPACE next, arrows turn, P look, M model)" % [
		_model, _look, CLIPS[_clip]]


func _play(i: int) -> void:
	_clip = posmod(i, CLIPS.size())
	_player.play(CLIPS[_clip])
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_play(event.keycode - KEY_1)
		elif event.keycode == KEY_SPACE:
			_play(_clip + 1)
		elif event.keycode == KEY_P:
			_look = "pixel" if _look == "ps1" else "ps1"
			_apply_look()
		elif event.keycode == KEY_M:
			_model = "mannequin" if _model == "knight" else "knight"
			_load_unit()
			await get_tree().process_frame
			_apply_look()
			_play(_clip)
		elif event.keycode == KEY_LEFT:
			_unit.rotation_degrees.y += 30
		elif event.keycode == KEY_RIGHT:
			_unit.rotation_degrees.y -= 30


func _save_shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://shots/%s_%s_%s.png" % [_model, _look, name])
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save screenshot: " + path)
		get_tree().quit(1)


func _take_shots() -> void:
	DirAccess.make_dir_recursive_absolute("res://shots")
	for i in CLIPS.size():
		_play(i)
		_player.pause()
		var length := _player.get_animation(CLIPS[i]).length
		for frac in [0.25, 0.5, 0.9]:
			_player.seek(length * frac, true)
			await _save_shot("%s_%d" % [CLIPS[i], int(frac * 100)])
	print("SHOTS_DONE")
	get_tree().quit()


func _take_sequence() -> void:
	DirAccess.make_dir_recursive_absolute("res://shots")
	for clip in ["Idle", "Move", "Attack1"]:
		_play(CLIPS.find(clip))
		_player.pause()
		var length := _player.get_animation(clip).length
		# [tuned] 24 samples show contacts and follow-through; loops omit the duplicate end.
		for frame in 24:
			var fraction := float(frame) / (24.0 if clip in LOOPING else 23.0)
			_player.seek(length * fraction, true)
			await _save_shot("%s_seq_%02d" % [clip, frame])
	print("SEQUENCE_DONE")
	get_tree().quit()


func _take_turnaround() -> void:
	# level camera, Idle pose: front / side / back, then a face close-up
	DirAccess.make_dir_recursive_absolute("res://shots")
	_cam.fov = 22.0
	_cam.position = Vector3(0, 1.0, 7.5)
	_cam.look_at(Vector3(0, 0.95, 0))
	_player.play("Idle")
	_player.seek(0.5, true)
	_player.pause()
	for a in [0, 90, 180]:
		_unit.rotation_degrees.y = a
		await _save_shot("turn_%d" % a)
	_cam.fov = 20.0
	_cam.position = Vector3(0.5, 1.8, 2.6)
	_cam.look_at(Vector3(0, 1.74, 0))
	_unit.rotation_degrees.y = 20
	await _save_shot("close")
	print("SHOTS_DONE")
	get_tree().quit()
