"""Dazed Plumbing -- Blender art for the six machines that still had flat stand-in art, in DazedPower's style.

Machines (dazedplumb_01, facings E, S, W, N consecutive, one tile each, no states):
    main 232-235 (water main)       fuelhand 236-239 (hand fuel pump)    fuelelec 240-243 (electric fuel pump)
    digester 244-247 (biogas)       well 248-251 (drilled well)          smoker 252-255 (propane drum smoker)

It loads dz2.py (and through it dz_render.py) from its own folder as a library, so camera, lights, materials,
wear and the 2:1 ortho tile camera are exactly DazedPower's. Run with Blender 4.2+ or the bpy module:

    blender -b --factory-startup -P tools/blender/dup_machines_render.py -- <out dir> [all|cells|icons|<machine> ...]
    python  tools/blender/dup_machines_render.py -- <out dir> all            (with `pip install bpy`)

Icon-only: pipesection (Item_DazedPipeSection, a threaded steel pipe length with a coupling).

Raw 256x512 cells land in <out>/cells/<index>.png and 256x256 icon renders in <out>/icons/Item_<Name>.png.
Then grade and shrink them exactly like DazedPower (grade_all.py + import_art.py):

    python3 tools/blender/dup_machines_post.py <out dir> <final dir>

which writes <final dir>/cells/<index>.png (128x256) and <final dir>/icons/Item_*.png (32x32).
"""
import os, sys, math, random, time

_ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
_OUT_DIR = os.path.abspath(_ARGS[0] if _ARGS else "dup_machines_out")
_JOBS = _ARGS[1:] or ["all"]
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], "--", _OUT_DIR, "_library"]          # dz2/dz_render read their own args; "_library" runs no job
__file__ = os.path.join(_HERE, "dz2.py")
exec(compile(open(__file__).read(), __file__, "exec"))         # defines mat, box, cyl, tube, P(), tile_camera, ...
__file__ = os.path.join(_HERE, "dup_machines_render.py")
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

# Ground contact: a second, quick pass renders only the soft sky-occlusion under the machine onto a shadow catcher
# exactly the machine's own square (1x1), with the machine itself held out and the key and rim suns off. It is saved
# as <index>_s.png and laid under the cell by dup_machines_post.py: a grounded contact shadow, never a hard cast
# shadow (DazedPower's sprites have none, and nothing spills onto the neighbours).
CONTACT_SHADOW = True
CONTACT_SAMPLES = 48


def contact_plane():
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    o = obj(bm, mat("#808080", 1.0, dirt=0, wear=False), name="contact")
    o.is_shadow_catcher = True; o.hide_render = True
    return o


def render_contact(path, plane):
    suns = [bpy.data.objects[n] for n in ("Key", "Rim")]
    parts = [o for o in MODEL.objects if o.type == "MESH" and o is not plane]
    keep = scene.cycles.samples
    for o in suns: o.hide_render = True
    for o in parts: o.is_holdout = True
    plane.hide_render = False; scene.cycles.samples = CONTACT_SAMPLES
    try: render(path)
    finally:
        for o in suns: o.hide_render = False
        for o in parts: o.is_holdout = False
        plane.hide_render = True; scene.cycles.samples = keep


# ------------------------------------------------------------------ shared bits
def pad(w, d, h=0.07, at=(0, 0), col="#8e8a83"):
    """A weathered concrete pad with a chamfered edge."""
    box((w, d, h), (at[0], at[1], h / 2), mat(col, 0.95, var=0.22, dirt=0.4), bevel=0.012)
    return h


def flange(c, r, t, m, axis="Z", bolts=6):
    c = Vector(c); cyl(r, t, c, m, axis=axis, segs=24)
    nut = mat("#4a4b4c", 0.55, 0.5, rust=0.3, dirt=0.2)
    for i in range(bolts):
        a = 2 * math.pi * (i + 0.5) / bolts
        if axis == "Z": off = Vector((math.cos(a), math.sin(a), 0))
        elif axis == "X": off = Vector((0, math.cos(a), math.sin(a)))
        else: off = Vector((math.cos(a), 0, math.sin(a)))
        cyl(0.009, t + 0.012, c + off * r * 0.78, nut, axis=axis, segs=6)


