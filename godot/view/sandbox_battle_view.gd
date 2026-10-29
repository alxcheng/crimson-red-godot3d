extends Node3D
## SANDBOX BATTLE: the dungeon stage, the dimetric camera, 4 heroes vs three waves, driven by the real movement
## stack (sim/sandbox_battle.gd). The 2D game's controls: keys 1-4 select a hero; ONE left click orders the selected
## hero, onto an enemy if one is under the cursor (attack), otherwise a move to that spot; SPACE pauses.
## Abilities: Q W E (R unused) cast the selected hero's actives from the 2D data (Hamstring, Sunder Armor, Challenging
## Shout), paid from the shared resource bar at the moment of the press. Selection bases: green under heroes, red under
## enemies (hover, and the enemy the selected hero is fighting).
## Extras for tuning: BACKSPACE restarts, K / J / H spawn a skeleton / goblin / witch at the cursor, F debug overlay (radii, paths,
## goals), [ and ] slow down / speed up time.
##
## Run: ./play_sandbox   [--shot=name --t=12 --debug --select=1]
##   --shot=name  fast-forward --t seconds, save shots/sandbox_<name>.png and quit (for checking)
##   --zoom=1.0 --focus=x,z  camera framing (zoom < 1 is closer); --pitch / --yaw as in ./view_stage

const Sandbox := preload("res://sim/sandbox_battle.gd")
const StageScene := preload("res://view/stage_scene.gd")
const UnitView := preload("res://view/unit_view.gd")
const Picking := preload("res://view/picking.gd")
const OrderLine := preload("res://view/order_line.gd")
## The limited-palette experiment (ui/pixel_art.gdshader). Roll back: set this to false (P toggles it live).
const USE_PALETTE := false
## The Flowerwall CRT (addons/flowerwall_crt) is OFF for now (Director). Set to true to bring it back; nothing else changes.
const USE_CRT := false
const LOGICAL_W := 960.0           # the logical pixel grid is 960x540 (was 640x360: the outline looked grainy)
const GameData := preload("res://sim/game_data.gd")
const GameState := preload("res://menus/game_state.gd")
const MenuApp := preload("res://menus/menu_app.gd")
const Blood := preload("res://view/blood.gd")
const SlashFx := preload("res://view/slash_fx.gd")
const HealFx := preload("res://view/heal_fx.gd")
const BattleHud := preload("res://view/battle_hud.gd")
const MoveMarker := preload("res://view/move_marker.gd")
const GREEN := Color(0.15, 1.0, 0.3)      # the selection base of a hero (Director: green for characters, red for enemies)
const RED := Color(1.0, 0.1, 0.1)
const TIME_SCALES := [0.25, 0.5, 1.0, 1.5, 2.0]

var battle
var stage
var views := {}
var paused := false
var accum := 0.0
var time_scale_i := 2
var selected_index := 0
var hover_id := -1
var debug_on := false
var show_order_line := false      # the order line / path trails are hidden (Director); L brings them back for tuning
var _ui: CanvasLayer
var _hud
var _blood
var _mirror_view
var _mirror_proxy
var _wiz_preset := -1
var _last_hit_shake := -1
var _slow_anim := 1.0
var _time_scale := SmoothValue.new(1.0, 16.0)     # the game's speed: an ability press slows it to a stop (and back)
var _slow_hold := 0.0
var _aim: Dictionary = {}                        # while an aimed ability waits for its target: {slot, kind, hero, name, radius}
var _aim_ring: MeshInstance3D
var _proj_nodes := {}                            # projectile id -> MeshInstance3D (taken from _proj_pool)
var _heal_pool: Array = []                       # effect POOLS: built once at start so nothing is allocated or compiled mid-fight
var _slash_pool: Array = []
var _ring_pool: Array = []
var _proj_pool: Array = []
var _text_pool: Array = []
const PROJECTILE_COLORS := {"fire": Color(1.0, 0.62, 0.12), "frost": Color(0.6, 0.88, 1.0), "purple": Color(0.72, 0.3, 1.0)}
const SLOW_HOLD := 0.45                          # seconds the world stays stopped after an ability that needs no aim
var _perf := "--perf" in OS.get_cmdline_user_args()    # dev: print fps / draw calls after 6 s and quit
var _perf_frames := 0
var _perf_time := 0.0
var _perf_worst := 0.0
var _autoplay := "--autoplay" in OS.get_cmdline_user_args()   # dev: a stand-in player (idle heroes get clicked onto the nearest enemy / the most hurt ally)
var _autoplay_t := 0.0
var _perf_sim_us := 0
var _perf_ticks := 0
var _perf_view_us := 0
var _pixel_mat: ShaderMaterial
var _pixel_layer: CanvasLayer
var _palette_on := USE_PALETTE
var _dying_markers: Array = []
var _markers := {}                 # hero id -> MoveMarker (one per hero; a new order on that hero removes it)
var _rings := {}                   # "sel" / "hover" / "tgt" -> {mesh, mat, alpha, scale, color}
var _order_line
var _effects: Array = []           # expanding area rings
var _texts: Array = []
var _debug_mesh: MeshInstance3D
var _shot_name := ""


## The stages: the original dungeon plus the five zones of the 2D map (blender/build_zones.py). `--stage=<name>` picks one; N cycles.
const STAGES := ["dungeon", "black_forest", "cold_wastes", "wetcaves", "waxen_desert", "castle_crimson"]
static var _stage_name := ""


func _stage_path(file: String) -> String:
	var name := _stage_name if _stage_name != "" else _arg("stage", "dungeon")
	if GameState.from_menu:                                   # started from the stage-select screen: its zone (or the dungeon for the tutorial)
		name = GameState.ZONES[GameState.zone_index]["id"] if GameState.zone_index >= 0 else "dungeon"
	return "res://models/stage/%s" % file if name == "dungeon" else "res://models/stage/%s/%s" % [name, file]


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return default


