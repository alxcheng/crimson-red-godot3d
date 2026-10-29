"""build_zones.py - the five zone battle stages of the 2D game's map (map_gen.ZONES): Black Forest, Cold Wastes ("frozen wastes"),
Wetcaves, Waxen Desert and Castle Crimson, in the same arena as the dungeon stage (30 x 32 m, party at -X, gateway at +X,
far walls at -X and the back, low near sides) so every system works unchanged on all of them.

Run (headless):
    blender --background --python blender/build_zones.py -- godot/models/stage [zone ...]

Writes godot/models/stage/<zone>/stage.glb + stage.json (the same layout the viewer / sandbox already read, plus an
"environment" block: ambient and fill colours and the zone name). Seeded: the same run always makes the same stage.
Colours follow the 2D zone backgrounds (captures/ui_smoke/battle-bg-<zone>.png); every shape is a CR-original faceted loft [tuned].
"""
import json
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_humanoid as h
import build_monsters as m
import build_stage as st

HX, HY = st.HX, st.HY
WALL_H = st.WALL_H

PALETTE = {
    # black forest
    "grass_a": (46, 70, 44), "grass_b": (38, 58, 40), "grass_c": (58, 82, 48), "dirt": (70, 56, 40), "leaf_dark": (26, 50, 38),
    "leaf_mid": (40, 76, 48), "trunk": (66, 46, 34), "trunk_dark": (44, 32, 28), "web": (210, 210, 218), "fungus": (150, 90, 168),
    # cold wastes
    "ice_a": (150, 204, 238), "ice_b": (112, 166, 218), "ice_c": (206, 234, 250), "ice_dark": (66, 116, 176),
    "snow": (234, 243, 250), "snow_shadow": (186, 206, 226), "frost_glow": (150, 214, 255),
    # wetcaves
    "cave_a": (72, 86, 74), "cave_b": (56, 70, 60), "cave_c": (88, 102, 86), "cave_d": (40, 52, 46), "cave_moss": (58, 112, 62),
    "water": (58, 120, 132), "glow": (110, 236, 190),
    # waxen desert
    "sand_a": (206, 192, 154), "sand_b": (188, 172, 134), "sand_c": (224, 210, 172), "sand_dark": (146, 130, 100),
    "sandstone": (176, 150, 112), "sandstone_dark": (128, 108, 82), "cactus": (88, 128, 84), "candle": (238, 228, 192),
    "obelisk": (124, 114, 104),
    # castle crimson
    "brick_a": (112, 40, 46), "brick_b": (96, 32, 40), "brick_c": (130, 50, 52), "brick_dark": (62, 22, 30), "carpet": (146, 26, 30),
    "carpet_dark": (98, 18, 24), "gold": (200, 162, 66), "banner": (176, 32, 38), "marble": (150, 138, 136),
}
for key, colour in PALETTE.items():
    h.COLOURS[key] = colour
    if key not in h.MATS:
        h.MATS.append(key)

ZONES = {
    "black_forest": dict(name="BLACK FOREST", ambient=(0.46, 0.6, 0.52), ambient_e=1.0, fill=(0.6, 0.85, 0.7), fill_e=0.5,
                         floor=("grass_a", "grass_b", "grass_c", "grass_b"), accent="dirt", base="grass_b",
                         light=(0.55, 0.95, 0.65), emissive=["glow"]),
    "cold_wastes": dict(name="COLD WASTES", ambient=(0.58, 0.66, 0.84), ambient_e=0.85, fill=(0.8, 0.9, 1.0), fill_e=0.5,
                        floor=("ice_a", "ice_b", "ice_c", "ice_b"), accent="snow", base="ice_dark",
                        light=(0.55, 0.8, 1.0), emissive=["frost_glow"]),
    "wetcaves": dict(name="WETCAVES", ambient=(0.42, 0.58, 0.52), ambient_e=0.95, fill=(0.55, 0.85, 0.75), fill_e=0.45,
                     floor=("cave_a", "cave_b", "cave_c", "cave_d"), accent="cave_moss", base="cave_d",
                     light=(0.4, 0.95, 0.75), emissive=["glow"]),
    "waxen_desert": dict(name="WAXEN DESERT", ambient=(0.66, 0.6, 0.5), ambient_e=0.75, fill=(1.0, 0.92, 0.76), fill_e=0.5,
                         floor=("sand_a", "sand_b", "sand_c", "sand_b"), accent="sand_dark", base="sand_dark",
                         light=(1.0, 0.72, 0.38), emissive=["flame", "flame_core"]),
    "castle_crimson": dict(name="CASTLE CRIMSON", ambient=(0.62, 0.42, 0.44), ambient_e=0.95, fill=(1.0, 0.7, 0.62), fill_e=0.45,
                           floor=("brick_a", "brick_b", "brick_c", "brick_a"), accent="carpet", base="brick_dark",
                           light=(1.0, 0.5, 0.3), emissive=["flame", "flame_core"]),
}


