"""weapon_shapes.py - the new weapon models (origin at the grip, long axis +Z, no armature). Colours are material KEYS that
weapon_tiers.py recolours per tier: iron / iron_dark / iron_edge / steel (metal), brass (trim), wood / wood_dark, leather_dark,
crystal (gem), bone, cotton (bow string). All shapes are CR art direction [tuned]; names are Diablo 2 base types."""
import math

import build_humanoid as h
import build_monsters as m


def _rod(b, mat, p0, p1, r, r1=None, sides=5):
    m.rod(b, "w", mat, p0, p1, r, sides, r1)


def _grip(b, z0, z1, r=.02):
    b.loft("w", "leather_dark", [(0, 0, z0, r, r), (0, 0, z1, r, r)], 6)


def _blade(b, mat, rings):
    b.loft("w", mat, rings, 4)


# ----------------------------------------------------------------------------------------------------- melee, one hand
def scimitar(b):
    """Scimitar: a curved single-edged blade with a knuckle-guard crossbar."""
    _grip(b, -.12, .09)
    b.loft("w", "brass", [(0, 0, -.16, .03, .03), (0, 0, -.12, .03, .03)], 6)
    b.loft("w", "iron_dark", [(0, 0, .09, .09, .02), (0, 0, .125, .09, .02)], box=True)
    _blade(b, "steel", [(0, 0, .13, .026, .008), (.012, 0, .30, .04, .009), (.045, 0, .50, .044, .009), (.095, 0, .66, .034, .008), (.15, 0, .77, .004, .003)])
    _blade(b, "iron_edge", [(.03, 0, .15, .006, .011), (.05, 0, .42, .006, .011), (.09, 0, .6, .006, .011)])      # the spine


def mace(b):
    """Mace: a wooden haft with a flanged iron head and a top spike."""
    b.loft("w", "wood", [(0, 0, -.15, .02, .02), (0, 0, .46, .02, .02)], 6)
    _grip(b, -.12, .05, .024)
    b.loft("w", "iron_dark", [(0, 0, .42, .032, .032), (0, 0, .47, .032, .032)], 6)
    m.bulb(b, "w", "iron", (0, 0, .55), (.048, .048, .07), 8)
    for k in range(6):
        a = k * math.pi / 3
        _rod(b, "iron_dark", (math.cos(a) * .035, math.sin(a) * .035, .55), (math.cos(a) * .095, math.sin(a) * .095, .55), .026, .008)
    _rod(b, "iron_edge", (0, 0, .61), (0, 0, .72), .02, .004)


# ----------------------------------------------------------------------------------------------------- melee, two hands
def greatsword(b):
    """Great sword: a long straight blade with a fuller, a wide crossguard and a long two-hand grip."""
    _grip(b, -.24, .16)
    b.loft("w", "brass", [(0, 0, -.30, .04, .04), (0, 0, -.24, .04, .04)], 8)
    b.loft("w", "iron_dark", [(0, 0, .16, .21, .026), (0, 0, .21, .21, .026)], box=True)
    for s in (-1, 1):
        _rod(b, "iron_dark", (s * .19, 0, .185), (s * .24, 0, .26), .02, .01)
    _blade(b, "steel", [(0, 0, .21, .05, .011), (0, 0, .95, .056, .011), (0, 0, 1.34, .006, .003)])
    _blade(b, "iron_edge", [(0, 0, .26, .009, .014), (0, 0, 1.0, .009, .014)])                                      # fuller


def great_axe(b):
    """Great axe: a long haft with a double-bitted head and a top spike."""
    b.loft("w", "wood", [(0, 0, -.34, .024, .024), (0, 0, .5, .022, .022), (0, 0, 1.0, .026, .026)], 6)
    _grip(b, -.2, .15, .03)
    for s in (-1, 1):
        m.panel(b, "w", "iron", [(s * .02, 0, .86), (s * .07, 0, .96), (s * .26, 0, 1.16), (s * .29, 0, .84), (s * .08, 0, .86 - .02)])
        m.panel(b, "w", "iron_edge", [(s * .26, 0, 1.16), (s * .285, 0, 1.12), (s * .30, 0, .86), (s * .29, 0, .84)])
    b.loft("w", "iron_dark", [(0, 0, .84, .04, .04), (0, 0, 1.02, .04, .04)], box=True)
    _rod(b, "iron_edge", (0, 0, 1.0), (0, 0, 1.28), .026, .004)


