extends Node3D
## One battle unit on screen: the rigged model (plus weapon and gear), driven every frame from the sandbox
## sim unit: position, heading, and the clip that matches what the unit is doing.
## The sim owns timing; this only plays animations. The Move clip is played at (sim speed / the clip's
## ground speed), clamped to 0.6-1.4x, so the feet do not skate.

const CLIP_INFO_PATH := "res://models/clip_info.json"
const RUN_THRESHOLD_RATIO := 0.8      # of the run clip's ground speed: below it the unit walks, from it up it runs
const OUTLINE_WIDTH := 0.03         # metres the white silhouette grows (about one logical pixel at 960x540)
const PLAYABLE := ["knight", "mannequin"]
const PLAYABLE_HEIGHT := 0.9           # Director: 70% was too short, 77% still too squat
const PLAYABLE_WIDTH := 1.05
const TORSO_SCALE := 1.12             # torso and shoulders larger (the head is compensated, so helmets read smaller)
const GEAR_PATH := "res://models/gear/%s.glb"
const SWORD_PATH := "res://models/sword.glb"
const SANDBOX := preload("res://sim/sandbox_battle.gd")

static var _clip_info: Dictionary = {}

var unit                      # SandboxBattle.Unit
var player: AnimationPlayer
var _ground_speed := 2.5
var _walk_speed := 1.0
var _run_threshold := 2.0
var _last_swing := 0
var _last_state := -1
var _dead_played := false


func setup(u) -> void:
	unit = u
	if _clip_info.is_empty():
		_clip_info = JSON.parse_string(FileAccess.get_file_as_string(CLIP_INFO_PATH))
	var scene := load("res://models/%s.glb" % u.model) as PackedScene
	var model := scene.instantiate() as Node3D
	add_child(model)
	if u.model in PLAYABLE:
		model.scale = Vector3(PLAYABLE_WIDTH, PLAYABLE_HEIGHT, PLAYABLE_WIDTH)      # Director: playable characters are squat (90% height, 105% width)
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in player.get_animation_list():
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Move", "Walk"] else Animation.LOOP_NONE
	_ground_speed = _clip_info[u.model]["clips"]["Move"]["ground_speed_mps"]
	_walk_speed = _clip_info[u.model]["clips"]["Walk"]["ground_speed_mps"]
	_run_threshold = _ground_speed * RUN_THRESHOLD_RATIO
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if u.weapon != "":
		_attach_weapon(skeleton, u.weapon)
	for gear_id in u.gear:
		_attach_gear(skeleton, gear_id)
	if u.model in PLAYABLE:
		_scale_torso(player, skeleton)
	# Outlines. Every body material WRITES stencil 1; the overlay is an inverted hull (back faces grown outwards) that only
	# draws where the stencil is NOT 1, so the white line follows the outer silhouette of the whole unit (and of units
	# overlapping each other) with no lines between its parts. A faint black hull behind it draws the facet contours.
	_hull = _outline_material().duplicate() as StandardMaterial3D      # one per unit, so its colour can change on its own
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat != null and mat.stencil_mode != BaseMaterial3D.STENCIL_MODE_CUSTOM:
				mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
				mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
				mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
				mat.stencil_reference = 1
		mi.material_overlay = _hull
		if ghost:
			mi.material_override = _ghost_material()
	sync(0.0)
	player.play("Idle")


var _hull: StandardMaterial3D
var ghost := false                                  # Mirror Image: a flat bright-blue copy (set before setup())
var outline_ice := false                            # Ice Block / Hellfire: the caster glows pale blue
var outline_gold := false                           # an ally an ability would heal / buff (aiming)
var _gold_t := 0.0                                  # a heal just landed: the outline glows holy gold for a moment
var outline_red := false                            # set by the battle view: this enemy is the target of a click / an order
var _outline_col := SmoothColor.new(Color.WHITE, 16.0)
static var _outline_mat: StandardMaterial3D
static var _ghost_mat: StandardMaterial3D


func _ghost_material() -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.albedo_color = Color(0.35, 0.68, 1.0, 0.62)
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _ghost_mat


func _outline_material() -> StandardMaterial3D:
	if _outline_mat == null:
		var contour := ShaderMaterial.new()                 # faint black facet contour (inverted hull, after skinning)
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode cull_front, unshaded, blend_mix;\nuniform float width = 0.02;\nuniform float strength = 0.45;\nvoid vertex() { VERTEX += NORMAL * width; }\nvoid fragment() { ALBEDO = vec3(0.0); ALPHA = strength; }\n"
		contour.shader = sh
		var hull := StandardMaterial3D.new()                # white silhouette: only where the stencil was not written
		hull.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hull.albedo_color = Color.WHITE
		hull.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA      # drawn after every opaque body has written the stencil
		hull.cull_mode = BaseMaterial3D.CULL_FRONT
		hull.grow = true
		hull.grow_amount = OUTLINE_WIDTH
		hull.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		hull.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
		hull.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
		hull.stencil_reference = 1
		hull.next_pass = contour
		_outline_mat = hull
	return _outline_mat


