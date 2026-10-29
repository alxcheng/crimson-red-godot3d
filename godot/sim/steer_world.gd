extends RefCounted
## The movement stack for battle units on the ground plane (metres; Vector2 = (x, z)); see PORT_PLAN.md 3.2.
##
##  1. order     a goal (move point, or a melee slot kept fresh by the caller)
##  2. path      A* on the nav grid, string-pulled; re-pathed on a throttle and when stuck
##  3. desired   follow waypoints, slow on arrival
##  4. avoid     ORCA with uneven responsibility: held units (attacking/stunned) are immovable, idle units
##               yield a little and drift home, movers have right of way, the newer order wins
##  5. stop      per-group arrival radius that grows as units arrive, density stop, blocked-near-goal stop
##  6. fix       position relaxation for any remaining overlap, then clamp to the walkable area
## Fixed-step and deterministic; no nodes, so it runs headless.

const NavGrid := preload("res://sim/nav_grid.gd")
const Orca := preload("res://sim/orca.gd")
const GameData := preload("res://sim/game_data.gd")

enum Mode { IDLE, MOVING, HELD }

const NEIGHBOUR_RANGE := 6.0
const MAX_NEIGHBOURS := 10
const TIME_HORIZON := 2.4                            # [tuned] longer than the 1.4 s used at full speed: slower units need more lead
const IDLE_PUSH_SPEED := 0.8 * GameData.PACE
const IDLE_HOME_GAIN := 3.0
const REPATH_INTERVAL := 0.4
const STUCK_CHECK := 0.8
const WEIGHT_MOVING := 1.0
const WEIGHT_IDLE := 2.5
const NEWER_ORDER_BONUS := 0.4
const ARRIVE_RADIUS := 0.12


class Agent:
	var id := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kvel := Vector2.ZERO          # knockback velocity (decays)
	var radius := 0.45
	var max_speed := 3.0
	var mode := 0                     # SteerWorld.Mode
	var goal := Vector2.ZERO
	var goal_set := false
	var via := Vector2.ZERO           # optional first stop (an approach point); cleared when reached or the goal is in view
	var via_active := false
	var group := -1
	var accept_radius := 0.0           # if blocked this close to the goal, count as arrived (slots packed by neighbours)
	var arrive_radius := 0.12         # how close counts as "at the goal" (melee slots use a looser one)
	var arrived := false
	var gave_up := false
	var home := Vector2.ZERO
	var order_time := 0.0
	var path := PackedVector2Array()
	var path_i := 0
	var repath_t := 0.0
	var repath_goal := Vector2.ZERO
	var stuck_t := 0.0
	var stuck_pos := Vector2.ZERO
	var stuck_count := 0
	var blocked_t := 0.0
	var travelled := 0.0
	var pref := Vector2.ZERO


var nav
var agents: Array = []
var time := 0.0
var group_arrived := {}
# metrics
var max_overlap := 0.0
var overlap_ticks := 0
var gave_up_count := 0


func _init(p_nav) -> void:
	nav = p_nav


func add_agent(id: int, pos: Vector2, radius: float, max_speed: float) -> Agent:
	var a := Agent.new()
	a.id = id
	a.pos = pos
	a.home = pos
	a.radius = radius
	a.max_speed = max_speed
	a.stuck_pos = pos
	agents.append(a)
	return a


func order_move(a: Agent, goal: Vector2, group: int = -1, via: Vector2 = Vector2.INF) -> void:
	a.via = via
	a.via_active = via != Vector2.INF
	a.goal = goal
	a.goal_set = true
	a.group = group
	a.arrived = false
	a.gave_up = false
	a.mode = Mode.MOVING
	a.order_time = time
	a.stuck_count = 0
	a.blocked_t = 0.0
	_repath(a)


## Keep walking to a goal that moves (a melee slot, a target): updates the goal and re-paths on the throttle.
func update_goal(a: Agent, goal: Vector2, via: Vector2 = Vector2.INF) -> void:
	a.goal = goal
	if a.via_active and via != Vector2.INF:
		a.via = via
	if a.arrived and a.pos.distance_to(goal) > a.arrive_radius * 3.0:
		a.arrived = false
		a.mode = Mode.MOVING
		a.order_time = time


func stop(a: Agent) -> void:
	a.mode = Mode.IDLE
	a.goal_set = false
	a.home = a.pos
	a.vel = Vector2.ZERO


func hold(a: Agent, on: bool) -> void:
	a.mode = Mode.HELD if on else Mode.IDLE
	if on:
		a.vel = Vector2.ZERO
	a.home = a.pos


