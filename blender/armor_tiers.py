"""armor_tiers.py - the 30 armor sets (3 weights x 10 tiers), pure data, no bpy.

Every set is a HEAD piece plus a BODY armor, built from the EXISTING models in build_gear.py and only recoloured (metals, leathers,
cloths), so no new geometry. Tier 1 is the starter (Scale Mail / Soft Leather Garb / Cotton Cloak with their own colours); tier 10 is
for the last stage. `python3 blender/armor_tiers.py` writes godot/data/armor_tiers.json (the item rows, shop levels and gear ids).
Defence ("power", the DEF the item adds) rises geometrically with the tier and every number is [tuned].
Palette sources: bronze, iron, steel, brass, gold, mithril (light blue), adamantine (red), draconite (black).
"""
import json
import os

METALS = {            # main, dark, edge
    "bronze": ((176, 118, 56), (120, 76, 34), (222, 164, 88)),
    "iron": ((100, 104, 114), (62, 66, 76), (150, 154, 164)),
    "steel": ((172, 180, 194), (110, 118, 134), (230, 236, 246)),
    "brass": ((200, 158, 62), (142, 104, 34), (240, 206, 104)),
    "gold": ((232, 190, 64), (176, 128, 30), (255, 234, 130)),
    "mithril": ((118, 190, 238), (66, 128, 190), (206, 238, 255)),
    "adamant": ((178, 30, 34), (110, 16, 22), (240, 90, 78)),
    "draconite": ((34, 34, 44), (16, 16, 24), (88, 84, 112)),
}
# leather colourways per tier: main, dark, tan, boiled (the base models use leather / leather_dark / leather_tan / leather_boiled)
LEATHERS = {
    2: ((126, 69, 35), (80, 44, 22), (158, 108, 64), (102, 62, 38)), 3: ((110, 64, 36), (70, 40, 24), (140, 96, 60), (92, 56, 34)),
    4: ((96, 60, 40), (60, 38, 26), (128, 90, 60), (84, 54, 36)), 5: ((64, 98, 56), (40, 64, 36), (96, 130, 78), (52, 82, 46)),
    6: ((210, 192, 156), (150, 130, 96), (232, 216, 182), (180, 160, 124)), 7: ((60, 90, 130), (36, 56, 90), (96, 130, 170), (48, 74, 112)),
    8: ((120, 36, 30), (74, 20, 20), (160, 62, 48), (96, 28, 26)), 9: ((44, 40, 44), (22, 20, 26), (70, 64, 70), (34, 30, 36)),
    10: ((36, 32, 40), (16, 14, 22), (60, 54, 64), (28, 24, 32)),
}
CLOTHS = {2: (190, 170, 130), 3: (124, 128, 138), 5: (56, 122, 72), 7: (96, 156, 214), 9: (34, 30, 44)}      # cotton for the cloaks / hoods
CRIMSON = ((150, 30, 40), (92, 18, 26), (200, 70, 74))                                                      # a recolour of the gray wizard cloth
TRIM = {2: "bronze", 3: "brass", 4: "iron", 5: "bronze", 6: "brass", 7: "steel", 8: "draconite", 9: "adamant", 10: "gold"}   # buckles / clasps ("brass" in the base models)
METAL = {2: "bronze", 3: "iron", 4: "steel", 5: "brass", 6: "gold", 7: "mithril", 8: "adamant", 9: "draconite", 10: "draconite"}