# ----------------------------------------------------------------------------------------------- floors
def tile_floor(b, rng, zone, size, top, sides=6, accent_chance=0.06, rows=(0.5, 0.8)):
    """Generic stone / slab / patch floor: staggered rows of low irregular tiles over a base slab."""
    cfg = ZONES[zone]
    width, depth = st.ARENA_W + 2.4, st.ARENA_D + 2.4
    b.loft("floor", cfg["base"], [(0, 0, -.12, width / 2, depth / 2), (0, 0, -.005, width / 2, depth / 2)], box=True)
    count = 0
    y = -depth / 2
    while y < depth / 2 - .2:
        row = rng.uniform(*rows)
        x = -width / 2 + rng.uniform(0, .45)
        while x < width / 2 - .2:
            w = rng.uniform(*size)
            cx, cy = x + w / 2, y + row / 2
            rx, ry = max(.12, w / 2 - .03), max(.12, row / 2 - .03)
            t = rng.uniform(*top)
            colour = rng.choice(cfg["floor"]) if rng.random() > accent_chance else cfg["accent"]
            rot = rng.uniform(0, math.pi / 3)
            b.loft("floor", colour, [(cx, cy, -.01, rx, ry), (cx, cy, t * .6, rx * .97, ry * .97),
                                     (cx, cy, t, rx * rng.uniform(.78, .9), ry * rng.uniform(.78, .9))], sides=sides, rot=rot)
            count += 1
            x += w
        y += row
    return count


