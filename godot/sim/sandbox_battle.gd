extends RefCounted
## SANDBOX battle: units on the dungeon stage driven by the real movement stack (SteerWorld + melee slots),
## with a deliberately tiny combat model so movement, spacing, facing and animation timing can be judged
## in play. It is NOT the game's rules: damage, HP and targeting are placeholders ([tuned], marked below).
## What is real: speeds and collision radii (exported 2D data), attack cooldown / hit delay / animation lock
## (the 2D auto-attack rows), the 2D controls, and the movement/engagement logic.
##
## Headless and deterministic: no nodes, own random source, a fixed 60 Hz step. The view reads `units` and
## drains `events`.

const GameData := preload("res://sim/game_data.gd")
const NavGrid := preload("res://sim/nav_grid.gd")
const SteerWorld := preload("res://sim/steer_world.gd")
const Slots := preload("res://sim/slots.gd")

enum State { IDLE, MOVE, ATTACK, HIT, DEAD }

const DT := 1.0 / 60.0
const REACH := 1.0              # melee reach beyond the two bodies (rings 0 and 1 can attack)
const HIT_STAGGER := 0.3        # seconds a hit unit cannot act (the TakeHit clip length)
const HIT_KNOCK := 3.0          # knockback speed from a normal hit (about half a metre)
const TURN_RATE := deg_to_rad(720.0)
const CORPSE_TIME := 3.0
const AUTO_TARGET_RADIUS := 6.0  # [tuned] Director: the fixed radius around ANY playable character inside which it auto-targets (the same for ranged heroes)
const ENTRY_STAGGER := 0.8
const RESOURCE_MAX := 50.0       # the shared party resource bar (the 2D game: 10 bars of 5)
const RESOURCE_PER_BAR := 5.0
const RESOURCE_START := 20.0     # [tuned] sandbox only: the 2D battle starts at 0; a head start lets abilities be tried
const SKILL_KINDS := {"KnightHamstring": "hamstring", "KnightSunderArmor": "sunder", "KnightChallengingShout": "shout",
		"KnightDefend": "defend", "KnightCharge": "charge", "KnightBattleShout": "battleshout",
		"PriestGroupHeal": "groupheal", "PriestShield": "shield", "PriestPowerInfusion": "infuse", "PriestVengefulAngel": "angel"}
const SKILL_ANIM := {"hamstring": "Attack2", "sunder": "Attack3", "shout": "", "defend": "", "charge": "", "battleshout": "",
		"groupheal": "StaffRaise", "shield": "StaffRaise", "infuse": "StaffRaise", "angel": "StaffRaise"}   # the 2D rows: animListIdx 4 = Attack2 (the staff clip for wizards)
# 3D-side icon overrides (Director): the 2D rows give all four Wizard abilities skill_icons46
const ICON_OVERRIDE := {}
const SKILL_LOCK := {"groupheal": 0.95, "shield": 0.95, "infuse": 0.95, "angel": 0.95}   # how long a staff cast keeps the caster busy
const KNOCK_ANGEL := 9.0         # [tuned] m/s: Vengeful Angel's knockback (the 2D row says force 120)
const PROJECTILE_SPEED := 12.0   # [tuned] m/s (WizardAutoFireball.projectile.speed is in 2D units)
const PROJECTILE_HEIGHT := 1.2
const DOT_TICK := 1.0
const DEFAULT_WIZARD_BUILD := {"1": "explosion", "10": "ice_block", "20": "blizzard"}   # the sandbox Wizard's picks (the skill tree: data/wizard_talents.json)

# placeholder combat numbers [tuned]; everything else comes from the data
const PLACEHOLDER_DAMAGE := {"knight": 85.0, "rogue": 55.0, "goblin": 28.0, "skeleton": 24.0, "witch": 30.0, "wizard": 55.0, "cleric": 65.0}
const PLACEHOLDER_HP := {"knight": 1000.0, "rogue": 700.0, "goblin": 375.0, "skeleton": 500.0, "witch": 420.0, "wizard": 600.0, "cleric": 650.0}


class Unit:
	var id := 0
	var team := 0                    # 0 heroes, 1 enemies
	var kind := ""
	var label := ""
	var model := ""                  # res://models/<model>.glb
	var gear: Array = []
	var weapon := ""
	var radius := 0.45
	var speed := 3.0
	var hp := 100.0
	var max_hp := 100.0
	var damage := 10.0
	var cd_max := 1.1
	var delay := 0.233
	var lock := 0.467
	var cd := 0.0
	var state := 0                   # State
	var state_t := 0.0
	var target := -1                 # who it is attacking / approaching
	var ordered := false             # a player attack order (heroes)
	var move_order := false          # a player move order (heroes)
	var move_point := Vector2.ZERO
	var move_issued := false
	var pending_t := -1.0            # time until the swing lands
	var pending_target := -1
	var swing := 0
	var heading := 0.0               # radians; 0 = facing +Z (the models' forward)
	var corpse_t := 0.0
	var claimed := -1                # target whose slot ring this unit is registered in
	var skills: Array = []           # heroes: [{id, name, kind, bars, cost, cd_max, cd, delay, anim, row}]
	var queued_skill := -1           # pressed ability waiting for the unit to be free / in range
	var pending_skill := -1          # the ability whose effect lands at pending_t
	var cur_lock := 0.467            # length of the swing / cast in progress
	var swing_anim := "Attack1"      # which attack clip the view plays for this swing
	var statuses := {}               # name -> {t, mag, src}: WEAKEN (deals less), VULNERABILITY (takes more), STUN, SLOW, DOT
	var ranged := false              # attacks from wherever it stands (the Wizard, the Cleric): no range requirement
	var heals := false               # the Cleric: its auto action heals an ALLY (the most hurt one, or the one it was ordered onto)
	var heal_value := 1.0
	var queued_aim := {}             # the aim of a pressed aimed ability: {pos} (area) or {unit} (unit)
	var pending_aim := {}
	var dot_t := 0.0
	var threat := {}                 # enemies: hero id -> threat
	var threat_decay_t := 0.0
	var passive := false             # tests: a dummy that never acts (it still takes hits)
	var spec := ""                    # the Wizard's level-25 specialisation: pyromancer / cryomancer
	var burn_mult := 1.0             # Pyromancer: burning deals double damage
	var auto_element := "fire"       # Cryomancer: auto attacks become frost bolts
	var mirror := false              # Mirror Image (visual only: the view draws the copy)
	var block := {}                  # Ice Block / Hellfire in progress: {t, wave_t, def, element, power}
	var charge := {}                 # the Knight's Charge in progress: {target, t, from, def}
	var burn_t := 0.0
	var agent                        # SteerWorld.Agent


