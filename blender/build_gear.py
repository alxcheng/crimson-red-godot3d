"""build_gear.py - headpieces, body armour and weapons for the shared Crimson Red rig.

Run (headless):
    blender --background --python blender/build_gear.py -- godot/models/gear [piece_id ...]

Conventions (so any character can wear any piece):
  * Headpieces and armour are skinned meshes on the SAME 24-bone skeleton (export carries the
    rest-pose armature; Godot binds skins by bone name, so the mesh can be re-parented under any
    character's Skeleton3D). Every loft is rigid on one bone, like the bodies.
  * Gear sits ~1.5-3 cm outside the base body so it never z-fights; it is built for the Knight /
    mannequin proportions (head x-widening included).
  * Weapons are props: origin at the grip, blade/shaft along +Z, no armature. They attach to
    hand_R exactly like sword.glb.
  * gear.json lists every piece: id, display name, slot, file, and the Battleheart item it
    represents in main-game/data/bh_items.lua (so the Godot port can map item id -> model).
All shapes/colours are CR-original art direction [tuned]; item names/ids come from bh_items.lua.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_humanoid as h
import armor_tiers as tiers
import weapon_shapes
import weapon_tiers as wtiers
import build_monsters as m   # shared rod / panel / bulb helpers and the iron/leather palette

EXTRA = {
    "brass": (196, 154, 60), "gold": (226, 186, 70), "wood": (112, 74, 42), "wood_dark": (74, 48, 26),
    "cotton": (196, 184, 160), "cotton_dark": (150, 138, 116), "cloth_red": (150, 30, 36),
    "leather_tan": (158, 108, 64), "leather_boiled": (102, 62, 38), "bronze": (178, 132, 64),
    "mail": (104, 108, 114), "rust": (122, 78, 52), "crystal": (110, 200, 255), "hood": (66, 74, 62),
}
for key, colour in EXTRA.items():
    h.COLOURS[key] = colour
    if key not in h.MATS:
        h.MATS.append(key)

# Wizard robe and hat colourways: main cloth, darker lining/trim, lighter highlight.
WIZARD_COLOURS = {
    "black":  ((30, 28, 36), (16, 14, 20), (72, 66, 90)),
    "brown":  ((122, 82, 48), (82, 54, 30), (166, 118, 74)),
    "blue":   ((50, 84, 172), (30, 54, 118), (100, 136, 214)),
    "green":  ((56, 132, 70), (34, 90, 48), (104, 172, 112)),
    "purple": ((114, 60, 162), (74, 36, 114), (164, 112, 204)),
    "gray":   ((132, 134, 142), (90, 92, 100), (178, 180, 188)),
    "white":  ((234, 232, 224), (190, 186, 174), (252, 252, 248)),
}
for _name, (_main, _dark, _light) in WIZARD_COLOURS.items():
    for _suffix, _col in (("", _main), ("_dark", _dark), ("_light", _light)):
        EXTRA["wz_" + _name + _suffix] = _col
for key, colour in EXTRA.items():
    h.COLOURS[key] = colour
    if key not in h.MATS:
        h.MATS.append(key)

HEAD_X = 1.18   # the bodies widen the head bone by this factor; headgear must too


def ring_head(rings):
    """Apply the head-bone widening to (cx, cy, cz, rx, ry) rings."""
    return [(cx * HEAD_X, cy, cz, rx * HEAD_X, ry) for cx, cy, cz, rx, ry in rings]


# ------------------------------------------------------------------ headpieces
def helm_iron(b):
    """Kettle helm: dome with a brim, nasal bar and a short neck guard. Face stays open."""
    b.loft("head", "iron", ring_head([(0, .015, 1.775, .125, .125), (0, .015, 1.84, .125, .125),
                                     (0, .012, 1.91, .10, .105), (0, .01, 1.965, .062, .065),
                                     (0, .01, 1.995, .018, .02)]), 8)
    b.loft("head", "iron_dark", ring_head([(0, .01, 1.765, .148, .145), (0, .01, 1.785, .148, .145)]), 8)
    b.loft("head", "iron_edge", ring_head([(0, -.128, 1.88, .011, .009), (0, -.132, 1.70, .011, .009)]), box=True)
    b.loft("head", "iron", ring_head([(0, .085, 1.78, .105, .05), (0, .115, 1.69, .095, .03),
                                     (0, .118, 1.63, .07, .02)]), 8)
    b.loft("head", "brass", ring_head([(0, .012, 1.8, .13, .13), (0, .012, 1.815, .13, .13)]), 8)


def helm_great(b):
    """Great helm: full-face steel pot with an eye slit and breath holes."""
    b.loft("head", "iron", ring_head([(0, .005, 1.60, .105, .105), (0, .005, 1.70, .13, .13),
                                     (0, .005, 1.84, .13, .13), (0, .008, 1.93, .105, .108),
                                     (0, .01, 1.975, .06, .06)]), 8)
    b.loft("head", "iron_dark", ring_head([(0, .005, 1.965, .068, .07), (0, .005, 1.99, .068, .07)]), 8)
    m.panel(b, "head", "eye", [(-.085 * HEAD_X, -.128, 1.775), (.085 * HEAD_X, -.128, 1.775),
                               (.085 * HEAD_X, -.128, 1.752), (-.085 * HEAD_X, -.128, 1.752)])
    for z in (1.68, 1.65, 1.62):
        m.panel(b, "head", "iron_dark", [(-.03 * HEAD_X, -.126, z), (.03 * HEAD_X, -.126, z),
                                         (.03 * HEAD_X, -.126, z - .012), (-.03 * HEAD_X, -.126, z - .012)])
    b.loft("head", "iron_edge", ring_head([(0, -.126, 1.95, .008, .006), (0, -.126, 1.60, .008, .006)]), box=True)
    b.loft("head", "cloth_red", ring_head([(0, .01, 1.99, .012, .045), (0, .02, 2.10, .008, .07),
                                          (0, .075, 2.07, .006, .05)]), 4)    # short crest


def cap_leather(b):
    """Soft leather skullcap with a stitched brow band and ear flaps."""
    b.loft("head", "leather", ring_head([(0, .015, 1.78, .115, .115), (0, .015, 1.84, .115, .115),
                                        (0, .012, 1.91, .095, .098), (0, .01, 1.955, .05, .055)]), 8)
    b.loft("head", "leather_dark", ring_head([(0, .012, 1.77, .121, .121), (0, .012, 1.795, .121, .121)]), 8)
    for sign in (-1, 1):
        b.loft("head", "leather", [(sign * .125 * HEAD_X, .02, 1.78, .02, .05), (sign * .128 * HEAD_X, .03, 1.69, .018, .04),
                                   (sign * .12 * HEAD_X, .03, 1.65, .012, .025)], 5)
    m.panel(b, "head", "brass", [(-.012, -.114, 1.80), (.012, -.114, 1.80), (.012, -.114, 1.77), (-.012, -.114, 1.77)])


def hood_cloth(b):
    """Cloth hood with a face opening, falling into a short cowl on the shoulders."""
    b.loft("head", "hood", ring_head([(0, .02, 1.76, .125, .13), (0, .025, 1.84, .13, .135),
                                     (0, .02, 1.92, .105, .11), (0, .015, 1.975, .05, .055),
                                     (0, .03, 1.99, .012, .015)]), 7)
    b.loft("head", "hood", ring_head([(0, .075, 1.78, .115, .06), (0, .09, 1.68, .12, .06),
                                     (0, .09, 1.60, .13, .06)]), 7)
    b.loft("neck", "hood", [(0, .02, 1.66, .13, .12), (0, .02, 1.56, .185, .15), (0, .0, 1.47, .25, .155)], 8)
    b.loft("neck", "cotton_dark", [(0, -.02, 1.585, .14, .135), (0, -.02, 1.56, .19, .152)], 8)


# ---------------------------------------------------------------------- armour
def scale_rows(b, bone, mat, z0, z1, r0, r1, rows, depth, cx=0.0):
    """Overlapping rows of scales: each row flares out at its lower edge, giving the sawtooth
    silhouette of scale mail. r0/r1 = (rx, ry) at z0 (bottom) and z1 (top)."""
    for i in range(rows):
        lo, hi = i / rows, (i + 1) / rows
        zb, zt = z0 + (z1 - z0) * lo, z0 + (z1 - z0) * hi
        rb = (r0[0] + (r1[0] - r0[0]) * lo, r0[1] + (r1[1] - r0[1]) * lo)
        rt = (r0[0] + (r1[0] - r0[0]) * hi, r0[1] + (r1[1] - r0[1]) * hi)
        b.loft(bone, mat, [(cx, 0, zb, rb[0] + depth, rb[1] + depth), (cx, 0, zb + (zt - zb) * .35, rb[0], rb[1]),
                           (cx, 0, zt, rt[0], rt[1])], 8)


def full_limbs(b, arm, leg, trim, boot, glove, cap=None):
    """Cover both arms (upper arm, forearm, hand) and both legs (thigh, shin, foot, toe) so every
    armour is a full-body set. Materials: arm/leg = main layer, trim = bands, boot/glove = ends,
    cap = knee and elbow caps."""
    cap = cap or trim
    for s, sgn in (("L", 1), ("R", -1)):
        ax, lx = sgn * .27, sgn * .10
        b.loft(f"upper_arm_{s}", arm, [(ax, 0, 1.44, .086, .08), (ax, 0, 1.34, .093, .087), (ax, 0, 1.25, .084, .079),
                                      (ax, 0, 1.15, .064, .063)], 8)
        m.bulb(b, f"forearm_{s}", cap, (ax, 0, 1.15), (.07, .07, .05), 7)                          # elbow
        b.loft(f"forearm_{s}", arm, [(ax, 0, 1.16, .064, .063), (ax, 0, 1.06, .075, .071), (ax, 0, .88, .055, .055)], 8)
        b.loft(f"forearm_{s}", trim, [(ax, 0, 1.0, .08, .075), (ax, 0, .975, .08, .075)], 8)
        b.loft(f"hand_{s}", glove, [(ax, 0, .89, .064, .058), (ax, 0, .80, .07, .062), (ax, 0, .72, .05, .044)], 7)
        b.loft(f"thigh_{s}", leg, [(lx, 0, .94, .122, .122), (lx, 0, .78, .115, .115), (lx, 0, .62, .097, .099),
                                  (lx, 0, .50, .08, .082)], 8)
        b.loft(f"thigh_{s}", trim, [(lx, 0, .79, .12, .12), (lx, 0, .765, .12, .12)], 8)
        m.bulb(b, f"shin_{s}", cap, (lx, -.012, .50), (.085, .09, .055), 7)                          # knee
        b.loft(f"shin_{s}", leg, [(lx, 0, .49, .082, .087), (lx, 0, .40, .088, .098), (lx, 0, .24, .072, .08),
                                 (lx, 0, .12, .058, .064)], 8)
        b.loft(f"shin_{s}", trim, [(lx, 0, .30, .084, .092), (lx, 0, .275, .084, .092)], 8)
        b.loft(f"foot_{s}", boot, [(lx, .07, .055, .05, .05), (lx, -.03, .055, .06, .054), (lx, -.09, .046, .058, .046)], 7, axis="Y")
        b.loft(f"toe_{s}", boot, [(lx, -.09, .046, .058, .046), (lx, -.15, .036, .047, .038), (lx, -.19, .03, .026, .026)], 7, axis="Y")


def armor_scale_mail(b):
    """Scale Mail (item 4): full-body scale harness: hauberk, tassets, pauldrons, collar, scale arms and legs."""
    scale_rows(b, "spine1", "iron", 1.04, 1.27, (.172, .118), (.236, .142), 3, .012)
    scale_rows(b, "spine2", "iron", 1.26, 1.47, (.228, .142), (.282, .142), 3, .012)
    b.loft("spine2", "iron_dark", [(0, 0, 1.47, .15, .105), (0, 0, 1.55, .11, .09)], 8)          # gorget
    b.loft("hips", "iron_dark", [(0, 0, 1.03, .178, .124), (0, 0, 1.0, .186, .13)], 8)           # belt
    m.panel(b, "hips", "brass", [(-.035, -.134, 1.04), (.035, -.134, 1.04), (.035, -.134, .985), (-.035, -.134, .985)])
    for z0, z1, k in ((.97, .90, 1.0), (.90, .83, 1.05), (.83, .77, 1.1)):                        # tasset skirt
        b.loft("hips", "iron", [(0, 0, z0, .185 * k, .13 * k), (0, 0, z1, .19 * k, .134 * k)], 8)
    for s, x in (("L", 1), ("R", -1)):
        m.bulb(b, f"clavicle_{s}", "iron", (x * .27, 0, 1.465), (.13, .12, .085), 8)
        b.loft(f"clavicle_{s}", "iron_dark", [(x * .27, 0, 1.43, .14, .13), (x * .27, 0, 1.40, .15, .14)], 8)
    full_limbs(b, arm="iron", leg="iron", trim="iron_dark", boot="iron_dark", glove="iron", cap="iron_edge")


def armor_leather_garb(b):
    """Soft Leather Garb (item 5): full leather outfit: jerkin, belt and pouch, sleeves, trousers, boots, gloves."""
    b.loft("spine1", "leather", [(0, 0, 1.04, .165, .115), (0, 0, 1.16, .188, .128), (0, 0, 1.28, .232, .138)], 8)
    b.loft("spine2", "leather", [(0, 0, 1.26, .225, .138), (0, 0, 1.36, .262, .152), (0, 0, 1.45, .276, .138),
                                (0, 0, 1.49, .17, .10)], 8)
    b.loft("spine2", "leather_dark", [(0, 0, 1.47, .15, .11), (0, 0, 1.53, .10, .085)], 8)        # collar
    b.loft("hips", "leather_dark", [(0, 0, 1.05, .178, .124), (0, 0, 1.0, .186, .13)], 8)         # belt
    m.panel(b, "hips", "brass", [(-.025, -.134, 1.045), (.025, -.134, 1.045), (.025, -.134, .995), (-.025, -.134, .995)])
    b.loft("hips", "leather", [(.18, -.04, .98, .045, .05), (.185, -.04, .90, .05, .055)], 6)      # pouch
    for z in (1.12, 1.2, 1.3, 1.38):
        m.panel(b, "spine1" if z < 1.26 else "spine2", "leather_dark",
                [(-.02, -.152 if z > 1.26 else -.132, z), (.02, -.152 if z > 1.26 else -.132, z),
                 (.02, -.152 if z > 1.26 else -.132, z - .012), (-.02, -.152 if z > 1.26 else -.132, z - .012)])
    for s, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s}", "leather", [(x * .27, 0, 1.50, .085, .08), (x * .27, 0, 1.44, .125, .115), (x * .27, 0, 1.38, .115, .105)], 7)
    b.loft("hips", "leather_dark", [(0, 0, .99, .182, .127), (0, 0, .86, .19, .132)], 8)          # trousers waist
    full_limbs(b, arm="leather", leg="leather_dark", trim="brass", boot="leather", glove="leather_dark", cap="leather")


def armor_cotton_cloak(b):
    """Cotton Cloak (item 6): a full cotton outfit with a long back cloak on a clasped collar.
    Rigid: no cloth bones in the rig."""
    b.loft("neck", "cotton", [(0, 0, 1.50, .15, .105), (0, 0, 1.58, .11, .09)], 8)
    b.loft("neck", "brass", [(0, -.1, 1.52, .02, .012), (0, -.105, 1.50, .02, .012)], 6, axis="Y")
    b.loft("spine2", "cotton", [(0, .13, 1.50, .28, .03), (0, .15, 1.36, .30, .035), (0, .16, 1.26, .31, .035)], box=True)
    b.loft("spine1", "cotton", [(0, .16, 1.28, .31, .035), (0, .18, 1.16, .325, .04), (0, .19, 1.04, .335, .04)], box=True)
    b.loft("hips", "cotton_dark", [(0, .19, 1.04, .335, .04), (0, .21, .86, .35, .045), (0, .22, .72, .36, .045)], box=True)
    for s, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s}", "cotton", [(x * .27, 0, 1.50, .10, .09), (x * .27, 0, 1.43, .14, .13), (x * .27, 0, 1.36, .12, .11)], 7)
    # Full cotton outfit under the cloak: tunic, sleeves, trousers, wrapped boots and gloves.
    b.loft("spine1", "cotton", [(0, 0, 1.04, .163, .113), (0, 0, 1.16, .186, .127), (0, 0, 1.28, .23, .137)], 8)
    b.loft("spine2", "cotton", [(0, 0, 1.26, .223, .137), (0, 0, 1.36, .26, .151), (0, 0, 1.45, .274, .137), (0, 0, 1.49, .168, .10)], 8)
    b.loft("hips", "cotton_dark", [(0, 0, 1.03, .176, .122), (0, 0, .99, .184, .128)], 8)
    b.loft("hips", "cotton", [(0, 0, .99, .182, .127), (0, 0, .86, .19, .132)], 8)
    full_limbs(b, arm="cotton", leg="cotton", trim="cotton_dark", boot="leather_dark", glove="cotton_dark", cap="cotton_dark")



# ------------------------------------------------------------------ medieval helmet set
# Distinct historical types (no two share a silhouette): nasal helm and great helm already exist above
# (helm_iron, helm_great); the set below adds spangenhelm, sugarloaf, bascinet, hounskull, sallet, barbute,
# armet, frog-mouth, burgonet, morion, kettle hat, cabasset, zischaegge and shishak.
def _shell(b, mat, pts, sides=8):
    """Head shell from (z, rx, ry, cy) rings."""
    b.loft("head", mat, ring_head([(0, cy, z, rx, ry) for z, rx, ry, cy in pts]), sides)


def _slit(b, z, half, y=-.139, drop=.016):
    m.panel(b, "head", "eye", [(-half * HEAD_X, y, z + drop / 2), (half * HEAD_X, y, z + drop / 2),
                               (half * HEAD_X, y - .002, z - drop / 2), (-half * HEAD_X, y - .002, z - drop / 2)])


def _studs(b, mat, zs, y, half, n=5):
    for z in zs:
        for i in range(n):
            x = -half + 2 * half * i / (n - 1)
            b.loft("head", mat, [(x * HEAD_X, y, z, .008, .008), (x * HEAD_X, y - .008, z, .006, .006)], 4)


def _aventail(b, top=1.66, bottom=1.46):
    """Mail collar around the neck (below the chin)."""
    b.loft("head", "mail", ring_head([(0, .02, top, .13, .12), (0, .02, (top + bottom) / 2, .16, .14), (0, .02, bottom, .22, .17)]), 8)


def helm_spangenhelm(b):
    """Spangenhelm: a conical segmented helm, four riveted ribs to a brow band, a nasal bar."""
    _shell(b, "iron", [(1.775, .128, .128, .012), (1.86, .118, .118, .012), (1.95, .088, .09, .012), (2.02, .04, .042, .012), (2.06, .008, .008, .012)])
    b.loft("head", "brass", ring_head([(0, .012, 1.765, .138, .138), (0, .012, 1.805, .138, .138)]), 8)
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        m.rod(b, "head", "iron_edge", (math.cos(a) * .135 * HEAD_X, .012 + math.sin(a) * .135, 1.79),
              (0, .012, 2.065), .011, 5, end_radius=.005)
    b.loft("head", "iron_edge", ring_head([(0, -.14, 1.80, .012, .008), (0, -.145, 1.67, .012, .008)]), box=True)


def helm_sugarloaf(b):
    """Sugarloaf helm: an enclosed tall conical helm, a horizontal eye slit and breath holes, a raised face ridge."""
    _shell(b, "iron_dark", [(1.57, .135, .125, .01), (1.70, .142, .132, .01), (1.85, .138, .13, .01), (1.98, .105, .1, .01), (2.08, .045, .045, .01), (2.13, .006, .006, .01)], 9)
    _slit(b, 1.78, .09)
    b.loft("head", "iron", ring_head([(0, -.135, 2.0, .012, .014), (0, -.145, 1.62, .012, .014)]), box=True)
    for i in range(6):
        for j in range(2):
            m.panel(b, "head", "eye", [((-.07 + i * .028) * HEAD_X - .004, -.14, 1.68 - j * .035 + .004), ((-.07 + i * .028) * HEAD_X + .004, -.14, 1.68 - j * .035 + .004),
                                       ((-.07 + i * .028) * HEAD_X + .004, -.141, 1.68 - j * .035 - .004), ((-.07 + i * .028) * HEAD_X - .004, -.141, 1.68 - j * .035 - .004)])


def helm_bascinet(b):
    """Bascinet: a tall pointed skull, face open, with a mail aventail down to the shoulders."""
    _shell(b, "iron", [(1.74, .13, .13, .015), (1.84, .13, .13, .02), (1.94, .11, .115, .03), (2.03, .065, .07, .045), (2.09, .02, .02, .055)])
    b.loft("head", "iron_edge", ring_head([(0, .015, 1.735, .14, .14), (0, .015, 1.76, .14, .14)]), 8)
    _aventail(b, 1.64, 1.46)
    b.loft("head", "mail", ring_head([(0, .03, 1.80, .145, .14), (0, .03, 1.70, .15, .145), (0, .03, 1.64, .15, .14)]), 8)  # cheeks and nape


def helm_hounskull(b):
    """Hounskull: a bascinet with a snouted visor (the pig-faced look), pivoted at the brow, mail collar below."""
    helm_bascinet(b)
    b.loft("head", "iron", [(0, -.105, 1.745, .105, .07), (0, -.18, 1.71, .08, .055), (0, -.26, 1.675, .045, .035), (0, -.285, 1.67, .018, .02)], 7, axis="Y")
    _slit(b, 1.775, .075, y=-.185)
    for sx in (-1, 1):
        b.loft("head", "brass", [(sx * .155 * HEAD_X, -.02, 1.80, .014, .014), (sx * .165 * HEAD_X, -.02, 1.80, .018, .018)], 5, axis="Y")


def helm_sallet(b):
    """Sallet: a rounded skull sweeping into a long tail at the back, a brow slit and a flat chin guard."""
    _shell(b, "iron", [(1.72, .128, .128, .012), (1.83, .13, .13, .012), (1.93, .108, .11, .014), (2.0, .05, .055, .016), (2.025, .01, .01, .016)])
    b.loft("head", "iron", ring_head([(0, .10, 1.86, .12, .035), (0, .17, 1.72, .115, .03), (0, .245, 1.60, .10, .028)]), box=True)       # tail
    b.loft("head", "iron_edge", ring_head([(0, -.135, 1.80, .115, .014), (0, -.14, 1.72, .115, .014)]), box=True)                        # brow plate
    b.loft("head", "iron", ring_head([(0, -.128, 1.70, .105, .02), (0, -.14, 1.60, .09, .02)]), box=True)                                 # chin guard
    _slit(b, 1.735, .09, y=-.145)
    _studs(b, "brass", [1.81], -.14, .09, 4)


def helm_barbute(b):
    """Barbute: a rounded helm with a Y-shaped face opening: brow bar, nose bar, cheek plates and a deep neck."""
    _shell(b, "iron", [(1.80, .127, .125, .012), (1.89, .127, .125, .012), (1.97, .095, .095, .012), (2.02, .04, .04, .012), (2.05, .008, .008, .012)])
    b.loft("head", "iron_dark", ring_head([(0, .012, 1.78, .135, .133), (0, .012, 1.805, .135, .133)]), 8)
    for sx in (-1, 1):
        b.loft("head", "iron", ring_head([(sx * .125, 0, 1.78, .018, .115), (sx * .13, .01, 1.70, .018, .12), (sx * .12, .03, 1.60, .018, .105)]), box=True)
    b.loft("head", "iron", ring_head([(0, .105, 1.78, .125, .03), (0, .135, 1.60, .115, .03)]), box=True)                                 # back
    b.loft("head", "iron_edge", ring_head([(0, -.135, 1.80, .115, .012), (0, -.135, 1.77, .115, .012)]), box=True)                        # brow
    b.loft("head", "iron_edge", ring_head([(0, -.14, 1.78, .012, .01), (0, -.145, 1.64, .012, .01)]), box=True)                           # nose bar
    _studs(b, "brass", [1.795], -.138, .1, 5)


def helm_armet(b):
    """Armet: a smooth closed helm with a hinged visor, a ridged comb, and a rolled rondel collar."""
    _shell(b, "iron", [(1.56, .125, .12, .01), (1.68, .138, .132, .01), (1.82, .138, .132, .012), (1.94, .112, .11, .016), (2.0, .05, .055, .02), (2.02, .01, .01, .02)], 9)
    b.loft("head", "iron_edge", ring_head([(0, -.14, 1.84, .13, .02), (0, -.15, 1.64, .075, .025)]), box=True)                           # visor
    _slit(b, 1.775, .095, y=-.15)
    b.loft("head", "iron_dark", [(0, 0, 1.98, .012, .02), (0, .08, 2.02, .012, .03), (0, .15, 1.96, .012, .03)], 4, axis="Y") if False else None
    b.loft("head", "iron_edge", [(0, -.1, 2.0, .012, .02), (0, 0, 2.05, .012, .04), (0, .1, 2.0, .012, .035), (0, .14, 1.92, .012, .02)], 4, axis="Y")  # comb
    b.loft("head", "iron_edge", ring_head([(0, .01, 1.52, .20, .18), (0, .01, 1.56, .185, .165)]), 9)                                    # rondel collar
    _studs(b, "brass", [1.535], -.17, .1, 5)


def helm_frog_mouth(b):
    """Frog-mouth helm (jousting): a tall boxy shell with a forward-sloping face plate and a narrow slanted slit."""
    b.loft("head", "iron", ring_head([(0, .02, 1.53, .13, .12), (0, .02, 1.70, .14, .13), (0, .02, 1.88, .135, .13), (0, .02, 2.0, .115, .11), (0, .02, 2.06, .06, .06)]), 8)
    b.loft("head", "iron_edge", ring_head([(0, -.115, 1.95, .115, .02), (0, -.165, 1.80, .11, .025), (0, -.15, 1.60, .10, .025)]), box=True)   # sloped face plate
    m.panel(b, "head", "eye", [(-.1 * HEAD_X, -.205, 1.795), (.1 * HEAD_X, -.215, 1.835), (.1 * HEAD_X, -.215, 1.815), (-.1 * HEAD_X, -.205, 1.775)])
    b.loft("head", "iron_dark", ring_head([(0, -.105, 1.57, .13, .02), (0, -.13, 1.50, .1, .02)]), box=True)
    b.loft("head", "iron_edge", [(0, .1, 2.0, .01, .02), (0, .15, 1.92, .01, .06), (0, .16, 1.6, .01, .07)], 4, axis="Y") if False else None


def helm_burgonet(b):
    """Burgonet: an open helm with a high comb, a forward peak, hinged cheek-pieces and a neck lame."""
    _shell(b, "iron", [(1.76, .128, .13, .012), (1.86, .125, .128, .012), (1.95, .098, .1, .012), (2.0, .05, .055, .012), (2.03, .01, .01, .012)])
    b.loft("head", "iron_edge", [(0, -.17, 1.90, .012, .02), (0, -.08, 2.0, .014, .06), (0, .02, 2.06, .014, .085), (0, .12, 2.0, .014, .06), (0, .17, 1.9, .012, .03)], 4, axis="Y")  # comb
    b.loft("head", "iron_dark", ring_head([(0, -.115, 1.80, .12, .03), (0, -.20, 1.77, .105, .02)]), box=True)                           # peak
    for sx in (-1, 1):
        b.loft("head", "iron", ring_head([(sx * .13, -.01, 1.77, .016, .09), (sx * .135, 0, 1.69, .016, .095), (sx * .12, .015, 1.62, .014, .08)]), box=True)  # cheek
        m.bulb(b, "head", "brass", (sx * .135 * HEAD_X, -.01, 1.765), (.016, .016, .016), 5)
    b.loft("head", "iron_dark", ring_head([(0, .12, 1.76, .12, .02), (0, .15, 1.66, .105, .02)]), box=True)                              # neck lame
    b.loft("head", "brass", ring_head([(0, .012, 1.745, .14, .14), (0, .012, 1.77, .14, .14)]), 8)


def helm_morion(b):
    """Morion: a low dome, a tall curved comb, and a boat-shaped brim that sweeps up at the front and back."""
    _shell(b, "iron", [(1.78, .13, .13, .012), (1.87, .125, .125, .012), (1.95, .09, .095, .012), (1.99, .035, .04, .012)])
    b.loft("head", "iron_dark", [(0, -.31, 1.86, .13, .008), (0, -.2, 1.80, .15, .012), (0, 0, 1.775, .16, .012),
                                  (0, .2, 1.80, .15, .012), (0, .31, 1.88, .13, .008)], 8, axis="Y") if False else None
    b.loft("head", "iron_dark", ring_head([(0, 0, 1.775, .16, .25), (0, 0, 1.79, .14, .21)]), 10)                                          # brim
    b.loft("head", "iron_edge", [(0, -.24, 1.93, .01, .02), (0, -.14, 1.97, .012, .035), (0, 0, 2.02, .012, .05), (0, .14, 1.97, .012, .035), (0, .24, 1.93, .01, .02)], 4, axis="Y")
    _studs(b, "brass", [1.80], -.12, .1, 5)


def helm_kettle_hat(b):
    """Kettle hat: a shallow dome with a very wide, flat brim and a leather chin strap."""
    b.loft("head", "iron", ring_head([(0, .012, 1.785, .27, .27), (0, .012, 1.80, .24, .24), (0, .012, 1.815, .16, .16)]), 10)
    _shell(b, "iron", [(1.80, .155, .155, .012), (1.9, .145, .145, .012), (1.98, .095, .095, .012), (2.03, .03, .03, .012)], 9)
    b.loft("head", "iron_edge", ring_head([(0, .012, 1.785, .272, .272), (0, .012, 1.79, .268, .268)]), 10)
    for sx in (-1, 1):
        m.rod(b, "head", "leather", (sx * .14 * HEAD_X, 0, 1.78), (sx * .075, -.09, 1.585), .011, 4)


def helm_cabasset(b):
    """Cabasset: a pointed conical helm with a small brim and a drawn-out knob at the tip."""
    _shell(b, "iron", [(1.775, .13, .13, .012), (1.86, .125, .125, .012), (1.95, .1, .1, .014), (2.04, .06, .06, .02), (2.09, .02, .02, .03)])
    b.loft("head", "iron_dark", ring_head([(0, .012, 1.775, .185, .18), (0, .012, 1.795, .15, .15)]), 9)
    m.rod(b, "head", "iron_edge", (0, .03, 2.085), (0, .045, 2.16), .018, 5, end_radius=.004)
    b.loft("head", "brass", ring_head([(0, .012, 1.80, .133, .133), (0, .012, 1.82, .133, .133)]), 8)


def helm_zischagge(b):
    """Zischaegge (lobster-tail helm): a ridged skull, three overlapping tail lames, a peak and a three-bar visor."""
    _shell(b, "iron", [(1.76, .128, .128, .012), (1.86, .128, .128, .012), (1.95, .1, .102, .012), (2.0, .045, .05, .012), (2.02, .01, .01, .012)])
    for i, (z, w) in enumerate(((1.72, .115), (1.66, .105), (1.60, .095))):
        b.loft("head", "iron_dark", ring_head([(0, .12 + i * .03, z + .05, w, .03), (0, .13 + i * .035, z - .02, w + .01, .03)]), box=True)
    b.loft("head", "iron_dark", ring_head([(0, -.115, 1.82, .115, .03), (0, -.21, 1.80, .10, .02)]), box=True)                              # peak
    for sx in (-.07, 0.0, .07):
        m.rod(b, "head", "iron_edge", (sx * HEAD_X, -.14, 1.80), (sx * HEAD_X * 1.05, -.17, 1.60), .01, 5)
    b.loft("head", "iron_edge", [(0, -.015, 2.0, .012, .02), (0, .06, 2.015, .012, .03), (0, .13, 1.96, .012, .02)], 4, axis="Y")


def helm_shishak(b):
    """Shishak: a tall pointed eastern helm with a spike, a nasal, a cast brass face-mask and a mail curtain."""
    _shell(b, "iron", [(1.77, .13, .13, .012), (1.88, .124, .124, .012), (1.99, .09, .09, .012), (2.08, .04, .04, .012), (2.13, .008, .008, .012)])
    m.rod(b, "head", "iron_edge", (0, .012, 2.12), (0, .012, 2.2), .014, 5, end_radius=.003)
    b.loft("head", "brass", ring_head([(0, .012, 1.77, .138, .138), (0, .012, 1.80, .138, .138)]), 8)
    b.loft("head", "brass", ring_head([(0, -.128, 1.79, .105, .02), (0, -.138, 1.68, .095, .02), (0, -.12, 1.60, .06, .02)]), box=True)   # mask
    for sx in (-1, 1):
        m.panel(b, "head", "eye", [(sx * .02 * HEAD_X, -.15, 1.765), (sx * .075 * HEAD_X, -.15, 1.765), (sx * .075 * HEAD_X, -.15, 1.74), (sx * .02 * HEAD_X, -.15, 1.74)])
    b.loft("head", "mail", ring_head([(0, .03, 1.74, .15, .14), (0, .03, 1.62, .165, .15), (0, .03, 1.46, .22, .17)]), 8)


# ------------------------------------------------------------------ medium armor (Diablo 2's mid-weight body armors)
def _torso(b, mat, k=1.0, trim=None):
    """The shared torso: lower and upper body in one material (k widens it a little for bulkier armor)."""
    b.loft("spine1", mat, [(0, 0, 1.04, .165 * k, .115 * k), (0, 0, 1.16, .188 * k, .128 * k), (0, 0, 1.28, .232 * k, .138 * k)], 8)
    b.loft("spine2", mat, [(0, 0, 1.26, .225 * k, .138 * k), (0, 0, 1.36, .262 * k, .152 * k), (0, 0, 1.45, .276 * k, .138 * k), (0, 0, 1.49, .17, .10)], 8)
    b.loft("hips", trim or "leather_dark", [(0, 0, 1.05, .178 * k, .124 * k), (0, 0, 1.0, .186 * k, .13 * k)], 8)              # belt


def _buckle(b, y=-.136):
    m.panel(b, "hips", "brass", [(-.03, y, 1.045), (.03, y, 1.045), (.03, y, .99), (-.03, y, .99)])


def _bands(b, bone, mat_a, mat_b, z0, z1, r0, r1, n):
    """Thin horizontal bands, alternating two materials: rings of mail on a torso."""
    for i in range(n):
        z = z0 + (z1 - z0) * i / n
        z2 = z0 + (z1 - z0) * (i + 1) / n
        ra = (r0[0] + (r1[0] - r0[0]) * i / n, r0[1] + (r1[1] - r0[1]) * i / n)
        rb = (r0[0] + (r1[0] - r0[0]) * (i + 1) / n, r0[1] + (r1[1] - r0[1]) * (i + 1) / n)
        b.loft(bone, mat_a if i % 2 == 0 else mat_b, [(0, 0, z, ra[0] + .012, ra[1] + .012), (0, 0, z2, rb[0] + .012, rb[1] + .012)], 8)


def armor_leather_armor(b):
    """Leather Armor: a tan leather jerkin with a dark belt, shoulder straps and a short skirt of leather tabs."""
    _torso(b, "leather_tan")
    _buckle(b)
    b.loft("spine2", "leather_dark", [(0, 0, 1.47, .15, .11), (0, 0, 1.53, .10, .085)], 8)                      # collar
    for s_, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s_}", "leather_boiled", [(x * .27, 0, 1.49, .09, .085), (x * .27, 0, 1.44, .13, .118), (x * .27, 0, 1.38, .118, .108)], 7)
    for k in range(5):                                                                                              # skirt tabs
        a = (k - 2) * .55
        m.rod(b, "hips", "leather_tan", (math.sin(a) * .17, -math.cos(a) * .12, .98), (math.sin(a) * .2, -math.cos(a) * .15, .72), .05, 4)
    full_limbs(b, arm="leather_tan", leg="leather_dark", trim="leather_boiled", boot="leather_dark", glove="leather_dark", cap="leather_tan")


def armor_hard_leather(b):
    """Hard Leather Armor: boiled leather in overlapping bands with brass studs and domed shoulder guards."""
    scale_rows(b, "spine1", "leather_boiled", 1.04, 1.27, (.172, .118), (.236, .142), 3, .012)
    scale_rows(b, "spine2", "leather_boiled", 1.26, 1.47, (.228, .142), (.282, .142), 3, .012)
    b.loft("hips", "leather_dark", [(0, 0, 1.05, .178, .124), (0, 0, 1.0, .186, .13)], 8)
    _buckle(b)
    b.loft("spine2", "leather_dark", [(0, 0, 1.47, .15, .11), (0, 0, 1.55, .11, .09)], 8)
    for s_, x in (("L", 1), ("R", -1)):
        m.bulb(b, f"clavicle_{s_}", "leather_boiled", (x * .27, 0, 1.465), (.135, .125, .09), 8)
        for k in range(3):                                                                                          # brass studs
            m.bulb(b, f"clavicle_{s_}", "brass", (x * (.2 + k * .06), -.06, 1.5 - k * .01), (.014, .014, .014), 5)
    for z0, z1, k in ((.97, .90, 1.0), (.90, .82, 1.06)):                                                           # tassets
        b.loft("hips", "leather_boiled", [(0, 0, z0, .185 * k, .13 * k), (0, 0, z1, .19 * k, .134 * k)], 8)
    full_limbs(b, arm="leather_boiled", leg="leather_dark", trim="brass", boot="leather_boiled", glove="leather_dark", cap="leather_boiled")


def armor_ring_mail(b):
    """Ring Mail: a leather coat sewn with rings of iron (banded rows), a leather collar and ring-mail upper arms."""
    _torso(b, "leather_dark")
    _bands(b, "spine1", "iron", "iron_dark", 1.04, 1.27, (.176, .122), (.244, .148), 9)
    _bands(b, "spine2", "iron", "iron_dark", 1.26, 1.47, (.236, .148), (.29, .148), 8)
    _buckle(b)
    b.loft("spine2", "leather_tan", [(0, 0, 1.47, .15, .11), (0, 0, 1.55, .10, .085)], 8)
    for s_, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s_}", "leather_tan", [(x * .27, 0, 1.49, .09, .085), (x * .27, 0, 1.43, .13, .118), (x * .27, 0, 1.37, .12, .11)], 7)
    full_limbs(b, arm="iron_dark", leg="leather_dark", trim="leather_tan", boot="leather_dark", glove="leather_tan", cap="iron")


def armor_scale_hauberk(b):
    """Scale Hauberk (Diablo 2's Scale Mail): overlapping bronze scales on a knee-length hauberk over leather arms and legs."""
    scale_rows(b, "spine1", "bronze", 1.04, 1.27, (.172, .118), (.236, .142), 4, .016)
    scale_rows(b, "spine2", "bronze", 1.26, 1.47, (.228, .142), (.282, .142), 4, .016)
    scale_rows(b, "hips", "bronze", .74, 1.0, (.21, .15), (.185, .13), 5, .016)                                    # the long skirt
    b.loft("hips", "leather_dark", [(0, 0, 1.03, .18, .126), (0, 0, .99, .19, .13)], 8)
    _buckle(b)
    b.loft("spine2", "bronze", [(0, 0, 1.47, .15, .105), (0, 0, 1.54, .11, .09)], 8)
    for s_, x in (("L", 1), ("R", -1)):
        scale_rows(b, f"upper_arm_{s_}", "bronze", 1.18, 1.44, (.1, .095), (.1, .095), 3, .012, cx=x * .27)
    full_limbs(b, arm="leather_tan", leg="leather_dark", trim="bronze", boot="leather_dark", glove="leather_dark", cap="bronze")


def armor_chain_mail(b):
    """Chain Mail: a long mail shirt with elbow sleeves and a mail collar (a coif without the hood), leather trousers and boots."""
    _torso(b, "mail", 1.02, "leather_dark")
    _bands(b, "spine1", "mail", "iron_dark", 1.04, 1.27, (.18, .124), (.246, .15), 8)
    _bands(b, "spine2", "mail", "iron_dark", 1.26, 1.47, (.238, .15), (.292, .15), 8)
    b.loft("hips", "mail", [(0, 0, 1.0, .19, .134), (0, 0, .86, .205, .146), (0, 0, .72, .212, .15)], 8)            # the hem
    b.loft("neck", "mail", [(0, 0, 1.46, .16, .115), (0, 0, 1.58, .12, .1), (0, 0, 1.64, .105, .09)], 8)           # the collar
    _buckle(b)
    for s_, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s_}", "mail", [(x * .27, 0, 1.5, .09, .085), (x * .27, 0, 1.44, .135, .122), (x * .27, 0, 1.37, .122, .11)], 7)
    full_limbs(b, arm="mail", leg="leather_dark", trim="iron_dark", boot="leather_dark", glove="leather_dark", cap="iron")


