extends RefCounted
## The player's save and the rules that read it: a GDScript port of the 2D game's save.lua, items.lua and progression.lua, with the same
## data shape (gold, partyOrder, unlockedCharacters[class] = {recruited, level, pointsToNextLevel, equipped, skillTree}, items, inventory,
## shopState). Stats are never saved: hero_stats() derives them. Saved as JSON in user://save_1.json.
##
## Only the heroes with a full skill tree are playable for now (Director): the Knight and the Wizard.

const GameData := preload("res://sim/game_data.gd")

const PLAYABLE := ["knight", "wizard"]
const STARTING_PARTY := ["knight", "wizard"]
const MAX_LEVEL := 30
const INVENTORY_SIZE := 35
const SHOP_SLOTS := 6
const PARTY_SLOTS := 4
const SAVE_PATH := "user://save_1.json"
static var save_path := SAVE_PATH                  # tests point this somewhere else so they never touch the real save
## Armor comes in three weights (Director): HEAVY plate and mail, MEDIUM leather and gi, LIGHT cloaks and robes. A class wears one weight:
## the Knight heavy, the Wizard light. (Keys are Battleheart item ids.)
const ARMOR_WEIGHT := {4: "heavy", 103: "heavy", 104: "heavy", 105: "heavy", 106: "heavy", 107: "heavy",
		5: "medium", 113: "medium", 114: "medium", 115: "medium", 116: "medium", 117: "medium", 44: "medium", 118: "medium", 119: "medium", 120: "medium", 121: "medium", 122: "medium",
		6: "light", 108: "light", 109: "light", 110: "light", 111: "light", 112: "light"}
const CLASS_ARMOR := {"knight": ["heavy"], "paladin": ["heavy"], "wizard": ["light"], "priest": ["light"], "witch": ["light"], "rogue": ["medium"], "barbarian": ["medium"]}
const MODELLED_BH := [0, 1, 2, 3, 4, 5, 6, 9, 10, 11]      # the Battleheart weapons / armors that have a 3D model
const TRINKET_STATS := {"power": ["ATK", 1.0], "defense": ["DEF", 1.0], "crit": ["CRIT", 0.01]}

## The stages (the 2D map zones, blender/build_zones.py): id, display name, fights, the stage folder in models/stage/.
const ZONES := [
	{"id": "black_forest", "name": "BLACK FOREST", "fights": 6, "blurb": "Webs and wisps between the trees."},
	{"id": "cold_wastes", "name": "COLD WASTES", "fights": 6, "blurb": "A frozen lake ringed with ice crystals."},
	{"id": "wetcaves", "name": "WETCAVES", "fights": 7, "blurb": "Glowing mushrooms over black pools."},
	{"id": "waxen_desert", "name": "WAXEN DESERT", "fights": 8, "blurb": "Candles burn in the sand."},
	{"id": "castle_crimson", "name": "CASTLE CRIMSON", "fights": 9, "blurb": "A red hall with torches and banners."},
]

