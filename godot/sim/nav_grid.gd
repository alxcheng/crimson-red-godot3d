extends RefCounted
## Walkable-area queries and A* pathing on the stage's ground plane (metres, Vector2 = (x, z)).
##
## Built from stage.json: a rectangle of walkable floor minus circle/box obstacles. Unit size is handled
## analytically: `clearance_at(p)` is the exact distance from p to the nearest wall/obstacle edge, so a
## unit of radius r may stand wherever clearance >= r. A* runs on a coarse grid (0.25 m) for the route;
## the route is then pulled straight with line-of-sight checks against the same clearance function.
## Pure logic: no nodes, so it runs headless and is deterministic.

const CELL := 0.5      # route grid; smoothing and clearance use the exact (analytic) distances, so this only sets how fine the A* search is
const SQRT2 := 1.41421356
const HEURISTIC_WEIGHT := 1.15   # slightly greedy A*: far fewer expansions, routes at most ~15% longer before smoothing

var min_x: float
var max_x: float
var min_z: float
var max_z: float
var circles: Array = []   # [{x, z, r}]
var boxes: Array = []     # [{x, z, hw, hd}]
var _clear_cache := PackedFloat32Array()            # per-tick memo of _cell_clear (NAN = not yet computed)
var _dyn_buckets := {}                        # bucket key -> [dynamic obstacles that can matter inside that bucket]
var dynamic: Array = []   # temporary obstacles for ONE query: [{x, z, r}] (units that hold their ground)
var _static_clear := PackedFloat32Array()
var _cols: int
var _rows: int
var _ox: float
var _oz: float


static func from_layout(layout: Dictionary):
	var grid = load("res://sim/nav_grid.gd").new()
	var b: Dictionary = layout["bounds"]
	grid.setup(b["min_x"], b["max_x"], b["min_z"], b["max_z"], layout.get("obstacles", []))
	return grid


func setup(p_min_x: float, p_max_x: float, p_min_z: float, p_max_z: float, obstacles: Array) -> void:
	min_x = p_min_x
	max_x = p_max_x
	min_z = p_min_z
	max_z = p_max_z
	circles.clear()
	boxes.clear()
	for o in obstacles:
		if o["type"] == "circle":
			circles.append({"x": o["x"], "z": o["z"], "r": o["r"]})
		else:
			boxes.append({"x": o["x"], "z": o["z"], "hw": o["w"] * 0.5, "hd": o["d"] * 0.5})
	_ox = min_x
	_oz = min_z
	_cols = int(ceil((max_x - min_x) / CELL))
	_rows = int(ceil((max_z - min_z) / CELL))
	# clearance of every cell centre against the static stage, computed once (A* reads it many times)
	var saved := dynamic
	dynamic = []
	_static_clear.resize(_cols * _rows)
	for r in _rows:
		for c in _cols:
			_static_clear[r * _cols + c] = clearance_static(_center_of(Vector2i(c, r)))
	dynamic = saved
	_clear_cache.resize(_cols * _rows)
	_clear_cache.fill(NAN)


const MAX_EXPANSIONS := 1400     # A* cell budget per route (the map has ~3800 cells)
const _DX := [1, -1, 0, 0, 1, 1, -1, -1]
const _DY := [0, 0, 1, -1, 1, -1, 1, -1]
const PULL_WINDOW := 14          # cells (7 m) the route straightening looks ahead from each waypoint
const _BUCKET := 2.0
const _INFLUENCE := 1.6          # a unit never needs more clearance than this, so farther obstacles cannot matter
const _NO_OBSTACLES: Array = []


func _bucket_key(p: Vector2) -> int:
	return (int(floor(p.x / _BUCKET)) + 4096) * 8192 + (int(floor(p.y / _BUCKET)) + 4096)


