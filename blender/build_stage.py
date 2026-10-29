"""build_stage.py - the rudimentary cobblestone dungeon battle stage.

Run (headless):
    blender --background --python blender/build_stage.py -- godot/models/stage

Writes stage.glb (three meshes: stage_floor, stage_walls, stage_props) and stage.json (everything
the game needs that is not a mesh: walkable bounds, obstacles for navigation, spawn points, lights).

Conventions
  * Metres. Blender Z-up; the glTF export maps (x, y, z) -> Godot (x, z, -y), so a point at Blender
    (x, y) is at ground (x, z = -y) in Godot and in stage.json. stage.json always uses Godot ground
    coordinates (x, z).
  * The arena is 30 x 32 m (the old 800 x 450 px play area at ~23.3 px/m), long axis along X.
    Party starts at the -X end, enemies enter through the gateway at the +X end.
  * Camera (see godot/view/stage_scene.gd): orthographic, SIDEWAYS top-down like the 2D game: yaw 0 (looking along
    -Z, the arena's long X axis runs left to right on screen), pitch 40 deg. (Director: "more sideways top down like the
    original"; the earlier 2:1 dimetric view was yaw 45, pitch 30.) The FAR walls (the -X end and the back, Blender +Y)
    are full height; the NEAR sides (the +X end with the gateway, and the front, Blender -Y) are low parapets so
    nothing hides the fight.
  * Flat-shaded faceted lofts in flat colours, no textures, like the characters. Fully seeded: the same
    run always produces the same stage.
All shapes, sizes and colours are CR-original art direction [tuned].
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_humanoid as h
import build_monsters as m   # rod / panel / bulb helpers

SEED = 20261028
ARENA_W, ARENA_D = 30.0, 32.0          # walkable area (m)
HX, HY = ARENA_W / 2, ARENA_D / 2
WALL_H = 4.2                            # far walls
PARAPET_H = 0.9                         # near walls
OBSTACLES = False                       # free-standing pillars, ruined walls and braziers in the arena (off: an open floor)

PALETTE = {
    "stone_a": (118, 112, 106), "stone_b": (98, 93, 92), "stone_c": (132, 125, 114), "stone_d": (84, 82, 88),
    "moss": (64, 82, 54), "mortar": (30, 28, 31), "wall_a": (104, 98, 96), "wall_b": (88, 85, 88),
    "wall_c": (120, 113, 104), "wall_dark": (58, 56, 62), "wood_dark": (74, 48, 26), "iron_black": (42, 42, 48),
    "flame": (255, 168, 58), "flame_core": (255, 226, 130), "bone_pile": (196, 190, 160),
}
for key, colour in PALETTE.items():
    h.COLOURS[key] = colour
    if key not in h.MATS:
        h.MATS.append(key)

FLOOR_STONES = ("stone_a", "stone_b", "stone_c", "stone_d")
WALL_STONES = ("wall_a", "wall_b", "wall_c", "wall_dark")


def jitter(rng, v, amount):
    return v + rng.uniform(-amount, amount)


# ------------------------------------------------------------------------ floor
def build_floor(b, rng):
    """Irregular cobbles in staggered rows over a dark mortar slab. A one-metre apron past the
    walkable area runs under the walls."""
    width, depth = ARENA_W + 2.4, ARENA_D + 2.4
    b.loft("floor", "mortar", [(0, 0, -.12, width / 2, depth / 2), (0, 0, -.005, width / 2, depth / 2)], box=True)
    stones = 0
    y = -depth / 2
    while y < depth / 2 - .2:
        row = rng.uniform(.5, .78)
        x = -width / 2 + rng.uniform(0, .45)
        while x < width / 2 - .2:
            w = rng.uniform(.5, .98)
            cx, cy = x + w / 2, y + row / 2
            rx, ry = max(.12, w / 2 - .035), max(.12, row / 2 - .035)
            top = rng.uniform(.04, .11)
            colour = rng.choice(FLOOR_STONES) if rng.random() > .06 else "moss"
            rot = rng.uniform(0, math.pi / 3)
            rings = [(cx, cy, -.01, rx, ry),
                     (cx, cy, top * .6, rx * .97, ry * .97),
                     (cx, cy, top, rx * rng.uniform(.74, .88), ry * rng.uniform(.74, .88))]
            b.loft("floor", colour, rings, sides=6, rot=rot)
            stones += 1
            x += w
        y += row
    return stones


# ------------------------------------------------------------------------- walls
def wall_course_blocks(b, rng, a0, a1, fixed, height, along_x, thick, courses_seed, stones=None):
    """A stone wall of staggered courses. along_x=True runs along X at Blender y=fixed, else along Y at
    x=fixed. Block faces jitter a little in depth and height so the wall reads as rough masonry."""
    z = 0.0
    course = 0
    while z < height - .05:
        ch = min(rng.uniform(.4, .52), height - z)
        s = a0 - rng.uniform(0, .5) * (course % 2)
        while s < a1:
            length = rng.uniform(.8, 1.5)
            t = thick * rng.uniform(.9, 1.08)
            depth_off = rng.uniform(-.04, .04)
            lo, hi = s + .02, min(s + length, a1 + .6) - .02
            mid, half = (lo + hi) / 2, (hi - lo) / 2
            hgt = ch * rng.uniform(.94, 1.0)
            colour = rng.choice(stones or WALL_STONES)
            if along_x:
                rings = [(mid, fixed + depth_off, z, half, t / 2), (mid, fixed + depth_off, z + hgt, half * .98, t / 2 * .97)]
            else:
                rings = [(fixed + depth_off, mid, z, t / 2, half), (fixed + depth_off, mid, z + hgt, t / 2 * .97, half * .98)]
            b.loft("walls", colour, rings, box=True)
            s += length
        z += ch
        course += 1


def build_walls(b, rng):
    far_t, low_t = .7, .6
    # FAR walls: -X end (a wall along Y) and the Blender +Y side (a wall along X)
    wall_course_blocks(b, rng, -HY - 1.2, HY + 1.2, -HX - .45, WALL_H, False, far_t, 0)
    wall_course_blocks(b, rng, -HX - 1.2, HX + 1.2, HY + .45, WALL_H, True, far_t, 1)
    # NEAR parapets: -Y side (full length) and the +X end, which has the gateway gap in the middle
    wall_course_blocks(b, rng, -HX - 1.2, HX + 1.2, -HY - .4, PARAPET_H, True, low_t, 2)
    gate_half = 2.0
    wall_course_blocks(b, rng, -HY - 1.2, -gate_half - .55, HX + .4, PARAPET_H + .2, False, low_t, 3)
    wall_course_blocks(b, rng, gate_half + .55, HY + 1.2, HX + .4, PARAPET_H + .2, False, low_t, 4)


# ------------------------------------------------------------------------- props
def pillar(b, x, y, height=WALL_H):
    """Round stone column: square plinth, tapered shaft with bands, square capital."""
    b.loft("props", "wall_dark", [(x, y, 0, .62, .62), (x, y, .35, .62, .62)], box=True)
    b.loft("props", "wall_b", [(x, y, .35, .5, .5), (x, y, height * .5, .44, .44), (x, y, height - .4, .46, .46)], sides=8)
    for z in (.9, height * .5, height - .7):
        b.loft("props", "wall_c", [(x, y, z, .5, .5), (x, y, z + .16, .5, .5)], sides=8)
    b.loft("props", "wall_dark", [(x, y, height - .4, .66, .66), (x, y, height, .66, .66)], box=True)


def brazier(b, rng, x, y, lit=True):
    """Iron bowl on a tripod with a faceted flame (the flame material is emissive in Godot)."""
    for k in range(3):
        a = k * 2 * math.pi / 3 + .4
        m.rod(b, "props", "iron_black", (x + math.cos(a) * .32, y + math.sin(a) * .32, 0),
              (x + math.cos(a) * .1, y + math.sin(a) * .1, .95), .035, 5)
    b.loft("props", "iron_black", [(x, y, .8, .2, .2), (x, y, .95, .36, .36), (x, y, 1.12, .42, .42)], sides=8)
    if lit:
        b.loft("props", "flame", [(x, y, 1.06, .3, .3), (x, y, 1.35, .2, .2), (x, y, 1.62, .02, .02)], sides=6, rot=rng.uniform(0, 1))
        b.loft("props", "flame_core", [(x, y, 1.08, .15, .15), (x, y, 1.3, .09, .09), (x, y, 1.45, .01, .01)], sides=5)


def wall_torch(b, x, y, face):
    """Torch bracket on a far wall. face = (dx, dy) direction the torch points out of the wall."""
    fx, fy = face
    m.rod(b, "props", "iron_black", (x, y, 2.05), (x + fx * .3, y + fy * .3, 2.25), .035, 5)
    b.loft("props", "wood_dark", [(x + fx * .3, y + fy * .3, 2.2, .05, .05), (x + fx * .3, y + fy * .3, 2.55, .06, .06)], sides=5)
    b.loft("props", "flame", [(x + fx * .3, y + fy * .3, 2.5, .1, .1), (x + fx * .3, y + fy * .3, 2.75, .07, .07),
                              (x + fx * .3, y + fy * .3, 2.95, .01, .01)], sides=5)


def rubble(b, rng, cx, cy, count, spread):
    for _ in range(count):
        x, y = cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread, spread)
        r = rng.uniform(.07, .24)
        hgt = r * rng.uniform(.6, 1.2)
        b.loft("props", rng.choice(FLOOR_STONES + WALL_STONES), [(x, y, 0, r, r * .8), (x, y, hgt * .6, r * .9, r * .72),
                                                              (x, y, hgt, r * .45, r * .35)], sides=rng.choice((5, 6, 7)),
               rot=rng.uniform(0, 1))


def broken_wall(b, rng, x, y, length, turn):
    """A knee-to-waist-high ruined wall segment that blocks movement. turn=True runs along Y."""
    a0 = -length / 2
    z = 0.0
    while z < 1.25:
        ch = rng.uniform(.38, .46)
        s = a0 + rng.uniform(0, .3)
        end = length / 2 - rng.uniform(0, .5 * (z / 1.25 + .2))
        while s < end:
            ln = min(rng.uniform(.7, 1.2), end - s)
            if ln < .25:
                break
            mid = s + ln / 2
            px, py = (x, y + mid) if turn else (x + mid, y)
            half = (ln / 2 - .02, .3) if not turn else (.3, ln / 2 - .02)
            b.loft("props", rng.choice(WALL_STONES), [(px, py, z, half[0], half[1]),
                                                     (px, py, z + ch * .96, half[0] * .98, half[1] * .98)], box=True)
            s += ln
        z += ch


def gateway(b, rng, x, y_center=0.0):
    """Stone archway at the +X end: two square posts and a semicircular arch of voussoirs. Enemies enter here."""
    gate_half, post = 2.0, .55
    for side in (-1, 1):
        py = y_center + side * (gate_half + post / 2 + .02)
        b.loft("props", "wall_c", [(x, py, 0, .5, post / 2), (x, py, 3.0, .5, post / 2)], box=True)
        b.loft("props", "wall_dark", [(x, py, 0, .56, post / 2 + .06), (x, py, .3, .56, post / 2 + .06)], box=True)
    radius = gate_half + post * .5
    steps = 9
    for i in range(steps):
        a0 = math.pi * i / steps
        a1 = math.pi * (i + 1) / steps
        am = (a0 + a1) / 2
        r_in, r_out = gate_half - .05, gate_half + post + .3
        pa = (x, y_center + math.cos(am) * r_in, 3.0 + math.sin(am) * r_in)
        pb = (x, y_center + math.cos(am) * r_out, 3.0 + math.sin(am) * r_out)
        m.rod(b, "props", WALL_STONES[i % 4], pa, pb, .34, 4)
    # keystone and a dark opening plate so the doorway reads against the near wall
    m.rod(b, "props", "wall_c", (x, y_center, 3.0 + gate_half - .1), (x, y_center, 3.0 + gate_half + post + .42), .4, 4)


def bones(b, rng, cx, cy):
    """A small heap of bones for atmosphere."""
    for _ in range(9):
        x, y = cx + rng.uniform(-.5, .5), cy + rng.uniform(-.5, .5)
        a = rng.uniform(0, math.pi)
        ln = rng.uniform(.25, .5)
        m.rod(b, "props", "bone_pile", (x, y, .05), (x + math.cos(a) * ln, y + math.sin(a) * ln, .05 + rng.uniform(0, .12)), .025, 5)
    m.bulb(b, "props", "bone_pile", (cx, cy, .1), (.12, .1, .11), 6)


# -------------------------------------------------------------------------- stage
def build():
    rng = random.Random(SEED)
    layout = {"obstacles": [], "lights": []}
    objects = {}
    for name in ("stage_floor", "stage_walls", "stage_props"):
        objects[name] = h.Builder()
    stones = build_floor(objects["stage_floor"], rng)
    build_walls(objects["stage_walls"], rng)
    p = objects["stage_props"]

    # Navigation obstacles are authored here and exported next to the mesh. Blender (x, y) -> ground (x, -y).
    def obstacle(kind, x, y, **kw):
        entry = {"type": kind, "x": round(x, 3), "z": round(-y, 3)}
        entry.update(kw)
        layout["obstacles"].append(entry)

    if OBSTACLES:
        for px, py in ((-8.0, -4.5), (-8.0, 4.5), (6.5, -4.5), (6.5, 4.5)):
            pillar(p, px, py)
            obstacle("circle", px, py, r=.66)
        # two ruined wall segments to route around (long axis along X / along Y)
        broken_wall(p, rng, 0.5, -3.2, 3.6, False)
        obstacle("box", 0.5, -3.2, w=3.7, d=.65)
        broken_wall(p, rng, -1.5, 3.6, 3.0, True)
        obstacle("box", -1.5, 3.6, w=.65, d=3.1)
        # braziers (lit) flanking the party end and the gateway
        for bx, by in ((-HX + 1.0, -2.5), (-HX + 1.0, 2.5), (HX - 1.2, -3.6), (HX - 1.2, 3.6)):
            brazier(p, rng, bx, by)
            obstacle("circle", bx, by, r=.45)
            layout["lights"].append({"x": round(bx, 3), "y": 1.5, "z": round(-by, 3), "color": [1.0, .6, .28],
                                     "energy": 2.2, "range": 9.0, "flicker": .25})
    gateway(p, rng, HX + .4)
    # wall torches on the far walls (they light the floor; there are no free-standing lights)
    for ty in (-5.0, 0.0, 5.0):                       # -X end wall (faces +X)
        wall_torch(p, -HX - .1, ty, (1, 0))
        layout["lights"].append({"x": round(-HX + .25, 3), "y": 2.6, "z": round(-ty, 3), "color": [1.0, .58, .25],
                                 "energy": 2.4, "range": 10.0, "flicker": .3})
    for tx in (-10.0, -2.0, 6.0, 12.0):               # +Y side wall (faces -Y)
        wall_torch(p, tx, HY + .1, (0, -1))
        layout["lights"].append({"x": tx, "y": 2.6, "z": round(-(HY - .25), 3), "color": [1.0, .58, .25],
                                 "energy": 2.4, "range": 10.0, "flicker": .3})
    for cx, cy in ((-HX + .9, -HY + .8), (-HX + .8, HY - .8), (HX - .8, HY - .9), (3.5, HY - .7), (-4.0, -HY + .7)):
        rubble(p, rng, cx, cy, 14, 1.0)
    bones(p, rng, -3.0, 1.2)
    bones(p, rng, 9.5, -1.8)

    layout.update({
        "units": "metres; x, z are Godot ground coordinates (z = -Blender y)",
        "px_per_m": 23.3,
        "bounds": {"min_x": -HX, "max_x": HX, "min_z": -HY, "max_z": HY},
        "spawns": {
            # the 2D game's party stands at VW*0.25; four heroes in a column, facing +X
            "party": [{"x": -8.6, "z": z} for z in (-3.0, -1.0, 1.0, 3.0)],
            # enemies walk in through the gateway (2D: from the right edge)
            "enemy_entry": [{"x": HX + 0.8, "z": z} for z in (-1.2, 0.0, 1.2)],
            "enemy_inside": [{"x": 8.0, "z": -2.0}, {"x": 8.0, "z": 2.0}],
        },
        "camera": {"yaw_deg": 0, "pitch_deg": 22, "projection": "orthogonal"},
        "emissive_materials": ["flame", "flame_core"],
        "far_walls": ["-X end", "-Z side"],
        "stats": {"floor_stones": stones},
    })
    return objects, layout


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "../godot/models/stage")
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects, layout = build()
    objs = []
    for name, builder in objects.items():
        obj = h.make_object(name, builder)
        for poly in obj.data.polygons:
            poly.use_smooth = False
        assert all(p.area > 1e-10 for p in obj.data.polygons), f"{name}: degenerate faces"
        assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co), f"{name}: bad geometry"
        print("MESH", name, "triangles", h.count_tris(obj))
        objs.append(obj)
    h.export(objs, os.path.join(out_dir, "stage.glb"), False)
    with open(os.path.join(out_dir, "stage.json"), "w") as f:
        json.dump(layout, f, indent=2)
    blend = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stage.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("STAGE_OK", layout["stats"], "obstacles", len(layout["obstacles"]), "lights", len(layout["lights"]))


if __name__ == "__main__":
    main()
