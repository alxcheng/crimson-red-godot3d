extends "res://menus/menu_screen.gd"
## STAGE SELECT: the hub after PLAY. The five zones of the 2D map (Black Forest, Cold Wastes, Wetcaves, Waxen Desert, Castle Crimson) on the left,
## the chosen zone's preview, name, fights and ENTER on the right. The top bar is the 2D map's: BACK, then the links PARTY / TALENTS / EQUIP / SHOP,
## the zone name at the right and the gold. Style: pure red / white on black (gold only for coins), the red box gliding between items, tooltips.

const LINKS := ["PARTY", "TALENTS", "EQUIP", "SHOP"]
const ROW_X := 20.0
const ROW_Y := 62.0
const ROW_W := 250.0
const ROW_H := 44.0
const ROW_GAP := 10.0
const PREVIEW := Rect2(300, 62, 320, 180)
const ENTER_RECT := Rect2(300, 392, 320, 36)

var _link_rects: Array = []
var _hover := {}
var _pressed := {}
var _box := C.RedBox.new()
var _sel := SmoothValue.new(0.0, 14.0)           # the highlight bar's row (springs between rows)
var _preview_alpha := SmoothValue.new(1.0, 14.0)
var _shown_zone := 0


func enter(_args: Dictionary = {}) -> void:
	_shown_zone = clampi(GameState.zone_index, 0, GameState.unlocked_count() - 1)
	GameState.zone_index = _shown_zone
	_sel.snap(float(_shown_zone))
	_link_rects = []
	var x := C.BACK_RECT.position.x + C.BACK_RECT.size.x + 32.0
	for lbl in LINKS:
		var w := C.text_w(lbl, 16)
		_link_rects.append(Rect2(x, floorf((C.TOP_BAR_H - C.text_h(16)) / 2.0), w, C.text_h(16)))
		x += w + 32.0
	_box.init_at(C.back_box())


func _row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y + i * (ROW_H + ROW_GAP), ROW_W, ROW_H)


func _detect() -> Rect2:
	_hover = {}
	if C.BACK_RECT.has_point(mouse):
		_hover = {"zone": "back"}
		return C.back_box()
	for i in _link_rects.size():
		if _link_rects[i].has_point(mouse):
			_hover = {"zone": "link", "i": i}
			return C.padded(_link_rects[i])
	for i in GameState.unlocked_count():
		if _row_rect(i).has_point(mouse):
			_hover = {"zone": "row", "i": i}
			return C.padded(_row_rect(i))
	if ENTER_RECT.has_point(mouse):
		_hover = {"zone": "enter"}
		return C.padded(ENTER_RECT)
	return Rect2()


func update(dt: float) -> void:
	var r := _detect()
	if not _hover.is_empty():
		_box.set_target(r)
	_box.update(dt)
	_sel.target = float(GameState.zone_index)
	_sel.update(dt)
	if _shown_zone != GameState.zone_index:                  # the preview fades out, swaps and fades back in
		_preview_alpha.target = 0.0
		if _preview_alpha.value < 0.08:
			_shown_zone = GameState.zone_index
	else:
		_preview_alpha.target = 1.0
	_preview_alpha.update(dt)


func mouse_pressed(_p: Vector2) -> void:
	_detect()
	_pressed = _hover.duplicate()


func mouse_released(_p: Vector2) -> void:
	_detect()
	var p := _pressed
	_pressed = {}
	if p.is_empty() or p.get("zone") != _hover.get("zone") or p.get("i", -1) != _hover.get("i", -1):
		return
	match p["zone"]:
		"back":
			app.switch_to("save_select")
		"link":
			app.switch_to(["party", "talents", "equip", "shop"][p["i"]])
		"row":
			GameState.zone_index = p["i"]
		"enter":
			app.start_battle()


func key_pressed(key: int) -> void:
	match key:
		KEY_ESCAPE:
			app.switch_to("save_select")
		KEY_UP:
			GameState.zone_index = maxi(0, GameState.zone_index - 1)
		KEY_DOWN:
			GameState.zone_index = mini(GameState.unlocked_count() - 1, GameState.zone_index + 1)
		KEY_ENTER, KEY_KP_ENTER:
			app.start_battle()


