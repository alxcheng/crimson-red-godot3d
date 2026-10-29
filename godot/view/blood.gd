extends Node3D
## Blood splatter, ported from the 2D game (encounter/particles.lua spawnBlood / updateBlood / drawBlood):
## every hit throws 20 red 2x2 px specks away from the attacker; they arc under gravity, land on the floor, stay 1 s, then vanish.
## 2D numbers at SCALE 1.5 (VH 450 / 300), converted to metres at the project's 23.3 px per metre:
##   horizontal speed 45..133 px/s -> 1.9..5.7 m/s, upward speed 75..148 px/s -> 3.2..6.4 m/s, gravity 441 px/s^2 -> 18.9 m/s^2.
##
## Efficiency: the whole effect is ONE MultiMesh draw call (a ring buffer of POOL small cubes) and NO per-frame CPU work per speck.
## A hit only writes each speck's start position and velocity into the pool (20 writes); the vertex shader flies, lands and retires
## it from the time alone (ballistic arc, flattened splat on the floor, hidden after FLOOR_TIME). The script advances one
## uniform (the effect's own clock, which stops while the game is paused).

const POOL := 1024                 # specks alive at once (a hit is 20; the oldest are recycled)
const PER_HIT := 20                # 2D: 20 (40 on a crit; crits are not in the sandbox yet)
const SPEED_H := Vector2(1.9, 5.7) # m/s, the 2D (30..89) * SCALE / px-per-metre
const SPEED_UP := Vector2(3.2, 6.4)
const GRAVITY := 18.9
const FLOOR_TIME := 1.0            # 2D floorTimer
const SPECK := 0.065               # m: about 2 logical pixels at 960x540

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled;
uniform float t_now;
uniform float gravity = 18.9;
uniform float floor_time = 1.0;
uniform vec4 colour : source_color = vec4(1.0, 0.08, 0.08, 1.0);
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float age = t_now - INSTANCE_CUSTOM.x;
	vec3 v = INSTANCE_CUSTOM.yzw;                       // x = horizontal x, y = up, z = horizontal z (m/s)
	float t_land = (v.y + sqrt(v.y * v.y + 2.0 * gravity * max(origin.y, 0.0))) / gravity;
	vec3 p;
	vec3 local = VERTEX;
	if (age < 0.0 || age > t_land + floor_time) {
		p = vec3(0.0, -100.0, 0.0);                      // not born yet / already gone
		local = vec3(0.0);
	} else if (age < t_land) {
		p = vec3(origin.x + v.x * age, origin.y + v.y * age - 0.5 * gravity * age * age, origin.z + v.z * age);
	} else {                                             // landed: a flat splat where it came down
		p = vec3(origin.x + v.x * t_land, 0.012, origin.z + v.z * t_land);
		local = vec3(local.x * 1.7, local.y * 0.15, local.z * 1.7);
	}
	VERTEX = (VIEW_MATRIX * vec4(p + local, 1.0)).xyz;
}
void fragment() {
	ALBEDO = colour.rgb;
}
"""

var _mm := MultiMesh.new()
var _mat := ShaderMaterial.new()
var _clock := 0.0
var _next := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 7
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SPECK
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat.shader = shader
	_mat.set_shader_parameter("gravity", GRAVITY)
	_mat.set_shader_parameter("floor_time", FLOOR_TIME)
	box.material = _mat
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = box
	_mm.instance_count = POOL
	_mm.custom_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 30, 120))
	clear()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Remove every speck (a restart).
func clear() -> void:
	for i in POOL:
		_mm.set_instance_custom_data(i, Color(-10000.0, 0, 0, 0))
	_next = 0


## Advance the effect's clock (call with the game's delta; skip it while paused so the specks freeze).
func update(dt: float) -> void:
	_clock += dt
	_mat.set_shader_parameter("t_now", _clock)


## A hit: PER_HIT specks leave `to` (the victim, ground position) at `height` metres, thrown away from `from` (the attacker).
func splatter(from: Vector2, to: Vector2, height: float, count: int = PER_HIT) -> void:
	var away := (to - from)
	away = away.normalized() if away.length() > 0.001 else Vector2.RIGHT
	for _i in count:
		var ang := _rng.randf_range(-0.35, 0.35)                 # the 2D game throws along x only; a little spread reads better in 3D
		var dir := away.rotated(ang)
		var sh := _rng.randf_range(SPEED_H.x, SPEED_H.y)
		var su := _rng.randf_range(SPEED_UP.x, SPEED_UP.y)
		var i := _next
		_next = (_next + 1) % POOL
		_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(to.x, height, to.y)))
		_mm.set_instance_custom_data(i, Color(_clock, dir.x * sh, su, dir.y * sh))
