extends Node3D
## The Knight's area attack (Sunder Armor) as a 3D slash: two crescent arcs (a flat spin at waist height and a tilted
## counter-arc) sweep once round him out to the area's radius, white at the head fading to red at the tail, then fade.
## One small quad per arc and a shader that draws the crescent from time alone; the motion is a SmoothValue.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float progress = 0.0;      // 0 -> 1: the head sweeps once round
uniform float fade = 1.0;
uniform float start_angle = 0.0;
uniform float tail = 0.42;         // length of the crescent, in turns
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float head = start_angle + progress * 6.2831853 * 1.15;
	float a = mod(head - ang, 6.2831853) / 6.2831853;           // 0 at the head, growing along the tail
	float width = mix(0.012, 0.17, 1.0 - a / tail);              // thick at the head, a point at the tail
	float band = 1.0 - smoothstep(width * 0.5, width, abs(r - 0.86));
	float body = step(a, tail) * band;
	float heat = 1.0 - a / tail;
	vec3 col = mix(vec3(1.0, 0.1, 0.05), vec3(1.0), pow(heat, 1.4));
	ALBEDO = col * body * fade * 2.2;
	ALPHA = body * fade;
}
"""

static var _shader: Shader
var _arcs: Array = []
var _sweep := SmoothValue.new(0.0, 11.0)
var _fade := SmoothValue.new(1.0, 5.0)
var _age := 0.0


func _init() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	for k in 2:
		var mi := MeshInstance3D.new()
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE * (2.0 / 0.86)                    # unit radius: the node is scaled to the area's radius (the arc runs at 0.86 of the half size)
		mi.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("start_angle", 0.4 if k == 0 else 3.4)
		mi.material_override = mat
		mi.position = Vector3(0, 0.9 + 0.12 * k, 0)
		mi.rotation_degrees = Vector3(0, 0, 0) if k == 0 else Vector3(26, 20, -22)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_arcs.append(mat)
	visible = false
	set_process(false)


## Play at `at` for an area of `radius` metres (a free pool member).
func play(at: Vector3, radius: float) -> void:
	position = at
	scale = Vector3(radius, 1.0, radius)
	_age = 0.0
	_sweep.snap(0.0)
	_sweep.target = 1.0
	_fade.snap(1.0)
	_fade.target = 1.0
	visible = true
	set_process(true)


func busy() -> bool:
	return visible


func _process(dt: float) -> void:
	_age += dt
	_sweep.update(dt)
	if _age > 0.28:
		_fade.target = 0.0
	_fade.update(dt)
	for k in _arcs.size():
		var delayed: float = clampf(_sweep.value - 0.06 * k, 0.0, 1.0)
		_arcs[k].set_shader_parameter("progress", delayed)
		_arcs[k].set_shader_parameter("fade", clampf(_fade.value, 0.0, 1.0))
	if _age > 0.9:
		visible = false
		set_process(false)