func _ready() -> void:
	_shot_name = _arg("shot", "")
	debug_on = "--debug" in OS.get_cmdline_user_args()
	selected_index = int(_arg("select", "1")) - 1
	stage = StageScene.new()
	add_child(stage)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_stage_path("stage.json")))
	layout["_glb"] = _stage_path("stage.glb")
	var focus := Vector2.INF
	var fa := _arg("focus", "").split(",")
	if fa.size() == 2:
		focus = Vector2(float(fa[0]), float(fa[1]))
	stage.setup(layout, float(_arg("yaw", "-1")), float(_arg("pitch", "-1")), float(_arg("zoom", "0.75")), focus)
	_build_ui()
	if not USE_CRT and get_node_or_null("/root/flowerwall_crt") != null:
		get_node("/root/flowerwall_crt").queue_free()
	_build_low_res()
	_build_pixel_pass()
	_build_rings()
	_build_pools()
	_order_line = OrderLine.new()
	add_child(_order_line)
	_blood = Blood.new()
	add_child(_blood)
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.mesh = ImmediateMesh.new()
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.no_depth_test = true
	_debug_mesh.material_override = dm
	add_child(_debug_mesh)
	_restart()
	var fx := OS.get_cmdline_user_args()                   # dev: bisect the screen effects' cost (with --perf)
	if "--nocrt" in fx and get_node_or_null("/root/flowerwall_crt") != null:
		get_node("/root/flowerwall_crt").queue_free()
	if "--nopixel" in fx:
		_pixel_layer.queue_free()
	if "--nooutline" in fx:
		for vw in views.values():
			for mesh in vw.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).material_overlay = null
	if "--nostage" in fx:
		for n in stage.get_children():
			if n is Node3D and not n is Camera3D and not n is Light3D:
				n.visible = false
	if "--nohud" in fx:
		_hud.visible = false
	if "--nolights" in fx:
		for l in stage.find_children("*", "OmniLight3D", true, false):
			l.visible = false
	if _arg("wiz", "") != "":                              # dev: start with a Wizard build, e.g. --wiz=pyro | cryo | mirror | tele
		var wb: Dictionary = {"pyro": {"1": "explosion", "10": "ice_block", "20": "blizzard", "25": "pyromancer"}, "cryo": {"1": "explosion", "10": "teleport", "20": "blizzard", "25": "cryomancer"},
				"mirror": {"1": "explosion", "10": "ice_block", "20": "mirror_image"}, "tele": {"1": "iridescent_bolt", "10": "teleport", "20": "blizzard"}}.get(_arg("wiz", ""), {})
		for h in battle.heroes():
			if h.ranged and not h.heals and not wb.is_empty():
				battle.set_wizard_build(h, wb)
	if _arg("hurt", "") != "":                             # dev: start the heroes at this fraction of their health (try the Cleric)
		for h in battle.heroes():
			h.hp = h.max_hp * float(_arg("hurt", "0.5"))
	if _arg("spawn", "") != "":
		battle.spawn(_arg("spawn", ""), Vector2(-3.0, 1.0))
	if _shot_name != "":
		_fast_forward_and_shoot.call_deferred()


## The party the player built in the menus: classes in party order, gear from the equipped items' 3D models, the Wizard's skill-tree build, the Knight's
## ability picks, and health from hero_stats (the damage numbers are still the sandbox's placeholders).
func _campaign_party() -> Array:
	var out: Array = []
	for name in GameState.party():
		if not Sandbox.DEFAULT_PARTY.any(func(d): return d["kind"] == name):
			continue
		var eq: Dictionary = GameState.record(name).get("equipped", {})
		var weapon := GameState.model_for(GameState.item_of(eq.get("weapon")))
		var armor_inst: Dictionary = GameState.item_of(eq.get("armor"))
		var armor := GameState.model_for(armor_inst)
		var head := GameState.head_for(armor_inst)
		var spec := {"kind": name, "weapon_speed": GameState.weapon_speed(GameState.item_of(eq.get("weapon"))), "label": GameState.C_title(name), "hp": float(GameState.hero_stats(name).get("maxHP", 0))}
		if name == "wizard":
			var starter: bool = armor == "armor_cloak" or armor == ""          # the starting Cotton Cloak keeps the Wizard's blue robe and hat
			spec["gear"] = ["hat_wizard_blue", "armor_wizard_blue"] if starter else [head, armor]
			spec["weapon"] = weapon if weapon != "" else "staff_oak"
			spec["build"] = GameState.wizard_build()
		else:
			spec["gear"] = [head if head != "" else "helm_iron", armor if armor != "" else "armor_scale_mail"]
			spec["weapon"] = weapon if weapon != "" else "sword_long"
			spec["abilities"] = GameState.active_abilities(name)
		out.append(spec)
	return out


## Leave the battle for the menus: a won battle pays its rewards first (gold, XP); RETREAT and defeat pay nothing.
func _leave(won: bool) -> void:
	if won:
		var survivors: Array = []
		for h in battle.heroes():
			if h.state != Sandbox.State.DEAD:
				survivors.append(h.kind)
		GameState.on_encounter_won(survivors)
	GameState.write_save()
	MenuApp.next_screen = "stage_select" if GameState.zone_index >= 0 else "title"
	get_tree().change_scene_to_file("res://menus/menu_app.tscn")


func _on_retreat() -> void:
	if GameState.from_menu:
		_leave(false)
	else:
		_restart()