def armor_splint_mail(b):
    """Splint Mail: a mail shirt armoured with vertical iron splints on the chest, arms and shins, plated shoulders."""
    _torso(b, "mail", 1.02, "iron_dark")
    _buckle(b)
    for x in (-.15, -.075, 0.0, .075, .15):                                                                         # chest splints
        m.rod(b, "spine1", "iron", (x, -.128 - abs(x) * .1, 1.05), (x * 1.15, -.136 - abs(x) * .1, 1.27), .02, 4)
        m.rod(b, "spine2", "iron", (x * 1.15, -.136 - abs(x) * .1, 1.27), (x * 1.3, -.14 - abs(x) * .1, 1.46), .022, 4)
    for s_, x in (("L", 1), ("R", -1)):
        m.bulb(b, f"clavicle_{s_}", "iron", (x * .27, 0, 1.47), (.15, .13, .09), 8)
        b.loft(f"clavicle_{s_}", "iron_dark", [(x * .27, 0, 1.42, .155, .135), (x * .27, 0, 1.39, .16, .14)], 8)
        for off in (-.04, 0.0, .04):
            m.rod(b, f"upper_arm_{s_}", "iron", (x * .27 + off, -.08, 1.42), (x * .27 + off, -.085, 1.18), .014, 4)
            m.rod(b, f"forearm_{s_}", "iron", (x * .27 + off, -.07, 1.1), (x * .27 + off, -.075, .9), .014, 4)
        for off in (-.05, .0, .05):
            m.rod(b, f"shin_{s_}", "iron", (x * .1 + off, -.095, .46), (x * .1 + off, -.1, .16), .014, 4)
    b.loft("hips", "mail", [(0, 0, 1.0, .19, .134), (0, 0, .84, .205, .148)], 8)
    full_limbs(b, arm="mail", leg="mail", trim="iron_dark", boot="iron_dark", glove="iron_dark", cap="iron_edge")


