"""build_humanoid.py - builds the test models for Crimson Red 3D (knight, mannequin).

OSRS-style low poly: flat-shaded, faceted, tapered limbs (no boxes), diamond eyes.
Colours and stance copy the 2D Knight sprite (navy tabard, black sleeves/legs, grey armour).
One mesh, one connected 24-bone shared skeleton, seven animations
(Idle, Move, Attack1, Attack2, Attack3, TakeHit, Death) and a separate sword prop, exported as .glb for Godot.

Run (headless):
    blender --background --python build_humanoid.py -- <output_dir> [knight|mannequin]

Conventions (every future model must follow these so animations and gear are interchangeable):
  * Blender is Z-up. The character faces -Y (glTF export turns that into Godot's +Z, "forward").
    The character's left side is +X.
  * Bone names use underscores (upper_arm_L), not dots: Godot node names dislike dots.
  * Every child starts at its parent's tail. Pelvis branches and clavicles bridge the
    torso to the limbs; feet/toes follow the sole. Main limb segments stay vertical at rest.
    `rot()` and `pos()` express poses in degrees/metres; foot targets are solved in world space.
  * Props (weapons) have their origin at the grip and the blade along +Z.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, Quaternion, Euler

FPS = 240  # [tuned] clips are authored in seconds; dense 240Hz keys keep fast strikes from sliding the planted feet.
SQ2 = math.sqrt(2.0)

# ---- skeleton ----------------------------------------------------------------
# name: (parent, head (x, y, z), tail (x, y, z))
BONES = {
    "root":    (None,     (0, 0, 0),      (0, 0, 0.90)),
    "hips":    ("root",   (0, 0, 0.90),   (0, 0, 1.04)),
    "spine1":  ("hips",   (0, 0, 1.04),   (0, 0, 1.26)),
    "spine2":  ("spine1", (0, 0, 1.26),   (0, 0, 1.48)),
    "neck":    ("spine2", (0, 0, 1.48),   (0, 0, 1.62)),
    "head":    ("neck",   (0, 0, 1.62),   (0, 0, 1.88)),
}
for _s, _x in (("L", 1), ("R", -1)):
    BONES.update({
        f"clavicle_{_s}":  ("spine2", (0, 0, 1.48), (_x * 0.27, 0, 1.45)),
        f"upper_arm_{_s}": (f"clavicle_{_s}", (_x * 0.27, 0, 1.45), (_x * 0.27, 0, 1.15)),
        f"forearm_{_s}":   (f"upper_arm_{_s}", (_x * 0.27, 0, 1.15), (_x * 0.27, 0, 0.88)),
        f"hand_{_s}":      (f"forearm_{_s}", (_x * 0.27, 0, 0.88), (_x * 0.27, 0, 0.72)),
        f"pelvis_{_s}":    ("hips", (0, 0, 1.04), (_x * 0.10, 0, 0.90)),
        f"thigh_{_s}":     (f"pelvis_{_s}", (_x * 0.10, 0, 0.90), (_x * 0.10, 0, 0.50)),
        f"shin_{_s}":      (f"thigh_{_s}", (_x * 0.10, 0, 0.50), (_x * 0.10, 0, 0.085)),
        f"foot_{_s}":      (f"shin_{_s}", (_x * 0.10, 0, 0.085), (_x * 0.10, -0.10, 0.05)),
        f"toe_{_s}":       (f"foot_{_s}", (_x * 0.10, -0.10, 0.05), (_x * 0.10, -0.18, 0.025)),
    })


def is_up(bone):
    return BONES[bone][2][2] > BONES[bone][1][2]


# ---- colours (sRGB, from the 2D Knight sprite / OSRS reference) ---------------
COLOURS = {
    "skin":  (214, 160, 126),
    "hair":  (24, 20, 28),
    "navy":  (40, 62, 132),
    "navy2": (26, 42, 96),
    "black": (30, 30, 38),
    "grey":  (150, 156, 168),
    "steel": (205, 212, 224),
    "eye":   (10, 10, 12),
    "white": (238, 238, 244),
    "mgrey": (168, 172, 190),
}
MATS = list(COLOURS)


def make_material(name):
    r, g, b = COLOURS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = ((r / 255) ** 2.2, (g / 255) ** 2.2, (b / 255) ** 2.2, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


# ---- mesh building: ring lofts -------------------------------------------------
class Builder:
    """Lofts closed ring stacks into faceted solids. Each loft is rigidly bound to one bone."""

    def __init__(self):
        self.bm = bmesh.new()
        self.groups = {}   # bone -> [BMVert]

    def loft(self, bone, mat, rings, sides=8, axis="Z", box=False, rot=0.0):
        """rings: axis Z -> (cx, cy, cz, rx, ry); axis Y -> (cx, cy, cz, rx, rz).
        box=True makes a 4-sided rectangle with half-sizes rx, ry (or rz)."""
        if box:
            sides, rot = 4, math.pi / 4
        scale = SQ2 if box else 1.0
        stack = []
        for cx, cy, cz, ra, rb in rings:
            ring = []
            for k in range(sides):
                a = rot + 2 * math.pi * k / sides
                if axis == "Z":
                    co = (cx + ra * scale * math.cos(a), cy + rb * scale * math.sin(a), cz)
                else:
                    co = (cx + ra * scale * math.cos(a), cy, cz + rb * scale * math.sin(a))
                ring.append(self.bm.verts.new(co))
            stack.append(ring)
        faces = [stack[0][::-1], stack[-1]]
        for lo, hi in zip(stack, stack[1:]):
            for k in range(sides):
                faces.append([lo[k], lo[(k + 1) % sides], hi[(k + 1) % sides], hi[k]])
        mi = MATS.index(mat)
        for verts in faces:
            f = self.bm.faces.new(verts)
            f.material_index = mi
            f.smooth = False
        self.groups.setdefault(bone, []).extend(v for ring in stack for v in ring)

    def broaden_head(self):
        # [tuned] 18% broader skull/jaw/hair, same height, depth and polygon count.
        for bone in ("head",):
            for v in self.groups.get(bone, []):
                v.co.x *= 1.18

    def finish(self, mesh):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        self.bm.verts.index_update()
        idx = {b: [v.index for v in vs] for b, vs in self.groups.items()}
        self.bm.to_mesh(mesh)
        self.bm.free()
        return idx


def build_body(b):
    """Athletic ~8-head proportions: small head, long neck, V-taper torso, long limbs that
    swell at the muscle and slim at wrist and ankle."""
    # pelvis + legs (black trousers, grey greaves and boots)
    b.loft("hips", "black", [(0, 0, .86, .15, .10), (0, 0, .96, .175, .115), (0, 0, 1.06, .15, .10)])
    for s, x in (("L", 1), ("R", -1)):
        b.loft(f"thigh_{s}", "black", [(x * .10, 0, .92, .105, .105), (x * .10, 0, .78, .098, .098),
                                       (x * .10, 0, .62, .08, .082), (x * .10, 0, .50, .062, .065)], 7)
        b.loft(f"shin_{s}", "black", [(x * .10, 0, .50, .062, .065), (x * .10, 0, .42, .068, .075)], 7)
        b.loft(f"shin_{s}", "grey", [(x * .10, 0, .47, .07, .078), (x * .10, 0, .36, .072, .086),
                                     (x * .10, 0, .22, .058, .066), (x * .10, 0, .12, .045, .05)], 7)
        b.loft(f"foot_{s}", "grey", [(x * .10, .06, .05, .04, .04), (x * .10, -.03, .05, .05, .045), (x * .10, -.09, .04, .048, .038)], 6, axis="Y")
        b.loft(f"toe_{s}", "grey", [(x * .10, -.09, .04, .048, .038), (x * .10, -.15, .03, .038, .03), (x * .10, -.18, .025, .02, .02)], 6, axis="Y")
    # tunic (narrow waist, broad chest), tabard panels, gorget
    b.loft("spine1", "navy", [(0, 0, 1.04, .15, .10), (0, 0, 1.16, .175, .115), (0, 0, 1.28, .215, .125)])
    b.loft("spine2", "navy", [(0, 0, 1.26, .205, .125), (0, 0, 1.36, .245, .14), (0, 0, 1.45, .26, .125), (0, 0, 1.50, .15, .09)])
    b.loft("spine2", "grey", [(0, 0, 1.47, .16, .115), (0, 0, 1.54, .11, .085)], 8)
    for i, (z0, z1) in enumerate(((1.02, .88), (.88, .74), (.74, .58)), start=1):
        b.loft("hips", "navy", [(0, -.12, z0, .16 - .012 * i, .012), (0, -.12, z1, .16 - .012 * (i + 1), .012)], box=True)
        b.loft("hips", "navy2", [(0, .12, z0, .16 - .012 * i, .012), (0, .12, z1, .16 - .012 * (i + 1), .012)], box=True)
    # neck, small head, face, hair
    b.loft("neck", "skin", [(0, 0, 1.50, .06, .06), (0, 0, 1.64, .05, .052)], 6)
    b.loft("head", "skin", [(0, 0, 1.60, .05, .055), (0, -.005, 1.66, .075, .085), (0, -.005, 1.75, .085, .095),
                            (0, 0, 1.82, .07, .08), (0, 0, 1.86, .035, .045)], 8)
    b.loft("head", "skin", [(0, -.088, 1.70, .02, .028), (0, -.13, 1.69, .007, .011)], 4, axis="Y")            # nose
    for x in (.036, -.036):
        b.loft("head", "eye", [(x, -.097, 1.745, .02, .01), (x, -.101, 1.745, .02, .01)], 4, axis="Y")        # diamond eyes
    b.loft("head", "hair", [(0, .02, 1.72, .092, .102), (0, .02, 1.80, .098, .108), (0, .015, 1.87, .072, .082), (0, .01, 1.915, .03, .04)], 8)
    b.loft("head", "hair", [(0, .085, 1.82, .065, .036), (0, .095, 1.72, .052, .032), (0, .10, 1.62, .03, .022)], 6)
    # arms: broad shoulder armour, muscular black sleeves, grey bracers and gauntlets
    for s, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s}", "grey", [(x * .27, 0, 1.52, .055, .055), (x * .27, 0, 1.48, .12, .11), (x * .27, 0, 1.38, .11, .10)], 7)
        b.loft(f"upper_arm_{s}", "black", [(x * .27, 0, 1.44, .07, .07), (x * .27, 0, 1.34, .078, .074),
                                           (x * .27, 0, 1.25, .07, .066), (x * .27, 0, 1.15, .052, .052)], 7)
        b.loft(f"forearm_{s}", "black", [(x * .27, 0, 1.15, .052, .052), (x * .27, 0, 1.06, .062, .058), (x * .27, 0, .88, .044, .044)], 7)
        b.loft(f"forearm_{s}", "grey", [(x * .27, 0, 1.02, .066, .062), (x * .27, 0, .88, .05, .05)], 7)
        b.loft(f"hand_{s}", "grey", [(x * .27, 0, .88, .05, .045), (x * .27, 0, .80, .058, .05), (x * .27, 0, .72, .04, .035)], 6)


def build_mannequin_body(b):
    """Plain faceless white mannequin on the same skeleton and proportions as the Knight."""
    b.loft("hips", "white", [(0, 0, .86, .15, .10), (0, 0, .96, .175, .115), (0, 0, 1.06, .15, .10)])
    b.loft("spine1", "white", [(0, 0, 1.04, .15, .10), (0, 0, 1.16, .175, .115), (0, 0, 1.28, .215, .125)])
    b.loft("spine2", "white", [(0, 0, 1.26, .205, .125), (0, 0, 1.36, .245, .14), (0, 0, 1.45, .26, .125), (0, 0, 1.50, .15, .09)])
    b.loft("neck", "white", [(0, 0, 1.48, .06, .06), (0, 0, 1.64, .05, .052)], 6)
    b.loft("head", "white", [(0, 0, 1.60, .05, .055), (0, -.005, 1.66, .075, .085), (0, -.005, 1.75, .085, .095),
                             (0, 0, 1.82, .07, .08), (0, 0, 1.87, .035, .045)], 8)
    for s, x in (("L", 1), ("R", -1)):
        b.loft(f"clavicle_{s}", "white", [(x * .27, 0, 1.51, .05, .05), (x * .27, 0, 1.46, .095, .09), (x * .27, 0, 1.38, .08, .08)], 7)
        b.loft(f"upper_arm_{s}", "white", [(x * .27, 0, 1.44, .07, .07), (x * .27, 0, 1.34, .078, .074),
                                           (x * .27, 0, 1.25, .07, .066), (x * .27, 0, 1.15, .052, .052)], 7)
        b.loft(f"forearm_{s}", "mgrey", [(x * .27, 0, 1.17, .058, .058), (x * .27, 0, 1.13, .058, .058)], 7)       # elbow joint
        b.loft(f"forearm_{s}", "white", [(x * .27, 0, 1.15, .052, .052), (x * .27, 0, 1.06, .062, .058), (x * .27, 0, .88, .044, .044)], 7)
        b.loft(f"hand_{s}", "white", [(x * .27, 0, .88, .05, .045), (x * .27, 0, .80, .056, .05), (x * .27, 0, .72, .036, .03)], 6)
        b.loft(f"thigh_{s}", "white", [(x * .10, 0, .92, .105, .105), (x * .10, 0, .78, .098, .098),
                                       (x * .10, 0, .62, .08, .082), (x * .10, 0, .50, .062, .065)], 7)
        b.loft(f"shin_{s}", "mgrey", [(x * .10, 0, .52, .07, .072), (x * .10, 0, .48, .07, .072)], 7)             # knee joint
        b.loft(f"shin_{s}", "white", [(x * .10, 0, .50, .062, .065), (x * .10, 0, .36, .072, .086),
                                      (x * .10, 0, .22, .058, .066), (x * .10, 0, .12, .045, .05)], 7)
        b.loft(f"foot_{s}", "white", [(x * .10, .06, .05, .04, .04), (x * .10, -.03, .05, .05, .045), (x * .10, -.09, .04, .048, .038)], 6, axis="Y")
        b.loft(f"toe_{s}", "white", [(x * .10, -.09, .04, .048, .038), (x * .10, -.15, .03, .038, .03), (x * .10, -.18, .025, .02, .02)], 6, axis="Y")


def build_sword(b):
    """Origin at the grip, blade along +Z."""
    b.loft("sword", "black", [(0, 0, -.10, .02, .02), (0, 0, .09, .02, .02)], 6)
    b.loft("sword", "grey", [(0, 0, -.15, .03, .03), (0, 0, -.10, .03, .03)], 6)
    b.loft("sword", "grey", [(0, 0, .09, .11, .02), (0, 0, .13, .11, .02)], box=True)
    b.loft("sword", "steel", [(0, 0, .13, .03, .009), (0, 0, .60, .032, .009), (0, 0, .86, .004, .002)], 4)


# ---- rig -----------------------------------------------------------------------
def build_armature():
    data = bpy.data.armatures.new("humanoid_rig")
    arm = bpy.data.objects.new("humanoid_rig", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, (parent, head, tail) in BONES.items():
        eb = data.edit_bones.new(name)
        eb.head, eb.tail, eb.roll = head, tail, 0.0
        if parent:
            eb.parent = made[parent]
            assert (eb.head - eb.parent.tail).length < 1e-6, (name, parent)
            eb.use_connect = True
        made[name] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def make_object(name, builder, armature=None):
    mesh = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for m in MATS:
        mesh.materials.append(make_material(m))
    groups = builder.finish(mesh)
    if armature:
        for bone, idx in groups.items():
            obj.vertex_groups.new(name=bone).add(idx, 1.0, "REPLACE")
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = armature
        obj.parent = armature
    return obj


# ---- animation helpers ----------------------------------------------------------
# A pose is {bone: [rx, ry, rz, lx, ly, lz]} in degrees / metres. Poses ADD together.
def rot(bone, pitch=0.0, twist=0.0, side=0.0):
    """pitch: tip swings FORWARD. twist: turns toward the character's LEFT.
    side: tip moves toward the character's LEFT (+X)."""
    if is_up(bone):
        return {bone: [pitch, twist, -side, 0, 0, 0]}
    return {bone: [-pitch, -twist, -side, 0, 0, 0]}