static func C_title(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


## 20.0 -> "20", 1.5 -> "1.5" (JSON numbers arrive as floats).
static func num(x: Variant) -> String:
	return String.num(float(x), 1).trim_suffix(".0")


static var data: Dictionary = {}
static var zone_index := 0                      # the stage chosen on the stage-select screen
static var from_menu := false                    # the battle was started from the menus (campaign party, gear, stage, rewards)
static var last_result: Dictionary = {}         # what the last won battle gave (shown on the stage-select screen)


# ------------------------------------------------------------------------------------------------- save
static func ensure() -> void:
	if data.is_empty():
		if not load_save():
			new_game()


static func new_game() -> void:
	data = {"floor": 1, "gold": 15, "partyOrder": [false, false, false, false], "unlockedCharacters": {}, "items": {}, "inventory": [],
			"shopState": {"offers": [], "hireOffer": null, "seeded": false}, "_itemIdSeq": 0, "_knightTiersSwapped": true, "mapProgression": {"clearedEncounters": []}}
	for name in PLAYABLE:
		data["unlockedCharacters"][name] = {"recruited": false, "level": 1, "pointsToNextLevel": xp_to_next(1), "equipped": {}, "skillTree": []}
	for i in STARTING_PARTY.size():
		var name: String = STARTING_PARTY[i]
		data["unlockedCharacters"][name]["recruited"] = true
		data["partyOrder"][i] = name
		equip_starter_gear(name)
	write_save()


static func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("unlockedCharacters"):
		return false
	data = parsed
	if not data.get("_knightTiersSwapped", false):                  # the Knight's Lv 1 and Lv 10 tiers were swapped: carry the saved picks over
		var st: Array = data["unlockedCharacters"].get("knight", {}).get("skillTree", [])
		if st.size() > 2:
			var tmp = st[0]
			st[0] = st[2]
			st[2] = tmp
		data["_knightTiersSwapped"] = true
	for name in PLAYABLE:                                          # a save from before a class existed
		if not data["unlockedCharacters"].has(name):
			data["unlockedCharacters"][name] = {"recruited": false, "level": 1, "pointsToNextLevel": xp_to_next(1), "equipped": {}, "skillTree": []}
	return true


# ------------------------------------------------------------------------------------------------- save slots (2D save.lua: save_N.json)
const SLOT_COUNT := 5
static var slot := 1                                           # the active save slot
static var slot_prefix := "user://save_"                        # tests point this elsewhere


static func slot_path(i: int) -> String:
	return "%s%d.json" % [slot_prefix, i]


## What the save-select row shows: {place, party} from the slot's file, or {} when it is empty or unreadable.
static func slot_info(i: int) -> Dictionary:
	var path := slot_path(i)
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY or not d.has("unlockedCharacters"):
		return {}
	var wins: Dictionary = d.get("mapProgression", {}).get("zoneWins", {})
	var place := "ALL ZONES CLEARED"
	for z in ZONES:
		var w := int(wins.get(z["id"], 0))
		if w < int(z["fights"]):
			place = "%s - FIGHT %d OF %d" % [z["name"], w + 1, int(z["fights"])]
			break
	var names: Array = []
	for name in d.get("partyOrder", []):
		if typeof(name) == TYPE_STRING:
			names.append("%s %d" % [name.to_upper(), int(d["unlockedCharacters"].get(name, {}).get("level", 1))])
	return {"place": place, "party": " / ".join(names) + "   %d gold" % int(d.get("gold", 0))}


## Make slot `i` the active save: load it, or start a new game in it when it is empty.
static func use_slot(i: int) -> void:
	slot = i
	save_path = slot_path(i)
	data = {}
	zone_index = 0
	last_result = {}
	ensure()


static func delete_slot(i: int) -> void:
	if FileAccess.file_exists(slot_path(i)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(i)))
	if i == slot and save_path == slot_path(i):
		data = {}


static func write_save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


# ------------------------------------------------------------------------------------------------- party
static func party() -> Array:
	var out: Array = []
	for name in data["partyOrder"]:
		if typeof(name) == TYPE_STRING:
			out.append(name)
	return out


static func record(name: String) -> Dictionary:
	return data["unlockedCharacters"].get(name, {})


static func level_of(name: String) -> int:
	return int(record(name).get("level", 1))


static func recruited() -> Array:
	var out: Array = []
	for name in PLAYABLE:
		if record(name).get("recruited", false):
			out.append(name)
	return out


# ------------------------------------------------------------------------------------------------- items (items.lua)
static func catalog() -> Dictionary:
	return GameData.items()


static func make_instance(id: String, bh_id: int) -> Dictionary:
	var row: Dictionary = catalog().get(str(bh_id), {})
	if row.is_empty():
		return {}
	var mods := {}
	if row["type"] == "weapon":
		mods["ATK"] = row["power"]
	elif row["type"] == "armor":
		mods["DEF"] = row["power"]
	elif TRINKET_STATS.has(row.get("effect", "")):
		var t: Array = TRINKET_STATS[row["effect"]]
		mods[t[0]] = row["power"] * t[1]
	var tier: int = int(row.get("tier", 9))
	return {"id": id, "bhId": bh_id, "itemType": row["type"], "name": row["name"], "desc": row.get("desc", ""), "grade": 1 if tier <= 3 else (2 if tier <= 6 else 3),
			"value": row["price"], "sellPrice": int(floor(float(row["price"]) / 2.0)), "usableBy": row.get("usableBy", []), "mods": mods}