def armor_breast_plate(b):
    """Breast Plate: an iron cuirass with a raised ridge and brass trim over leather, vambraces, small pauldrons and a skirt of tassets."""
    _torso(b, "iron", 1.02, "leather_dark")
    b.loft("spine2", "iron_dark", [(0, 0, 1.47, .16, .115), (0, 0, 1.55, .115, .095)], 8)
    m.rod(b, "spine1", "iron_edge", (0, -.13, 1.05), (0, -.15, 1.28), .02, 4)
    m.rod(b, "spine2", "iron_edge", (0, -.15, 1.28), (0, -.16, 1.46), .022, 4)
    b.loft("spine2", "brass", [(0, 0, 1.455, .265, .145), (0, 0, 1.44, .272, .15)], 8)                              # neck trim
    b.loft("hips", "brass", [(0, 0, 1.03, .184, .13), (0, 0, 1.0, .19, .134)], 8)
    _buckle(b)
    for z0, z1, k in ((.98, .9, 1.0), (.9, .82, 1.07), (.82, .74, 1.13)):
        b.loft("hips", "leather_boiled", [(0, 0, z0, .19 * k, .134 * k), (0, 0, z1, .195 * k, .138 * k)], 8)
    for s_, x in (("L", 1), ("R", -1)):
        m.bulb(b, f"clavicle_{s_}", "iron", (x * .27, 0, 1.465), (.125, .115, .08), 8)
        b.loft(f"forearm_{s_}", "iron", [(x * .27, 0, 1.0, .08, .076), (x * .27, 0, .9, .076, .072)], 8)           # vambrace
    full_limbs(b, arm="leather_boiled", leg="leather_dark", trim="brass", boot="leather_dark", glove="leather_dark", cap="iron")