def pos(bone, left=0.0, up=0.0, fwd=0.0):
    """Only for upward-pointing bones (root, hips, spine...)."""
    return {"root" if bone == "hips" else bone: [0, 0, 0, left, up, fwd]}


def add(*poses):
    out = {}
    for p in poses:
        for bone, v in p.items():
            cur = out.setdefault(bone, [0.0] * 6)
            for i in range(6):
                cur[i] += v[i]
    return out


# All poses/timings below are CR-original animation art direction [tuned].
# Feet are solved against world-space contact targets, then baked onto the existing
# deform bones. No runtime IK or extra Godot rig dependency is required.
# `hips` is connected to `root`, so it cannot translate: body offsets given to
# pos("hips") are applied to `root` (pelvis bobbing is root motion in this rig).
STANCE_MANNEQUIN = add(
    pos("hips", up=-.055, left=.018), rot("hips", twist=-4, side=-2),
    rot("spine1", pitch=2, side=2), rot("spine2", pitch=1, twist=4),
    rot("head", pitch=-3, twist=4, side=-1),
    rot("upper_arm_L", pitch=3, side=12), rot("forearm_L", pitch=15),
    rot("upper_arm_R", pitch=-2, side=-10), rot("forearm_R", pitch=18),
    rot("hand_L", pitch=-4), rot("hand_R", pitch=-5),
)
STANCE = add(
    pos("hips", up=-.065, left=.012), rot("hips", twist=-7, side=-2),
    rot("spine1", pitch=3, side=2), rot("spine2", pitch=2, twist=7),
    rot("head", pitch=-5, twist=3),
    rot("upper_arm_R", pitch=24, side=-14), rot("forearm_R", pitch=48),
    rot("hand_R", pitch=2),
    rot("upper_arm_L", pitch=8, side=17), rot("forearm_L", pitch=25),
    rot("hand_L", pitch=-6),
)
STANCES = {"knight": STANCE, "mannequin": STANCE_MANNEQUIN}

