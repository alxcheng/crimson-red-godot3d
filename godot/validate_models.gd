extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://validate_models.gd
## Checks the exported animation data, independently of the Blender build script.

const CLIPS := ["Idle", "Move", "Attack1", "TakeHit", "Death"]
const LOOPS := ["Idle", "Move"]
const REQUIRED_BONES := ["root", "hips", "spine1", "spine2", "neck", "head",
	"upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R", "hand_L", "hand_R",
	"thigh_L", "thigh_R", "shin_L", "shin_R", "foot_L", "foot_R", "toe_L", "toe_R"]
# The authored foot pivot sits 85 mm above the sole. Allow 3 mm for glTF import
# key reduction / quaternion interpolation, while rejecting visible sliding or sinking.
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
	for model in ["knight", "mannequin"]:
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
		for bone in REQUIRED_BONES:
			_check(bone in names, "%s: missing shared bone %s" % [model, bone])
		if _reference_bones.is_empty():
			_reference_bones = names
			_reference_parents = parents
		else:
			_check(names == _reference_bones, "%s: shared bone names/order differ" % model)
			_check(parents == _reference_parents, "%s: shared bone hierarchy differs" % model)
		for clip in CLIPS:
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
			# Sample at least 60 Hz, including interpolated poses between baked 30 Hz keys.
			var intervals := maxi(32, ceili(animation.length * 60.0))
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
				if clip in ["Idle", "Attack1", "Move"]:
					var feet := _feet(skeleton)
					var grounded := false
					for foot in 2:
						var drift := feet[foot].distance_to(first_feet[foot])
						max_foot_drift = maxf(max_foot_drift, drift)
						var height := feet[foot].y - ANKLE_HEIGHT
						foot_lift[foot] = maxf(foot_lift[foot], height)
						grounded = grounded or absf(height) <= CONTACT_TOLERANCE
						_check(height >= -CONTACT_TOLERANCE,
							"%s/%s: foot %d below ground at sample %d" % [model, clip, foot, sample])
						if clip in ["Idle", "Attack1"]:
							_check(drift <= CONTACT_TOLERANCE,
								"%s/%s: planted foot %d drift %.5fm at sample %d" %
								[model, clip, foot, drift, sample])
					_check(grounded, "%s/%s: no grounded foot at sample %d" % [model, clip, sample])
			if clip == "Move":
				for foot in 2:
					_check(foot_lift[foot] > 0.03, "%s/Move: foot %d never clears the ground" % [model, foot])
			elif clip in ["Idle", "Attack1"]:
				print("PLANTED %s/%s maximum drift %.5fm" % [model, clip, max_foot_drift])
			_check(moved, "%s/%s: no evaluated skeletal movement" % [model, clip])
			animation.loop_mode = original_loop
			print("CHECKED %s/%s %.3fs" % [model, clip, animation.length])
		unit.free()
	print("MODEL_VALIDATION_PASS" if _failures == 0 else "MODEL_VALIDATION_FAIL: %d" % _failures)
	quit(0 if _failures == 0 else 1)