var nav
var world
var units := {}
var zones: Array = []               # ground zones: Blizzard / Firestorm {pos, radius, t, tick_t, ticks_left, src, element, bonus}
var projectiles: Array = []         # [{id, src, target, pos, dmg}] flying fireballs
var _next_projectile := 1
var events: Array = []
var time := 0.0
var slots := {}
var next_id := 1
var resource := RESOURCE_START
var layout: Dictionary
var wave_index := -1
var spawn_queue: Array = []         # [{t, kind}]
var next_wave_t := 2.0
var over := ""                      # "", "victory", "defeat"
var _rng_state := 12345
const WAVES := [["goblin", "goblin", "goblin"],
		["skeleton", "skeleton", "goblin", "goblin"],
		["skeleton", "skeleton", "skeleton", "goblin", "goblin", "goblin"]]


func _init(p_layout: Dictionary = {}) -> void:
	layout = p_layout if not p_layout.is_empty() else GameData.stage_layout()
	nav = NavGrid.from_layout(layout)
	world = SteerWorld.new(nav)


func _rand() -> float:
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7fffffff
	return float(_rng_state) / float(0x7fffffff)


# ----------------------------------------------------------------------------- units
func _def(kind: String) -> Dictionary:
	var abilities := GameData.abilities()
	match kind:
		"knight", "rogue":
			var auto: Dictionary = abilities[GameData.classes()["knight"]["auto"]]
			return {"team": 0, "model": "knight", "radius": GameData.hero_radius(kind), "speed": GameData.hero_speed_mps(),
					"cd": auto["cdMax"] * (0.8 if kind == "rogue" else 1.0), "delay": auto["delay"], "lock": auto["animLock"]}
		"wizard":
			var wauto: Dictionary = abilities[GameData.classes()["wizard"]["auto"]]
			return {"team": 0, "model": "knight", "radius": GameData.hero_radius("wizard"), "speed": GameData.hero_speed_mps(),
					"cd": wauto["cdMax"], "delay": wauto["delay"], "lock": 0.8}
		"cleric":
			var cauto: Dictionary = abilities[GameData.classes()["priest"]["auto"]]
			return {"team": 0, "model": "knight", "radius": GameData.hero_radius("priest"), "speed": GameData.hero_speed_mps(),
					"cd": cauto["cdMax"], "delay": cauto["delay"], "lock": 0.8}
		"witch":
			# 3D-only enemy (no 2D data row): a slow caster that borrows the skeleton's auto attack numbers
			var base: Dictionary = _def("skeleton")
			base["model"] = "witch"
			base["radius"] = GameData.enemy_radius("skeleton") * 0.95
			base["speed"] = GameData.enemy_speed_mps("skeleton") * 0.85
			return base
		_:
			var enemy: Dictionary = GameData.enemies()[kind]
			var auto2: Dictionary = abilities[enemy["auto"]]
			return {"team": 1, "model": kind, "radius": GameData.enemy_radius(kind), "speed": GameData.enemy_speed_mps(kind),
					"cd": auto2["cdMax"], "delay": auto2["delay"], "lock": auto2["animLock"]}


func spawn(kind: String, pos: Vector2, label: String = "", gear: Array = [], weapon: String = "") -> Unit:
	var d := _def(kind)
	var u := Unit.new()
	u.id = next_id
	next_id += 1
	u.team = d["team"]
	u.kind = kind
	u.label = label if label != "" else kind
	u.model = d["model"]
	u.gear = gear
	u.weapon = weapon
	u.radius = d["radius"]
	u.speed = d["speed"]
	u.cd_max = d["cd"]
	u.delay = d["delay"]
	u.lock = d["lock"]
	u.max_hp = PLACEHOLDER_HP[kind]
	u.hp = u.max_hp
	u.damage = PLACEHOLDER_DAMAGE[kind]
	u.heading = (-PI / 2.0) if u.team == 1 else (PI / 2.0)   # heroes face +X, enemies face -X
	u.agent = world.add_agent(u.id, pos, u.radius, u.speed)
	u.agent.mode = SteerWorld.Mode.IDLE
	if kind == "knight":
		u.skills = _class_skills("knight")
	elif kind == "wizard":
		set_wizard_build(u, DEFAULT_WIZARD_BUILD)
		u.ranged = true
	elif kind == "cleric":
		u.skills = _class_skills("priest").slice(0, 3)      # three abilities per hero (Director)
		u.ranged = true
		u.heals = true
		u.heal_value = float(GameData.abilities()[GameData.classes()["priest"]["auto"]]["effect"]["value"])
	units[u.id] = u
	if u.team == 1:                                    # 2D createEnemy: start by going after a random hero (threat 1 on it)
		var living: Array = []
		for h in heroes():
			if h.state != State.DEAD:
				living.append(h)
		if not living.is_empty():
			var pick = living[int(_rand() * living.size()) % living.size()]
			u.threat[pick.id] = 1.0
			_set_target(u, pick.id)
	events.append({"type": "spawn", "id": u.id})
	return u


## The Knight's three default actives, read from the exported 2D data (data/abilities.lua rows).
## Knight abilities from the talent tree: ids of 2D ability rows. Only the ones the sandbox implements get a slot (Hamstring, Sunder Armor, Challenging
## Shout); the others (Defend, Charge, Battle Shout) are picked in the tree but not in battle yet. At most three.
func _skills_from_ids(ids: Array) -> Array:
	var out: Array = []
	var abilities := GameData.abilities()
	for id in ids:
		if not SKILL_KINDS.has(id) or not abilities.has(id):
			continue
		var row: Dictionary = abilities[id]
		var kind: String = SKILL_KINDS[id]
		var bars: int = int(row.get("bars", 0))
		out.append({"id": id, "name": row["name"], "kind": kind, "bars": bars, "cost": bars * RESOURCE_PER_BAR, "cd_max": row["cdMax"], "cd": 0.0, "delay": row.get("delay", 0.0),
				"anim": SKILL_ANIM[kind], "row": row, "icon": row.get("iconName", ""), "select": row.get("select", ""), "side": row.get("selectSide", ""), "lock": SKILL_LOCK.get(kind, -1.0)})
	return out.slice(0, 3)


func _class_skills(class_id: String) -> Array:
	var out: Array = []
	var abilities := GameData.abilities()
	for id in GameData.classes()[class_id]["actives"]:
		var row: Dictionary = abilities[id]
		var kind: String = SKILL_KINDS[id]
		var bars: int = int(row.get("bars", 0))               # the abilities marked bh = true cost no bars, only a cooldown
		out.append({"id": id, "name": row["name"], "kind": kind, "bars": bars, "cost": bars * RESOURCE_PER_BAR,
				"cd_max": row["cdMax"], "cd": 0.0, "delay": row["delay"], "anim": SKILL_ANIM[kind], "row": row,
				"icon": ICON_OVERRIDE.get(id, row.get("iconName", "")), "select": row.get("select", ""), "side": row.get("selectSide", ""), "lock": SKILL_LOCK.get(kind, -1.0)})
	return out