func _restart() -> void:
	if _blood != null:
		_blood.clear()
	for m in _markers.values():
		m.queue_free()
	_markers.clear()
	for v in views.values():
		v.queue_free()
	views.clear()
	battle = Sandbox.new()
	battle.spawn_party(_campaign_party() if GameState.from_menu else [])
	_hud.clear_end()
	accum = 0.0
	_consume_events()


# ------------------------------------------------------------------------------------------- UI
func _build_ui() -> void:
	_ui = CanvasLayer.new()                    # floating combat text, in window (1280x720) pixels
	add_child(_ui)
	var layer := CanvasLayer.new()             # the 2D game's HUD on its own 800x450 canvas, scaled up
	layer.layer = 5
	layer.scale = Vector2(BattleHud.SCALE, BattleHud.SCALE)
	add_child(layer)
	_hud = BattleHud.new()
	layer.add_child(_hud)
	_hud.bind(self)
	_hud.pause_toggled.connect(_toggle_pause)
	_hud.retreat.connect(_on_retreat)
	# the HUD draws the game's own cursor: hide the system one with a clear image (never capture the mouse)
	var clear := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	Input.set_custom_mouse_cursor(clear, Input.CURSOR_ARROW)


## The 3D scene is rendered at the 960x540 logical grid (nearest-neighbour upscale), so units, outlines and the pixel grid all
## share one pixel size and the 3D fragment work is a quarter of the window's. The HUD, pixel pass and CRT stay full resolution.
func _build_low_res() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
	_update_low_res()
	vp.size_changed.connect(_update_low_res)


func _update_low_res() -> void:
	var vp := get_viewport()
	var w := float(vp.size.x)
	vp.scaling_3d_scale = clampf(LOGICAL_W / maxf(w, 1.0), 0.25, 1.0)


## Pixel-art pass over the 3D scene and the floating text (the HUD, layer 5, stays crisp); the CRT addon sits above everything.
func _build_pixel_pass() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_pixel_layer = layer
	var rect := ColorRect.new()
	rect.size = Vector2(1280, 720)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/pixel_art.gdshader")
	rect.material = mat
	layer.add_child(rect)
	_pixel_mat = mat
	mat.set_shader_parameter("use_palette", USE_PALETTE)
	var lut: Array = PixelPalette.build_lut()
	mat.set_shader_parameter("lut_a", lut[0])
	mat.set_shader_parameter("lut_b", lut[1])


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func _toggle_pause() -> void:
	paused = not paused


func _build_rings() -> void:
	for key in ["sel", "hover", "tgt"]:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.93
		torus.outer_radius = 1.0
		torus.rings = 24
		torus.ring_segments = 6
		mi.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0, 0, 0, 0)
		mat.no_depth_test = false
		mi.material_override = mat
		mi.scale = Vector3(0.1, 0.05, 0.1)
		add_child(mi)
		_rings[key] = {"mesh": mi, "mat": mat, "alpha": SmoothValue.new(0.0, 14.0), "scale": SmoothValue.new(0.6, 16.0, 0.55),
				"color": SmoothColor.new(GREEN, 16.0)}
	# the aiming ring: follows the cursor while an area ability waits for its spot
	_aim_ring = MeshInstance3D.new()
	var at := TorusMesh.new()
	at.inner_radius = 0.97
	at.outer_radius = 1.0
	at.rings = 48
	at.ring_segments = 4
	_aim_ring.mesh = at
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.albedo_color = Color(1, 1, 1, 0.95)
	_aim_ring.material_override = am
	_aim_ring.visible = false
	add_child(_aim_ring)


# ------------------------------------------------------------------------------------- effect pools
## Every effect the fight spawns repeatedly (heal light, fireballs, area rings, the Knight's slash, floating numbers) is built ONCE here and
## then only switched on and off. Creating nodes, materials and shaders mid-fight was what made the first fireball / heal hitch.
## The shaders are shared (compiled once); `_prewarm` draws every pooled effect once, hidden under the floor, so the GPU pipelines are
## built while the battle is loading instead of when the first heal lands.
func _build_pools() -> void:
	for i in 6:
		var h := HealFx.new()
		add_child(h)
		_heal_pool.append(h)
	for i in 2:
		var sl := SlashFx.new()
		add_child(sl)
		_slash_pool.append(sl)
	for i in 8:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.96
		torus.outer_radius = 1.0
		torus.rings = 40
		torus.ring_segments = 4
		mi.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_ring_pool.append({"mesh": mi, "mat": mat, "busy": false})
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 8
	sphere.rings = 4
	for i in 10:
		var ball := MeshInstance3D.new()
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = Color(1.0, 0.62, 0.12)
		ball.material_override = pm
		ball.mesh = sphere
		ball.visible = false
		add_child(ball)
		_proj_pool.append(ball)
	for i in 32:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 4)
		l.visible = false
		_ui.add_child(l)
		_text_pool.append(l)
	_prewarm()


func _prewarm() -> void:
	var under := Vector3(0.0, -4.0, 0.0)                    # below the floor: drawn (so the pipelines compile) but never seen
	for h in _heal_pool:
		h.play(under)
	for sl in _slash_pool:
		sl.play(under, 1.0)
	for r in _ring_pool:
		r["mesh"].position = under
		r["mesh"].visible = true
	for ball in _proj_pool:
		ball.position = under
		ball.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for h in _heal_pool:
		h.visible = false
		h.set_process(false)
	for sl in _slash_pool:
		sl.visible = false
		sl.set_process(false)
	for r in _ring_pool:
		r["mesh"].visible = false
	for ball in _proj_pool:
		ball.visible = false


