extends RefCounted
## How an item looks in the menus (item_ui.lua): the glyph token (W / A / T in a frame tinted by grade), the bonus text, the tooltip lines, and the shared
## INVENTORY panel (7 x 5 grid) that the EQUIP and SHOP screens both draw.

const C := preload("res://menus/menu_common.gd")
const GameState := preload("res://menus/game_state.gd")
const GRADE_COLORS := {1: Color(1, 1, 1), 2: Color(0.95, 0.78, 0.2), 3: Color(1, 0, 0)}
const GLYPHS := {"weapon": "W", "armor": "A", "trinket": "T"}
const COLS := 7
const ROWS := 5
const CELL := 64.0
const HEAD_H := 34.0
const PAD := 14.0

static func inv_rect() -> Rect2:
	var x := 306.0
	var y := C.TOP_BAR_H + 12.0
	return Rect2(x, y, C.VW - 20.0 - x, C.VH - 20.0 - y)


static func cell_rect(idx: int) -> Rect2:
	var r := inv_rect()
	var gx := r.position.x + floorf((r.size.x - COLS * CELL) / 2.0)
	var gy := r.position.y + HEAD_H + floorf((r.size.y - HEAD_H - ROWS * CELL) / 2.0)
	return Rect2(gx + (idx % COLS) * CELL, gy + (idx / COLS) * CELL, CELL, CELL)


static func index_at(p: Vector2) -> int:
	var inv: Array = GameState.data["inventory"]
	for idx in mini(inv.size(), COLS * ROWS):
		if cell_rect(idx).has_point(p):
			return idx
	return -1


static func grade_color(inst: Dictionary) -> Color:
	return GRADE_COLORS.get(int(inst.get("grade", 1)), Color.WHITE)


static func glyph(c: CanvasItem, inst: Dictionary, x: float, y: float, size: float) -> void:
	C.outline(c, Rect2(x + 2.0, y + 2.0, size - 4.0, size - 4.0), grade_color(inst), 2.0)
	C.text_centered(c, GLYPHS.get(inst.get("itemType", ""), "?"), Rect2(x, y, size, size), 16, C.WHITE)


static func mods_text(inst: Dictionary, sep: String = ", ") -> String:
	var parts: Array = []
	for k in inst.get("mods", {}):
		var v: float = float(inst["mods"][k])
		parts.append("+%s %s" % [str(int(v)) if k != "CRIT" else str(snappedf(v, 0.01)), k])
	parts.sort()
	return sep.join(parts)


static func tooltip_lines(inst: Dictionary, char_name: String = "", price_label: String = "", price: int = 0) -> Array:
	var lines: Array = [{"text": inst.get("name", "(unnamed)"), "size": 16, "color": grade_color(inst) if int(inst.get("grade", 1)) > 1 else C.WHITE},
			{"text": C.title_case(inst.get("itemType", "item")) + ((" (" + C.title_case(GameState.armor_weight(inst)) + ")") if GameState.armor_weight(inst) != "" else ""), "color": C.WHITE}]
	if String(inst.get("desc", "")) != "":
		lines.append({"text": inst["desc"], "color": C.WHITE})
	var mt := mods_text(inst)
	if mt != "":
		lines.append({"text": mt, "color": C.RED})
	if inst.get("itemType", "") == "weapon":
		var ws := GameState.weapon_speed(inst)
		lines.append({"text": "Attack cooldown x%s (%s)" % [String.num(ws, 2), "fast" if ws < 1.0 else ("slow" if ws > 1.0 else "normal")], "color": C.WHITE})
	var users: Array = inst.get("usableBy", [])
	if not users.is_empty():
		var names: Array = []
		for u in users:
			names.append(C.title_case(u))
		lines.append({"text": "For: " + ", ".join(names), "color": C.WHITE})
	if char_name != "" and not GameState.can_use(inst, char_name):
		var why := GameState.weight_problem(inst, char_name)
		lines.append({"text": why if why != "" else C.title_case(char_name) + " cannot use this", "color": C.RED})
	if price_label != "":
		lines.append({"text": "%s %d gold" % [price_label, price], "color": C.GOLD})
	return lines


static func draw_inventory(c: CanvasItem, selected_id: String, hint: String) -> void:
	var r := inv_rect()
	C.outline(c, r, C.WHITE, 2.0)
	var head_y := floorf(r.position.y + (HEAD_H - C.text_h(16)) / 2.0) + 2.0
	C.text(c, "INVENTORY", r.position.x + PAD, head_y, 16, C.RED)
	if hint != "":
		var fitted := C.fit_text(hint, 13, r.size.x - PAD * 2.0 - C.text_w("INVENTORY", 16) - 16.0)
		C.text_right(c, fitted, r.end.x - PAD, head_y + 2.0, 13, C.WHITE)
	for idx in COLS * ROWS:
		C.outline(c, cell_rect(idx), C.WHITE, 1.0)
	var inv: Array = GameState.data["inventory"]
	for idx in mini(inv.size(), COLS * ROWS):
		var cr := cell_rect(idx)
		var inst := GameState.item_of(inv[idx])
		if not inst.is_empty():
			glyph(c, inst, cr.position.x + 6.0, cr.position.y + 6.0, CELL - 12.0)
		if inv[idx] == selected_id:
			C.outline(c, Rect2(cr.position + Vector2.ONE, cr.size - Vector2(2, 2)), C.WHITE, 2.0)
