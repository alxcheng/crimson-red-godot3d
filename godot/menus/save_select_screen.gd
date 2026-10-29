extends "res://menus/menu_screen.gd"
## SAVE SELECT (2D screens/save_select.lua): PLAY on the title lands here. Five stacked slot rows, one per `user://save_N.json`: SLOT N, then
## the zone and fight reached and the party, or EMPTY. Clicking a row loads that save (an empty slot starts a new game) and opens the stage
## select. DELETE (filled slots) needs a second press to confirm, then removes the file. The red box glides between items (RedBox).

const SLOT_COUNT := 5
const ROW_X := 40.0
const ROW_W := C.VW - 80.0
const ROW_H := 60.0
const ROW_GAP := 10.0
const ROW_Y := floorf((C.VH - (SLOT_COUNT * ROW_H + (SLOT_COUNT - 1) * ROW_GAP)) / 2.0)
const DEL_W := 76.0
const DEL_H := 22.0
const DEL_PAD := 6.0
const DEL_GAP := 8.0

var _slots: Array = []                      # slot_info per slot ({} = empty)
var _hover := {}                            # {k: "back" | "row" | "del", i}
var _pressed := {}
var _confirm := -1                          # the slot whose DELETE awaits its second press
var _box := C.RedBox.new()


func enter(_args: Dictionary = {}) -> void:
	_refresh()
	_confirm = -1
	_hover = {}
	_pressed = {}
	_box.init_at(_row_hit(0))


func _refresh() -> void:
	_slots = []
	for i in SLOT_COUNT:
		_slots.append(GameState.slot_info(i + 1))


func _row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y + i * (ROW_H + ROW_GAP), ROW_W, ROW_H)


## The clickable part of a row: it stops before the DELETE button so the button stays reachable.
func _row_hit(i: int) -> Rect2:
	var r := _row_rect(i)
	return Rect2(r.position, Vector2(r.size.x - DEL_PAD - DEL_W - DEL_GAP, r.size.y))


func _del_rect(i: int) -> Rect2:
	var r := _row_rect(i)
	return Rect2(r.end.x - DEL_PAD - DEL_W, r.position.y + (ROW_H - DEL_H) / 2.0, DEL_W, DEL_H)


func _detect() -> Rect2:
	_hover = {}
	if C.BACK_RECT.has_point(mouse):
		_hover = {"k": "back", "i": 0}
		return C.back_box()
	for i in SLOT_COUNT:
		if not _slots[i].is_empty() and _del_rect(i).has_point(mouse):
			_hover = {"k": "del", "i": i}
			return C.padded(_del_rect(i))
		if _row_hit(i).has_point(mouse):
			_hover = {"k": "row", "i": i}
			return _row_hit(i)
	return Rect2()


func update(dt: float) -> void:
	var r := _detect()
	if not _hover.is_empty():
		_box.set_target(r)
	if _confirm >= 0 and _hover.get("k") != "del":
		_confirm = -1                                         # moving away cancels a pending delete
	_box.update(dt)


func mouse_pressed(_p: Vector2) -> void:
	_detect()
	_pressed = _hover.duplicate()


func mouse_released(_p: Vector2) -> void:
	_detect()
	var p := _pressed
	_pressed = {}
	if p.is_empty() or p["k"] != _hover.get("k") or p["i"] != _hover.get("i"):
		return
	match p["k"]:
		"back":
			app.switch_to("title")
		"row":
			_open_slot(p["i"])
		"del":
			if _confirm == p["i"]:
				GameState.delete_slot(p["i"] + 1)
				_confirm = -1
				_refresh()
			else:
				_confirm = p["i"]


## Load (or start) the slot's save and go to the stage select.
func _open_slot(i: int) -> void:
	GameState.use_slot(i + 1)
	app.switch_to("stage_select")


func key_pressed(key: int) -> void:
	if key == KEY_ESCAPE:
		app.switch_to("title")


func draw_scene() -> void:
	C.back_button(self, _pressed.get("k") == "back")
	_box.draw(self, not _pressed.is_empty())
	for i in SLOT_COUNT:
		var r := _row_rect(i)
		var on: bool = _pressed.get("k") == "row" and _pressed.get("i") == i
		var col := C.BLACK if on else C.WHITE
		C.text(self, "SLOT %d" % (i + 1), r.position.x + 10.0, r.position.y + (ROW_H - C.text_h(16)) / 2.0, 16, col)
		var info: Dictionary = _slots[i]
		if info.is_empty():
			C.text(self, "EMPTY - NEW GAME", r.position.x + 90.0, r.position.y + (ROW_H - C.text_h(13)) / 2.0, 13, C.BLACK if on else C.RED)
			continue
		var max_w := _del_rect(i).position.x - DEL_GAP - (r.position.x + 90.0)
		C.text(self, C.fit_text(String(info["place"]), 13, max_w), r.position.x + 90.0, r.position.y + 9.0, 13, col)
		C.text(self, C.fit_text(String(info["party"]), 11, max_w), r.position.x + 90.0, r.position.y + 32.0, 11, col)
		var d := _del_rect(i)
		var confirming := _confirm == i
		var dpress: bool = _pressed.get("k") == "del" and _pressed.get("i") == i
		if confirming:
			draw_rect(d, C.WHITE if dpress else C.RED)
		else:
			C.outline(self, d, C.RED, 1.0)
		C.text_centered(self, "CONFIRM" if confirming else "DELETE", d, 11, C.BLACK if (dpress or confirming and false) else C.WHITE)