## "FIGHT 3 OF 6" (the next fight out of the zone's total), or "CLEARED" once all of them are won.
func _progress_text(i: int) -> String:
	if GameState.zone_complete(i):
		return "CLEARED (%d fights)" % int(GameState.ZONES[i]["fights"])
	return "FIGHT %d OF %d" % [GameState.fight_number(i), int(GameState.ZONES[i]["fights"])]


func _is_pressed(zone: String, i: int = -1) -> bool:
	return not _pressed.is_empty() and _pressed.get("zone") == zone and (i < 0 or _pressed.get("i", -1) == i) and _hover.get("zone") == zone


func draw_scene() -> void:
	C.top_bar(self, "", _is_pressed("back"))
	for i in LINKS.size():
		var rr: Rect2 = _link_rects[i]
		C.text(self, LINKS[i], rr.position.x, rr.position.y, 16, C.BLACK if _is_pressed("link", i) else C.WHITE)
	var zone: Dictionary = GameState.ZONES[GameState.zone_index]
	C.text_right(self, zone["name"], C.VW - 20.0 - 90.0, floorf((C.TOP_BAR_H - C.text_h(16)) / 2.0), 16, C.RED)
	var gold := str(int(GameState.data["gold"]))
	C.text_right(self, gold, C.VW - 20.0, floorf((C.TOP_BAR_H - C.text_h(16)) / 2.0), 16, C.WHITE)
	C.coin(self, C.VW - 20.0 - C.text_w(gold, 16) - 10.0, floorf(C.TOP_BAR_H / 2.0), 7.0)

	# the zone list: a white bar springs to the chosen row
	var bar_y: float = ROW_Y + _sel.value * (ROW_H + ROW_GAP)
	draw_rect(Rect2(ROW_X, bar_y, ROW_W, ROW_H), C.WHITE)
	for i in GameState.unlocked_count():
		var r := _row_rect(i)
		var on: float = clampf(1.0 - absf(_sel.value - float(i)), 0.0, 1.0)
		if on < 0.5:
			C.outline(self, r, C.RED, 2.0)
		C.text(self, GameState.ZONES[i]["name"], r.position.x + 12.0, r.position.y + 6.0, 16, C.BLACK if on > 0.5 else C.WHITE)
		C.text(self, _progress_text(i), r.position.x + 12.0, r.position.y + 24.0, 13, C.BLACK if on > 0.5 else C.RED)

	# the preview of the chosen zone
	var tex := C.texture("res://assets/ui/zone_%s.png" % GameState.ZONES[_shown_zone]["id"])
	draw_rect(PREVIEW, C.BLACK)
	if tex != null:
		draw_texture_rect(tex, PREVIEW, false, Color(1, 1, 1, clampf(_preview_alpha.value, 0.0, 1.0)))
	C.outline(self, PREVIEW, C.WHITE, 2.0)
	C.text(self, zone["name"], PREVIEW.position.x, PREVIEW.end.y + 14.0, 20, C.RED)
	C.text(self, String(zone["blurb"]), PREVIEW.position.x, PREVIEW.end.y + 42.0, 13, C.WHITE)
	C.text(self, _progress_text(GameState.zone_index), PREVIEW.position.x, PREVIEW.end.y + 60.0, 13, C.RED)

	# ENTER
	var pressed := _is_pressed("enter")
	draw_rect(ENTER_RECT, C.WHITE if pressed else C.RED)
	C.text_centered(self, "ENTER", ENTER_RECT, 16, C.BLACK if pressed else C.WHITE)

	# what the last battle gave
	if not GameState.last_result.is_empty():
		var res: Dictionary = GameState.last_result
		C.text(self, "LAST BATTLE", 640.0, 62.0, 13, C.RED)
		C.text(self, "+%d gold" % int(res["gold"]), 640.0, 82.0, 13, C.GOLD)
		var y := 100.0
		for x in res["xp"]:
			C.text(self, "%s +%d XP" % [C.title_case(x["name"]), int(x["gained"])], 640.0, y, 13, C.WHITE)
			y += 16.0
			if int(x["levelUps"]) > 0:
				C.text(self, "LEVEL UP: Lv %d" % int(x["level"]), 640.0, y, 13, C.RED)
				y += 16.0

	_box.draw(self, _is_pressed("back") or _is_pressed("link") or _is_pressed("row") or _is_pressed("enter"))
	C.back_button(self, _is_pressed("back"))