# ------------------------------------------------------------------ wizard robe and hat
def wizard_hat(b, colour):
    """Wizard hat: a wide brim, a tall cone whose tip folds over, a darker band with a brass buckle and star."""
    c, d, l = "wz_" + colour, "wz_" + colour + "_dark", "wz_" + colour + "_light"
    b.loft("head", d, ring_head([(0, .01, 1.80, .34, .34), (0, .01, 1.825, .30, .30)]), 10)             # brim underside
    b.loft("head", c, ring_head([(0, .01, 1.82, .34, .34), (0, .01, 1.845, .29, .29)]), 10)             # brim
    b.loft("head", c, ring_head([(0, .012, 1.84, .185, .185), (0, .02, 2.0, .15, .15), (0, .05, 2.16, .115, .115),
                                 (0, .10, 2.30, .075, .075)]), 8)
    b.loft("head", c, ring_head([(0, .10, 2.30, .075, .075), (0, .17, 2.40, .045, .045), (0, .27, 2.43, .02, .02)]), 8)  # fold
    b.loft("head", d, ring_head([(0, .012, 1.845, .19, .19), (0, .012, 1.905, .178, .178)]), 8)         # band
    m.panel(b, "head", "brass", [(-.045, -.19, 1.86), (.045, -.19, 1.86), (.045, -.192, 1.90), (-.045, -.192, 1.90)])
    star = [(0, -.2, 2.02), (.018, -.2, 1.985), (.055, -.2, 1.985), (.026, -.2, 1.96), (.04, -.2, 1.925),
            (0, -.2, 1.947), (-.04, -.2, 1.925), (-.026, -.2, 1.96), (-.055, -.2, 1.985), (-.018, -.2, 1.985)]
    m.panel(b, "head", "brass", [(x * .8, y, z * 1.0) for x, y, z in star])


