extends "res://menus/menu_screen.gd"
## SHOP (screens/shop.lua, BH's Merchant + Tavern): GEAR tab = up to six items for sale (click one, then BUY), HIRE tab = the hero for hire (nobody is
## looking for work while only the Knight and the Wizard are playable); the right panel is the shared inventory (click an item, then SELL). Buy at the
## item's value, sell for half, no buying with a full inventory. The stock re-rolls after a won battle. The "NOT ENOUGH GOLD" flash is a SmoothValue.

const IC := preload("res://menus/item_ui.gd")
const PAD := 14.0
const MARGIN := 20.0
const SLOT := 64.0
const BTN_H := 36.0

var _tab := "gear"
var _sel := {}                                       # {kind: "offer", idx} | {kind: "inv", id}
var _hover := {}
var _pressed := {}
var _box := C.RedBox.new()
var _flash_text := ""
var _flash := SmoothValue.new(0.0, 12.0)
var _flash_t := 0.0


func _panel() -> Rect2:
	var y := C.TOP_BAR_H + 12.0
	return Rect2(MARGIN, y, 270.0, C.VH - MARGIN - y)


func _inner_w() -> float:
	return _panel().size.x - PAD * 2.0


func _tab_rect(which: String) -> Rect2:
	var gap := 10.0
	var w := floorf((_inner_w() - gap) / 2.0)
	return Rect2(_panel().position.x + PAD + (w + gap if which == "hire" else 0.0), _panel().position.y + PAD, w, 28.0)


func _divider_y() -> float:
	return _tab_rect("gear").end.y + 12.0


func _slot_rect(i: int) -> Rect2:
	var gap_x := floorf((_inner_w() - 3.0 * SLOT) / 2.0)
	return Rect2(_panel().position.x + PAD + (i % 3) * (SLOT + gap_x), _divider_y() + 14.0 + (i / 3) * (SLOT + 24.0), SLOT, SLOT)


func _btn_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + PAD, p.end.y - PAD - BTN_H, _inner_w(), BTN_H)


func enter(_args: Dictionary = {}) -> void:
	GameState.restock_if_needed()
	_box.init_at(C.padded(_tab_rect("gear")))


func exit() -> void:
	GameState.write_save()


func _offers() -> Array:
	return GameState.shop_state()["offers"]


func _selected_item() -> Dictionary:
	if _sel.is_empty():
		return {}
	if _sel["kind"] == "offer":
		return GameState.item_of(_offers()[_sel["idx"]])
	return GameState.item_of(_sel["id"]) if _sel["id"] in GameState.data["inventory"] else {}


func _action() -> Dictionary:
	if _tab == "hire":
		return {}
	var inst := _selected_item()
	if inst.is_empty():
		return {}
	if _sel["kind"] == "offer":
		return {"verb": "BUY", "price": int(inst["value"]), "enabled": int(GameState.data["gold"]) >= int(inst["value"]) and not GameState.inventory_full()}
	return {"verb": "SELL", "price": int(inst["sellPrice"]), "enabled": true}


func _say(text: String) -> void:
	_flash_text = text
	_flash.snap(1.0)
	_flash.target = 1.0
	_flash_t = 1.0


func _run_action() -> void:
	var inst := _selected_item()
	if inst.is_empty():
		return
	if _sel["kind"] == "offer":
		if GameState.inventory_full():
			_say("INVENTORY FULL")
			return
		if not GameState.spend_gold(int(inst["value"])):
			_say("NOT ENOUGH GOLD")
			return
		var id: Variant = _offers()[_sel["idx"]]
		_offers()[_sel["idx"]] = false
		GameState.data["inventory"].append(id)
	else:
		GameState.data["inventory"].erase(_sel["id"])
		GameState.add_gold(maxi(0, int(inst["sellPrice"])))
		GameState.data["items"].erase(_sel["id"])
	_sel = {}


func _detect() -> Rect2:
	_hover = {}
	if C.BACK_RECT.has_point(mouse):
		_hover = {"zone": "back"}
		return C.back_box()
	for which in ["gear", "hire"]:
		if _tab_rect(which).has_point(mouse):
			_hover = {"zone": "tab", "tab": which}
			return C.padded(_tab_rect(which))
	if not _action().is_empty() and _btn_rect().has_point(mouse):
		_hover = {"zone": "button"}
		return C.padded(_btn_rect())
	if _tab == "gear":
		for i in GameState.SHOP_SLOTS:
			if i < _offers().size() and typeof(_offers()[i]) == TYPE_STRING and _slot_rect(i).has_point(mouse):
				_hover = {"zone": "offer", "i": i}
				return _slot_rect(i)
		var idx := IC.index_at(mouse)
		if idx >= 0:
			_hover = {"zone": "inv", "i": idx, "id": GameState.data["inventory"][idx]}
			return IC.cell_rect(idx)
	return Rect2()


func update(dt: float) -> void:
	var r := _detect()
	if not _hover.is_empty():
		_box.set_target(r)
	_box.update(dt)
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_flash.target = 0.0
	_flash.update(dt)


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
		"tab":
			_tab = p["tab"]
			_sel = {}
		"offer":
			var same: bool = not _sel.is_empty() and _sel["kind"] == "offer" and _sel["idx"] == p["i"]
			_sel = {} if same else {"kind": "offer", "idx": p["i"]}
		"inv":
			var same2: bool = not _sel.is_empty() and _sel["kind"] == "inv" and _sel["id"] == p["id"]
			_sel = {} if same2 else {"kind": "inv", "id": p["id"]}
		"button":
			_run_action()