static func mint(bh_id: int) -> String:
	data["_itemIdSeq"] = int(data.get("_itemIdSeq", 0)) + 1
	var id := "it_%04d" % int(data["_itemIdSeq"])
	var inst := make_instance(id, bh_id)
	if inst.is_empty():
		return ""
	data["items"][id] = inst
	return id


static func item_of(id: Variant) -> Dictionary:
	if typeof(id) != TYPE_STRING:
		return {}
	return data["items"].get(id, {})


static func armor_weight(inst: Dictionary) -> String:
	if inst.get("itemType", "") != "armor":
		return ""
	var row: Dictionary = catalog().get(str(int(inst.get("bhId", -1))), {})
	return String(row.get("weight", ARMOR_WEIGHT.get(int(inst.get("bhId", -1)), "medium")))


## Why `name` cannot wear this armor ("" when it can): its weight is not one the class wears.
static func weight_problem(inst: Dictionary, name: String) -> String:
	var w := armor_weight(inst)
	if w == "":
		return ""
	var allowed: Array = CLASS_ARMOR.get(name, ["medium"])
	return "" if w in allowed else "%s wears %s armor" % [C_title(name), " or ".join(allowed)]


static func can_use(inst: Dictionary, name: String) -> bool:
	var users: Array = inst.get("usableBy", [])
	return (users.is_empty() or name in users) and weight_problem(inst, name) == ""


static func resolve_gear(name: String) -> Dictionary:
	var out := {}
	for slot in record(name).get("equipped", {}):
		out[slot] = item_of(record(name)["equipped"][slot])
	return out


static func equip_starter_gear(name: String) -> void:
	var def: Dictionary = GameData.classes()[name]
	var rec := record(name)
	rec["equipped"] = rec.get("equipped", {})
	for i in 2:
		var slot: String = ["weapon", "armor"][i]
		if not rec["equipped"].has(slot) and i < def["starterGear"].size():
			rec["equipped"][slot] = mint(int(def["starterGear"][i]))


static func add_gold(n: int) -> void:
	data["gold"] = int(data.get("gold", 0)) + n


static func spend_gold(n: int) -> bool:
	if n <= 0 or int(data.get("gold", 0)) < n:
		return false
	data["gold"] = int(data["gold"]) - n
	return true


static func inventory_full() -> bool:
	return data["inventory"].size() >= INVENTORY_SIZE


static func is_supported(bh_id: int) -> bool:
	var row: Dictionary = catalog().get(str(bh_id), {})
	if row.is_empty():
		return false
	if (row["type"] == "armor" or row["type"] == "weapon") and not row.has("model") and not MODELLED_BH.has(bh_id):
		return false                                                          # the other Battleheart armors / weapons have no 3D model; the tiers replace them
	return row["type"] != "trinket" or TRINKET_STATS.has(row.get("effect", ""))


## The 3D model for an item (blender/build_gear.py gear.json `bh_item`), or "" when the item has no model yet.
static func model_for(inst: Dictionary) -> String:
	if inst.is_empty():
		return ""
	var row: Dictionary = catalog().get(str(int(inst["bhId"])), {})
	if row.has("model"):                                                  # the armor tiers 2-10 name their own body model
		return String(row["model"])
	return {0: "sword_iron", 10: "sword_long", 9: "sword_carver", 1: "dagger_iron", 3: "staff_oak", 2: "rod_cleric", 11: "hatchet",
			4: "armor_scale_mail", 5: "armor_leather", 6: "armor_cloak"}.get(int(inst["bhId"]), "")


## Weapon speed: a multiplier on the class's auto-attack cooldown (not the animation speed). One-hand weapons are below 1, two-hand above.
static func weapon_speed(inst: Dictionary) -> float:
	if inst.is_empty() or inst.get("itemType", "") != "weapon":
		return 1.0
	var row: Dictionary = catalog().get(str(int(inst["bhId"])), {})
	return float(row.get("speed", 1.0))


## The helm of an armor set (the armor tiers carry one; the starters wear their class's usual headpiece).
static func head_for(inst: Dictionary) -> String:
	if inst.is_empty():
		return ""
	var row: Dictionary = catalog().get(str(int(inst["bhId"])), {})
	if row.has("head"):
		return String(row["head"])
	return {4: "helm_iron", 5: "cap_leather", 6: "hood_cloth"}.get(int(inst["bhId"]), "")


