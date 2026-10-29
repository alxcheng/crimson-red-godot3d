extends RefCounted
## Optimal Reciprocal Collision Avoidance for circular agents on the ground plane: a port of the
## RVO2 idea (van den Berg et al.) written for this game. For each agent it builds one half-plane of
## "safe velocities" per neighbour, then picks the safe velocity closest to the one the agent wants,
## by a small linear program (falling back to the least-violating velocity when no safe one exists).
##
## `share` lets responsibility be uneven (the RTS rules): a unit that must not move (attacking, stunned)
## takes none, the unit moving past it takes all; two equal movers split 50/50.
## Pure functions on Vector2: deterministic and headless.

const EPSILON := 0.00001


class Line:
	var point := Vector2.ZERO
	var direction := Vector2.ZERO


static func det(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


## neighbours: [{pos: Vector2, vel: Vector2, radius: float, share: float}] where `share` is the fraction
## of the avoidance THIS agent takes for that neighbour (0..1; 0.5 = reciprocal).
static func compute(pos: Vector2, vel: Vector2, radius: float, pref_velocity: Vector2, max_speed: float,
		neighbours: Array, time_horizon: float, dt: float) -> Vector2:
	var lines: Array = []
	var inv_horizon := 1.0 / time_horizon
	for n in neighbours:
		var rel_pos: Vector2 = n["pos"] - pos
		var rel_vel: Vector2 = vel - n["vel"]
		var dist_sq := rel_pos.length_squared()
		var combined: float = radius + n["radius"]
		var combined_sq := combined * combined
		var line := Line.new()
		var u: Vector2
		if dist_sq > combined_sq:
			var w := rel_vel - inv_horizon * rel_pos
			var w_len_sq := w.length_squared()
			var dot1 := w.dot(rel_pos)
			if dot1 < 0.0 and dot1 * dot1 > combined_sq * w_len_sq:
				var w_len := sqrt(w_len_sq)
				var unit_w := w / w_len
				line.direction = Vector2(unit_w.y, -unit_w.x)
				u = (combined * inv_horizon - w_len) * unit_w
			else:
				var leg := sqrt(dist_sq - combined_sq)
				if det(rel_pos, w) > 0.0:
					line.direction = Vector2(rel_pos.x * leg - rel_pos.y * combined,
							rel_pos.x * combined + rel_pos.y * leg) / dist_sq
				else:
					line.direction = -Vector2(rel_pos.x * leg + rel_pos.y * combined,
							-rel_pos.x * combined + rel_pos.y * leg) / dist_sq
				u = rel_vel.dot(line.direction) * line.direction - rel_vel
		else:
			# already overlapping: resolve within one tick
			var inv_dt := 1.0 / dt
			var w := rel_vel - inv_dt * rel_pos
			var w_len := w.length()
			if w_len < EPSILON:
				w = Vector2(1, 0)
				w_len = 1.0
			var unit_w := w / w_len
			line.direction = Vector2(unit_w.y, -unit_w.x)
			u = (combined * inv_dt - w_len) * unit_w
		line.point = vel + n["share"] * u
		lines.append(line)
	var result := Vector2.ZERO
	var fail := _lp2(lines, max_speed, pref_velocity, false)
	result = fail[1]
	if fail[0] < lines.size():
		result = _lp3(lines, fail[0], max_speed, result)
	return result


# Returns [index of the first line that could not be satisfied (lines.size() if none), velocity].
static func _lp2(lines: Array, radius: float, opt: Vector2, direction_opt: bool) -> Array:
	var result: Vector2
	if direction_opt:
		result = opt * radius
	elif opt.length_squared() > radius * radius:
		result = opt.normalized() * radius
	else:
		result = opt
	for i in lines.size():
		var li: Line = lines[i]
		if det(li.direction, li.point - result) > 0.0:
			var r = _lp1(lines, i, radius, opt, direction_opt)
			if r == null:
				return [i, result]
			result = r
	return [lines.size(), result]


static func _lp1(lines: Array, line_no: int, radius: float, opt: Vector2, direction_opt: bool):
	var ln: Line = lines[line_no]
	var dot := ln.point.dot(ln.direction)
	var disc := dot * dot + radius * radius - ln.point.length_squared()
	if disc < 0.0:
		return null
	var sq := sqrt(disc)
	var t_left := -dot - sq
	var t_right := -dot + sq
	for i in line_no:
		var li: Line = lines[i]
		var denom := det(ln.direction, li.direction)
		var numer := det(li.direction, ln.point - li.point)
		if absf(denom) <= EPSILON:
			if numer < 0.0:
				return null
			continue
		var t := numer / denom
		if denom >= 0.0:
			t_right = minf(t_right, t)
		else:
			t_left = maxf(t_left, t)
		if t_left > t_right:
			return null
	if direction_opt:
		if opt.dot(ln.direction) > 0.0:
			return ln.point + t_right * ln.direction
		return ln.point + t_left * ln.direction
	var t2 := ln.direction.dot(opt - ln.point)
	if t2 < t_left:
		return ln.point + t_left * ln.direction
	if t2 > t_right:
		return ln.point + t_right * ln.direction
	return ln.point + t2 * ln.direction


# No velocity satisfies every line: minimise the worst violation.
static func _lp3(lines: Array, begin: int, radius: float, current: Vector2) -> Vector2:
	var result := current
	var distance := 0.0
	for i in range(begin, lines.size()):
		var li: Line = lines[i]
		if det(li.direction, li.point - result) > distance:
			var proj: Array = []
			for j in i:
				var lj: Line = lines[j]
				var line := Line.new()
				var determinant := det(li.direction, lj.direction)
				if absf(determinant) <= EPSILON:
					if li.direction.dot(lj.direction) > 0.0:
						continue
					line.point = 0.5 * (li.point + lj.point)
				else:
					line.point = li.point + (det(lj.direction, li.point - lj.point) / determinant) * li.direction
				line.direction = (lj.direction - li.direction).normalized()
				proj.append(line)
			var temp := result
			var r := _lp2(proj, radius, Vector2(-li.direction.y, li.direction.x), true)
			if r[0] < proj.size():
				result = temp
			else:
				result = r[1]
			distance = det(li.direction, li.point - result)
	return result