def handwheel(c, r, m, axis="Z", spokes=4):
    c = Vector(c)
    torus(r, r * 0.13, c, m, axis=axis, seg=32, rseg=8)
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        if axis == "Z": e = Vector((math.cos(a), math.sin(a), 0))
        elif axis == "X": e = Vector((0, math.cos(a), math.sin(a)))
        else: e = Vector((math.cos(a), 0, math.sin(a)))
        tube(c, c + e * r, r * 0.08, m, 8)
    cyl(r * 0.22, r * 0.35, c, m, axis=axis, segs=12)


def hose_loop(pts, r=0.016):
    path(pts, r, mat("#1f1f21", 0.75, var=0.08, dirt=0.25), segs=12)


def nozzle(c, rot, col="#3f3f40"):
    """A fuel nozzle: grip body, trigger guard and spout, built along -Y before `rot`."""
    R = M(c, rot); body = mat(col, 0.45, 0.6, var=0.1, dirt=0.3)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.035, 0.11, 0.05), verts=b.verts)
    obj(b, body, R, bevel=0.01)
    b = bmesh.new(); bmesh.ops.create_cone(b, cap_ends=True, cap_tris=False, segments=10, radius1=0.011, radius2=0.009, depth=0.12)
    obj(b, mat("#8f9194", 0.4, 0.7, dirt=0.2), R @ M((0, -0.1, -0.025), (70, 0, 0)), smooth=True)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.03, 0.07, 0.012), verts=b.verts)
    obj(b, mat("#2a2a2b", 0.6, dirt=0.2), R @ M((0, 0.0, -0.045)), bevel=0.004)


def wood_post(x, y, h, w=0.07):
    box((w, w, h), (x, y, h / 2), mat("#7d6a55", 0.9, var=0.22, dirt=0.45), bevel=0.006)


# ------------------------------------------------------------------ 232 water main
def m_water_main():
    """A municipal service riser: two ductile-iron legs up out of a concrete pad, a flanged gate valve with a
    rising stem and handwheel, a curb-stop valve box and a brass hose bib."""
    p = P()
    pad(0.66, 0.5, 0.08, at=(0, 0.04))
    duct = mat("#4b5f78", 0.6, 0.35, var=0.16, rust=0.32, dirt=0.4)        # faded utility blue, rusting through
    zt = 0.46
    for x in (-0.2, 0.2):
        flange((x, 0.06, 0.1), 0.065, 0.02, duct)
        cyl(0.042, zt - 0.1, (x, 0.06, 0.1 + (zt - 0.1) / 2), duct, segs=20)
        ball(0.05, (x, 0.06, zt), duct)
    tube((-0.2, 0.06, zt), (-0.085, 0.06, zt), 0.042, duct, 20)
    tube((0.085, 0.06, zt), (0.2, 0.06, zt), 0.042, duct, 20)
    # gate valve in the middle of the run
    for x in (-0.07, 0.07): flange((x, 0.06, zt), 0.068, 0.022, duct, axis="X")
    ball(0.07, (0, 0.06, zt), duct, scale=(0.95, 0.8, 1.0))
    box((0.07, 0.07, 0.14), (0, 0.06, zt + 0.1), duct, bevel=0.014)                     # bonnet
    cyl(0.05, 0.02, (0, 0.06, zt + 0.18), duct, segs=6)
    for x in (-0.03, 0.03): tube((x, 0.06, zt + 0.18), (x, 0.06, zt + 0.27), 0.008, p["steel_dark"], 8)  # yoke
    cyl(0.009, 0.16, (0, 0.06, zt + 0.25), mat("#9a9c98", 0.35, 0.8, dirt=0.15), segs=10)       # rising stem
    handwheel((0, 0.06, zt + 0.3), 0.075, mat("#8b3328", 0.55, 0.3, var=0.12, rust=0.25, dirt=0.3))
    # brass hose bib on the right leg, facing the viewer
    brass = mat("#a88a4c", 0.38, 0.75, dirt=0.3)
    tube((0.2, 0.06, 0.26), (0.2, -0.04, 0.26), 0.016, brass, 10)
    tube((0.2, -0.04, 0.26), (0.2, -0.06, 0.22), 0.016, brass, 10)
    box((0.06, 0.012, 0.012), (0.2, -0.04, 0.29), mat("#8b3328", 0.6))
    # curb-stop valve box lid in the pad's front corner
    cyl(0.075, 0.02, (-0.17, -0.12, 0.085), mat("#3a3a3b", 0.7, 0.4, rust=0.4, dirt=0.4), segs=24)
    cyl(0.03, 0.006, (-0.17, -0.12, 0.096), mat("#2a2a2b", 0.7, 0.3), segs=16)
    # utility tag on a wire
    box((0.05, 0.004, 0.035), (-0.2, 0.012, 0.33), mat("#c9c1a6", 0.8, dirt=0.3))