# ------------------------------------------------------------------------------------------------- stats (progression.lua)
static func xp_to_next(level: int) -> int:
	var rewards: Dictionary = GameData.table("bh_rewards")
	var xp: float = float(rewards["FIRST_LEVEL_XP"])
	var tbl: Array = rewards["XP_TABLE"]
	for i in range(2, level + 1):
		xp = floorf(xp * float(tbl[mini(i + 1, tbl.size() - 1)]))
	return int(xp)


static func add_xp(rec: Dictionary, amount: int) -> int:
	if amount <= 0:
		return 0
	rec["level"] = maxi(1, int(rec.get("level", 1)))
	if int(rec["level"]) >= MAX_LEVEL:
		rec["pointsToNextLevel"] = 0
		return 0
	var need: int = int(rec.get("pointsToNextLevel", 0))
	if need <= 0:
		need = xp_to_next(int(rec["level"]))
	need -= amount
	var gained := 0
	while need <= 0 and int(rec["level"]) < MAX_LEVEL:
		rec["level"] = int(rec["level"]) + 1
		gained += 1
		need += xp_to_next(int(rec["level"]))
	rec["pointsToNextLevel"] = 0 if int(rec["level"]) >= MAX_LEVEL else need
	return gained


static func hero_stats(name: String) -> Dictionary:
	var def: Dictionary = GameData.classes().get(name, {})
	if def.is_empty():
		return {}
	var level := level_of(name)
	var b: Dictionary = def["base"]
	var s: Dictionary = def["scale"]
	var out := {"maxHP": b["hp"] + s["hp"] * (level - 1), "ATK": b["power"] + s["power"] * (level - 1), "DEF": b["defense"] + s["defense"] * (level - 1), "CRIT": b.get("crit", 0.0)}
	for slot in resolve_gear(name):
		var inst: Dictionary = resolve_gear(name)[slot]
		for k in inst.get("mods", {}):
			if out.has(k):
				out[k] += inst["mods"][k]
	var mods := talent_mods(name)
	for k in mods:
		if out.has(k):
			out[k] += mods[k]
	if mods.has("DEF_PCT"):
		out["DEF"] *= 1.0 + float(mods["DEF_PCT"])
	return {"maxHP": int(floor(out["maxHP"])), "ATK": int(floor(out["ATK"])), "DEF": int(floor(out["DEF"])), "CRIT": out["CRIT"]}


# ------------------------------------------------------------------------------------------------- talents
## A class's talent ladder: {autoBump, choices: [{level, options: [{id, name, ability|mods|traits|desc|spec}]}]}. The Wizard's is the
## Director's skill tree (data/wizard_talents.json); the Knight's is the 2D game's.
static func ladder_for(name: String) -> Dictionary:
	if name == "wizard":
		return GameData.wizard_talents()
	if name == "knight":
		return _knight_ladder()
	return GameData.table("talents")["LADDER"].get(name, {"choices": []})


static var _knight_cache := {}


## The Knight's ladder is the 2D game's with the level-1 and level-10 tiers SWAPPED (Director): Lv 1 offers Sunder Armor | Charge and Lv 10 offers
## Hamstring | Defend. The exported 2D table is left untouched; the swap is applied here.
static func _knight_ladder() -> Dictionary:
	if _knight_cache.is_empty():
		var ladder: Dictionary = GameData.table("talents")["LADDER"]["knight"].duplicate(true)
		var i1 := -1
		var i10 := -1
		for i in ladder["choices"].size():
			if int(ladder["choices"][i]["level"]) == 1:
				i1 = i
			elif int(ladder["choices"][i]["level"]) == 10:
				i10 = i
		if i1 >= 0 and i10 >= 0:
			var tmp: Array = ladder["choices"][i1]["options"]
			ladder["choices"][i1]["options"] = ladder["choices"][i10]["options"]
			ladder["choices"][i10]["options"] = tmp
		_knight_cache = ladder
	return _knight_cache


static func picks_of(name: String) -> Array:
	return record(name).get("skillTree", [])


static func chosen_option(name: String, choice_idx: int) -> String:
	var st: Array = picks_of(name)
	return String(st[choice_idx]) if choice_idx < st.size() and typeof(st[choice_idx]) == TYPE_STRING else ""


