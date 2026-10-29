extends "res://menus/menu_screen.gd"
## PARTY (screens/party_select.lua): the four ACTIVE slots in a framed strip, the 6x2 RESERVES grid under it, click-to-move (a party member goes to the
## reserves, a reserve fills the lowest free slot), a hover tooltip with name / level / stats, the red box gliding between cells.

const ICON := 56.0
const SLOTS := 4
const GAP := 18.0
const PAD := 14.0
const LABEL_H := 20.0
const NUMBER_H := 20.0
const COLS := 6
const ROWS := 2
const RGAP := 8.0

var _party: Array = []                     # [0..3] class or ""
var _roster: Array = []
var _box := C.RedBox.new()
var _pressed_back := false
var _hover_char := ""
var _hover_in_party := false
var _hover_rect := Rect2()


func _party_frame() -> Rect2:
	var total := SLOTS * ICON + (SLOTS - 1) * GAP
	var w := total + PAD * 2.0
	return Rect2(floorf((C.VW - w) / 2.0), C.TOP_BAR_H + 14.0 + LABEL_H, w, PAD + ICON + NUMBER_H + PAD - 6.0)


func _slot_rect(i: int) -> Rect2:
	var f := _party_frame()
	return Rect2(f.position.x + PAD + i * (ICON + GAP), f.position.y + PAD, ICON, ICON)


func _roster_frame() -> Rect2:
	var inner_w := COLS * ICON + (COLS - 1) * RGAP
	var inner_h := ROWS * ICON + (ROWS - 1) * RGAP
	var pf := _party_frame()
	return Rect2(floorf((C.VW - (inner_w + PAD * 2.0)) / 2.0), pf.end.y + 14.0 + LABEL_H, inner_w + PAD * 2.0, inner_h + PAD * 2.0)


func _cell_rect(idx: int) -> Rect2:
	var f := _roster_frame()
	return Rect2(f.position.x + PAD + (idx % COLS) * (ICON + RGAP), f.position.y + PAD + (idx / COLS) * (ICON + RGAP), ICON, ICON)


func enter(_args: Dictionary = {}) -> void:
	_party = ["", "", "", ""]
	var in_party := {}
	var order: Array = GameState.data["partyOrder"]
	for i in SLOTS:
		if typeof(order[i]) == TYPE_STRING:
			_party[i] = order[i]
			in_party[order[i]] = true
	_roster = []
	for name in GameState.recruited():
		if not in_party.has(name):
			_roster.append(name)
	_box.init_at(C.padded(_slot_rect(0)))


func exit() -> void:
	var out: Array = []
	for i in SLOTS:
		out.append(_party[i] if _party[i] != "" else false)
	GameState.data["partyOrder"] = out
	GameState.write_save()


func _back() -> void:
	app.switch_to("stage_select")


func update(dt: float) -> void:
	_hover_char = ""
	var target := Rect2()
	if C.BACK_RECT.has_point(mouse):
		target = C.back_box()
	for i in SLOTS:
		if _slot_rect(i).has_point(mouse):
			target = C.padded(_slot_rect(i))
			if _party[i] != "":
				_hover_char = _party[i]
				_hover_in_party = true
				_hover_rect = _slot_rect(i)
			break
	if _hover_char == "":
		for idx in _roster.size():
			if _cell_rect(idx).has_point(mouse):
				target = C.padded(_cell_rect(idx))
				_hover_char = _roster[idx]
				_hover_in_party = false
				_hover_rect = _cell_rect(idx)
				break
	if target.size.x > 0.0:
		_box.set_target(target)
	_box.update(dt)


func mouse_pressed(_p: Vector2) -> void:
	if C.BACK_RECT.has_point(mouse):
		_pressed_back = true
		return
	for i in SLOTS:
		if _party[i] != "" and _slot_rect(i).has_point(mouse):
			_roster.append(_party[i])
			_party[i] = ""
			return
	for idx in _roster.size():
		if _cell_rect(idx).has_point(mouse):
			var name: String = _roster[idx]
			_roster.remove_at(idx)
			var free := _party.find("")
			if free >= 0:
				_party[free] = name
			else:
				_roster.append(name)
			return


func mouse_released(_p: Vector2) -> void:
	if _pressed_back and C.BACK_RECT.has_point(mouse):
		_back()
	_pressed_back = false


func key_pressed(key: int) -> void:
	if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_KP_ENTER:
		_back()


func _portrait(name: String, x: float, y: float, size: float) -> void:
	var tex := C.texture("res://assets/ui/icon-%s.png" % name)
	if tex != null:
		C.icon(self, tex, x, y, size)
	else:
		C.text_centered(self, C.title_case(name), Rect2(x, y, size, size), 14, C.WHITE)


func _frame(caption: String, r: Rect2) -> void:
	C.text(self, caption, r.position.x, r.position.y - LABEL_H, 14, C.RED)
	C.outline(self, r, C.WHITE, 2.0)
	C.outline(self, Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), C.RED, 1.0)


func draw_scene() -> void:
	C.top_bar(self, "PARTY", _pressed_back and C.BACK_RECT.has_point(mouse))
	_frame("ACTIVE", _party_frame())
	for i in SLOTS:
		var r := _slot_rect(i)
		draw_rect(r, C.BLACK)
		C.outline(self, r, C.RED, 2.0)
		if _party[i] != "":
			_portrait(_party[i], r.position.x, r.position.y, ICON)
		var lbl := str(i + 1)
		C.text(self, lbl, r.position.x + (ICON - C.text_w(lbl, 14)) / 2.0, r.position.y + ICON + 5.0, 14, C.RED)
	_frame("RESERVES", _roster_frame())
	for idx in COLS * ROWS:
		var cr := _cell_rect(idx)
		draw_rect(cr, C.BLACK)
		if idx < _roster.size():
			C.outline(self, cr, C.RED, 1.0)
			_portrait(_roster[idx], cr.position.x, cr.position.y, ICON)
	_box.draw(self, _pressed_back and C.BACK_RECT.has_point(mouse))
	C.back_button(self, _pressed_back and C.BACK_RECT.has_point(mouse))
func draw_overlay(c: CanvasItem) -> void:
	if _hover_char != "":
		var st := GameState.hero_stats(_hover_char)
		C.tooltip(c, [
			{"text": C.title_case(_hover_char), "size": 16, "color": C.RED},
			{"text": "Lv %d    ATK %d    DEF %d    HP %d" % [GameState.level_of(_hover_char), int(st.get("ATK", 0)), int(st.get("DEF", 0)), int(st.get("maxHP", 0))], "color": C.WHITE},
			{"text": "IN PARTY - click to remove" if _hover_in_party else "RESERVE - click to add", "color": C.RED}], _hover_rect)