## The Wizard's skill tree (data/wizard_talents.json): `build` maps a tier level ("1", "10", "20", "25") to the option picked there.
## Abilities come in tier order (Q, W, E); the level-25 specialisation swaps spells (Pyromancer: Blizzard -> Firestorm, Ice Block -> Hellfire,
## burning x2; Cryomancer: Explosion -> Ice Shock, auto attacks -> frost bolts). Mirror Image is a passive (the view draws the copy).
func set_wizard_build(u: Unit, build: Dictionary) -> void:
	var wt := GameData.wizard_talents()
	var picked: Array = []
	u.spec = ""
	for tier in wt["choices"]:
		var pick: String = build.get(str(int(tier["level"])), "")
		for opt in tier["options"]:
			if opt["id"] == pick:
				if opt.has("ability"):
					picked.append(opt["ability"])
				if opt.has("spec"):
					u.spec = opt["spec"]
	var spec_def: Dictionary = wt["specs"].get(u.spec, {})
	u.burn_mult = float(spec_def.get("burnMultiplier", 1.0))
	u.auto_element = String(spec_def.get("autoElement", "fire"))
	u.mirror = false
	u.skills = []
	for ability_id in picked:
		var final_id: String = spec_def.get("replaces", {}).get(ability_id, ability_id)
		var def: Dictionary = wt["abilities"][final_id]
		if def.get("passive", false):
			if def["kind"] == "mirror":
				u.mirror = true
			continue
		var bars: int = int(def["bars"])
		u.skills.append({"id": final_id, "name": def["name"], "kind": def["kind"], "bars": bars, "cost": bars * RESOURCE_PER_BAR, "cd_max": float(def["cdMax"]),
				"cd": 0.0, "delay": 0.4, "anim": "StaffRaise", "row": {"effect": def["effect"]}, "icon": def["icon"], "select": def["select"], "side": "",
				"lock": 0.95, "element": def["element"], "element_def": def})


## A party entry: {kind, label, gear[], weapon, build{} (the Wizard's skill tree picks), abilities[] (ability ids from the talent tree), hp}.
const TEST_PARTY := [
	{"kind": "knight", "label": "Knight", "gear": ["helm_iron", "armor_scale_mail"], "weapon": "sword_long"},
	{"kind": "cleric", "label": "Cleric", "gear": ["hood_cloth", "armor_cloak"], "weapon": "rod_cleric"},
	{"kind": "wizard", "label": "Wizard", "gear": ["hat_wizard_blue", "armor_wizard_blue"], "weapon": "staff_oak"},
	{"kind": "rogue", "label": "Rogue", "gear": ["hood_cloth", "armor_cloak"], "weapon": "dagger_iron"}]
const DEFAULT_PARTY := [
	{"kind": "knight", "label": "Knight", "gear": ["helm_iron", "armor_scale_mail"], "weapon": "sword_long"},
	{"kind": "wizard", "label": "Wizard", "gear": ["hat_wizard_blue", "armor_wizard_blue"], "weapon": "staff_oak"}]
static var dev_party: Array = DEFAULT_PARTY            # what the sandbox spawns when it was not started from the menus (tests set TEST_PARTY)


## Only heroes with a full skill tree are playable for now (Knight, Wizard), three abilities each.
func spawn_party(party: Array = []) -> void:
	if party.is_empty():
		party = dev_party
	var spots: Array = layout["spawns"]["party"]
	for i in mini(party.size(), spots.size()):
		var spec: Dictionary = party[i]
		var s: Dictionary = spots[i]
		var u := spawn(spec["kind"], Vector2(s["x"], s["z"]), spec.get("label", ""), spec.get("gear", []), spec.get("weapon", ""))
		u.cd_max *= float(spec.get("weapon_speed", 1.0))                      # weapon speed scales the auto-attack cooldown only
		if spec.has("build") and not spec["build"].is_empty():
			set_wizard_build(u, spec["build"])
		if spec.has("abilities"):
			u.skills = _skills_from_ids(spec["abilities"])
		if spec.get("hp", 0) > 0:
			u.max_hp = float(spec["hp"])
			u.hp = u.max_hp


func heroes() -> Array:
	var out: Array = []
	for id in units:
		if units[id].team == 0:
			out.append(units[id])
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func alive(id: int) -> bool:
	return units.has(id) and units[id].state != State.DEAD


func _dist(a: Unit, b: Unit) -> float:
	return a.agent.pos.distance_to(b.agent.pos)


func in_range(a: Unit, b: Unit) -> bool:
	if a.ranged:
		return true                        # no range requirement
	return _dist(a, b) <= a.radius + b.radius + REACH


# ------------------------------------------------------------------------- commands
## Player: walk to a point (like clicking the ground).
func command_move(id: int, point: Vector2) -> void:
	if not alive(id):
		return
	var u: Unit = units[id]
	_interrupt(u)
	_drop_target(u)
	u.ordered = false
	u.move_order = true
	u.move_point = nav.push_out(point, u.radius)
	u.move_issued = false     # issued as soon as the unit is free (a swing in progress finishes first)


## The 2D `skills.interrupt`: a move order discards a default action that has not landed yet, puts an ability that has not landed
## back at the FRONT of the queue (still paid, cooldown still running; it winds up again from the start), and resets the auto timer.
func _interrupt(u: Unit) -> void:
	if u.pending_t >= 0.0:
		if u.pending_skill >= 0:
			u.queued_skill = u.pending_skill
			u.queued_aim = u.pending_aim
		u.pending_t = -1.0
		u.pending_skill = -1
		if u.state == State.ATTACK:
			u.state = State.IDLE
			u.state_t = 0.0
	u.cd = 0.0


## Player: click a unit (like clicking an enemy; for a healer, an ally).
func command_attack(id: int, target_id: int) -> void:
	if not alive(id) or not alive(target_id):
		return
	var u: Unit = units[id]
	if (units[target_id].team == u.team) != u.heals:
		return                                                    # a healer is ordered onto allies, everyone else onto enemies
	var had_target := u.target >= 0 and alive(u.target)
	u.move_order = false
	u.ordered = true
	_set_target(u, target_id)
	if not had_target:
		u.cd = 0.0                           # 2D: a hero given a target while it had none acts as soon as it is in range


