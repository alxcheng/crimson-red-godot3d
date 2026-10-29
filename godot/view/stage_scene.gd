extends Node3D
## The dungeon stage under the dimetric orthographic camera, at full resolution: floor/walls/props mesh, the
## torch lights from stage.json (with flicker) and the camera. Shared by the stage viewer and the sandbox battle.
##
## setup(layout, yaw_deg, pitch_deg, zoom, focus): builds everything; `camera` is the Camera3D.

const STAGE_PATH := "res://models/stage/stage.glb"

var camera: Camera3D
var layout: Dictionary
var _lights: Array[OmniLight3D] = []
var _base_energy: Array[float] = []
var _flicker: Array[float] = []
var _t := 0.0
var _focus := Vector3(0, 1.2, 0)
var _yaw := 0.0
var _pitch := 0.0
var shake := SmoothValue.new(0.0, 14.0, 0.35)    # camera shake amount; kick() it on impacts


func setup(p_layout: Dictionary, yaw_deg: float = -1.0, pitch_deg: float = -1.0, zoom: float = 1.0,
		focus: Vector2 = Vector2.INF) -> void:
	layout = p_layout
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var zone_env: Dictionary = layout.get("environment", {})                  # per-zone mood (build_zones.py); the dungeon uses the defaults
	var amb: Array = zone_env.get("ambient_color", [0.42, 0.38, 0.5])
	env.ambient_light_color = Color(amb[0], amb[1], amb[2])
	env.ambient_light_energy = float(zone_env.get("ambient_energy", 0.55))
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# a very weak cool fill from the camera side so faces away from the torches are not black
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-50, 45, 0)
	fill.light_energy = float(zone_env.get("fill_energy", 0.28))
	var fc: Array = zone_env.get("fill_color", [0.7, 0.75, 1.0])
	fill.light_color = Color(fc[0], fc[1], fc[2])
	add_child(fill)
	_load_stage()
	_add_lights()
	_make_camera(yaw_deg, pitch_deg, zoom, focus)


func _load_stage() -> void:
	var stage := (load(layout.get("_glb", STAGE_PATH)) as PackedScene).instantiate()
	add_child(stage)
	var emissive: Array = layout.get("emissive_materials", [])
	for node in stage.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.resource_name in emissive:
				var copy := mat.duplicate() as StandardMaterial3D
				copy.emission_enabled = true
				copy.emission = copy.albedo_color
				copy.emission_energy_multiplier = 1.6
				mi.set_surface_override_material(i, copy)


func _add_lights() -> void:
	for l in layout.get("lights", []):
		var light := OmniLight3D.new()
		light.position = Vector3(l["x"], l["y"], l["z"])
		light.light_color = Color(l["color"][0], l["color"][1], l["color"][2])
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.omni_attenuation = 1.4
		add_child(light)
		_lights.append(light)
		_base_energy.append(l["energy"])
		_flicker.append(l["flicker"])


const V_CENTER := 0.04     # nudge so the arena sits in the middle of the screen at shallow pitches


func _make_camera(yaw_deg: float, pitch_deg: float, zoom: float, focus: Vector2) -> void:
	var cam_data: Dictionary = layout["camera"]
	_yaw = deg_to_rad(cam_data["yaw_deg"] if yaw_deg < 0.0 else yaw_deg)
	_pitch = deg_to_rad(cam_data["pitch_deg"] if pitch_deg < 0.0 else pitch_deg)
	var bounds: Dictionary = layout["bounds"]
	var width: float = bounds["max_x"] - bounds["min_x"]
	var depth: float = bounds["max_z"] - bounds["min_z"]
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Frame the whole arena for any yaw / pitch: the rotated rectangle's horizontal screen extent, and its ground
	# depth foreshortened by sin(pitch) plus the far wall's height. `size` is the vertical extent; width follows aspect.
	var screen_w := width * absf(cos(_yaw)) + depth * absf(sin(_yaw))
	var ground_depth := width * absf(sin(_yaw)) + depth * absf(cos(_yaw))
	var screen_h := ground_depth * sin(_pitch) + 4.2 * cos(_pitch)
	camera.size = maxf(screen_h, screen_w / (16.0 / 9.0)) * 1.04 * zoom
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	if focus != Vector2.INF:
		_focus = Vector3(focus.x, 1.2, focus.y)
	_place_camera(Vector2.ZERO)


func _place_camera(offset: Vector2) -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.position = _focus + dir * 60.0
	camera.look_at(_focus, Vector3.UP)
	camera.h_offset = offset.x
	camera.v_offset = offset.y + camera.size * V_CENTER


func _process(delta: float) -> void:
	_t += delta
	for i in _lights.size():
		var n := sin(_t * 9.0 + i * 1.7) * 0.5 + sin(_t * 23.0 + i * 4.1) * 0.5
		_lights[i].light_energy = _base_energy[i] * (1.0 + _flicker[i] * 0.35 * n)
	shake.update(delta)
	if camera != null:
		camera.h_offset = sin(_t * 61.0) * shake.value
		camera.v_offset = cos(_t * 53.0) * shake.value + camera.size * V_CENTER


## Ground point (x, z) under a screen position, or Vector2.INF when the ray misses the floor.
func ground_at(screen_pos: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return Vector2.INF
	return Vector2(hit.x, hit.z)
