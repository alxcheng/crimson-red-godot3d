"""Weapon-handling clips for the shared 24-bone rig: two-handed melee (TwoHandIdle, TwoHandAttack), a caster raising a
staff (StaffRaise) and the off-hand strike of a dual wielder (OffhandAttack). Pure pose data like knight_poses.py.

Authoring notes (all angles and timings are CR-original art direction [tuned]; punchy like the Knight's attacks:
anticipation pushed 1.3-1.4x past the pose, contact eased with "back" overshoot, a held follow-through):
  * `grip` on a clip is a point in the RIGHT HAND bone's local frame where the LEFT hand should hold the weapon; the
    builder solves the left arm to it each sample (two-bone IK, see build_humanoid.solve_grip).
  * OffhandAttack is the Attack1 slash mirrored left/right, so a dual wielder cycles Attack1 (main) -> OffhandAttack.
"""
import math

# Where the left hand holds a two-hander, in hand_R's local frame (x along the shaft: the weapon's blade points +x,
# y along the hand). [tuned] by eye against sword_long.
TWO_HAND_GRIP = (-0.20, 0.06, 0.0)


def mirror_pose(p):
    """Left/right mirror of a full pose: swap L/R bones, negate yaw/roll and the sideways offset."""
    out = {}
    for bone, v in p.items():
        if bone.endswith("_L"):
            nb = bone[:-2] + "_R"
        elif bone.endswith("_R"):
            nb = bone[:-2] + "_L"
        else:
            nb = bone
        out[nb] = [v[0], -v[1], -v[2], -v[3], v[4], v[5]]
    return out