def maul(b):
    """Maul: a long haft capped by a heavy two-faced iron head with bands."""
    b.loft("w", "wood", [(0, 0, -.34, .024, .024), (0, 0, .5, .022, .022), (0, 0, .98, .026, .026)], 6)
    _grip(b, -.2, .15, .03)
    b.loft("w", "iron", [(0, 0, .9, .17, .08), (0, 0, 1.14, .17, .08)], box=True)
    for x in (-.17, .17):
        b.loft("w", "iron_dark", [(x, 0, .88, .035, .09), (x, 0, 1.16, .035, .09)], box=True)
    b.loft("w", "iron_edge", [(0, 0, 1.14, .1, .05), (0, 0, 1.18, .06, .03)], box=True)
    _rod(b, "iron_dark", (0, 0, 1.18), (0, 0, 1.3), .03, .006)


def halberd(b):
    """Halberd: a long shaft with a spear point, an axe blade and a rear hook."""
    b.loft("w", "wood", [(0, 0, -.5, .024, .024), (0, 0, .6, .022, .022), (0, 0, 1.25, .026, .026)], 6)
    _grip(b, -.2, .15, .03)
    b.loft("w", "iron_dark", [(0, 0, 1.12, .035, .035), (0, 0, 1.3, .035, .035)], 6)
    _rod(b, "steel", (0, 0, 1.28), (0, 0, 1.62), .035, .004, 4)
    m.panel(b, "w", "iron", [(.02, 0, 1.2), (.07, 0, 1.3), (.24, 0, 1.38), (.26, 0, 1.12), (.06, 0, 1.14)])
    m.panel(b, "w", "iron_edge", [(.24, 0, 1.38), (.265, 0, 1.36), (.275, 0, 1.12), (.26, 0, 1.12)])
    _rod(b, "iron_dark", (-.02, 0, 1.2), (-.17, 0, 1.3), .026, .006)


# ----------------------------------------------------------------------------------------------------- bows (two hands)
def _bow(b, half, belly, back, limb_mat, limb_w, tips):
    """Bow limbs curve toward +X (the belly) and the string runs straight at x = 0 between the tips."""
    zs = [-half + i * (2 * half) / 10 for i in range(11)]
    rings = []
    for z in zs:
        t = abs(z) / half
        cx = belly * (1 - t * t) - back * max(0.0, t - .62) ** 2 * 6
        rings.append((cx, 0, z, limb_w * (1 - .45 * t), .014 * (1 - .3 * t)))
    b.loft("w", limb_mat, rings, 6)
    _grip(b, -.08, .08, .026)
    tip_x = rings[0][0]
    for s in (-1, 1):
        m.bulb(b, "w", "brass" if tips == "brass" else "iron_dark", (rings[-1 if s > 0 else 0][0], 0, s * half), (.016, .016, .02), 5)
    b.loft("w", "cotton", [(tip_x, 0, -half, .0035, .0035), (tip_x, 0, half, .0035, .0035)], 4)


def bow_short(b):
    """Short bow: a small wooden bow."""
    _bow(b, .45, .12, 0.0, "wood", .02, "iron")


def bow_long(b):
    """Long bow: tall, a deep draw."""
    _bow(b, .72, .13, 0.0, "wood", .02, "iron")
    b.loft("w", "wood_dark", [(.14, 0, -.12, .024, .018), (.14, 0, .12, .024, .018)], 6)


def bow_composite(b):
    """Composite bow: recurved tips and bone-and-sinew inlay on the limbs."""
    _bow(b, .56, .13, .06, "wood", .024, "brass")
    for z in (-.3, -.18, .18, .3):
        b.loft("w", "bone", [(.08, 0, z - .03, .028, .018), (.08, 0, z + .03, .028, .018)], 6)


