"""Goblin and Skeleton animation on the shared Crimson Red rig.

Timings come from main-game/data/classes.lua ANIM_SETS and the sprite sheets in
assets/enemies/{Goblin,Skeleton}/base. The 2D sheets have no Take Hit, so the TakeHit
clip is the shared reaction in build_humanoid.py. Attack2/Attack3 are CR-original
variants (2D has one Attack): [tuned] to the same cel rate.
Goblin: hunched, springy, a long coil then a sudden overhead stab (Attack.png cels 7-8).
Skeleton: stiff, ratcheting, sword raised high then a lunging thrust with the shield pulled up.

Pure pose data: clips(model, rot, pos, add, override, amplify) -> {name: clip, "ready": pose}.
Times are seconds. See build_humanoid.sample_clip for the clip format and easings.
"""
import math

SP = "main-game/assets/enemies/"


def _stance(rot, pos, add, model):
    if model == "witch":
        # hunched: the spine folds forward ~34 degrees, the head thrust out; the right hand holds the staff upright
        # (arm pitches plus the spine's forward fold add up to 90 degrees, which stands the baked staff vertical); the left hand clutches the robe
        return add(
            pos("hips", up=-.07, left=.01), rot("hips", twist=-6),
            rot("spine1", pitch=19), rot("spine2", pitch=15, twist=4),
            rot("neck", pitch=-11), rot("head", pitch=-17, twist=3),
            rot("clavicle_L", pitch=4), rot("clavicle_R", pitch=4),
            rot("upper_arm_R", pitch=26, side=-10), rot("forearm_R", pitch=54), rot("hand_R", pitch=-28),
            rot("upper_arm_L", pitch=22, side=16), rot("forearm_L", pitch=46), rot("hand_L", pitch=-6))
    if model == "goblin":
        return add(
            pos("hips", up=-.20, left=.012), rot("hips", twist=-12, side=-3),
            rot("spine1", pitch=14), rot("spine2", pitch=10, twist=10),
            rot("neck", pitch=-8), rot("head", pitch=-14, twist=4),
            rot("clavicle_L", pitch=-3), rot("clavicle_R", pitch=-3),
            rot("upper_arm_R", pitch=38, side=-16), rot("forearm_R", pitch=62), rot("hand_R", pitch=-24),
            rot("upper_arm_L", pitch=28, side=24), rot("forearm_L", pitch=58), rot("hand_L", pitch=-8))
    return add(
        pos("hips", up=-.075, left=.01), rot("hips", twist=-6, side=-2),
        rot("spine1", pitch=-2), rot("spine2", pitch=-3, twist=6),
        rot("head", pitch=-4, twist=4),
        rot("upper_arm_R", pitch=30, side=-16), rot("forearm_R", pitch=48), rot("hand_R", pitch=-34),
        rot("upper_arm_L", pitch=38, side=14), rot("forearm_L", pitch=74), rot("hand_L", pitch=-10))


STANCE = {}


def clips(model, rot, pos, add, override, amplify):
    STANCE[model] = ready = _stance(rot, pos, add, model)
    fn = {"goblin": goblin, "witch": witch}.get(model, skeleton)
    lib = fn(ready, rot, pos, add, override, amplify)
    lib["ready"] = ready
    return lib


def entry(sheet, frames, rate, keys, ease=None, markers=None, loop=False, feet="planted", tail=0.0, fn=None):
    clip = {"duration": frames * rate + tail, "ease": ease or {}, "markers": markers or {},
            "loop": loop, "feet": feet, "source": SP + sheet, "frames": frames, "frame_seconds": rate}
    if fn:
        clip["fn"] = fn
    else:
        clip["keys"] = keys
    return clip