CLIP_ORDER = ["Idle", "Move", "Walk", "Cast", "Attack1", "Attack2", "Attack3", "TakeHit", "Death",
              "TwoHandIdle", "TwoHandAttack", "StaffRaise", "StaffCast", "OffhandAttack"]     # the last four: the humanoid bodies only
LOOPING = ("Idle", "Move", "Walk", "TwoHandIdle")

# Per-model locomotion/foot style. feet = (x, front_y, back_y) of the planted soles;
# run = Move gait (lean degrees, arm swing degrees, root drop, bounce, stride half-length,
# foot lift, cycle seconds).
STYLE = {
    "knight":    dict(feet=(.215, -.08, .07), lean=20, arm=48, drop=.02, bounce=.065, twist=12,
                      stride=.56, lift=.36, cycle=.6, duty=.38, idle_bounce=1.0),
    "mannequin": dict(feet=(.215, -.08, .07), lean=16, arm=44, drop=.04, bounce=.06, twist=10,
                      stride=.60, lift=.34, cycle=.62, duty=.38, idle_bounce=.8),
    "goblin":    dict(feet=(.25, -.10, .10), lean=30, arm=55, drop=.09, bounce=.075, twist=16,
                      stride=.54, lift=.32, cycle=.5, duty=.36, idle_bounce=1.3),
    "witch":     dict(feet=(.20, -.08, .08), lean=34, arm=30, drop=.05, bounce=.04, twist=12,
                      stride=.32, lift=.24, cycle=.66, duty=.45, idle_bounce=.4),
    "skeleton":  dict(feet=(.17, -.08, .08), lean=12, arm=34, drop=.04, bounce=.06, twist=10,
                      stride=.56, lift=.30, cycle=.54, duty=.40, idle_bounce=.6),
}


