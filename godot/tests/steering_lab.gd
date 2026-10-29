extends SceneTree
## The steering lab: scripted movement scenarios that judge the RTS movement stack by numbers.
## Run: Godot --headless --path crimson-red-3d/godot --script res://tests/steering_lab.gd
## Prints one line per scenario (time to settle, worst overlap, stuck/gave-up units, path efficiency)
## and STEERING_LAB_PASS / FAIL (exit code 0 / 1). Thresholds are [tuned] and live next to each scenario.

const GameData := preload("res://sim/game_data.gd")
const NavGrid := preload("res://sim/nav_grid.gd")
const SteerWorld := preload("res://sim/steer_world.gd")
const Slots := preload("res://sim/slots.gd")
const LAYOUT_PATH := "res://models/stage/stage.json"

const DT := 1.0 / 60.0
# Speeds and radii come from the exported 2D data (the original speeds, in metres per second).
var HERO_R: float = GameData.hero_radius("knight")
var HERO_SPEED: float = GameData.hero_speed_mps()
var GOBLIN_R: float = GameData.enemy_radius("goblin")
var GOBLIN_SPEED: float = GameData.enemy_speed_mps("goblin")
var SKELETON_R: float = GameData.enemy_radius("skeleton")
var SKELETON_SPEED: float = GameData.enemy_speed_mps("skeleton")

var _layout: Dictionary
var _failures := 0
var _rows: Array = []


func _initialize() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	_run.call_deferred()


func _stage_nav():
	return NavGrid.from_layout(_layout)


## The stage is an open floor now, so obstacle behaviour is tested on this explicit layout (the old stage's
## four pillars and two ruined walls, kept as test data so routing around obstacles stays covered).
func _cluttered_nav():
	var g = NavGrid.new()
	g.setup(-15.0, 15.0, -7.5, 7.5, [
		{"type": "circle", "x": -8.0, "z": -4.5, "r": 0.66}, {"type": "circle", "x": -8.0, "z": 4.5, "r": 0.66},
		{"type": "circle", "x": 6.5, "z": -4.5, "r": 0.66}, {"type": "circle", "x": 6.5, "z": 4.5, "r": 0.66},
		{"type": "box", "x": 0.5, "z": -3.2, "w": 3.7, "d": 0.65}, {"type": "box", "x": -1.5, "z": 3.6, "w": 0.65, "d": 3.1}])
	return g


func _open_nav():
	var g = NavGrid.new()
	g.setup(-15.0, 15.0, -7.5, 7.5, [])
	return g


func _report(name: String, ok: bool, details: String, reason: String = "") -> void:
	if not ok:
		_failures += 1
	_rows.append("%s  %-26s %s%s" % ["PASS" if ok else "FAIL", name, details, ("   <- " + reason) if reason != "" else ""])


func _step(world, seconds: float, until: Callable = Callable()) -> float:
	var t := 0.0
	seconds /= GameData.PACE                       # the budgets were written for the original speeds; everyone is slower now
	while t < seconds:
		world.tick(DT)
		t += DT
		if until.is_valid() and until.call():
			break
	return t


func _all_arrived(world) -> bool:
	for a in world.agents:
		if a.mode == SteerWorld.Mode.MOVING and not a.arrived:
			return false
	return true


func _eff(a, start: Vector2) -> float:
	var straight: float = start.distance_to(a.goal)
	return a.travelled / maxf(straight, 0.01)


# ---------------------------------------------------------------- scenarios
func head_on() -> void:
	var w = SteerWorld.new(_stage_nav())
	var a = w.add_agent(1, Vector2(-6, 0), HERO_R, HERO_SPEED)
	var b = w.add_agent(2, Vector2(6, 0), HERO_R, HERO_SPEED)
	w.order_move(a, Vector2(6, 0))
	w.order_move(b, Vector2(-6, 0))
	var t := _step(w, 12.0, func(): return _all_arrived(w))
	var eff := maxf(_eff(a, Vector2(-6, 0)), _eff(b, Vector2(6, 0)))
	var ok: bool = _all_arrived(w) and w.gave_up_count == 0 and w.max_overlap < 0.10 and eff < 1.25
	_report("head_on (exact symmetry)", ok, "t=%.1fs overlap=%.3f gaveup=%d eff=%.2f" % [t, w.max_overlap, w.gave_up_count, eff],
		"" if ok else "arrived=%s" % _all_arrived(w))