static func write_choice(name: String, choice_idx: int, opt_id: String) -> void:
	var rec := record(name)
	var st: Array = rec.get("skillTree", [])
	while st.size() <= choice_idx:
		st.append("")
	st[choice_idx] = opt_id
	rec["skillTree"] = st


static func talent_mods(name: String) -> Dictionary:
	var out := {}
	var ladder := ladder_for(name)
	for i in ladder["choices"].size():
		var pick := chosen_option(name, i)
		for opt in ladder["choices"][i]["options"]:
			if opt["id"] == pick:
				for k in opt.get("mods", {}):
					out[k] = out.get(k, 0.0) + opt["mods"][k]
	return out


## The ability ids a hero brings into battle, in ladder order (Q W E), capped at three (Director: three abilities per hero).
static func active_abilities(name: String) -> Array:
	var out: Array = []
	var ladder := ladder_for(name)
	for i in ladder["choices"].size():
		var pick := chosen_option(name, i)
		for opt in ladder["choices"][i]["options"]:
			if opt["id"] == pick and opt.has("ability"):
				var wt: Dictionary = GameData.wizard_talents()
				if wt["abilities"].has(opt["ability"]) and wt["abilities"][opt["ability"]].get("passive", false):
					continue                                         # passives (Mirror Image) are not on the ability bar
				out.append(String(opt["ability"]))
	return out.slice(0, 3)


## The Wizard's picks as the sandbox's build dictionary ("1" -> "explosion", ...), from the saved skill tree.
static func wizard_build() -> Dictionary:
	var out := {}
	var ladder := ladder_for("wizard")
	for i in ladder["choices"].size():
		var pick := chosen_option("wizard", i)
		if pick != "":
			out[str(int(ladder["choices"][i]["level"]))] = pick
	return out


## Ability text for the tooltips: {name, cooldown, bars, target, lines}. The Wizard's spells are written in data/wizard_talents.json; the
## 2D rows are described from their data (the numbers are the real ones).
static func describe_ability(id: String) -> Dictionary:
	var wt := GameData.wizard_talents()
	if wt["abilities"].has(id):
		var a: Dictionary = wt["abilities"][id]
		var target := "Passive" if a.get("passive", false) else ("Pick an area" if a["select"] == "area" else ("Pick an enemy" if a["select"] == "unit" else "No target needed"))
		return {"name": a["name"], "cooldown": a["cdMax"], "bars": a["bars"], "target": target, "lines": [String(a["desc"])]}
	var row: Dictionary = GameData.abilities().get(id, {})
	if row.is_empty():
		return {}
	var lines: Array = []
	var eff: Dictionary = row.get("effect", {})
	match eff.get("kind", ""):
		"damage":
			lines.append("Deals %d%% damage" % int(round(100.0 * (1.0 + float(eff.get("buffMods", {}).get("0", 0.0))))))
			if eff.has("onHit"):
				var st: Dictionary = eff["onHit"]["effect"]
				lines.append("%s %d%% for %s s" % [String(st["index"]).capitalize(), int(round(float(st["magnitude"]) * 100.0)), num(st["duration"])])
		"aoe":
			var inner: Dictionary = eff.get("inner", {})
			lines.append("Deals %d%% damage to enemies around you" % int(round(100.0 * (1.0 + float(inner.get("buffMods", {}).get("0", 0.0))))))
			if inner.has("onHit"):
				var st2: Dictionary = inner["onHit"]["effect"]
				lines.append("%s %d%% for %s s" % [String(st2["index"]).capitalize(), int(round(float(st2["magnitude"]) * 100.0)), num(st2["duration"])])
		"threat":
			lines.append("Adds %d threat on every enemy" % int(eff["flat"]))
		"status":
			lines.append("%s for %s s" % [String(eff["index"]).capitalize(), num(eff["duration"])])
		_:
			lines.append(String(eff.get("kind", "")))
	var target2 := "Pick an area" if row.get("select", "") == "area" else ("Pick a unit" if row.get("select", "") == "unit" else ("Around you" if row.get("select", "") == "self" else "No target needed"))
	return {"name": String(row.get("name", id)), "cooldown": row.get("cdMax", 0), "bars": int(row.get("bars", 0)), "target": target2, "lines": lines}