def override(base, *parts):
    """Copy a full pose and REPLACE (not add to) the bones the parts mention."""
    out = {bone: list(v) for bone, v in base.items()}
    out.update(add(*parts))
    return out


def amplify(pose, base, k):
    """Exaggerate `pose` away from `base` by factor k (anticipation / punch)."""
    out = {}
    for bone in pose.keys() | base.keys():
        a, b = pose.get(bone, [0.] * 6), base.get(bone, [0.] * 6)
        out[bone] = [y + (x - y) * k for x, y in zip(a, b)]
    return out


# Easing for the segment that ENDS at a key. "back" overshoots ~10%: the punch.
EASE = {
    "linear": lambda u: u,
    "smooth": lambda u: u * u * (3 - 2 * u),
    "in": lambda u: u * u * u,
    "out": lambda u: 1 - (1 - u) ** 3,
    "snap": lambda u: 1 - (1 - u) ** 4,
    "back": lambda u: 1 + 2.7 * (u - 1) ** 3 + 1.7 * (u - 1) ** 2,
}


def sample_clip(clip, t):
    if "fn" in clip:
        return clip["fn"](t)
    keys = clip["keys"]
    times = sorted(keys)
    if t <= times[0]:
        return keys[times[0]]
    if t >= times[-1]:
        return keys[times[-1]]
    for a, b in zip(times, times[1:]):
        if a <= t <= b:
            u = EASE[clip.get("ease", {}).get(b, "smooth")]((t - a) / (b - a))
            pa, pb = keys[a], keys[b]
            return {bone: [x * (1 - u) + y * u for x, y in
                           zip(pa.get(bone, [0.] * 6), pb.get(bone, [0.] * 6))]
                    for bone in pa.keys() | pb.keys()}


