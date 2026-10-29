extends Control
## The encounter HUD, ported 1:1 from the 2D game (main-game/encounter/ui.lua + screens/encounter.lua + defeat.lua).
## It is drawn on an 800x450 canvas (the 2D game's virtual resolution) that the CanvasLayer scales up to the window,
## so every number below is the 2D number: skill icons 50 px at (5,5) with 5 px gaps, resource bar 10 segments along the
## bottom, HP/stagger bars 40x4 above each unit, hero numbers, pause icon top right, pause menu, VICTORY / DEFEAT in 50 px
## red Dedicool, and the Kenney hand / crosshair cursor. Every gradual change is a SmoothValue (UI_ANIMATION.md).
##
## `bind(view)` gives it the sandbox view (battle, camera, selection, hover, paused). It never changes the battle; the
## pause button and menu emit signals.

const Sandbox := preload("res://sim/sandbox_battle.gd")
const MenuCommon := preload("res://menus/menu_common.gd")

signal pause_toggled
signal retreat

const VW := 800.0
const VH := 450.0
const SCALE := 1280.0 / 800.0           # window (1280x720 base) pixels per HUD pixel

# 2D constants (encounter/ui.lua, screens/encounter.lua)
const BAR_W := 28.0                  # smaller than the 2D game's 40x4
const BAR_H := 3.0
const BAR_GAP := 1.0
const BAR_SHOW_TIME := 2.0           # a bar stays this long after its unit's health changes, then shrinks away
const ABOVE := 10.0
const ICON_SIZE := 50.0
const ICON_GAP := 5.0
const ICON_X := 5.0
const ICON_Y := 5.0
const RES_PER_SEG := 5.0
const RES_SEG_COUNT := 10
const RES_BAR_H := 8.0
const RES_MARGIN_X := 15.0
const RES_SEG_GAP := 2.0
const RES_POP_EXTRA := 10.0
const RES_BAR_Y := VH - RES_BAR_H - 4.0
const PAUSE_BTN_SIZE := 28.0
const PAUSE_BTN_PAD := 6.0
const PAUSE_ITEMS := ["RETURN", "RETREAT"]
const PAUSE_MENU_W := 180.0
const PAUSE_ITEM_H := 34.0
const SKILL_COUNT := 3                  # three abilities per hero (Director)
const SKILL_KEYS := ["Q", "W", "E"]
const SKILL_KEYCODES := [KEY_Q, KEY_W, KEY_E]
const ICON_MIN_SCALE := 0.8
const TAGS := {"WEAKEN": ["W", Color(1, 1, 1)], "VULNERABILITY": ["V", Color(1, 0, 0)], "STUN": ["S", Color(1, 1, 1)],
		"SLOW": ["L", Color(1, 1, 1)], "DOT": ["D", Color(1, 0, 0)], "SHIELD": ["H", Color(1, 0.84, 0.28)], "ATK_BUFF": ["A", Color(1, 0.84, 0.28)],
		"BURN": ["B", Color(1, 0, 0)], "DEF_BUFF": ["G", Color(0.5, 0.7, 1.0)], "INVULN": ["I", Color(0.62, 0.92, 1.0)]}
const DEFEAT_AT := 1.8

var view
var font: Font
var _icons := {}
var _cursors := {}
var _bars := {}                       # unit id -> {fill, trail, alpha}
var _slots: Array = []                # per ability slot: {scale, sweep, cd_alpha}
var _res_fill := SmoothValue.new(0.0, 12.0)
var _res_pops: Array = []
var _last_segments := 0
var aim_text := ""                   # set by the battle view while an aimed ability waits for its target
var _pause_hover := -1
var _pause_pressed := -1
var _btn_down := false
var _mouse_down := false
var _end_text := ""
var _end_delay := 0.0
var _end_t := 0.0
var _end_scale := SmoothValue.new(1.25, 16.0, 0.5)
var _end_dim := SmoothValue.new(0.0, 12.0)
var _menu_alpha := SmoothValue.new(0.0, 18.0)
var _sel_alpha := {}                  # unit id -> SmoothValue plate brightness


