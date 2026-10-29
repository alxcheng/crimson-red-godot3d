extends Node3D
## The move-command marker on the floor (StarCraft-style): a green ring with four arrow heads pointing in, which pops in
## large, settles and flashes until the hero arrives, is re-ordered, or dies. One per hero (the view keeps them by hero id).
## All motion is SmoothValue: the pop-in scale, the flash level, the fade-out.

const COLOR := Color(0.15, 1.0, 0.3)
const RADIUS := 0.4
const FLASH_PERIOD := 0.32

var _mesh := ImmediateMesh.new()
var _scale := SmoothValue.new(1.8, 16.0, 0.5)
var _flash := SmoothValue.new(1.0, 22.0)
var _alpha := SmoothValue.new(1.0, 10.0)
var _age := 0.0
var _flash_t := 0.0
var _flash_high := true
var dying := false


func _init() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	mi.material_override = m
	add_child(mi)
	_scale.target = 1.0
	_alpha.snap(0.0)
	_alpha.target = 1.0


func place(ground: Vector2) -> void:
	position = Vector3(ground.x, 0.06, ground.y)


func age() -> float:
	return _age


## Start fading out; the view frees the node once finished() is true.
func dismiss() -> void:
	dying = true
	_alpha.target = 0.0


func finished() -> bool:
	return dying and _alpha.value < 0.02


func update(delta: float) -> void:
	_age += delta
	_flash_t += delta
	if _flash_t >= FLASH_PERIOD * 0.5:
		_flash_t = 0.0
		_flash_high = not _flash_high
		_flash.target = 1.0 if _flash_high else 0.25
	_scale.update(delta)
	_flash.update(delta)
	_alpha.update(delta)
	var a: float = clampf(_alpha.value, 0.0, 1.0)
	var lvl: float = clampf(_flash.value, 0.0, 1.0)
	var col := Color(0.15, 1.0, 0.3).lerp(Color(1, 1, 1), lvl * 0.35)
	col.a = a * (0.35 + 0.65 * lvl)
	var s: float = maxf(_scale.value, 0.05)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# ring
	var r_out := RADIUS * s
	var r_in := r_out * 0.86
	for i in 32:
		var a0 := TAU * i / 32.0
		var a1 := TAU * (i + 1) / 32.0
		_quad(Vector2(cos(a0), sin(a0)) * r_in, Vector2(cos(a0), sin(a0)) * r_out, Vector2(cos(a1), sin(a1)) * r_out, Vector2(cos(a1), sin(a1)) * r_in, col)
	# four arrow heads on the axes, pointing at the centre
	for k in 4:
		var dir := Vector2(cos(k * PI / 2.0), sin(k * PI / 2.0))
		var side := Vector2(-dir.y, dir.x)
		var tip := dir * r_in * 0.5
		var base := dir * r_in * 0.95
		_tri(tip, base + side * r_out * 0.22, base - side * r_out * 0.22, col)
	_mesh.surface_end()


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	for p in [a, b, c]:
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(Vector3(p.x, 0.0, p.y))


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, d, col)