def armor_wizard_robe(b, colour):
    """Wizard Robe: full-body robe. Rigid pieces only, so the skirt is split into a half per leg (follows the stride
    without clipping): high shawl collar, sash with a brass buckle and hanging ends, bell sleeves with light cuffs."""
    c, d, l = "wz_" + colour, "wz_" + colour + "_dark", "wz_" + colour + "_light"
    b.loft("spine1", c, [(0, 0, 1.04, .175, .125), (0, 0, 1.18, .195, .135), (0, 0, 1.28, .235, .14)], 8)
    b.loft("spine2", c, [(0, 0, 1.26, .23, .14), (0, 0, 1.37, .265, .155), (0, 0, 1.46, .28, .14), (0, 0, 1.50, .18, .105)], 8)
    b.loft("spine2", l, [(0, 0, 1.30, .236, .146), (0, 0, 1.285, .236, .146)], 8)
    b.loft("neck", d, [(0, 0, 1.46, .17, .125), (0, 0, 1.58, .125, .10), (0, 0, 1.64, .10, .085)], 8)   # high collar
    b.loft("neck", l, [(0, 0, 1.585, .13, .105), (0, 0, 1.62, .115, .095)], 8)
    b.loft("hips", d, [(0, 0, 1.06, .185, .13), (0, 0, .98, .195, .135)], 8)                              # sash
    m.panel(b, "hips", "brass", [(-.04, -.14, 1.07), (.04, -.14, 1.07), (.04, -.14, .975), (-.04, -.14, .975)])
    m.panel(b, "hips", d, [(.02, -.142, .975), (.085, -.142, .975), (.10, -.142, .62), (.045, -.142, .66)])   # sash ends
    m.panel(b, "hips", d, [(-.02, -.142, .975), (-.085, -.142, .975), (-.10, -.142, .56), (-.045, -.142, .60)])
    b.loft("hips", c, [(0, 0, .99, .19, .13), (0, 0, .86, .21, .15)], 8)                                   # waist / hip skirt top
    for s, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s}", c, [(x * .27, 0, 1.50, .09, .085), (x * .27, 0, 1.44, .13, .12), (x * .27, 0, 1.37, .115, .105)], 7)
        ax, lx = x * .27, x * .10
        b.loft(f"upper_arm_{s}", c, [(ax, 0, 1.44, .092, .088), (ax, 0, 1.30, .105, .10), (ax, 0, 1.15, .115, .11)], 8)
        b.loft(f"forearm_{s}", c, [(ax, 0, 1.16, .115, .11), (ax, 0, 1.02, .15, .14), (ax, 0, .90, .19, .17)], 8)       # bell sleeve
        b.loft(f"forearm_{s}", l, [(ax, 0, .905, .195, .175), (ax, 0, .865, .20, .18)], 8)                               # cuff
        b.loft(f"forearm_{s}", d, [(ax, 0, .865, .19, .17), (ax, 0, .845, .175, .155)], 8)                               # lining
        # robe halves per leg: wide thigh, flaring shin to the hem, hem trim, boots peek out below
        b.loft(f"thigh_{s}", c, [(lx, 0, .96, .15, .145), (lx, 0, .78, .17, .165), (lx, 0, .62, .18, .175), (lx, 0, .50, .185, .18)], 8)
        b.loft(f"shin_{s}", c, [(lx, 0, .50, .185, .18), (lx, 0, .36, .20, .195), (lx, 0, .22, .225, .22), (lx, 0, .14, .235, .23)], 8)
        b.loft(f"shin_{s}", l, [(lx, 0, .145, .237, .232), (lx, 0, .105, .242, .237)], 8)
        b.loft(f"foot_{s}", d, [(lx, .07, .055, .05, .05), (lx, -.03, .055, .06, .054), (lx, -.09, .046, .058, .046)], 7, axis="Y")
        b.loft(f"toe_{s}", d, [(lx, -.09, .046, .058, .046), (lx, -.15, .036, .047, .038), (lx, -.20, .03, .02, .022)], 7, axis="Y")