func knock(a: Agent, impulse: Vector2) -> void:
	a.kvel += impulse


func _repath(a: Agent) -> void:
	var dest: Vector2 = a.via if a.via_active else a.goal
	a.path = nav.find_path(a.pos, dest, a.radius)
	a.path_i = 1 if a.path.size() > 1 else 0
	a.repath_t = 0.0
	a.repath_goal = dest


func _weight(a: Agent) -> float:
	if a.mode == Mode.HELD:
		return INF
	return WEIGHT_MOVING if a.mode == Mode.MOVING else WEIGHT_IDLE


func tick(dt: float) -> void:
	time += dt
	_refresh_group_counts()
	# units standing still (fighting, stunned, or settled) are obstacles for ROUTES, like a building, so a
	# unit that needs to get round a crowd plans a way round it instead of shoving through
	nav.dynamic.clear()
	for h: Agent in agents:
		if h.mode == Mode.HELD or h.mode == Mode.IDLE:
			nav.dynamic.append({"x": h.pos.x, "z": h.pos.y, "r": h.radius})
	nav.rebuild_dynamic()
	var new_vel := {}
	for a: Agent in agents:
		if a.mode == Mode.HELD:
			new_vel[a.id] = Vector2.ZERO
			continue
		a.pref = _preferred_velocity(a, dt)
		var neighbours: Array = []
		var near: Array = []
		for o: Agent in agents:
			if o == a:
				continue
			var d := a.pos.distance_to(o.pos)
			if d < NEIGHBOUR_RANGE:
				near.append([d, o])
		near.sort_custom(func(x, y): return x[0] < y[0])
		for k in mini(near.size(), MAX_NEIGHBOURS):
			var o: Agent = near[k][1]
			neighbours.append({"pos": o.pos, "vel": o.vel, "radius": o.radius, "share": _share(a, o)})
		var speed_cap: float = a.max_speed if a.mode == Mode.MOVING else IDLE_PUSH_SPEED
		new_vel[a.id] = Orca.compute(a.pos, a.vel, a.radius, a.pref, speed_cap, neighbours, TIME_HORIZON, dt)
	# integrate
	for a: Agent in agents:
		a.vel = new_vel[a.id]
		var step: Vector2 = a.vel * dt + a.kvel * dt
		a.kvel *= pow(0.9, 60.0 * dt)
		if a.kvel.length() < 0.02:
			a.kvel = Vector2.ZERO
		a.pos += step
		a.travelled += step.length()
	_measure_overlap()
	_relax_overlaps()
	for a: Agent in agents:
		a.pos = nav.push_out(a.pos, a.radius)
		_check_progress(a, dt)


func _share(a: Agent, o: Agent) -> float:
	var wo := _weight(o)
	var wa := _weight(a)
	if wo == INF:
		return 1.0
	if a.mode == Mode.MOVING and o.mode == Mode.MOVING:
		var newer_a: bool = a.order_time > o.order_time
		wa += NEWER_ORDER_BONUS if newer_a else 0.0
		wo += 0.0 if newer_a else NEWER_ORDER_BONUS
	return wo / (wa + wo)


func _refresh_group_counts() -> void:
	group_arrived.clear()
	for a: Agent in agents:
		if a.group >= 0 and a.arrived and not a.gave_up:
			group_arrived[a.group] = group_arrived.get(a.group, 0) + 1


func _stop_radius(a: Agent) -> float:
	var extra := 0.0
	if a.group >= 0:
		extra = a.radius * 1.1 * sqrt(float(group_arrived.get(a.group, 0)))
	return a.arrive_radius + extra


