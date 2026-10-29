class_name SmoothRect
extends RefCounted
## A Rect2 that glides: the red selection box, panels that grow, highlights that follow the hover.

var position: SmoothVec2
var size: SmoothVec2


func _init(start: Rect2 = Rect2(), speed: float = 14.0, damping_ratio: float = 1.0) -> void:
	position = SmoothVec2.new(start.position, speed, damping_ratio)
	size = SmoothVec2.new(start.size, speed, damping_ratio)


var target: Rect2:
	get: return Rect2(position.target, size.target)
	set(r):
		position.target = r.position
		size.target = r.size


var value: Rect2:
	get: return Rect2(position.value, size.value)


func update(dt: float) -> void:
	position.update(dt)
	size.update(dt)


func snap(r: Rect2) -> void:
	position.snap(r.position)
	size.snap(r.size)


func is_settled() -> bool:
	return position.is_settled() and size.is_settled()