# --------------------------------------------------------------------- weapons
def _grip(b, z0, z1, r=.02):
    b.loft("w", "leather_dark", [(0, 0, z0, r, r), (0, 0, z1, r, r)], 6)


def sword_iron(b):
    """Iron Sword (item 0): the original Knight sword prop."""
    h.build_sword(b)


def sword_long(b):
    """Longsword (item 10): longer fuller blade, wheel pommel and a swept crossguard."""
    _grip(b, -.14, .10)
    b.loft("w", "brass", [(0, 0, -.19, .035, .035), (0, 0, -.14, .035, .035)], 8)               # pommel
    b.loft("w", "iron_dark", [(0, 0, .10, .15, .022), (0, 0, .14, .15, .022)], box=True)
    for sign in (-1, 1):
        b.loft("w", "iron_dark", [(sign * .14, 0, .12, .014, .014), (sign * .17, 0, .15, .01, .01)], 5)
    b.loft("w", "steel", [(0, 0, .14, .036, .009), (0, 0, .78, .038, .009), (0, 0, 1.04, .005, .003)], 4)
    b.loft("w", "iron_edge", [(0, 0, .16, .008, .011), (0, 0, .70, .008, .011)], 4)               # fuller


def sword_carver(b):
    """Rusty Carver (item 9): a broad, notched, single-edged cleaver."""
    _grip(b, -.13, .09)
    b.loft("w", "rust", [(0, 0, -.17, .03, .03), (0, 0, -.13, .03, .03)], 6)
    b.loft("w", "iron_dark", [(0, 0, .09, .07, .02), (0, 0, .12, .07, .02)], box=True)
    m.panel(b, "w", "rust", [(-.02, 0, .12), (.075, 0, .12), (.075, 0, .62), (.05, 0, .70), (-.02, 0, .62),
                             (-.028, 0, .5), (-.02, 0, .4), (-.028, 0, .3), (-.02, 0, .2)])
    for z in (.30, .42, .55):
        m.panel(b, "w", "iron_dark", [(.055, 0, z), (.085, 0, z + .02), (.075, 0, z + .04)])


