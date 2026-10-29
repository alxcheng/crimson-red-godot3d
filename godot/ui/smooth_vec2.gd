class_name SmoothVec2
extends RefCounted
## Two SmoothValues: positions, sizes, scale pairs, offsets.

var x: SmoothValue
var y: SmoothValue


func _init(start: Vector2 = Vector2.ZERO, speed: float = 12.0, damping_ratio: float = 1.0) -> void:
	x = SmoothValue.new(start.x, speed, damping_ratio)
	y = SmoothValue.new(start.y, speed, damping_ratio)


var target: Vector2:
	get: return Vector2(x.target, y.target)
	set(v):
		x.target = v.x
		y.target = v.y


var value: Vector2:
	get: return Vector2(x.value, y.value)


func update(dt: float) -> void:
	x.update(dt)
	y.update(dt)


func snap(v: Vector2) -> void:
	x.snap(v.x)
	y.snap(v.y)


func kick(extra_velocity: Vector2) -> void:
	x.kick(extra_velocity.x)
	y.kick(extra_velocity.y)


func is_settled() -> bool:
	return x.is_settled() and y.is_settled()