# ------------------------------------------------------------------ 236 hand fuel pump
def m_fuel_hand():
    """A cast-iron rotary hand pump on a pipe pedestal: crank, spout, rubber hose and nozzle on a hook."""
    p = P()
    pad(0.46, 0.46, 0.06, at=(0, 0.04))
    red = mat("#8c3a2e", 0.55, 0.25, var=0.18, rust=0.4, dirt=0.4)      # old barn-red paint gone chalky
    iron = mat("#38393a", 0.6, 0.4, var=0.12, rust=0.35, dirt=0.3)
    flange((0, 0.06, 0.07), 0.085, 0.02, iron, bolts=4)
    cyl(0.032, 0.6, (0, 0.06, 0.37), p["galv"], segs=18)
    cyl(0.05, 0.05, (0, 0.06, 0.66), iron, segs=18)
    # rotary pump body: a round casing facing +X
    cyl(0.11, 0.1, (0, 0.06, 0.76), red, axis="X", segs=32)
    for s in (-1, 1): cyl(0.115, 0.014, (s * 0.055, 0.06, 0.76), red, axis="X", segs=32)
    for i in range(6):
        a = 2 * math.pi * i / 6
        cyl(0.007, 0.13, (0, 0.06 + math.cos(a) * 0.095, 0.76 + math.sin(a) * 0.095), iron, axis="X", segs=6)
    cyl(0.03, 0.04, (0.07, 0.06, 0.76), iron, axis="X", segs=14)
    # crank on the +X side with a wooden grip
    tube((0.09, 0.06, 0.76), (0.09, -0.06, 0.92), 0.012, iron, 10)
    cyl(0.017, 0.08, (0.13, -0.06, 0.92), mat("#6b5039", 0.8, var=0.2, dirt=0.3), axis="X", segs=12)
    # outlet spout to the front and the hose
    tube((0, -0.04, 0.8), (0, -0.12, 0.8), 0.02, red, 12); ball(0.022, (0, -0.12, 0.8), red)
    tube((0, -0.12, 0.8), (0, -0.12, 0.74), 0.02, red, 12)
    hose_loop([(0, -0.12, 0.73), (-0.04, -0.17, 0.55), (-0.1, -0.16, 0.3), (-0.13, -0.08, 0.22), (-0.11, 0.0, 0.34),
               (-0.075, 0.03, 0.52)])
    box((0.03, 0.04, 0.012), (-0.045, 0.04, 0.56), iron)                              # hook on the post
    nozzle((-0.075, -0.0, 0.53), (15, 0, 25))
    # inlet from the line
    tube((0, 0.06, 0.08), (0, 0.06, GROUND_Z), PIPE_R * 0.8, iron, 14)