## Player: press an ability key (0-based slot). PAY AT PRESS (the 2D rule): the cost is spent and the cooldown starts
## now; the ability fires when the hero is free (and, for Hamstring, in reach of its target). Returns false when
## nothing was spent (dead, no such skill, on cooldown, not enough resource, or a targeted skill with no enemy).
func command_skill(id: int, slot: int, aim: Dictionary = {}) -> bool:
	if not alive(id):
		return false
	var u: Unit = units[id]
	if slot < 0 or slot >= u.skills.size():
		return false
	var sk: Dictionary = u.skills[slot]
	if sk["cd"] > 0.0 or resource < sk["cost"] or u.queued_skill >= 0:
		return false
	if sk["select"] == "area" and not aim.has("pos"):
		return false
	if sk["select"] == "unit":
		if not aim.has("unit") or not alive(aim["unit"]):
			return false
		var same_team: bool = units[aim["unit"]].team == u.team
		if same_team != (sk["side"] == "allies"):                # allies for healing / buffs, enemies otherwise
			return false
	resource -= sk["cost"]                    # 2D: pay at press; a targeted ability waits in the queue for a target in reach
	sk["cd"] = sk["cd_max"]
	u.queued_skill = slot
	u.queued_aim = aim
	events.append({"type": "press", "id": id, "skill": sk["name"], "t": time})
	return true


## What a pressed ability needs from the player before it can go off: "" (nothing), "area" (place it) or "unit" (click a unit).
## Returns "none" when the press would be refused (cooldown, resource), "" / "area" / "unit" otherwise. Nothing is spent here.
func skill_select(id: int, slot: int) -> String:
	if not alive(id):
		return "none"
	var u: Unit = units[id]
	if slot < 0 or slot >= u.skills.size():
		return "none"
	var sk: Dictionary = u.skills[slot]
	if sk["cd"] > 0.0 or resource < sk["cost"] or u.queued_skill >= 0:
		return "none"
	return "area" if sk["select"] == "area" else ("unit" if sk["select"] == "unit" else "")


func _nearest_enemy(u: Unit) -> int:
	var best := -1
	var best_d := INF
	for id in units:
		var o: Unit = units[id]
		if o.team != u.team and o.state != State.DEAD and _dist(u, o) < best_d:
			best_d = _dist(u, o)
			best = id
	return best


func _set_target(u: Unit, target_id: int) -> void:
	if u.target == target_id:
		return
	_drop_target(u)
	u.target = target_id


func _drop_target(u: Unit) -> void:
	if u.claimed >= 0 and slots.has(u.claimed):
		slots[u.claimed].release(u.id)
	u.claimed = -1
	u.target = -1


# ------------------------------------------------------------------------------ tick
func tick() -> void:
	time += DT
	resource = minf(RESOURCE_MAX, resource + DT)         # the 2D battle: +1 per second
	_run_waves()
	for id in units.keys():
		if units.has(id):
			_step_unit(units[id])
	_resolve_hits()
	_update_projectiles()
	_update_zones()
	_rebalance_slots()
	world.tick(DT)
	for id in units.keys():
		var u: Unit = units[id]
		if u.state != State.DEAD:
			_update_heading(u)
	_cleanup_corpses()
	_check_over()


func _step_unit(u: Unit) -> void:
	if u.state == State.DEAD:
		u.corpse_t += DT
		return
	u.cd = maxf(0.0, u.cd - DT)
	for sk in u.skills:
		sk["cd"] = maxf(0.0, sk["cd"] - DT)
	_tick_statuses(u)
	if not u.block.is_empty():
		_tick_block(u)
	if u.passive:
		world.hold(u.agent, true)
		return
	u.agent.max_speed = u.speed * (1.0 - (u.statuses["SLOW"]["mag"] if u.statuses.has("SLOW") else 0.0))
	if not u.charge.is_empty() and not u.statuses.has("STUN"):
		_tick_charge(u)
		return
	if u.statuses.has("STUN"):                          # stunned: cannot move, swing or cast; a swing in progress is lost
		u.pending_t = -1.0
		u.pending_skill = -1
		u.state = State.IDLE
		world.hold(u.agent, true)
		return
	u.state_t += DT
	if u.state == State.ATTACK and u.state_t >= u.cur_lock:
		u.state = State.IDLE
		u.state_t = 0.0
	elif u.state == State.HIT and u.state_t >= HIT_STAGGER:
		u.state = State.IDLE
		u.state_t = 0.0
	if u.state == State.ATTACK or u.state == State.HIT:
		world.hold(u.agent, true)
		return
	if u.agent.mode == SteerWorld.Mode.HELD:
		world.hold(u.agent, false)
	# a pressed ability that needs no target fires as soon as the hero is free
	if u.queued_skill >= 0 and u.skills[u.queued_skill]["kind"] != "hamstring":
		_start_cast(u, u.queued_skill, null)
		return
	_choose_target(u)
	if u.target >= 0 and alive(u.target):
		var t: Unit = units[u.target]
		if in_range(u, t):
			world.hold(u.agent, true)
			u.state = State.IDLE
			if u.queued_skill >= 0:
				_start_cast(u, u.queued_skill, t)
			elif u.cd <= 0.0:
				_start_attack(u, t)
		else:
			_approach(u, t)
			u.state = State.MOVE
		return
	if u.move_order:
		if not u.move_issued:
			world.order_move(u.agent, u.move_point)
			u.move_issued = true
		if u.agent.arrived:
			u.move_order = false
			u.state = State.IDLE
		else:
			u.state = State.MOVE
		return
	u.state = State.MOVE if u.agent.mode == SteerWorld.Mode.MOVING and not u.agent.arrived else State.IDLE


## TARGETING, as the 2D game does it (systems.lua, screens/encounter.lua, combat.registerHit):
##  * a hero has NO target of its own: it gets one only when the player CLICKS a unit (enemies for attackers, allies for a healer,
##    itself included), or when it is hit while it has no target and is not walking (it fights back);
##  * a target that dies is dropped by everyone aimed at it; a hero then stands idle until it is told what to do;
##  * an enemy aims at the hero it holds the highest THREAT against, every frame, with no hysteresis. The table decays x0.9 per
##    second. It starts on a random hero (threat 1); with an empty table it takes the first living hero.
func _choose_target(u: Unit) -> void:
	if u.target >= 0 and not alive(u.target):
		_drop_target(u)
		u.ordered = false
	if u.team == 0:
		_auto_assist(u)
		return
	_choose_by_threat(u)