# Walk gait per model (the run is STYLE): a relaxed walk, one foot always down (duty > .5), small bounce.
WALK = {
    "knight":    dict(stride=.64, cycle=1.0, duty=.62, lift=.16, lean=5, arm=20, drop=.012, bounce=.02, twist=9),
    "mannequin": dict(stride=.64, cycle=1.0, duty=.62, lift=.16, lean=5, arm=20, drop=.012, bounce=.02, twist=9),
    "goblin":    dict(stride=.50, cycle=.9, duty=.62, lift=.14, lean=12, arm=26, drop=.05, bounce=.025, twist=11),
    "witch":     dict(stride=.40, cycle=1.1, duty=.65, lift=.11, lean=30, arm=14, drop=.06, bounce=.018, twist=7),
    "skeleton":  dict(stride=.50, cycle=1.0, duty=.62, lift=.14, lean=4, arm=18, drop=.02, bounce=.02, twist=8),
}


def locomotion(model, walk=False):
    """Move clip: a real run. Each foot is planted for `duty` of the cycle, so both feet
    leave the ground between strides (flight phase) and the body rises and falls.
    walk=True builds the Walk clip instead (same rig, WALK numbers, relaxed arms, no flight phase)."""
    st = dict(STYLE[model])
    if walk:
        st.update(WALK[model])
    cycle, duty = st["cycle"], st["duty"]
    s, c = math.sin, math.cos
    mid_stance = duty / 2

    def fn(t):
        u = t / cycle
        phi = 2 * math.pi * u
        # lowest at mid-stance, highest in mid-flight, twice per cycle
        spring = c(4 * math.pi * (u - mid_stance))
        p = add(pos("hips", up=-st["drop"] - st["bounce"] * spring, left=.025 * s(phi)),
                rot("hips", twist=st["twist"] * c(phi), side=3 * s(phi)),
                rot("spine1", pitch=st["lean"] * .55 + 2.5 * spring, side=-3 * s(phi)),
                rot("spine2", pitch=st["lean"] * .45 + 2.5 * spring, twist=-st["twist"] * 1.3 * c(phi)),
                rot("neck", pitch=-st["lean"] * .3),
                rot("head", pitch=-st["lean"] * .5 - 3 * spring, twist=3 * c(phi)))
        for side, sign in (("L", 1), ("R", -1)):
            swing = sign * c(phi)
            pump = sign * s(phi)
            if model == "witch" and side == "R":
                # the staff arm stays put (arm pitches add up to 90: the staff stays upright and she leans on it)
                p = add(p, rot("upper_arm_R", pitch=26 - st["arm"] * .25 * swing, side=-10),
                        rot("forearm_R", pitch=54 + 4 * swing), rot("hand_R", pitch=-26 - 4 * swing))
            elif walk and model in ("knight", "goblin") and side == "R":
                p = add(p, rot("upper_arm_R", pitch=20 - st["arm"] * .4 * swing, side=-12),
                        rot("forearm_R", pitch=52 + 6 * swing), rot("hand_R", pitch=-26))
            elif walk:
                p = add(p, rot(f"upper_arm_{side}", pitch=4 - st["arm"] * swing, side=sign * 6),
                        rot(f"forearm_{side}", pitch=24 - 8 * swing), rot(f"hand_{side}", pitch=-4))
            elif model in ("knight", "goblin") and side == "R":
                # weapon arm stays cocked and pumps less so the blade does not whip about
                p = add(p, rot("upper_arm_R", pitch=34 - st["arm"] * .45 * swing, side=-14),
                        rot("forearm_R", pitch=78 + 10 * swing), rot("hand_R", pitch=-28 + 8 * spring))
            else:
                # running arms: elbows locked near 90 degrees, pumping against the legs
                p = add(p, rot(f"upper_arm_{side}", pitch=6 - st["arm"] * swing, side=sign * 8),
                        rot(f"forearm_{side}", pitch=88 - 12 * swing), rot(f"hand_{side}", pitch=-5))
        return p

    def feet(side, t):
        sign = 1 if side == "L" else -1
        u = ((t / cycle) + (0 if side == "L" else .5)) % 1
        half = st["stride"] / 2
        if u < duty:                      # stance: the sole slides back under the body
            y, z, pitch = -half + 2 * half * u / duty, .085, 0
            pitch = 0
        else:                             # swing: heel kicks up, knee drives forward
            k = (u - duty) / (1 - duty)
            ease = k * k * (3 - 2 * k)
            y = half - 2 * half * ease
            z = .085 + st["lift"] * math.sin(math.pi * k) ** 1.4
            pitch = -35 * math.sin(math.pi * k)
        return Vector((sign * .13, y, z)), pitch, sign * 4
    return {"duration": cycle, "fn": fn, "foot": feet, "loop": True,
            "markers": {}, "props": {"ground_speed_mps": st["stride"] / (duty * cycle)}}


