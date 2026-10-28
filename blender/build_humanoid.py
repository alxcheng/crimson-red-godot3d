"""build_humanoid.py - builds the test models for Crimson Red 3D (knight, mannequin).

OSRS-style low poly: flat-shaded, faceted, tapered limbs (no boxes), diamond eyes.
Colours and stance copy the 2D Knight sprite (navy tabard, black sleeves/legs, grey armour).
One mesh, one ~30 bone skeleton, five animations named after the 2D game's animation set
(Idle, Move, Attack1, TakeHit, Death) and a separate sword prop, exported as .glb for Godot.

Run (headless):
    blender --background --python build_humanoid.py -- <output_dir> [knight|mannequin]

Conventions (every future model must follow these so animations and gear are interchangeable):
  * Blender is Z-up. The character faces -Y (glTF export turns that into Godot's +Z, "forward").
    The character's left side is +X.
  * Bone names use underscores (upper_arm_L), not dots: Godot node names dislike dots.
  * Every bone points straight up or down at rest. The helpers `rot()` and `pos()` turn
    "pitch forward / twist left / lean left" and "left / up / forward" into the right Euler
    and location values for either kind of bone, so animation code never thinks about axes.
  * Props (weapons) have their origin at the grip and the blade along +Z.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, Quaternion, Euler

FPS = 60  # [tuned] bake foot contacts at 60Hz; pose timing below is authored at 30Hz.
SQ2 = math.sqrt(2.0)

# ---- skeleton ----------------------------------------------------------------
# name: (parent, head (x, y, z), tail (x, y, z))
BONES = {
    "root":    (None,     (0, 0, 0),      (0, 0, 0.20)),
    "hips":    ("root",   (0, 0, 0.90),   (0, 0, 1.04)),
    "spine1":  ("hips",   (0, 0, 1.04),   (0, 0, 1.26)),
    "spine2":  ("spine1", (0, 0, 1.26),   (0, 0, 1.48)),
    "neck":    ("spine2", (0, 0, 1.48),   (0, 0, 1.62)),
    "head":    ("neck",   (0, 0, 1.62),   (0, 0, 1.88)),
    "hair_back": ("head", (0, 0.085, 1.80), (0, 0.095, 1.62)),
}
for _s, _x in (("L", 1), ("R", -1)):
    BONES.update({
        f"clavicle_{_s}":  ("spine2", (_x * 0.06, 0, 1.44), (_x * 0.06, 0, 1.50)),
        f"upper_arm_{_s}": (f"clavicle_{_s}", (_x * 0.27, 0, 1.45), (_x * 0.27, 0, 1.15)),
        f"forearm_{_s}":   (f"upper_arm_{_s}", (_x * 0.27, 0, 1.15), (_x * 0.27, 0, 0.88)),
        f"hand_{_s}":      (f"forearm_{_s}", (_x * 0.27, 0, 0.88), (_x * 0.27, 0, 0.72)),
        f"thigh_{_s}":     ("hips", (_x * 0.10, 0, 0.90), (_x * 0.10, 0, 0.50)),
        f"shin_{_s}":      (f"thigh_{_s}", (_x * 0.10, 0, 0.50), (_x * 0.10, 0, 0.085)),
        f"foot_{_s}":      (f"shin_{_s}", (_x * 0.10, 0, 0.085), (_x * 0.10, 0, 0.03)),
        f"toe_{_s}":       (f"foot_{_s}", (_x * 0.10, -0.10, 0.05), (_x * 0.10, -0.10, 0.0)),
    })
for _i, (_z0, _z1) in enumerate(((1.02, 0.88), (0.88, 0.74), (0.74, 0.58)), start=1):
    BONES[f"tab_f{_i}"] = ("hips" if _i == 1 else f"tab_f{_i - 1}", (0, -0.12, _z0), (0, -0.12, _z1))
    BONES[f"tab_b{_i}"] = ("hips" if _i == 1 else f"tab_b{_i - 1}", (0, 0.12, _z0), (0, 0.12, _z1))


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
        for bone in ("head", "hair_back"):
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
        b.loft(f"tab_f{i}", "navy", [(0, -.12, z0, .16 - .012 * i, .012), (0, -.12, z1, .16 - .012 * (i + 1), .012)], box=True)
        b.loft(f"tab_b{i}", "navy2", [(0, .12, z0, .16 - .012 * i, .012), (0, .12, z1, .16 - .012 * (i + 1), .012)], box=True)
    # neck, small head, face, hair
    b.loft("neck", "skin", [(0, 0, 1.50, .06, .06), (0, 0, 1.64, .05, .052)], 6)
    b.loft("head", "skin", [(0, 0, 1.60, .05, .055), (0, -.005, 1.66, .075, .085), (0, -.005, 1.75, .085, .095),
                            (0, 0, 1.82, .07, .08), (0, 0, 1.86, .035, .045)], 8)
    b.loft("head", "skin", [(0, -.088, 1.70, .02, .028), (0, -.13, 1.69, .007, .011)], 4, axis="Y")            # nose
    for x in (.036, -.036):
        b.loft("head", "eye", [(x, -.097, 1.745, .02, .01), (x, -.101, 1.745, .02, .01)], 4, axis="Y")        # diamond eyes
    b.loft("head", "hair", [(0, .02, 1.72, .092, .102), (0, .02, 1.80, .098, .108), (0, .015, 1.87, .072, .082), (0, .01, 1.915, .03, .04)], 8)
    b.loft("hair_back", "hair", [(0, .085, 1.82, .065, .036), (0, .095, 1.72, .052, .032), (0, .10, 1.62, .03, .022)], 6)
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
    return {bone: [0, 0, 0, left, up, fwd]}


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
    rot("tab_f1", pitch=6), rot("tab_b1", pitch=-6),
)
STANCES = {"knight": STANCE, "mannequin": STANCE_MANNEQUIN}


def cloth(phi, amp, lead=0.0, base_f=0.0, base_b=0.0):
    """Small overlapping movement, with a delay along the cloth and hair chain."""
    out = {}
    for i in (1, 2, 3):
        out = add(out,
                  rot(f"tab_f{i}", pitch=base_f + amp * math.sin(phi - .55 * i - lead)),
                  rot(f"tab_b{i}", pitch=base_b + amp * math.sin(phi - .55 * i - lead - .4)))
    return add(out, rot("hair_back", pitch=amp * .65 * math.sin(phi - 1.1 - lead)))


def idle_pose(phi, stance):
    # Four-second breath with a slower, asymmetric transfer of weight. Counter-rotate
    # the chest/head so the character stays attentive rather than swaying as one rod.
    s = math.sin
    return add(stance,
        pos("hips", up=.004 * s(2 * phi), left=.013 * s(phi)),
        rot("hips", side=1.1 * s(phi), twist=1.3 * s(phi)),
        rot("spine1", side=-1.0 * s(phi), pitch=.6 * s(2 * phi)),
        rot("spine2", pitch=.9 * s(2 * phi - .4), twist=-1.3 * s(phi)),
        rot("clavicle_L", pitch=.7 * s(2 * phi - .4)),
        rot("clavicle_R", pitch=.7 * s(2 * phi - .6)),
        rot("head", pitch=-.8 * s(2 * phi - .6), twist=2 * s(phi - .5)),
        rot("upper_arm_L", pitch=1.8 * s(2 * phi - .8), side=.7 * s(phi)),
        rot("upper_arm_R", pitch=1.2 * s(2 * phi - 1.0)),
        rot("forearm_L", pitch=1.3 * s(2 * phi - 1.1)),
        rot("forearm_R", pitch=1.0 * s(2 * phi - 1.2)),
        cloth(phi, .7),
    )


def move_pose(phi, model):
    s, c = math.sin, math.cos
    # Independent absolute locomotion pose; never add the bent combat stance again.
    p = add(pos("hips", up=-.058 - .012 * c(2 * phi), left=.016 * s(phi)),
        rot("hips", twist=5 * c(phi), side=1.6 * s(phi)),
        rot("spine1", pitch=5, side=-1.5 * s(phi)),
        rot("spine2", pitch=3, twist=-8 * c(phi)),
        rot("head", pitch=-7, twist=3 * c(phi)),
        cloth(phi, 2.5, base_f=4, base_b=-5))
    for side, sign in (("L", 1), ("R", -1)):
        swing = sign * c(phi)
        if model == "knight" and side == "R":
            p = add(p, rot("upper_arm_R", pitch=29 - 8 * swing, side=-15),
                    rot("forearm_R", pitch=48 + 4 * swing), rot("hand_R", pitch=2))
        else:
            p = add(p, rot(f"upper_arm_{side}", pitch=5 - 24 * swing, side=sign * 10),
                    rot(f"forearm_{side}", pitch=26 - 9 * swing),
                    rot(f"hand_{side}", pitch=-5))
    return p


# Attack deltas on the ready pose: anticipation, short acceleration, a readable
# contact at frame 13, follow-through, then recovery. No additive 200-degree elbows.
ATTACK = {
    1: {},
    6: add(pos("hips", fwd=-.055, up=-.015, left=-.018), rot("hips", twist=-12),
        rot("spine2", twist=-14, pitch=-4), rot("head", twist=20, pitch=3),
        rot("upper_arm_R", pitch=45, side=-8), rot("forearm_R", pitch=-10),
        rot("upper_arm_L", pitch=10, side=6), cloth(0, 0, base_f=-2, base_b=2)),
    10: add(pos("hips", fwd=-.065, up=-.025, left=-.026), rot("hips", twist=-18),
        rot("spine1", twist=-7), rot("spine2", twist=-20, pitch=-7),
        rot("head", twist=32, pitch=7), rot("upper_arm_R", pitch=108, side=-16),
        rot("forearm_R", pitch=-18), rot("hand_R", pitch=-15),
        rot("upper_arm_L", pitch=18, side=10), rot("forearm_L", pitch=10),
        cloth(0, 0, base_f=-3, base_b=3)),
    13: add(pos("hips", fwd=.075, up=-.035, left=.015), rot("hips", twist=18),
        rot("spine1", twist=6, pitch=4), rot("spine2", twist=18, pitch=9),
        rot("head", twist=-27, pitch=-8), rot("upper_arm_R", pitch=52, side=24),
        rot("forearm_R", pitch=-30), rot("hand_R", pitch=-52),
        rot("upper_arm_L", pitch=-15, side=12),
        cloth(0, 0, base_f=7, base_b=-9)),
    17: add(pos("hips", fwd=.09, up=-.025, left=.028), rot("hips", twist=23),
        rot("spine1", twist=7, pitch=4), rot("spine2", twist=21, pitch=9),
        rot("head", twist=-32, pitch=-8), rot("upper_arm_R", pitch=16, side=37),
        rot("forearm_R", pitch=-16), rot("hand_R", pitch=-42),
        rot("upper_arm_L", pitch=-18, side=14),
        cloth(0, 0, base_f=4, base_b=-6)),
    24: add(pos("hips", fwd=.025, up=-.012), rot("hips", twist=5),
        rot("spine2", twist=7, pitch=2), rot("upper_arm_R", pitch=3, side=12),
        rot("forearm_R", pitch=-6), cloth(0, 0, base_f=-2, base_b=2)),
    34: {},
}

ANIMS = {
    "TakeHit": (False, {
        1: {},
        # impact: head snaps, chest caves, arms fling out
        4: add(pos("hips", fwd=-0.12, up=-0.02), rot("hips", twist=8), rot("spine1", pitch=-14),
               rot("spine2", pitch=-18, twist=-10), rot("head", pitch=-24, twist=12),
               rot("upper_arm_L", pitch=-18, side=52), rot("forearm_L", pitch=-10),
               rot("upper_arm_R", pitch=-10, side=-46), rot("forearm_R", pitch=-20),
               rot("thigh_L", pitch=-12), rot("thigh_R", pitch=8), cloth(0, 0, base_f=20, base_b=26)),
        # rebound past neutral
        9: add(pos("hips", fwd=0.03), rot("spine1", pitch=5), rot("spine2", pitch=7, twist=3),
               rot("head", pitch=6), cloth(0, 0, base_f=-8, base_b=-12)),
        16: {},
    }),
    "Death": (False, {
        1: {},
        # hit and stagger
        6: add(pos("hips", fwd=-0.10, up=-0.04), rot("spine1", pitch=-10), rot("spine2", pitch=-14),
               rot("head", pitch=-20, twist=10), rot("upper_arm_L", pitch=-20, side=50),
               rot("upper_arm_R", pitch=-8, side=-48), rot("forearm_R", pitch=-30), rot("hand_R", pitch=-40)),
        # knees give way, head drops
        16: add(pos("hips", fwd=-0.12, up=-0.30), rot("spine1", pitch=12), rot("spine2", pitch=14),
                rot("head", pitch=18, twist=-8), rot("thigh_L", pitch=70), rot("shin_L", pitch=-100),
                rot("thigh_R", pitch=52), rot("shin_R", pitch=-104), rot("foot_L", pitch=-20), rot("foot_R", pitch=-20),
                rot("upper_arm_L", pitch=-10, side=44), rot("upper_arm_R", pitch=-6, side=-40), rot("forearm_R", pitch=-6),
                cloth(0, 0, base_f=12, base_b=-22)),
        # topple backward
        30: add(rot("root", pitch=-62), pos("root", up=0.04), pos("hips", up=-0.26), rot("spine1", pitch=6),
                rot("head", pitch=10), rot("thigh_L", pitch=40), rot("shin_L", pitch=-60),
                rot("thigh_R", pitch=30), rot("shin_R", pitch=-70),
                rot("upper_arm_L", pitch=-30, side=60), rot("upper_arm_R", pitch=-20, side=-62), rot("forearm_R", pitch=-14),
                cloth(0, 0, base_f=22, base_b=10)),
        # lie flat, limbs settle
        40: add(rot("root", pitch=-88), pos("root", up=0.12), pos("hips", up=-0.06), rot("head", pitch=-6, twist=12),
                rot("thigh_L", pitch=12), rot("shin_L", pitch=-20), rot("thigh_R", pitch=6, side=-8), rot("shin_R", pitch=-14),
                rot("upper_arm_L", pitch=-10, side=64), rot("upper_arm_R", pitch=-14, side=-62), rot("forearm_R", pitch=-8),
                cloth(0, 0, base_f=18, base_b=8)),
    }),
}


def interpolate(keys, frame):
    frames = sorted(keys)
    if frame >= frames[-1]:
        return keys[frames[-1]]
    for a, b in zip(frames, frames[1:]):
        if a <= frame <= b:
            t = (frame - a) / (b - a)
            # Ease anticipation/recovery; the short strike segment retains momentum.
            if (a, b) != (10, 13):
                t = t * t * (3 - 2 * t)
            return {bone: [va * (1 - t) + vb * t for va, vb in
                    zip(keys[a].get(bone, [0.] * 6), keys[b].get(bone, [0.] * 6))]
                    for bone in keys[a].keys() | keys[b].keys()}
    return keys[frames[0]]


def foot_target(side, name, frame):
    sign = 1 if side == "L" else -1
    if name == "Move":
        # 60% planted stance, 40% swing. Ground speed = .42 / (.6 * 1.0) = .7 m/s.
        # Contact moves back at constant speed relative to the character's root.
        t = ((frame - 1) / 30 + (0 if side == "L" else .5)) % 1
        if t < .6:
            y, z, pitch = -.21 + .42 * t / .6, .085, 0
        else:
            u = (t - .6) / .4
            ease = u * u * (3 - 2 * u)
            y = .21 - .42 * ease
            z = .085 + .12 * math.sin(math.pi * u) ** 2
            pitch = -16 * math.sin(math.pi * u)
        return Vector((sign * .145, y, z)), pitch, sign * 4
    # Same foot positions for ready, breathing and the planted sword strike.
    return Vector((sign * .215, -.08 if side == "L" else .07, .085)), 0, sign * 9


def solve_feet(arm, name, frame):
    """Analytic two-bone IK; knee pole forward, sole level during ground contact."""
    for side in ("L", "R"):
        thigh, shin, foot = [arm.pose.bones[f"{part}_{side}"] for part in ("thigh", "shin", "foot")]
        target, pitch, yaw = foot_target(side, name, frame)
        hip = thigh.head.copy()
        direction = target - hip
        d = direction.length
        a, b = thigh.bone.length, shin.bone.length
        if not abs(a - b) + .001 < d < a + b - .001:
            raise ValueError(f"Unreachable foot: {name} frame {frame} {side}: {d}")
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


def make_actions(arm, model):
    arm.animation_data_create()
    scene = bpy.context.scene
    scene.render.fps = FPS
    stance = STANCES[model]
    bpy.context.view_layer.objects.active = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    lengths = {"Idle": 121, "Move": 31, "Attack1": 34, "TakeHit": 16, "Death": 40}
    for name, last in lengths.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        action["loop"] = name in ("Idle", "Move")
        if name == "Attack1":
            action.pose_markers.new("Anticipation").frame = 19
            action.pose_markers.new("Contact").frame = 25
            action.pose_markers.new("Follow through").frame = 33
        if name == "Move":
            action["ground_speed_mps"] = .7
        arm.animation_data.action = action
        previous = {}
        for sample in range((last - 1) * 2 + 1):
            frame = 1 + sample / 2
            baked_frame = sample + 1
            if name == "Idle":
                full = idle_pose(2 * math.pi * (frame - 1) / 120, stance)
            elif name == "Move":
                full = move_pose(2 * math.pi * (frame - 1) / 30, model)
            elif name == "Attack1":
                # Same intentional sword swing on both bodies, independent of idle arm angles.
                full = add(STANCE, interpolate(ATTACK, frame))
            else:
                full = add(stance, interpolate(ANIMS[name][1], frame))
            for pb in arm.pose.bones:
                v = full.get(pb.name, [0.] * 6)
                pb.location = v[3:]
                pb.rotation_quaternion = Euler([math.radians(a) for a in v[:3]], "XYZ").to_quaternion()
                pb.scale = (1, 1, 1)
            bpy.context.view_layer.update()
            if name in ("Idle", "Move", "Attack1", "TakeHit"):
                solve_feet(arm, name, frame)
            for pb in arm.pose.bones:
                q = pb.rotation_quaternion.copy()
                if pb.name in previous and q.dot(previous[pb.name]) < 0:
                    q.negate()
                previous[pb.name] = q.copy()
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=baked_frame, group=pb.name)
                pb.keyframe_insert("location", frame=baked_frame, group=pb.name)
        # Dense baked samples use linear interpolation: no Bezier overshoot at contacts.
        for slot in action.slots:
            for layer in action.layers:
                for strip in layer.strips:
                    bag = strip.channelbag(slot)
                    if bag:
                        for curve in bag.fcurves:
                            for key in curve.keyframe_points:
                                key.interpolation = "LINEAR"
    arm.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_start, scene.frame_end = 1, 241
    scene.frame_set(1)


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
    make_actions(arm, model)
    print("TRIANGLES", model, count_tris(body), "bones", len(arm.data.bones))
    export([arm, body], os.path.join(out_dir, model + ".glb"), True)

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