## Director's addition to the 2D rules: an IDLE playable character (no target, not walking, not a healer) auto-targets an enemy
## that a party member is attacking, as long as that enemy is inside AUTO_TARGET_RADIUS of it (the same radius for ranged heroes,
## whatever their reach). The other auto-target (the first enemy that hits an idle hero) is in _apply_hit.
func _auto_assist(u: Unit) -> void:
	if u.heals or u.target >= 0 or u.move_order or u.state == State.DEAD or u.agent.mode == SteerWorld.Mode.MOVING:
		return
	var best := -1
	var best_d := INF
	for id in units:
		var a: Unit = units[id]
		if a == u or a.team != 0 or a.heals or a.state == State.DEAD or a.target < 0 or not alive(a.target):
			continue
		var t: Unit = units[a.target]
		if a.state != State.ATTACK and not in_range(a, t):
			continue                                   # that party member is not attacking yet (still walking up to its target)
		var d := _dist(u, t)
		if d <= AUTO_TARGET_RADIUS and d < best_d:
			best_d = d
			best = t.id
	if best >= 0:
		_set_target(u, best)


func _choose_by_threat(u: Unit) -> void:
	u.threat_decay_t += DT
	if u.threat_decay_t >= 1.0:
		u.threat_decay_t = 0.0
		for hid in u.threat:
			u.threat[hid] = u.threat[hid] * 0.9
	var top := -1
	var top_threat := -1.0
	for hid in u.threat:
		if alive(hid) and u.threat[hid] > top_threat:
			top_threat = u.threat[hid]
			top = hid
	if top >= 0:
		_set_target(u, top)
	elif u.target < 0:
		for h in heroes():
			if h.state != State.DEAD:
				_set_target(u, h.id)
				break


func _approach(u: Unit, t: Unit) -> void:
	if not slots.has(t.id):
		slots[t.id] = Slots.new()
	var ring = slots[t.id]
	var s: Vector2i = ring.claim(t.agent.pos, t.radius, u.id, u.agent.pos, u.radius)
	u.claimed = t.id
	if s.x < 0:
		world.update_goal(u.agent, t.agent.pos)
		return
	var goal: Vector2 = ring.position_of(t.agent.pos, s.x, s.y)
	var via: Vector2 = ring.approach_point(t.agent.pos, s.x, s.y)
	if u.agent.mode != SteerWorld.Mode.MOVING or not u.agent.goal_set:
		world.order_move(u.agent, goal, -1, via)
		u.agent.arrive_radius = 0.2
		u.agent.accept_radius = 0.6
	else:
		world.update_goal(u.agent, goal, via)


func _start_attack(u: Unit, t: Unit) -> void:
	u.state = State.ATTACK
	u.state_t = 0.0
	u.cd = u.cd_max
	u.pending_t = u.delay
	u.pending_target = t.id
	u.pending_skill = -1
	u.cur_lock = u.lock
	u.swing_anim = "StaffCast" if u.ranged else ("Cast" if u.kind == "witch" else "Attack1")
	u.swing += 1
	u.heading = _turn_toward(u.heading, atan2(t.agent.pos.x - u.agent.pos.x, t.agent.pos.y - u.agent.pos.y), PI)
	events.append({"type": "attack", "id": u.id, "target": t.id, "t": time})


func _resolve_hits() -> void:
	for id in units.keys():
		var u: Unit = units[id]
		if u.pending_t < 0.0 or u.state == State.DEAD:
			continue
		u.pending_t -= DT
		if u.pending_t > 0.0:
			continue
		u.pending_t = -1.0
		if u.pending_skill >= 0:
			_resolve_skill(u)
		else:
			_resolve_basic(u)


func _resolve_basic(u: Unit) -> void:
	var t: Unit = units.get(u.pending_target)
	if t == null or t.state == State.DEAD:
		return
	if u.heals:                           # the Cleric's auto action: heal the target (instant, as the 2D PriestAutoHeal)
		_heal(u, t, u.damage * u.heal_value)
		return
	if u.ranged:                          # a fireball: it hits when it arrives (_update_projectiles)
		if u.kind == "wizard":
			_launch_projectile(u, t, _roll(u, t, 0.0), u.auto_element, u.auto_element, false)     # fireball (burns) or, for the Cryomancer, a frost bolt
		else:
			_launch_projectile(u, t, _roll(u, t, 0.0), "", "fire", false)
		return
	if _dist(u, t) > u.radius + t.radius + REACH + 0.6:
		events.append({"type": "miss", "id": u.id, "target": t.id, "t": time})
		return
	_apply_hit(u, t, _roll(u, t, 0.0))


## Damage of one blow: the attacker's base x (1 + the ability's bonus), less WEAKEN on the attacker, more VULNERABILITY on the
## victim, +-10% spread. (The 2D engine's power/defence formula is not ported yet: placeholder numbers.)
func _launch_projectile(src: Unit, t: Unit, dmg: float, element: String, style: String, ability: bool) -> void:
	var pid := _next_projectile
	_next_projectile += 1
	projectiles.append({"id": pid, "src": src.id, "target": t.id, "pos": src.agent.pos, "dmg": dmg, "element": element, "style": style, "ability": ability})
	events.append({"type": "projectile", "pid": pid, "id": src.id, "target": t.id, "style": style, "t": time})


## Ice Block / Hellfire: while it lasts, a wave every `waveEvery` seconds around the caster.
## The Knight's Charge (2D abilities.chargeSystem): faster, locked on, ends on contact or after maxTime / when the target dies.
func _tick_charge(u: Unit) -> void:
	var c: Dictionary = u.charge
	var t: Unit = units.get(c["target"])
	c["t"] += DT
	if t == null or t.state == State.DEAD or c["t"] > float(c["def"]["maxTime"]):
		u.charge = {}
		return
	if in_range(u, t):
		var far: float = minf(1.0, c["from"].distance_to(u.agent.pos) / (float(c["def"]["fullDistance"]) / GameData.PX_PER_M))
		var mult: float = float(c["def"]["damage"]) * (1.0 + float(c["def"]["bonusDamage"]) * far)
		u.charge = {}
		world.hold(u.agent, true)
		_apply_hit(u, t, _roll(u, t, mult - 1.0), true)
		return
	u.agent.max_speed = u.speed * float(c["def"]["speed"])
	_approach(u, t)
	u.state = State.MOVE


func _tick_block(u: Unit) -> void:
	u.block["t"] -= DT
	u.block["wave_t"] += DT
	var def: Dictionary = u.block["def"]
	if u.block["wave_t"] >= float(def["waveEvery"]):
		u.block["wave_t"] -= float(def["waveEvery"])
		var radius: float = float(def["rx"]) / GameData.PX_PER_M
		var element: String = u.block["element"]
		events.append({"type": "area", "pos": u.agent.pos, "radius": radius, "kind": "frostwave" if element == "frost" else "firewave", "t": time})
		for id in units.keys():
			var o: Unit = units[id]
			if o.team != u.team and o.state != State.DEAD and o.agent.pos.distance_to(u.agent.pos) - o.radius <= radius:
				if element == "frost":
					_apply_element(u, o, "frost", 0.0)               # slows and chills (the stagger half is not ported yet)
				else:
					_apply_element(u, o, "fire", u.damage * float(def["burnPower"]))
	if u.block["t"] <= 0.0:
		u.block = {}