def hit_reaction(model, ready):
    """TakeHit, 3 cels at 6/60: snap away from the blow, rebound past neutral, settle."""
    k = 1.0 if model != "goblin" else 1.15
    impact = override(ready, pos("hips", fwd=-.16 * k, up=-.05), rot("hips", twist=10, side=3),
        rot("spine1", pitch=-16), rot("spine2", pitch=-20, twist=-12),
        rot("neck", pitch=-8), rot("head", pitch=-30, twist=16),
        rot("upper_arm_L", pitch=-20, side=56), rot("forearm_L", pitch=-6),
        rot("upper_arm_R", pitch=-14, side=-52), rot("forearm_R", pitch=-14))
    rebound = override(ready, pos("hips", fwd=.05, up=-.03), rot("spine1", pitch=9),
        rot("spine2", pitch=11, twist=4), rot("head", pitch=9, twist=-4))
    counter = override(ready, pos("hips", fwd=-.03, up=-.01), rot("spine1", pitch=-3),
        rot("spine2", pitch=-4), rot("head", pitch=-4))
    keys = {0.0: ready, .05: impact, .1: impact, .17: rebound, .23: counter, .3: ready}
    return {"duration": .3, "keys": keys,
            "ease": {.05: "snap", .1: "linear", .17: "back", .23: "back", .3: "back"},
            "foot": None, "loop": False, "markers": {"Impact": .05}}


def planted_feet(model):
    x, fy, by = STYLE[model]["feet"]

    def feet(side, t):
        sign = 1 if side == "L" else -1
        return Vector((sign * x, fy if side == "L" else by, .085)), 0, sign * 9
    return feet


def make_actions(arm, model, library):
    """Bake every clip of `library` (name -> clip) with 60 Hz samples and solved feet."""
    arm.animation_data_create()
    scene = bpy.context.scene
    scene.render.fps = FPS
    bpy.context.view_layer.objects.active = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for name in [n for n in CLIP_ORDER if n in library]:
        clip = library[name]
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        action["loop"] = bool(clip.get("loop"))
        for key, value in clip.get("props", {}).items():
            action[key] = value
        for marker, when in clip.get("markers", {}).items():
            action.pose_markers.new(marker).frame = 1 + round(when * FPS)
        arm.animation_data.action = action
        foot = clip.get("foot", "planted")
        if foot == "planted":
            foot = planted_feet(model)
        samples = max(2, round(clip["duration"] * FPS))
        AUTO_DROP[0] = 0.0
        previous = {}
        for sample in range(samples + 1):
            t = sample / FPS if sample < samples else clip["duration"]
            full = sample_clip(clip, t)
            for pb in arm.pose.bones:
                v = full.get(pb.name, [0.] * 6)
                pb.location = v[3:]
                pb.rotation_quaternion = Euler([math.radians(a) for a in v[:3]], "XYZ").to_quaternion()
                pb.scale = (1, 1, 1)
            bpy.context.view_layer.update()
            if foot:
                solve_feet(arm, name, foot, t)
            if clip.get("grip") is not None:
                solve_grip(arm, clip["grip"])
            for pb in arm.pose.bones:
                q = pb.rotation_quaternion.copy()
                if pb.name in previous and q.dot(previous[pb.name]) < 0:
                    q.negate()
                previous[pb.name] = q.copy()
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=sample + 1, group=pb.name)
                pb.keyframe_insert("location", frame=sample + 1, group=pb.name)
        # Dense baked samples use linear interpolation: no Bezier overshoot at contacts.
        for slot in action.slots:
            for layer in action.layers:
                for strip in layer.strips:
                    bag = strip.channelbag(slot)
                    if bag:
                        for curve in bag.fcurves:
                            for key in curve.keyframe_points:
                                key.interpolation = "LINEAR"
        print("CLIP", model, name, "auto-drop %.3f" % AUTO_DROP[0])
    arm.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_start, scene.frame_end = 1, 121
    scene.frame_set(1)