# ------------------------------------------------------------------ 240 electric fuel pump
def m_fuel_elec():
    """A farm transfer pump (12V/120V motor on a cast pump) and a mechanical meter on a steel stand,
    nozzle in its holster, switch box and cable."""
    p = P()
    pad(0.5, 0.46, 0.06, at=(0, 0.04))
    stand_m = mat("#4e5357", 0.5, 0.45, var=0.12, rust=0.25, dirt=0.35)
    green = mat("#4d5e48", 0.5, 0.25, var=0.14, rust=0.2, dirt=0.35)        # faded implement green
    for x in (-0.12, 0.12): box((0.04, 0.04, 0.62), (x, 0.08, 0.37), stand_m, bevel=0.005)
    box((0.3, 0.2, 0.025), (0, 0.06, 0.68), stand_m, bevel=0.005)
    box((0.3, 0.04, 0.03), (0, 0.08, 0.2), stand_m, bevel=0.004)
    # motor (finned) lying along X, pump head at -X
    cyl(0.075, 0.18, (0.05, 0.06, 0.77), green, axis="X", segs=28)
    for i in range(7): cyl(0.079, 0.008, (-0.02 + i * 0.024, 0.06, 0.77), green, axis="X", segs=28)
    cyl(0.07, 0.02, (0.15, 0.06, 0.77), mat("#2e3330", 0.5, 0.4), axis="X", segs=24)
    box((0.1, 0.12, 0.13), (-0.09, 0.06, 0.765), mat("#55585a", 0.45, 0.6, rust=0.2, dirt=0.35), bevel=0.018)
    box((0.07, 0.06, 0.05), (0.06, 0.06, 0.865), green, bevel=0.01)                  # switch housing
    box((0.025, 0.012, 0.02), (0.06, 0.025, 0.87), mat("#2a2a2b", 0.5))
    # meter on the outlet, facing the front
    tube((-0.09, 0.0, 0.76), (-0.09, -0.06, 0.76), 0.022, p["steel_dark"], 12)
    box((0.13, 0.08, 0.12), (-0.09, -0.1, 0.76), mat("#6d6a5c", 0.5, 0.3, var=0.12, rust=0.15, dirt=0.35), bevel=0.02)
    box((0.08, 0.006, 0.035), (-0.09, -0.142, 0.785), mat("#d9d2bd", 0.4, dirt=0.15))
    box((0.07, 0.007, 0.012), (-0.09, -0.144, 0.79), mat("#2a2a2a", 0.4, dirt=0))
    # hose from under the meter, a loop to the holster on the right leg
    tube((-0.09, -0.1, 0.7), (-0.09, -0.1, 0.66), 0.018, p["steel_dark"], 12)
    hose_loop([(-0.09, -0.1, 0.66), (-0.1, -0.16, 0.45), (-0.02, -0.2, 0.24), (0.12, -0.14, 0.2), (0.18, -0.06, 0.34),
               (0.17, 0.0, 0.46)])
    box((0.05, 0.05, 0.08), (0.165, 0.045, 0.5), stand_m, bevel=0.006)                 # holster
    nozzle((0.165, 0.0, 0.52), (15, 0, -60))
    # inlet riser and the power cable down the left leg
    tube((-0.12, 0.06, 0.73), (-0.12, 0.06, GROUND_Z), 0.02, p["galv"], 12)
    path([(0.11, 0.06, 0.86), (0.13, 0.12, 0.7), (0.13, 0.12, 0.1), (0.16, 0.26, 0.03), (0.26, 0.42, 0.02)], 0.009, p["wire_k"])


# ------------------------------------------------------------------ 244 biogas digester
def m_digester():
    """A sun-faded poly tank on a pad: a capped feed pipe, a slurry spigot, and on top the gas take-off --
    ball valve, gauge and a black line down to the ground."""
    p = P()
    pad(0.86, 0.86, 0.07)
    poly = mat("#3f4a40", 0.7, 0.05, var=0.2, dirt=0.5)                   # dark green poly, chalked by sun
    cyl(0.36, 0.56, (0, 0.04, 0.35), poly, segs=48)
    ball(0.36, (0, 0.04, 0.63), poly, scale=(1, 1, 0.3))
    for z in (0.2, 0.36, 0.52): torus(0.36, 0.01, (0, 0.04, z), poly, seg=48)
    cyl(0.13, 0.05, (0.1, 0.1, 0.73), poly, segs=24)                        # manway
    cyl(0.14, 0.02, (0.1, 0.1, 0.76), mat("#2f3530", 0.7, dirt=0.3), segs=24)
    # feed pipe: wide PVC going in at the front, capped
    pvc = mat("#bdb8a8", 0.65, var=0.12, dirt=0.55)
    tube((-0.2, -0.22, 0.42), (-0.28, -0.38, 0.62), 0.065, pvc, 20)
    cyl(0.075, 0.05, (-0.285, -0.39, 0.64), pvc, segs=20, rot=(26, 0, -27))
    # slurry spigot low on the +X/-Y side with stains on the pad
    brass = mat("#9b8248", 0.4, 0.7, dirt=0.35)
    tube((0.24, -0.22, 0.18), (0.29, -0.27, 0.18), 0.02, brass, 10)
    tube((0.29, -0.27, 0.18), (0.29, -0.27, 0.13), 0.018, brass, 10)
    box((0.02, 0.06, 0.012), (0.29, -0.27, 0.21), mat("#8b3328", 0.6), rot=(0, 0, 45))
    cyl(0.07, 0.004, (0.3, -0.28, 0.072), mat("#3b3227", 0.95, dirt=0, wear=False), segs=20)
    # gas take-off: nipple, ball valve (yellow gas handle), gauge, line down the back
    galv = p["galv"]
    tube((-0.12, 0.1, 0.72), (-0.12, 0.1, 0.84), 0.016, galv, 10)
    ball(0.026, (-0.12, 0.1, 0.84), brass)
    box((0.07, 0.014, 0.012), (-0.09, 0.1, 0.87), mat("#c7a43a", 0.55, dirt=0.2))
    tube((-0.12, 0.1, 0.84), (-0.12, 0.22, 0.84), 0.014, galv, 10)
    tube((-0.12, 0.1, 0.86), (-0.12, 0.1, 0.92), 0.008, galv, 8)
    gauge((-0.12, 0.085, 0.95), (0, 0, 0), 0.035, 0.45)
    hose_loop([(-0.12, 0.22, 0.84), (-0.14, 0.38, 0.6), (-0.12, 0.42, 0.2), (-0.05, 0.4, 0.06), (0, 0.2, GROUND_Z)], 0.012)


