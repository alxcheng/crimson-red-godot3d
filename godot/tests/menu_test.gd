extends SceneTree
## The menu screens, driven like a player (headless): game state rules, the talent tree (picks are switchable), shop buy / sell, equip, party, stage select.

const GameState := preload("res://menus/game_state.gd")
const C := preload("res://menus/menu_common.gd")
const TalentsScreen := preload("res://menus/talents_screen.gd")
const ShopScreen := preload("res://menus/shop_screen.gd")
const EquipScreen := preload("res://menus/equip_screen.gd")
const PartyScreen := preload("res://menus/party_screen.gd")
const StageScreen := preload("res://menus/stage_select_screen.gd")
const TitleScreen := preload("res://menus/title_screen.gd")
const SaveSelectScreen := preload("res://menus/save_select_screen.gd")
const IC := preload("res://menus/item_ui.gd")

var _fail := 0


class StubApp:
	extends Node
	var last := ""
	var started := false

	func switch_to(n: String, _a: Dictionary = {}) -> void:
		last = n

	func start_battle() -> void:
		started = true


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error(msg)


func _click(screen, p: Vector2) -> void:
	screen.mouse = p
	screen.update(0.016)
	screen.mouse_pressed(p)
	screen.update(0.016)
	screen.mouse_released(p)