func _update_zones() -> void:
	for z in zones.duplicate():
		z["t"] -= DT
		z["tick_t"] += DT
		if z["tick_t"] >= 1.0 and z["ticks_left"] > 0:
			z["tick_t"] -= 1.0
			z["ticks_left"] -= 1
			var src: Unit = units.get(z["src"])
			if src != null:
				events.append({"type": "zone_tick", "pos": z["pos"], "radius": z["radius"], "element": z["element"], "t": time})
				for id in units.keys():
					var o: Unit = units[id]
					if o.team != src.team and o.state != State.DEAD and o.agent.pos.distance_to(z["pos"]) - o.radius <= z["radius"]:
						var d := _roll(src, o, z["bonus"])
						_apply_hit(src, o, d, true)
						_apply_element(src, o, z["element"], d)
		if z["t"] <= 0.0 or z["ticks_left"] <= 0:
			zones.erase(z)


func _update_projectiles() -> void:
	for pr in projectiles.duplicate():
		var t: Unit = units.get(pr["target"])
		var src: Unit = units.get(pr["src"])
		if t == null or t.state == State.DEAD:
			projectiles.erase(pr)
			events.append({"type": "projectile_end", "pid": pr["id"], "hit": false})
			continue
		var to: Vector2 = t.agent.pos - pr["pos"]
		var step := PROJECTILE_SPEED * DT
		if to.length() <= step + t.radius:
			projectiles.erase(pr)
			events.append({"type": "projectile_end", "pid": pr["id"], "hit": true})
			if src != null:
				_apply_hit(src, t, pr["dmg"], pr.get("ability", false))
				if pr.get("element", "") != "":
					_apply_element(src, t, pr["element"], pr["dmg"])
		else:
			pr["pos"] = pr["pos"] + to.normalized() * step


func _heal(src: Unit, t: Unit, amount: float) -> void:
	var before := t.hp
	t.hp = minf(t.max_hp, t.hp + amount)
	events.append({"type": "heal", "id": src.id, "target": t.id, "amount": t.hp - before, "t": time})


func _roll(attacker: Unit, victim: Unit, bonus: float) -> float:
	var weaken: float = attacker.statuses["WEAKEN"]["mag"] if attacker.statuses.has("WEAKEN") else 0.0
	var vuln: float = victim.statuses["VULNERABILITY"]["mag"] if victim.statuses.has("VULNERABILITY") else 0.0
	var buff: float = attacker.statuses["ATK_BUFF"]["mag"] if attacker.statuses.has("ATK_BUFF") else 0.0     # Power Infusion
	var shield: float = victim.statuses["SHIELD"]["mag"] if victim.statuses.has("SHIELD") else 0.0         # Shield: a fixed share removed
	if victim.statuses.has("DEF_BUFF"):
		shield += 0.5 * float(victim.statuses["DEF_BUFF"]["mag"])                                            # Defend [tuned placeholder]
	return attacker.damage * (1.0 + bonus + buff) * (1.0 - weaken) * (1.0 + vuln) * (1.0 - shield) * (0.9 + 0.2 * _rand())


func _intimidation() -> float:
	# Knight passive: every hit adds threat worth 50% of his defence (data/classes.lua traits.threatFromDef)
	return GameData.classes()["knight"]["traits"]["threatFromDef"] * GameData.classes()["knight"]["base"]["defense"]


func _apply_hit(attacker: Unit, t: Unit, dmg: float, ability: bool = false) -> void:
	if t.statuses.has("INVULN"):
		return                                          # Ice Block / Hellfire: nothing can hurt the caster
	t.hp -= dmg
	events.append({"type": "hit", "id": attacker.id, "target": t.id, "dmg": dmg, "ability": ability, "t": time})
	if t.team == 1 and attacker.team == 0:
		t.threat[attacker.id] = t.threat.get(attacker.id, 0.0) + dmg * 0.5 + (_intimidation() if attacker.kind == "knight" else 0.0)    # 2D combat.registerHit: 50%% of the damage
	if t.hp <= 0.0:
		_die(t)
		return
	if t.state != State.ATTACK:
		t.state = State.HIT
		t.state_t = 0.0
	var away: Vector2 = (t.agent.pos - attacker.agent.pos).normalized()
	world.knock(t.agent, away * HIT_KNOCK)
	if t.team == 0 and not t.heals and t.target < 0 and not t.move_order and attacker.state != State.DEAD \
			and _dist(t, attacker) <= AUTO_TARGET_RADIUS:
		_set_target(t, attacker.id)                    # 2D combat.registerHit: hit with no target while not walking: fight back (inside the radius)
	elif t.team == 1 and t.target < 0 and attacker.state != State.DEAD:
		_set_target(t, attacker.id)


## FIRE applies BURN (a damage over time of 15% of the damage dealt over 5 s; the Pyromancer's burning deals double); FROST applies SLOW and extra
## damage taken for 5 s (data/wizard_talents.json rules).
func _apply_element(src: Unit, t: Unit, element: String, dmg: float) -> void:
	if t.state == State.DEAD:
		return
	var rules: Dictionary = GameData.wizard_talents()["rules"]
	if element == "fire":
		var per_sec: float = dmg * float(rules["burnShare"]) / float(rules["burnSeconds"]) * src.burn_mult
		_apply_status(t, "BURN", per_sec, float(rules["burnSeconds"]), src.id)
	elif element == "frost":
		_apply_status(t, "SLOW", float(rules["frostSlow"]), float(rules["frostSeconds"]), src.id)
		_apply_status(t, "VULNERABILITY", float(rules["frostVulnerability"]), float(rules["frostSeconds"]), src.id)


func _apply_status(t: Unit, name: String, magnitude: float, seconds: float, src: int = -1) -> void:
	t.statuses[name] = {"t": seconds, "mag": magnitude, "src": src}
	events.append({"type": "status", "id": t.id, "name": name, "on": true, "t": time})


func _tick_statuses(u: Unit) -> void:
	if u.statuses.has("BURN") and not u.statuses.has("INVULN"):
		u.burn_t += DT
		if u.burn_t >= 1.0:
			u.burn_t -= 1.0
			var burn: float = float(u.statuses["BURN"]["mag"])
			u.hp -= burn
			events.append({"type": "dot", "id": u.id, "dmg": burn, "t": time})
			if u.hp <= 0.0:
				_die(u)
				return
	if u.statuses.has("DOT"):                           # damage over time: a tick every DOT_TICK, worth mag x the caster's power per second
		u.dot_t += DT
		if u.dot_t >= DOT_TICK:
			u.dot_t -= DOT_TICK
			var src_unit: Unit = units.get(u.statuses["DOT"]["src"])
			var amount: float = float(u.statuses["DOT"]["mag"]) * (src_unit.damage if src_unit != null else 30.0) * DOT_TICK
			u.hp -= amount
			events.append({"type": "dot", "id": u.id, "dmg": amount, "t": time})
			if u.hp <= 0.0:
				_die(u)
				return
	for name in u.statuses.keys():
		u.statuses[name]["t"] -= DT
		if u.statuses[name]["t"] <= 0.0:
			u.statuses.erase(name)
			events.append({"type": "status", "id": u.id, "name": name, "on": false, "t": time})