def bow_war(b):
    """War bow: broad metal-shod limbs with spiked tips and a plated grip."""
    _bow(b, .64, .14, .08, "iron_dark", .03, "brass")
    b.loft("w", "iron", [(.145, 0, -.1, .036, .03), (.145, 0, .1, .036, .03)], 6)
    for s in (-1, 1):
        _rod(b, "iron_edge", (-.03, 0, s * .62), (-.1, 0, s * .76), .022, .004)
    for z in (-.35, .35):
        b.loft("w", "iron_edge", [(.08, 0, z - .02, .034, .02), (.08, 0, z + .02, .034, .02)], 6)


# ----------------------------------------------------------------------------------------------------- crossbows (one hand)
def _xbow(b, stock_len, span, thick, trim):
    """Stock along +Z with the prod across X at the front; a bolt groove, a trigger and a string."""
    b.loft("w", "wood", [(0, 0, -.1, .022, .03), (0, 0, .06, .026, .034), (0, 0, stock_len, .02 * thick, .026 * thick)], 6)
    _grip(b, -.08, .04, .03)
    z = stock_len - .04
    for s in (-1, 1):
        _rod(b, "iron_dark", (0, 0, z), (s * span * .6, 0, z - .01), .022 * thick, .016 * thick, 5)
        _rod(b, "iron", (s * span * .6, 0, z - .01), (s * span, 0, z + .06), .016 * thick, .008, 5)
        _rod(b, "cotton", (s * span, 0, z + .06), (0, 0, z - .08), .004, .004, 3)
    b.loft("w", "iron_dark", [(0, .03, .08, .008, .004), (0, .03, stock_len + .02, .008, .004)], 4)               # groove
    _rod(b, "iron_edge", (0, .03, .1), (0, .03, stock_len + .06), .008, .004, 4)                                    # bolt
    b.loft("w", trim, [(0, 0, stock_len - .06, .03 * thick, .034 * thick), (0, 0, stock_len - .02, .03 * thick, .034 * thick)], 6)
    _rod(b, "iron_dark", (0, 0, stock_len), (0, -.04, stock_len + .09), .014, .008)                                  # stirrup post


def xbow_light(b):
    """Light crossbow: a slim stock and a narrow prod."""
    _xbow(b, .42, .24, 1.0, "brass")


def xbow_heavy(b):
    """Heavy crossbow: a thick stock, a wide steel prod and a stirrup."""
    _xbow(b, .5, .34, 1.35, "iron_edge")
    _rod(b, "iron", (0, 0, .46), (0, -.07, .55), .012, .012)
    _rod(b, "iron", (-.05, -.07, .55), (.05, -.07, .55), .012, .012)                                                 # the stirrup


def xbow_repeating(b):
    """Repeating crossbow: a box magazine over the stock and a pull lever."""
    _xbow(b, .46, .28, 1.15, "iron_edge")
    b.loft("w", "wood_dark", [(0, .055, .1, .03, .04), (0, .055, .4, .03, .04)], box=True)
    b.loft("w", "iron_dark", [(0, .1, .12, .034, .008), (0, .1, .38, .034, .008)], box=True)
    _rod(b, "iron", (0, -.02, .0), (0, -.14, -.18), .014, .01)                                                       # lever


# ----------------------------------------------------------------------------------------------------- staves (two hands)
def _shaft(b, bottom, top, r=.024):
    b.loft("w", "wood", [(0, 0, bottom, r, r), (0, 0, (bottom + top) / 2, r * .9, r * .9), (0, 0, top, r * 1.1, r * 1.1)], 7)
    b.loft("w", "leather_dark", [(0, 0, -.12, r * 1.2, r * 1.2), (0, 0, .06, r * 1.2, r * 1.2)], 7)


def staff_gnarled(b):
    """Gnarled staff: a knotted shaft that twists around a crystal at the top."""
    _shaft(b, -.6, .9)
    for z, s in ((.25, 1), (.55, -1), (.75, 1)):
        m.bulb(b, "w", "wood_dark", (s * .014, 0, z), (.03, .03, .035), 6)
    for ang in (0, 2.1, 4.2):
        _rod(b, "wood_dark", (0, 0, .85), (math.cos(ang) * .09, math.sin(ang) * .09, 1.08), .03, .012)
        _rod(b, "wood_dark", (math.cos(ang) * .09, math.sin(ang) * .09, 1.08), (math.cos(ang + .8) * .04, math.sin(ang + .8) * .04, 1.22), .012, .006)
    m.bulb(b, "w", "crystal", (0, 0, 1.08), (.045, .045, .08), 6)


