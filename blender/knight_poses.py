"""Knight poses traced from the project's original 135px sprite cels.

Visual sources: main-game/assets/characters/Knight/base/{Idle,Attack1,Attack2,
Attack3,Death}.png. Cell counts come from the images/data/sprites.lua; playback
rates come from data/classes.lua. Attack3 is not wired into the 2D animation set,
so its 7/60 second cel duration is explicitly [tuned], matching Attack1.

The module is pure pose data, independent of bpy. Call clips(rot, pos, add, stance).
Each returned key is a FULL pose; feet are solved by the shared rig builder for
planted clips. Times are seconds, starting at zero. Extra in-between keys describe
motion hidden by the sprite's painted slash arc; they do not change cel timings.
All 3D joint angles, pose offsets, and arc interpolation are art direction [tuned].
"""
import math


SPRITE_ROOT = "main-game/assets/characters/Knight/base/"


WRIST = (62, -45)  # [tuned] elbow / wrist at impact, so the blade is not in line with the forearm


def clips(rot, pos, add, stance):
    def override(base, *parts):
        out = {bone: list(v) for bone, v in base.items()}
        out.update(add(*parts))
        return out

    def pose(base, *parts):
        result = {bone: list(values) for bone, values in base.items()}
        # Absolute replacement avoids accumulating a combat stance a second time.
        result.update(add(*parts))
        return result

    def punch(p, k):
        """Push a pose k times further from `ready` (anticipation / follow-through)."""
        return {bone: [y + (x - y) * k for x, y in zip(p.get(bone, [0.] * 6), ready.get(bone, [0.] * 6))]
                for bone in p.keys() | ready.keys()}

    ready = pose(stance,
        pos("hips", up=-.080, left=.008), rot("hips", twist=-10),
        rot("spine1", pitch=4), rot("spine2", pitch=3, twist=8),
        rot("neck", pitch=-2), rot("head", pitch=-5, twist=2),
        rot("upper_arm_R", pitch=18, side=-15),
        rot("forearm_R", pitch=28), rot("hand_R", pitch=-46),
        rot("upper_arm_L", pitch=6, side=23),
        rot("forearm_L", pitch=20), rot("hand_L", pitch=-7),
    )

    # Idle.png: low diagonal guard, wide bent legs, small chest/shoulder breathing.
    idle_rate = 10 / 60
    idle_keys = {}
    for cell in range(11):
        phase = 2 * math.pi * cell / 10
        sn, cs = math.sin(phase), math.cos(phase)
        idle_keys[cell * idle_rate] = add(ready,
            pos("hips", up=.016 * sn, left=.022 * cs, fwd=.008 * sn),
            rot("hips", twist=3.0 * cs, side=2.2 * sn),
            rot("spine1", pitch=2.4 * sn, side=-2.0 * cs),
            rot("spine2", pitch=3.0 * math.sin(phase - .5), twist=-3.5 * cs),
            rot("clavicle_L", pitch=2.0 * math.sin(phase - .4)),
            rot("clavicle_R", pitch=2.0 * math.sin(phase - .6)),
            rot("head", pitch=-2.8 * math.sin(phase - .6), twist=3.5 * math.sin(phase - 1.2)),
            rot("upper_arm_L", pitch=4.5 * math.sin(phase - .8), side=2.5 * sn),
            rot("upper_arm_R", pitch=5.0 * math.sin(phase - .9), side=-2.0 * sn),
            rot("forearm_R", pitch=6.0 * math.sin(phase - 1.1)),
            rot("hand_R", pitch=5.0 * math.sin(phase - 1.4)),
            rot("forearm_L", pitch=4.0 * math.sin(phase - 1.0)),
        )

    # Both first cels of Attack1 hold a fully extended backswing. The painted
    # third-cel arc crosses the target, then ends in a low forward lean.
    back = pose(ready,
        pos("hips", up=-.075, fwd=-.025, left=-.012),
        rot("hips", twist=-23), rot("spine1", pitch=2, twist=-6),
        rot("spine2", pitch=1, twist=-16), rot("head", pitch=-3, twist=38),
        rot("upper_arm_R", pitch=-80, side=-22),
        rot("forearm_R", pitch=20), rot("hand_R", pitch=-70),
        rot("upper_arm_L", pitch=15, side=34), rot("forearm_L", pitch=17),
    )
    across = pose(ready,
        pos("hips", up=-.12, fwd=.055, left=.015),
        rot("hips", twist=17), rot("spine1", pitch=9, twist=6),
        rot("spine2", pitch=12, twist=23), rot("head", pitch=-11, twist=-35),
        rot("upper_arm_R", pitch=82, side=46),
        rot("forearm_R", pitch=16), rot("hand_R", pitch=-60),
        rot("upper_arm_L", pitch=-14, side=34), rot("forearm_L", pitch=24),
    )
    low = pose(ready,
        pos("hips", up=-.125, fwd=.075, left=.02),
        rot("hips", twist=22), rot("spine1", pitch=10, twist=6),
        rot("spine2", pitch=13, twist=22), rot("head", pitch=-15, twist=-38),
        rot("upper_arm_R", pitch=53, side=34),
        rot("forearm_R", pitch=24), rot("hand_R", pitch=-46),
        rot("upper_arm_L", pitch=-17, side=30), rot("forearm_L", pitch=28),
    )
    attack1_rate = 7 / 60
    r1 = attack1_rate
    def bent(p, elbow=WRIST[0], wrist=WRIST[1]):
        """Keep the sword arm bent and the wrist cocked at impact, never a rigid rod."""
        return override(p, rot("forearm_R", pitch=elbow), rot("hand_R", pitch=wrist))

    pull = punch(back, 1.35)
    hit_across = bent(punch(across, 1.3))
    through = bent(punch(low, 1.3))
    attack1_keys = {
        0.0: back,
        r1: pull,                  # coil: the blade is dragged back and the body loads
        2 * r1: hit_across,        # contact (matches the 2D hit frame)
        3 * r1: through,
        4 * r1: through,
        4 * r1 + .16: ready,
    }
    attack1_ease = {r1: "in", 2 * r1: "back", 3 * r1: "out", 4 * r1: "linear", 4 * r1 + .16: "smooth"}

    # Attack2.png is the reverse cut. It starts at the low/front Attack1 finish,
    # sweeps back across the torso, and ends with the blade extended behind.
    reverse_contact = pose(ready,
        pos("hips", up=-.095, fwd=.015),
        rot("hips", twist=-2), rot("spine1", pitch=5, twist=-4),
        rot("spine2", pitch=3, twist=-10), rot("head", pitch=-5, twist=14),
        rot("upper_arm_R", pitch=85, side=-42),
        rot("forearm_R", pitch=14), rot("hand_R", pitch=-30),
        rot("upper_arm_L", pitch=11, side=34), rot("forearm_L", pitch=21),
    )
    attack2_rate = 13 / 60
    r2 = attack2_rate
    reverse_hit = bent(punch(reverse_contact, 1.3))
    reverse_through = punch(back, 1.3)
    attack2_keys = {
        0.0: low,
        r2: punch(low, 1.15),
        2 * r2: reverse_hit,
        3 * r2: reverse_through,
        4 * r2: reverse_through,
        4 * r2 + .2: ready,
    }
    attack2_ease = {r2: "smooth", 2 * r2: "back", 3 * r2: "out", 4 * r2: "linear", 4 * r2 + .2: "smooth"}

    # Attack3.png: dip the blade behind, rise to load the swing, then a strong
    # overhead-to-ground diagonal. The overhead in-between is hidden by its arc.
    dip = pose(back,
        pos("hips", up=-.095, fwd=-.035),
        rot("upper_arm_R", pitch=-61, side=-24),
        rot("forearm_R", pitch=23), rot("hand_R", pitch=-65),
        rot("head", pitch=-4, twist=39),
    )
    rise = pose(dip,
        pos("hips", up=-.025, fwd=-.02),
        rot("spine1", pitch=-2, twist=-5), rot("spine2", pitch=-3, twist=-17),
        rot("upper_arm_R", pitch=-62, side=-21),
        rot("forearm_R", pitch=26), rot("hand_R", pitch=-62),
    )
    overhead = pose(rise,
        pos("hips", up=-.04, fwd=.005),
        rot("hips", twist=-6), rot("spine1", pitch=-2, twist=2),
        rot("spine2", pitch=-3, twist=5), rot("head", pitch=-3, twist=1),
        rot("upper_arm_R", pitch=131, side=-10),
        rot("forearm_R", pitch=28), rot("hand_R", pitch=-14),
        rot("upper_arm_L", pitch=9, side=37), rot("forearm_L", pitch=30),
    )
    chop = pose(low,
        pos("hips", up=-.16, fwd=.08, left=.022),
        rot("hips", twist=20), rot("spine1", pitch=11, twist=7),
        rot("spine2", pitch=14, twist=25), rot("head", pitch=-17, twist=-40),
        rot("upper_arm_R", pitch=75, side=25),
        rot("forearm_R", pitch=15), rot("hand_R", pitch=-64),
    )
    ground_finish = pose(chop,
        pos("hips", up=-.17, fwd=.09, left=.023),
        rot("upper_arm_R", pitch=41, side=23),
        rot("forearm_R", pitch=28), rot("hand_R", pitch=-43),
        rot("spine1", pitch=12, twist=6), rot("spine2", pitch=15, twist=22),
    )
    attack3_rate = 7 / 60  # [tuned] Attack3.png has no 2D ANIM_SETS playback entry.
    r3 = attack3_rate
    attack3_keys = {
        0.0: back,
        r3: punch(dip, 1.4),
        2 * r3: punch(rise, 1.4),
        2.65 * r3: punch(overhead, 1.25),
        3.2 * r3: bent(punch(chop, 1.3)),
        4 * r3: bent(punch(ground_finish, 1.3)),
        5 * r3: bent(punch(ground_finish, 1.3)),
        5 * r3 + .2: ready,
    }
    attack3_ease = {r3: "smooth", 2 * r3: "out", 2.65 * r3: "smooth", 3.2 * r3: "back",
                    4 * r3: "out", 5 * r3: "linear", 5 * r3 + .2: "smooth"}

    # Death.png: buckle onto the knees, fold forward, and settle prone/sideways.
    # Ground the evaluated mesh when exporting (sole/toe geometry can differ per
    # playable body); .19m is the initial root clearance for this Knight [tuned].
    buckle = pose(ready,
        pos("hips", up=-.18, fwd=.025), rot("spine1", pitch=7),
        rot("spine2", pitch=9), rot("head", pitch=4),
        rot("thigh_L", pitch=31), rot("shin_L", pitch=-58),
        rot("thigh_R", pitch=24), rot("shin_R", pitch=-52),
        rot("upper_arm_R", pitch=8, side=-20), rot("forearm_R", pitch=17),
        rot("hand_R", pitch=-43),
    )
    knee = pose(buckle,
        pos("hips", up=-.36, fwd=.035),
        rot("thigh_L", pitch=63), rot("shin_L", pitch=-113),
        rot("thigh_R", pitch=57), rot("shin_R", pitch=-109),
        rot("spine1", pitch=12), rot("spine2", pitch=13), rot("head", pitch=10),
        rot("upper_arm_R", pitch=10, side=-20), rot("forearm_R", pitch=6),
    )
    fold = pose(knee,
        pos("hips", up=-.43, fwd=.06),
        rot("spine1", pitch=25), rot("spine2", pitch=24), rot("head", pitch=20),
        rot("thigh_L", pitch=70), rot("shin_L", pitch=-120),
        rot("thigh_R", pitch=64), rot("shin_R", pitch=-116),
        rot("upper_arm_L", pitch=27, side=33), rot("forearm_L", pitch=18),
    )
    fall = pose(fold,
        pos("root", up=.11, fwd=.05), rot("root", pitch=43, twist=7),
        pos("hips", up=-.29, fwd=.015),
        rot("spine1", pitch=20), rot("spine2", pitch=18), rot("head", pitch=12),
        rot("upper_arm_L", pitch=38, side=32), rot("forearm_L", pitch=10),
        rot("upper_arm_R", pitch=21, side=-25), rot("forearm_R", pitch=12),
    )
    prone = pose(ready,
        pos("root", up=.19, fwd=.12), rot("root", pitch=89, twist=9),
        pos("hips", up=0, fwd=0), rot("hips", twist=-3),
        rot("spine1", pitch=2), rot("spine2", pitch=-2), rot("neck", pitch=0),
        rot("head", pitch=0, twist=42),
        rot("thigh_L", pitch=6, side=5), rot("shin_L", pitch=-8),
        rot("thigh_R", pitch=-3, side=-9), rot("shin_R", pitch=-6),
        rot("foot_L", pitch=0), rot("foot_R", pitch=0),
        rot("toe_L", pitch=0), rot("toe_R", pitch=0),
        rot("upper_arm_L", pitch=13, side=25), rot("forearm_L", pitch=9),
        rot("hand_L", pitch=0), rot("upper_arm_R", pitch=12, side=-29),
        rot("forearm_R", pitch=14), rot("hand_R", pitch=-40),
    )
    bounce = pose(prone, pos("root", up=.27, fwd=.12), rot("root", pitch=80, twist=9),
                  rot("head", pitch=6, twist=42), rot("upper_arm_L", pitch=24, side=40),
                  rot("upper_arm_R", pitch=22, side=-40))
    death_rate = 6 / 60
    death_keys = {
        0.0: ready,
        death_rate: buckle,
        2 * death_rate: knee,
        3 * death_rate: knee,
        4 * death_rate: fold,
        5 * death_rate: fold,
        6 * death_rate: fall,
        7 * death_rate: prone,
        7.5 * death_rate: bounce,
        8.3 * death_rate: prone,
        9 * death_rate: prone,
    }

    def entry(name, frames, rate, keys, markers=None, feet="planted", loop=False, note="",
              ease=None, tail=0.0):
        return {
            "duration": frames * rate + tail,
            "keys": keys,
            "ease": ease or {},
            "markers": markers or {},
            "feet": feet,
            "loop": loop,
            "source": SPRITE_ROOT + name + ".png",
            "frames": frames,
            "frame_seconds": rate,
            "note": note,
        }

    return {
        "ready": ready,
        "Idle": entry("Idle", 10, idle_rate, idle_keys, loop=True),
        "Attack1": entry("Attack1", 4, r1, attack1_keys,
                         {"Contact": 2 * r1, "Follow through": 3 * r1},
                         ease=attack1_ease, tail=.16),
        "Attack2": entry("Attack2", 4, r2, attack2_keys,
                         {"Contact": 2 * r2, "Follow through": 3 * r2},
                         ease=attack2_ease, tail=.2),
        "Attack3": entry("Attack3", 5, r3, attack3_keys,
                         {"Contact": 3.2 * r3, "Follow through": 4 * r3},
                         ease=attack3_ease, tail=.2,
                         note="[tuned] 7/60 s per cel, because Attack3 is not in 2D ANIM_SETS"),
        "Death": entry("Death", 9, death_rate, death_keys,
                       {"Knees": 2 * death_rate, "Ground": 7 * death_rate}, feet="free",
                       ease={death_rate: "out", 2 * death_rate: "back", 4 * death_rate: "in",
                             6 * death_rate: "in", 7 * death_rate: "in", 7.5 * death_rate: "out", 8.3 * death_rate: "in"}),
    }
