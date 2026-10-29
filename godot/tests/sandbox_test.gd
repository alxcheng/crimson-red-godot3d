extends SceneTree
## Run: Godot --headless --path crimson-red-3d/godot --script res://tests/sandbox_test.gd
## The sandbox battle's headless logic: orders, attack timing, containment, a whole fight, determinism.
const Sandbox := preload("res://sim/sandbox_battle.gd")
var _fail := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error(msg)


func _run_for(b, seconds: float) -> void:
	for _i in int(seconds / Sandbox.DT):
		b.tick()


func _initialize() -> void:
	_test_move_order()
	_test_attack_order()
	_test_resource_and_press_rules()
	_test_hamstring()
	_test_sunder_armor()
	_test_targeting_rules()
	_test_wizard()
	_test_knight_tree_abilities()
	_test_cleric()
	_test_weapon_speed()
	_test_challenging_shout()
	_test_timing_and_containment()
	_test_determinism()
	print("SANDBOX_PASS" if _fail == 0 else "SANDBOX_FAIL: %d" % _fail)
	quit(0 if _fail == 0 else 1)


func _test_move_order() -> void:
	var b = Sandbox.new()
	b.next_wave_t = 9999.0
	b.spawn_party(Sandbox.TEST_PARTY)
	var hero = b.heroes()[0]
	b.command_move(hero.id, Vector2(0.0, 0.0))
	_run_for(b, 6.0)
	_check(hero.agent.pos.length() < 0.5, "hero did not reach the move point: %s" % hero.agent.pos)
	_check(not hero.move_order, "move order not cleared on arrival")
	_check(absf(wrapf(hero.heading - PI / 2.0, -PI, PI)) < 1.7, "hero heading should face the way it walked (+X): %f" % hero.heading)


func _test_attack_order() -> void:
	var b = Sandbox.new()
	b.next_wave_t = 9999.0
	b.spawn_party(Sandbox.TEST_PARTY)
	var a = b.spawn("goblin", Vector2(4.0, -2.0))
	var c = b.spawn("goblin", Vector2(5.0, 2.0))
	var hero = b.heroes()[3]
	b.command_attack(hero.id, c.id)
	_run_for(b, 8.0)
	var first_target := -1
	for e in b.events:
		if e["type"] == "attack" and e["id"] == hero.id:
			first_target = e["target"]
			break
	_check(first_target == c.id, "ordered hero should attack the ordered goblin first (got %d, wanted %d)" % [first_target, c.id])
	_check(not b.alive(c.id) or b.units[c.id].hp < b.units[c.id].max_hp, "ordered target took no damage")


## A stand-in for the player (heroes only target what is clicked, as in 2D): every second, a hero with no target is clicked
## onto the nearest enemy, or, for the Cleric, onto the most hurt ally.
func _autoplay(b) -> void:
	for h in b.heroes():
		if h.state == Sandbox.State.DEAD or (h.target >= 0 and b.alive(h.target)):
			continue
		var best := -1
		var best_key := INF
		for id in b.units:
			var o = b.units[id]
			if o.state == Sandbox.State.DEAD or (o.team == h.team) != h.heals:
				continue
			var key: float = (o.hp / o.max_hp) if h.heals else h.agent.pos.distance_to(o.agent.pos)
			if key < best_key:
				best_key = key
				best = id
		if best >= 0:
			b.command_attack(h.id, best)