func _start_cast(u: Unit, slot: int, target) -> void:
	var sk: Dictionary = u.skills[slot]
	u.queued_skill = -1
	u.state = State.ATTACK
	u.state_t = 0.0
	u.pending_skill = slot
	u.pending_t = sk["delay"]
	u.pending_target = target.id if target != null else -1
	u.swing_anim = sk["anim"]
	u.cur_lock = (sk["lock"] if sk["lock"] > 0.0 else sk["delay"] + 0.3) if sk["anim"] != "" else 0.0
	u.pending_aim = u.queued_aim
	u.queued_aim = {}
	if sk["anim"] != "":
		u.swing += 1
	if target != null:
		u.heading = _turn_toward(u.heading, atan2(target.agent.pos.x - u.agent.pos.x, target.agent.pos.y - u.agent.pos.y), PI)
	elif u.pending_aim.has("pos"):
		var ap: Vector2 = u.pending_aim["pos"]
		u.heading = _turn_toward(u.heading, atan2(ap.x - u.agent.pos.x, ap.y - u.agent.pos.y), PI)
	elif u.pending_aim.has("unit") and alive(u.pending_aim["unit"]):
		var ap2: Vector2 = units[u.pending_aim["unit"]].agent.pos
		u.heading = _turn_toward(u.heading, atan2(ap2.x - u.agent.pos.x, ap2.y - u.agent.pos.y), PI)
	events.append({"type": "cast", "id": u.id, "skill": sk["name"], "target": u.pending_target, "t": time})


func _resolve_skill(u: Unit) -> void:
	var sk: Dictionary = u.skills[u.pending_skill]
	u.pending_skill = -1
	var effect: Dictionary = sk["row"].get("effect", {})
	match sk["kind"]:
		"hamstring":
			# 200% damage to the target and WEAKEN (-30% damage dealt) for 10 s
			var t: Unit = units.get(u.pending_target)
			if t == null or t.state == State.DEAD or _dist(u, t) > u.radius + t.radius + REACH + 0.6:
				events.append({"type": "miss", "id": u.id, "target": u.pending_target, "t": time})
				return
			_apply_hit(u, t, _roll(u, t, effect["buffMods"]["0"]), true)
			if t.state != State.DEAD:
				var st: Dictionary = effect["onHit"]["effect"]
				_apply_status(t, "WEAKEN", st["magnitude"], st["duration"])
		"sunder":
			# 150% damage and VULNERABILITY (+15% damage taken) for 10 s to every enemy around the Knight
			var inner: Dictionary = effect["inner"]
			var radius: float = effect["rx"] / GameData.PX_PER_M      # the 2D ellipse is a circle on the ground
			var centre: Vector2 = u.agent.pos
			events.append({"type": "area", "pos": centre, "radius": radius, "kind": "sunder", "t": time})
			for id in units.keys():
				var o: Unit = units[id]
				if o.team != u.team and o.state != State.DEAD and o.agent.pos.distance_to(centre) - o.radius <= radius:
					_apply_hit(u, o, _roll(u, o, inner["buffMods"]["0"]), true)
					if o.state != State.DEAD:
						var st2: Dictionary = inner["onHit"]["effect"]
						_apply_status(o, "VULNERABILITY", st2["magnitude"], st2["duration"])
		"nuke":
			# Explosion / Ice Shock: 250% damage to every enemy in the area at the aimed spot; fire burns, frost chills
			var nradius: float = float(effect["rx"]) / GameData.PX_PER_M
			var npos: Vector2 = u.pending_aim.get("pos", u.agent.pos)
			events.append({"type": "area", "pos": npos, "radius": nradius, "kind": "explosion" if sk["element"] == "fire" else "frostwave", "t": time})
			for id in units.keys():
				var o: Unit = units[id]
				if o.team != u.team and o.state != State.DEAD and o.agent.pos.distance_to(npos) - o.radius <= nradius:
					var d := _roll(u, o, float(effect["damage"]) - 1.0)
					_apply_hit(u, o, d, true)
					_apply_element(u, o, sk["element"], d)
		"bolt":
			# Iridescent Bolt: a purple fireball, 500% damage to the clicked enemy when it lands (fire: burns)
			var bt: Unit = units.get(u.pending_aim.get("unit", -1))
			if bt == null or bt.state == State.DEAD:
				return
			_launch_projectile(u, bt, _roll(u, bt, float(effect["damage"]) - 1.0), sk["element"], "purple", true)
		"ice_block":
			# invulnerable for `duration`; every `waveEvery` seconds a wave of frost (or fire, as Hellfire) rolls out from the caster
			u.block = {"t": float(effect["duration"]), "wave_t": 0.0, "def": effect, "element": sk["element"]}
			_apply_status(u, "INVULN", 1.0, float(effect["duration"]), u.id)
			events.append({"type": "area", "pos": u.agent.pos, "radius": 1.6, "kind": "iceblock" if sk["element"] == "frost" else "hellfire", "t": time})
		"teleport":
			# blink to the chosen spot; lightning at the start and the end stuns enemies around each for 1 s
			var tp: Vector2 = u.pending_aim.get("pos", u.agent.pos)
			var tradius: float = float(effect["rx"]) / GameData.PX_PER_M
			var start: Vector2 = u.agent.pos
			var end: Vector2 = nav.push_out(tp, u.radius)
			for strike in [start, end]:
				events.append({"type": "lightning", "pos": strike, "radius": tradius, "t": time})
				for id in units.keys():
					var o2: Unit = units[id]
					if o2.team != u.team and o2.state != State.DEAD and o2.agent.pos.distance_to(strike) - o2.radius <= tradius:
						_apply_status(o2, "STUN", 1.0, float(effect["stun"]), u.id)
			u.agent.pos = end
			u.agent.vel = Vector2.ZERO
			u.agent.kvel = Vector2.ZERO
			world.hold(u.agent, true)
			events.append({"type": "teleport", "id": u.id, "from": start, "to": end, "t": time})
		"zone":
			# Blizzard / Firestorm: an area twice the Explosion's; `ticks` ticks of damage, one per second, for `duration`
			var zpos: Vector2 = u.pending_aim.get("pos", u.agent.pos)
			var zrad: float = float(effect["rx"]) / GameData.PX_PER_M
			zones.append({"pos": zpos, "radius": zrad, "t": float(effect["duration"]), "tick_t": 0.0, "ticks_left": int(effect["ticks"]), "src": u.id,
					"element": sk["element"], "bonus": float(effect["damage"]) - 1.0})
			events.append({"type": "area", "pos": zpos, "radius": zrad, "kind": "blizzard" if sk["element"] == "frost" else "firestorm", "t": time})
		"groupheal":
			for o in units.values():
				if o.team == u.team and o.state != State.DEAD:
					_heal(u, o, u.damage * float(effect["value"]))
			events.append({"type": "area", "pos": u.agent.pos, "radius": 99.0, "kind": "groupheal", "t": time})
		"shield", "infuse":
			var ally: Unit = units.get(u.pending_aim.get("unit", -1))
			if ally == null or ally.state == State.DEAD:
				return
			_apply_status(ally, effect["index"], effect["magnitude"], effect["duration"], u.id)
			events.append({"type": "area", "pos": ally.agent.pos, "radius": 1.6, "kind": sk["kind"], "t": time})
		"angel":
			# a holy burst around the Cleric: damage and a hard knockback on every enemy in 3.9 m
			var arad: float = effect["rx"] / GameData.PX_PER_M
			events.append({"type": "area", "pos": u.agent.pos, "radius": arad, "kind": "angel", "t": time})
			for id in units.keys():
				var o2: Unit = units[id]
				if o2.team != u.team and o2.state != State.DEAD and o2.agent.pos.distance_to(u.agent.pos) - o2.radius <= arad:
					var away2: Vector2 = (o2.agent.pos - u.agent.pos).normalized()
					_apply_hit(u, o2, _roll(u, o2, 0.0), true)
					if o2.state != State.DEAD:
						world.knock(o2.agent, away2 * KNOCK_ANGEL)
		"defend":
			# DEF_BUFF: +30% defence for 10 s on the Knight (placeholder effect until the defence formula is ported: -15% damage taken)
			_apply_status(u, "DEF_BUFF", float(effect["magnitude"]), float(effect["duration"]), u.id)
			events.append({"type": "area", "pos": u.agent.pos, "radius": 1.6, "kind": "defend", "t": time})
		"battleshout":
			# ATK_BUFF +20% damage for 10 s on every living ally
			var inner_b: Dictionary = effect["inner"]
			for o in units.values():
				if o.team == u.team and o.state != State.DEAD:
					_apply_status(o, "ATK_BUFF", float(inner_b["magnitude"]), float(inner_b["duration"]), u.id)
					events.append({"type": "area", "pos": o.agent.pos, "radius": 1.4, "kind": "infuse", "t": time})
		"charge":
			# the Knight runs at the clicked enemy at 4x speed and hits it for 200% (up to 300% the farther he ran) on arrival
			var ct: Unit = units.get(u.pending_aim.get("unit", -1))
			if ct == null or ct.state == State.DEAD:
				return
			u.charge = {"target": ct.id, "t": 0.0, "from": u.agent.pos, "def": sk["row"]["charge"]}
			u.move_order = false
			u.ordered = true
			_set_target(u, ct.id)
		"shout":
			# +350 threat on every living enemy: they turn on the Knight
			events.append({"type": "area", "pos": u.agent.pos, "radius": 6.0, "kind": "shout", "t": time})
			for o in units.values():
				if o.team != u.team and o.state != State.DEAD:
					o.threat[u.id] = o.threat.get(u.id, 0.0) + effect["flat"]