def dagger_iron(b):
    """Iron Dagger (item 1): short, double-edged, ring pommel."""
    _grip(b, -.09, .06, .017)
    b.loft("w", "iron_dark", [(0, 0, -.12, .028, .028), (0, 0, -.09, .028, .028)], 6)
    b.loft("w", "iron_dark", [(0, 0, .06, .06, .016), (0, 0, .085, .06, .016)], box=True)
    b.loft("w", "steel", [(0, 0, .085, .028, .008), (0, 0, .30, .026, .008), (0, 0, .43, .003, .002)], 4)


def staff_oak(b):
    """Oakwood Staff (item 3): gnarled shaft with a knotted crown cradling a crystal."""
    b.loft("w", "wood", [(0, 0, -.55, .024, .024), (0, 0, .2, .022, .022), (0, 0, .95, .028, .028)], 7)
    b.loft("w", "leather_dark", [(0, 0, -.08, .028, .028), (0, 0, .08, .028, .028)], 7)            # grip wrap
    for sign, tilt in ((-1, -.07), (1, .07), (0, 0)):
        m.rod(b, "w", "wood_dark", (0, 0, .92), (tilt * 1.2, .03 * (1 if sign else -1), 1.18), .03, 5, end_radius=.016)
    m.bulb(b, "w", "crystal", (0, 0, 1.06), (.04, .04, .07), 6)


def rod_cleric(b):
    """Cleric's Rod (item 2): a short flanged mace-staff with a gold sun at the head."""
    b.loft("w", "wood", [(0, 0, -.3, .02, .02), (0, 0, .55, .02, .02)], 6)
    b.loft("w", "leather_dark", [(0, 0, -.1, .024, .024), (0, 0, .08, .024, .024)], 6)
    m.bulb(b, "w", "gold", (0, 0, .64), (.05, .05, .06), 8)
    for k in range(6):
        a = k * math.pi / 3
        m.rod(b, "w", "gold", (math.cos(a) * .05, 0, .64 + math.sin(a) * .05),
              (math.cos(a) * .10, 0, .64 + math.sin(a) * .10), .016, 4, end_radius=.004)