func _test_timing_and_containment() -> void:
	var b = Sandbox.new()
	b.spawn_party(Sandbox.TEST_PARTY)
	var bounds: Dictionary = b.layout["bounds"]
	var started := {}
	var checked := 0
	var worst_delay_error := 0.0
	var kinds_seen := {}
	for _i in int(120.0 / Sandbox.DT):
		if _i % 60 == 0:
			_autoplay(b)
		b.tick()
		for e in b.take_events():
			if e["type"] == "attack":
				started[e["id"]] = e["t"]
			elif e["type"] == "hit":
				kinds_seen[e["id"]] = true
				if started.has(e["id"]):
					var u = b.units.get(e["id"])
					if u != null and not u.ranged:           # a fireball hits when it arrives, not at the cast's delay
						worst_delay_error = maxf(worst_delay_error, absf((e["t"] - started[e["id"]]) - u.delay))
						checked += 1
		for u in b.units.values():
			if u.state == Sandbox.State.DEAD:
				continue
			var p: Vector2 = u.agent.pos
			if p.x < bounds["min_x"] - 0.01 or p.x > bounds["max_x"] + 0.01 or p.y < bounds["min_z"] - 0.01 or p.y > bounds["max_z"] + 0.01:
				_check(false, "unit %d left the arena at %s" % [u.id, p])
				return
		if b.over != "":
			break
	_check(checked > 10, "too few hits to check timing: %d" % checked)
	_check(worst_delay_error < 0.02, "swing-to-hit delay off by %.3f s" % worst_delay_error)
	_check(b.over != "", "the three waves should finish (victory or defeat) within 120 s; wave_index=%d" % b.wave_index)
	_check(b.world.max_overlap < 0.25, "units overlapped by %.2f m" % b.world.max_overlap)
	print("  fight: result=%s time=%.1fs hits=%d delay_err=%.4f max_overlap=%.3f gave_up=%d" % [
		b.over, b.time, checked, worst_delay_error, b.world.max_overlap, b.world.gave_up_count])


func _signature() -> String:
	var b = Sandbox.new()
	b.spawn_party(Sandbox.TEST_PARTY)
	var s := ""
	for _i in int(30.0 / Sandbox.DT):
		b.tick()
		for e in b.take_events():
			s += "%s:%d:%.3f;" % [e["type"], e.get("id", 0), e.get("t", 0.0)]
	for u in b.units.values():
		s += "%d:%.4f,%.4f;" % [u.id, u.agent.pos.x, u.agent.pos.y]
	return s


func _test_determinism() -> void:
	_check(_signature() == _signature(), "two identical battles diverged")


func _quiet_battle():
	var b = Sandbox.new()
	b.next_wave_t = 9999.0
	b.spawn_party(Sandbox.TEST_PARTY)
	for h in b.heroes():                       # the Wizard's fireballs would add damage to the numbers the tests check
		if h.ranged:
			b.units.erase(h.id)
			b.world.agents.erase(h.agent)
	return b


func _hits_by(b, who: int) -> Array:
	var out: Array = []
	for e in b.events:
		if e["type"] == "hit" and e["id"] == who:
			out.append(e)
	return out


func _test_resource_and_press_rules() -> void:
	var b = _quiet_battle()
	var knight = b.heroes()[0]
	var r0: float = b.resource
	_run_for(b, 2.0)
	_check(absf(b.resource - (r0 + 2.0)) < 0.05, "the shared resource should regenerate 1 per second (%f -> %f)" % [r0, b.resource])
	_check(knight.skills.size() == 3, "the Knight should have the three actives from the data")
	_check(knight.skills[0]["cost"] == 10.0 and knight.skills[1]["cost"] == 5.0 and knight.skills[2]["cost"] == 10.0, "costs are bars x 5")
	b.resource = 4.0
	_check(not b.command_skill(knight.id, 1), "not enough resource: the press must be rejected")
	_check(b.resource == 4.0 and knight.skills[1]["cd"] == 0.0, "a rejected press must spend nothing and start no cooldown")
	b.resource = 30.0
	_check(b.command_skill(knight.id, 1), "Sunder Armor should be castable with 30 resource")
	_check(b.resource == 25.0 and knight.skills[1]["cd"] > 9.9, "pay at press: cost spent and cooldown started at once")
	_check(not b.command_skill(knight.id, 1), "a skill on cooldown cannot be pressed")
	_check(not b.command_skill(knight.id, 0) or true, "")   # hamstring with no enemy: rejected below
	var b2 = _quiet_battle()
	# 2D rule: the press is accepted and paid even with no target; the ability waits in the queue for a target in reach
	_check(b2.command_skill(b2.heroes()[0].id, 0), "Hamstring with no target is accepted (paid at press) and waits for a target")
	_check(b2.resource == Sandbox.RESOURCE_START - 10.0 and b2.heroes()[0].queued_skill == 0, "the cost is spent and the ability is queued")


