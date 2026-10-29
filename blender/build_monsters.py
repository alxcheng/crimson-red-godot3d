"""Faceted Goblin and Skeleton studies on the shared Crimson Red humanoid rig.

References: main-game/assets/enemies/{Goblin,Skeleton}/base/Idle.png.
All shapes/proportions below are CR-original 3D art direction [tuned]. Palette and
silhouette follow those sprites; these are editable rigged meshes, not sprite planes.
Run: Blender --background --python blender/build_monsters.py -- godot/models [goblin|skeleton]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_humanoid as h

PALETTE = {
    "goblin_skin": (85, 115, 43),
    "goblin_highlight": (113, 140, 61),
    "goblin_dark": (59, 81, 31),
    "goblin_eye": (213, 244, 27),
    "leather": (126, 69, 35),
    "leather_dark": (80, 44, 22),
    "pants": (46, 47, 55),
    "bone": (143, 143, 103),
    "bone_light": (174, 173, 127),
    "bone_shadow": (104, 105, 71),
    "iron": (142, 146, 143),
    "iron_edge": (188, 190, 184),
    "iron_dark": (91, 95, 94),
    "tooth": (220, 218, 166),
    "witch_skin": (104, 158, 70),
    "witch_dark": (62, 104, 46),
    "robe": (26, 24, 32),
    "robe_trim": (62, 46, 80),
    "hat_band": (96, 58, 128),
    "brass": (200, 165, 60),
    "wood": (122, 86, 50),
    "hair": (160, 160, 170),
}
for key, colour in PALETTE.items():
    h.COLOURS[key] = colour
    if key not in h.MATS:
        h.MATS.append(key)


def bulb(b, bone, mat, centre, radius, sides=7):
    x, y, z = centre
    rx, ry, rz = radius
    b.loft(bone, mat, [(x, y, z-rz, rx*.30, ry*.30),
                      (x, y, z-rz*.45, rx*.88, ry*.88),
                      (x, y, z+rz*.35, rx, ry),
                      (x, y, z+rz, rx*.35, ry*.35)], sides)


def rod(b, bone, mat, start, end, radius, sides=6, end_radius=None):
    """Closed faceted rod along an arbitrary direction, bound to one deform bone."""
    start, end = Vector(start), Vector(end)
    length = (end-start).length
    after = len(b.groups.get(bone, []))
    r1 = radius if end_radius is None else end_radius
    b.loft(bone, mat, [(0,0,0,radius*.8,radius*.8),
                      (0,0,length*.12,radius,radius),
                      (0,0,length*.88,r1,r1),
                      (0,0,length,r1*.8,r1*.8)], sides)
    q = Vector((0,0,1)).rotation_difference((end-start).normalized())
    for v in b.groups[bone][after:]:
        v.co = start + q @ v.co


def panel(b, bone, mat, vertices):
    """A thin closed low-poly patch with an intentionally angular outline."""
    front = [b.bm.verts.new(v) for v in vertices]
    back = [b.bm.verts.new((v[0],v[1]+.012,v[2])) for v in vertices]
    for vs in (front, back[::-1]):
        b.bm.faces.new(vs).material_index = h.MATS.index(mat)
    for i in range(len(front)):
        b.bm.faces.new((front[i],back[i],back[(i+1)%len(front)],front[(i+1)%len(front)])).material_index=h.MATS.index(mat)
    b.groups.setdefault(bone,[]).extend(front+back)


def boots(b):
    for side, sign in (("L",1),("R",-1)):
        x = sign*.10
        b.loft('shin_'+side,'leather',[(x,0,.105,.050,.056),(x,0,.23,.070,.074),(x,0,.37,.071,.071),(x,0,.39,.078,.077)],7)
        b.loft('foot_'+side,'leather',[(x,.045,.045,.048,.038),(x,-.015,.047,.057,.042),(x,-.10,.035,.060,.030)],7,axis='Y')
        b.loft('toe_'+side,'leather',[(x,-.095,.035,.060,.030),(x,-.17,.03,.055,.025),(x,-.21,.027,.035,.022)],7,axis='Y')


def weapon(b, arm, model):
    """Bake a grip-oriented prop into the right hand's vertex group."""
    bone='hand_R'
    first=len(b.groups.get(bone,[]))
    length=.52 if model=='goblin' else .73
    # Local weapon coordinates are +Z along blade, matching the shared sword prop.
    b.loft(bone,'leather_dark',[(0,0,-.075,.018,.018),(0,0,.075,.018,.018)],6)
    b.loft(bone,'iron_edge',[(0,0,.07,.065,.018),(0,0,.105,.065,.018)],box=True)
    # Curved, one-sided blade outline copied from the enemy sprites' curved weapons.
    vertices=[(-.022,-.008,.10),(.030,-.008,.10),(.040,-.008,length*.67),
              (.085,-.008,length*.88),(.060,-.008,length),(.010,-.008,length*.84),(-.022,-.008,length*.54)]
    panel(b,bone,'steel',vertices)
    rest=arm.data.bones[bone].matrix_local
    grip=rest @ Matrix.Translation((0,.07,0)) @ Matrix.Rotation(math.radians(-130),4,'X') @ Matrix.Rotation(math.pi/2,4,'Z')
    for v in b.groups[bone][first:]:
        v.co=grip @ v.co