func crossing() -> void:
	var w = SteerWorld.new(_open_nav())
	var id := 1
	var starts := {}
	for k in 4:
		var left = w.add_agent(id, Vector2(-9, -1.5 + k), HERO_R, HERO_SPEED)
		starts[id] = left.pos
		w.order_move(left, Vector2(9, -1.5 + k))
		id += 1
		var down = w.add_agent(id, Vector2(-1.5 + k, 6), HERO_R, HERO_SPEED)
		starts[id] = down.pos
		w.order_move(down, Vector2(-1.5 + k, -6))
		id += 1
	var t := _step(w, 14.0, func(): return _all_arrived(w))
	var eff := 0.0
	for a in w.agents:
		eff = maxf(eff, _eff(a, starts[a.id]))
	var ok: bool = _all_arrived(w) and w.gave_up_count == 0 and w.max_overlap < 0.12 and eff < 1.5
	_report("crossing 4x4", ok, "t=%.1fs overlap=%.3f gaveup=%d eff=%.2f" % [t, w.max_overlap, w.gave_up_count, eff])


func route_around() -> void:
	var w = SteerWorld.new(_cluttered_nav())
	var a = w.add_agent(1, Vector2(-6, -3.2), HERO_R, HERO_SPEED)
	w.order_move(a, Vector2(8, -3.2))   # the ruined wall at (0.5, -3.2) is in the way
	var t := _step(w, 12.0, func(): return _all_arrived(w))
	var eff := _eff(a, Vector2(-6, -3.2))
	var ok: bool = _all_arrived(w) and not a.gave_up and eff < 1.4 and w.nav.clearance_static(a.pos) >= HERO_R - 0.01
	_report("route around ruin", ok, "t=%.1fs eff=%.2f" % [t, eff])


func doorway() -> void:
	var nav = NavGrid.new()
	nav.setup(-15.0, 15.0, -7.5, 7.5, [{"type": "box", "x": 0.0, "z": 4.15, "w": 0.4, "d": 6.7},
			{"type": "box", "x": 0.0, "z": -4.15, "w": 0.4, "d": 6.7}])   # a wall with a 1.6 m gap
	var w = SteerWorld.new(nav)
	for i in 6:
		var a = w.add_agent(i + 1, Vector2(-5 + (i % 2) * 1.2, -2.0 + (i / 2) * 1.5), HERO_R, HERO_SPEED)
		w.order_move(a, Vector2(5, -2.0 + i * 0.8), 7)
	var t := _step(w, 30.0, func(): return _all_arrived(w))
	var ok: bool = _all_arrived(w) and w.gave_up_count == 0 and w.max_overlap < 0.12
	_report("doorway 6 through 1.6 m", ok, "t=%.1fs overlap=%.3f gaveup=%d" % [t, w.max_overlap, w.gave_up_count])


func _positions(list: Array) -> Dictionary:
	var d := {}
	for a in list:
		d[a.id] = a.pos
	return d


func _in_range(a, target, reach: float) -> bool:
	return a.pos.distance_to(target.pos) <= a.radius + target.radius + reach