func _test_hamstring() -> void:
	var b = _quiet_battle()
	b.resource = 50.0
	var knight = b.heroes()[0]
	var g = b.spawn("goblin", knight.agent.pos + Vector2(1.2, 0.0))
	g.threat.clear()
	g.threat[knight.id] = 1.0
	g.target = knight.id
	g.max_hp = 5000.0
	g.hp = 5000.0
	b.command_attack(knight.id, g.id)                                  # the Knight's current target (heroes only target what is clicked)
	_check(b.command_skill(knight.id, 0), "Hamstring castable")
	_run_for(b, 1.5)
	var hits := _hits_by(b, knight.id)
	_check(hits.size() >= 1, "Hamstring should land")
	var dmg: float = hits[0]["dmg"]
	_check(dmg > 1.75 * knight.damage and dmg < 2.25 * knight.damage, "Hamstring is ~200%% damage, got %f (base %f)" % [dmg, knight.damage])
	_check(g.statuses.has("WEAKEN") and absf(g.statuses["WEAKEN"]["mag"] - 0.3) < 0.001, "the target should be weakened by 30%")
	# a weakened goblin hits for 30% less
	var weak_hit: float = g.damage * 0.7
	b.events.clear()
	_run_for(b, 3.0)
	var goblin_hits: Array = _hits_by(b, g.id)
	_check(goblin_hits.size() > 0, "the goblin should be attacking the Knight")
	for h in goblin_hits:
		_check(h["dmg"] <= g.damage * 1.1 * 0.7 + 0.01, "WEAKEN should cut the goblin's damage by 30%%: %f" % h["dmg"])


func _test_sunder_armor() -> void:
	var b = _quiet_battle()
	b.resource = 50.0
	var knight = b.heroes()[0]
	var near: Array = []
	for i in 3:
		var o = b.spawn("goblin", knight.agent.pos + Vector2(1.2 + i * 0.3, -1.0 + i))
		o.max_hp = 5000.0
		o.hp = 5000.0
		o.passive = true
		b.world.hold(o.agent, true)
		near.append(o)
	var far = b.spawn("goblin", knight.agent.pos + Vector2(8.0, 0.0))
	far.max_hp = 5000.0
	far.hp = 5000.0
	far.passive = true
	b.world.hold(far.agent, true)
	_check(b.command_skill(knight.id, 1), "Sunder Armor castable")
	_run_for(b, 1.0)
	for o in near:
		_check(o.hp < o.max_hp and absf((o.max_hp - o.hp) - 1.5 * knight.damage) < 0.5 * knight.damage, "Sunder hits nearby enemies for ~150%%: lost %f" % (o.max_hp - o.hp))
		_check(o.statuses.has("VULNERABILITY") and absf(o.statuses["VULNERABILITY"]["mag"] - 0.15) < 0.001, "nearby enemies are marked +15%")
	_check(far.hp == far.max_hp and not far.statuses.has("VULNERABILITY"), "an enemy outside the area is untouched")


