extends "res://menus/menu_screen.gd"
## The title screen, ported from screens/title.lua: the Sierpinski logo, "crimson red" whose letters fly in (crimson from the left,
## red from the right, per-letter delays, each a SmoothValue with a touch of under-damping), and PLAY / TUTORIAL / OPTIONS / EXIT with the red box.

const ITEMS := ["PLAY", "TUTORIAL", "OPTIONS", "EXIT"]
const BOX_PAD_X := 8.0
const BOX_PAD_Y := 5.0
const FONT_PX := 20                      # floor(VH * 0.0444)
const TITLE_PX := 36                     # floor(VH * 0.08)
const STAGGER := 0.053

var _tris: Array = []
var _letters: Array = []                 # {ch, final_x, y, x: SmoothValue, delay}
var _t := 0.0
var _hover := -1
var _pressed := -1
var _box := C.RedBox.new()


func _btn_rect(i: int) -> Rect2:
	var w := C.text_w(ITEMS[i], FONT_PX)
	return Rect2((C.VW - w) / 2.0, C.VH * 0.65 + i * (C.VH * 0.066), w, C.text_h(FONT_PX))


func _box_rect(i: int) -> Rect2:
	var r := _btn_rect(i)
	return Rect2(r.position - Vector2(BOX_PAD_X, BOX_PAD_Y), r.size + Vector2(BOX_PAD_X, BOX_PAD_Y) * 2.0)


func enter(_args: Dictionary = {}) -> void:
	var cx := C.VW / 2.0
	var size_t := C.VH * 0.11
	var h := size_t * sqrt(3.0) / 2.0
	var start_y := C.VH * 0.08
	for row in [[0, start_y, [0.0]], [1, start_y + h, [-0.5, 0.5]], [2, start_y + 2.0 * h, [-1.0, 0.0, 1.0]]]:
		for off in row[2]:
			var x: float = cx + float(off) * size_t
			_tris.append(PackedVector2Array([Vector2(x, row[1]), Vector2(x - size_t / 2.0, row[1] + h), Vector2(x + size_t / 2.0, row[1] + h)]))
	var s := "crimson red"
	var base_x := (C.VW - C.text_w(s, TITLE_PX)) / 2.0
	var xs: Array = []
	var cur := base_x
	for ch in s:
		xs.append(cur)
		cur += C.text_w(ch, TITLE_PX)
	var y := floorf(C.VH * 0.49)
	var crimson_order := [6, 5, 4, 3, 2, 1, 0]                      # "n" arrives first
	for rank in crimson_order.size():
		_add_letter(s[crimson_order[rank]], xs[crimson_order[rank]], y, true, rank * STAGGER)
	for rank in 3:
		var idx: int = [8, 9, 10][rank]
		_add_letter(s[idx], xs[idx], y, false, rank * STAGGER)
	_box.init_at(_box_rect(0))


func _add_letter(ch: String, fx: float, y: float, from_left: bool, delay: float) -> void:
	var sv := SmoothValue.new(-40.0 if from_left else C.VW + 40.0, 14.0, 0.7)    # a slight settle (UI_ANIMATION.md: title letters)
	_letters.append({"ch": ch, "fx": fx, "y": y, "x": sv, "delay": delay})


func update(dt: float) -> void:
	_t += dt
	for l in _letters:
		if _t >= l["delay"]:
			l["x"].target = l["fx"]
		l["x"].update(dt)
	_hover = -1
	for i in ITEMS.size():
		if _btn_rect(i).has_point(mouse):
			_hover = i
	if _hover >= 0:
		_box.set_target(_box_rect(_hover))
	_box.update(dt)


func mouse_pressed(_p: Vector2) -> void:
	if _hover >= 0:
		_pressed = _hover


func mouse_released(_p: Vector2) -> void:
	if _pressed >= 0 and _pressed == _hover:
		match ITEMS[_pressed]:
			"PLAY":
				app.switch_to("save_select")
			"TUTORIAL":
				GameState.zone_index = -1                           # a practice battle in the dungeon, nothing saved
				app.start_battle()
			"EXIT":
				get_tree().quit()
	_pressed = -1


func key_pressed(key: int) -> void:
	if key == KEY_ESCAPE:
		get_tree().quit()


func draw_scene() -> void:
	for tri in _tris:
		draw_colored_polygon(tri, C.RED)
	for l in _letters:
		if _t >= l["delay"]:
			C.text(self, l["ch"], l["x"].value, l["y"], TITLE_PX, C.RED)
	_box.draw(self, _pressed >= 0)
	for i in ITEMS.size():
		var r := _btn_rect(i)
		C.text(self, ITEMS[i], r.position.x, r.position.y, FONT_PX, C.BLACK if _pressed == i else C.WHITE)