# tier -> (item name, body model, head model); the body models are build_gear.py pieces, heads too
SETS = {
    "heavy": {1: ("Scale Mail", "armor_scale_mail", "helm_iron"),
              2: ("Bronze Splint Mail", "armor_splint_mail", "helm_spangenhelm"), 3: ("Iron Plate", "armor_breast_plate", "helm_sallet"),
              4: ("Steel Scale Mail", "armor_scale_mail", "helm_barbute"), 5: ("Brass Splint Mail", "armor_splint_mail", "helm_bascinet"),
              6: ("Sunforged Plate", "armor_breast_plate", "helm_armet"), 7: ("Mithril Scale Mail", "armor_scale_mail", "helm_burgonet"),
              8: ("Adamant Splint Mail", "armor_splint_mail", "helm_zischagge"), 9: ("Draconite Plate", "armor_breast_plate", "helm_hounskull"),
              10: ("Dragonlord Scale Mail", "armor_scale_mail", "helm_great")},
    "medium": {1: ("Soft Leather Garb", "armor_leather", "cap_leather"),
               2: ("Leather Armor", "armor_leather_armor", "helm_shishak"), 3: ("Hard Leather Armor", "armor_hard_leather", "helm_sugarloaf"),
               4: ("Ring Mail", "armor_ring_mail", "helm_cabasset"), 5: ("Brass Chain Mail", "armor_chain_mail", "helm_morion"),
               6: ("Gilded Scale Hauberk", "armor_scale_hauberk", "helm_kettle_hat"), 7: ("Mithril Ring Mail", "armor_ring_mail", "helm_frog_mouth"),
               8: ("Adamant Scale Hauberk", "armor_scale_hauberk", "helm_sallet"), 9: ("Draconite Chain Mail", "armor_chain_mail", "helm_barbute"),
               10: ("Dragonscale Hauberk", "armor_scale_hauberk", "helm_zischagge")},
    "light": {1: ("Cotton Cloak", "armor_cloak", "hood_cloth"),
              2: ("Linen Robe", "robe:brown", "hat:brown"), 3: ("Greyweave Cloak", "armor_cloak", "hood_cloth"),
              4: ("Silk Robe", "robe:blue", "hat:blue"), 5: ("Verdant Cloak", "armor_cloak", "hood_cloth"),
              6: ("Gilded White Robe", "robe:white", "hat:white"), 7: ("Mithril Cloak", "armor_cloak", "hood_cloth"),
              8: ("Crimson Battlemage Robe", "robe:gray", "hat:gray"), 9: ("Draconite Cloak", "armor_cloak", "hood_cloth"),
              10: ("Archmage's Robe", "robe:purple", "hat:purple")},
}
ID_BASE = {"heavy": 300, "medium": 310, "light": 320}
START_ITEM = {"heavy": 4, "medium": 5, "light": 6}               # tier 1 = the Battleheart starters
POWER_T1 = {"heavy": 20, "medium": 12, "light": 8}
POWER_T10 = {"heavy": 54, "medium": 42, "light": 32}
USABLE = ["knight", "rogue", "brigand", "piper", "witch", "champion", "duelist", "hunter", "jester", "paladin", "wizard", "priest", "barbarian"]


def power(weight, tier):
    a, c = POWER_T1[weight], POWER_T10[weight]
    return round(a * (c / a) ** ((tier - 1) / 9))


def min_level(tier):
    return round((tier - 1) * 3.2)


def piece_ids(weight, tier):
    """(body gear id, head gear id) of a set; tier 1 uses the original pieces."""
    if tier == 1:
        return SETS[weight][1][1], SETS[weight][1][2]
    return "armor_%s_%d" % (weight, tier), "head_%s_%d" % (weight, tier)


def recolour(weight, tier, part):
    """{material: (r, g, b)} overrides for one built piece (part 'armor' or 'head')."""
    out = {}
    M, Md, Me = METALS[METAL[tier]]
    out.update({"iron": M, "iron_dark": Md, "iron_edge": Me, "bronze": M, "mail": tuple((a + b) // 2 for a, b in zip(M, Md))})
    T = METALS[TRIM[tier]][0]
    out["brass"] = T
    if tier == 10:
        out.update({"iron_edge": METALS["gold"][2], "brass": METALS["gold"][0], "bronze": METALS["adamant"][0]})
    lt = LEATHERS.get(tier)
    if lt:
        out.update({"leather": lt[0], "leather_dark": lt[1], "leather_tan": lt[2], "leather_boiled": lt[3]})
    cloth = CLOTHS.get(tier)
    if cloth:
        out.update({"cotton": cloth, "cotton_dark": tuple(int(v * .7) for v in cloth), "hood": tuple(int(v * .85) for v in cloth)})
    if weight == "light":
        body = SETS["light"][tier][1 if part == "armor" else 2]
        if body.endswith(":gray"):                                          # the gray wizard cloth becomes crimson (adamantine tier)
            for suffix, col in zip(("", "_dark", "_light"), CRIMSON):
                out["wz_gray" + suffix] = col
    return out


def items():
    rows, shop = {}, []
    for weight in ("heavy", "medium", "light"):
        for tier in range(2, 11):
            iid = ID_BASE[weight] + tier
            body, head = piece_ids(weight, tier)
            p = power(weight, tier)
            rows[str(iid)] = {"name": SETS[weight][tier][0], "desc": "Tier %d %s armor set (helm and body)." % (tier, weight),
                              "type": "armor", "weight": weight, "tier": tier, "power": p, "price": int(round(p * p / 9 / 5.0) * 5),
                              "usableBy": USABLE, "model": body, "head": head}
            shop.append({"id": iid, "minLevel": min_level(tier), "maxLevel": 999 if tier == 10 else min_level(tier) + 9})
    return {"_note": "The 3D side's armor tiers 2-10 for light / medium / heavy (tier 1 = Battleheart items 4, 5, 6). Generated by blender/armor_tiers.py. "
                     "power = DEF [tuned]; minLevel/maxLevel = shop levels [tuned].", "ITEMS": rows, "SHOP": shop}


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../godot/data/armor_tiers.json")
    json.dump(items(), open(out, "w"), indent=1)
    print("wrote", out, [power("heavy", t) for t in range(1, 11)], [power("medium", t) for t in range(1, 11)], [power("light", t) for t in range(1, 11)])