# ------------------------------------------------------------------------------------- the loop
func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	if _autoplay:
		_autoplay_t += delta
		if _autoplay_t > 1.0:
			_autoplay_t = 0.0
			_autoplay_step()
	if _perf:
		_perf_frames += 1
		_perf_time += delta
		if _perf_time > 2.0:                          # skip the start-up (shader compile, scene load)
			_perf_worst = maxf(_perf_worst, delta)
		if _perf_time > 6.0:
			print("PERF win=%s fps=%.1f avg_frame=%.2f ms worst=%.1f ms draw_calls=%d objects=%d primitives=%d units=%d process=%.2f ms" % [
				DisplayServer.window_get_size(), _perf_frames / _perf_time, 1000.0 * _perf_time / _perf_frames, _perf_worst * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), battle.units.size(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			print("PERF script per frame: view _process=%.2f ms (sim part %.2f ms, %.2f ticks/frame, %.2f ms/tick)" % [
				_perf_view_us / 1000.0 / _perf_frames, _perf_sim_us / 1000.0 / _perf_frames, float(_perf_ticks) / _perf_frames, _perf_sim_us / 1000.0 / maxf(_perf_ticks, 1)])
			get_tree().quit()
	# the game's speed: slow to a stop on an ability press; it stays stopped while an aimed ability waits for its target
	var want := 1.0
	if not _aim.is_empty():
		want = 0.0
	elif _slow_hold > 0.0:
		_slow_hold -= delta
		want = 0.0
	_time_scale.target = want
	_time_scale.update(delta)
	var game_speed: float = clampf(_time_scale.value, 0.0, 1.0)
	if want == 0.0 and game_speed < 0.015:
		game_speed = 0.0
	if not paused:
		accum += minf(delta, 0.1) * TIME_SCALES[time_scale_i] * game_speed
		while accum >= Sandbox.DT:
			accum -= Sandbox.DT
			var _ts := Time.get_ticks_usec()
			battle.tick()
			_perf_sim_us += Time.get_ticks_usec() - _ts
			_perf_ticks += 1
			_consume_events()
	if not paused:
		_blood.update(delta * game_speed)
	_slow_anim = game_speed
	_update_aim()
	_update_projectiles()
	_update_mirror()
	for vid in views:
		views[vid].outline_ice = battle.units.has(vid) and battle.units[vid].statuses.has("INVULN")
	_update_hover()
	_sync_views(delta)
	_update_markers(delta)
	_update_rings(delta)
	_update_texts(delta)
	_update_effects(delta)
	var hs_now: Array = battle.heroes()
	_order_line.visible = show_order_line
	_order_line.update_line(hs_now[selected_index] if selected_index < hs_now.size() else null, battle, delta)
	if debug_on:
		_draw_debug()
	else:
		(_debug_mesh.mesh as ImmediateMesh).clear_surfaces()
	_perf_view_us += Time.get_ticks_usec() - _t0


func _autoplay_step() -> void:
	for h in battle.heroes():
		if h.state == Sandbox.State.DEAD or (h.target >= 0 and battle.alive(h.target)):
			continue
		var best := -1
		var best_key := INF
		for id in battle.units:
			var o = battle.units[id]
			if o.state == Sandbox.State.DEAD or (o.team == h.team) != h.heals:
				continue
			var key: float = (o.hp / o.max_hp) if h.heals else h.agent.pos.distance_to(o.agent.pos)
			if key < best_key:
				best_key = key
				best = id
		if best >= 0:
			battle.command_attack(h.id, best)


func _consume_events() -> void:
	for e in battle.take_events():
		match e["type"]:
			"spawn":
				_add_unit_view(battle.units[e["id"]])
			"hit":
				var target = battle.units.get(e["target"])
				var attacker = battle.units.get(e["id"])
				if e.get("ability", false) and Engine.get_process_frames() != _last_hit_shake:
					_last_hit_shake = Engine.get_process_frames()          # one shake per frame, however many enemies an area hits
					stage.shake.kick(3.0)                                  # screen shake when an ABILITY hits (2D useVFX); normal attacks do not shake
				if target != null and attacker != null:
					_blood.splatter(attacker.agent.pos, target.agent.pos, Picking.height_of(target.model) * 0.5)
				if target != null:
					_add_text(target.agent.pos, str(int(round(e["dmg"]))), Color(1, 1, 1) if target.team == 1 else Color(1, 0, 0))
			"remove":
				if views.has(e["id"]):
					views[e["id"]].queue_free()
					views.erase(e["id"])
			"cast":
				stage.shake.kick(2.6)                                      # screen shake on ability use (not on normal attacks)
				var caster = battle.units.get(e["id"])
				if caster != null:
					_add_text(caster.agent.pos, _pretty(String(e["skill"])).to_upper() + "!", Color(1, 1, 1), 1.9)
			"press":
				var hs: Array = battle.heroes()
				if selected_index < hs.size() and hs[selected_index].id == e["id"]:
					for k in hs[selected_index].skills.size():
						if hs[selected_index].skills[k]["name"] == e["skill"]:
							_hud.press_skill(k)
			"heal":
				var healed = battle.units.get(e["target"])
				if healed != null:
					for fx in _heal_pool:
						if not fx.busy():
							fx.play(Vector3(healed.agent.pos.x, 0.0, healed.agent.pos.y))
							break
					if views.has(e["target"]):
						views[e["target"]].flash_heal()
					if e["amount"] >= 1.0:
						_add_text(healed.agent.pos, "+%d" % int(round(e["amount"])), Color(1.0, 0.84, 0.28), 2.0)
			"lightning":
				_add_area_effect(e["pos"], e["radius"], "lightning")
			"zone_tick":
				_add_area_effect(e["pos"], e["radius"] * 0.55, "blizzard" if e["element"] == "frost" else "firestorm")
			"dot":
				var dt_unit = battle.units.get(e["id"])
				if dt_unit != null:
					_add_text(dt_unit.agent.pos, str(int(round(e["dmg"]))), Color(1, 0, 0), 1.9)
			"status":
				var who = battle.units.get(e["id"])
				if who != null and e["on"]:
					_add_text(who.agent.pos, "WEAKENED" if e["name"] == "WEAKEN" else "MARKED", Color(1, 0, 0) if e["name"] == "VULNERABILITY" else Color(1, 1, 1), 2.3)
			"area":
				_add_area_effect(e["pos"], e["radius"], e["kind"])
			"victory":
				_hud.show_end("VICTORY", 0.0)
			"defeat":
				_hud.show_end("DEFEAT", BattleHud.DEFEAT_AT)


func _add_unit_view(u) -> void:
	var v := UnitView.new()
	add_child(v)
	v.setup(u)
	views[u.id] = v


func _sync_views(delta: float) -> void:
	for id in views:
		var v = views[id]
		v.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
		if not paused:
			v.slow = _slow_anim
			v.sync(delta)


func _update_effects(delta: float) -> void:
	for e in _effects.duplicate():
		e["age"] += delta
		e["grow"].update(delta)
		e["fade"].update(delta)
		var r: float = maxf(e["grow"].value, 0.05)
		e["mesh"].scale = Vector3(r, 1.0, r)
		var c: Color = e["mat"].albedo_color
		c.a = clampf(e["fade"].value, 0.0, 1.0)
		e["mat"].albedo_color = c
		if e["age"] > 1.6:
			e["mesh"].visible = false
			e["slot"]["busy"] = false
			_effects.erase(e)


# ------------------------------------------------------------------------------------- input
func _pick_at(screen_pos: Vector2) -> int:
	var candidates: Array = []
	for id in battle.units:
		var u = battle.units[id]
		if u.state != Sandbox.State.DEAD:
			candidates.append({"id": id, "pos": u.agent.pos, "radius": u.radius, "height": Picking.height_of(u.model)})
	return Picking.pick(stage.camera, candidates, screen_pos)


func _update_hover() -> void:
	hover_id = _pick_at(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				selected_index = event.keycode - KEY_1
			KEY_SPACE, KEY_ESCAPE:
				if not _aim.is_empty():
					_cancel_aim()
				else:
					_toggle_pause()
			KEY_BACKSPACE:
				_restart()
			KEY_Q, KEY_W, KEY_E:
				_press_skill({KEY_Q: 0, KEY_W: 1, KEY_E: 2}[event.keycode])
			KEY_T:
				_cycle_wizard_build()
			KEY_N:
				var cur: String = _stage_name if _stage_name != "" else _arg("stage", "dungeon")
				_stage_name = STAGES[(maxi(STAGES.find(cur), 0) + 1) % STAGES.size()]
				get_tree().reload_current_scene()
			KEY_P:
				_palette_on = not _palette_on
				_pixel_mat.set_shader_parameter("use_palette", _palette_on)
			KEY_L:
				show_order_line = not show_order_line
			KEY_F:
				debug_on = not debug_on
			KEY_K:
				_spawn_at_mouse("skeleton")
			KEY_J:
				_spawn_at_mouse("goblin")
			KEY_H:
				_spawn_at_mouse("witch")
			KEY_BRACKETLEFT:
				time_scale_i = maxi(0, time_scale_i - 1)
			KEY_BRACKETRIGHT:
				time_scale_i = mini(TIME_SCALES.size() - 1, time_scale_i + 1)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _hud.handle_mouse(event) or not event.pressed or paused:
			return
		if GameState.from_menu and battle.over != "":                # the end screen: a click goes back to the menus
			_leave(battle.over == "victory")
			return
		if not _aim.is_empty():
			_confirm_aim(event.position)
			return
		_order_selected(event.position)


## "SunderArmor" -> "Sunder Armor" (the 2D data names have no spaces)
func _pretty(name: String) -> String:
	var out := ""
	for i in name.length():
		if i > 0 and name[i] == name[i].to_upper() and name[i] != name[i].to_lower():
			out += " "
		out += name[i]
	return out


func _press_skill(slot: int) -> void:
	if not _aim.is_empty():
		_cancel_aim()                                        # the same key (or another) cancels at no cost
		return
	var hs: Array = battle.heroes()
	if selected_index >= hs.size():
		return
	var hero = hs[selected_index]
	if slot >= hero.skills.size():
		return
	var sk: Dictionary = hero.skills[slot]
	var need: String = battle.skill_select(hero.id, slot)
	if need == "none":
		_reject(hero, slot)
		return
	if need == "area" or need == "unit":
		# aimed ability: the world slows to a stop and stays stopped until the player picks (or cancels)
		_aim = {"slot": slot, "kind": need, "hero": hero.id, "name": _pretty(sk["name"]), "radius": float(sk["row"].get("effect", {}).get("rx", 0.0)) / GameData.PX_PER_M, "side": sk["side"]}
		_aim_ring.visible = need == "area"
		_slow_hold = 0.0
		return
	if battle.command_skill(hero.id, slot):
		_slow_hold = SLOW_HOLD                              # slow to a stop for a beat, then back to normal
	else:
		_reject(hero, slot)


func _reject(hero, slot: int) -> void:
	if slot >= hero.skills.size():
		return
	_hud.reject_skill(slot)
	var sk: Dictionary = hero.skills[slot]
	var why := "COOLDOWN" if sk["cd"] > 0.0 else ("NOT ENOUGH RESOURCE" if battle.resource < sk["cost"] else "NO TARGET")
	_add_text(hero.agent.pos, why, Color(1, 0, 0), 2.3)


func _cancel_aim() -> void:
	_aim = {}
	_aim_ring.visible = false
	_slow_hold = 0.0


## The click that picks the aimed ability's target: a ground point (area) or an enemy (unit).
func _confirm_aim(screen_pos: Vector2) -> void:
	var slot: int = _aim["slot"]
	var ok := false
	if _aim["kind"] == "area":
		var g: Vector2 = stage.ground_at(screen_pos)
		if g == Vector2.INF:
			return
		ok = battle.command_skill(_aim["hero"], slot, {"pos": g})
	else:
		var id := _pick_at(screen_pos)
		var want_team := 0 if _aim["side"] == "allies" else 1       # healing / buffs go to allies, the rest to enemies
		if id < 0 or battle.units[id].team != want_team:
			return                                           # nothing to pick yet: keep waiting
		ok = battle.command_skill(_aim["hero"], slot, {"unit": id})
	_aim = {}
	_aim_ring.visible = false
	_slow_hold = 0.12 if ok else 0.0                         # the cast goes off, and the world speeds back up


## Mirror Image (the Wizard's Lv 20 pick): a bright blue copy, visual only. It is not a unit: this draws a second model that follows the Wizard
## diagonally to the lower right and replays its animations (so it appears to attack the same target).
class MirrorAgent:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO


class MirrorProxy:
	var model := "knight"
	var gear: Array = []
	var weapon := ""
	var agent := MirrorAgent.new()
	var heading := 0.0
	var state := 0
	var swing := 0
	var swing_anim := "Attack1"
	var statuses := {}


func _update_mirror() -> void:
	var wiz = null
	for h in battle.heroes():
		if h.ranged and not h.heals and h.state != Sandbox.State.DEAD:
			wiz = h
	var on: bool = wiz != null and wiz.mirror
	if not on:
		if _mirror_view != null:
			_mirror_view.visible = false
		return
	if _mirror_view == null:
		_mirror_proxy = MirrorProxy.new()
		_mirror_proxy.gear = wiz.gear
		_mirror_proxy.weapon = wiz.weapon
		_mirror_view = UnitView.new()
		_mirror_view.ghost = true
		add_child(_mirror_view)
		_mirror_view.setup(_mirror_proxy)
	_mirror_view.visible = true
	var px: MirrorProxy = _mirror_proxy
	px.agent.pos = wiz.agent.pos + Vector2(1.0, 1.0)         # lower right: +x is right, +z is toward the camera
	px.agent.vel = wiz.agent.vel
	px.heading = wiz.heading
	px.state = wiz.state
	px.swing = wiz.swing
	px.swing_anim = wiz.swing_anim
	_mirror_view.slow = _slow_anim
	_mirror_view.sync(get_process_delta_time())


## Dev: T cycles the Wizard's skill-tree presets (data/wizard_talents.json "presets").
func _cycle_wizard_build() -> void:
	var wiz = null
	for h in battle.heroes():
		if h.ranged and not h.heals:
			wiz = h
	if wiz == null:
		return
	var presets: Dictionary = GameData.wizard_talents()["presets"]
	var names: Array = presets.keys()
	_wiz_preset = (_wiz_preset + 1) % names.size()
	battle.set_wizard_build(wiz, presets[names[_wiz_preset]])
	_add_text(wiz.agent.pos, String(names[_wiz_preset]).to_upper(), Color(1, 1, 1), 2.6)


func _update_aim() -> void:
	_hud.aim_text = ("CLICK TO USE %s - ESC TO CANCEL" % String(_aim["name"]).to_upper()) if not _aim.is_empty() else ""
	if _aim.is_empty():
		for id in views:
			views[id].outline_gold = false
		return
	var mp := get_viewport().get_mouse_position()
	if _aim["kind"] == "area":
		var g: Vector2 = stage.ground_at(mp)
		if g != Vector2.INF:
			_aim_ring.position = Vector3(g.x, 0.07, g.y)
			var r: float = _aim["radius"]
			_aim_ring.scale = Vector3(r, 1.0, r)
	# every enemy the ability would hit is framed in red
	for id in views:
		var o = battle.units.get(id)
		if o == null or o.state == Sandbox.State.DEAD:
			continue
		if _aim["side"] == "allies":
			views[id].outline_gold = o.team == 0 and id == hover_id
			continue
		if o.team != 1:
			continue
		if _aim["kind"] == "area":
			var g2: Vector2 = stage.ground_at(mp)
			views[id].outline_red = g2 != Vector2.INF and o.agent.pos.distance_to(g2) - o.radius <= _aim["radius"]
		else:
			views[id].outline_red = id == hover_id


## Fireballs: the sim owns them; this keeps one small glowing ball per live projectile at its position.
func _update_projectiles() -> void:
	var seen := {}
	for pr in battle.projectiles:
		seen[pr["id"]] = true
		if not _proj_nodes.has(pr["id"]):
			var free_ball: MeshInstance3D = null
			for ball in _proj_pool:
				if not ball.visible:
					free_ball = ball
					break
			if free_ball == null:
				continue                                      # the pool is empty: skip drawing this one (the sim still hits)
			(free_ball.material_override as StandardMaterial3D).albedo_color = PROJECTILE_COLORS.get(pr.get("style", "fire"), Color(1.0, 0.62, 0.12))
			free_ball.scale = Vector3.ONE * (1.5 if pr.get("style", "") == "purple" else 1.0)
			free_ball.visible = true
			_proj_nodes[pr["id"]] = free_ball
		_proj_nodes[pr["id"]].position = Vector3(pr["pos"].x, Sandbox.PROJECTILE_HEIGHT, pr["pos"].y)
	for id in _proj_nodes.keys():
		if not seen.has(id):
			_proj_nodes[id].visible = false
			_proj_nodes.erase(id)


func _order_selected(screen_pos: Vector2) -> void:
	var hs: Array = battle.heroes()
	if selected_index >= hs.size():
		return
	var hero = hs[selected_index]
	if hero.state == Sandbox.State.DEAD:
		return
	var clicked := _pick_at(screen_pos)
	if clicked >= 0 and (battle.units[clicked].team == 1) != hero.heals:         # enemies for attackers, allies for the Cleric
		battle.command_attack(hero.id, clicked)
		_clear_marker(hero.id)
		return
	var g: Vector2 = stage.ground_at(screen_pos)
	if g != Vector2.INF:
		battle.command_move(hero.id, g)
		_set_marker(hero)


func _set_marker(hero) -> void:
	_clear_marker(hero.id)
	var m = MoveMarker.new()
	add_child(m)
	m.place(hero.move_point)
	_markers[hero.id] = m


func _clear_marker(id: int) -> void:
	if _markers.has(id):
		_markers[id].dismiss()
		_dying_markers.append(_markers[id])
		_markers.erase(id)


func _update_markers(delta: float) -> void:
	for id in _markers.keys():
		var h = battle.units.get(id)
		if h == null or h.state == Sandbox.State.DEAD or (not h.move_order and _markers[id].age() > 0.2):
			_clear_marker(id)
		else:
			_markers[id].update(delta)
	for m in _dying_markers.duplicate():
		m.update(delta)
		if m.finished():
			m.queue_free()
			_dying_markers.erase(m)


func _spawn_at_mouse(kind: String) -> void:
	var g: Vector2 = stage.ground_at(get_viewport().get_mouse_position())
	if g != Vector2.INF:
		battle.spawn(kind, battle.nav.push_out(g, 0.5))


# ---------------------------------------------------------------------------------- feedback
func _update_rings(delta: float) -> void:
	var hs: Array = battle.heroes()
	var hero = hs[selected_index] if selected_index < hs.size() and hs[selected_index].state != Sandbox.State.DEAD else null
	# the selected hero's base is GREEN; the enemy it is fighting has a RED base
	_ring_follow("sel", hero, GREEN, 0.9, delta)
	var fought = null
	if hero != null and hero.target >= 0 and battle.alive(hero.target) and hero.ordered:
		fought = battle.units[hero.target]
	_ring_follow("tgt", fought, RED, 0.8, delta)
	# hover: green on a hero, red on an enemy: what a click would select / attack
	var hu = battle.units.get(hover_id) if hover_id >= 0 else null
	_ring_follow("hover", hu, (GREEN if hu != null and hu.team == 0 else RED), 0.6, delta)
	# the white outline turns RED on an enemy that is a target: the one the selected hero was ordered onto, or the one a click would hit
	for id in views:
		var o = battle.units.get(id)
		views[id].outline_red = o != null and o.team == 1 and o.state != Sandbox.State.DEAD and ((fought != null and fought.id == id) or id == hover_id)


func _ring_follow(key: String, u, color: Color, alpha: float, delta: float) -> void:
	var r: Dictionary = _rings[key]
	r["alpha"].target = alpha if u != null else 0.0
	r["scale"].target = (u.radius * 1.4) if u != null else r["scale"].target
	if u != null:
		r["color"].target = color
	r["alpha"].update(delta)
	r["scale"].update(delta)
	r["color"].update(delta)
	if u != null:
		r["mesh"].position = Vector3(u.agent.pos.x, 0.05, u.agent.pos.y)
	var s: float = maxf(r["scale"].value, 0.01)
	r["mesh"].scale = Vector3(s, 1.0, s)
	var c: Color = r["color"].value
	c.a = clampf(r["alpha"].value, 0.0, 1.0)
	r["mat"].albedo_color = c
	r["mesh"].visible = c.a > 0.01


func _add_area_effect(pos: Vector2, radius: float, kind: String) -> void:
	if kind == "groupheal":
		return                                                # the heal light on each ally is the effect
	radius = minf(radius, 16.0)                              # TimeStop covers the whole stage: draw a big ring, not an infinite one
	if kind == "sunder":
		for sl in _slash_pool:
			if not sl.busy():
				sl.play(Vector3(pos.x, 0.0, pos.y), radius)
				break
	var slot: Dictionary = {}
	for r in _ring_pool:
		if not r["busy"]:
			slot = r
			break
	if slot.is_empty():
		return                                                # all rings are in use: skip this one rather than allocate
	slot["busy"] = true
	slot["mat"].albedo_color = {"sunder": Color(1, 0.1, 0.1, 0.9), "explosion": Color(1.0, 0.55, 0.1, 0.95), "blizzard": Color(0.6, 0.85, 1.0, 0.95),
			"conflagrate": Color(1.0, 0.45, 0.1, 0.95), "timestop": Color(1, 1, 1, 0.9),
			"frostwave": Color(0.6, 0.88, 1.0, 0.95), "firewave": Color(1.0, 0.4, 0.1, 0.95), "iceblock": Color(0.62, 0.92, 1.0, 0.95),
			"hellfire": Color(1.0, 0.35, 0.1, 0.95), "defend": Color(0.5, 0.7, 1.0, 0.95), "firestorm": Color(1.0, 0.45, 0.1, 0.95), "lightning": Color(1.0, 1.0, 0.65, 0.98),
			"angel": Color(1.0, 0.9, 0.5, 0.95), "shield": Color(1.0, 0.84, 0.28, 0.95), "infuse": Color(1.0, 0.84, 0.28, 0.95)}.get(kind, Color(1, 1, 1, 0.9))
	var mi: MeshInstance3D = slot["mesh"]
	mi.position = Vector3(pos.x, 0.06, pos.y)
	mi.scale = Vector3(0.2, 1, 0.2)
	mi.visible = true
	var grow := SmoothValue.new(0.2, 9.0)
	grow.target = radius
	var fade := SmoothValue.new(0.9, 3.5)
	fade.target = 0.0
	_effects.append({"slot": slot, "mesh": mi, "mat": slot["mat"], "grow": grow, "fade": fade, "age": 0.0})


func _add_text(ground: Vector2, text: String, color: Color, height: float = 1.9) -> void:
	var l: Label = null
	for cand in _text_pool:
		if not cand.visible:
			l = cand
			break
	if l == null:
		return                                                # all 32 labels are busy: drop this number rather than allocate
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.modulate.a = 1.0
	l.visible = true
	var rise := SmoothValue.new(0.0, 5.0)
	rise.target = 46.0
	_texts.append({"label": l, "world": Vector3(ground.x, height, ground.y), "rise": rise, "alpha": SmoothValue.new(1.0, 5.0), "age": 0.0})


func _update_texts(delta: float) -> void:
	for t in _texts.duplicate():
		t["age"] += delta
		t["rise"].update(delta)
		if t["age"] > 0.35:
			t["alpha"].target = 0.0
		t["alpha"].update(delta)
		var sp: Vector2 = stage.camera.unproject_position(t["world"])
		t["label"].position = sp + Vector2(-12, -t["rise"].value)
		t["label"].modulate.a = clampf(t["alpha"].value, 0.0, 1.0)
		if t["age"] > 1.4:
			t["label"].visible = false
			_texts.erase(t)


func _draw_debug() -> void:
	var m := _debug_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	for u in battle.units.values():
		if u.state == Sandbox.State.DEAD:
			continue
		var col := Color(1, 0.2, 0.2) if u.team == 1 else Color(0.3, 1, 0.5)
		_circle(m, u.agent.pos, u.radius, col)
		var a = u.agent
		if a.goal_set and not a.arrived:
			var pts: PackedVector2Array = a.path
			for i in range(maxi(a.path_i - 1, 0), pts.size() - 1):
				_line(m, pts[i], pts[i + 1], Color(1, 1, 0))
			_line(m, a.pos, a.goal, Color(0.4, 0.8, 1))
		_line(m, a.pos, a.pos + Vector2(sin(u.heading), cos(u.heading)) * u.radius * 1.6, Color(1, 1, 1))
	for id in battle.slots:
		var t = battle.units.get(id)
		if t == null or t.state == Sandbox.State.DEAD:
			continue
		for ri in battle.slots[id].rings.size():
			var ring: Dictionary = battle.slots[id].rings[ri]
			for si in ring["count"]:
				if ring["owner"][si] != -1:
					_circle(m, battle.slots[id].position_of(t.agent.pos, ri, si), 0.12, Color(1, 0.6, 0))
	m.surface_end()


func _line(m: ImmediateMesh, a: Vector2, b: Vector2, c: Color) -> void:
	m.surface_set_color(c)
	m.surface_add_vertex(Vector3(a.x, 0.08, a.y))
	m.surface_set_color(c)
	m.surface_add_vertex(Vector3(b.x, 0.08, b.y))


func _circle(m: ImmediateMesh, centre: Vector2, r: float, c: Color) -> void:
	for i in 20:
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 1) / 20.0
		_line(m, centre + Vector2(cos(a0), sin(a0)) * r, centre + Vector2(cos(a1), sin(a1)) * r, c)


# ----------------------------------------------------------------------------------- shots
func _fast_forward_and_shoot() -> void:
	var seconds := float(_arg("t", "10"))
	# scripted input for screenshots: --cast=slot@seconds,...   --move=x,z@seconds   --attack=@seconds (nearest enemy)
	var script: Array = []
	for item in _arg("cast", "").split(",", false):
		var parts := item.split("@")
		script.append({"t": float(parts[1]), "kind": "cast", "slot": int(parts[0])})
	var mv := _arg("move", "")
	if mv != "":
		var mp := mv.split("@")
		var xz := mp[0].split(":")
		script.append({"t": float(mp[1]), "kind": "move", "p": Vector2(float(xz[0]), float(xz[1]))})
	var at := _arg("attack", "")
	if at != "":
		script.append({"t": float(at.trim_prefix("@")), "kind": "attack"})
	for _i in int(seconds / Sandbox.DT):
		for step in script.duplicate():
			if battle.time >= step["t"]:
				script.erase(step)
				var hs: Array = battle.heroes()
				var hero = hs[selected_index]
				match step["kind"]:
					"cast":
						battle.command_skill(hero.id, step["slot"])
					"move":
						battle.command_move(hero.id, step["p"])
						_set_marker(hero)
					"attack":
						var best := -1
						var best_d := INF
						for id in battle.units:
							var o = battle.units[id]
							if o.team == 1 and o.state != Sandbox.State.DEAD and o.agent.pos.distance_to(hero.agent.pos) < best_d:
								best_d = o.agent.pos.distance_to(hero.agent.pos)
								best = id
						if best >= 0:
							battle.command_attack(hero.id, best)
		battle.tick()
		_consume_events()
	for _f in 6:
		await get_tree().process_frame
		_sync_views(0.016)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://shots")
	var path := ProjectSettings.globalize_path("res://shots/sandbox_%s.png" % _shot_name)
	get_viewport().get_texture().get_image().save_png(path)
	print("SANDBOX_SHOT ", path, "  units=", battle.units.size(), " time=", snappedf(battle.time, 0.1))
	get_tree().quit()