func _init() -> void:
	font = MenuCommon.font()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(VW, VH)
	for i in SKILL_COUNT:
		_slots.append({"scale": SmoothValue.new(1.0, 12.0, 0.5), "sweep": SmoothValue.new(0.0, 16.0), "cd_alpha": SmoothValue.new(0.0, 16.0)})


func bind(v) -> void:
	view = v


func press_skill(slot: int) -> void:
	_slots[slot]["scale"].kick(-9.0)


func reject_skill(slot: int) -> void:
	_slots[slot]["scale"].kick(-6.0)


func show_end(text: String, delay: float) -> void:
	_end_text = text
	_end_delay = delay
	_end_t = 0.0
	_end_scale.snap(1.25)
	_end_scale.target = 1.0
	_end_dim.snap(0.0)


func clear_end() -> void:
	_end_text = ""


## Mouse in HUD pixels.
func mouse() -> Vector2:
	return get_viewport().get_mouse_position() / SCALE


# ------------------------------------------------------------------------------------------ layout
func _pause_btn_rect() -> Rect2:
	return Rect2(VW - PAUSE_BTN_PAD - PAUSE_BTN_SIZE, PAUSE_BTN_PAD, PAUSE_BTN_SIZE, PAUSE_BTN_SIZE)


func _menu_rect() -> Rect2:
	var h := 20.0 + PAUSE_ITEMS.size() * PAUSE_ITEM_H + 20.0
	return Rect2(floorf((VW - PAUSE_MENU_W) / 2.0), floorf((VH - h) / 2.0), PAUSE_MENU_W, h)


func _item_rect(i: int) -> Rect2:
	var m := _menu_rect()
	var w := 120.0
	var h := 26.0
	return Rect2(floorf(m.position.x + (m.size.x - w) / 2.0), m.position.y + 20.0 + i * PAUSE_ITEM_H + (PAUSE_ITEM_H - h) / 2.0, w, h)


func _item_at(p: Vector2) -> int:
	for i in PAUSE_ITEMS.size():
		if _item_rect(i).has_point(p):
			return i
	return -1