# ------------------------------------------------------------------ 248 drilled well
def m_well():
    """A 6-inch steel well casing with a bolted sanitary cap, conduit to a pump control box on a treated post,
    and a well pressure tank beside it."""
    p = P()
    pad(0.5, 0.5, 0.06, at=(-0.08, -0.06))
    casing = mat("#55595c", 0.55, 0.55, var=0.14, rust=0.45, dirt=0.4)
    cyl(0.085, 0.42, (-0.1, -0.08, 0.27), casing, segs=28)
    cyl(0.1, 0.06, (-0.1, -0.08, 0.5), mat("#4a4d50", 0.5, 0.5, rust=0.3, dirt=0.3), segs=28)
    ball(0.1, (-0.1, -0.08, 0.53), mat("#4a4d50", 0.5, 0.5, rust=0.3, dirt=0.3), scale=(1, 1, 0.35))
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.4
        cyl(0.01, 0.04, (-0.1 + math.cos(a) * 0.092, -0.08 + math.sin(a) * 0.092, 0.5), p["steel_dark"], segs=6)
    cyl(0.012, 0.03, (-0.1, -0.08, 0.57), p["steel_dark"], segs=8)                        # vent
    # conduit to the control box on its post
    conduit = mat("#8d918f", 0.45, 0.4, dirt=0.3)
    path([(-0.06, -0.08, 0.53), (0.0, -0.06, 0.56), (0.12, 0.02, 0.56), (0.18, 0.12, 0.56)], 0.011, conduit)
    wood_post(0.22, 0.2, 0.95, 0.075)
    box((0.15, 0.08, 0.2), (0.2, 0.14, 0.62), mat("#80857f", 0.5, 0.35, var=0.1, rust=0.15, dirt=0.35), bevel=0.012)
    box((0.13, 0.006, 0.17), (0.2, 0.098, 0.62), mat("#868b85", 0.5, 0.3, dirt=0.3), bevel=0.003)
    box((0.04, 0.008, 0.02), (0.2, 0.093, 0.66), mat("#d6cfba", 0.6, dirt=0.15))
    lamp((0.25, 0.094, 0.68), False, r=0.009)
    path([(0.2, 0.15, 0.52), (0.24, 0.24, 0.3), (0.26, 0.3, 0.03), (0.3, 0.45, 0.02)], 0.009, p["wire_k"])
    # pressure tank, sun-faded blue, with the pressure switch and gauge on its tee
    blue = mat("#4d6880", 0.5, 0.25, var=0.12, rust=0.12, dirt=0.4)
    cyl(0.13, 0.4, (-0.22, 0.24, 0.25), blue, segs=32)
    ball(0.13, (-0.22, 0.24, 0.45), blue, scale=(1, 1, 0.45))
    cyl(0.11, 0.05, (-0.22, 0.24, 0.025), mat("#2c2d2f", 0.7, dirt=0.3), segs=24)
    galv = p["galv"]
    tube((-0.1, -0.08, 0.36), (-0.1, 0.1, 0.36), 0.014, galv, 10)
    tube((-0.1, 0.1, 0.36), (-0.12, 0.2, 0.36), 0.014, galv, 10)
    box((0.05, 0.05, 0.06), (-0.07, 0.1, 0.4), mat("#4f5052", 0.5, 0.3), bevel=0.008)       # pressure switch
    gauge((-0.12, 0.09, 0.42), (0, 0, 0), 0.025, 0.55)