# ------------------------------------------------------------------ goblin
def goblin(ready, rot, pos, add, override, amplify):
    s, c = math.sin, math.cos
    idle_rate, atk = 8 / 60, 7 / 60
    idle_dur = 4 * idle_rate

    def idle_fn(t):
        phi = 2 * math.pi * t / idle_dur
        # quick predatory bounce: one deep breath-bob per cycle, jittery head and blade hand
        return add(ready,
            pos("hips", up=.045 * s(phi) - .02, left=.03 * s(phi), fwd=.02 * c(phi)),
            rot("hips", twist=6 * c(phi), side=3 * s(phi)),
            rot("spine1", pitch=4 * s(phi + .5)), rot("spine2", pitch=5 * s(phi - .2), twist=-7 * c(phi)),
            rot("head", pitch=-5 * s(phi + .3), twist=10 * s(phi + 1.2)),
            rot("clavicle_L", pitch=4 * s(phi)), rot("clavicle_R", pitch=4 * s(phi + .4)),
            rot("upper_arm_R", pitch=9 * s(2 * phi), side=-3 * s(phi)),
            rot("forearm_R", pitch=12 * s(2 * phi - .6)), rot("hand_R", pitch=10 * s(2 * phi)),
            rot("upper_arm_L", pitch=8 * s(phi - .6), side=4 * s(phi)),
            rot("forearm_L", pitch=10 * s(phi - 1.0)))
    idle = entry("Goblin/base/Idle.png", 4, idle_rate, None, loop=True, fn=idle_fn)

    # --- Attack1: low coil, shaking tension, then a sudden overhead stab (Attack.png).
    crouch = override(ready, pos("hips", up=-.31, fwd=-.04), rot("hips", twist=-26),
        rot("spine1", pitch=22), rot("spine2", pitch=14, twist=-24), rot("head", pitch=-18, twist=26),
        rot("upper_arm_R", pitch=-62, side=-20), rot("forearm_R", pitch=34), rot("hand_R", pitch=-30),
        rot("upper_arm_L", pitch=40, side=44), rot("forearm_L", pitch=40))
    coil = override(crouch, pos("hips", up=-.34, fwd=-.06), rot("hips", twist=-34),
        rot("spine2", twist=-32, pitch=18), rot("upper_arm_R", pitch=-78, side=-26),
        rot("head", pitch=-22, twist=34))
    stab = override(ready, pos("hips", up=-.04, fwd=.16, left=.02), rot("hips", twist=28),
        rot("spine1", pitch=-10, twist=8), rot("spine2", pitch=-14, twist=26),
        rot("neck", pitch=-12), rot("head", pitch=-26, twist=-24),
        rot("upper_arm_R", pitch=158, side=-10), rot("forearm_R", pitch=6), rot("hand_R", pitch=-14),
        rot("upper_arm_L", pitch=-26, side=40), rot("forearm_L", pitch=20))
    landed = override(stab, pos("hips", up=-.16, fwd=.19), rot("spine1", pitch=14),
        rot("spine2", pitch=10, twist=22), rot("head", pitch=-8, twist=-22),
        rot("upper_arm_R", pitch=96, side=0), rot("forearm_R", pitch=14))
    # Contact at 24.5/60 s = 3.5 cels: data/abilities.lua GoblinAutoAttack.delay.
    keys = {0.0: ready, 1.2 * atk: crouch, 2.5 * atk: coil, 3.5 * atk: stab, 4.6 * atk: landed,
            8 * atk: landed, 8 * atk + .22: ready}
    attack1 = entry("Goblin/base/Attack.png", 8, atk, keys,
        ease={1.2 * atk: "out", 2.5 * atk: "smooth", 3.5 * atk: "back", 4.6 * atk: "out",
              8 * atk: "linear", 8 * atk + .22: "smooth"},
        markers={"Contact": 3.5 * atk, "Follow through": 4.6 * atk}, tail=.22)

    # --- Attack2: two quick cross slashes, low and angry.
    cut_r = override(ready, pos("hips", up=-.26, fwd=.07), rot("hips", twist=30), rot("spine2", pitch=14, twist=30),
        rot("head", pitch=-18, twist=-30), rot("upper_arm_R", pitch=70, side=48), rot("forearm_R", pitch=20),
        rot("hand_R", pitch=-50), rot("upper_arm_L", pitch=-20, side=40))
    cut_l = override(ready, pos("hips", up=-.26, fwd=.07), rot("hips", twist=-28), rot("spine2", pitch=14, twist=-30),
        rot("head", pitch=-18, twist=30), rot("upper_arm_R", pitch=72, side=-58), rot("forearm_R", pitch=18),
        rot("hand_R", pitch=-30), rot("upper_arm_L", pitch=40, side=60))
    wind = override(ready, pos("hips", up=-.30, fwd=-.06), rot("hips", twist=-30), rot("spine2", pitch=16, twist=-34),
        rot("head", pitch=-14, twist=32), rot("upper_arm_R", pitch=-30, side=-60), rot("forearm_R", pitch=40),
        rot("upper_arm_L", pitch=50, side=40))
    a2 = 7 / 60
    keys = {0.0: ready, 2.2 * a2: wind, 3.5 * a2: cut_r, 4.8 * a2: wind, 5.8 * a2: cut_l, 7.5 * a2: cut_l,
            7.5 * a2 + .2: ready}
    attack2 = entry("Goblin/base/Attack.png", 7.5, a2, keys,
        ease={2.2 * a2: "out", 3.5 * a2: "snap", 4.8 * a2: "smooth", 5.8 * a2: "snap", 7.5 * a2: "linear",
              7.5 * a2 + .2: "smooth"},
        markers={"Contact": 3.5 * a2, "Follow through": 5.8 * a2}, tail=.2)

    # --- Attack3: leaping two-handed chop (the airborne look is a stretch, feet stay planted).
    load = override(ready, pos("hips", up=-.34, fwd=-.05), rot("spine1", pitch=26), rot("spine2", pitch=18),
        rot("head", pitch=-20), rot("upper_arm_R", pitch=-50, side=-12), rot("forearm_R", pitch=30),
        rot("upper_arm_L", pitch=-44, side=18), rot("forearm_L", pitch=34))
    up = override(ready, pos("hips", up=.00, fwd=.0), rot("spine1", pitch=-14), rot("spine2", pitch=-16),
        rot("head", pitch=-26), rot("upper_arm_R", pitch=165, side=-8), rot("forearm_R", pitch=8),
        rot("upper_arm_L", pitch=150, side=14), rot("forearm_L", pitch=10))
    slam = override(ready, pos("hips", up=-.30, fwd=.2), rot("spine1", pitch=34), rot("spine2", pitch=26),
        rot("head", pitch=6), rot("upper_arm_R", pitch=62, side=-4), rot("forearm_R", pitch=14),
        rot("upper_arm_L", pitch=58, side=8), rot("forearm_L", pitch=16))
    a3 = 7 / 60
    keys = {0.0: ready, 1.6 * a3: load, 2.7 * a3: up, 3.5 * a3: slam, 5.5 * a3: slam, 5.5 * a3 + .22: ready}
    attack3 = entry("Goblin/base/Attack.png", 5.5, a3, keys,
        ease={1.6 * a3: "out", 2.7 * a3: "out", 3.5 * a3: "snap", 5.5 * a3: "linear", 5.5 * a3 + .22: "smooth"},
        markers={"Contact": 3.5 * a3, "Follow through": 5.5 * a3}, tail=.22)

    # --- Death.png: flung over backwards, a bounce, then flat on its back.
    d = 6 / 60
    flung = override(ready, pos("hips", up=-.1, fwd=-.18), rot("hips", twist=-10), rot("spine1", pitch=-20),
        rot("spine2", pitch=-24), rot("head", pitch=-30), rot("upper_arm_L", pitch=-30, side=60),
        rot("upper_arm_R", pitch=-20, side=-60), rot("forearm_R", pitch=10))
    air = override(flung, pos("root", up=.12, fwd=-.2), rot("root", pitch=-48), pos("hips", up=-.2, fwd=-.1),
        rot("thigh_L", pitch=40), rot("thigh_R", pitch=18), rot("shin_L", pitch=-60), rot("shin_R", pitch=-40))
    floor = override(ready, pos("root", up=.20, fwd=.55), rot("root", pitch=-90, twist=-12), pos("hips", up=0),
        rot("spine1", pitch=-3), rot("spine2", pitch=-4), rot("neck", pitch=-5), rot("head", pitch=-8, twist=24),
        rot("thigh_L", pitch=8, side=10), rot("thigh_R", pitch=-6, side=-14), rot("shin_L", pitch=-12), rot("shin_R", pitch=-6),
        rot("upper_arm_L", pitch=-18, side=42), rot("upper_arm_R", pitch=-10, side=-52), rot("forearm_R", pitch=-8),
        rot("forearm_L", pitch=10), rot("hand_R", pitch=-14))
    bounce = override(floor, pos("root", up=.30, fwd=.45), rot("root", pitch=-82))
    keys = {0.0: ready, d: flung, 2 * d: air, 3 * d: floor, 3.6 * d: bounce, 4 * d: floor, 5 * d: floor}
    death = entry("Goblin/base/Death.png", 5, d, keys, feet="free",
        ease={d: "snap", 2 * d: "out", 3 * d: "in", 3.6 * d: "out", 4 * d: "in", 5 * d: "linear"},
        markers={"Ground": 3 * d})
    return {"Idle": idle, "Attack1": attack1, "Attack2": attack2, "Attack3": attack3, "Death": death}


