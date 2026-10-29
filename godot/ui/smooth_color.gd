class_name SmoothColor
extends RefCounted
## RGBA as four springs. Channels are clamped on output (springs with damping_ratio < 1 may overshoot).
## Plain RGB is fine for this game's red/white palette; if multi-hue fades are added later, animate in
## OKLab instead.

var r: SmoothValue
var g: SmoothValue
var b: SmoothValue
var a: SmoothValue


func _init(start: Color = Color.WHITE, speed: float = 12.0, damping_ratio: float = 1.0) -> void:
	r = SmoothValue.new(start.r, speed, damping_ratio)
	g = SmoothValue.new(start.g, speed, damping_ratio)
	b = SmoothValue.new(start.b, speed, damping_ratio)
	a = SmoothValue.new(start.a, speed, damping_ratio)


var target: Color:
	get: return Color(r.target, g.target, b.target, a.target)
	set(c):
		r.target = c.r
		g.target = c.g
		b.target = c.b
		a.target = c.a


var value: Color:
	get: return Color(clampf(r.value, 0.0, 1.0), clampf(g.value, 0.0, 1.0),
			clampf(b.value, 0.0, 1.0), clampf(a.value, 0.0, 1.0))


func update(dt: float) -> void:
	r.update(dt)
	g.update(dt)
	b.update(dt)
	a.update(dt)


func snap(c: Color) -> void:
	r.snap(c.r)
	g.snap(c.g)
	b.snap(c.b)
	a.snap(c.a)


func is_settled() -> bool:
	return r.is_settled() and g.is_settled() and b.is_settled() and a.is_settled()
