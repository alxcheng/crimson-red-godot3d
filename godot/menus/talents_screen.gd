extends "res://menus/menu_screen.gd"
## TALENTS (screens/talents.lua, Academy): one hero's talent ladder, a vertical list of level rows where the fork levels offer two options (A / B).
## Director: picks are SWITCHABLE, not permanent: any reached fork can be re-picked at any time (click the other option; click the chosen one to clear it),
## free of charge. The ladder is the 2D game's (Knight) or the Director's skill tree (Wizard, data/wizard_talents.json); a tier with no options yet is shown
## as "to be defined". Left: the hero's abilities (Q W E, three at most) with icons and tooltips. Wheel scrolls the ladder (a SmoothValue). Dev: L adds a level.

const SLOTS := 4
const ICON := 44.0
const PARTY_GAP := 12.0
const NODE_H := 24.0
const NODE_GAP := 6.0
const FORK_H := 40.0
const BOX_W := 200.0
const CENTER_X := 400.0
const ABIL_X := 22.0
const ABIL_ICON := 40.0
const ABIL_GAP := 14.0
const ABIL_ROW_W := 150.0
const KEYS := ["Q", "W", "E"]

var _party: Array = []
var _sel_char := ""
var _scroll := SmoothValue.new(0.0, 14.0)
var _rows: Array = []                       # built each frame: {kind, level, y, h, choice, left, right}
var _content_h := 0.0
var _hover := {}
var _pressed := {}
var _box := C.RedBox.new()
var _clip: Control


func _ladder_top() -> float:
	return C.TOP_BAR_H + 12.0 + ICON + 10.0 + 18.0 + 26.0


func _ladder_bottom() -> float:
	return C.VH - 16.0


func _chip_rect(i: int) -> Rect2:
	var total := SLOTS * ICON + (SLOTS - 1) * PARTY_GAP
	return Rect2(floorf((C.VW - total) / 2.0) + i * (ICON + PARTY_GAP), C.TOP_BAR_H + 12.0, ICON, ICON)


func _abil_rect(i: int) -> Rect2:
	return Rect2(ABIL_X, _ladder_top() + 18.0 + i * (ABIL_ICON + ABIL_GAP), ABIL_ROW_W, ABIL_ICON)


func enter(_args: Dictionary = {}) -> void:
	_party = GameState.party()
	_sel_char = _party[0] if not _party.is_empty() else ""
	_clip = Control.new()
	_clip.position = Vector2(CENTER_X - BOX_W - 24.0, _ladder_top() - 8.0)
	_clip.size = Vector2((BOX_W + 24.0) * 2.0, _ladder_bottom() - _ladder_top() + 12.0)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_clip.draw.connect(_draw_ladder)
	add_child(_clip)
	_box.init_at(C.padded(_chip_rect(0)) if not _party.is_empty() else C.back_box())


func exit() -> void:
	GameState.write_save()


func _level() -> int:
	return GameState.level_of(_sel_char)


## Rows of the ladder, level 1 up to the last fork. A fork level gets one fork row per tier at that level (the Wizard has two tiers at level 10).
func _build_rows() -> void:
	_rows = []
	if _sel_char == "":
		return
	var ladder := GameState.ladder_for(_sel_char)
	var choices: Array = ladder["choices"]
	var last := 1
	for ch in choices:
		last = maxi(last, int(ch["level"]))
	var y := _ladder_top() - _scroll.value
	for lvl in range(1, last + 1):
		var any := false
		for i in choices.size():
			if int(choices[i]["level"]) == lvl:
				any = true
				_rows.append({"kind": "fork", "level": lvl, "idx": i, "y": y, "h": FORK_H})
				y += FORK_H + NODE_GAP
		if not any:
			_rows.append({"kind": "plain", "level": lvl, "y": y, "h": NODE_H})
			y += NODE_H + NODE_GAP
	_content_h = y + _scroll.value - _ladder_top()
	var max_scroll := maxf(0.0, _content_h - (_ladder_bottom() - _ladder_top()))
	_scroll.target = clampf(_scroll.target, 0.0, max_scroll)


func _row_boxes(row: Dictionary) -> Array:
	return [Rect2(CENTER_X - 12.0 - BOX_W, row["y"], BOX_W, FORK_H), Rect2(CENTER_X + 12.0, row["y"], BOX_W, FORK_H)]


