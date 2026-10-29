extends "res://menus/menu_screen.gd"
## EQUIP (screens/equip.lua, BH's "Armory"): pick a hero from the party strip, then move items between the shared inventory and the hero's three gear
## slots (weapon / armor / trinket). Click an item to hold it, then its slot to equip (type and class checked; the old item returns to the inventory);
## click an occupied slot with nothing held to unequip. Hover for details. The save is written on exit.

const IC := preload("res://menus/item_ui.gd")
const PAD := 14.0
const MARGIN := 20.0
const SLOTS := [{"key": "weapon", "label": "WEAPON"}, {"key": "armor", "label": "ARMOR"}, {"key": "trinket", "label": "TRINKET"}]
const CHIP := 48.0
const PORTRAIT := 96.0
const SLOT_SIZE := 48.0
const SLOT_GAP := 12.0

var _party: Array = []
var _sel_char := ""
var _held := ""                                      # inventory item id being held
var _hover := {}
var _pressed := {}
var _box := C.RedBox.new()
var _chip_sel := SmoothRect.new(Rect2(), 16.0)       # the white ring that glides to the selected hero


func _panel() -> Rect2:
	var y := C.TOP_BAR_H + 12.0
	return Rect2(MARGIN, y, 270.0, C.VH - MARGIN - y)


func _chip_rect(i: int) -> Rect2:
	var p := _panel()
	var gap := floorf((p.size.x - PAD * 2.0 - 4.0 * CHIP) / 3.0)
	return Rect2(p.position.x + PAD + i * (CHIP + gap), p.position.y + PAD, CHIP, CHIP)


func _divider_y() -> float:
	return _panel().position.y + PAD + CHIP + 12.0


func _portrait_rect() -> Rect2:
	return Rect2(_panel().position.x + PAD, _divider_y() + 12.0, PORTRAIT, PORTRAIT)


func _slot_rect(i: int) -> Rect2:
	var pr := _portrait_rect()
	return Rect2(_panel().position.x + PAD, pr.end.y + 12.0 + i * (SLOT_SIZE + SLOT_GAP), SLOT_SIZE, SLOT_SIZE)


func enter(_args: Dictionary = {}) -> void:
	_party = []
	for name in GameState.party():
		_party.append(name)
	_sel_char = _party[0] if not _party.is_empty() else ""
	_box.init_at(C.padded(_chip_rect(0)) if not _party.is_empty() else C.back_box())
	_chip_sel.snap(_chip_rect(0))


func exit() -> void:
	GameState.write_save()


func _equipped() -> Dictionary:
	var rec := GameState.record(_sel_char)
	rec["equipped"] = rec.get("equipped", {})
	return rec["equipped"]


func _detect() -> Rect2:
	_hover = {}
	if C.BACK_RECT.has_point(mouse):
		_hover = {"zone": "back"}
		return C.back_box()
	for i in _party.size():
		if _chip_rect(i).has_point(mouse):
			_hover = {"zone": "chip", "char": _party[i], "i": i}
			return C.padded(_chip_rect(i))
	if _sel_char != "":
		for i in SLOTS.size():
			if _slot_rect(i).has_point(mouse):
				_hover = {"zone": "slot", "slot": SLOTS[i]["key"], "i": i}
				return C.padded(_slot_rect(i))
	var idx := IC.index_at(mouse)
	if idx >= 0:
		_hover = {"zone": "inv", "id": GameState.data["inventory"][idx], "i": idx}
		return C.padded(IC.cell_rect(idx))
	return Rect2()


func update(dt: float) -> void:
	var r := _detect()
	if not _hover.is_empty():
		_box.set_target(r)
	_box.update(dt)
	var idx := _party.find(_sel_char)
	if idx >= 0:
		_chip_sel.target = _chip_rect(idx)
	_chip_sel.update(dt)


func mouse_pressed(_p: Vector2) -> void:
	_detect()
	_pressed = _hover.duplicate()


func mouse_released(_p: Vector2) -> void:
	_detect()
	var p := _pressed
	_pressed = {}
	if p.is_empty() or p.get("zone") != _hover.get("zone"):
		return
	match p["zone"]:
		"back":
			app.switch_to("stage_select")
		"chip":
			_sel_char = p["char"]
			_held = ""
		"slot":
			if _held != "":
				_equip(_held, p["slot"])
			else:
				_unequip(p["slot"])
		"inv":
			_held = "" if _held == p["id"] else String(p["id"])


func key_pressed(key: int) -> void:
	if key == KEY_ESCAPE:
		app.switch_to("stage_select")


func _equip(id: String, slot: String) -> void:
	var inst := GameState.item_of(id)
	if inst.is_empty() or inst["itemType"] != slot or not GameState.can_use(inst, _sel_char):
		return
	var eq := _equipped()
	var prev: Variant = eq.get(slot)
	eq[slot] = id
	GameState.data["inventory"].erase(id)
	if typeof(prev) == TYPE_STRING and prev != id:
		GameState.data["inventory"].append(prev)
	if _held == id:
		_held = ""