# ---------------------------------------------------------------- skeleton
def skeleton(ready, rot, pos, add, override, amplify):
    s, c = math.sin, math.cos
    idle_rate, atk = 8 / 60, 7 / 60
    # Ratcheting, puppet-like idle: each cel jolts to the next pose.
    def beat(i):
        sg = 1 if i % 2 == 0 else -1
        return add(ready,
            pos("hips", up=.018 * (1 if i % 2 else -1), left=.025 * sg),
            rot("hips", twist=5 * sg), rot("spine1", pitch=3 * (1 if i % 2 else -1), side=3 * sg),
            rot("spine2", twist=-6 * sg, pitch=3), rot("head", pitch=-4 * (1 if i % 2 else -1), twist=14 * sg, side=5 * sg),
            rot("upper_arm_R", pitch=9 * sg, side=-4 * sg), rot("forearm_R", pitch=12 * sg), rot("hand_R", pitch=-12 * sg),
            rot("upper_arm_L", pitch=6 * -sg, side=4), rot("forearm_L", pitch=7 * sg))
    idle_keys = {i * idle_rate: beat(i % 4) for i in range(5)}
    idle_keys[4 * idle_rate] = idle_keys[0.0]
    idle = entry("Skeleton/base/Idle.png", 4, idle_rate, idle_keys, loop=True,
        ease={i * idle_rate: "back" for i in range(1, 5)})

    # --- Attack1: sword hoisted high behind the head with the shield forward, then a lunging thrust.
    raise_ = override(ready, pos("hips", up=-.10, fwd=-.05), rot("hips", twist=-22), rot("spine1", pitch=-4),
        rot("spine2", pitch=-8, twist=-26), rot("head", pitch=-8, twist=26),
        rot("upper_arm_R", pitch=-104, side=-26), rot("forearm_R", pitch=52), rot("hand_R", pitch=-40),
        rot("upper_arm_L", pitch=58, side=8), rot("forearm_L", pitch=84))
    quiver = override(raise_, rot("upper_arm_R", pitch=-110, side=-30), rot("spine2", pitch=-10, twist=-30),
        pos("hips", up=-.11, fwd=-.06))
    thrust = override(ready, pos("hips", up=-.15, fwd=.17, left=.02), rot("hips", twist=24),
        rot("spine1", pitch=10, twist=6), rot("spine2", pitch=14, twist=24), rot("head", pitch=-16, twist=-22),
        rot("upper_arm_R", pitch=96, side=-4), rot("forearm_R", pitch=2), rot("hand_R", pitch=-6),
        rot("upper_arm_L", pitch=-12, side=34), rot("forearm_L", pitch=36))
    held = override(thrust, pos("hips", up=-.16, fwd=.20), rot("spine2", pitch=16, twist=26),
        rot("upper_arm_R", pitch=100))
    # Contact at 24.5/60 s = 3.5 cels: data/abilities.lua SkeletonAutoAttack.delay.
    keys = {0.0: ready, 1.3 * atk: raise_, 2.8 * atk: raise_, 3.1 * atk: quiver, 3.5 * atk: thrust,
            4.5 * atk: held, 8 * atk: held, 8 * atk + .24: ready}
    attack1 = entry("Skeleton/base/Attack.png", 8, atk, keys,
        ease={1.3 * atk: "out", 2.8 * atk: "linear", 3.1 * atk: "smooth", 3.5 * atk: "snap", 4.5 * atk: "out",
              8 * atk: "linear", 8 * atk + .24: "smooth"},
        markers={"Contact": 3.5 * atk, "Follow through": 4.5 * atk}, tail=.24)

    # --- Attack2: overhead sword chop.
    hoist = override(ready, pos("hips", up=-.06, fwd=-.06), rot("spine1", pitch=-8), rot("spine2", pitch=-12),
        rot("head", pitch=-8), rot("upper_arm_R", pitch=170, side=-8), rot("forearm_R", pitch=14),
        rot("hand_R", pitch=-10), rot("upper_arm_L", pitch=30, side=18))
    chop = override(ready, pos("hips", up=-.20, fwd=.16), rot("hips", twist=8), rot("spine1", pitch=18),
        rot("spine2", pitch=22, twist=8), rot("head", pitch=8), rot("upper_arm_R", pitch=58, side=-4),
        rot("forearm_R", pitch=6), rot("hand_R", pitch=-20), rot("upper_arm_L", pitch=50, side=10))
    a2 = 7 / 60
    keys = {0.0: ready, 2.0 * a2: hoist, 3.0 * a2: hoist, 3.5 * a2: chop, 6 * a2: chop, 6 * a2 + .22: ready}
    attack2 = entry("Skeleton/base/Attack.png", 6, a2, keys,
        ease={2.0 * a2: "out", 3.0 * a2: "linear", 3.5 * a2: "snap", 6 * a2: "linear", 6 * a2 + .22: "smooth"},
        markers={"Contact": 3.5 * a2, "Follow through": 5 * a2}, tail=.22)

    # --- Attack3: shield bash, shoulder first.
    draw = override(ready, pos("hips", up=-.12, fwd=-.08), rot("hips", twist=-20), rot("spine2", pitch=4, twist=-24),
        rot("head", twist=18), rot("upper_arm_L", pitch=-8, side=40), rot("forearm_L", pitch=50),
        rot("upper_arm_R", pitch=-20, side=-30), rot("forearm_R", pitch=40))
    bash = override(ready, pos("hips", up=-.14, fwd=.2, left=-.03), rot("hips", twist=34), rot("spine1", pitch=10, twist=8),
        rot("spine2", pitch=12, twist=30), rot("head", pitch=-10, twist=-30),
        rot("upper_arm_L", pitch=98, side=0), rot("forearm_L", pitch=20),
        rot("upper_arm_R", pitch=-10, side=-36), rot("forearm_R", pitch=60))
    a3 = 7 / 60
    keys = {0.0: ready, 2.2 * a3: draw, 3.0 * a3: draw, 3.5 * a3: bash, 6 * a3: bash, 6 * a3 + .22: ready}
    attack3 = entry("Skeleton/base/Attack.png", 6, a3, keys,
        ease={2.2 * a3: "out", 3.0 * a3: "linear", 3.5 * a3: "snap", 6 * a3: "linear", 6 * a3 + .22: "smooth"},
        markers={"Contact": 3.5 * a3, "Follow through": 5.2 * a3}, tail=.22)

    # --- Death.png: staggers, knees give, then it collapses into a heap.
    d = 6 / 60
    stagger = override(ready, pos("hips", up=-.12, fwd=-.12), rot("spine1", pitch=-12), rot("spine2", pitch=-16),
        rot("head", pitch=-24, twist=14), rot("upper_arm_L", pitch=-12, side=54), rot("upper_arm_R", pitch=-30, side=-40),
        rot("forearm_R", pitch=-6))
    knees = override(ready, pos("hips", up=-.38, fwd=-.02), rot("spine1", pitch=16), rot("spine2", pitch=18),
        rot("head", pitch=24, twist=-10), rot("thigh_L", pitch=70), rot("shin_L", pitch=-112),
        rot("thigh_R", pitch=58), rot("shin_R", pitch=-108),
        rot("upper_arm_L", pitch=24, side=34), rot("upper_arm_R", pitch=-10, side=-36), rot("forearm_R", pitch=8))
    heap = override(knees, pos("root", up=.17, fwd=.34), rot("root", pitch=84, twist=-8), pos("hips", up=0, fwd=0),
        rot("spine1", pitch=4), rot("spine2", pitch=-2), rot("head", pitch=6, twist=36),
        rot("thigh_L", pitch=10, side=8), rot("shin_L", pitch=-12), rot("thigh_R", pitch=-4, side=-10),
        rot("shin_R", pitch=-10), rot("upper_arm_L", pitch=14, side=48), rot("upper_arm_R", pitch=18, side=-54),
        rot("forearm_L", pitch=12), rot("forearm_R", pitch=8))
    rattle = override(heap, pos("root", up=.27, fwd=.34), rot("root", pitch=76, twist=-8),
        rot("head", pitch=14, twist=40), rot("upper_arm_L", pitch=26, side=44), rot("upper_arm_R", pitch=30, side=-48))
    keys = {0.0: ready, d: stagger, 2 * d: knees, 3 * d: heap, 3.5 * d: rattle, 4.3 * d: heap, 5 * d: heap}
    death = entry("Skeleton/base/Death.png", 5, d, keys, feet="free",
        ease={d: "snap", 2 * d: "back", 3 * d: "in", 3.5 * d: "out", 4.3 * d: "in", 5 * d: "linear"},
        markers={"Knees": 2 * d, "Ground": 3 * d})
    return {"Idle": idle, "Attack1": attack1, "Attack2": attack2, "Attack3": attack3, "Death": death}


