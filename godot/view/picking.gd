extends RefCounted
## Which unit is under the mouse? One function for the hover highlight AND the click, so what lights up is
## exactly what gets ordered.
##
## Why not "the ground point under the cursor is inside the unit's collision circle": under the dimetric camera a
## unit's body is drawn ABOVE its feet, so clicking the visible body hits the floor BEHIND the circle and misses,
## and the circle itself is only about a metre wide, a few pixels at this camera distance.
##
## What other games do (research, PORT_PLAN.md section 9): selection is its own volume, separate from the collision
## circle (StarCraft II keeps a distinct selection radius; Brood War selects the top-most unit whose sprite box is
## under the pixel; League of Legends tests the model's bounding box first, then a disc and a hemispheroid of a
## selection radius and height, the first one the ray reaches). So here:
##   tier 1 "body": a vertical capsule from the feet to the head (collision radius x 0.9, at least 0.35 m);
##          among units whose body contains the cursor the FRONT-MOST wins, like the top-most sprite;
##   tier 2 "generous": the same capsule widened (radius x 1.5, at least 0.6 m, and at least MIN_PICK_PX pixels
##          so a small or distant unit is still clickable) plus a ground disc around the feet (collision radius
##          + GROUND_EXTRA); the unit whose centre line the cursor is closest to wins.

const MIN_PICK_PX := 18.0      # a unit can be clicked within this many pixels of its body, whatever the zoom
const GROUND_EXTRA := 0.6      # metres: the ground disc around the feet is the collision radius plus this
const HEIGHTS := {"knight": 1.95 * 0.9, "skeleton": 1.95, "goblin": 1.4, "witch": 1.9, "mannequin": 1.95 * 0.9}   # playable rigs are drawn at 90% height


static func height_of(model: String) -> float:
	return HEIGHTS.get(model, 1.9)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0))


## candidates: [{id, pos: Vector2 (ground x, z), radius: float, height: float}]. Returns the id or -1.
static func pick(camera: Camera3D, candidates: Array, screen_pos: Vector2) -> int:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ground_hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_dir)
	var ground := Vector2.INF
	if ground_hit != null:
		ground = Vector2(ground_hit.x, ground_hit.z)
	var right := camera.global_transform.basis.x
	var forward := -camera.global_transform.basis.z
	var best_core := -1
	var best_core_depth := INF
	var best_wide := -1
	var best_wide_score := INF
	for c in candidates:
		var p: Vector2 = c["pos"]
		var feet := Vector3(p.x, 0.0, p.y)
		var low := camera.unproject_position(feet + Vector3(0, 0.1, 0))
		var high := camera.unproject_position(feet + Vector3(0, c["height"] * 0.95, 0))
		var px_per_m := camera.unproject_position(feet + right).distance_to(camera.unproject_position(feet))
		var d := _seg_dist(screen_pos, low, high)
		var core_px := maxf(maxf(c["radius"] * 0.9, 0.35) * px_per_m, 6.0)
		var wide_px := maxf(maxf(c["radius"] * 1.5, 0.6) * px_per_m, MIN_PICK_PX)
		var on_ground: bool = ground != Vector2.INF and ground.distance_to(p) <= c["radius"] + GROUND_EXTRA
		var depth := (feet + Vector3(0, c["height"] * 0.5, 0) - camera.global_position).dot(forward)
		if d <= core_px or ground != Vector2.INF and ground.distance_to(p) <= c["radius"] * 0.9:
			if depth < best_core_depth:
				best_core_depth = depth
				best_core = c["id"]
		elif d <= wide_px or on_ground:
			var score := minf(d / wide_px, ground.distance_to(p) / (c["radius"] + GROUND_EXTRA) if ground != Vector2.INF else INF)
			if score < best_wide_score:
				best_wide_score = score
				best_wide = c["id"]
	return best_core if best_core >= 0 else best_wide
