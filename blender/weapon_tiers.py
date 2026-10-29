"""weapon_tiers.py - 6 weapon lines x 10 tiers (pure data, no bpy). Models are the shapes in weapon_shapes.py (plus the original
sword / hatchet / staff props) recoloured per tier with armor_tiers' metals; names are Diablo 2 base types (no uniques).
Lines: melee one hand, melee two hands, bow (two hands), crossbow (one hand), staff (two hands), wand (one hand).
`python3 blender/weapon_tiers.py` writes godot/data/weapon_tiers.json. Tier 1 of melee-1h / melee-2h / staff are Battleheart items 0 / 10 / 3.
All numbers [tuned]."""
import json
import os

import armor_tiers as at

METAL = at.METAL
WOODS = {1: (112, 74, 42), 2: (160, 126, 84), 3: (176, 146, 92), 4: (132, 70, 48), 5: (92, 60, 38), 6: (70, 46, 32),
         7: (44, 34, 30), 8: (214, 204, 176), 9: (118, 40, 30), 10: (34, 26, 34)}               # oak, ash, yew, cedar, walnut, dark oak, ebony, bone-white, bloodwood, blackwood
GEMS = {1: (110, 200, 255), 2: (80, 130, 230), 3: (80, 200, 120), 4: (230, 70, 70), 5: (170, 100, 220), 6: (240, 190, 70),
        7: (80, 230, 230), 8: (240, 240, 250), 9: (255, 90, 40), 10: (255, 60, 220)}
BONE = {t: c for t, c in zip(range(1, 11), [(200, 190, 160)] * 5 + [(214, 206, 176), (180, 172, 150), (150, 140, 120), (120, 90, 80), (60, 50, 60)])}

# line -> (id base, label, class list, hand, power tier 1, power tier 10, rows[tier] = (name, shape, tier-1 bh item or None))
LINES = {
    "melee_1h": (400, "One-hand melee", ["knight", "paladin", "rogue", "barbarian", "champion", "duelist", "brigand"], {
        1: ("Iron Sword", "sword_iron"), 2: ("Hand Axe", "hatchet"), 3: ("Mace", "mace"), 4: ("Scimitar", "scimitar"),
        5: ("Cleaver", "hatchet"), 6: ("Flanged Mace", "mace"), 7: ("Sabre", "scimitar"), 8: ("Tomahawk", "hatchet"),
        9: ("Morning Star", "mace"), 10: ("Phase Blade", "scimitar")}),
    "melee_2h": (410, "Two-hand melee", ["knight", "paladin", "rogue", "barbarian", "champion"], {
        1: ("Longsword", "sword_long"), 2: ("Bardiche", "halberd"), 3: ("Maul", "maul"), 4: ("Claymore", "greatsword"),
        5: ("Great Axe", "great_axe"), 6: ("Halberd", "halberd"), 7: ("Flamberge", "greatsword"), 8: ("Great Maul", "maul"),
        9: ("Giant Thresher", "halberd"), 10: ("Colossus Blade", "greatsword")}),
    "bow": (420, "Bow", ["hunter", "piper"], {
        1: ("Short Bow", "bow_short"), 2: ("Long Bow", "bow_long"), 3: ("Composite Bow", "bow_composite"), 4: ("Short Battle Bow", "bow_short"),
        5: ("Long Battle Bow", "bow_long"), 6: ("Short War Bow", "bow_composite"), 7: ("Long War Bow", "bow_war"),
        8: ("Razor Bow", "bow_war"), 9: ("Hydra Bow", "bow_war"), 10: ("Rune Bow", "bow_war")}),
    "crossbow": (430, "Crossbow", ["hunter", "brigand"], {
        1: ("Light Crossbow", "xbow_light"), 2: ("Crossbow", "xbow_light"), 3: ("Heavy Crossbow", "xbow_heavy"), 4: ("Arbalest", "xbow_heavy"),
        5: ("Repeating Crossbow", "xbow_repeating"), 6: ("Siege Crossbow", "xbow_heavy"), 7: ("Ballista", "xbow_heavy"),
        8: ("Chu-Ko-Nu", "xbow_repeating"), 9: ("Colossus Crossbow", "xbow_heavy"), 10: ("Demon Crossbow", "xbow_repeating")}),
    "staff": (440, "Staff", ["wizard", "priest", "witch"], {
        1: ("Oakwood Staff", "staff_oak"), 2: ("Short Staff", "staff_oak"), 3: ("Long Staff", "staff_oak"), 4: ("Gnarled Staff", "staff_gnarled"),
        5: ("Battle Staff", "staff_battle"), 6: ("War Staff", "staff_war"), 7: ("Jo Staff", "staff_gnarled"), 8: ("Cedar Staff", "staff_battle"),
        9: ("Gothic Staff", "staff_war"), 10: ("Archon Staff", "staff_war")}),
    "wand": (450, "Wand", ["wizard", "priest", "witch"], {
        1: ("Wand", "wand_straight"), 2: ("Yew Wand", "wand_straight"), 3: ("Bone Wand", "wand_skull"), 4: ("Grim Wand", "wand_skull"),
        5: ("Burnt Wand", "wand_knob"), 6: ("Petrified Wand", "wand_knob"), 7: ("Tomb Wand", "wand_knob"), 8: ("Grave Wand", "wand_skull"),
        9: ("Unearthed Wand", "wand_knob"), 10: ("Lich Wand", "wand_skull")}),
}
# Weapon speed = a multiplier on the class's auto-attack cooldown (NOT the animation speed): one-hand weapons below 1, two-hand above,
# and the weapon type shifts it. [tuned]
SPEED = {"sword_iron": .9, "hatchet": .9, "scimitar": .8, "mace": 1.0,
         "sword_long": 1.2, "greatsword": 1.3, "halberd": 1.35, "great_axe": 1.45, "maul": 1.6,
         "bow_short": .9, "bow_composite": 1.0, "bow_war": 1.1, "bow_long": 1.2,
         "xbow_light": .9, "xbow_repeating": .7, "xbow_heavy": 1.2,
         "staff_oak": 1.2, "staff_gnarled": 1.3, "staff_battle": 1.4, "staff_war": 1.5,
         "wand_straight": .75, "wand_skull": .8, "wand_knob": .85}
