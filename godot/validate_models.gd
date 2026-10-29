extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://validate_models.gd
## Checks the exported animation data, independently of the Blender build script.

const MODELS := ["knight", "mannequin", "goblin", "skeleton", "witch"]
const CLIPS := ["Idle", "Move", "Walk", "Attack1", "Attack2", "Attack3", "TakeHit", "Death"]
const HUMANOID_EXTRA := ["TwoHandIdle", "TwoHandAttack", "StaffRaise", "StaffCast", "OffhandAttack"]   # knight / mannequin only
const WITCH_CLIPS := ["Idle", "Move", "Walk", "Cast", "TakeHit", "Death"]
const PLANTED := ["Idle", "Attack1", "Attack2", "Attack3", "TwoHandIdle", "TwoHandAttack", "StaffRaise", "StaffCast", "OffhandAttack", "Cast"]
const LOOPS := ["Idle", "Move", "Walk"]
const REQUIRED_BONES := ["root", "hips", "spine1", "spine2", "neck", "head",
	"clavicle_L", "clavicle_R", "upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R",
	"hand_L", "hand_R", "pelvis_L", "pelvis_R", "thigh_L", "thigh_R",
	"shin_L", "shin_R", "foot_L", "foot_R", "toe_L", "toe_R"]
# [tuned] The authored foot pivot sits 85 mm above the sole. Allow 3 mm at human
# scale for glTF interpolation, while rejecting visible sliding or sinking.
const ANKLE_HEIGHT := 0.085
const CONTACT_TOLERANCE := 0.003
var _failures := 0
var _reference_bones: Array[String] = []
var _reference_parents: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose(bone))
	return result


func _same_pose(a: Transform3D, b: Transform3D) -> bool:
	# glTF quaternion and translation values are stored with float32 precision.
	return a.origin.distance_to(b.origin) < 0.0001 \
		and a.basis.x.distance_to(b.basis.x) < 0.0001 \
		and a.basis.y.distance_to(b.basis.y) < 0.0001 \
		and a.basis.z.distance_to(b.basis.z) < 0.0001


func _feet(skeleton: Skeleton3D) -> Array[Vector3]:
	skeleton.force_update_all_bone_transforms()
	var result: Array[Vector3] = []
	for side in ["L", "R"]:
		var bone := skeleton.find_bone("foot_" + side)
		result.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
	return result