## Mouse button forwarded by the view. Returns true when the HUD used the click (pause button / pause menu).
func handle_mouse(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var p: Vector2 = event.position / SCALE
	_mouse_down = event.pressed
	if event.pressed:
		if _pause_btn_rect().has_point(p):
			_btn_down = true
			return true
		if view.paused:
			_pause_pressed = _item_at(p)
			return true
		return false
	var used := false
	if _btn_down:
		_btn_down = false
		used = true
		if _pause_btn_rect().has_point(p):
			pause_toggled.emit()
	if _pause_pressed >= 0:
		var i := _item_at(p)
		if i == _pause_pressed:
			if i == 0:
				pause_toggled.emit()
			else:
				retreat.emit()
		_pause_pressed = -1
		used = true
	return used


# ------------------------------------------------------------------------------------------ update
func _process(delta: float) -> void:
	if view == null or view.battle == null:
		return
	var b = view.battle
	_pause_hover = _item_at(mouse()) if view.paused else -1
	# resource bar
	_res_fill.target = b.resource
	_res_fill.update(delta)
	var segs := int(floor(b.resource / RES_PER_SEG))
	if segs > _last_segments:
		var pv := SmoothValue.new(1.0, 5.0)
		pv.target = 0.0
		_res_pops.append({"seg": segs - 1, "v": pv})
	_last_segments = segs
	for p in _res_pops.duplicate():
		p["v"].update(delta)
		if p["v"].value < 0.02:
			_res_pops.erase(p)
	# ability icons
	var hs: Array = b.heroes()
	var hero = hs[view.selected_index] if view.selected_index < hs.size() else null
	for i in SKILL_COUNT:
		var s: Dictionary = _slots[i]
		var held: bool = Input.is_key_pressed(SKILL_KEYCODES[i]) and not view.paused
		s["scale"].target = ICON_MIN_SCALE if held else 1.0
		s["scale"].update(delta)
		if hero != null and i < hero.skills.size():
			var sk: Dictionary = hero.skills[i]
			var cost: float = sk["cost"]
			s["sweep"].target = (cost - b.resource) / cost if cost > 0.0 and b.resource < cost else 0.0
			s["cd_alpha"].target = 1.0 if sk["cd"] > 0.0 else 0.0
		else:
			s["sweep"].target = 0.0
			s["cd_alpha"].target = 0.0
		s["sweep"].update(delta)
		s["cd_alpha"].update(delta)
	# unit bars
	for id in b.units:
		var u = b.units[id]
		if not _bars.has(id):
			_bars[id] = {"fill": SmoothValue.new(1.0, 14.0), "trail": SmoothValue.new(1.0, 3.0), "alpha": SmoothValue.new(1.0, 20.0), "width": SmoothValue.new(0.0, 16.0, 0.8), "last": u.hp, "show": 0.0}
		var d: Dictionary = _bars[id]
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		d["fill"].target = ratio
		d["trail"].target = ratio
		if ratio > d["trail"].value:
			d["trail"].snap(ratio)
		d["alpha"].target = 0.0 if u.state == Sandbox.State.DEAD else 1.0
		if absf(u.hp - d["last"]) > 0.001:
			d["last"] = u.hp
			d["show"] = BAR_SHOW_TIME
		d["show"] = maxf(d["show"] - delta, 0.0)
		var is_sel: bool = u.team == 0 and hero == u
		d["width"].target = 1.0 if (d["show"] > 0.0 or is_sel) and u.state != Sandbox.State.DEAD else 0.0
		for k in ["fill", "trail", "alpha", "width"]:
			d[k].update(delta)
	for id in _bars.keys():
		if not b.units.has(id):
			_bars.erase(id)
	# end banner
	if _end_text != "":
		_end_t += delta
		_end_scale.update(delta)
		_end_dim.target = 0.5 if _end_text == "DEFEAT" and _end_t >= _end_delay else 0.0
		_end_dim.update(delta)
	_menu_alpha.target = 1.0 if view.paused else 0.0
	_menu_alpha.update(delta)
	queue_redraw()


# ------------------------------------------------------------------------------------------ drawing
func _text(s: String, x: float, y: float, px: int, col: Color) -> void:
	draw_string(font, Vector2(floorf(x), floorf(y) + font.get_ascent(px)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_centered(s: String, r: Rect2, px: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_text(s, r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y - font.get_height(px)) / 2.0, px, col)


func _draw() -> void:
	if view == null or view.battle == null:
		return
	_draw_bars()
	_draw_skills()
	_draw_resource_bar()
	_draw_aim_text()
	_draw_end()
	_draw_pause_button()
	_draw_pause_menu()
	_draw_cursor()


func _head_of(u) -> Vector3:
	return Vector3(u.agent.pos.x, 2.1 * (0.75 if u.model == "goblin" else (0.92 if u.model in ["knight", "mannequin"] else 1.0)), u.agent.pos.y)


func _draw_bars() -> void:
	var b = view.battle
	var cam: Camera3D = view.stage.camera
	var heroes: Array = b.heroes()
	var sel = heroes[view.selected_index] if view.selected_index < heroes.size() else null
	for id in b.units:
		var u = b.units[id]
		var d: Dictionary = _bars[id] if _bars.has(id) else {}
		if d.is_empty() or d["alpha"].value < 0.02 or d["width"].value < 0.02:
			continue
		var head := _head_of(u)
		if cam.is_position_behind(head):
			continue
		var sp: Vector2 = cam.unproject_position(head) / SCALE
		var a: float = clampf(d["alpha"].value, 0.0, 1.0)
		var bw: float = BAR_W * clampf(d["width"].value, 0.0, 1.2)      # grows from the centre
		var bar_x := floorf(sp.x - bw / 2.0)
		var hp_y := floorf(sp.y) - ABOVE - BAR_H
		var stg_y := hp_y + BAR_H + BAR_GAP
		draw_rect(Rect2(bar_x - 2, hp_y - 1, bw + 4, BAR_H + 2), Color(0.2, 0.2, 0.2, a))
		var ratio: float = clampf(d["fill"].value, 0.0, 1.0)
		var hp_col := Color(0, 1, 0, a) if u.team == 0 else Color(1, 1, 0, a)
		draw_rect(Rect2(bar_x, hp_y, bw * ratio, BAR_H), hp_col)
		var trail: float = clampf(d["trail"].value, 0.0, 1.0)
		if trail > ratio:
			draw_rect(Rect2(bar_x + bw * ratio, hp_y, bw * (trail - ratio), BAR_H), Color(0.9, 0.1, 0.1, 0.6 * a))
		# stagger track (the sandbox has no stagger yet: the empty track and its threshold tick, as the 2D game draws them)
		draw_rect(Rect2(bar_x, stg_y, bw, BAR_H), Color(0.18, 0.18, 0.18, a))
		draw_rect(Rect2(bar_x + bw - 2, stg_y, 2, BAR_H), Color(0.75, 0.75, 0.75, a))
		# hover / pressed plate: green on a hero, red on an enemy; brighter while the button is down
		if id == view.hover_id:
			var bright := 1.0 if _mouse_down else 0.65
			var plate_h := BAR_H + BAR_GAP + BAR_H + 2.0
			var c := Color(bright, 0, 0, a) if u.team == 1 else Color(0, bright, 0, a)
			draw_rect(Rect2(bar_x - 3 + 0.5, hp_y - 2 + 0.5, bw + 6 - 1, plate_h - 1), c, false, 1.0)
		# status tags (3D sandbox addition: the 2D game shows these through particles)
		var tx := bar_x + bw + 6.0
		for st in TAGS:
			if u.statuses.has(st):
				_text(TAGS[st][0], tx, hp_y - 1, 10, Color(TAGS[st][1].r, TAGS[st][1].g, TAGS[st][1].b, a))
				tx += 8.0
	# the hero's number (its selection key), with a 1-pixel black outline
	for i in heroes.size():
		var h = heroes[i]
		var d2: Dictionary = _bars.get(h.id, {})
		if d2.is_empty() or d2["alpha"].value < 0.02:
			continue
		var head := _head_of(h)
		if cam.is_position_behind(head):
			continue
		var sp: Vector2 = cam.unproject_position(head) / SCALE
		var lw := font.get_string_size(str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var wv: float = clampf(d2["width"].value, 0.0, 1.2)
		# beside the bar's left end, riding it as it grows and shrinks; centred over the unit when the bar is gone
		var nx := floorf(sp.x - lw / 2.0 - wv * (BAR_W * wv / 2.0 + 3.0 + lw / 2.0))
		var ny := floorf(floorf(sp.y) - ABOVE - BAR_H)
		var label := str(i + 1)
		var a2: float = clampf(d2["alpha"].value, 0.0, 1.0)
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				if ox != 0 or oy != 0:
					_text(label, nx + ox, ny + oy, 10, Color(0, 0, 0, a2))
		_text(label, nx, ny, 10, Color(0, 1, 0, a2) if h == sel else Color(1, 1, 1, a2))


func _icon_for(name: String) -> Texture2D:
	var n := name.trim_prefix("skill_icons")
	var digits := ""
	for ch in n:
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	if digits == "":
		return null
	if not _icons.has(digits):
		var path := "res://assets/ui/skill_icons%s.png" % digits
		_icons[digits] = load(path) if ResourceLoader.exists(path) else null
	return _icons[digits]


func _draw_skills() -> void:
	var heroes: Array = view.battle.heroes()
	if view.selected_index >= heroes.size():
		return
	var hero = heroes[view.selected_index]
	for i in SKILL_COUNT:
		if i >= hero.skills.size():
			continue                                   # a slot with no ability is not drawn
		var sk: Dictionary = hero.skills[i]
		var s: Dictionary = _slots[i]
		var ix := ICON_X + i * (ICON_SIZE + ICON_GAP)
		var iy := ICON_Y
		var sc: float = clampf(s["scale"].value, ICON_MIN_SCALE, 1.5)   # hard limit: never below 80%
		var cx := ix + ICON_SIZE / 2.0
		var cy := iy + ICON_SIZE / 2.0
		var tex := _icon_for(String(sk.get("icon", "")))
		var side := ICON_SIZE * sc
		if tex != null:
			draw_texture_rect(tex, Rect2(cx - side / 2.0, cy - side / 2.0, side, side), false)
		else:
			draw_rect(Rect2(cx - side / 2.0, cy - side / 2.0, side, side), Color(0.5, 0.5, 0.5))
		# resource sweep: fills from the top, shrinks as the resource approaches the cost
		var sweep: float = clampf(s["sweep"].value, 0.0, 1.0)
		if sweep > 0.001:
			draw_rect(Rect2(cx - side / 2.0, cy - side / 2.0, side, side * sweep), Color(0, 0, 0, 0.6))
		# cooldown: slight tint and the centred second count
		var cda: float = clampf(s["cd_alpha"].value, 0.0, 1.0)
		if cda > 0.01:
			draw_rect(Rect2(cx - side / 2.0, cy - side / 2.0, side, side), Color(0, 0, 0, 0.45 * cda))
			if sk["cd"] > 0.0:
				_text_centered(str(int(ceil(sk["cd"]))), Rect2(ix, iy, ICON_SIZE, ICON_SIZE), 10, Color(1, 1, 1, 1))
		_text(SKILL_KEYS[i], ix + 2, iy + ICON_SIZE - 12, 10, Color(1, 1, 1, 0.7))
		draw_rect(Rect2(cx - side / 2.0 + 0.5, cy - side / 2.0 + 0.5, side - 1, side - 1), Color(0.5, 0.5, 0.5, 1), false, 1.0)


func _draw_resource_bar() -> void:
	var total_w := VW - 2.0 * RES_MARGIN_X
	var seg_w := (total_w - (RES_SEG_COUNT - 1) * RES_SEG_GAP) / RES_SEG_COUNT
	for i in RES_SEG_COUNT:
		var seg_x := RES_MARGIN_X + i * (seg_w + RES_SEG_GAP)
		var pop := 0.0
		for p in _res_pops:
			if p["seg"] == i:
				pop = maxf(pop, clampf(p["v"].value, 0.0, 1.0))
		var extra := pop * RES_POP_EXTRA
		var cx := seg_x + seg_w / 2.0
		var cy := RES_BAR_Y + RES_BAR_H / 2.0
		var dw := seg_w + extra
		var dh := RES_BAR_H + extra
		var dx := cx - dw / 2.0
		var dy := cy - dh / 2.0
		draw_rect(Rect2(dx, dy, dw, dh), Color(0.15, 0.15, 0.15, 1))
		var filled := clampf((_res_fill.value - i * RES_PER_SEG) / RES_PER_SEG, 0.0, 1.0)
		if filled > 0.0:
			draw_rect(Rect2(dx, dy, dw * filled, dh), Color(1, 1, 1, 1))


func GameState_from_menu() -> bool:
	return load("res://menus/game_state.gd").from_menu


func _draw_aim_text() -> void:
	if aim_text != "":
		_text_centered(aim_text, Rect2(0, VH - 44, VW, 14), 10, Color.WHITE)


func _draw_end() -> void:
	if _end_text == "" or _end_t < _end_delay:
		return
	if _end_dim.value > 0.001:
		draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, _end_dim.value))
	var px := 50
	var w := font.get_string_size(_end_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var h := font.get_height(px)
	var sc := maxf(_end_scale.value, 0.01)
	draw_set_transform(Vector2(VW / 2.0, VH / 2.0 - 10.0), 0.0, Vector2(sc, sc))
	draw_string(font, Vector2(-w / 2.0, -h / 2.0 + font.get_ascent(px)), _end_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1, 0, 0, 1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if view.battle.over != "" and GameState_from_menu():
		_text_centered("Click to continue", Rect2(0, VH / 2.0 + 26.0, VW, 16), 13, Color.WHITE)


func _draw_pause_button() -> void:
	var r := _pause_btn_rect()
	if not view.paused:
		var bar_w := 5.0
		var bar_h := r.size.y * 0.5
		var gap := 5.0
		var bx := r.position.x + (r.size.x - (bar_w * 2.0 + gap)) / 2.0
		draw_rect(Rect2(bx, r.position.y + (r.size.y - bar_h) / 2.0, bar_w, bar_h), Color.WHITE)
		draw_rect(Rect2(bx + bar_w + gap, r.position.y + (r.size.y - bar_h) / 2.0, bar_w, bar_h), Color.WHITE)
	else:
		var c := r.get_center()
		var rr := r.size.y * 0.32
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - rr * 0.6, c.y - rr), Vector2(c.x - rr * 0.6, c.y + rr), Vector2(c.x + rr, c.y)]), Color.WHITE)