AUTO_DROP = [0.0]  # largest correction (m) the solver had to make; report per clip


def solve_feet(arm, name, foot_fn, t):
    """Analytic two-bone IK; knee pole forward, sole level during ground contact.
    If a pose would pull a leg past full extension, the body is dropped just enough."""
    root = arm.pose.bones["root"]
    for _ in range(6):
        worst = 0.0
        for side in ("L", "R"):
            thigh, shin = arm.pose.bones[f"thigh_{side}"], arm.pose.bones[f"shin_{side}"]
            target = foot_fn(side, t)[0]
            reach = thigh.bone.length + shin.bone.length - .004
            worst = max(worst, (target - thigh.head).length - reach)
        if worst <= 0:
            break
        root.location[1] -= worst + .002
        AUTO_DROP[0] = max(AUTO_DROP[0], worst + .002)
        bpy.context.view_layer.update()
    else:
        raise ValueError(f"Unreachable foot: {name} t={t:.3f}")
    for side in ("L", "R"):
        thigh, shin, foot = [arm.pose.bones[f"{part}_{side}"] for part in ("thigh", "shin", "foot")]
        target, pitch, yaw = foot_fn(side, t)
        hip = thigh.head.copy()
        direction = target - hip
        d = direction.length
        a, b = thigh.bone.length, shin.bone.length
        d = max(d, abs(a - b) + .001)
        axis = direction.normalized()
        pole = Vector((0, -1, 0))
        pole = (pole - axis * pole.dot(axis)).normalized()
        along = (a * a - b * b + d * d) / (2 * d)
        knee = hip + axis * along + pole * math.sqrt(max(0, a * a - along * along))
        for pb, head, tail in ((thigh, hip, knee), (shin, knee, target)):
            rest = pb.bone.matrix_local.to_quaternion()
            swing = Vector((0, 0, -1)).rotation_difference((tail - head).normalized())
            pb.matrix = Matrix.LocRotScale(head, swing @ rest, Vector((1, 1, 1)))
            bpy.context.view_layer.update()
        turn = Quaternion((0, 0, 1), math.radians(yaw))
        tilt = Quaternion((1, 0, 0), math.radians(pitch))
        foot.matrix = Matrix.LocRotScale(target, turn @ tilt @ foot.bone.matrix_local.to_quaternion(), Vector((1, 1, 1)))
        bpy.context.view_layer.update()


