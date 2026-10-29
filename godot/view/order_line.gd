extends Node3D
## The order line: an arrow trail on the floor from the selected hero to where it was sent, or to the enemy it was
## ordered to attack (the 2D game's order line, `encounter/orderline.lua`: arrow heads, the far end glides rather than
## jumps, a pulse when it locks onto a target). Colours: white trail; the end marker is red on an enemy, green on a spot.
## All motion is SmoothValue (far end glide speed 30, as the 2D GLIDE; lock pulse).

const RED := Color(1.0, 0.1, 0.1)
const GREEN := Color(0.15, 1.0, 0.3)

var _mesh := ImmediateMesh.new()
var _end := SmoothVec2.new(Vector2.ZERO, 30.0)
var _alpha := SmoothValue.new(0.0, 12.0)
var _pulse := SmoothValue.new(0.0, 14.0, 0.4)
var _marker := SmoothColor.new(GREEN, 14.0)
var _showing := false
var _locked := false


func _init() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


## hero: the selected sandbox Unit (or null); battle: the sandbox battle.
func update_line(hero, battle, delta: float) -> void:
	var goal := Vector2.INF
	var locked := false
	if hero != null and hero.state != 4:        # State.DEAD
		if hero.ordered and hero.target >= 0 and battle.alive(hero.target):
			goal = battle.units[hero.target].agent.pos
			locked = true
		elif hero.move_order:
			goal = hero.move_point
	if goal != Vector2.INF:
		if not _showing:
			_end.snap(goal)
		_end.target = goal
		_alpha.target = 0.8
		if locked and not _locked:
			_pulse.kick(7.0)
		_marker.target = RED if locked else GREEN
	else:
		_alpha.target = 0.0
	_showing = goal != Vector2.INF
	_locked = locked
	_end.update(delta)
	_alpha.update(delta)
	_pulse.update(delta)
	_marker.update(delta)
	_draw(hero)


func _draw(hero) -> void:
	_mesh.clear_surfaces()
	var a := clampf(_alpha.value, 0.0, 1.0)
	if a < 0.02 or hero == null:
		return
	var from: Vector2 = hero.agent.pos
	var to: Vector2 = _end.value
	var d := to - from
	var length := d.length()
	if length < 0.3:
		return
	var dir := d / length
	var n := Vector2(-dir.y, dir.x)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(1, 1, 1, a)
	# arrow heads along the trail, pointing at the far end
	var step := 0.85
	var s := 0.9
	while s < length - 0.5:
		var c := from + dir * s
		_tri(c + dir * 0.3, c - dir * 0.14 + n * 0.24, c - dir * 0.02, white)
		_tri(c + dir * 0.3, c - dir * 0.02, c - dir * 0.14 - n * 0.24, white)
		s += step
	# the end marker: a ring that swells when it locks onto a target
	var ring_r := 0.42 + clampf(_pulse.value, -0.2, 0.6) * 0.1
	var mc: Color = _marker.value
	mc.a = a
	_ring(to, ring_r, 0.08, mc)
	_mesh.surface_end()


func _tri(p0: Vector2, p1: Vector2, p2: Vector2, c: Color) -> void:
	for p in [p0, p1, p2]:
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(p.x, 0.07, p.y))


func _ring(centre: Vector2, r: float, w: float, c: Color) -> void:
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var o0 := centre + Vector2(cos(a0), sin(a0)) * (r + w)
		var o1 := centre + Vector2(cos(a1), sin(a1)) * (r + w)
		var i0 := centre + Vector2(cos(a0), sin(a0)) * r
		var i1 := centre + Vector2(cos(a1), sin(a1)) * r
		_tri(i0, o0, o1, c)
		_tri(i0, o1, i1, c)
