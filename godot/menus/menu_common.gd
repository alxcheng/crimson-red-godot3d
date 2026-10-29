extends RefCounted
## Shared helpers for the menu screens, ported from the 2D game's common.lua: the 800x450 virtual canvas, the Dedicool font,
## text fitting, the red selection box that glides between items (a SmoothRect: UI_ANIMATION.md), the 40 px top bar with BACK,
## hover tooltips. Everything is drawn onto a Control by passing it in: `c.draw_*`.

const VW := 800.0
const VH := 450.0
const TOP_BAR_H := 40.0
const BOX_PAD := 5.0
const BACK_RECT := Rect2(16, 10, 48, 20)
const RED := Color(1, 0, 0)
const WHITE := Color(1, 1, 1)
const BLACK := Color(0, 0, 0)
const GOLD := Color(0.95, 0.78, 0.2)
const TIP_MAX_W := 300.0

static var _font: Font
static var _tex_cache := {}


static func font() -> Font:
	if _font == null:
		# The Dedicool font is not redistributed with this repo; without it the engine's default font is used.
		if ResourceLoader.exists("res://assets/ui/Dedicool.ttf"):
			var ff := FontFile.new()
			ff.load_dynamic_font("res://assets/ui/Dedicool.ttf")
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_font = ff
		else:
			_font = ThemeDB.fallback_font
	return _font


static func text_w(s: String, px: int) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


static func text_h(px: int) -> float:
	return font().get_height(px)


static func title_case(s: String) -> String:
	var out := ""
	var up := true
	for ch in s:
		if ch == " " or ch == "_":
			out += " "
			up = true
		else:
			out += ch.to_upper() if up else ch
			up = false
	return out


## `s` cut to fit `max_w` px, ending in ".." when cut (common.fitText).
static func fit_text(s: String, px: int, max_w: float) -> String:
	if text_w(s, px) <= max_w:
		return s
	while s.length() > 1 and text_w(s + "..", px) > max_w:
		s = s.substr(0, s.length() - 1)
	return s + ".."