func _open(script, app):
	var s = script.new()
	s.app = app
	root.add_child(s)
	s.enter({})
	s.attach_overlay()
	s.update(0.016)
	return s


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	GameState.save_path = "user://menu_test_save.json"           # never the player's save
	GameState.new_game()
	var app := StubApp.new()
	root.add_child(app)
	# ---- the new game
	_check(GameState.party() == ["knight", "wizard"], "a new game's party is the Knight and the Wizard (the heroes with full trees)")
	_check(GameState.PLAYABLE == ["knight", "wizard"], "only the full-tree heroes are playable")
	var st := GameState.hero_stats("knight")
	_check(st["ATK"] == 20 + int(GameState.catalog()["0"]["power"]) and st["DEF"] == 35 and st["maxHP"] == 1000, "Knight stats = class base + starter gear (Training Sword ATK, Riveted Mail +20 DEF): %s" % st)
	_check(GameState.model_for(GameState.item_of(GameState.record("knight")["equipped"]["weapon"])) == "sword_iron", "equipped items map to their 3D models")
	# ---- the talent tree: switchable picks
	GameState.record("wizard")["level"] = 25
	var ts = _open(TalentsScreen, app)
	ts._sel_char = "wizard"
	ts.update(0.016)
	var ladder := GameState.ladder_for("wizard")
	_check(ts.get_child(ts.get_child_count() - 1) == ts._overlay, "the tooltip overlay is the LAST child of the screen, so popup text is drawn on top of the talent ladder")
	_check(ladder["choices"].size() == 6, "the Wizard's tree has six tiers (Lv 1, 5, 10, 10, 20, 25)")
	var fork_rows: Array = ts._rows.filter(func(r): return r["kind"] == "fork")
	_check(fork_rows.size() == 6 and fork_rows.filter(func(r): return r["level"] == 10).size() == 2, "two fork rows at level 10")
	var row1: Dictionary = fork_rows[0]
	var boxes: Array = ts._row_boxes(row1)
	_click(ts, boxes[0].get_center())
	_check(GameState.chosen_option("wizard", 0) == "explosion", "clicking option A picks Explosion")
	_click(ts, boxes[1].get_center())
	_check(GameState.chosen_option("wizard", 0) == "iridescent_bolt", "clicking option B SWITCHES the pick (picks are not permanent)")
	_click(ts, boxes[1].get_center())
	_check(GameState.chosen_option("wizard", 0) == "", "clicking the chosen option again clears it")
	_click(ts, boxes[0].get_center())
	var tbd_row: Dictionary = fork_rows[1]                       # Lv 5: no options yet
	_check(ts._state(tbd_row, 0) == "tbd", "a tier with no options is shown as to be defined")
	GameState.write_choice("wizard", 2, "ice_block")
	GameState.write_choice("wizard", 4, "blizzard")
	GameState.write_choice("wizard", 5, "pyromancer")
	_check(GameState.active_abilities("wizard") == ["explosion", "ice_block", "blizzard"], "the Wizard's bar follows the picks: %s" % [GameState.active_abilities("wizard")])
	GameState.write_choice("wizard", 4, "mirror_image")
	_check(GameState.active_abilities("wizard") == ["explosion", "ice_block"], "Mirror Image is a passive: not on the ability bar")
	_check(GameState.wizard_build() == {"1": "explosion", "10": "ice_block", "20": "mirror_image", "25": "pyromancer"}, "the picks become the sandbox's build: %s" % [GameState.wizard_build()])
	var kl := GameState.ladder_for("knight")
	_check(kl["choices"][0]["options"][0]["id"] == "sunder" and kl["choices"][0]["options"][1]["id"] == "charge", "Knight Lv 1 now offers Sunder Armor | Charge")
	_check(kl["choices"][2]["options"][0]["id"] == "hamstring" and kl["choices"][2]["options"][1]["id"] == "defend", "Knight Lv 10 now offers Hamstring | Defend")
	GameState.write_choice("knight", 0, "sunder")
	GameState.write_choice("knight", 2, "hamstring")
	GameState.write_choice("knight", 4, "challenge")
	_check(GameState.active_abilities("knight").size() == 3, "the Knight's picks give three abilities at most")
	# ---- shop
	GameState.data["gold"] = 500
	var sh = _open(ShopScreen, app)
	var offers: Array = GameState.shop_state()["offers"]
	_check(offers.size() >= 3, "the shop stocks 3 to 6 items")
	var price: int = int(GameState.item_of(offers[0])["value"])
	_click(sh, sh._slot_rect(0).get_center())
	_check(not sh._action().is_empty() and sh._action()["verb"] == "BUY", "selecting an offer shows BUY")
	_click(sh, sh._btn_rect().get_center())
	_check(int(GameState.data["gold"]) == 500 - price and GameState.data["inventory"].size() == 1 and typeof(offers[0]) == TYPE_BOOL, "BUY pays the price, moves the item to the inventory, empties the slot")
	var inv_id: String = GameState.data["inventory"][0]
	_click(sh, IC.cell_rect(0).get_center())
	_check(sh._action()["verb"] == "SELL", "selecting an inventory item shows SELL")
	var before: int = int(GameState.data["gold"])
	_click(sh, sh._btn_rect().get_center())
	_check(int(GameState.data["gold"]) == before + int(floor(price / 2.0)) and GameState.data["inventory"].is_empty(), "SELL pays half and removes the item")
	GameState.data["gold"] = 0
	_click(sh, sh._slot_rect(1).get_center())
	_click(sh, sh._btn_rect().get_center())
	_check(GameState.data["inventory"].is_empty(), "no buying without the gold")
	# ---- equip
	GameState.data["inventory"] = []
	var longsword := GameState.mint(10)                       # Broadsword: knight / paladin
	GameState.data["inventory"].append(longsword)
	var eq = _open(EquipScreen, app)
	_check(eq._sel_char == "knight", "the first party hero is selected")
	_click(eq, IC.cell_rect(0).get_center())
	_check(eq._held == longsword, "clicking an item holds it")
	_click(eq, eq._slot_rect(0).get_center())
	_check(GameState.record("knight")["equipped"]["weapon"] == longsword and GameState.data["inventory"].size() == 1, "clicking the weapon slot equips it; the Training Sword goes back to the inventory")
	_check(GameState.hero_stats("knight")["ATK"] == 20 + int(GameState.catalog()["10"]["power"]), "equipping changes the stats")
	# an item the class cannot use is refused (the Hazel Staff is the Wizard's)
	var staff := GameState.mint(3)
	GameState.data["inventory"].append(staff)
	_click(eq, IC.cell_rect(1).get_center())
	_click(eq, eq._slot_rect(0).get_center())
	_check(GameState.record("knight")["equipped"]["weapon"] == longsword, "a class cannot equip an item it cannot use")
	# ---- armor weights: the Knight wears heavy, the Wizard light
	var cloak := GameState.make_instance("t1", 6)                        # Linen Wrap (light)
	var scale := GameState.make_instance("t2", 4)                        # Riveted Mail (heavy)
	var leather := GameState.make_instance("t3", 5)                      # Hide Jerkin (medium)
	_check(GameState.armor_weight(cloak) == "light" and GameState.armor_weight(scale) == "heavy" and GameState.armor_weight(leather) == "medium", "armor items have a weight")
	_check(GameState.can_use(scale, "knight") and not GameState.can_use(cloak, "knight") and not GameState.can_use(leather, "knight"), "the Knight wears heavy armor only")
	_check(GameState.can_use(cloak, "wizard") and not GameState.can_use(scale, "wizard") and not GameState.can_use(leather, "wizard"), "the Wizard wears light armor only")
	_check(GameState.weight_problem(cloak, "knight") == "Knight wears heavy armor", "the tooltip says why: %s" % GameState.weight_problem(cloak, "knight"))
	var last := {"heavy": 0, "medium": 0, "light": 0}                    # the 10-tier armor sets: 3 weights x tiers 1-10
	for w in ["heavy", "medium", "light"]:
		for t in range(1, 11):
			var aid: int = {"heavy": 4, "medium": 5, "light": 6}[w] if t == 1 else {"heavy": 300, "medium": 310, "light": 320}[w] + t
			var inst := GameState.make_instance("s%d" % aid, aid)
			var cls: String = {"heavy": "knight", "medium": "rogue", "light": "wizard"}[w]
			var p: int = int(GameState.catalog()[str(aid)]["power"])
			_check(GameState.armor_weight(inst) == w and GameState.can_use(inst, cls), "%s tier %d: weight and class" % [w, t])
			_check(p > last[w], "%s tier %d: power %d rises with the tier" % [w, t, p])
			last[w] = p
			_check(FileAccess.file_exists("res://models/gear/%s.glb" % GameState.model_for(inst)) and FileAccess.file_exists("res://models/gear/%s.glb" % GameState.head_for(inst)), "%s tier %d: body and helm models are built" % [w, t])
		_check(not GameState.can_use(GameState.make_instance("x", {"heavy": 304, "medium": 314, "light": 324}[w]), {"heavy": "wizard", "medium": "knight", "light": "knight"}[w]), "%s armor is not wearable by the wrong class" % w)
	var tier_dps := {}
	var wlast := {}                                                       # the 6 weapon lines x 10 tiers
	for line in ["melee_1h", "melee_2h", "bow", "crossbow", "staff", "wand"]:
		var base: int = {"melee_1h": 400, "melee_2h": 410, "bow": 420, "crossbow": 430, "staff": 440, "wand": 450}[line]
		var prev := 0
		for t in range(1, 11):
			var wid: int = {"melee_1h": 0, "melee_2h": 10, "staff": 3}.get(line, 0) if t == 1 and line in ["melee_1h", "melee_2h", "staff"] else base + t
			var winst := GameState.make_instance("w%d" % wid, wid)
			var wp: int = int(GameState.catalog()[str(wid)]["power"])
			var dps := float(wp) / GameState.weapon_speed(winst)               # power / speed is one number per tier, for every weapon type
			if t > 1 or line in ["bow", "crossbow", "wand"]:
				_check(absf(dps - float(tier_dps.get(t, dps))) < 1.6, "%s tier %d: DPS index %.1f equals the other lines (%.1f)" % [line, t, dps, float(tier_dps.get(t, dps))])
			tier_dps[t] = tier_dps.get(t, dps)
			_check(dps >= prev - 0.01, "%s tier %d: DPS index rises" % [line, t])
			prev = dps
			_check(GameState.model_for(winst) != "" and FileAccess.file_exists("res://models/gear/%s.glb" % GameState.model_for(winst)), "%s tier %d has a built model" % [line, t])
		wlast[line] = prev
	_check(GameState.can_use(GameState.make_instance("wz", 441), "wizard") and not GameState.can_use(GameState.make_instance("wk", 421), "knight") and GameState.can_use(GameState.make_instance("wn", 412), "knight"), "weapon lines are class-restricted")
	var sp1 := GameState.weapon_speed(GameState.make_instance("a", 402))   # hatchet-class one-hand
	var sp2 := GameState.weapon_speed(GameState.make_instance("b", 415))   # great axe
	_check(sp1 < 1.0 and sp2 > 1.0 and GameState.can_use(GameState.make_instance("r", 412), "rogue"), "one-hand weapons are faster than two-hand ones; rogues wield melee weapons")
	_check(GameState.is_supported(4) and not GameState.is_supported(103), "armors without a model are not offered")
	_check(GameState.roll_offers(30).size() > 0, "shop rolls at level 30")
	# ---- party
	var pa = _open(PartyScreen, app)
	_click(pa, pa._slot_rect(1).get_center())
	_check(pa._party[1] == "" and pa._roster == ["wizard"], "clicking a party member sends them to the reserves")
	_click(pa, pa._cell_rect(0).get_center())
	_check(pa._party[1] == "wizard", "clicking a reserve fills the lowest free slot")
	# ---- stage select + title
	var ss = _open(StageScreen, app)
	_check(GameState.unlocked_count() == 1, "only the first zone is shown on a new game")
	GameState.data["mapProgression"]["zoneWins"] = {"black_forest": 6, "cold_wastes": 6, "wetcaves": 7}   # zones 1-3 cleared: the 4th opens
	_check(GameState.unlocked_count() == 4 and GameState.zone_complete(2) and not GameState.zone_complete(3), "a zone opens when the one before it is complete")
	ss = _open(StageScreen, app)
	_click(ss, ss._row_rect(3).get_center())
	_check(GameState.zone_index == 3 and ss._progress_text(3) == "FIGHT 1 OF 8" and ss._progress_text(0) == "CLEARED (6 fights)", "clicking a zone selects it; shows fight n of m")
	_click(ss, StageScreen.ENTER_RECT.get_center())
	_check(app.started, "ENTER starts the battle")
	_click(ss, ss._link_rects[3].get_center())
	_check(app.last == "shop", "the SHOP link opens the shop")
	var ti = _open(TitleScreen, app)
	_click(ti, ti._btn_rect(0).get_center())
	_check(app.last == "save_select", "PLAY opens the save select")
	# ---- save select: 5 slots, new game in an empty one, load a filled one, DELETE needs a second press
	var kept: Dictionary = GameState.data.duplicate(true)               # the slot tests swap the game state; put it back afterwards
	var kept_path: String = GameState.save_path
	GameState.slot_prefix = "user://menu_test_slot_"
	for i in range(1, 6):
		GameState.delete_slot(i)
	var sv = _open(SaveSelectScreen, app)
	_check(GameState.slot_info(1).is_empty(), "an empty slot has no info")
	_click(sv, sv._row_hit(2).get_center())
	_check(app.last == "stage_select" and GameState.slot == 3 and GameState.party() == ["knight", "wizard"] and FileAccess.file_exists(GameState.slot_path(3)), "an empty slot starts a new game in that slot")
	GameState.data["gold"] = 777
	GameState.write_save()
	var info := GameState.slot_info(3)
	_check(String(info["place"]) == "BLACK FOREST - FIGHT 1 OF 6" and String(info["party"]).contains("KNIGHT 1") and String(info["party"]).contains("777"), "a filled slot shows zone, fight and party: %s" % info)
	GameState.use_slot(1)
	_check(GameState.data["gold"] != 777, "another slot is a separate game")
	GameState.use_slot(3)
	_check(GameState.data["gold"] == 777, "a filled slot loads its save")
	sv = _open(SaveSelectScreen, app)
	_click(sv, sv._del_rect(2).get_center())
	_check(not GameState.slot_info(3).is_empty() and sv._confirm == 2, "DELETE asks for a second press")
	_click(sv, sv._del_rect(2).get_center())
	_check(GameState.slot_info(3).is_empty(), "the second press deletes the slot")
	for i in range(1, 6):
		GameState.delete_slot(i)
	GameState.slot_prefix = "user://save_"
	GameState.save_path = kept_path
	GameState.data = kept
	GameState.slot = 1
	# ---- save round trip
	GameState.write_save()
	var snapshot: int = GameState.data["gold"]
	GameState.data = {}
	_check(GameState.load_save() and GameState.data["gold"] == snapshot and GameState.chosen_option("wizard", 0) == "explosion", "the save round-trips (gold, talent picks)")
	print("MENU_PASS" if _fail == 0 else "MENU_FAIL: %d" % _fail)
	quit(0 if _fail == 0 else 1)