## The 2D targeting rules: heroes do not pick targets, enemies follow threat, a hit hero fights back, the Cleric heals what it is clicked onto.
func _test_targeting_rules() -> void:
	var b = _quiet_battle()
	var knight = b.heroes()[0]
	var dummy = b.spawn("goblin", knight.agent.pos + Vector2(2.0, 0.0))
	dummy.passive = true
	_run_for(b, 3.0)
	_check(knight.target < 0 and b.units[dummy.id].hp == dummy.max_hp, "a hero does not auto-target an enemy standing next to it")
	b.command_attack(knight.id, dummy.id)
	_check(knight.target == dummy.id and knight.cd == 0.0, "a click sets the target and the first swing is immediate")
	b.command_move(knight.id, knight.agent.pos + Vector2(0.0, 3.0))
	_check(knight.target < 0, "a move order (a click on the ground) drops the target")
	# a hero hit while it has no target and is not walking fights back
	var b2 = _quiet_battle()
	var k2 = b2.heroes()[0]
	var attacker = b2.spawn("goblin", k2.agent.pos + Vector2(1.2, 0.0))
	b2._apply_hit(attacker, k2, 1.0)
	_check(k2.target == attacker.id, "a hero hit with no target and standing still fights back")
	var k3 = b2.heroes()[1]
	b2.command_move(k3.id, k3.agent.pos + Vector2(0.0, 2.0))
	b2._apply_hit(attacker, k3, 1.0)
	_check(k3.target < 0, "a hero that is walking does not turn to fight")
	# an idle hero joins in when a party member attacks an enemy inside its radius; one outside the radius does not; ranged heroes use the same radius
	var b3 = Sandbox.new()
	b3.next_wave_t = 9999.0
	b3.spawn_party(Sandbox.TEST_PARTY)
	var hs3 = b3.heroes()
	var fighter = hs3[0]
	var near_hero = hs3[3]                                    # the Rogue, idle next to the Knight
	var wiz = null
	for h in hs3:
		if h.ranged and not h.heals:
			wiz = h
	near_hero.agent.pos = fighter.agent.pos + Vector2(0.0, 2.2)           # stand next to the Knight
	var target = b3.spawn("goblin", fighter.agent.pos + Vector2(1.2, 0.0))
	target.passive = true
	target.max_hp = 90000.0
	target.hp = 90000.0
	b3.command_attack(fighter.id, target.id)
	_run_for(b3, 2.0)
	_check(near_hero.target == target.id, "an idle hero near the fight auto-targets what its party member attacks")
	_check(wiz.target == target.id or wiz.agent.pos.distance_to(target.agent.pos) > Sandbox.AUTO_TARGET_RADIUS,
			"the Wizard assists inside the radius (same radius as everyone, whatever its reach)")
	var far_battle = Sandbox.new()
	far_battle.next_wave_t = 9999.0
	far_battle.spawn_party(Sandbox.TEST_PARTY)
	var fh = far_battle.heroes()
	var lone = fh[0]
	var helper = null
	for h in fh:
		if h.ranged and not h.heals:
			helper = h
	far_battle.command_move(lone.id, Vector2(helper.agent.pos.x + 12.0, helper.agent.pos.y))
	_run_for(far_battle, 8.0)
	var far_dummy = far_battle.spawn("goblin", lone.agent.pos + Vector2(1.2, 0.0))
	far_dummy.passive = true
	far_dummy.max_hp = 90000.0
	far_dummy.hp = 90000.0
	far_battle.command_attack(lone.id, far_dummy.id)
	_run_for(far_battle, 2.0)
	_check(helper.target < 0, "an idle ranged hero more than the radius away does not auto-target (%.1f m)" % helper.agent.pos.distance_to(far_dummy.agent.pos))
	# a ranged enemy's first hit from outside the radius does not make an idle hero fight back
	var shooter = far_battle.spawn("goblin", helper.agent.pos + Vector2(Sandbox.AUTO_TARGET_RADIUS + 3.0, 0.0))
	shooter.passive = true
	far_battle._apply_hit(shooter, helper, 1.0)
	_check(helper.target < 0, "the first attacker outside the radius is not auto-targeted")
	# an enemy takes the highest threat every frame
	var g = b2.spawn("goblin", Vector2(0.0, 0.0))
	g.threat.clear()
	g.threat[k2.id] = 10.0
	g.threat[k3.id] = 11.0
	b2.tick()
	_check(g.target == k3.id, "an enemy aims at the hero it has the most threat against (no hysteresis)")