def build_goblin(b, arm):
    # Lean dark trousers and large leather boots, with a jagged brown waist sash.
    b.loft('hips','pants',[(0,0,.86,.14,.10),(0,0,1.01,.15,.10)],7)
    panel(b,'hips','leather', [(-.145,-.105,1.02),(.145,-.105,1.02),(.13,-.105,.83),(.035,-.105,.80),(-.02,-.105,.89),(-.13,-.105,.84)])
    for side,sign in (("L",1),("R",-1)):
        x=sign*.10
        b.loft('thigh_'+side,'pants',[(x,0,.93,.091,.087),(x,0,.76,.086,.078),(x,0,.57,.060,.060),(x,0,.50,.055,.055)],7)
        b.loft('shin_'+side,'goblin_skin',[(x,0,.51,.052,.054),(x,0,.40,.053,.052),(x,0,.27,.041,.044)],7)
    boots(b)
    # Broad upper back, narrow belly. A brown asymmetrical jerkin leaves green skin visible.
    b.loft('spine1','goblin_skin',[(0,0,1.02,.125,.09),(0,0,1.15,.15,.105),(0,0,1.29,.19,.12)],7)
    b.loft('spine2','goblin_skin',[(0,.015,1.25,.18,.12),(0,.015,1.38,.22,.14),(0,0,1.48,.16,.10)],7)
    panel(b,'spine1','leather',[(-.13,-.102,1.04),(.13,-.102,1.04),(.15,-.125,1.25),(.035,-.13,1.28),(-.07,-.12,1.16)])
    panel(b,'spine2','leather',[(-.04,-.132,1.25),(.17,-.125,1.27),(.17,-.125,1.45),(.10,-.10,1.49),(.045,-.11,1.41)])
    rod(b,'neck','goblin_dark',(0,0,1.48),(0,-.02,1.64),.052)
    # Face: heavy brow, tapered muzzle, long side ears and yellow-green eyes.
    b.loft('head','goblin_skin',[(0,-.02,1.60,.065,.065),(0,-.02,1.67,.12,.105),(0,-.015,1.78,.13,.115),(0,.015,1.88,.10,.085),(0,.025,1.93,.055,.055)],7)
    b.loft('head','goblin_skin',[(0,-.105,1.71,.08,.055),(0,-.20,1.68,.049,.033),(0,-.23,1.675,.016,.018)],5,axis='Y')
    for sign in (-1,1):
        # Each ear narrows toward a long, swept-back point.
        rod(b,'head','goblin_skin',(sign*.105,.015,1.79),(sign*.30,.065,1.91),.055,5,end_radius=.005)
        rod(b,'head','goblin_dark',(sign*.135,-.021,1.80),(sign*.252,.028,1.875),.024,5,end_radius=.003)
        x=sign*.052
        panel(b,'head','goblin_eye',[(x-sign*.020,-.125,1.78),(x+sign*.020,-.125,1.775),(x+sign*.017,-.125,1.735),(x-sign*.012,-.125,1.742)])
        rod(b,'head','goblin_dark',(sign*.015,-.13,1.79),(sign*.095,-.105,1.81),.019,5)
        b.loft('head','tooth',[(sign*.046,-.155,1.667,.013,.009),(sign*.046,-.155,1.70,.006,.005)],5)
    panel(b,'head','goblin_dark',[(-.052,-.156,1.67),(.052,-.156,1.67),(.043,-.16,1.65),(-.043,-.16,1.65)])
    # Short steel-gray mohawk, a recognizable silhouette in the source sprite.
    for y,z in ((-.015,1.93),(.035,1.95),(.085,1.925)):
        b.loft('head','iron_dark',[(0,y,z-.06,.032,.036),(0,y,z+.025,.026,.032),(0,y+.008,z+.10,.005,.008)],5)
    for side,sign in (("L",1),("R",-1)):
        x=sign*.27
        bulb(b,'clavicle_'+side,'goblin_skin',(x,0,1.44),(.082,.080,.075))
        b.loft('upper_arm_'+side,'goblin_skin',[(x,0,1.44,.066,.068),(x,0,1.31,.075,.068),(x,0,1.15,.045,.047)],7)
        b.loft('forearm_'+side,'goblin_skin',[(x,0,1.16,.045,.047),(x,-.005,1.05,.058,.052),(x,0,.88,.036,.037)],7)
        bulb(b,'hand_'+side,'goblin_skin',(x,-.006,.81),(.045,.038,.085),6)
        # Small ivory elbow spikes from the sprite.
        rod(b,'forearm_'+side,'tooth',(x,.025,1.13),(x+sign*.055,.065,1.19),.023,5,end_radius=.003)
    weapon(b,arm,'goblin')