def solve_grip(arm, grip):
    """Two-bone IK for the LEFT arm: put hand_L on `grip`, a point in hand_R's local frame (a two-handed weapon's
    second grip). The hand takes hand_R's orientation, as both hold the same shaft."""
    hand_r = arm.pose.bones["hand_R"]
    target = (hand_r.matrix @ Vector(grip))
    upper, fore, hand = (arm.pose.bones[n] for n in ("upper_arm_L", "forearm_L", "hand_L"))
    shoulder = upper.head.copy()
    a, b = upper.bone.length, fore.bone.length
    direction = target - shoulder
    d = min(max(direction.length, abs(a - b) + .001), a + b - .004)
    axis = direction.normalized()
    pole = Vector((.55, .25, -1.0))                       # elbow down, a little out and back
    pole = (pole - axis * pole.dot(axis)).normalized()
    along = (a * a - b * b + d * d) / (2 * d)
    elbow = shoulder + axis * along + pole * math.sqrt(max(0, a * a - along * along))
    wrist = shoulder + axis * d
    for pb, head, tail in ((upper, shoulder, elbow), (fore, elbow, wrist)):
        rest = pb.bone.matrix_local.to_quaternion()
        rest_dir = rest @ Vector((0, 1, 0))
        swing = rest_dir.rotation_difference((tail - head).normalized())
        pb.matrix = Matrix.LocRotScale(head, swing @ rest, Vector((1, 1, 1)))
        bpy.context.view_layer.update()
    hand.matrix = Matrix.LocRotScale(wrist, hand_r.matrix.to_quaternion(), Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def bouncy_idle(idle, model):
    """Overlay a springy knee-dip on the idle: sharp dip, quick rise, chest/arms/sword
    lagging behind with overshoot, like the squash and stretch of the 2D idle."""
    amount = STYLE[model]["idle_bounce"]
    duration = idle["duration"]
    beats = max(1, round(duration / .8))      # roughly a bounce every .8 s, whole number per loop
    period = duration / beats
    base = idle

    def dip(t):
        b = abs(math.sin(math.pi * t / period))
        return (1 - b) ** 2                   # 1 at the bottom of the bounce, 0 at the top

    def fn(t):
        d0, d1, d2 = dip(t), dip(t - .06), dip(t - .12)
        return add(sample_clip(base, t),
            pos("hips", up=-.045 * amount * d0),
            rot("spine1", pitch=5 * amount * d1), rot("spine2", pitch=6 * amount * d1),
            rot("head", pitch=-7 * amount * d2),
            rot("clavicle_L", pitch=-4 * amount * d1), rot("clavicle_R", pitch=-4 * amount * d1),
            rot("upper_arm_L", pitch=-9 * amount * d2), rot("upper_arm_R", pitch=-8 * amount * d2),
            rot("forearm_L", pitch=9 * amount * d2), rot("forearm_R", pitch=-10 * amount * d2),
            rot("hand_R", pitch=8 * amount * d2))
    out = dict(idle)
    out.pop("keys", None)
    out["fn"] = fn
    return out


def build_library(model):
    """Clip library for any shared-rig model: Idle/Move/Attack1-3/TakeHit/Death."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    if model in ("knight", "mannequin"):
        import knight_poses
        stance = STANCES[model]
        lib = knight_poses.clips(rot, pos, add, stance)
    else:
        import monster_poses
        lib = monster_poses.clips(model, rot, pos, add, override, amplify)
    ready = lib["ready"]
    lib["Idle"] = bouncy_idle(lib["Idle"], model)
    lib["Move"] = locomotion(model)
    lib["Walk"] = locomotion(model, walk=True)
    lib["TakeHit"] = hit_reaction(model, ready)
    lib["TakeHit"]["foot"] = "planted"
    if model in ("knight", "mannequin"):
        import weapon_poses
        lib.update(weapon_poses.clips(rot, pos, add, ready, lib["Attack1"], override))
    for name in [n for n in CLIP_ORDER if n in lib]:
        lib[name].setdefault("loop", name in LOOPING)
        if lib[name].get("feet") == "free":
            lib[name]["foot"] = None
    return lib



# ---- export ------------------------------------------------------------------
def export(objs, path, animations):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                  export_apply=False, export_materials="EXPORT", export_animations=animations)
    if animations:
        kwargs.update(export_animation_mode="ACTIONS", export_force_sampling=True,
                      export_anim_slide_to_zero=True, export_optimize_animation_size=False)
    bpy.ops.export_scene.gltf(**kwargs)
    print("WROTE", path, os.path.getsize(path), "bytes")


def record_clip_info(out_dir, model, arm):
    """Write clip timings next to the models (godot/models/clip_info.json) for the game: the Move cycle's
    ground speed in WORLD metres/s (so playback can be matched to a unit's sim speed) and every clip's length."""
    path = os.path.join(out_dir, "clip_info.json")
    data = json.load(open(path)) if os.path.exists(path) else {}
    scale = arm.scale.x
    clips = {}
    for name in CLIP_ORDER:
        if name not in bpy.data.actions:
            continue
        action = bpy.data.actions[name]
        clips[name] = {"duration": round((action.frame_range[1] - action.frame_range[0]) / FPS, 4)}
        if "ground_speed_mps" in action.keys():
            clips[name]["ground_speed_mps"] = round(action["ground_speed_mps"] * scale, 4)
    data[model] = {"scale": scale, "clips": clips}
    json.dump(data, open(path, "w"), indent=2, sort_keys=True)


def count_tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = args[0] if args else "."
    model = args[1] if len(args) > 1 else "knight"
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    arm = build_armature()
    bb = Builder()
    {"knight": build_body, "mannequin": build_mannequin_body}[model](bb)
    bb.broaden_head()
    body = make_object(model, bb, arm)
    make_actions(arm, model, build_library(model))
    print("TRIANGLES", model, count_tris(body), "bones", len(arm.data.bones))
    export([arm, body], os.path.join(out_dir, model + ".glb"), True)
    record_clip_info(out_dir, model, arm)

    if model == "knight":
        sb = Builder()
        build_sword(sb)
        sword = make_object("sword", sb)
        print("TRIANGLES sword", count_tris(sword))
        export([sword], os.path.join(out_dir, "sword.glb"), False)

        # Editable Blender preview uses the same palm offset / grip angle as Godot.
        # Bone parenting is measured from its tail (0.16m past the wrist).
        sword.parent = arm
        sword.parent_type = "BONE"
        sword.parent_bone = "hand_R"
        sword.matrix_parent_inverse = Matrix.Identity(4)
        sword.location = (0, .07 - arm.data.bones["hand_R"].length, 0)
        sword.rotation_euler = (math.radians(-130), 0, 0)
        # Director: turn the blade 90 degrees around its grip (+Z before glTF export).
        sword.rotation_euler = (sword.rotation_euler.to_matrix() @ Matrix.Rotation(math.pi / 2, 3, "Z")).to_euler()

    arm.animation_data.action = bpy.data.actions["Idle"]
    arm.show_in_front = True
    arm.data.display_type = "STICK"
    bpy.context.scene.frame_set(1)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_distance = 3.4
                area.spaces.active.region_3d.view_location = (0, 0, 1)
                area.spaces.active.region_3d.view_rotation = Euler((math.radians(78), 0, math.radians(20))).to_quaternion()
                area.spaces.active.shading.type = "MATERIAL"

    # the .blend lives next to the script, NOT in the Godot project (Godot would try to import it)
    blend = os.path.join(os.path.dirname(os.path.abspath(__file__)), model + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("BUILD_OK", model)


if __name__ == "__main__":
    main()