func _die(u: Unit) -> void:
	u.state = State.DEAD
	u.corpse_t = 0.0
	u.pending_t = -1.0
	_drop_target(u)
	for other in units.values():
		if other.target == u.id:
			other.ordered = false
			_drop_target(other)
	slots.erase(u.id)
	world.agents.erase(u.agent)
	events.append({"type": "death", "id": u.id, "t": time})


func _cleanup_corpses() -> void:
	for id in units.keys():
		var u: Unit = units[id]
		if u.state == State.DEAD and u.corpse_t >= CORPSE_TIME:
			units.erase(id)
			events.append({"type": "remove", "id": id})


func _rebalance_slots() -> void:
	for tid in slots.keys():
		if not alive(tid):
			continue
		var positions := {}
		for id in units:
			positions[id] = units[id].agent.pos
		slots[tid].rebalance(units[tid].agent.pos, positions)


func _turn_toward(current: float, target: float, max_step: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	return current + clampf(diff, -max_step, max_step)


func _update_heading(u: Unit) -> void:
	var v: Vector2 = u.agent.vel
	if v.length() > 0.4:
		u.heading = _turn_toward(u.heading, atan2(v.x, v.y), TURN_RATE * DT)
	elif u.target >= 0 and alive(u.target):
		var t: Unit = units[u.target]
		var d: Vector2 = t.agent.pos - u.agent.pos
		if d.length() > 0.01:
			u.heading = _turn_toward(u.heading, atan2(d.x, d.y), TURN_RATE * DT)


# ------------------------------------------------------------------------------ waves
func _run_waves() -> void:
	for q in spawn_queue.duplicate():
		if time >= q["t"]:
			spawn_queue.erase(q)
			_spawn_enemy(q["kind"], q["i"])
	if over != "":
		return
	var enemies_left := spawn_queue.size()
	for u in units.values():
		if u.team == 1 and u.state != State.DEAD:
			enemies_left += 1
	if enemies_left == 0:
		if next_wave_t < 0.0:
			next_wave_t = time + 2.5
		elif time >= next_wave_t:
			next_wave_t = -1.0
			wave_index += 1
			if wave_index >= WAVES.size():
				over = "victory"
				events.append({"type": "victory"})
				return
			var kinds: Array = WAVES[wave_index]
			for i in kinds.size():
				spawn_queue.append({"t": time + i * ENTRY_STAGGER, "kind": kinds[i], "i": i})
			events.append({"type": "wave", "index": wave_index})


func _spawn_enemy(kind: String, i: int) -> void:
	var entries: Array = layout["spawns"]["enemy_entry"]
	var e: Dictionary = entries[i % entries.size()]
	spawn(kind, Vector2(layout["bounds"]["max_x"] - 0.6, e["z"] + (i / entries.size()) * 0.9 * (1 if i % 2 == 0 else -1)))


func _check_over() -> void:
	if over != "":
		return
	for u in units.values():
		if u.team == 0 and u.state != State.DEAD:
			return
	over = "defeat"
	events.append({"type": "defeat"})


func take_events() -> Array:
	var out := events
	events = []
	return out