func _preferred_velocity(a: Agent, dt: float) -> Vector2:
	if a.mode == Mode.IDLE or not a.goal_set:
		var to_home: Vector2 = a.home - a.pos
		return to_home * IDLE_HOME_GAIN if to_home.length() > 0.02 else Vector2.ZERO
	if a.arrived:
		a.mode = Mode.IDLE
		a.home = a.pos
		return Vector2.ZERO
	var to_goal: Vector2 = a.goal - a.pos
	var dist := to_goal.length()
	var stop_r := _stop_radius(a)
	if dist <= stop_r:
		a.arrived = true
		return Vector2.ZERO
	# blocked near the goal (others already standing there): stop instead of pushing
	if a.group >= 0 and dist < stop_r + a.radius * 4.0 + 1.0 and a.vel.length() < 0.2 * a.max_speed:
		a.blocked_t += dt
		if a.blocked_t > 0.6:
			a.arrived = true
			return Vector2.ZERO
	else:
		a.blocked_t = 0.0
	# density stop: the area around the goal is already crowded by standing units
	if a.group >= 0 and dist < a.radius * 3.0 + 0.5:
		var crowd := 0.0
		var area_r := a.radius * 2.6
		for o: Agent in agents:
			if o != a and (o.mode == Mode.IDLE or o.mode == Mode.HELD) and o.pos.distance_to(a.goal) < area_r:
				crowd += PI * o.radius * o.radius
		if crowd / (PI * area_r * area_r) > 0.5:
			a.arrived = true
			return Vector2.ZERO
	if a.via_active and (a.pos.distance_to(a.via) < 0.6 or nav.segment_clear(a.pos, a.goal, a.radius)):
		a.via_active = false
		_repath(a)
	a.repath_t += dt
	var dest: Vector2 = a.via if a.via_active else a.goal
	if a.repath_t >= REPATH_INTERVAL and dest.distance_to(a.repath_goal) > 0.5:
		_repath(a)
	if a.path.is_empty():
		return Vector2.ZERO
	while a.path_i < a.path.size() - 1 and a.pos.distance_to(a.path[a.path_i]) < maxf(0.3, a.radius * 0.6):
		a.path_i += 1
	# look ahead: skip to the next waypoint when it is directly reachable
	if a.path_i < a.path.size() - 1 and nav.segment_clear(a.pos, a.path[a.path_i + 1], a.radius):
		a.path_i += 1
	var target: Vector2 = a.path[a.path_i]
	# a goal that keeps moving (a slot on a moving target) is steered at directly once it is in view,
	# so the unit does not chase a stale last waypoint
	if not a.via_active and a.path_i >= a.path.size() - 1 and nav.segment_clear(a.pos, a.goal, a.radius):
		target = a.goal
	var to_t := target - a.pos
	var d := to_t.length()
	if d < 0.0001:
		return Vector2.ZERO
	var speed := a.max_speed
	if a.path_i == a.path.size() - 1:
		speed = minf(speed, d / 0.25)    # arrival: reach the point in about a quarter second
	return to_t / d * speed


func _check_progress(a: Agent, dt: float) -> void:
	if a.mode != Mode.MOVING or a.arrived:
		a.stuck_t = 0.0
		a.stuck_pos = a.pos
		return
	a.stuck_t += dt
	if a.stuck_t < STUCK_CHECK:
		return
	var moved := a.pos.distance_to(a.stuck_pos)
	a.stuck_t = 0.0
	a.stuck_pos = a.pos
	if moved < 0.12 * a.max_speed * STUCK_CHECK and a.pos.distance_to(a.goal) > _stop_radius(a) + a.radius:
		if a.pos.distance_to(a.goal) <= a.accept_radius:
			a.arrived = true          # blocked by neighbours right next to the goal: close enough
			return
		a.stuck_count += 1
		_repath(a)
		if a.stuck_count >= 4:
			a.arrived = true
			a.gave_up = true
			gave_up_count += 1
	else:
		a.stuck_count = 0


func _measure_overlap() -> void:
	var worst := 0.0
	for i in agents.size():
		for j in range(i + 1, agents.size()):
			var a: Agent = agents[i]
			var b: Agent = agents[j]
			worst = maxf(worst, a.radius + b.radius - a.pos.distance_to(b.pos))
	max_overlap = maxf(max_overlap, worst)
	if worst > 0.05:
		overlap_ticks += 1


func _relax_overlaps() -> void:
	for _pass in 2:
		for i in agents.size():
			for j in range(i + 1, agents.size()):
				var a: Agent = agents[i]
				var b: Agent = agents[j]
				var d: Vector2 = b.pos - a.pos
				var dist := d.length()
				var overlap: float = a.radius + b.radius - dist
				if overlap <= 0.0:
					continue
				var n := d / dist if dist > 0.0001 else Vector2(1, 0)
				var wa := _weight(a)
				var wb := _weight(b)
				var ma := 0.0 if wa == INF else (1.0 if wb == INF else wb / (wa + wb))
				var mb := 0.0 if wb == INF else (1.0 if wa == INF else wa / (wa + wb))
				if wa == INF and wb == INF:    # two units holding ground (one was knocked into the other): split it
					ma = 0.5
					mb = 0.5
				a.pos -= n * overlap * ma
				b.pos += n * overlap * mb