func key_pressed(key: int) -> void:
	if key == KEY_ESCAPE:
		app.switch_to("stage_select")


func _is_pressed(zone: String) -> bool:
	return not _pressed.is_empty() and _pressed.get("zone") == zone and _hover.get("zone") == zone


func _price(x: float, y: float, amount: int, col: Color) -> void:
	var s := str(amount)
	var w := 14.0 + C.text_w(s, 13)
	var left := floorf(x - w / 2.0)
	C.coin(self, left + 5.0, y + C.text_h(13) / 2.0, 5.0)
	C.text(self, s, left + 14.0, y, 13, col)


func draw_scene() -> void:
	var back_p := _is_pressed("back")
	C.top_bar(self, "SHOP", back_p)
	var gold := str(int(GameState.data["gold"]))
	C.text_right(self, gold, C.VW - MARGIN, floorf((C.TOP_BAR_H - C.text_h(16)) / 2.0), 16, C.WHITE)
	C.coin(self, C.VW - MARGIN - C.text_w(gold, 16) - 10.0, floorf(C.TOP_BAR_H / 2.0), 7.0)
	var p := _panel()
	C.outline(self, p, C.WHITE, 2.0)
	draw_line(Vector2(p.position.x + PAD, _divider_y() + 0.5), Vector2(p.end.x - PAD, _divider_y() + 0.5), C.WHITE, 1.0)
	for which in ["gear", "hire"]:
		var tr := _tab_rect(which)
		if _tab == which:
			draw_rect(tr, C.WHITE)
			C.text_centered(self, which.to_upper(), tr, 16, C.RED)
		else:
			C.outline(self, tr, C.RED, 2.0)
			C.text_centered(self, which.to_upper(), tr, 16, C.WHITE)
	if _tab == "gear":
		_draw_gear()
	else:
		C.text_centered(self, "No one is looking for work", Rect2(p.position.x, _divider_y(), p.size.x, p.end.y - _divider_y()), 14, C.WHITE)
	var action := _action()
	if not action.is_empty():
		var br := _btn_rect()
		if action["enabled"]:
			draw_rect(br, C.RED)
		else:
			C.outline(self, br, C.RED, 1.0)
		var label := "%s %d" % [action["verb"], int(action["price"])]
		var sx := floorf(br.position.x + (br.size.x - (16.0 + C.text_w(label, 16))) / 2.0)
		C.coin(self, sx + 6.0, br.position.y + br.size.y / 2.0, 6.0)
		C.text(self, label, sx + 16.0, floorf(br.position.y + (br.size.y - C.text_h(16)) / 2.0), 16, C.WHITE if action["enabled"] else C.RED)
	var fa: float = clampf(_flash.value, 0.0, 1.0)
	if fa > 0.01:
		C.text_centered(self, _flash_text, Rect2(p.position.x + PAD, _btn_rect().position.y - 24.0, _inner_w(), 20.0), 14, Color(1, 0, 0, fa))
	var sel_inv: String = String(_sel["id"]) if (not _sel.is_empty() and _sel["kind"] == "inv") else ""
	IC.draw_inventory(self, sel_inv, "Click an item to sell it" if _tab == "gear" else "")
	_box.draw(self, back_p)
	C.back_button(self, back_p)


func draw_overlay(c: CanvasItem) -> void:
	match _hover.get("zone", ""):
		"offer":
			var inst := GameState.item_of(_offers()[_hover["i"]])
			if not inst.is_empty():
				var r := _slot_rect(_hover["i"])
				C.tooltip(c, IC.tooltip_lines(inst, "", "Costs", int(inst["value"])), Rect2(r.position, r.size + Vector2(0, 20)))
		"inv":
			var inst2 := GameState.item_of(_hover["id"])
			if not inst2.is_empty():
				C.tooltip(c, IC.tooltip_lines(inst2, "", "Sells for", int(inst2["sellPrice"])), IC.cell_rect(_hover["i"]))


func _draw_gear() -> void:
	var p := _panel()
	for i in GameState.SHOP_SLOTS:
		var r := _slot_rect(i)
		C.outline(self, r, C.WHITE, 1.0)
		var entry: Variant = _offers()[i] if i < _offers().size() else null
		var inst := GameState.item_of(entry)
		if not inst.is_empty():
			IC.glyph(self, inst, r.position.x + 6.0, r.position.y + 6.0, SLOT - 12.0)
			_price(r.position.x + SLOT / 2.0, r.end.y + 4.0, int(inst["value"]), C.GOLD if int(GameState.data["gold"]) >= int(inst["value"]) else C.RED)
			if not _sel.is_empty() and _sel["kind"] == "offer" and _sel["idx"] == i:
				C.outline(self, Rect2(r.position + Vector2.ONE, r.size - Vector2(2, 2)), C.WHITE, 2.0)
		elif typeof(entry) == TYPE_BOOL:
			C.text_centered(self, "SOLD", r, 13, C.WHITE)
	var inst2 := _selected_item()
	var detail_y := _btn_rect().position.y - 46.0
	if not inst2.is_empty():
		C.text_centered(self, C.fit_text(inst2["name"], 14, _inner_w()), Rect2(p.position.x + PAD, detail_y, _inner_w(), 18.0), 14, C.WHITE)
		C.text_centered(self, C.fit_text(IC.mods_text(inst2), 13, _inner_w()), Rect2(p.position.x + PAD, detail_y + 18.0, _inner_w(), 16.0), 13, C.RED)
	else:
		C.text_centered(self, "Click an item to buy or sell it", _btn_rect(), 13, C.WHITE)