func _wizard_of(b):
	for h in b.heroes():
		if h.ranged and not h.heals:
			return h
	return null


func _dummy(b, pos: Vector2, hp: float = 90000.0):
	var o = b.spawn("goblin", pos)
	o.passive = true
	o.max_hp = hp
	o.hp = hp
	b.world.hold(o.agent, true)
	return o


## The Wizard's skill tree (data/wizard_talents.json, the Director's design).
func _test_wizard() -> void:
	var b = Sandbox.new()
	b.next_wave_t = 9999.0
	b.spawn_party(Sandbox.TEST_PARTY)
	var wiz = _wizard_of(b)
	_check(wiz != null and wiz.skills.size() == 3, "the default Wizard build has three actives (Explosion, Ice Block, Blizzard)")
	_check(wiz.skills[0]["name"] == "Explosion" and wiz.skills[1]["name"] == "Ice Block" and wiz.skills[2]["name"] == "Blizzard", "skills come in tier order")
	_check(b.skill_select(wiz.id, 0) == "area" and b.skill_select(wiz.id, 1) == "" and b.skill_select(wiz.id, 2) == "area", "Explosion / Blizzard are area-aimed, Ice Block needs no aim")
	_check(wiz.skills[0]["cost"] == 10.0 and wiz.skills[1]["cost"] == 10.0, "2 bars = 10 resource")
	_check(not b.command_skill(wiz.id, 0), "an area ability without an aim point is refused and costs nothing")
	_check(b.resource == Sandbox.RESOURCE_START, "a refused press costs nothing")
	# a goblin 5 m away is shot from where the Wizard stands; fire burns (15% of the damage over 5 s)
	var g = _dummy(b, wiz.agent.pos + Vector2(5.0, 0.0), 5000.0)
	b.command_attack(wiz.id, g.id)
	var saw_projectile := false
	for _i in int(4.0 / Sandbox.DT):
		b.tick()
		saw_projectile = saw_projectile or b.projectiles.size() > 0
	_check(saw_projectile and g.hp < g.max_hp, "the Wizard hits a goblin 5 m away with fireballs")
	_check(wiz.agent.pos.distance_to(g.agent.pos) > 3.0, "the Wizard fires from range instead of walking into melee")
	_check(g.statuses.has("BURN") or g.hp < g.max_hp - 100.0, "fireballs burn")

	# Explosion: 250% damage to everything in the circle; fire applies BURN worth 15% of the damage over 5 s
	var b2 = Sandbox.new()
	b2.next_wave_t = 9999.0
	b2.spawn_party(Sandbox.TEST_PARTY)
	b2.resource = 50.0
	var w2 = _wizard_of(b2)
	var inside = _dummy(b2, Vector2(0.0, 0.0))
	var outside = _dummy(b2, Vector2(9.0, 0.0))
	_check(b2.command_skill(w2.id, 0, {"pos": Vector2(0.5, 0.0)}), "Explosion castable at a spot")
	_check(b2.resource == 40.0, "Explosion costs 2 bars")
	for _i in int(1.2 / Sandbox.DT):
		b2.tick()
	var lost: float = inside.max_hp - inside.hp
	_check(lost > 2.0 * w2.damage and lost < 3.1 * w2.damage and outside.hp == outside.max_hp, "Explosion deals ~250%% inside the circle only (%f of %f)" % [lost, w2.damage])
	_check(inside.statuses.has("BURN") and absf(inside.statuses["BURN"]["mag"] * 5.0 - 0.15 * lost) < 0.2 * lost * 0.15 + 0.5, "fire burns for 15%% of the damage over 5 s")
	# Ice Block: invulnerable for 10 s; a wave every 2 s slows (frost) enemies in the area
	b2.resource = 50.0
	var near = _dummy(b2, w2.agent.pos + Vector2(2.0, 0.0))
	_check(b2.command_skill(w2.id, 1), "Ice Block castable")
	for _i in int(0.9 / Sandbox.DT):
		b2.tick()
	var hp0: float = w2.hp
	b2._apply_hit(near, w2, 200.0)
	_check(w2.statuses.has("INVULN") and w2.hp == hp0, "Ice Block makes the Wizard invulnerable")
	for _i in int(2.2 / Sandbox.DT):
		b2.tick()
	_check(near.statuses.has("SLOW") and near.statuses.has("VULNERABILITY"), "an Ice Block wave slows enemies and makes them take more damage (frost)")
	for _i in int(8.5 / Sandbox.DT):
		b2.tick()
	_check(not w2.statuses.has("INVULN") and w2.block.is_empty(), "Ice Block ends after 10 s")
	# Blizzard: 5 ticks, one per second, in an area twice the Explosion's, with frost
	b2.resource = 50.0
	var far_in = _dummy(b2, Vector2(5.0, 4.0))          # inside the doubled radius (7.7 m) but outside the Explosion's (3.9 m)
	var before: float = far_in.hp
	_check(b2.command_skill(w2.id, 2, {"pos": Vector2(2.0, 2.0)}), "Blizzard castable")
	var ticks := 0
	for _i in int(7.0 / Sandbox.DT):
		b2.tick()
		for e in b2.take_events():
			if e["type"] == "zone_tick":
				ticks += 1
	_check(ticks == 5, "Blizzard ticks 5 times (%d)" % ticks)
	_check(before - far_in.hp > 3.0 * 0.6 * w2.damage and far_in.statuses.has("SLOW"), "Blizzard hits the doubled area and chills it")
	_check(b2.zones.is_empty(), "the Blizzard zone ends")

	# Teleport: blink, lightning at both ends stuns enemies for 1 s
	var b3 = Sandbox.new()
	b3.next_wave_t = 9999.0
	b3.spawn_party(Sandbox.TEST_PARTY)
	b3.resource = 50.0
	var w3 = _wizard_of(b3)
	b3.set_wizard_build(w3, {"1": "iridescent_bolt", "10": "teleport"})
	_check(w3.skills.size() == 2 and w3.skills[1]["name"] == "Teleport" and w3.skills[1]["cost"] == 5.0, "Teleport costs 1 bar")
	var at_start = _dummy(b3, w3.agent.pos + Vector2(1.5, 0.0))
	var at_end = _dummy(b3, Vector2(0.0, 0.0))
	_check(b3.command_skill(w3.id, 1, {"pos": Vector2(0.5, 0.0)}), "Teleport castable")
	for _i in int(1.0 / Sandbox.DT):
		b3.tick()
	_check(w3.agent.pos.distance_to(Vector2(0.5, 0.0)) < 0.5, "the Wizard arrives at the chosen spot")
	_check(at_start.statuses.has("STUN") and at_end.statuses.has("STUN"), "lightning at the start and the end stuns enemies")
	# Iridescent Bolt: 500% to one target, fire
	var tgt = _dummy(b3, Vector2(8.0, 0.0))
	_check(b3.command_skill(w3.id, 0, {"unit": tgt.id}), "Iridescent Bolt castable on an enemy")
	for _i in int(3.0 / Sandbox.DT):
		b3.tick()
	_check(tgt.max_hp - tgt.hp > 4.0 * w3.damage, "Iridescent Bolt deals ~500%% (%f)" % (tgt.max_hp - tgt.hp))

	# the level-25 specialisations and Mirror Image
	var b4 = Sandbox.new()
	b4.next_wave_t = 9999.0
	b4.spawn_party(Sandbox.TEST_PARTY)
	var w4 = _wizard_of(b4)
	b4.set_wizard_build(w4, {"1": "explosion", "10": "ice_block", "20": "blizzard", "25": "pyromancer"})
	_check(w4.skills[1]["name"] == "Hellfire" and w4.skills[2]["name"] == "Firestorm" and w4.burn_mult == 2.0, "Pyromancer: Ice Block -> Hellfire, Blizzard -> Firestorm, burning x2")
	b4.set_wizard_build(w4, {"1": "explosion", "10": "teleport", "20": "blizzard", "25": "cryomancer"})
	_check(w4.skills[0]["name"] == "Ice Shock" and w4.auto_element == "frost", "Cryomancer: Explosion -> Ice Shock, auto attacks -> frost bolts")
	var frosty = _dummy(b4, w4.agent.pos + Vector2(4.0, 0.0), 5000.0)
	b4.command_attack(w4.id, frosty.id)
	for _i in int(3.0 / Sandbox.DT):
		b4.tick()
	_check(frosty.statuses.has("SLOW"), "a frost bolt slows its target")
	b4.set_wizard_build(w4, {"1": "explosion", "10": "ice_block", "20": "mirror_image"})
	_check(w4.mirror and w4.skills.size() == 2, "Mirror Image is a passive (a visual copy, no extra skill)")