func _state(row: Dictionary, opt_idx: int) -> String:
	var ch: Dictionary = GameState.ladder_for(_sel_char)["choices"][row["idx"]]
	if ch["options"].size() <= opt_idx:
		return "tbd"
	if _level() < int(row["level"]):
		return "locked"
	return "chosen" if GameState.chosen_option(_sel_char, row["idx"]) == ch["options"][opt_idx]["id"] else "selectable"


func _in_ladder(p: Vector2) -> bool:
	return p.y >= _ladder_top() - 8.0 and p.y < _ladder_bottom() + 4.0


func _detect() -> Rect2:
	_hover = {}
	if C.BACK_RECT.has_point(mouse):
		_hover = {"zone": "back"}
		return C.back_box()
	for i in _party.size():
		if _chip_rect(i).has_point(mouse):
			_hover = {"zone": "chip", "char": _party[i], "i": i}
			return C.padded(_chip_rect(i))
	var abil := GameState.active_abilities(_sel_char)
	for i in abil.size():
		if _abil_rect(i).has_point(mouse):
			_hover = {"zone": "abil", "i": i}
			return Rect2()
	if _in_ladder(mouse):
		for row in _rows:
			if row["kind"] != "fork":
				continue
			var boxes := _row_boxes(row)
			for k in 2:
				if boxes[k].has_point(mouse):
					_hover = {"zone": "opt", "row": row, "k": k, "rect": boxes[k]}
					return boxes[k]
	return Rect2()


func update(dt: float) -> void:
	_build_rows()
	var r := _detect()
	if not _hover.is_empty() and r.size.x > 0.0:
		_box.set_target(r)
	_box.update(dt)
	_scroll.update(dt)
	_clip.queue_redraw()


func wheel(dy: float) -> void:
	var max_scroll := maxf(0.0, _content_h - (_ladder_bottom() - _ladder_top()))
	_scroll.target = clampf(_scroll.target + dy * 60.0, 0.0, max_scroll)


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
			_scroll.snap(0.0)
			_scroll.target = 0.0
		"opt":
			var row: Dictionary = p["row"]
			var st := _state(row, p["k"])
			if st == "selectable":
				GameState.write_choice(_sel_char, row["idx"], GameState.ladder_for(_sel_char)["choices"][row["idx"]]["options"][p["k"]]["id"])      # switch to this one
			elif st == "chosen":
				GameState.write_choice(_sel_char, row["idx"], "")                                           # click the chosen one again: clear it


func key_pressed(key: int) -> void:
	if key == KEY_ESCAPE:
		app.switch_to("stage_select")
	elif key == KEY_L and _sel_char != "":                       # dev: +1 level, to try the higher forks
		var rec := GameState.record(_sel_char)
		rec["level"] = mini(GameState.MAX_LEVEL, int(rec["level"]) + 1)
		rec["pointsToNextLevel"] = GameState.xp_to_next(int(rec["level"]))


func _opt_desc(opt: Dictionary) -> String:
	if opt.has("ability"):
		var d := GameState.describe_ability(String(opt["ability"]))
		if not d.is_empty():
			if d["target"] == "Passive":
				return "Passive"
			return "Ability  %s s  %d bar%s" % [GameState.num(d["cooldown"]), int(d["bars"]), "" if int(d["bars"]) == 1 else "s"]
	return String(opt.get("desc", ""))


func _portrait(name: String, x: float, y: float, size: float) -> void:
	var tex := C.texture("res://assets/ui/icon-%s.png" % name)
	if tex != null:
		C.icon(self, tex, x, y, size)
	else:
		C.text_centered(self, C.title_case(name), Rect2(x, y, size, size), 12, C.WHITE)


func _is_pressed(zone: String) -> bool:
	return not _pressed.is_empty() and _pressed.get("zone") == zone and _hover.get("zone") == zone