def build_witch(b, arm):
    """A hunch-backed green-skinned witch: black robes, a bent pointed hat, a gnarled wooden staff she leans on.
    The hunch is posture (spine bones in every clip) plus a hump on the back; she is modelled upright in the rest pose."""
    boots(b)
    # long skirt on the hips bone, a violet hem band; the boots peek out under it
    b.loft('hips', 'robe', [(0, 0, 1.06, .20, .15), (0, 0, .82, .27, .21), (0, 0, .50, .34, .27), (0, 0, .20, .41, .33)], 9)
    b.loft('hips', 'robe_trim', [(0, 0, .20, .41, .33), (0, 0, .13, .42, .34)], 9)
    # robed torso with a rounded hump, and a stiff shawl collar
    b.loft('spine1', 'robe', [(0, 0, 1.02, .17, .12), (0, 0, 1.18, .19, .13), (0, 0, 1.32, .22, .14)], 8)
    b.loft('spine2', 'robe', [(0, 0, 1.30, .22, .14), (0, .015, 1.42, .24, .155), (0, 0, 1.51, .17, .11)], 8)
    bulb(b, 'spine2', 'robe', (0, .115, 1.40), (.17, .15, .16), 8)                 # the hump
    b.loft('spine2', 'robe_trim', [(0, 0, 1.45, .30, .20), (0, 0, 1.52, .22, .15)], 8)
    b.loft('hips', 'robe_trim', [(0, 0, 1.04, .205, .155), (0, 0, 1.00, .21, .16)], 9)   # a sash
    rod(b, 'neck', 'witch_skin', (0, 0, 1.50), (0, -.03, 1.63), .042)
    # head: pointed chin, long hooked nose with a wart, yellow eyes, wild grey hair under the hat
    b.loft('head', 'witch_skin', [(0, -.02, 1.60, .06, .06), (0, -.02, 1.66, .10, .09), (0, -.015, 1.76, .105, .095),
                                   (0, .01, 1.83, .08, .075), (0, .02, 1.87, .04, .04)], 7)
    rod(b, 'head', 'witch_skin', (0, -.075, 1.625), (0, -.13, 1.575), .036, 5, end_radius=.012)          # chin
    rod(b, 'head', 'witch_skin', (0, -.085, 1.74), (0, -.205, 1.68), .034, 5, end_radius=.016)           # nose
    rod(b, 'head', 'witch_skin', (0, -.205, 1.68), (0, -.215, 1.61), .018, 5, end_radius=.005)           # hooked tip
    bulb(b, 'head', 'witch_dark', (.02, -.15, 1.715), (.013, .013, .013), 5)                              # wart
    for sign in (-1, 1):
        x = sign * .05
        panel(b, 'head', 'goblin_eye', [(x - sign * .022, -.112, 1.765), (x + sign * .02, -.112, 1.76),
                                        (x + sign * .016, -.112, 1.728), (x - sign * .014, -.112, 1.735)])
        rod(b, 'head', 'witch_dark', (sign * .012, -.116, 1.785), (sign * .10, -.098, 1.80), .017, 5)  # brows
        rod(b, 'head', 'hair', (sign * .105, .03, 1.82), (sign * .17, .08, 1.54), .015, 4, end_radius=.004)
        rod(b, 'head', 'hair', (sign * .09, .06, 1.80), (sign * .13, .13, 1.58), .013, 4, end_radius=.004)
    panel(b, 'head', 'witch_dark', [(-.04, -.12, 1.675), (.04, -.12, 1.675), (.03, -.125, 1.655), (-.03, -.125, 1.655)])
    # the pointed hat: a wide brim, a cone that bends back at the tip, a violet band and a brass buckle
    b.loft('head', 'robe', [(0, 0, 1.845, .33, .33), (0, 0, 1.87, .27, .27)], 10)
    b.loft('head', 'robe', [(0, .005, 1.86, .175, .175), (0, .03, 2.02, .135, .135), (0, .07, 2.17, .09, .09),
                            (0, .14, 2.29, .05, .05), (0, .24, 2.35, .012, .012)], 8)
    b.loft('head', 'hat_band', [(0, .005, 1.875, .178, .178), (0, .01, 1.925, .17, .17)], 8)
    panel(b, 'head', 'brass', [(-.04, -.178, 1.88), (.04, -.178, 1.88), (.04, -.18, 1.92), (-.04, -.18, 1.92)])
    for side, sign in (("L", 1), ("R", -1)):
        x = sign * .27
        bulb(b, 'clavicle_' + side, 'robe', (x, 0, 1.44), (.09, .085, .08))
        b.loft('upper_arm_' + side, 'robe', [(x, 0, 1.46, .075, .075), (x, 0, 1.30, .085, .085), (x, 0, 1.16, .095, .095)], 7)
        b.loft('forearm_' + side, 'robe', [(x, 0, 1.16, .095, .095), (x, 0, 1.00, .115, .11), (x, 0, .89, .13, .12)], 7)
        b.loft('forearm_' + side, 'robe_trim', [(x, 0, .89, .13, .12), (x, 0, .85, .135, .125)], 7)
        bulb(b, 'hand_' + side, 'witch_skin', (x, -.006, .79), (.04, .034, .07), 6)
        for off in (-.026, -.009, .009, .026):                      # long, bony fingers
            rod(b, 'hand_' + side, 'witch_skin', (x + off, -.012, .76), (x + off * 1.3, -.022, .64), .011, 4, end_radius=.006)
    # the staff: a gnarled wooden walking staff through the right fist. Its shaft runs along the hand's +Y in the rest
    # pose, so with the forearm bent about 90 degrees it stands upright (top above the hand, foot on the ground).
    x, z, y0 = -.27, .79, -.006
    top, foot = y0 - .62, y0 + .98
    knots = [(foot, 0.0), (y0 + .5, .012), (y0 + .1, -.01), (y0 - .25, .01), (top, 0.0)]
    for (ya, xa), (yb, xb) in zip(knots, knots[1:]):
        rod(b, 'hand_R', 'wood', (x + xa, ya, z), (x + xb, yb, z), .026, 5)
    rod(b, 'hand_R', 'wood', (x, top, z), (x + .01, top - .06, z + .09), .024, 5, end_radius=.018)       # the crook
    rod(b, 'hand_R', 'wood', (x + .01, top - .06, z + .09), (x + .005, top - .17, z + .13), .018, 5, end_radius=.008)
    bulb(b, 'hand_R', 'wood', (x, foot - .02, z), (.04, .05, .04), 5)                                     # knob at the foot
    rod(b, 'hand_R', 'leather_dark', (x, y0 - .07, z), (x, y0 + .08, z), .03, 6)                          # leather grip wrap