# ------------------------------------------------------------------ 252 smoker
def m_smoker():
    """An upright drum smoker made from a 55-gallon drum: heat-black paint gone rusty and scorched, a hinged
    lid with a thermometer and a chimney, a fire door, and a propane burner fed from a brass valve."""
    p = P()
    WEAR["scorch"] = 0.15
    for (x, y) in ((-0.2, -0.2), (0.2, -0.2), (-0.2, 0.2), (0.2, 0.2)):
        box((0.04, 0.04, 0.1), (x, y, 0.05), p["steel_dark"], bevel=0.004)
    box((0.48, 0.04, 0.03), (0, -0.2, 0.09), p["steel_dark"]); box((0.48, 0.04, 0.03), (0, 0.2, 0.09), p["steel_dark"])
    drum = mat("#3e3c38", 0.75, 0.25, var=0.22, rust=0.22, dirt=0.35)
    cyl(0.28, 0.82, (0, 0, 0.51), drum, segs=40)
    for z in (0.37, 0.65): torus(0.28, 0.013, (0, 0, z), drum, seg=48)
    torus(0.282, 0.016, (0, 0, 0.11), drum, seg=48)
    # lid
    lid = mat("#33312e", 0.7, 0.3, var=0.2, rust=0.35, dirt=0.3)
    cyl(0.295, 0.04, (0, 0, 0.94), lid, segs=40)
    ball(0.29, (0, 0, 0.955), lid, scale=(1, 1, 0.12))
    path([(-0.1, -0.05, 0.98), (-0.08, -0.05, 1.03), (0.08, -0.05, 1.03), (0.1, -0.05, 0.98)], 0.01, p["steel"])
    # chimney toward the back with a rain cap
    stack = mat("#3a3936", 0.6, 0.4, var=0.15, rust=0.5, dirt=0.25)
    cyl(0.045, 0.34, (0.12, 0.14, 1.12), stack, segs=18)
    cyl(0.085, 0.012, (0.12, 0.14, 1.33), stack, segs=20); ball(0.085, (0.12, 0.14, 1.335), stack, scale=(1, 1, 0.35))
    for a in (0, 2.1, 4.2): tube((0.12 + 0.04 * math.cos(a), 0.14 + 0.04 * math.sin(a), 1.29), (0.12 + 0.05 * math.cos(a), 0.14 + 0.05 * math.sin(a), 1.33), 0.004, stack, 6)
    # lid thermometer facing the viewer
    gauge((0.05, -0.27, 0.86), (0, 0, 20), 0.032, 0.7, rim="#a9aaa6")
    # fire door low on the front with a turn handle
    door = mat("#2f2d2a", 0.7, 0.3, var=0.2, rust=0.4, dirt=0.4)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.18, 0.02, 0.13), verts=b.verts)
    obj(b, door, M((0.0, -0.283, 0.25)), bevel=0.006)
    cyl(0.012, 0.03, (0.06, -0.3, 0.25), p["steel"], axis="Y", segs=8)
    box((0.06, 0.012, 0.014), (0.06, -0.318, 0.25), p["steel"])
    for x in (-0.09, 0.09): cyl(0.006, 0.16, (x, -0.293, 0.25), p["steel_dark"], segs=8)
    # burner feed on the +X side: brass valve and a black gas line to the ground
    brass = mat("#a88a4c", 0.38, 0.75, dirt=0.3)
    tube((0.27, -0.06, 0.22), (0.35, -0.06, 0.22), 0.012, brass, 10)
    cyl(0.022, 0.05, (0.33, -0.06, 0.22), brass, axis="X", segs=6)
    box((0.012, 0.05, 0.012), (0.33, -0.08, 0.25), mat("#c7a43a", 0.55))
    hose_loop([(0.35, -0.06, 0.22), (0.39, -0.02, 0.15), (0.36, 0.12, 0.05), (0.2, 0.2, 0.025), (0.0, 0.0, GROUND_Z)], 0.011)
    # a little smoke from the chimney's cap? no: no state sprites, so it is drawn cold.
    WEAR["scorch"] = 0.0