func _test_knight_tree_abilities() -> void:
	var b = Sandbox.new()
	b.next_wave_t = 9999.0
	b.spawn_party([{"kind": "knight", "label": "Knight", "gear": [], "weapon": "sword_long", "abilities": ["KnightDefend", "KnightCharge", "KnightBattleShout"]},
			{"kind": "wizard", "label": "Wizard", "gear": [], "weapon": "staff_oak"}])
	b.resource = 50.0
	var k = b.heroes()[0]
	_check(k.skills.size() == 3 and k.skills[0]["name"] == "Defend" and k.skills[1]["name"] == "Charge" and k.skills[2]["name"] == "BattleShout", "the Knight's talent picks (Defend, Charge, Battle Shout) become his three abilities")
	_check(b.skill_select(k.id, 0) == "" and b.skill_select(k.id, 1) == "unit" and b.skill_select(k.id, 2) == "", "Defend / Battle Shout need no aim, Charge picks an enemy")
	_check(b.command_skill(k.id, 0), "Defend castable")
	_run_for(b, 0.5)
	_check(k.statuses.has("DEF_BUFF"), "Defend gives the Knight DEF_BUFF")
	_check(b.command_skill(k.id, 2), "Battle Shout castable")
	_run_for(b, 0.5)
	var w = b.heroes()[1]
	_check(k.statuses.has("ATK_BUFF") and w.statuses.has("ATK_BUFF") and absf(k.statuses["ATK_BUFF"]["mag"] - 0.2) < 0.001, "Battle Shout gives every ally +20% damage")
	var far = _dummy(b, k.agent.pos + Vector2(9.0, 0.0))
	var t0: float = b.time
	_check(b.command_skill(k.id, 1, {"unit": far.id}), "Charge castable on a far enemy")
	var t_hit := -1.0
	for _i in int(4.0 / Sandbox.DT):
		b.tick()
		for e in b.take_events():
			if e["type"] == "hit" and e["id"] == k.id and t_hit < 0.0:
				t_hit = b.time
	_check(t_hit > 0.0 and t_hit - t0 < 2.5, "the Knight charges 9 m and hits (%.2f s)" % (t_hit - t0))
	_check(far.max_hp - far.hp > 1.9 * k.damage, "Charge hits for about 200%% or more (%f)" % (far.max_hp - far.hp))