def build_skeleton(b,arm):
    # Weathered olive bones, brown boots and shorts: source Skeleton/Idle.png.
    boots(b)
    for side,sign in (("L",1),("R",-1)):
        x=sign*.10
        bulb(b,'thigh_'+side,'bone_light',(x,0,.87),(.047,.046,.056))
        rod(b,'thigh_'+side,'bone',(x,0,.86),(x,0,.54),.026,7,end_radius=.024)
        bulb(b,'shin_'+side,'bone_light',(x,-.004,.50),(.041,.044,.043))
        rod(b,'shin_'+side,'bone',(x-sign*.015,0,.47),(x-sign*.012,0,.14),.020,6,end_radius=.014)
        rod(b,'shin_'+side,'bone_shadow',(x+sign*.023,.015,.47),(x+sign*.020,.012,.14),.013,5,end_radius=.011)
    b.loft('hips','leather',[(0,0,.85,.16,.11),(0,0,.99,.17,.115),(0,0,1.03,.14,.10)],7)
    panel(b,'hips','leather_dark',[(-.16,-.115,.94),(.16,-.115,.94),(.14,-.115,.76),(.055,-.115,.79),(0,-.115,.86),(-.08,-.115,.79),(-.14,-.115,.84)])
    b.loft('hips','iron_dark',[(0,0,1.00,.15,.11),(0,0,1.035,.15,.11)],8)
    panel(b,'hips','iron',[(-.028,-.122,1.00),(.028,-.122,1.00),(.028,-.122,1.055),(-.028,-.122,1.055)])
    # Hollow ribcage and separated vertebrae rather than a solid humanoid torso.
    for z in (1.045,1.10,1.155,1.21,1.265,1.32,1.375,1.43):
        bone='spine1' if z<1.26 else 'spine2'
        bulb(b,bone,'bone_light',(0,.065,z),(.043,.040,.024),6)
    for z,width in ((1.16,.12),(1.22,.165),(1.28,.19),(1.34,.20),(1.40,.18)):
        bone='spine1' if z<1.26 else 'spine2'
        for sign in (-1,1):
            points=[(sign*.012,-.11,z-.025),(sign*width*.65,-.105,z-.035),(sign*width,-.02,z),(sign*width*.75,.075,z+.018),(0,.085,z+.025)]
            for a,c in zip(points,points[1:]):rod(b,bone,'bone',a,c,.015,5)
    rod(b,'spine1','bone_light',(0,-.108,1.17),(0,-.11,1.29),.021,6)
    rod(b,'spine2','bone_light',(0,-.11,1.28),(0,-.105,1.44),.022,6)
    for sign in (-1,1):
        rod(b,'spine2','bone_light',(0,0,1.46),(sign*.24,0,1.43),.026,6)
    # A single diagonal leather strap from left shoulder to opposite waist.
    rod(b,'spine2','leather',( .14,-.14,1.46),(.075,-.155,1.27),.022,4)
    rod(b,'spine1','leather',(.075,-.155,1.27),(-.055,-.125,1.03),.023,4)
    rod(b,'neck','bone',(0,.015,1.47),(0,0,1.64),.031,6)
    # Skull, deep sockets and separated tooth/jaw row.
    b.loft('head','bone',[(0,-.005,1.64,.075,.065),(0,-.005,1.70,.115,.095),(0,0,1.81,.125,.115),(0,.012,1.88,.10,.10),(0,.015,1.92,.06,.06)],8)
    for sign in (-1,1):
        x=sign*.055
        panel(b,'head','eye',[(x-sign*.040,-.111,1.81),(x+sign*.037,-.108,1.81),(x+sign*.029,-.119,1.75),(x-sign*.032,-.123,1.75)])
        rod(b,'head','bone_light',(sign*.018,-.12,1.82),(sign*.103,-.095,1.825),.020,5)
        bulb(b,'head','bone_light',(sign*.095,-.08,1.715),(.027,.025,.034),6)
    panel(b,'head','eye',[(-.014,-.116,1.75),(.014,-.116,1.75),(.027,-.111,1.707),(-.025,-.111,1.707)])
    panel(b,'head','eye',[(-.070,-.099,1.69),(.070,-.099,1.69),(.061,-.104,1.653),(-.059,-.104,1.653)])
    for x in (-.051,-.026,0,.026,.051):
        b.loft('head','tooth',[(x,-.107,1.658,.009,.009),(x,-.107,1.682,.009,.009)],box=True)
    b.loft('head','bone_light',[(0,0,1.625,.065,.061),(0,-.025,1.651,.082,.075)],7)
    # Gray open-faced skullcap, with a small squared crown like the sprite.
    b.loft('head','iron',[(0,.005,1.835,.13,.12),(0,.01,1.92,.115,.108),(0,.015,1.965,.055,.065)],8)
    b.loft('head','iron_edge',[(0,0,1.825,.132,.123),(0,0,1.85,.132,.123)],8)
    for side,sign in (("L",1),("R",-1)):
        x=sign*.27
        bulb(b,'clavicle_'+side,'bone_light',(x,0,1.44),(.042,.046,.043))
        rod(b,'upper_arm_'+side,'bone',(x,0,1.41),(x,0,1.19),.023,6)
        bulb(b,'forearm_'+side,'bone_light',(x,0,1.15),(.035,.034,.037))
        for off in (-.018,.018):rod(b,'forearm_'+side,'bone',(x+off,0,1.12),(x+off*.6,0,.88),.013,5)
        bulb(b,'hand_'+side,'bone_light',(x,-.005,.845),(.032,.026,.038),6)
        for off in (-.025,-.008,.009,.025):
            rod(b,'hand_'+side,'bone',(x+off,-.012,.825),(x+off,-.017,.754),.008,4)
    # Broad gray shield, a rim, raised boss and the source sprite's central dark motif.
    cx,cy,cz=.29,-.07,1.06
    b.loft('forearm_L','iron_dark',[(cx,cy+.025,cz,.19,.30),(cx,cy-.025,cz,.19,.30)],10,axis='Y')
    b.loft('forearm_L','iron',[(cx,cy-.028,cz,.167,.275),(cx,cy-.045,cz,.167,.275)],10,axis='Y')
    bulb(b,'forearm_L','iron_edge',(cx,cy-.064,cz),(.043,.032,.045),6)
    panel(b,'forearm_L','iron_dark',[(cx-.018,cy-.049,cz+.12),(cx+.018,cy-.049,cz+.12),(cx+.018,cy-.049,cz-.10),(cx-.018,cy-.049,cz-.10)])
    weapon(b,arm,'skeleton')