def castle_floor(b, rng):
    """Square flagstones in two reds and a carpet runner down the middle of the hall with gold borders."""
    cfg = ZONES["castle_crimson"]
    width, depth = st.ARENA_W + 2.4, st.ARENA_D + 2.4
    b.loft("floor", "brick_dark", [(0, 0, -.12, width / 2, depth / 2), (0, 0, -.005, width / 2, depth / 2)], box=True)
    n = 0
    y = -depth / 2 + .5
    while y < depth / 2:
        x = -width / 2 + .5
        while x < width / 2:
            colour = cfg["floor"][(int((x + 40) // 1) + int((y + 40) // 1)) % 4]
            b.loft("floor", colour, [(x, y, -.01, .47, .47), (x, y, .05 + rng.uniform(0, .02), .45, .45)], box=True)
            n += 1
            x += 1.0
        y += 1.0
    # the runner (along X, a few metres wide) and its borders
    for yy, hw, mat, top in ((0.0, 2.3, "carpet", .075), (0.0, 2.45, "gold", .06)):
        b.loft("floor", mat, [(0, yy, .02, width / 2 - .6, hw), (0, yy, top, width / 2 - .6, hw)], box=True)
    b.loft("floor", "carpet", [(0, 0, .02, width / 2 - .6, 2.2), (0, 0, .09, width / 2 - .6, 2.2)], box=True)
    for yy in (-2.38, 2.38):
        b.loft("floor", "gold", [(0, yy, .07, width / 2 - .6, .07), (0, yy, .1, width / 2 - .6, .07)], box=True)
    return n


def puddles(b, rng, count, mat="water", rmin=.8, rmax=2.0):
    for _ in range(count):
        x, y = rng.uniform(-HX + 2, HX - 2), rng.uniform(-HY + 2, HY - 2)
        rx, ry = rng.uniform(rmin, rmax), rng.uniform(rmin, rmax) * .7
        b.loft("floor", mat, [(x, y, .055, rx, ry), (x, y, .075, rx * .94, ry * .94)], sides=9, rot=rng.uniform(0, 1))


def cracks(b, rng, mat, count):
    for _ in range(count):
        x, y = rng.uniform(-HX + 2, HX - 2), rng.uniform(-HY + 2, HY - 2)
        a = rng.uniform(0, math.pi)
        ln = rng.uniform(1.2, 3.4)
        m.rod(b, "floor", mat, (x, y, .05), (x + math.cos(a) * ln, y + math.sin(a) * ln, .055), .03, 4)


# ----------------------------------------------------------------------------------------------- shared skyline helpers
def border_positions(rng, spacing):
    """(x, y, side) points along the far walls (the -X end and the back, y = +HY) and the low near sides."""
    far, near = [], []
    y = -HY - 1.0
    while y < HY + 1.0:
        far.append((-HX - .6 + rng.uniform(-.3, .3), y))
        y += spacing * rng.uniform(.8, 1.2)
    x = -HX
    while x < HX + 1.0:
        far.append((x, HY + .6 + rng.uniform(-.3, .3)))
        x += spacing * rng.uniform(.8, 1.2)
    x = -HX
    while x < HX + 1.0:
        near.append((x, -HY - .5 + rng.uniform(-.2, .2)))
        x += spacing * .7 * rng.uniform(.8, 1.2)
    gate = 2.6
    y = -HY - 1.0
    while y < HY + 1.0:
        if abs(y) > gate:
            near.append((HX + .5 + rng.uniform(-.2, .2), y))
        y += spacing * .7 * rng.uniform(.8, 1.2)
    return far, near


def tree(b, rng, x, y, big=1.0):
    trunk_r = rng.uniform(.22, .38) * big
    ht = rng.uniform(3.8, 5.6) * big
    b.loft("walls", "trunk" if rng.random() > .3 else "trunk_dark",
           [(x, y, 0, trunk_r * 1.3, trunk_r * 1.3), (x, y, ht * .4, trunk_r, trunk_r), (x, y, ht, trunk_r * .7, trunk_r * .7)], 6, rot=rng.uniform(0, 1))
    for k in range(3):
        cr = rng.uniform(1.0, 1.7) * big * (1.0 - k * .18)
        z = ht * (.55 + k * .22)
        b.loft("walls", "leaf_dark" if (k + int(x)) % 2 else "leaf_mid",
               [(x + rng.uniform(-.2, .2), y + rng.uniform(-.2, .2), z - cr * .5, cr * .5, cr * .5),
                (x, y, z, cr, cr), (x, y, z + cr * .7, cr * .45, cr * .45)], 7, rot=rng.uniform(0, 1))


def crystal(b, rng, x, y, big=1.0):
    r = rng.uniform(.4, .95) * big
    ht = rng.uniform(1.8, 4.6) * big
    mat = rng.choice(("ice_a", "ice_b", "ice_c"))
    lean_x, lean_y = rng.uniform(-.35, .35) * ht * .2, rng.uniform(-.35, .35) * ht * .2
    b.loft("walls", mat, [(x, y, 0, r, r), (x + lean_x * .5, y + lean_y * .5, ht * .55, r * .8, r * .8), (x + lean_x, y + lean_y, ht, r * .04, r * .04)],
           6, rot=rng.uniform(0, 1))


def snow_mound(b, rng, x, y, r):
    b.loft("walls", rng.choice(("snow", "snow_shadow")), [(x, y, 0, r, r * .8), (x, y, r * .35, r * .75, r * .62), (x, y, r * .55, r * .3, r * .24)], 7,
           rot=rng.uniform(0, 1))


def rock_spire(b, rng, x, y, mats=("cave_a", "cave_b", "cave_c"), big=1.0, hanging=False):
    r = rng.uniform(.35, .9) * big
    ht = rng.uniform(1.5, 4.2) * big
    mat = rng.choice(mats)
    if hanging:
        b.loft("walls", mat, [(x, y, WALL_H + .4, r, r), (x, y, WALL_H + .4 - ht * .55, r * .55, r * .55), (x, y, WALL_H + .4 - ht, r * .04, r * .04)], 6)
    else:
        b.loft("walls", mat, [(x, y, 0, r, r), (x, y, ht * .5, r * .6, r * .6), (x, y, ht, r * .05, r * .05)], 6, rot=rng.uniform(0, 1))


def mushroom(b, rng, x, y, glow=True, big=1.0, mat_cap="glow", prop="props"):
    s = rng.uniform(.25, .55) * big
    b.loft(prop, "cave_c", [(x, y, 0, s * .22, s * .22), (x, y, s * 1.1, s * .17, s * .17)], 6)
    m.bulb(b, prop, mat_cap, (x, y, s * 1.2), (s * .75, s * .75, s * .38), 7)


def dune(b, rng, x, y, w, ht):
    b.loft("walls", rng.choice(("sand_a", "sand_b", "sand_c")), [(x, y, 0, w, w * .7), (x, y, ht * .6, w * .72, w * .5), (x, y, ht, w * .28, w * .2)], 8, rot=rng.uniform(0, 1))


def sandstone_block(b, rng, x, y, big=1.0):
    w, d, ht = rng.uniform(.8, 1.7) * big, rng.uniform(.7, 1.4) * big, rng.uniform(1.4, 4.2) * big
    b.loft("walls", rng.choice(("sandstone", "sandstone_dark", "sand_dark")), [(x, y, 0, w, d), (x, y, ht * .9, w * .86, d * .86), (x, y, ht, w * .8, d * .8)],
           box=True)


def cactus(b, rng, x, y, big=1.0):
    ht = rng.uniform(1.6, 3.0) * big
    r = rng.uniform(.18, .28) * big
    b.loft("props", "cactus", [(x, y, 0, r, r), (x, y, ht * .8, r * .9, r * .9), (x, y, ht, r * .5, r * .5)], 6)
    for side in (-1, 1):
        if rng.random() > .35:
            z = ht * rng.uniform(.4, .65)
            m.rod(b, "props", "cactus", (x, y, z), (x + side * .5 * big, y, z), r * .5, 5)
            m.rod(b, "props", "cactus", (x + side * .5 * big, y, z), (x + side * .5 * big, y, z + rng.uniform(.5, 1.0)), r * .5, 5)


def candle(b, rng, x, y, big=1.0, lit=True):
    r = rng.uniform(.25, .42) * big
    ht = rng.uniform(1.0, 2.4) * big
    b.loft("props", "candle", [(x, y, 0, r * 1.1, r * 1.1), (x, y, ht * .5, r, r), (x, y, ht, r * .95, r * .95)], 8)
    b.loft("props", "candle", [(x, y, ht, r * 1.1, r * 1.0), (x, y, ht + .08, r * .5, r * .5)], 8)             # a wax drip lip
    if lit:
        b.loft("props", "flame", [(x, y, ht + .06, .13, .13), (x, y, ht + .32, .09, .09), (x, y, ht + .5, .01, .01)], 5)
        b.loft("props", "flame_core", [(x, y, ht + .08, .06, .06), (x, y, ht + .28, .04, .04), (x, y, ht + .38, .01, .01)], 5)


def obelisk(b, rng, x, y, big=1.0):
    ht = rng.uniform(3.0, 5.0) * big
    w = rng.uniform(.4, .6) * big
    b.loft("props", "obelisk", [(x, y, 0, w * 1.4, w * 1.4), (x, y, ht * .9, w * .8, w * .8), (x, y, ht, w * .02, w * .02)], box=True)
    b.loft("props", "sandstone_dark", [(x, y, 0, w * 1.7, w * 1.7), (x, y, .3, w * 1.6, w * 1.6)], box=True)


def banner(b, x, y, along_x, big=1.0):
    """A red banner hanging on a far wall with a gold stripe (face toward the room)."""
    w, ht = .75 * big, 2.2 * big
    if along_x:        # the +Y wall, facing -Y
        b.loft("props", "banner", [(x, y - .08, 1.2, w, .03), (x, y - .08, 1.2 + ht, w, .03)], box=True)
        b.loft("props", "gold", [(x, y - .12, 1.2 + ht * .55, w * .75, .02), (x, y - .12, 1.2 + ht * .62, w * .75, .02)], box=True)
    else:              # the -X wall, facing +X
        b.loft("props", "banner", [(x + .08, y, 1.2, .03, w), (x + .08, y, 1.2 + ht, .03, w)], box=True)
        b.loft("props", "gold", [(x + .12, y, 1.2 + ht * .55, .02, w * .75), (x + .12, y, 1.2 + ht * .62, .02, w * .75)], box=True)


def light(layout, x, y, z, color, energy, rng_range, flicker=.15):
    layout["lights"].append({"x": round(x, 3), "y": y, "z": round(-z, 3), "color": [round(c, 3) for c in color], "energy": energy,
                             "range": rng_range, "flicker": flicker})


# ----------------------------------------------------------------------------------------------- the zones
def build_zone(zone):
    rng = random.Random(st.SEED + sum(ord(c) for c in zone))
    cfg = ZONES[zone]
    layout = {"obstacles": [], "lights": []}
    objects = {name: h.Builder() for name in ("stage_floor", "stage_walls", "stage_props")}
    f, w, p = objects["stage_floor"], objects["stage_walls"], objects["stage_props"]
    far, near = border_positions(rng, 1.6)
    emissive = list(cfg["emissive"])

    if zone == "black_forest":
        stones = tile_floor(f, rng, zone, (1.0, 2.2), (.02, .06), sides=7, accent_chance=.12, rows=(.7, 1.3))
        puddles(f, rng, 5, "grass_c", 1.2, 2.6)
        for x, y in far:
            tree(w, rng, x, y, big=1.15)
            tree(w, rng, x + rng.uniform(-.8, .8) + (1.2 if y > 0 else 0), y + rng.uniform(.6, 1.6) * (1 if y > 0 else 1), big=1.3)
        for x, y in near:
            m.bulb(w, "walls", "leaf_dark", (x, y, .35), (rng.uniform(.5, .9), rng.uniform(.4, .7), rng.uniform(.4, .6)), 7)
        for _ in range(26):                      # stumps, fungus, webs on the floor
            x, y = rng.uniform(-HX + 1.5, HX - 1.5), rng.uniform(-HY + 1.5, HY - 1.5)
            if rng.random() < .5:
                mushroom(p, rng, x, y, mat_cap="fungus", big=.8)
            else:
                st.rubble(p, rng, x, y, 4, .5)
        for tx, ty in ((-HX + 1.2, -4.0), (-HX + 1.2, 4.0), (-5.0, HY - 1.2), (6.0, HY - 1.2)):     # lanterns of will-o'-wisps
            m.bulb(p, "props", "glow", (tx, ty, 2.0), (.18, .18, .2), 6)
            light(layout, tx, 2.0, ty, cfg["light"], 2.0, 9.0, .35)
        st.gateway(p, rng, HX + .4) if False else None
        for sy in (-2.6, 2.6):
            tree(p, rng, HX + .4, sy * 1.0 + (-.6 if sy < 0 else .6), big=1.0)

    elif zone == "cold_wastes":
        stones = tile_floor(f, rng, zone, (1.4, 3.0), (.015, .05), sides=7, accent_chance=.1, rows=(.9, 1.6))
        cracks(f, rng, "ice_dark", 22)
        puddles(f, rng, 4, "ice_c", 1.4, 3.0)
        for x, y in far:
            crystal(w, rng, x, y, big=1.4)
            if rng.random() > .4:
                snow_mound(w, rng, x + rng.uniform(-.5, .5), y + rng.uniform(-.4, .4), rng.uniform(.8, 1.4))
        for x, y in near:
            snow_mound(w, rng, x, y, rng.uniform(.5, 1.0))
        for _ in range(16):
            x, y = rng.uniform(-HX + 1.5, HX - 1.5), rng.uniform(-HY + 1.5, HY - 1.5)
            snow_mound(p, rng, x, y, rng.uniform(.25, .55))
        for sx, sy in ((-HX + 1.4, -5.0), (-HX + 1.4, 5.0), (-4.0, HY - 1.4), (8.0, HY - 1.4)):       # frost lanterns: glowing crystals
            m.bulb(p, "props", "frost_glow", (sx, sy, .9), (.22, .22, .7), 6)
            light(layout, sx, 1.4, sy, cfg["light"], 2.2, 10.0, .12)
        for sy in (-3.0, 3.0):
            crystal(p, rng, HX + .5, sy * 1.2, big=1.0)

    elif zone == "wetcaves":
        stones = tile_floor(f, rng, zone, (.8, 1.9), (.03, .09), sides=6, accent_chance=.14, rows=(.55, 1.0))
        puddles(f, rng, 9, "water", 1.0, 2.6)
        st.wall_course_blocks(w, rng, -HY - 1.2, HY + 1.2, -HX - .45, WALL_H, False, .9, 0, ("cave_a", "cave_b", "cave_c", "cave_d"))
        st.wall_course_blocks(w, rng, -HX - 1.2, HX + 1.2, HY + .45, WALL_H, True, .9, 1, ("cave_a", "cave_b", "cave_c", "cave_d"))
        st.wall_course_blocks(w, rng, -HX - 1.2, HX + 1.2, -HY - .4, .9, True, .8, 2, ("cave_a", "cave_b", "cave_d"))
        st.wall_course_blocks(w, rng, -HY - 1.2, -2.6, HX + .4, 1.1, False, .8, 3, ("cave_a", "cave_b", "cave_d"))
        st.wall_course_blocks(w, rng, 2.6, HY + 1.2, HX + .4, 1.1, False, .8, 4, ("cave_a", "cave_b", "cave_d"))
        for x, y in far:
            rock_spire(w, rng, x, y, hanging=True)                       # stalactites
            rock_spire(w, rng, x + rng.uniform(-.8, .8), y + rng.uniform(-.8, .8) * (1 if y > 0 else 1))
        for _ in range(24):
            x, y = rng.uniform(-HX + 1.5, HX - 1.5), rng.uniform(-HY + 1.5, HY - 1.5)
            r = rng.random()
            if r < .45:
                mushroom(p, rng, x, y, big=1.0)
            elif r < .75:
                st.rubble(p, rng, x, y, 5, .6)
            else:
                st.bones(p, rng, x, y)
        for sx, sy in ((-HX + 1.2, -5.0), (-HX + 1.2, 5.0), (-4.0, HY - 1.2), (8.0, HY - 1.2), (-10.0, HY - 1.2)):
            for k in range(3):
                mushroom(p, rng, sx + rng.uniform(-.5, .5), sy + rng.uniform(-.5, .5), big=1.5)
            light(layout, sx, 1.3, sy, cfg["light"], 2.2, 9.5, .18)
        for sy in (-3.0, 3.0):
            rock_spire(p, rng, HX + .5, sy * 1.2, big=1.1)

    elif zone == "waxen_desert":
        stones = tile_floor(f, rng, zone, (1.6, 3.4), (.01, .035), sides=8, accent_chance=.08, rows=(1.0, 1.9))
        cracks(f, rng, "sand_dark", 34)
        for x, y in far:
            if rng.random() > .45:
                sandstone_block(w, rng, x, y, big=1.3)
            dune(w, rng, x + rng.uniform(-.6, .6), y + rng.uniform(-.6, .6), rng.uniform(1.4, 2.4), rng.uniform(1.0, 2.6))
        for x, y in near:
            dune(w, rng, x, y, rng.uniform(.8, 1.4), rng.uniform(.5, .9))
        for _ in range(14):
            cactus(p, rng, rng.uniform(-HX + 1.5, HX - 1.5), rng.uniform(-HY + 1.5, HY - 1.5))
        for _ in range(6):
            st.bones(p, rng, rng.uniform(-HX + 2, HX - 2), rng.uniform(-HY + 2, HY - 2))
        for cx, cy in ((-HX + 1.4, -5.5), (-HX + 1.4, 5.5), (-3.0, HY - 1.4), (9.0, HY - 1.4), (-12.0, HY - 1.4)):
            candle(p, rng, cx, cy, big=1.3)
            light(layout, cx, 2.2, cy, cfg["light"], 2.4, 10.0, .3)
        for sy in (-3.0, 3.0):
            obelisk(p, rng, HX + .5, sy * 1.2)

    elif zone == "castle_crimson":
        stones = castle_floor(f, rng)
        bricks = ("brick_a", "brick_b", "brick_c", "brick_dark")
        st.wall_course_blocks(w, rng, -HY - 1.2, HY + 1.2, -HX - .45, WALL_H, False, .7, 0, bricks)
        st.wall_course_blocks(w, rng, -HX - 1.2, HX + 1.2, HY + .45, WALL_H, True, .7, 1, bricks)
        st.wall_course_blocks(w, rng, -HX - 1.2, HX + 1.2, -HY - .4, st.PARAPET_H, True, .6, 2, bricks)
        st.wall_course_blocks(w, rng, -HY - 1.2, -2.6, HX + .4, st.PARAPET_H + .2, False, .6, 3, bricks)
        st.wall_course_blocks(w, rng, 2.6, HY + 1.2, HX + .4, st.PARAPET_H + .2, False, .6, 4, bricks)
        for y in (-12.0, -6.0, 0.0, 6.0, 12.0):
            st.pillar(p, -HX + .2, y, WALL_H)
        for x in (-10.0, -4.0, 2.0, 8.0, 13.0):
            st.pillar(p, x, HY - .3, WALL_H)
        for y in (-9.0, -3.0, 3.0, 9.0):
            banner(p, -HX + .05, y, False)
        for x in (-12.0, -7.0, -1.0, 5.0, 11.0):
            banner(p, x, HY - .05, True)
        for ty in (-9.0, -3.0, 3.0, 9.0):
            st.wall_torch(p, -HX - .1, ty, (1, 0))
            light(layout, -HX + .25, 2.6, ty, cfg["light"], 2.6, 10.0, .3)
        for tx in (-9.0, -3.0, 4.0, 10.0):
            st.wall_torch(p, tx, HY + .1, (0, -1))
            light(layout, tx, 2.6, HY - .25, cfg["light"], 2.6, 10.0, .3)
        st.gateway(p, rng, HX + .4)
        for cx, cy in ((-HX + .9, -HY + .8), (HX - .8, HY - .9)):
            st.rubble(p, rng, cx, cy, 10, .9)
        st.bones(p, rng, -5.0, 6.0)
        st.bones(p, rng, 7.0, -7.0)

    layout.update({
        "units": "metres; x, z are Godot ground coordinates (z = -Blender y)",
        "px_per_m": 23.3,
        "bounds": {"min_x": -HX, "max_x": HX, "min_z": -HY, "max_z": HY},
        "spawns": {"party": [{"x": -8.6, "z": z} for z in (-3.0, -1.0, 1.0, 3.0)],
                   "enemy_entry": [{"x": HX + 0.8, "z": z} for z in (-1.2, 0.0, 1.2)],
                   "enemy_inside": [{"x": 8.0, "z": -2.0}, {"x": 8.0, "z": 2.0}]},
        "camera": {"yaw_deg": 0, "pitch_deg": 22, "projection": "orthogonal"},
        "emissive_materials": emissive,
        "far_walls": ["-X end", "-Z side"],
        "environment": {"zone": zone, "name": cfg["name"], "ambient_color": list(cfg["ambient"]), "ambient_energy": cfg["ambient_e"],
                        "fill_color": list(cfg["fill"]), "fill_energy": cfg["fill_e"]},
        "stats": {"floor_tiles": stones},
    })
    return objects, layout


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_root = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "../godot/models/stage")
    zones = args[1:] or list(ZONES)
    for zone in zones:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        objects, layout = build_zone(zone)
        out_dir = os.path.join(out_root, zone)
        os.makedirs(out_dir, exist_ok=True)
        objs = []
        for name, builder in objects.items():
            obj = h.make_object(name, builder)
            for poly in obj.data.polygons:
                poly.use_smooth = False
            assert all(q.area > 1e-10 for q in obj.data.polygons), f"{zone}/{name}: degenerate faces"
            assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co), f"{zone}/{name}: bad geometry"
            print("MESH", zone, name, "triangles", h.count_tris(obj))
            objs.append(obj)
        h.export(objs, os.path.join(out_dir, "stage.glb"), False)
        with open(os.path.join(out_dir, "stage.json"), "w") as fh:
            json.dump(layout, fh, indent=2)
        print("ZONE_OK", zone, layout["stats"], "lights", len(layout["lights"]))


if __name__ == "__main__":
    main()