func _unequip(slot: String) -> void:
	var eq := _equipped()
	if typeof(eq.get(slot)) != TYPE_STRING:
		return
	if GameState.inventory_full():
		return
	GameState.data["inventory"].append(eq[slot])
	eq.erase(slot)


func _portrait(name: String, x: float, y: float, size: float) -> void:
	var tex := C.texture("res://assets/ui/icon-%s.png" % name)
	if tex != null:
		C.icon(self, tex, x, y, size)
	else:
		C.text_centered(self, C.title_case(name), Rect2(x, y, size, size), 14, C.WHITE)


func _dashed(r: Rect2, label: String) -> void:
	var dash := 4.0
	for side in 4:
		var a: Vector2 = [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)][side]
		var b: Vector2 = [r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.position][side]
		var len := a.distance_to(b)
		var d := (b - a) / len
		var t := 0.0
		while t < len:
			draw_line(a + d * t, a + d * minf(t + dash, len), C.RED, 1.0)
			t += dash * 2.0
	if label != "":
		C.text_centered(self, label, r, 14, C.RED)


func _is_pressed(zone: String) -> bool:
	return not _pressed.is_empty() and _pressed.get("zone") == zone and _hover.get("zone") == zone


func draw_scene() -> void:
	var back_p := _is_pressed("back")
	C.top_bar(self, "EQUIP", back_p)
	var p := _panel()
	C.outline(self, p, C.WHITE, 2.0)
	draw_line(Vector2(p.position.x + PAD, _divider_y() + 0.5), Vector2(p.end.x - PAD, _divider_y() + 0.5), C.WHITE, 1.0)
	for i in 4:
		var cr := _chip_rect(i)
		if i < _party.size():
			_portrait(_party[i], cr.position.x, cr.position.y, CHIP)
			C.outline(self, cr, C.RED, 1.0)
		else:
			_dashed(cr, "")
	if not _party.is_empty():
		var rr: Rect2 = _chip_sel.value
		C.outline(self, rr, C.WHITE, 2.0)
	if _sel_char != "":
		var pr := _portrait_rect()
		draw_rect(pr, C.BLACK)
		_portrait(_sel_char, pr.position.x, pr.position.y, PORTRAIT)
		C.outline(self, pr, C.WHITE, 2.0)
		var sx := pr.end.x + 14.0
		var text_w := p.end.x - PAD - sx
		C.text(self, C.fit_text(C.title_case(_sel_char), 16, text_w), sx, pr.position.y, 16, C.WHITE)
		C.text(self, "Lv %d" % GameState.level_of(_sel_char), sx, pr.position.y + 18.0, 16, C.RED)
		var st := GameState.hero_stats(_sel_char)
		var lines := [["ATK", int(st["ATK"]), C.RED], ["DEF", int(st["DEF"]), C.WHITE], ["HP", int(st["maxHP"]), C.RED]]
		for i in 3:
			var ly: float = pr.position.y + 40.0 + i * 19.0
			C.text(self, lines[i][0], sx, ly, 16, lines[i][2])
			C.text(self, str(lines[i][1]), sx + 44.0, ly, 16, C.WHITE)
		var eq := _equipped()
		for i in SLOTS.size():
			var sr := _slot_rect(i)
			var inst := GameState.item_of(eq.get(SLOTS[i]["key"]))
			if not inst.is_empty():
				IC.glyph(self, inst, sr.position.x, sr.position.y, SLOT_SIZE)
			else:
				_dashed(sr, String(SLOTS[i]["label"]).substr(0, 1))
			var tx := sr.position.x + SLOT_SIZE + 12.0
			C.text(self, SLOTS[i]["label"], tx, sr.position.y + 7.0, 13, C.RED)
			C.text(self, C.fit_text(inst.get("name", "empty"), 14, p.end.x - PAD - tx), tx, sr.position.y + 24.0, 14, C.WHITE)
	else:
		C.text_centered(self, "No character", Rect2(p.position.x, _divider_y(), p.size.x, p.end.y - _divider_y()), 16, C.WHITE)
	var held := GameState.item_of(_held)
	if not held.is_empty():
		IC.draw_inventory(self, _held, "Now click the %s slot to equip it" % held["itemType"])
	else:
		IC.draw_inventory(self, "", "Click an item, then its slot")
	_box.draw(self, back_p)
	C.back_button(self, back_p)


func draw_overlay(c: CanvasItem) -> void:
	match _hover.get("zone", ""):
		"inv":
			var inst := GameState.item_of(_hover["id"])
			if not inst.is_empty():
				C.tooltip(c, IC.tooltip_lines(inst, _sel_char, "Sells for", int(inst["sellPrice"])), IC.cell_rect(_hover["i"]))
		"slot":
			var inst2 := GameState.item_of(_equipped().get(_hover["slot"]))
			if not inst2.is_empty():
				var lines := IC.tooltip_lines(inst2)
				lines.append({"text": "Click to unequip", "color": C.WHITE})
				C.tooltip(c, lines, _slot_rect(_hover["i"]))
		"chip":
			C.tooltip(c, [{"text": C.title_case(_hover["char"]), "size": 16, "color": C.RED}, {"text": "Lv %d" % GameState.level_of(_hover["char"]), "color": C.WHITE}], _chip_rect(_hover["i"]))