func _run() -> void:
	for model in MODELS:
		var scene := load("res://models/%s.glb" % model) as PackedScene
		_check(scene != null, "%s: model cannot load" % model)
		if scene == null:
			continue
		var unit := scene.instantiate()
		root.add_child(unit)
		await process_frame
		var player := unit.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeleton := unit.find_child("Skeleton3D", true, false) as Skeleton3D
		_check(player != null and skeleton != null, "%s: animation player or skeleton missing" % model)
		if player == null or skeleton == null:
			unit.free()
			continue
		var names: Array[String] = []
		var parents: Array[int] = []
		for bone in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(bone))
			parents.append(skeleton.get_bone_parent(bone))
		_check(names.size() == REQUIRED_BONES.size(),
			"%s: expected %d reusable bones, found %d" % [model, REQUIRED_BONES.size(), names.size()])
		var core_complete := true
		for bone in REQUIRED_BONES:
			_check(bone in names, "%s: missing shared bone %s" % [model, bone])
			core_complete = core_complete and bone in names
		if not core_complete:
			unit.free()
			continue
		for bone_index in names.size():
			_check((parents[bone_index] == -1) == (names[bone_index] == "root"),
				"%s: only root may have no parent (%s)" % [model, names[bone_index]])
		for bone in names:
			_check(bone != "hair_back" and not bone.begins_with("tab_"),
				"%s: removed hair/loincloth bone remains: %s" % [model, bone])
		var rig_scale := absf(skeleton.global_transform.basis.get_scale().y)
		_check(rig_scale > 0.0 and is_finite(rig_scale), "%s: invalid rig scale" % model)
		var ankle_height := skeleton.global_position.y + ANKLE_HEIGHT * rig_scale
		var contact_tolerance := CONTACT_TOLERANCE * rig_scale
		if _reference_bones.is_empty():
			_reference_bones = names
			_reference_parents = parents
		else:
			_check(names == _reference_bones, "%s: shared bone names/order differ" % model)
			_check(parents == _reference_parents, "%s: shared bone hierarchy differs" % model)
		for clip in (WITCH_CLIPS if model == "witch" else CLIPS + (HUMANOID_EXTRA if model in ["knight", "mannequin"] else [])):
			_check(player.has_animation(clip), "%s: missing clip %s" % [model, clip])
			if not player.has_animation(clip):
				continue
			var animation := player.get_animation(clip)
			_check(is_finite(animation.length) and animation.length > 0.0,
				"%s/%s: invalid duration" % [model, clip])
			_check(animation.get_track_count() > 0, "%s/%s: empty clip" % [model, clip])
			# Disable looping while checking the actual final key, rather than a wrapped start.
			var original_loop := animation.loop_mode
			animation.loop_mode = Animation.LOOP_NONE
			player.play(clip)
			player.advance(0.0)
			player.pause()
			player.seek(0.0, true)
			var first := _poses(skeleton)
			var first_feet := _feet(skeleton)
			var max_foot_drift := 0.0
			var foot_lift := [0.0, 0.0]
			var moved := false
			var airborne := 0
			# Sample at least 120 Hz, including interpolated poses between baked 60 Hz keys.
			var intervals := maxi(32, ceili(animation.length * 120.0))
			for sample in intervals + 1:
				player.seek(animation.length * float(sample) / float(intervals), true)
				var current := _poses(skeleton)
				for bone in current.size():
					_check(current[bone].is_finite(), "%s/%s: nonfinite bone %s at sample %d" %
						[model, clip, names[bone], sample])
					moved = moved or not _same_pose(first[bone], current[bone])
					if sample == intervals and clip in LOOPS:
						_check(_same_pose(first[bone], current[bone]),
							"%s/%s: loop seam on %s" % [model, clip, names[bone]])
				if clip in PLANTED or clip in ["Move", "Walk"]:
					var feet := _feet(skeleton)
					var grounded := false
					for foot in 2:
						var drift := feet[foot].distance_to(first_feet[foot])
						max_foot_drift = maxf(max_foot_drift, drift)
						var height := feet[foot].y - ankle_height
						foot_lift[foot] = maxf(foot_lift[foot], height)
						grounded = grounded or absf(height) <= contact_tolerance
						_check(height >= -contact_tolerance,
							"%s/%s: foot %d below ground at sample %d" % [model, clip, foot, sample])
						if clip in PLANTED:
							_check(drift <= contact_tolerance,
								"%s/%s: planted foot %d drift %.5fm at sample %d" %
								[model, clip, foot, drift, sample])
					if clip in ["Move", "Walk"]:
						# A run has a flight phase; require the body to be on the ground most of the time.
						airborne += 0 if grounded else 1
					else:
						_check(grounded, "%s/%s: no grounded foot at sample %d" % [model, clip, sample])
			if clip in ["Move", "Walk"]:
				_check(float(airborne) / float(intervals + 1) <= 0.35, "%s/Move: airborne for too much of the run (%d of %d samples)" % [model, airborne, intervals + 1])
				for foot in 2:
					_check(foot_lift[foot] > 0.03 * rig_scale, "%s/Move: foot %d never clears the ground" % [model, foot])
			elif clip in PLANTED:
				print("PLANTED %s/%s maximum drift %.5fm" % [model, clip, max_foot_drift])
			if clip == "Death":
				skeleton.force_update_all_bone_transforms()
				var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine2")).origin
				var chest_height := chest.y - skeleton.global_position.y
				# [tuned] A finished collapse puts the upper torso near the floor.
				_check(chest_height >= -0.05 * rig_scale and chest_height <= 0.35 * rig_scale,
					"%s/Death: final chest height %.4fm is not grounded" % [model, chest_height])
			_check(moved, "%s/%s: no evaluated skeletal movement" % [model, clip])
			animation.loop_mode = original_loop
			print("CHECKED %s/%s %.3fs" % [model, clip, animation.length])
		unit.free()
	print("MODEL_VALIDATION_PASS" if _failures == 0 else "MODEL_VALIDATION_FAIL: %d" % _failures)
	quit(0 if _failures == 0 else 1)