STARTERS = {("melee_1h", 1): 0, ("melee_2h", 1): 10, ("staff", 1): 3}      # tier 1 kept as the existing Battleheart items


REF_T1, REF_T10 = 19.0, 65.0         # power per unit of weapon speed: the same DPS for every weapon type of a tier [tuned]


def ref_power(tier):
    """The DPS index of a tier: power / speed is this number for EVERY weapon of the tier (any type, any hands)."""
    return REF_T1 * (REF_T10 / REF_T1) ** ((tier - 1) / 9)


def power(line, tier):
    """Power (ATK) of a weapon: slower weapons hit harder so each tier has one DPS (power / speed)."""
    return round(ref_power(tier) * SPEED[LINES[line][3][tier][1]])


def piece_id(line, tier):
    base = {"sword_iron": "sword_iron", "sword_long": "sword_long", "staff_oak": "staff_oak"}
    if (line, tier) in STARTERS:
        return base[LINES[line][3][tier][1]]
    return "wpn_%s_%d" % (line, tier)


def recolour(tier):
    M, Md, Me = at.METALS[METAL[tier]] if tier > 1 else at.METALS["iron"]
    w = WOODS[tier]
    out = {"iron": M, "iron_dark": Md, "iron_edge": Me, "steel": tuple(min(255, int(v * 1.08)) for v in Me) if tier > 1 else Me,
           "brass": at.METALS[at.TRIM.get(tier, "brass")][0], "wood": w, "wood_dark": tuple(int(v * .66) for v in w),
           "crystal": GEMS[tier], "bone": BONE[tier], "gold": at.METALS["gold"][0]}
    if tier == 10:
        out.update({"iron_edge": at.METALS["gold"][2], "brass": at.METALS["gold"][0]})
    return out


def items():
    rows, shop = {}, []
    for line, (base, label, users, names) in LINES.items():
        for tier in range(1, 11):
            if (line, tier) in STARTERS:
                continue
            iid = base + tier
            p = power(line, tier)
            rows[str(iid)] = {"name": names[tier][0], "desc": "Tier %d %s." % (tier, label.lower()), "type": "weapon", "wline": line, "tier": tier,
                              "power": p, "price": int(round(ref_power(tier) ** 2 / 7 / 5.0) * 5), "usableBy": users, "model": piece_id(line, tier), "speed": SPEED[names[tier][1]]}
            shop.append({"id": iid, "minLevel": at.min_level(tier), "maxLevel": 999 if tier == 10 else at.min_level(tier) + 9})
    overrides = {}                                                       # the Battleheart starters with a model get the same rule (tier 1 index; the Rusty Carver tier 2)
    for bh, speed, tier in ((0, .9, 1), (1, .7, 1), (2, .85, 1), (3, 1.2, 1), (9, 1.1, 2), (10, 1.2, 1), (11, .9, 1)):
        overrides[str(bh)] = {"power": round(ref_power(tier) * speed), "speed": speed}
    return {"OVERRIDES": overrides, "_note": "The 3D side's weapon tiers (Diablo 2 base types). Generated by blender/weapon_tiers.py. power = ATK = speed x the tier's DPS index [tuned]; minLevel/maxLevel = shop levels [tuned].",
            "ITEMS": rows, "SHOP": shop}


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../godot/data/weapon_tiers.json")
    json.dump(items(), open(out, "w"), indent=1)
    print("wrote", out, [round(ref_power(t)) for t in range(1, 11)])
