extends RefCounted
## Melee engagement positions around ONE target: replaces the 2D game's fixed 6 slots (3 rings x left/right).
##
## Rings of angular slots around the target, expressed RELATIVE to the target so they follow it when it moves.
## Ring k has radius target_r + attacker_r + gap + k * (2 * attacker_r + gap); the number of slots in a ring is
## however many attackers fit on that circle. A newcomer takes the free slot closest to the bearing it is
## already approaching from (so nobody circles round the target), preferring inner rings; when an inner
## slot frees up, an outer attacker near it steps in (the old "backfill"). Pure logic, no nodes.

const GAP := 0.08
const MAX_RINGS := 6
const CHORD_SLACK := 1.2          # slots are spaced 20% wider than body-to-body, so units can settle without shoving
const RING_COST := 1.6           # an outer ring is worth this many radians of walking round the target (inner rings fill first)

var rings: Array = []            # [{radius, count, phase, owner: Array}]


func _make_ring(index: int, target_r: float, att_r: float) -> Dictionary:
	var radius := target_r + att_r + GAP + index * (2.0 * att_r + GAP)
	var ratio := clampf(CHORD_SLACK * (2.0 * att_r + GAP) / (2.0 * radius), 0.0, 0.99)
	var count := maxi(3, int(floor(PI / asin(ratio))))
	var owner: Array = []
	owner.resize(count)
	owner.fill(-1)
	return {"radius": radius, "count": count, "phase": index * PI / count, "owner": owner}


func _angle_of(ring: Dictionary, idx: int) -> float:
	return ring["phase"] + TAU * idx / ring["count"]


func position_of(target_pos: Vector2, ring_idx: int, slot_idx: int) -> Vector2:
	var ring: Dictionary = rings[ring_idx]
	var a := _angle_of(ring, slot_idx)
	return target_pos + Vector2(cos(a), sin(a)) * ring["radius"]


## A point outside the outer rings on the slot's bearing. Attackers walk to it first and then step radially
## into their slot, so they never squeeze along the inside of the ring past units that already stand there.
func approach_point(target_pos: Vector2, ring_idx: int, slot_idx: int) -> Vector2:
	var a := _angle_of(rings[ring_idx], slot_idx)
	var outer: float = rings[mini(1, rings.size() - 1)]["radius"] + 0.9
	return target_pos + Vector2(cos(a), sin(a)) * outer


func slot_of(attacker_id: int) -> Vector2i:
	for r in rings.size():
		var owner: Array = rings[r]["owner"]
		for i in owner.size():
			if owner[i] == attacker_id:
				return Vector2i(r, i)
	return Vector2i(-1, -1)


func release(attacker_id: int) -> void:
	var s := slot_of(attacker_id)
	if s.x >= 0:
		rings[s.x]["owner"][s.y] = -1


static func _ang_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## Returns the claimed slot as Vector2i(ring, index); keeps an existing claim.
func claim(target_pos: Vector2, target_r: float, attacker_id: int, attacker_pos: Vector2, attacker_r: float) -> Vector2i:
	var have := slot_of(attacker_id)
	if have.x >= 0:
		return have
	var bearing := (attacker_pos - target_pos).angle()
	var best := Vector2i(-1, -1)
	var best_score := INF
	for r in MAX_RINGS:
		if r >= rings.size():
			rings.append(_make_ring(r, target_r, attacker_r))
		var ring: Dictionary = rings[r]
		for i in ring["count"]:
			if ring["owner"][i] != -1:
				continue
			var score := _ang_diff(_angle_of(ring, i), bearing) + r * RING_COST
			if score < best_score:
				best_score = score
				best = Vector2i(r, i)
		if best.x >= 0 and best.x == r and r > 0:
			break    # a ring that already has a free slot cannot be beaten by a further-out one
	if best.x >= 0:
		rings[best.x]["owner"][best.y] = attacker_id
	return best


## Backfill and swap, called every few ticks. `positions` maps attacker id -> current position.
##  - an outer attacker steps into a free inner slot close to it;
##  - an outer attacker that is now clearly NEARER to an inner slot than that slot's owner swaps with it
##    (otherwise a unit that took an outer slot first can stand in front of the inner slot and block it).
func rebalance(target_pos: Vector2, positions: Dictionary) -> void:
	for r in range(1, rings.size()):
		var outer: Array = rings[r]["owner"]
		var inner: Dictionary = rings[r - 1]
		for i in outer.size():
			var who: int = outer[i]
			if who == -1:
				continue
			var a := _angle_of(rings[r], i)
			var best := -1
			var best_d := 0.8
			for k in inner["count"]:
				var d := _ang_diff(_angle_of(inner, k), a)
				if d < best_d:
					best_d = d
					best = k
			if best < 0:
				continue
			var owner_inner: int = inner["owner"][best]
			if owner_inner == -1:
				inner["owner"][best] = who
				outer[i] = -1
			elif positions.has(who) and positions.has(owner_inner):
				var slot_pos := position_of(target_pos, r - 1, best)
				if positions[owner_inner].distance_to(slot_pos) > 0.6 \
						and positions[who].distance_to(slot_pos) + 0.5 < positions[owner_inner].distance_to(slot_pos):
					inner["owner"][best] = who
					outer[i] = owner_inner


func occupied() -> int:
	var n := 0
	for ring in rings:
		for o in ring["owner"]:
			if o != -1:
				n += 1
	return n