def staff_battle(b):
    """Battle staff: an iron-shod shaft with collar bands and a spiked crown holding the gem."""
    _shaft(b, -.62, .96, .026)
    for z in (-.55, .3, .85):
        b.loft("w", "iron_dark", [(0, 0, z, .036, .036), (0, 0, z + .05, .036, .036)], 7)
    _rod(b, "iron_edge", (0, 0, -.62), (0, 0, -.74), .026, .004)
    for k in range(4):
        a = k * math.pi / 2
        _rod(b, "iron", (math.cos(a) * .035, math.sin(a) * .035, .94), (math.cos(a) * .095, math.sin(a) * .095, 1.22), .026, .006)
    m.bulb(b, "w", "crystal", (0, 0, 1.06), (.05, .05, .09), 6)


def staff_war(b):
    """War staff: a long shaft ending in a crown of curved wings around a large floating gem."""
    _shaft(b, -.66, 1.0, .028)
    for z in (-.58, .0, .4, .9):
        b.loft("w", "iron_dark", [(0, 0, z, .038, .038), (0, 0, z + .045, .038, .038)], 7)
    _rod(b, "iron_edge", (0, 0, -.66), (0, 0, -.8), .028, .004)
    for s in (-1, 1):
        _rod(b, "iron", (0, 0, .98), (s * .13, 0, 1.14), .026, .018)
        _rod(b, "iron_edge", (s * .13, 0, 1.14), (s * .08, 0, 1.4), .018, .004)
    for k in range(6):
        a = k * math.pi / 3
        m.bulb(b, "w", "brass", (math.cos(a) * .07, 0, 1.18 + math.sin(a) * .07), (.012, .012, .012), 4)           # a ring of studs
    m.bulb(b, "w", "crystal", (0, 0, 1.18), (.06, .06, .1), 6)


# ----------------------------------------------------------------------------------------------------- wands (one hand)
def wand_straight(b):
    """Wand: a slim shaft with a metal cap and a small gem."""
    b.loft("w", "wood", [(0, 0, -.12, .02, .02), (0, 0, .3, .014, .014), (0, 0, .42, .017, .017)], 6)
    _grip(b, -.1, .06, .024)
    b.loft("w", "iron_dark", [(0, 0, .4, .022, .022), (0, 0, .45, .022, .022)], 6)
    m.bulb(b, "w", "crystal", (0, 0, .5), (.022, .022, .04), 6)


def wand_knob(b):
    """Knobbed wand: a heavier head with three prongs around a gem."""
    b.loft("w", "wood_dark", [(0, 0, -.12, .02, .02), (0, 0, .3, .016, .016), (0, 0, .4, .026, .026)], 6)
    _grip(b, -.1, .06, .024)
    for k in range(3):
        a = k * 2.094
        _rod(b, "iron", (math.cos(a) * .02, math.sin(a) * .02, .4), (math.cos(a) * .045, math.sin(a) * .045, .56), .016, .004)
    m.bulb(b, "w", "crystal", (0, 0, .48), (.03, .03, .05), 6)


def wand_skull(b):
    """Skull wand: a bone shaft topped by a small skull with gem eyes."""
    b.loft("w", "bone", [(0, 0, -.12, .02, .02), (0, 0, .3, .014, .014), (0, 0, .4, .016, .016)], 6)
    _grip(b, -.1, .06, .024)
    m.bulb(b, "w", "bone", (0, 0, .5), (.04, .04, .05), 6)
    m.bulb(b, "w", "bone", (0, -.02, .43), (.026, .022, .02), 5)                                                     # jaw
    for s in (-1, 1):
        m.bulb(b, "w", "crystal", (s * .018, -.034, .515), (.011, .008, .011), 4)
    _rod(b, "iron_dark", (0, 0, .35), (0, 0, .39), .022, .022)


SHAPES = {f.__name__: f for f in (scimitar, mace, greatsword, great_axe, maul, halberd, bow_short, bow_long, bow_composite, bow_war,
                                  xbow_light, xbow_heavy, xbow_repeating, staff_gnarled, staff_battle, staff_war,
                                  wand_straight, wand_knob, wand_skull)}