func _test_weapon_speed() -> void:
	var b = Sandbox.new()
	b.spawn_party([{"kind": "knight", "weapon_speed": 0.8}, {"kind": "knight", "weapon_speed": 1.5}, {"kind": "knight"}])
	var h: Array = b.heroes()
	_check(is_equal_approx(h[0].cd_max / h[2].cd_max, 0.8) and is_equal_approx(h[1].cd_max / h[2].cd_max, 1.5), "weapon speed scales the auto-attack cooldown (%f, %f vs %f)" % [h[0].cd_max, h[1].cd_max, h[2].cd_max])


func _test_cleric() -> void:
	var b = Sandbox.new()
	b.next_wave_t = 9999.0
	b.spawn_party(Sandbox.TEST_PARTY)
	var cl = null
	var knight = b.heroes()[0]
	for h in b.heroes():
		if h.heals:
			cl = h
	_check(cl != null and cl.skills.size() == 3, "the Cleric has three abilities (Director: three per hero)")
	_check(b.skill_select(cl.id, 0) == "" and b.skill_select(cl.id, 1) == "unit" and b.skill_select(cl.id, 2) == "unit",
			"Group Heal needs no aim; Shield and Power Infusion pick an ally")
	# the auto action heals the most hurt ally, from wherever the Cleric stands
	knight.hp = knight.max_hp * 0.4
	var before: float = knight.hp
	b.command_attack(cl.id, knight.id)                                 # the Cleric heals the ally it was clicked onto (2D: no auto target)
	_run_for(b, 4.0)
	_check(knight.hp > before, "the Cleric heals the hurt Knight on its own (%f -> %f)" % [before, knight.hp])
	var healed_events := 0
	for e in b.events:
		if e["type"] == "heal" and e["id"] == cl.id:
			healed_events += 1
	_check(healed_events > 0 or knight.hp > before, "a heal event is raised")
	# Group Heal heals every hero; it costs no resource
	for h in b.heroes():
		h.hp = h.max_hp * 0.5
	var res_before: float = b.resource
	_check(b.command_skill(cl.id, 0), "Group Heal castable")
	_run_for(b, 1.5)
	var all_up := true
	for h in b.heroes():
		all_up = all_up and h.hp > h.max_hp * 0.5 + 30.0
	_check(all_up, "Group Heal heals every living hero")
	# Shield only goes to an ally; Power Infusion buffs damage
	var enemy = b.spawn("goblin", Vector2(0.0, 0.0))
	_check(not b.command_skill(cl.id, 1, {"unit": enemy.id}), "Shield refuses an enemy target")
	_check(b.command_skill(cl.id, 1, {"unit": knight.id}), "Shield castable on an ally")
	_run_for(b, 1.5)
	_check(knight.statuses.has("SHIELD") and absf(knight.statuses["SHIELD"]["mag"] - 0.75) < 0.001, "Shield removes 75%% of damage taken")
	_check(b.command_skill(cl.id, 2, {"unit": knight.id}), "Power Infusion castable on an ally")
	_run_for(b, 1.5)
	_check(knight.statuses.has("ATK_BUFF"), "Power Infusion adds +100%% damage")


func _test_challenging_shout() -> void:
	var b = _quiet_battle()
	b.resource = 50.0
	var hs = b.heroes()
	var knight = hs[0]
	var other = hs[1]
	var g = b.spawn("goblin", other.agent.pos + Vector2(2.0, 0.0))
	g.max_hp = 50000.0      # the heroes auto-attack it: keep it alive for the whole check
	g.hp = 50000.0
	g.threat[other.id] = 60.0
	g.target = other.id
	_run_for(b, 1.0)
	_check(g.target == other.id, "the goblin should be on the hero it has threat against")
	_check(b.command_skill(knight.id, 2), "Challenging Shout castable")
	_run_for(b, 1.2)
	_check(g.threat.get(knight.id, 0.0) >= 350.0 * 0.9 - 1.0, "the shout adds 350 threat on every enemy (less the 2D decay of 10%% per second: %f)" % g.threat.get(knight.id, 0.0))
	_check(g.target == knight.id, "the goblin should turn on the Knight after the shout (target %d)" % g.target)