def clips(rot, pos, add, ready, attack1, override):
    def pose(base, *parts):
        r = {bone: list(v) for bone, v in base.items()}
        r.update(add(*parts))
        return r

    def punch(p, k):
        return {bone: [y + (x - y) * k for x, y in zip(p.get(bone, [0.] * 6), ready.get(bone, [0.] * 6))]
                for bone in p.keys() | ready.keys()}

    # ------------------------------------------------------------------------------ two-handed melee
    th_ready = pose(ready,
        pos("hips", up=-.10, fwd=.01), rot("hips", twist=-6),
        rot("spine1", pitch=5), rot("spine2", pitch=4, twist=4), rot("head", pitch=-6),
        rot("upper_arm_R", pitch=40, side=-6), rot("forearm_R", pitch=68), rot("hand_R", pitch=-24),
        rot("upper_arm_L", pitch=36, side=14), rot("forearm_L", pitch=64),
    )
    idle_period = 0.9
    idle_keys = {}
    for i in range(9):
        ph = 2 * math.pi * i / 8
        idle_keys[i * idle_period / 8] = add(th_ready,
            pos("hips", up=.014 * math.sin(ph), left=.012 * math.cos(ph)),
            rot("spine2", pitch=2.5 * math.sin(ph - .5), twist=-2 * math.cos(ph)),
            rot("upper_arm_R", pitch=3 * math.sin(ph - .8)),
            rot("forearm_R", pitch=4 * math.sin(ph - 1.0)))

    wind = pose(th_ready,
        pos("hips", up=-.09, fwd=-.045), rot("hips", twist=-20),
        rot("spine1", pitch=-4, twist=-6), rot("spine2", pitch=-8, twist=-16), rot("head", pitch=-12, twist=16),
        rot("upper_arm_R", pitch=152, side=-12), rot("forearm_R", pitch=78), rot("hand_R", pitch=-44),
        rot("upper_arm_L", pitch=120, side=16), rot("forearm_L", pitch=60),
    )
    hit = pose(th_ready,
        pos("hips", up=-.15, fwd=.10, left=.02), rot("hips", twist=14),
        rot("spine1", pitch=14, twist=5), rot("spine2", pitch=18, twist=14), rot("head", pitch=-17, twist=-12),
        rot("upper_arm_R", pitch=56, side=10), rot("forearm_R", pitch=20), rot("hand_R", pitch=-30),
        rot("upper_arm_L", pitch=52, side=14), rot("forearm_L", pitch=26),
    )
    follow = pose(hit,
        pos("hips", up=-.185, fwd=.115, left=.022),
        rot("spine1", pitch=19), rot("spine2", pitch=23, twist=12), rot("head", pitch=-20),
        rot("upper_arm_R", pitch=36, side=12), rot("forearm_R", pitch=26), rot("hand_R", pitch=-22),
    )
    a = 0.18
    atk_keys = {
        0.0: th_ready,
        a: punch(wind, 1.35),          # big backswing: the weapon goes up and behind the head
        a + .13: punch(hit, 1.3),      # contact
        a + .24: punch(follow, 1.25),
        a + .42: punch(follow, 1.2),
        a + .64: th_ready,
    }
    atk_ease = {a: "in", a + .13: "back", a + .24: "out", a + .42: "linear", a + .64: "smooth"}
    two_hand_attack = {"duration": a + .64, "keys": atk_keys, "ease": atk_ease,
                       "markers": {"Contact": a + .13, "Follow through": a + .24}, "feet": "planted",
                       "loop": False, "grip": TWO_HAND_GRIP,
                       "note": "[tuned] overhead chop, both hands; contact at 0.31 s"}
    two_hand_idle = {"duration": idle_period, "keys": idle_keys, "ease": {}, "markers": {}, "feet": "planted",
                     "loop": True, "grip": TWO_HAND_GRIP, "note": "[tuned] two-hander guard"}

    # ------------------------------------------------------------------------------ caster raises a staff
    held = pose(ready,
        pos("hips", up=-.07), rot("hips", twist=-4),
        rot("upper_arm_R", pitch=10, side=-8), rot("forearm_R", pitch=40), rot("hand_R", pitch=-16),
        rot("upper_arm_L", pitch=8, side=22), rot("forearm_L", pitch=24),
    )
    crouch = pose(held,
        pos("hips", up=-.15, fwd=-.03), rot("hips", twist=-10),
        rot("spine1", pitch=9), rot("spine2", pitch=9, twist=-6), rot("head", pitch=-2),
        rot("upper_arm_R", pitch=-22, side=-14), rot("forearm_R", pitch=48), rot("hand_R", pitch=-20),
        rot("upper_arm_L", pitch=-18, side=34), rot("forearm_L", pitch=30),
    )
    raised = pose(held,
        pos("hips", up=.02, fwd=.015), rot("hips", twist=6),
        rot("spine1", pitch=-9), rot("spine2", pitch=-12, twist=4), rot("neck", pitch=-8), rot("head", pitch=-22),
        rot("clavicle_R", pitch=8), rot("clavicle_L", pitch=8),
        rot("upper_arm_R", pitch=172, side=-10), rot("forearm_R", pitch=12), rot("hand_R", pitch=-8, side=38),
        rot("upper_arm_L", pitch=96, side=52), rot("forearm_L", pitch=22), rot("hand_L", pitch=-12),
    )
    quiver = pose(raised, rot("spine2", pitch=-14, twist=-2), rot("head", pitch=-25),
                  rot("upper_arm_R", pitch=176, side=-9), rot("upper_arm_L", pitch=102, side=56))
    staff_dur = 1.3
    staff_keys = {
        0.0: held,
        .24: punch(crouch, 1.3),       # draw the staff back and gather
        .50: punch(raised, 1.12),       # thrust it skyward: the cast
        .72: quiver,
        .92: raised,
        1.3: held,
    }
    staff_ease = {.24: "smooth", .50: "back", .72: "smooth", .92: "smooth", 1.3: "smooth"}
    staff_raise = {"duration": staff_dur, "keys": staff_keys, "ease": staff_ease,
                   "markers": {"Cast": .50}, "feet": "planted", "loop": False,
                   "note": "[tuned] caster raises the staff overhead; the cast lands at 0.50 s"}

    # ------------------------------------------------------------------------------ StaffCast: the quick auto-attack cast
    cast_back = pose(held,
        pos("hips", up=-.12, fwd=-.03), rot("hips", twist=-10),
        rot("spine1", pitch=6), rot("spine2", pitch=6, twist=-8), rot("head", pitch=-3),
        rot("upper_arm_R", pitch=-10, side=-12), rot("forearm_R", pitch=56), rot("hand_R", pitch=-14, side=20),
        rot("upper_arm_L", pitch=-12, side=30), rot("forearm_L", pitch=28))
    cast_out = pose(held,
        pos("hips", up=-.06, fwd=.05), rot("hips", twist=8),
        rot("spine1", pitch=-2), rot("spine2", pitch=-4, twist=5), rot("head", pitch=-12),
        rot("upper_arm_R", pitch=104, side=-8), rot("forearm_R", pitch=6), rot("hand_R", pitch=-20, side=38),
        rot("upper_arm_L", pitch=70, side=40), rot("forearm_L", pitch=22), rot("hand_L", pitch=-12))
    staff_cast = {"duration": .8, "keys": {0.0: held, .2: punch(cast_back, 1.25), .4: punch(cast_out, 1.12), .5: cast_out, .8: held},
                  "ease": {.2: "smooth", .4: "back", .5: "linear", .8: "smooth"},
                  "markers": {"Cast": .4}, "feet": "planted", "loop": False,
                  "note": "[tuned] fast staff thrust for a ranged auto attack (the wizard's fireball leaves at 0.40 s, like WizardAutoFireball.delay)"}

    # ------------------------------------------------------------------------------ off-hand attack: Attack1 mirrored
    lead = 0.06
    off_keys = {0.0: ready}
    off_ease = {}
    a_keys, a_ease = attack1["keys"], attack1["ease"]
    times = sorted(a_keys)
    for t in times[:-1]:                       # the last key is `ready` again: it is replaced by the real ready
        off_keys[t + lead] = mirror_pose(a_keys[t])
        off_ease[t + lead] = a_ease.get(t, "smooth")
    off_ease[lead] = "smooth"
    end = attack1["duration"] + lead
    off_keys[end] = ready
    off_ease[end] = "smooth"
    offhand = {"duration": end, "keys": off_keys, "ease": off_ease,
               "markers": {k: v + lead for k, v in attack1["markers"].items()}, "feet": "planted", "loop": False,
               "note": "Attack1 mirrored: the off-hand strike of a dual wielder"}
    return {"TwoHandIdle": two_hand_idle, "TwoHandAttack": two_hand_attack, "StaffRaise": staff_raise,
            "StaffCast": staff_cast, "OffhandAttack": offhand}