func surround(count: int, name: String) -> void:
	var w = SteerWorld.new(_stage_nav())
	var target = w.add_agent(100, Vector2(0, 0), HERO_R, HERO_SPEED)
	w.hold(target, true)
	var slots = Slots.new()
	var mine: Array = []
	for i in count:
		var g = w.add_agent(i + 1, Vector2(9.0 + (i % 3) * 0.9, -2.0 + (i / 3) * 1.0), GOBLIN_R, GOBLIN_SPEED)
		var s: Vector2i = slots.claim(target.pos, target.radius, g.id, g.pos, g.radius)
		w.order_move(g, slots.position_of(target.pos, s.x, s.y), -1, slots.approach_point(target.pos, s.x, s.y))
		g.arrive_radius = 0.2
		g.accept_radius = 0.6
		mine.append(g)
	var reach := 1.1      # rings 0 and 1 can attack (ring 1 sits ~0.86 m off the target's body, plus settling tolerance), like the 2D game, whose reach covers its first two rings
	var first_all := -1.0
	var t := 0.0
	while t < 10.0:
		for g in mine:
			var s: Vector2i = slots.slot_of(g.id)
			if s.x >= 0:
				w.update_goal(g, slots.position_of(target.pos, s.x, s.y), slots.approach_point(target.pos, s.x, s.y))
		slots.rebalance(target.pos, _positions(mine))
		w.tick(DT)
		t += DT
		var in_range := 0
		for g in mine:
			if _in_range(g, target, reach):
				in_range += 1
		if first_all < 0.0 and in_range == mini(count, 6):
			first_all = t
	var in_range_end := 0
	for g in mine:
		if _in_range(g, target, reach):
			in_range_end += 1
	# more than six attackers cannot all reach (rings 0 and 1 only): the rest wait their turn near the target
	var ok: bool = first_all > 0.0 and first_all < 7.0 / GameData.PACE and w.max_overlap < 0.10 \
			and in_range_end >= mini(count, 6)
	_report(name, ok, "all-in-range at %.1fs, %d/%d in range, overlap=%.3f (units that cannot get a slot wait: %d)" % [
		first_all, in_range_end, count, w.max_overlap, w.gave_up_count])


func party_to_point() -> void:
	var w = SteerWorld.new(_stage_nav())
	for i in 4:
		var a = w.add_agent(i + 1, Vector2(-8.6, -3.0 + i * 2.0), HERO_R, HERO_SPEED)
		w.order_move(a, Vector2(0, 0), 1)
	var t := _step(w, 14.0, func(): return _all_arrived(w))
	var settled_at: Array = []
	for a in w.agents:
		settled_at.append(a.pos)
	_step(w, 2.0)
	var drift := 0.0
	var farthest := 0.0
	var min_gap := INF
	for i in w.agents.size():
		drift = maxf(drift, w.agents[i].pos.distance_to(settled_at[i]))
		farthest = maxf(farthest, w.agents[i].pos.length())
		for j in range(i + 1, w.agents.size()):
			min_gap = minf(min_gap, w.agents[i].pos.distance_to(w.agents[j].pos) - 2.0 * HERO_R)
	var ok: bool = t < 14.0 and drift < 0.06 and farthest < 2.6 and min_gap > -0.02 and w.gave_up_count == 0
	_report("party to one point", ok, "t=%.1fs jitter=%.3fm spread=%.2fm min_gap=%.2f gaveup=%d" % [t, drift, farthest, min_gap, w.gave_up_count])


func moving_target() -> void:
	var w = SteerWorld.new(_open_nav())
	var target = w.add_agent(100, Vector2(4, 0), HERO_R, HERO_SPEED * 0.6)   # a hero kiting at 60% speed
	w.order_move(target, Vector2(0, 4))
	var slots = Slots.new()
	var chasers: Array = []
	for i in 3:
		var g = w.add_agent(i + 1, Vector2(-10, -2.0 + i * 2.0), GOBLIN_R, GOBLIN_SPEED)
		g.arrive_radius = 0.2
		g.accept_radius = 0.6
		chasers.append(g)
		var cs: Vector2i = slots.claim(target.pos, target.radius, g.id, g.pos, g.radius)
		w.order_move(g, slots.position_of(target.pos, cs.x, cs.y), -1, slots.approach_point(target.pos, cs.x, cs.y))
	var in_range_ticks := 0
	var window_ticks := 0
	var t := 0.0
	while t < 16.0 / GameData.PACE:
		var ang: float = target.pos.angle() + 0.35            # keep jogging round a circle of radius 4 m
		w.update_goal(target, Vector2(cos(ang), sin(ang)) * 4.0)
		target.arrived = false
		target.mode = SteerWorld.Mode.MOVING
		for g in chasers:
			var s: Vector2i = slots.slot_of(g.id)
			w.update_goal(g, slots.position_of(target.pos, s.x, s.y), slots.approach_point(target.pos, s.x, s.y))
		slots.rebalance(target.pos, _positions(chasers))
		w.tick(DT)
		t += DT
		if t > 6.0 / GameData.PACE:
			window_ticks += 1
			var all_in := true
			for g in chasers:
				all_in = all_in and _in_range(g, target, 1.1)
			if all_in:
				in_range_ticks += 1
	var frac := float(in_range_ticks) / maxf(window_ticks, 1)
	var ok: bool = frac > 0.5 and w.gave_up_count == 0 and w.max_overlap < 0.15
	_report("slots follow a moving target", ok, "all 3 in range %.0f%% of 6-16 s, overlap=%.3f gaveup=%d" % [frac * 100.0, w.max_overlap, w.gave_up_count])


