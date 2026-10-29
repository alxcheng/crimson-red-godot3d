extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://tests/sandbox_view_test.gd
## Drives the sandbox battle SCENE like a player (selection keys, orders, pause, spawn, restart, debug overlay)
## and checks nothing errors and the controls do what they should. Headless: no rendering is checked.
const Sandbox := preload("res://sim/sandbox_battle.gd")
const SCENE := "res://view/sandbox_battle.tscn"
var _fail := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error(msg)


var _view


func _key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	_view._unhandled_input(e)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Sandbox.dev_party = Sandbox.TEST_PARTY                      # the 4-hero test party (the game's party is the Knight and the Wizard)
	var view := (load(SCENE) as PackedScene).instantiate()
	root.add_child(view)
	_view = view
	for _i in 10:
		await process_frame
	_check(view.views.size() == 4, "4 heroes should be on screen, got %d" % view.views.size())
	# 1-4 select
	_key(KEY_3)
	_check(view.selected_index == 2, "key 3 should select the third hero")
	# one click on the ground = a move order for the selected hero
	var hero = view.battle.heroes()[2]
	view._order_selected(root.get_visible_rect().size * Vector2(0.5, 0.55))   # headless viewports are tiny: aim relative
	_check(hero.move_order or hero.agent.goal_set, "a ground click should order the selected hero to move")
	# one click on an enemy = an attack order
	var enemy = view.battle.spawn("goblin", Vector2(3.0, 0.0))
	await process_frame
	view.hover_id = enemy.id
	view._order_selected(view.stage.camera.unproject_position(Vector3(3.0, 0.9, 0.0)))
	_check(hero.ordered and hero.target == enemy.id, "a click on an enemy should be an attack order")
	# Q W E cast the selected hero's abilities (the Knight: Hamstring, Sunder Armor, Challenging Shout)
	_key(KEY_1)
	hero = view.battle.heroes()[0]
	view.battle.resource = 50.0
	view.battle.command_attack(hero.id, enemy.id)
	_key(KEY_E)
	_check(hero.queued_skill == 2 or hero.skills[2]["cd"] > 0.0, "E should cast the third ability (Challenging Shout)")
	_check(view.battle.resource <= 40.0, "the ability's cost is paid at the press")
	# an aimed ability (the Wizard's Explosion): the world slows to a STOP and stays stopped until the target is picked
	_key(KEY_3)
	var wiz = view.battle.heroes()[2]
	_key(KEY_Q)
	_check(not view._aim.is_empty() and view._aim["kind"] == "area", "Q on the Wizard starts aiming an area")
	_check(wiz.skills[0]["cd"] == 0.0, "an aimed ability costs nothing until it is placed")
	var frozen_at: float = view.battle.time
	await create_timer(1.2).timeout                              # real seconds: the slow-to-stop takes about half a second
	var t_after: float = view.battle.time
	await create_timer(0.5).timeout
	_check(view.battle.time == t_after and t_after - frozen_at < 1.0, "the battle is stopped while aiming")
	view._confirm_aim(root.get_visible_rect().size * 0.5)
	_check(view._aim.is_empty() and wiz.skills[0]["cd"] > 0.0, "the click places the area: cooldown starts and aiming ends")
	await create_timer(1.2).timeout
	_check(view.battle.time > t_after, "after the pick the world speeds back up")
	_key(KEY_Q)
	_check(view._aim.is_empty(), "Explosion is on cooldown now: no aiming")
	view.battle.resource = 50.0
	_key(KEY_W)                                                  # Ice Block: no aim; a short stop, then normal speed
	_check(wiz.skills[1]["cd"] > 0.0, "Ice Block is cast at once")
	await create_timer(1.6).timeout                              # the stop-beat ends and the cast goes off
	_key(KEY_E)                                                  # Blizzard: an area, so it aims
	_key(KEY_ESCAPE)
	_check(view._aim.is_empty() and not view.paused, "ESC cancels aiming (it does not pause)")
	_key(KEY_1)
	# pause stops the sim, resume continues
	_key(KEY_SPACE)
	var t0: float = view.battle.time
	for _i in 20:
		await process_frame
	_check(view.paused and view.battle.time == t0, "SPACE should freeze the battle")
	_key(KEY_SPACE)
	for _i in 30:
		await process_frame
	_check(not view.paused and view.battle.time > t0, "SPACE again should resume")
	# debug overlay, time scale, spawn keys, restart
	_key(KEY_F)
	_check(view.debug_on, "F should toggle the debug overlay")
	for _i in 5:
		await process_frame
	_key(KEY_BRACKETRIGHT)
	_key(KEY_BRACKETLEFT)
	_key(KEY_K)
	_key(KEY_J)
	for _i in 10:
		await process_frame
	_key(KEY_BACKSPACE)
	for _i in 5:
		await process_frame
	_check(view.views.size() == 4 and view.battle.time < 1.0, "BACKSPACE should restart with a fresh party")
	print("SANDBOX_VIEW_PASS" if _fail == 0 else "SANDBOX_VIEW_FAIL: %d" % _fail)
	quit(0 if _fail == 0 else 1)