# ------------------------------------------------------------------ icon-only items
def pipe_section_icon():
    """A length of weathered steel pipe: rust-mottled galvanised body, freshly cut threads at both ends and a
    threaded coupling screwed onto one of them."""
    galv = mat("#868a87", 0.6, 0.5, var=0.2, rust=0.6, dirt=0.45)
    thread = mat("#a9aca8", 0.38, 0.75, var=0.08, rust=0.05, dirt=0.15)
    L, r = 0.25, 0.068
    Z = r * 1.36                                                 # resting on the coupling
    tube((-L + 0.075, 0, Z), (L - 0.07, 0, Z), r, galv, 24)
    tube((-L, 0, Z), (-L + 0.075, 0, Z), r - 0.004, thread, 24)          # cut threads: a bright, ridged stub
    tube((L - 0.07, 0, Z), (L, 0, Z), r - 0.004, thread, 24)
    for i in range(7):
        torus(r - 0.003, 0.0045, (-L + 0.008 + i * 0.011, 0, Z), thread, axis="X", seg=24, rseg=6)
    for i in range(2):
        torus(r - 0.003, 0.0045, (L - 0.064 + i * 0.011, 0, Z), thread, axis="X", seg=24, rseg=6)
    cpl = mat("#6f7370", 0.5, 0.55, var=0.12, rust=0.3, dirt=0.3)    # coupling on the +X end
    cyl(r * 1.36, 0.1, (L, 0, Z), cpl, axis="X", segs=28)
    for x in (L - 0.05, L + 0.05): torus(r * 1.3, 0.006, (x, 0, Z), cpl, axis="X", seg=28, rseg=6)
    cyl(r * 0.9, 0.102, (L + 0.001, 0, Z), mat("#141414", 0.9, dirt=0, wear=False), axis="X", segs=24)   # bore
    cyl(r * 0.9, 0.004, (-L - 0.001, 0, Z), mat("#141414", 0.9, dirt=0, wear=False), axis="X", segs=24)


ICON_ONLY = [("pipesection", pipe_section_icon, "DazedPipeSection")]


MACHINES = [("main", 232, m_water_main, "DazedWaterMain"), ("fuelhand", 236, m_fuel_hand, "DazedFuelPumpHand"),
            ("fuelelec", 240, m_fuel_elec, "DazedFuelPumpElectric"), ("digester", 244, m_digester, "DazedDigester"),
            ("well", 248, m_well, "DazedDrilledWell"), ("smoker", 252, m_smoker, "DazedSmoker")]


def render_cells(names):
    tile_camera(); out = os.path.join(OUT, "cells"); os.makedirs(out, exist_ok=True)
    for name, base, fn, item in MACHINES:
        if names and name not in names: continue
        WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
        clear(); start = len(BUILT); fn(); root, fixed = make_root(start)
        plane = contact_plane() if CONTACT_SHADOW else None   # stays put: the square does not turn
        for col, (fname, deg) in enumerate(FACINGS):
            root.rotation_euler = fixed.rotation_euler = (0, 0, math.radians(deg))
            render(os.path.join(out, "%d.png" % (base + col)))
            if plane: render_contact(os.path.join(out, "%d_s.png" % (base + col)), plane)
        log("machine", name, base)


def render_item_icons(names):
    out = os.path.join(OUT, "icons")
    for name, base, fn, item in MACHINES:
        if names and name not in names: continue
        WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
        icon_shot("Item_" + item, fn, out)
        log("icon", item)
    for name, fn, item in ICON_ONLY:
        if names and name not in names: continue
        WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
        icon_shot("Item_" + item, fn, out)
        log("icon", item)


for job in _JOBS:
    t0 = time.time()
    names = [m[0] for m in MACHINES]
    if job == "all": render_cells(None); render_item_icons(None)
    elif job == "cells": render_cells(None)
    elif job == "icons": render_item_icons(None)
    elif job in names: render_cells([job]); render_item_icons([job])
    elif job in [i[0] for i in ICON_ONLY]: render_item_icons([job])
    elif job.startswith("cells:"): render_cells(job[6:].split(","))
    log("job", job, "took %.0fs" % (time.time() - t0))