# ------------------------------------------------------------------------------------------------- shop (items.lua rollOffers, progression hire)
static func highest_level() -> int:
	var best := 1
	for name in recruited():
		best = maxi(best, level_of(name))
	return best


static func roll_offers(level: int) -> Array:
	var tables: Array = []
	for t in GameData.table("bh_items")["LOOT_TABLES"]:
		if level >= int(t["minLevel"]) and level <= int(t["maxLevel"]):
			tables.append(t)
	var extra: Array = []                                                          # the 3D side's own items appear as one more table
	for e in GameData.extra_shop():
		if level >= int(e["minLevel"]) and level <= int(e["maxLevel"]):
			extra.append(int(e["id"]))
	if not extra.is_empty():
		tables.append({"items": extra})
	var offers: Array = []
	if tables.is_empty():
		return offers
	for _i in randi_range(3, SHOP_SLOTS):
		for _try in 20:
			var t: Dictionary = tables[randi() % tables.size()]
			var bh_id: int = int(t["items"][randi() % t["items"].size()])
			if is_supported(bh_id):
				offers.append(bh_id)
				break
	return offers


static func shop_state() -> Dictionary:
	if not data.has("shopState"):
		data["shopState"] = {"offers": [], "hireOffer": null, "seeded": false}
	return data["shopState"]


static func restock_if_needed() -> void:
	var ss := shop_state()
	if ss.get("seeded", false) and not ss.get("pendingRestock", false):
		return
	for old in ss["offers"]:
		if typeof(old) == TYPE_STRING:
			data["items"].erase(old)
	ss["offers"] = []
	for bh_id in roll_offers(highest_level()):
		ss["offers"].append(mint(bh_id))
	ss["hireOffer"] = null                                           # nobody else is playable yet: no one is hiring
	ss["seeded"] = true
	ss["pendingRestock"] = false


# ------------------------------------------------------------------------------------------------- zone progress
## Wins in a zone (a zone is complete after its `fights` wins); later zones stay hidden until the one before them is complete.
static func zone_wins(i: int) -> int:
	return int(data["mapProgression"].get("zoneWins", {}).get(ZONES[i]["id"], 0))


static func zone_complete(i: int) -> bool:
	return zone_wins(i) >= int(ZONES[i]["fights"])


static func zone_unlocked(i: int) -> bool:
	return i <= 0 or zone_complete(i - 1)


static func unlocked_count() -> int:
	var n := 0
	while n < ZONES.size() and zone_unlocked(n):
		n += 1
	return n


## The number of the fight the zone offers next (1-based), capped at the zone's total once it is complete.
static func fight_number(i: int) -> int:
	return mini(zone_wins(i) + 1, int(ZONES[i]["fights"]))


# ------------------------------------------------------------------------------------------------- rewards (progression.onEncounterWon)
## The gold and XP of a won battle (one battle of the tier of the current floor). Returns what the stage-select screen shows.
static func on_encounter_won(survivors: Array) -> Dictionary:
	var rows: Array = GameData.table("bh_rewards")["LEVELS"]
	var tier: int = clampi(int(data.get("floor", 1)) + int(data["mapProgression"]["clearedEncounters"].size()), 1, rows.size())
	var row: Dictionary = rows[tier - 1]
	var result := {"gold": int(floor(float(row["gold"]) * randf_range(0.85, 1.15) + 0.5)), "xp": []}
	add_gold(result["gold"])
	data["mapProgression"]["clearedEncounters"].append(zone_index)
	if zone_index >= 0 and zone_index < ZONES.size() and not zone_complete(zone_index):
		var zw: Dictionary = data["mapProgression"].get("zoneWins", {})
		zw[ZONES[zone_index]["id"]] = zone_wins(zone_index) + 1
		data["mapProgression"]["zoneWins"] = zw
	var mult: float = [4.0, 2.0, 1.33, 1.0][clampi(survivors.size() - 1, 0, 3)]
	for name in survivors:
		var rec := record(name)
		if rec.is_empty():
			continue
		var before := int(rec["level"])
		var gained := int(floor(float(row["xp"]) * mult + 0.5))
		var ups := add_xp(rec, gained)
		result["xp"].append({"name": name, "gained": gained, "levelUps": ups, "level": int(rec["level"]), "before": before})
	shop_state()["pendingRestock"] = true
	last_result = result
	write_save()
	return result