## Word-wrap `s` into lines no wider than `max_w`.
static func wrap_text(s: String, px: int, max_w: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var cur := ""
	for word in s.split(" "):
		var trial := word if cur == "" else cur + " " + word
		if text_w(trial, px) > max_w and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	return lines


static func texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


# ------------------------------------------------------------------------------------------ drawing (on a CanvasItem)
static func text(c: CanvasItem, s: String, x: float, y: float, px: int, col: Color = WHITE) -> void:
	c.draw_string(font(), Vector2(floorf(x), floorf(y) + font().get_ascent(px)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


## common.printCentered: centred in the box (shrunk to fit its width).
static func text_centered(c: CanvasItem, s: String, r: Rect2, px: int, col: Color = WHITE) -> void:
	var w := text_w(s, px)
	var sc := minf(1.0, (r.size.x - 4.0) / maxf(1.0, w))
	if sc < 1.0:
		c.draw_set_transform(Vector2(floorf(r.position.x + (r.size.x - w * sc) / 2.0), floorf(r.position.y + (r.size.y - text_h(px) * sc) / 2.0)), 0.0, Vector2(sc, sc))
		text(c, s, 0.0, 0.0, px, col)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		text(c, s, r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y - text_h(px)) / 2.0, px, col)


static func text_right(c: CanvasItem, s: String, right: float, y: float, px: int, col: Color = WHITE) -> void:
	text(c, s, right - text_w(s, px), y, px, col)


static func outline(c: CanvasItem, r: Rect2, col: Color, width: float = 1.0) -> void:
	var hw := width * 0.5
	c.draw_rect(Rect2(r.position + Vector2(hw, hw), r.size - Vector2(width, width)), col, false, width)


static func top_bar(c: CanvasItem, title: String, back_pressed: bool) -> void:
	c.draw_line(Vector2(0, TOP_BAR_H + 0.5), Vector2(VW, TOP_BAR_H + 0.5), WHITE, 1.0)
	back_button(c, back_pressed)
	if title != "":
		text_centered(c, title, Rect2(0, 0, VW, TOP_BAR_H), 20, RED)


static func back_button(c: CanvasItem, pressed: bool) -> void:
	text_centered(c, "BACK", BACK_RECT, 16, BLACK if pressed else RED)


static func back_box() -> Rect2:
	return Rect2(BACK_RECT.position - Vector2(BOX_PAD, BOX_PAD), BACK_RECT.size + Vector2(BOX_PAD, BOX_PAD) * 2.0)


static func padded(r: Rect2) -> Rect2:
	return Rect2(r.position - Vector2(BOX_PAD, BOX_PAD), r.size + Vector2(BOX_PAD, BOX_PAD) * 2.0)


## A small drawn coin (the font has no coin glyph).
static func coin(c: CanvasItem, cx: float, cy: float, r: float) -> void:
	c.draw_circle(Vector2(cx, cy), r, GOLD)
	c.draw_arc(Vector2(cx, cy), r - 2.0, 0.0, TAU, 20, Color(0.7, 0.52, 0.1), 1.0)


## common.drawTooltip: a framed panel next to the hovered rectangle. `lines`: [{text, color, size}].
static func tooltip(c: CanvasItem, lines: Array, anchor: Rect2) -> void:
	if lines.is_empty():
		return
	var pad := 8.0
	var gap := 3.0
	var rows: Array = []
	var tw := 0.0
	var th := pad * 2.0 - gap
	for ln in lines:
		var px: int = int(ln.get("size", 13))
		var col: Color = ln.get("color", WHITE)
		var widest := 0.0
		for piece in wrap_text(String(ln["text"]), px, TIP_MAX_W):
			rows.append({"text": piece, "px": px, "color": col})
			th += text_h(px) + gap
			widest = maxf(widest, text_w(piece, px))
		tw = maxf(tw, widest)
	tw += pad * 2.0
	var tx := floorf(anchor.position.x + anchor.size.x / 2.0 - tw / 2.0)
	var ty := anchor.position.y + anchor.size.y + 8.0
	if ty + th > VH - 6.0:
		ty = anchor.position.y - th - 8.0
	tx = maxf(6.0, minf(tx, VW - 6.0 - tw))
	ty = maxf(6.0, ty)
	c.draw_rect(Rect2(tx, ty, tw, th), BLACK)
	outline(c, Rect2(tx, ty, tw, th), RED, 1.0)
	var ly := ty + pad
	for r in rows:
		text(c, r["text"], tx + pad, ly, r["px"], r["color"])
		ly += text_h(r["px"]) + gap


## Draw a texture fitted into a square cell (class portraits and ability icons).
static func icon(c: CanvasItem, tex: Texture2D, x: float, y: float, size: float, alpha: float = 1.0) -> void:
	if tex == null:
		return
	var sc := minf(size / tex.get_width(), size / tex.get_height())
	var w := tex.get_width() * sc
	var h := tex.get_height() * sc
	c.draw_texture_rect(tex, Rect2(x + (size - w) / 2.0, y + (size - h) / 2.0, w, h), false, Color(1, 1, 1, alpha))


# ------------------------------------------------------------------------------------------ the red selection box
class RedBox:
	var rect := SmoothRect.new(Rect2(), 14.0)       # common.BOX_SPEED 14
	var shown := false
	var _target := Rect2()

	func init_at(r: Rect2) -> void:
		rect.snap(r)
		_target = r
		shown = true

	func set_target(r: Rect2) -> void:
		if shown and _target == r:
			return
		_target = r
		rect.target = r
		if not shown:
			rect.snap(r)                        # snap on the first hover so it does not fly in from (0,0)
			shown = true

	func update(dt: float) -> void:
		if shown:
			rect.update(dt)

	## Red outline normally, white fill while pressed.
	func draw(c: CanvasItem, pressed: bool) -> void:
		if not shown:
			return
		var r: Rect2 = rect.value
		if pressed:
			c.draw_rect(r, Color.WHITE)
		else:
			var hw := 1.0
			c.draw_rect(Rect2(r.position + Vector2(hw, hw), r.size - Vector2(2.0 * hw, 2.0 * hw)), Color.RED, false, 2.0)