def validate_mesh(body,arm):
    assert all(v.groups for v in body.data.vertices), 'Unweighted monster vertices'
    assert all(g.name in arm.data.bones for g in body.vertex_groups), 'Unknown deform group'
    assert all(math.isfinite(c) for v in body.data.vertices for c in v.co), 'Non-finite geometry'
    assert all(not p.use_smooth for p in body.data.polygons), 'Style must stay flat shaded'
    assert all(p.area>1e-10 for p in body.data.polygons), 'Degenerate monster faces'
    print('MONSTER_GEOMETRY_PASS',body.name,'vertices',len(body.data.vertices),'triangles',h.count_tris(body),'bones',len(arm.data.bones))


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    out=args[0] if args else os.path.join(os.path.dirname(__file__),'../godot/models')
    model=args[1] if len(args)>1 else 'goblin'
    assert model in ('goblin','skeleton','witch')
    os.makedirs(out,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm=h.build_armature();b=h.Builder()
    {'goblin':build_goblin,'skeleton':build_skeleton,'witch':build_witch}[model](b,arm)
    body=h.make_object(model,b,arm)
    h.make_actions(arm,model,h.build_library(model))
    # Goblins are smaller, while their export keeps the same named connected rig.
    arm.scale={'goblin':(.70,)*3,'witch':(.84,)*3}.get(model,(1,1,1))
    validate_mesh(body,arm)
    h.export([arm,body],os.path.join(out,model+'.glb'),True)
    h.record_clip_info(out,model,arm)
    arm.animation_data.action=bpy.data.actions['Idle'];bpy.context.scene.frame_set(1)
    arm.show_in_front=True;arm.data.display_type='STICK'
    bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);bpy.context.view_layer.objects.active=arm
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_distance=3.1
                area.spaces.active.region_3d.view_location=(0,0,.7 if model=='goblin' else 1)
                area.spaces.active.shading.type='MATERIAL'
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__),model+'.blend'))
    print('BUILD_OK',model)


if __name__=='__main__':
    main()