func draw_scene() -> void:
	var back_p := _is_pressed("back")
	C.top_bar(self, "TALENTS", back_p)
	for i in SLOTS:
		var r := _chip_rect(i)
		draw_rect(r, C.BLACK)
		var name: String = _party[i] if i < _party.size() else ""
		var on := name != "" and name == _sel_char
		C.outline(self, r, C.WHITE if on else C.RED, 2.0 if on else 1.0)
		if name != "":
			_portrait(name, r.position.x, r.position.y, ICON)
	if _sel_char != "":
		var pts := int(GameState.record(_sel_char).get("pointsToNextLevel", 0))
		C.text_centered(self, "Lv %d  %s" % [_level(), C.title_case(_sel_char)], Rect2(0, _chip_rect(0).end.y + 10.0, C.VW, 18.0), 14, C.RED)
		C.text_centered(self, ("XP to next level: %d" % pts) if pts > 0 else "Max level", Rect2(0, _chip_rect(0).end.y + 28.0, C.VW, 14.0), 12, C.WHITE)
	var abil := GameState.active_abilities(_sel_char)
	if not abil.is_empty():
		C.text(self, "ABILITIES", ABIL_X, _ladder_top(), 12, C.RED)
	var wt := GameState.ladder_for("wizard")
	for i in abil.size():
		var ar := _abil_rect(i)
		var d := GameState.describe_ability(abil[i])
		draw_rect(Rect2(ar.position, Vector2(ABIL_ICON, ABIL_ICON)), C.BLACK)
		var icon_name := _ability_icon(abil[i])
		var tex := C.texture("res://assets/ui/%s.png" % icon_name) if icon_name != "" else null
		if tex != null:
			draw_texture_rect(tex, Rect2(ar.position, Vector2(ABIL_ICON, ABIL_ICON)), false)
		C.outline(self, Rect2(ar.position, Vector2(ABIL_ICON, ABIL_ICON)), C.WHITE, 1.0)
		C.text(self, KEYS[i], ar.position.x + ABIL_ICON + 8.0, ar.position.y + 4.0, 12, C.RED)
		C.text(self, C.fit_text(String(d.get("name", abil[i])), 12, ABIL_ROW_W - ABIL_ICON - 8.0), ar.position.x + ABIL_ICON + 8.0, ar.position.y + 21.0, 12, C.WHITE)
	_draw_scrollbar()
	C.text_right(self, "Picks can be switched at any time", C.VW - 14.0, C.TOP_BAR_H + 10.0, 12, C.RED)
	C.text_right(self, "L: +1 level (dev)", C.VW - 14.0, C.TOP_BAR_H + 26.0, 12, C.WHITE)
	_box.draw(self, back_p)
	C.back_button(self, back_p)


func _ability_icon(id: String) -> String:
	var wt := GameState.ladder_for("wizard")
	if wt["abilities"].has(id):
		return String(wt["abilities"][id]["icon"])
	var row: Dictionary = GameState.GameData.abilities().get(id, {})
	var n := String(row.get("iconName", ""))
	var digits := ""
	for ch in n.trim_prefix("skill_icons"):
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	return "skill_icons" + digits if digits != "" else ""


func _draw_scrollbar() -> void:
	var view := _ladder_bottom() - _ladder_top()
	if _content_h <= view:
		return
	var sx := CENTER_X + BOX_W + 30.0
	var track_h := view
	var thumb_h := maxf(20.0, track_h * view / _content_h)
	var thumb_y := _ladder_top() + (track_h - thumb_h) * _scroll.value / (_content_h - view)
	draw_rect(Rect2(sx + 1.0, _ladder_top(), 2.0, track_h), C.RED)
	draw_rect(Rect2(sx, thumb_y, 4.0, thumb_h), C.WHITE)