def hatchet(b):
    """Dual Hatchets (item 11): one hatchet (the prop is used in each hand)."""
    b.loft("w", "wood", [(0, 0, -.14, .02, .02), (0, 0, .42, .018, .018)], 6)
    b.loft("w", "leather_dark", [(0, 0, -.12, .024, .024), (0, 0, .03, .024, .024)], 6)
    m.panel(b, "w", "iron", [(.015, 0, .30), (.045, 0, .34), (.16, 0, .42), (.17, 0, .22), (.045, 0, .26)])
    m.panel(b, "w", "iron_edge", [(.16, 0, .42), (.175, 0, .40), (.175, 0, .24), (.17, 0, .22)])
    b.loft("w", "iron_dark", [(0, 0, .25, .03, .03), (0, 0, .35, .03, .03)], box=True)


# id: (name, slot, builder, battleheart item id or None)
CATALOG = {
    "helm_iron":         ("Nasal Helm", "head", helm_iron, None),
    "helm_great":        ("Great Helm", "head", helm_great, None),
    "cap_leather":       ("Leather Cap", "head", cap_leather, None),
    "hood_cloth":        ("Cloth Hood", "head", hood_cloth, None),
    "helm_spangenhelm":  ("Spangenhelm", "head", helm_spangenhelm, None),
    "helm_sugarloaf":    ("Sugarloaf Helm", "head", helm_sugarloaf, None),
    "helm_bascinet":     ("Bascinet", "head", helm_bascinet, None),
    "helm_hounskull":    ("Hounskull", "head", helm_hounskull, None),
    "helm_sallet":       ("Sallet", "head", helm_sallet, None),
    "helm_barbute":      ("Barbute", "head", helm_barbute, None),
    "helm_armet":        ("Armet", "head", helm_armet, None),
    "helm_frog_mouth":   ("Frog-Mouth Helm", "head", helm_frog_mouth, None),
    "helm_burgonet":     ("Burgonet", "head", helm_burgonet, None),
    "helm_morion":       ("Morion", "head", helm_morion, None),
    "helm_kettle_hat":   ("Kettle Hat", "head", helm_kettle_hat, None),
    "helm_cabasset":     ("Cabasset", "head", helm_cabasset, None),
    "helm_zischagge":    ("Zischaegge", "head", helm_zischagge, None),
    "helm_shishak":      ("Shishak", "head", helm_shishak, None),
    "armor_scale_mail":  ("Scale Mail", "armor", armor_scale_mail, 4),
    "armor_leather":     ("Soft Leather Garb", "armor", armor_leather_garb, 5),
    "armor_cloak":       ("Cotton Cloak", "armor", armor_cotton_cloak, 6),
    "armor_leather_armor": ("Leather Armor", "armor", armor_leather_armor, None),
    "armor_hard_leather":  ("Hard Leather Armor", "armor", armor_hard_leather, None),
    "armor_ring_mail":     ("Ring Mail", "armor", armor_ring_mail, None),
    "armor_scale_hauberk": ("Scale Hauberk", "armor", armor_scale_hauberk, None),
    "armor_chain_mail":    ("Chain Mail", "armor", armor_chain_mail, None),
    "armor_splint_mail":   ("Splint Mail", "armor", armor_splint_mail, None),
    "armor_breast_plate":  ("Breast Plate", "armor", armor_breast_plate, None),
    "sword_iron":        ("Iron Sword", "weapon", sword_iron, 0),
    "sword_long":        ("Longsword", "weapon", sword_long, 10),
    "sword_carver":      ("Rusty Carver", "weapon", sword_carver, 9),
    "dagger_iron":       ("Iron Dagger", "weapon", dagger_iron, 1),
    "staff_oak":         ("Oakwood Staff", "weapon", staff_oak, 3),
    "rod_cleric":        ("Cleric's Rod", "weapon", rod_cleric, 2),
    "hatchet":           ("Dual Hatchets (one)", "weapon", hatchet, 11),
}
for _colour in WIZARD_COLOURS:
    CATALOG["hat_wizard_" + _colour] = ("Wizard Hat (%s)" % _colour.title(), "head",
                                       (lambda b, c=_colour: wizard_hat(b, c)), None)
    CATALOG["armor_wizard_" + _colour] = ("Wizard Robe (%s)" % _colour.title(), "armor",
                                         (lambda b, c=_colour: armor_wizard_robe(b, c)), None)


# The 10-tier sets (armor_tiers.py): every tier 2-10 piece is an existing model rebuilt with a recoloured palette.
RECOLOURS = {}
for _w in ("heavy", "medium", "light"):
    for _t in range(2, 11):
        _name, _body, _head = tiers.SETS[_w][_t]
        for _part, _src, _slot, _id in (("armor", _body, "armor", tiers.piece_ids(_w, _t)[0]), ("head", _head, "head", tiers.piece_ids(_w, _t)[1])):
            if ":" in _src:
                _kind, _col = _src.split(":")
                _fn = (lambda b, c=_col: armor_wizard_robe(b, c)) if _kind == "robe" else (lambda b, c=_col: wizard_hat(b, c))
            else:
                _fn = CATALOG[_src][2]
            CATALOG[_id] = ("%s (%s)" % (_name, "helm" if _part == "head" else "body"), _slot, _fn, None)
            RECOLOURS[_id] = tiers.recolour(_w, _t, _part)

# The weapon tiers (weapon_tiers.py): new shapes (weapon_shapes.py) and the original props, recoloured per tier.
for _line, (_base, _label, _users, _p1, _p10, _rows) in wtiers.LINES.items():
    for _t, (_name, _shape) in _rows.items():
        if (_line, _t) in wtiers.STARTERS:
            continue
        _id = wtiers.piece_id(_line, _t)
        _fn = weapon_shapes.SHAPES[_shape] if _shape in weapon_shapes.SHAPES else CATALOG[_shape][2]
        CATALOG[_id] = (_name, "weapon", _fn, None)
        RECOLOURS[_id] = wtiers.recolour(_t)


def build_piece(piece_id, out_dir):
    name, slot, fn, bh = CATALOG[piece_id]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    saved = {k: h.COLOURS[k] for k in RECOLOURS.get(piece_id, {}) if k in h.COLOURS}
    for k, v in RECOLOURS.get(piece_id, {}).items():
        h.COLOURS[k] = v
    b = h.Builder()
    fn(b)
    if slot == "weapon":
        obj = h.make_object(piece_id, b)
        objs = [obj]
    else:
        arm = h.build_armature()
        obj = h.make_object(piece_id, b, arm)
        # every vertex must be weighted and bound to a real bone
        assert all(v.groups for v in obj.data.vertices), f"{piece_id}: unweighted vertices"
        assert all(g.name in arm.data.bones for g in obj.vertex_groups), f"{piece_id}: unknown bone"
        objs = [arm, obj]
    assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co), f"{piece_id}: bad geometry"
    path = os.path.join(out_dir, piece_id + ".glb")
    h.export(objs, path, False)
    h.COLOURS.update(saved)
    bbox = [Vector(c) for c in obj.bound_box]
    size = [round(max(v[i] for v in bbox) - min(v[i] for v in bbox), 3) for i in range(3)]
    print("PIECE", piece_id, slot, "triangles", h.count_tris(obj), "size", size)
    entry = {"id": piece_id, "name": name, "slot": slot, "file": piece_id + ".glb"}
    if bh is not None:
        entry["bh_item"] = bh
    if slot == "weapon":
        entry["attach"] = {"bone": "hand_R", "position": [0, .07, 0], "rotation_degrees": [-40, 90, 0]}
    return entry


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "../godot/models/gear")
    wanted = args[1:] or list(CATALOG)
    os.makedirs(out_dir, exist_ok=True)
    manifest = os.path.join(out_dir, "gear.json")
    entries = {}
    if os.path.exists(manifest):
        entries = {e["id"]: e for e in json.load(open(manifest))["pieces"]}
    for piece in wanted:
        entries[piece] = build_piece(piece, out_dir)
    ordered = [entries[k] for k in CATALOG if k in entries]
    json.dump({"pieces": ordered}, open(manifest, "w"), indent=2)
    print("GEAR_OK", len(wanted))


if __name__ == "__main__":
    main()