## Call after filling `dynamic`: files each temporary obstacle into the 2 m buckets it can influence, so a clearance
## query looks at a handful of obstacles instead of all of them.
func rebuild_dynamic() -> void:
	_dyn_buckets.clear()
	_clear_cache.resize(_cols * _rows)
	_clear_cache.fill(NAN)
	for d in dynamic:
		var reach: float = float(d["r"]) + _INFLUENCE
		for bx in range(int(floor((d["x"] - reach) / _BUCKET)), int(floor((d["x"] + reach) / _BUCKET)) + 1):
			for bz in range(int(floor((d["z"] - reach) / _BUCKET)), int(floor((d["z"] + reach) / _BUCKET)) + 1):
				var key := (bx + 4096) * 8192 + (bz + 4096)
				if not _dyn_buckets.has(key):
					_dyn_buckets[key] = []
				_dyn_buckets[key].append(d)


func _cell_clear(c: Vector2i) -> float:
	return _clear_idx(c.y * _cols + c.x, c.x, c.y)


func _clear_idx(i: int, cx: int, cy: int) -> float:
	var v := _clear_cache[i]
	if not is_nan(v):
		return v                                   # already worked out this tick (every route search shares it)
	v = _static_clear[i]
	if not _dyn_buckets.is_empty():
		var p := Vector2(_ox + (cx + 0.5) * CELL, _oz + (cy + 0.5) * CELL)
		for d in _dyn_buckets.get(_bucket_key(p), _NO_OBSTACLES):
			v = minf(v, p.distance_to(Vector2(d["x"], d["z"])) - d["r"])
	_clear_cache[i] = v
	return v


## Exact signed distance from p to the nearest wall or STATIC obstacle edge (negative inside an obstacle
## or outside the arena).
func clearance_static(p: Vector2) -> float:
	var d := minf(minf(p.x - min_x, max_x - p.x), minf(p.y - min_z, max_z - p.y))
	for c in circles:
		d = minf(d, p.distance_to(Vector2(c["x"], c["z"])) - c["r"])
	for bx in boxes:
		var q := Vector2(absf(p.x - bx["x"]) - bx["hw"], absf(p.y - bx["z"]) - bx["hd"])
		var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
		var inside := minf(maxf(q.x, q.y), 0.0)
		d = minf(d, outside + inside)
	return d


## Clearance including the temporary `dynamic` obstacles (units holding their ground), used for routing.
func clearance_at(p: Vector2) -> float:
	var d := clearance_static(p)
	if not _dyn_buckets.is_empty():
		for c in _dyn_buckets.get(_bucket_key(p), _NO_OBSTACLES):
			d = minf(d, p.distance_to(Vector2(c["x"], c["z"])) - c["r"])
	return d


## Push p out of walls/obstacles until a unit of `radius` fits. Used as the hard clamp after movement.
func push_out(p: Vector2, radius: float) -> Vector2:
	for _i in 6:
		var c := clearance_static(p)
		if c >= radius - 0.0005:
			return p
		var e := 0.02
		var g := Vector2(clearance_static(p + Vector2(e, 0)) - clearance_static(p - Vector2(e, 0)),
				clearance_static(p + Vector2(0, e)) - clearance_static(p - Vector2(0, e)))
		if g.length_squared() < 0.0000001:
			g = Vector2(0, 0) - p
		p += g.normalized() * (radius - c + 0.002)
	return p


func segment_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	var length := a.distance_to(b)
	var steps := maxi(1, int(ceil(length / 0.2)))
	for i in steps + 1:
		if clearance_at(a.lerp(b, float(i) / steps)) < radius:
			return false
	return true


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x - _ox) / CELL), 0, _cols - 1), clampi(int((p.y - _oz) / CELL), 0, _rows - 1))


func _center_of(c: Vector2i) -> Vector2:
	return Vector2(_ox + (c.x + 0.5) * CELL, _oz + (c.y + 0.5) * CELL)


func _nearest_walkable(p: Vector2, radius: float) -> Vector2:
	if clearance_at(p) >= radius:
		return p
	var best := p
	var best_d := INF
	for ring in range(1, 40):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var q := p + Vector2(dx, dy) * CELL
				if clearance_at(q) >= radius and p.distance_to(q) < best_d:
					best_d = p.distance_to(q)
					best = q
		if best_d < INF:
			return best
	return p


