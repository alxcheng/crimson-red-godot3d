extends Node3D
## The Cleric's heal on its target: holy, yellow-tinted light. A soft golden column of light stands on the target and fades while
## faint stripes of light run up it, a golden ring spreads on the floor, and a few sparks of light drift upward.
## Three additive meshes and a handful of tiny cubes; every fade is a SmoothValue. POOLED: the battle view builds a few of these at start
## (the two shaders are compiled once and shared) and `play()`s a free one, so a heal never allocates or compiles anything mid-fight.

const TINT := Color(1.0, 0.84, 0.28)
const COLUMN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float fade = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.84, 0.28);
void fragment() {
	float h = 1.0 - UV.y;                                   // 0 at the bottom of the column, 1 at the top
	float glow = pow(1.0 - h, 1.2);                         // brightest at the feet
	float stripes = 0.72 + 0.28 * sin((h * 5.0 - TIME * 3.0) * 6.2831853);
	ALBEDO = tint * glow * stripes * fade * 3.0;
	ALPHA = glow * fade;
}
"""
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float fade = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.84, 0.28);
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ring = smoothstep(0.55, 0.8, r) * (1.0 - smoothstep(0.88, 1.0, r));
	float soft = (1.0 - smoothstep(0.0, 0.9, r)) * 0.35;
	ALBEDO = tint * (ring + soft) * fade * 1.6;
	ALPHA = (ring + soft) * fade;
}
"""

static var _col_shader: Shader
static var _ring_shader: Shader
static var _spark_mesh: BoxMesh
var _column_mat := ShaderMaterial.new()
var _ring_mat := ShaderMaterial.new()
var _ring: MeshInstance3D
var _fade := SmoothValue.new(0.0, 12.0)            # rises quickly, then is sent back to 0 (speed 12 up; it falls at the same spring)
var _ring_scale := SmoothValue.new(0.3, 9.0)
var _sparks: Array = []
var _age := 0.0


func _init() -> void:
	if _col_shader == null:
		_col_shader = Shader.new()
		_col_shader.code = COLUMN_SHADER
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
		var spark_mat := StandardMaterial3D.new()
		spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spark_mat.albedo_color = TINT
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3.ONE * 0.07
		_spark_mesh.material = spark_mat
	_column_mat.shader = _col_shader
	_ring_mat.shader = _ring_shader
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.75
	cyl.height = 2.5
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	column.mesh = cyl
	column.material_override = _column_mat
	column.position = Vector3(0, 1.25, 0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(column)
	_ring = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * 2.2
	_ring.mesh = quad
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0, 0.06, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	for i in 9:
		var mi := MeshInstance3D.new()
		mi.mesh = _spark_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var a := rng.randf() * TAU
		_sparks.append({"mesh": mi, "x": cos(a) * rng.randf_range(0.15, 0.5), "z": sin(a) * rng.randf_range(0.15, 0.5),
				"v": rng.randf_range(0.9, 1.7), "delay": rng.randf_range(0.0, 0.3)})
	visible = false
	set_process(false)


## Start the effect at `at` (a free pool member).
func play(at: Vector3) -> void:
	position = at
	_age = 0.0
	_fade.snap(0.0)
	_fade.target = 1.0
	_ring_scale.snap(0.3)
	_ring_scale.target = 1.0
	visible = true
	set_process(true)


func busy() -> bool:
	return visible


func _process(dt: float) -> void:
	_age += dt
	if _age > 0.5:
		_fade.target = 0.0
	_fade.update(dt)
	_ring_scale.update(dt)
	var f: float = clampf(_fade.value, 0.0, 1.0)
	_column_mat.set_shader_parameter("fade", f)
	_ring_mat.set_shader_parameter("fade", f)
	var rs: float = maxf(_ring_scale.value, 0.05)
	_ring.scale = Vector3(rs, 1.0, rs)
	for sp in _sparks:
		var t: float = maxf(_age - float(sp["delay"]), 0.0)
		(sp["mesh"] as MeshInstance3D).position = Vector3(sp["x"], 0.15 + t * float(sp["v"]), sp["z"])
		(sp["mesh"] as MeshInstance3D).visible = t > 0.0 and t < 0.9
	if _age > 1.2:
		visible = false
		set_process(false)