# ------------------------------------------------------------------ witch
def witch(ready, rot, pos, add, override, amplify):
    """Idle (a shuffling hunched sway), Cast (gather, thrust the staff up, tremble, sag) and Death (flung back, a heap).
    Walk / Move / TakeHit come from build_humanoid (STYLE / WALK entries for "witch")."""
    s, c = math.sin, math.cos
    idle_dur = 1.8

    def idle_fn(t):
        phi = 2 * math.pi * t / idle_dur
        return add(ready,
            pos("hips", up=.018 * s(2 * phi) - .01, left=.02 * s(phi)),
            rot("hips", twist=3 * c(phi), side=2 * s(phi)),
            rot("spine1", pitch=2.5 * s(2 * phi + .4)), rot("spine2", pitch=3 * s(2 * phi - .2), twist=-4 * c(phi)),
            rot("head", pitch=-4 * s(2 * phi + .8), twist=9 * s(phi + 1.0)),      # peering about
            rot("clavicle_L", pitch=2 * s(phi)), rot("clavicle_R", pitch=2 * s(phi + .5)),
            rot("upper_arm_R", pitch=2 * s(2 * phi)), rot("forearm_R", pitch=-2 * s(2 * phi)),
            rot("upper_arm_L", pitch=6 * s(phi - .6), side=3 * s(phi)),
            rot("forearm_L", pitch=10 * s(phi - 1.0)), rot("hand_L", pitch=8 * s(2 * phi)))
    idle = entry("", 1, idle_dur, None, loop=True, fn=idle_fn)

    # --- Cast: gather (bend lower, the staff dragged back), then straighten out of the hunch, staff thrust skyward
    # (the pitches of the right arm still add up to 90 degrees: the staff stays upright), left hand clawed out; tremble; sag.
    gather = override(ready, pos("hips", up=-.17, fwd=-.04), rot("hips", twist=-12),
        rot("spine1", pitch=28), rot("spine2", pitch=22, twist=-8), rot("neck", pitch=-14), rot("head", pitch=-16, twist=6),
        rot("upper_arm_R", pitch=-6, side=-12), rot("forearm_R", pitch=70), rot("hand_R", pitch=-26),
        rot("upper_arm_L", pitch=-16, side=36), rot("forearm_L", pitch=34))
    raised = override(ready, pos("hips", up=-.08, fwd=.02), rot("hips", twist=8),
        rot("spine1", pitch=-4), rot("spine2", pitch=-8, twist=4), rot("neck", pitch=-12), rot("head", pitch=-30),
        rot("clavicle_R", pitch=8), rot("clavicle_L", pitch=8),
        rot("upper_arm_R", pitch=138, side=-8), rot("forearm_R", pitch=2), rot("hand_R", pitch=-50),
        rot("upper_arm_L", pitch=96, side=52), rot("forearm_L", pitch=24), rot("hand_L", pitch=-14))
    shudder = override(raised, rot("spine2", pitch=-11, twist=1), rot("head", pitch=-34, twist=-4),
        rot("upper_arm_R", pitch=142, side=-7), rot("upper_arm_L", pitch=102, side=57), pos("hips", up=-.07))
    sag = override(ready, pos("hips", up=-.13, fwd=.02), rot("spine1", pitch=24), rot("spine2", pitch=19),
        rot("head", pitch=-12), rot("upper_arm_R", pitch=28, side=-10), rot("forearm_R", pitch=52),
        rot("upper_arm_L", pitch=12, side=22), rot("forearm_L", pitch=36))
    keys = {0.0: ready, .30: amplify(gather, ready, 1.3), .62: amplify(raised, ready, 1.05), .78: shudder,
            .94: raised, 1.08: shudder, 1.22: raised, 1.6: sag, 1.95: ready}
    ease = {.30: "smooth", .62: "back", .78: "smooth", .94: "smooth", 1.08: "smooth", 1.22: "smooth", 1.6: "out", 1.95: "smooth"}
    cast = {"duration": 1.95, "keys": keys, "ease": ease, "markers": {"Cast": .62}, "loop": False, "feet": "planted",
            "note": "[tuned] 3D-only enemy: the spell leaves the staff at 0.62 s"}

    # --- Death: flung backwards over the staff, a short air time, a heap on her back with the hat askew.
    d = .10
    flung = override(ready, pos("hips", up=-.1, fwd=-.18), rot("hips", twist=-10), rot("spine1", pitch=-16),
        rot("spine2", pitch=-22), rot("head", pitch=-32), rot("upper_arm_L", pitch=-30, side=60),
        rot("upper_arm_R", pitch=-40, side=-50), rot("forearm_R", pitch=10))
    air = override(flung, pos("root", up=.12, fwd=-.2), rot("root", pitch=-48), pos("hips", up=-.2, fwd=-.1),
        rot("thigh_L", pitch=40), rot("thigh_R", pitch=18), rot("shin_L", pitch=-60), rot("shin_R", pitch=-40))
    floor = override(ready, pos("root", up=.20, fwd=.50), rot("root", pitch=-90, twist=-14), pos("hips", up=0),
        rot("spine1", pitch=-3), rot("spine2", pitch=-4), rot("neck", pitch=-5), rot("head", pitch=-8, twist=24),
        rot("thigh_L", pitch=8, side=10), rot("thigh_R", pitch=-6, side=-14), rot("shin_L", pitch=-12), rot("shin_R", pitch=-6),
        rot("upper_arm_L", pitch=-18, side=44), rot("upper_arm_R", pitch=-10, side=-56), rot("forearm_R", pitch=-8),
        rot("forearm_L", pitch=10), rot("hand_R", pitch=-14))
    bounce = override(floor, pos("root", up=.30, fwd=.42), rot("root", pitch=-82))
    dkeys = {0.0: ready, d: flung, 2 * d: air, 3 * d: floor, 3.6 * d: bounce, 4 * d: floor, 6 * d: floor}
    death = entry("", 6, d, dkeys, feet="free",
        ease={d: "snap", 2 * d: "out", 3 * d: "in", 3.6 * d: "out", 4 * d: "in", 6 * d: "linear"},
        markers={"Ground": 3 * d})
    return {"Idle": idle, "Cast": cast, "Death": death}