## Route from `from` to `to` for a unit of `radius`. Returns waypoints (first is `from`, last is the goal,
## snapped to walkable ground). Empty when unreachable.
func find_path(from: Vector2, to: Vector2, radius: float) -> PackedVector2Array:
	var start := _nearest_walkable(from, radius)
	var goal := _nearest_walkable(to, radius)
	if segment_clear(start, goal, radius):
		return PackedVector2Array([from, goal])
	var s := _cell_of(start)
	var g := _cell_of(goal)
	var n_cells := _cols * _rows
	var si := s.y * _cols + s.x
	var gi := g.y * _cols + g.x
	var cost := PackedFloat32Array()
	cost.resize(n_cells)
	cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(n_cells)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n_cells)
	var open: Array = [[_h(s, g), si]]   # binary heap of [f, cell index]
	cost[si] = 0.0
	var found := si == gi
	var expansions := 0
	var best_i := si                      # the closed cell nearest the goal, used when the search is cut short
	var best_h := INF
	while not open.is_empty():
		var cur_i: int = _heap_pop(open)[1]
		if closed[cur_i] == 1:
			continue
		closed[cur_i] = 1
		if cur_i == gi:
			found = true
			break
		var cx := cur_i % _cols
		var cy := cur_i / _cols
		var hh := _h(Vector2i(cx, cy), g)
		if hh < best_h:
			best_h = hh
			best_i = cur_i
		expansions += 1
		if expansions > MAX_EXPANSIONS:       # a goal that cannot be reached (walled in by standing units) would flood the whole map
			break
		for k in 8:
			var nx: int = cx + _DX[k]
			var ny: int = cy + _DY[k]
			if nx < 0 or ny < 0 or nx >= _cols or ny >= _rows:
				continue
			var ni: int = ny * _cols + nx
			if closed[ni] == 1:
				continue
			if _clear_idx(ni, nx, ny) < radius:
				continue
			var diagonal := k >= 4
			if diagonal:   # no cutting corners
				if _clear_idx(cy * _cols + nx, nx, cy) < radius or _clear_idx(ny * _cols + cx, cx, ny) < radius:
					continue
			var nc: float = cost[cur_i] + (SQRT2 if diagonal else 1.0)
			if nc < cost[ni]:
				cost[ni] = nc
				came[ni] = cur_i
				_heap_push(open, [nc + HEURISTIC_WEIGHT * _h(Vector2i(nx, ny), g), ni])
	if not found and best_i != si:
		gi = best_i                           # route to the closest point reached; the unit re-plans as it goes
		goal = _center_of(Vector2i(gi % _cols, gi / _cols))
		found = true
	if not found:
		return PackedVector2Array()
	var cells: Array[Vector2] = []
	var ci := gi
	while ci != si:
		cells.append(_center_of(Vector2i(ci % _cols, ci / _cols)))
		ci = came[ci]
	cells.reverse()
	cells.append(goal)
	# pull the route straight: from each anchor jump to the farthest waypoint still in line of sight
	var out := PackedVector2Array([from])
	var anchor := start
	var i := 0
	while i < cells.size():
		var far := i
		for j in range(mini(cells.size() - 1, i + PULL_WINDOW), i - 1, -1):   # a bounded look-ahead keeps this linear
			if segment_clear(anchor, cells[j], radius):
				far = j
				break
		out.append(cells[far])
		anchor = cells[far]
		i = far + 1
	return out


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + (SQRT2 - 1.0) * float(mini(dx, dy))


func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= heap[i][0]:
			break
		var tmp = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < heap.size() and heap[l][0] < heap[m][0]:
				m = l
			if r < heap.size() and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var tmp = heap[m]
			heap[m] = heap[i]
			heap[i] = tmp
			i = m
	return top