func through_fight() -> void:
	var w = SteerWorld.new(_open_nav())
	var cluster := [Vector2(-0.7, 0.2), Vector2(0.8, -0.3), Vector2(0.1, 1.2), Vector2(-0.2, -1.1), Vector2(1.5, 0.9)]
	var held: Array = []
	for i in cluster.size():
		var a = w.add_agent(10 + i, cluster[i], HERO_R if i < 2 else GOBLIN_R, 2.0)
		w.hold(a, true)
		held.append(a)
	var walker = w.add_agent(1, Vector2(-7, 0), HERO_R, HERO_SPEED)
	w.order_move(walker, Vector2(7, 0))
	var t := _step(w, 14.0, func(): return _all_arrived(w))
	var moved := 0.0
	for i in held.size():
		moved = maxf(moved, held[i].pos.distance_to(cluster[i]))
	var ok: bool = _all_arrived(w) and not walker.gave_up and moved < 0.02 and w.max_overlap < 0.12 and walker.pos.x > 6.0
	_report("walk through a standing fight", ok, "t=%.1fs fighters moved %.3fm overlap=%.3f eff=%.2f" % [t, moved, w.max_overlap, _eff(walker, Vector2(-7, 0))])


func knockback() -> void:
	var w = SteerWorld.new(_cluttered_nav())
	var a = w.add_agent(1, Vector2(-14.0, 0.0), HERO_R, HERO_SPEED)
	var b = w.add_agent(2, Vector2(-6.0, -4.5), HERO_R, HERO_SPEED)   # a pillar at (-8, -4.5), r 0.66
	w.knock(a, Vector2(-40, 0))
	w.knock(b, Vector2(-40, 0))
	_step(w, 2.0)
	var ok: bool = w.nav.clearance_static(a.pos) >= HERO_R - 0.01 and w.nav.clearance_static(b.pos) >= HERO_R - 0.01
	_report("knockback into wall and pillar", ok, "wall %.2f pillar %.2f clearance (need %.2f)" % [
		w.nav.clearance_static(a.pos), w.nav.clearance_static(b.pos), HERO_R])


func determinism() -> void:
	var finals: Array = []
	for _run_i in 2:
		var w = SteerWorld.new(_stage_nav())
		for i in 4:
			var a = w.add_agent(i + 1, Vector2(-8.6, -3.0 + i * 2.0), HERO_R, HERO_SPEED)
			w.order_move(a, Vector2(2, 0), 1)
		_step(w, 6.0)
		var s := ""
		for a in w.agents:
			s += "%f,%f;" % [a.pos.x, a.pos.y]
		finals.append(s)
	_report("deterministic replay", finals[0] == finals[1], "two runs %s" % ("identical" if finals[0] == finals[1] else "DIFFER"))


func pathing_cost() -> void:
	var nav = _cluttered_nav()
	var t0 := Time.get_ticks_usec()
	var n := 200
	for i in n:
		nav.find_path(Vector2(-14, -6 + (i % 12)), Vector2(14, 6 - (i % 12)), HERO_R)
	var per_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	_report("A* cost per query", per_ms < 4.0, "%.2f ms across a 30x15 m arena with 6 obstacles" % per_ms)


func _run() -> void:
	head_on()
	crossing()
	route_around()
	doorway()
	surround(6, "surround x6 (one ring)")
	surround(9, "surround x9 (two rings)")
	party_to_point()
	moving_target()
	through_fight()
	knockback()
	determinism()
	pathing_cost()
	print("---- steering lab ----")
	for r in _rows:
		print(r)
	print("STEERING_LAB_PASS" if _failures == 0 else "STEERING_LAB_FAIL: %d" % _failures)
	quit(0 if _failures == 0 else 1)