func _draw_pause_menu() -> void:
	var a: float = clampf(_menu_alpha.value, 0.0, 1.0)
	if a < 0.01:
		return
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.5 * a))
	var m := _menu_rect()
	draw_rect(m, Color(0, 0, 0, a))
	draw_rect(Rect2(m.position + Vector2.ONE, m.size - Vector2(2, 2)), Color(1, 1, 1, a), false, 2.0)
	for i in PAUSE_ITEMS.size():
		var r := _item_rect(i)
		var pressed := _pause_pressed == i and _pause_hover == i
		if pressed:
			draw_rect(r, Color(1, 1, 1, a))
		elif _pause_hover == i:
			draw_rect(Rect2(r.position + Vector2.ONE, r.size - Vector2(2, 2)), Color(1, 0, 0, a), false, 2.0)
		_text_centered(PAUSE_ITEMS[i], r, 16, Color(0, 0, 0, a) if pressed else Color(1, 1, 1, a))


func _cursor_tex(tile: int) -> Texture2D:
	if not _cursors.has(tile):
		_cursors[tile] = load("res://assets/cursor/tile_%04d.png" % tile)
	return _cursors[tile]


## The hand, or the crosshair over a unit a click would target (red for an enemy). Hot spots from common.lua.
func _draw_cursor() -> void:
	var p := mouse()
	p = Vector2(clampf(floorf(p.x), 0, VW - 1), clampf(floorf(p.y), 0, VH - 1))
	var live: bool = not view.paused and _end_text == ""
	var heroes_now: Array = view.battle.heroes()
	var sel_hero = heroes_now[view.selected_index] if view.selected_index < heroes_now.size() else null
	var healer: bool = sel_hero != null and sel_hero.heals
	var on_target: bool = live and view.hover_id >= 0 and view.battle.units.has(view.hover_id) and (view.battle.units[view.hover_id].team == 1) != healer
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var tile: int
	var hot: Vector2
	var tint := Color.WHITE
	if on_target:
		tile = 54 if down else 55
		hot = Vector2(8, 8)
		tint = Color(0, 1, 0) if healer else Color(1, 0, 0)
	else:
		tile = 137 if down else 175
		hot = Vector2(5, 1) if down else Vector2(3, 1)
	var tex := _cursor_tex(tile)
	if tex != null:
		draw_texture(tex, p - hot, tint)
