extends Control
## Base class of a menu screen: an 800x450 canvas (the 2D game's virtual resolution; the app scales it to the window) with the 2D screens'
## lifecycle: enter(args), update(dt), draw_scene(), mouse_pressed / mouse_released (virtual coordinates), key_pressed, wheel.
## Everything that animates uses SmoothValue / SmoothRect (UI_ANIMATION.md).

const C := preload("res://menus/menu_common.gd")
const GameState := preload("res://menus/game_state.gd")

var app                                  # the MenuApp (switch_to, start_battle)
var mouse := Vector2(-100, -100)         # the mouse in virtual (800x450) coordinates
var mouse_down := false
var _overlay: Control


func _init() -> void:
	size = Vector2(C.VW, C.VH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func enter(_args: Dictionary = {}) -> void:
	pass


func update(_dt: float) -> void:
	pass


func draw_scene() -> void:
	pass


func mouse_pressed(_p: Vector2) -> void:
	pass


func mouse_released(_p: Vector2) -> void:
	pass


func key_pressed(_key: int) -> void:
	pass


func wheel(_dy: float) -> void:
	pass


func exit() -> void:
	pass


## Popup text (tooltips) is drawn here, on a control added AFTER everything the screen draws (including child controls such as the talent ladder),
## so it is always on top. `c` is that overlay control.
func draw_overlay(_c: CanvasItem) -> void:
	pass


func attach_overlay() -> void:
	_overlay = Control.new()
	_overlay.size = Vector2(C.VW, C.VH)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.draw.connect(func(): draw_overlay(_overlay))
	add_child(_overlay)


func _process(delta: float) -> void:
	update(delta)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, C.VW, C.VH), C.BLACK)
	draw_scene()