## Bigger torso and shoulders: scale spine1 (everything above it grows), then shrink the neck back so the head keeps its size.
func _scale_torso(anim_player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var spine := skeleton.find_bone("spine1")
	var neck := skeleton.find_bone("neck")
	for clip in anim_player.get_animation_list():
		var a := anim_player.get_animation(clip)
		for i in range(a.get_track_count() - 1, -1, -1):      # scale is ours now: drop any exported scale tracks
			var path := String(a.track_get_path(i))
			if path.ends_with(":scale") and (path.contains("spine1") or path.contains("neck")):
				a.remove_track(i)
	skeleton.set_bone_pose_scale(spine, Vector3.ONE * TORSO_SCALE)
	skeleton.set_bone_pose_scale(neck, Vector3.ONE / TORSO_SCALE)


func _attach_weapon(skeleton: Skeleton3D, weapon_id: String) -> void:
	var path := SWORD_PATH if weapon_id == "sword_iron" else GEAR_PATH % weapon_id
	var attach := BoneAttachment3D.new()
	attach.bone_name = "hand_R"
	skeleton.add_child(attach)
	var weapon := (load(path) as PackedScene).instantiate() as Node3D
	attach.add_child(weapon)
	weapon.position = Vector3(0, 0.07, 0)
	weapon.rotation_degrees = Vector3(-40, 0, 0)
	weapon.rotate_object_local(Vector3.UP, deg_to_rad(90.0))


# Skinned gear: the gear glb carries the same 24-bone skeleton; re-parent its mesh under this unit's skeleton
# (skins bind by bone name).
func _attach_gear(skeleton: Skeleton3D, gear_id: String) -> void:
	var gear := (load(GEAR_PATH % gear_id) as PackedScene).instantiate()
	for mesh in gear.find_children("*", "MeshInstance3D", true, false):
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		skeleton.add_child(mesh)
		mesh.transform = Transform3D.IDENTITY
		(mesh as MeshInstance3D).skeleton = NodePath("..")
	gear.free()


var slow := 1.0                       # the game's speed (the battle view slows every animation with the world)
var _base_speed := 1.0


func _set_speed(x: float) -> void:
	_base_speed = x
	_apply_speed()


## A heal landed on this unit.
func flash_heal() -> void:
	_gold_t = 0.9


func _apply_speed() -> void:
	if player != null:
		player.speed_scale = _base_speed * slow * (0.0 if unit.statuses.has("STUN") else 1.0)     # a stunned unit freezes mid-pose


func sync(dt: float) -> void:
	_apply_speed()
	if _hull != null:
		_gold_t = maxf(_gold_t - dt, 0.0)
		_outline_col.target = Color(0.45, 0.75, 1.0) if ghost else (Color(1.0, 0.1, 0.1) if outline_red else (Color(1.0, 0.84, 0.28) if (outline_gold or _gold_t > 0.0) else (Color(0.62, 0.92, 1.0) if outline_ice else Color.WHITE)))
		_outline_col.update(dt)
		_hull.albedo_color = _outline_col.value
	var p: Vector2 = unit.agent.pos
	position = Vector3(p.x, 0.0, p.y)
	rotation.y = unit.heading
	var st: int = unit.state
	if st == SANDBOX.State.DEAD:
		if not _dead_played:
			_dead_played = true
			player.play("Death", 0.08)
		return
	if st == SANDBOX.State.ATTACK:
		if unit.swing != _last_swing:
			_last_swing = unit.swing
			_set_speed(1.0)
			if unit.swing_anim != "":
				player.play(unit.swing_anim, 0.05)
		_last_state = st
		return
	if st == SANDBOX.State.HIT:
		if _last_state != st:
			_set_speed(1.0)
			player.play("TakeHit", 0.03)
		_last_state = st
		return
	_last_state = st
	var speed: float = unit.agent.vel.length()
	var cur := player.current_animation
	# let a swing or a flinch play out unless the unit has started walking again
	if (cur.begins_with("Attack") or cur in ["TakeHit", "StaffRaise", "StaffCast", "Cast"]) and player.is_playing() and speed < 0.5:
		return
	if speed > 0.5:
		# walk under the threshold (its playback speeds up with the unit), run past it (same, on the run clip)
		var running: bool = speed >= _run_threshold * (0.92 if cur == "Move" else 1.0)
		var gait := "Move" if running else "Walk"
		if cur != gait:
			player.play(gait, 0.15)
		_set_speed(clampf(speed / (_ground_speed if running else _walk_speed), 0.6 if running else 0.5, 1.6 if running else 2.0))
	else:
		if cur != "Idle":
			player.play("Idle", 0.15)
		_set_speed(1.0)