## The ladder is drawn into a clipped child control (the scissor of the 2D screen); coordinates are shifted by its position.
func _draw_ladder() -> void:
	if _sel_char == "":
		return
	_clip.draw_set_transform(-_clip.position, 0.0, Vector2.ONE)
	_clip.draw_line(Vector2(CENTER_X, _ladder_top() - 4.0), Vector2(CENTER_X, _ladder_bottom()), C.RED, 2.0)
	for row in _rows:
		if row["kind"] == "plain":
			var w := 90.0
			var r := Rect2(CENTER_X - w / 2.0, row["y"], w, NODE_H)
			var reached: bool = _level() >= int(row["level"])
			_clip.draw_rect(r, C.BLACK)
			C.outline(_clip, r, C.RED, 2.0 if reached else 1.0)
			C.text_centered(_clip, "Lv %d" % int(row["level"]), r, 13, C.WHITE if reached else C.RED)
		else:
			_draw_fork(row)
	_clip.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fork(row: Dictionary) -> void:
	var ch: Dictionary = GameState.ladder_for(_sel_char)["choices"][row["idx"]]
	var cy: float = row["y"] + FORK_H / 2.0
	var boxes := _row_boxes(row)
	_clip.draw_line(Vector2(CENTER_X, cy), Vector2(boxes[0].end.x, cy), C.RED, 2.0)
	_clip.draw_line(Vector2(CENTER_X, cy), Vector2(boxes[1].position.x, cy), C.RED, 2.0)
	_clip.draw_colored_polygon(PackedVector2Array([Vector2(CENTER_X, cy - 6), Vector2(CENTER_X + 6, cy), Vector2(CENTER_X, cy + 6), Vector2(CENTER_X - 6, cy)]), C.RED)
	for k in 2:
		var b: Rect2 = boxes[k]
		var st := _state(row, k)
		var border := C.RED
		var fill := C.BLACK
		var name_c := C.WHITE
		var desc_c := C.RED
		match st:
			"chosen":
				border = C.WHITE
				fill = C.RED
				desc_c = C.WHITE
			"locked", "tbd":
				name_c = C.RED
		_clip.draw_rect(b, fill)
		C.outline(_clip, b, border, 3.0 if st == "chosen" else 2.0)
		var title := "?" if st == "tbd" else String(ch["options"][k]["name"])
		var desc := "To be defined" if st == "tbd" else _opt_desc(ch["options"][k])
		C.text_centered(_clip, C.fit_text(title, 12, b.size.x - 12.0), Rect2(b.position.x, b.position.y + 3.0, b.size.x, 14.0), 12, name_c)
		C.text_centered(_clip, C.fit_text(desc, 12, b.size.x - 12.0), Rect2(b.position.x, b.end.y - 18.0, b.size.x, 14.0), 12, desc_c)


func draw_overlay(c: CanvasItem) -> void:
	var abil := GameState.active_abilities(_sel_char)
	match _hover.get("zone", ""):
		"chip":
			C.tooltip(c, [{"text": C.title_case(_hover["char"]), "size": 16, "color": C.RED}, {"text": "Lv %d" % GameState.level_of(_hover["char"]), "color": C.WHITE}], _chip_rect(_hover["i"]))
		"abil":
			var d := GameState.describe_ability(abil[_hover["i"]])
			if not d.is_empty():
				var lines: Array = [{"text": "%s  %s" % [KEYS[_hover["i"]], d["name"]], "size": 16, "color": C.RED},
						{"text": "Cooldown %s s    Cost %d bar%s" % [GameState.num(d["cooldown"]), int(d["bars"]), "" if int(d["bars"]) == 1 else "s"], "color": C.RED},
						{"text": d["target"], "color": C.WHITE}]
				for ln in d["lines"]:
					lines.append({"text": String(ln), "color": C.WHITE})
				C.tooltip(c, lines, _abil_rect(_hover["i"]))
		"opt":
			var row: Dictionary = _hover["row"]
			var k: int = _hover["k"]
			var ch: Dictionary = GameState.ladder_for(_sel_char)["choices"][row["idx"]]
			var st := _state(row, k)
			if st == "tbd":
				C.tooltip(c, [{"text": "Level %d" % int(row["level"]), "size": 16, "color": C.RED}, {"text": "This tier has no options yet (to be defined).", "color": C.WHITE}], _hover["rect"])
				return
			var opt: Dictionary = ch["options"][k]
			var lines2: Array = [{"text": opt["name"], "size": 16, "color": C.RED}]
			if opt.has("ability"):
				var d2 := GameState.describe_ability(String(opt["ability"]))
				if not d2.is_empty():
					if d2["target"] != "Passive":
						lines2.append({"text": "Ability    Cooldown %s s    Cost %d bar%s" % [GameState.num(d2["cooldown"]), int(d2["bars"]), "" if int(d2["bars"]) == 1 else "s"], "color": C.RED})
					lines2.append({"text": d2["target"], "color": C.WHITE})
					for ln2 in d2["lines"]:
						lines2.append({"text": String(ln2), "color": C.WHITE})
			else:
				lines2.append({"text": String(opt.get("desc", "")), "color": C.WHITE})
			var status := "Reach level %d to choose" % int(row["level"])
			var col := C.WHITE
			if st == "selectable":
				status = "Click to choose it. You can switch back at any time."
				col = C.RED
			elif st == "chosen":
				status = "Chosen. Click again to clear it, or click the other option to switch."
			lines2.append({"text": status, "color": col})
			C.tooltip(c, lines2, _hover["rect"])
