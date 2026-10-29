extends Control
## A unit's health bar: white outline, red fill that follows the real value quickly and a white "damage"
## trail that follows slowly (both SmoothValue). Palette: red and white only.

var fill := SmoothValue.new(1.0, 16.0)
var trail := SmoothValue.new(1.0, 3.5)
var fade := SmoothValue.new(1.0, 10.0)      # alpha: dims when the unit is dead
var tags: Array = []                         # status letters drawn above the bar: [{text, red}]


func _init() -> void:
	custom_minimum_size = Vector2(52, 7)
	size = Vector2(52, 7)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ratio(r: float) -> void:
	fill.target = clampf(r, 0.0, 1.0)
	trail.target = clampf(r, 0.0, 1.0)


func snap_ratio(r: float) -> void:
	fill.snap(r)
	trail.snap(r)


func _process(delta: float) -> void:
	fill.update(delta)
	trail.update(delta)
	fade.update(delta)
	queue_redraw()


func _draw() -> void:
	var a := clampf(fade.value, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.75 * a))
	var inner := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * maxf(trail.value, 0.0), inner.size.y)), Color(1, 1, 1, 0.85 * a))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * maxf(fill.value, 0.0), inner.size.y)), Color(1, 0, 0, a))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, a), false, 1.0)
	var x := 0.0
	for tag in tags:
		var colour := Color(1, 0, 0, a) if tag["red"] else Color(1, 1, 1, a)
		draw_rect(Rect2(Vector2(x, -13), Vector2(13, 12)), Color(0, 0, 0, 0.8 * a))
		draw_rect(Rect2(Vector2(x, -13), Vector2(13, 12)), colour, false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(x + 3, -3), tag["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour)
		x += 15.0
