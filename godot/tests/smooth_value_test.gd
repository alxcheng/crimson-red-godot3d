extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://tests/smooth_value_test.gd
## Checks the spring: convergence, no overshoot when critically damped, overshoot when underdamped,
## frame-rate independence, retargeting keeps velocity, huge dt is stable, color clamping.
const SV := preload("res://ui/smooth_value.gd")
const SC := preload("res://ui/smooth_color.gd")
var _fail := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error(msg)


func _run_for(sv, seconds: float, step: float) -> void:
	var t := 0.0
	while t < seconds - 0.000001:
		sv.update(step)
		t += step


func _initialize() -> void:
	# 1. converges to target and settles
	var a = SV.new(0.0, 12.0)
	a.target = 100.0
	_run_for(a, 2.0, 1.0 / 60.0)
	_check(a.value == 100.0 and a.is_settled(), "critical spring did not settle: %f" % a.value)
	# 2. critically damped never overshoots
	var b = SV.new(0.0, 12.0)
	b.target = 100.0
	var peak := 0.0
	for i in 600:
		b.update(1.0 / 60.0)
		peak = maxf(peak, b.value)
	_check(peak <= 100.0001, "critically damped overshoot: %f" % peak)
	# 3. underdamped overshoots, then settles
	var c = SV.new(0.0, 12.0, 0.4)
	c.target = 100.0
	peak = 0.0
	for i in 600:
		c.update(1.0 / 60.0)
		peak = maxf(peak, c.value)
	_check(peak > 101.0 and c.value == 100.0, "underdamped should overshoot then settle (peak %f)" % peak)
	# 4. overdamped does not overshoot and settles
	var d = SV.new(0.0, 12.0, 2.5)
	d.target = 100.0
	peak = 0.0
	for i in 1200:
		d.update(1.0 / 60.0)
		peak = maxf(peak, d.value)
	_check(peak <= 100.0001 and d.value == 100.0, "overdamped misbehaved (peak %f, end %f)" % [peak, d.value])
	# 5. frame-rate independence: 60 Hz, 144 Hz, 20 Hz and one big step agree
	for zeta in [1.0, 0.5, 2.0]:
		var ref = SV.new(0.0, 10.0, zeta)
		ref.target = 50.0
		_run_for(ref, 0.5, 1.0 / 1000.0)
		for step in [1.0 / 60.0, 1.0 / 144.0, 1.0 / 20.0, 0.5]:  # all divide 0.5 s exactly
			var s = SV.new(0.0, 10.0, zeta)
			s.target = 50.0
			_run_for(s, 0.5, step)
			_check(absf(s.value - ref.value) < 0.05 and absf(s.velocity - ref.velocity) < 0.5,
				"frame-rate dependent: zeta %.1f step %.4f: %f vs %f" % [zeta, step, s.value, ref.value])
	# 6. retargeting mid-flight keeps velocity (no snap)
	var e = SV.new(0.0, 12.0)
	e.target = 100.0
	_run_for(e, 0.1, 1.0 / 60.0)
	var before: float = e.value
	var vel_before: float = e.velocity
	e.target = 0.0
	e.update(1.0 / 600.0)
	_check(absf(e.value - before) < 2.0 and e.velocity < vel_before + 1.0 and e.velocity > 0.0,
		"retarget reset the motion: %f -> %f, v %f -> %f" % [before, e.value, vel_before, e.velocity])
	# 7. huge dt is stable
	var f = SV.new(0.0, 12.0, 0.3)
	f.target = 10.0
	f.update(1000.0)
	_check(is_finite(f.value) and absf(f.value - 10.0) < 0.001, "huge dt unstable: %f" % f.value)
	# 8. kick moves a settled value and it returns
	var g = SV.new(0.0, 14.0, 0.5)
	g.kick(30.0)
	g.update(0.05)
	_check(g.value > 0.1, "kick did nothing")
	_run_for(g, 3.0, 1.0 / 60.0)
	_check(g.value == 0.0, "kick never settled")
	# 9. colour clamps
	var col = SC.new(Color(1, 0, 0, 1), 12.0, 0.3)
	col.target = Color(1, 1, 1, 1)
	for i in 120:
		col.update(1.0 / 60.0)
		var v: Color = col.value
		_check(v.r <= 1.0 and v.g >= 0.0 and v.g <= 1.0 and v.b <= 1.0, "colour out of range")
	print("SMOOTH_VALUE_PASS" if _fail == 0 else "SMOOTH_VALUE_FAIL: %d" % _fail)
	quit(0 if _fail == 0 else 1)
