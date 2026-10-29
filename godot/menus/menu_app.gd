extends Node
## The menu application (main scene): holds the current screen on an 800x450 canvas scaled to the window, forwards the mouse and keys,
## fades between screens (one SmoothValue for the black overlay, as the 2D game's transition), and draws the game's own hand cursor.
## Screens: title -> save_select -> stage_select -> party / equip / talents / shop -> battle (view/sandbox_battle.tscn) -> back to stage_select.

const C := preload("res://menus/menu_common.gd")
const GameState := preload("res://menus/game_state.gd")
const SCREENS := {
	"title": "res://menus/title_screen.gd",
	"save_select": "res://menus/save_select_screen.gd",
	"stage_select": "res://menus/stage_select_screen.gd",
	"party": "res://menus/party_screen.gd",
	"equip": "res://menus/equip_screen.gd",
	"shop": "res://menus/shop_screen.gd",
	"talents": "res://menus/talents_screen.gd",
}
const SCALE := 1280.0 / 800.0
const USE_CRT := false

## Set by the battle before it returns here, or by --screen=<name>.
static var next_screen := "title"

var screen                                   # the current MenuScreen
var screen_name := ""
var _layer: CanvasLayer
var _fade := SmoothValue.new(1.0, 23.0)      # black overlay alpha: 1 -> 0 on entering a screen, 0 -> 1 on leaving
var _pending := {}
var _cursor: Control
var _shot := ""


func _ready() -> void:
	GameState.ensure()
	if not USE_CRT and get_node_or_null("/root/flowerwall_crt") != null:
		get_node("/root/flowerwall_crt").queue_free()            # the CRT is off for now (Director); set USE_CRT to bring it back
	_layer = CanvasLayer.new()
	_layer.scale = Vector2(SCALE, SCALE)
	add_child(_layer)
	var top := CanvasLayer.new()                    # the cursor and the fade live on their own layer above every screen
	top.layer = 100
	top.scale = Vector2(SCALE, SCALE)
	add_child(top)
	_cursor = Control.new()
	_cursor.size = Vector2(C.VW, C.VH)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.draw.connect(_draw_overlay)
	top.add_child(_cursor)
	var clear := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)           # hide the system cursor without capturing the mouse
	Input.set_custom_mouse_cursor(clear, Input.CURSOR_ARROW)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--screen="):
			next_screen = a.substr(9)
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		if a.begins_with("--mouse="):                       # dev: put the mouse at virtual x,y (to shoot a tooltip)
			var xy := a.substr(8).split(",")
			get_viewport().warp_mouse(Vector2(float(xy[0]), float(xy[1])) * SCALE)
		if a.begins_with("--zone="):
			GameState.zone_index = int(a.substr(7))
	if next_screen == "battle":                       # dev: straight into a battle (--zone=N); --shot=name is then the battle's
		start_battle.call_deferred()
		return
	_open(next_screen, {})
	_fade.snap(0.0 if _shot != "" else 1.0)
	_fade.target = 0.0
	if _shot != "":
		_take_shot.call_deferred()


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


## Fade to black, then open `name`.
func switch_to(name: String, args: Dictionary = {}) -> void:
	_pending = {"name": name, "args": args}
	_fade.target = 1.0


func start_battle() -> void:
	GameState.write_save()
	GameState.from_menu = true
	get_tree().change_scene_to_file("res://view/sandbox_battle.tscn")


func _open(name: String, args: Dictionary) -> void:
	if screen != null:
		screen.exit()
		screen.queue_free()
	screen_name = name
	screen = load(SCREENS[name]).new()
	screen.app = self
	_layer.add_child(screen)
	screen.enter(args)
	screen.attach_overlay()                         # popup text goes on top of everything the screen drew
	next_screen = name


func _process(delta: float) -> void:
	_fade.update(delta)
	if not _pending.is_empty() and _fade.value > 0.98:
		var p := _pending
		_pending = {}
		_open(p["name"], p["args"])
		_fade.target = 0.0
	var m := get_viewport().get_mouse_position() / SCALE
	if screen != null:
		screen.mouse = m
		screen.mouse_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_cursor.queue_redraw()


func _input(event: InputEvent) -> void:
	if screen == null or not _pending.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position / SCALE
		screen.mouse = p
		if event.pressed:
			screen.mouse_pressed(p)
		else:
			screen.mouse_released(p)
	elif event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		screen.wheel(-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		screen.key_pressed(event.keycode)


func _draw_overlay() -> void:
	var a: float = clampf(_fade.value, 0.0, 1.0)
	if a > 0.004:
		_cursor.draw_rect(Rect2(0, 0, C.VW, C.VH), Color(0, 0, 0, a))
	var m := get_viewport().get_mouse_position() / SCALE
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var tex := C.texture("res://assets/cursor/tile_%04d.png" % (137 if down else 175))
	if tex != null:
		var hot := Vector2(5, 1) if down else Vector2(3, 1)
		_cursor.draw_texture(tex, Vector2(clampf(floorf(m.x), 0, C.VW - 1), clampf(floorf(m.y), 0, C.VH - 1)) - hot)


func _take_shot() -> void:
	for _i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://shots")
	var path := ProjectSettings.globalize_path("res://shots/menu_%s.png" % _shot)
	get_viewport().get_texture().get_image().save_png(path)
	print("MENU_SHOT ", path)
	get_tree().quit()
