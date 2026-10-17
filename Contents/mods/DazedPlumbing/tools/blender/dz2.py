"""Dazed art in the new style: DazedPower and DazedPlumbing sprites, icons and masks, built on dz_render.py.

    blender -b --factory-startup -P dz2.py -- <out dir> <job> [job ...]
Jobs: dp:<family>|dp:all, pl:<family>|pl:all, icons:dp, icons:dp:<Item>[,<Item>], icons:pl, test. Cells land in
<out>/<mod>/<family>/<index>.png at 256x512. DZ_DEVICE=CUDA (or OPTIX, HIP, CPU...) picks the Cycles device.
"""
import os, sys, math, random, time
DZ_LIBRARY = True
_here = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(_here, "dz_render.py")).read())
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

# ------------------------------------------------------------------ shared helpers


def ensure_uv(bm):
    return bm.loops.layers.uv.verify()


def cells_mat(cols, rows, cracked=False, tint="#1d2f4d"):
    """Solar cells: a dark blue grid on the panel's own UVs, with optional shatter lines."""
    key = ("cells", cols, rows, cracked, tint, round(WEAR["rust"], 2))
    if key in MATS: return MATS[key]
    m = bpy.data.materials.new("cells%d" % len(MATS))
    try: m.use_nodes = True
    except Exception: pass
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (cols, rows, 1)
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
    br = nt.nodes.new("ShaderNodeTexBrick"); br.offset = 0.0; br.squash = 1.0
    nt.links.new(mp.outputs["Vector"], br.inputs["Vector"])
    br.inputs["Scale"].default_value = 1.0; br.inputs["Mortar Size"].default_value = 0.05
    br.inputs["Brick Width"].default_value = 1.0; br.inputs["Row Height"].default_value = 1.0
    base = lin(tint)
    br.inputs["Color1"].default_value = base; br.inputs["Color2"].default_value = shade(base, 1.18)
    br.inputs["Mortar"].default_value = lin("#8e98a6")
    c = br.outputs["Color"]
    if cracked:
        vo = nt.nodes.new("ShaderNodeTexVoronoi"); vo.feature = "DISTANCE_TO_EDGE"
        nt.links.new(tc.outputs["UV"], vo.inputs["Vector"]); vo.inputs["Scale"].default_value = 9.0
        cr = ramp(nt, vo.outputs["Distance"], 0.03, 0.0)
        c = mix(nt, math_node(nt, "MULTIPLY", cr, 0.85), c, lin("#c9d2da"))
        c = mix(nt, 0.35, c, lin("#1a1a1a"))
    nt.links.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.45 if not cracked else 0.6
    spec = bsdf_in(b, "Specular IOR Level", "Specular")
    if spec: spec.default_value = 0.25
    b.inputs["Metallic"].default_value = 0.25
    MATS[key] = m
    return m


def uv_quad(w, l, m, matrix):
    """A flat UV-mapped rectangle w (X) by l (Y), facing +Z before `matrix`."""
    bm = bmesh.new(); uv = ensure_uv(bm)
    vs = [bm.verts.new((x * w / 2, y * l / 2, 0)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    f = bm.faces.new(vs)
    for loop, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))): loop[uv].uv = (u, v)
    return obj(bm, m, matrix)


SNOW = None


def snow_mat():
    return mat("#eef1f4", 0.9, var=0.06, dirt=0.0, wear=False)


def module(center, w, l, tilt, tier, state, yaw=0.0, frame="#aeb3b8", cells=None, seed=1, crack=False, snow_amt=1.0):
    """One solar panel tilted `tilt` degrees, low edge toward -Y; snow and cracks follow the state."""
    R = M(center, (tilt, 0, yaw))
    fm = mat(frame, 0.4, 0.6, var=0.08, rust=0.3 if tier == "makeshift" else 0.0, dirt=0.3)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(w, l, 0.035), verts=b.verts)
    obj(b, fm, R, bevel=0.004)
    cols, rows = max(2, round(w / 0.15)), max(2, round(l / 0.15))
    uv_quad(w - 0.035, l - 0.035, cells_mat(cols, rows, crack, cells or "#1d2f4d"), R @ M((0, 0, 0.0185)))
    if state == "snow":
        rnd = random.Random(seed)
        b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0)
        for v in b.verts:
            v.co.x *= w * 0.98; v.co.y = v.co.y * l * 0.8 * snow_amt - l * 0.4 * (1 - snow_amt) + l * 0.1 * snow_amt; v.co.z = (v.co.z + 0.5) * (0.03 + rnd.uniform(0, 0.015))
        obj(b, snow_mat(), R @ M((0, 0, 0.018)), bevel=0.012)
    return R


def legs_to(R, pts, z0, m, r=0.018):
    """Posts from the ground up to points given in a panel's frame."""
    for p in pts:
        top = R @ Vector(p)
        tube((top.x, top.y, z0), (top.x, top.y, top.z), r, m, 8)


def cinder(c, rot=0):
    box((0.39, 0.19, 0.19), c, P()["cinder"], rot=(0, 0, rot), bevel=0.004)


def jbox(c, m=None):
    box((0.1, 0.05, 0.09), c, m or mat("#3a3c40", 0.5, 0.2), bevel=0.008)


# ------------------------------------------------------------------ solar arrays
TIER_FRAME = {"makeshift": "#9a9c98", "salvaged": "#b6b8b4", "workshop": "#c7cacd"}


def array_static(tier, state):
    p = P(); crack = state == "cracked"
    if tier == "makeshift":
        for x in (-0.3, 0.3): box((0.06, 0.8, 0.07), (x, 0, 0.035), p["wood"])
        R1 = module((-0.19, 0.0, 0.42), 0.36, 0.72, 30, tier, state, frame="#8f918c", cells="#22314a", seed=1, crack=crack)
        R2 = module((0.2, 0.02, 0.42), 0.36, 0.66, 30, tier, state, frame="#a3a29b", cells="#283a52", seed=2)
        for R in (R1, R2):
            legs_to(R, [(0, -0.3, -0.02)], 0.07, p["wood"], 0.02)
            legs_to(R, [(0, 0.3, -0.02)], 0.07, p["wood"], 0.02)
        cinder((0.0, -0.32, 0.17), 90); tape((0, -0.3, 0.27), 0.02, "X", 0.03)
        for x in (-0.19, 0.2): box((0.03, 0.12, 0.012), (x, 0.0, 0.43), mat("#a4a7a6", 0.45), rot=(30, 0, 0))
        path([(0.2, 0.32, 0.6), (0.3, 0.38, 0.3), (0.38, 0.42, 0.02)], 0.007, p["wire_k"])
    elif tier == "salvaged":
        rail = mat("#a7aaa8", 0.45, 0.5, rust=0.2)
        R = None
        for i, x in enumerate((-0.22, 0.22)):
            R = module((x, 0.0, 0.45), 0.42, 0.78, 32, tier, state, frame="#b0b2ae", cells="#22344f" if i else "#2a3b55", seed=3 + i,
                       crack=crack and i == 0)
        for x in (-0.38, 0.0, 0.38):
            tube((x, -0.3, 0.02), (x, -0.3, 0.26), 0.02, rail, 8); tube((x, 0.3, 0.02), (x, 0.3, 0.64), 0.02, rail, 8)
            tube((x, -0.3, 0.02), (x, 0.3, 0.02), 0.018, rail, 8)
        jbox((0.2, 0.36, 0.5)); path([(0.2, 0.36, 0.45), (0.25, 0.4, 0.05), (0.4, 0.42, 0.02)], 0.007, p["wire_k"])
    else:
        rail = mat("#bfc3c5", 0.4, 0.6, dirt=0.15)
        for x in (-0.4, 0.4):
            box((0.06, 0.06, 0.06), (x, -0.32, 0.03), p["concrete"]); box((0.06, 0.06, 0.06), (x, 0.32, 0.03), p["concrete"])
            tube((x, -0.32, 0.06), (x, -0.32, 0.28), 0.02, rail, 8); tube((x, 0.32, 0.06), (x, 0.32, 0.68), 0.022, rail, 8)
        for y, z in ((-0.32, 0.28), (0.32, 0.68)): box((0.88, 0.04, 0.04), (0, y, z), rail)
        for i, x in enumerate((-0.29, 0.0, 0.29)):
            module((x, 0.0, 0.5), 0.28, 0.84, 33, tier, state, frame="#c4c7ca", cells="#1b2c48", seed=6 + i, crack=crack and i == 1)
        jbox((0.3, 0.36, 0.42), mat("#d6d7d3", 0.45, 0.1, dirt=0.1))
        path([(0.3, 0.36, 0.37), (0.3, 0.4, 0.05), (0.42, 0.42, 0.02)], 0.008, p["wire_k"])


def array_tracker(tier, state):
    p = P(); crack = state == "cracked"
    tilt = 70 if (tier == "workshop" and state == "snow") else 35
    if tier == "makeshift":
        for rot in (0, 90): box((0.7, 0.08, 0.06), (0, 0, 0.03), p["wood"], rot=(0, 0, rot))
        box((0.1, 0.1, 1.1), (0, 0, 0.6), p["wood_grey"])
        for a in (0, 90, 180, 270):
            d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
            tube(d * 0.3 + Vector((0, 0, 0.06)), d * 0.05 + Vector((0, 0, 0.45)), 0.018, p["wood"], 4)
        cyl(0.04, 0.12, (0, 0, 1.18), p["steel_dark"])
        R = module((0, 0, 1.3), 0.72, 0.72, tilt, tier, state, frame="#8f918c", cells="#22314a", seed=11, crack=crack)
        box((0.12, 0.08, 0.07), (0.09, 0.05, 1.1), mat("#2b2c2f", 0.6), bevel=0.01); tape((0, 0, 1.0), 0.07, "Z", 0.04)
        path([(0.05, 0.0, 1.05), (0.06, 0.02, 0.4), (0.25, 0.25, 0.02)], 0.007, p["wire_k"])
    elif tier == "salvaged":
        cyl(0.2, 0.08, (0, 0, 0.04), p["concrete"], segs=20)
        cyl(0.045, 1.15, (0, 0, 0.62), p["galv"], segs=16)
        box((0.14, 0.12, 0.12), (0, 0, 1.2), mat("#5b6255", 0.5, 0.3, rust=0.3), bevel=0.01)
        R = module((0, 0, 1.36), 0.8, 0.8, tilt, tier, state, frame="#b0b2ae", cells="#26374f", seed=12, crack=crack)
        tube((0, 0, 1.24), tuple(R @ Vector((0, 0.3, -0.02))), 0.012, p["steel"])
        path([(0.05, 0, 1.1), (0.05, 0, 0.1), (0.25, 0.3, 0.02)], 0.007, p["wire_k"])
    else:
        box((0.5, 0.5, 0.1), (0, 0, 0.05), p["concrete"], bevel=0.01)
        cyl(0.07, 1.12, (0, 0, 0.66), mat("#c4c8ca", 0.4, 0.5), r2=0.055, segs=20)
        cyl(0.1, 0.12, (0, 0, 1.26), mat("#3d4144", 0.45, 0.4), axis="X", segs=20)
        box((0.12, 0.1, 0.1), (0.12, 0, 1.26), mat("#3d4144", 0.45, 0.4), bevel=0.01)
        R = module((0, 0, 1.38), 0.86, 0.86, tilt, tier, state, frame="#c4c7ca", cells="#1b2c48", seed=13, crack=crack, snow_amt=0.2)
        box((0.1, 0.06, 0.14), (0, -0.09, 0.42), mat("#d6d7d3", 0.45, 0.1, dirt=0.1), bevel=0.01)
        path([(0, -0.09, 0.35), (0, -0.14, 0.12), (0, -0.3, 0.1), (0, -0.4, 0.02)], 0.012, p["steel_dark"])


def array_xl(tier, state):
    """A 2x2-square table; pieces are cut from it by masks."""
    p = P(); crack = state == "cracked"
    tilt = 25.0; slope = 1.62
    if tier == "makeshift":
        frame = p["wood"]; nx, ny = 3, 2
        cols = ["#22314a", "#2a3b55", "#1f2d44", "#283a52", "#22314a", "#30405a"]
    elif tier == "salvaged":
        frame = mat("#a7aaa8", 0.45, 0.5, rust=0.2); nx, ny = 3, 2
        cols = ["#22344f", "#2a3b55", "#22344f", "#22344f", "#283a52", "#22344f"]
    else:
        frame = mat("#bfc3c5", 0.4, 0.6, dirt=0.15); nx, ny = 4, 2
        cols = ["#1b2c48"] * 8
    W = 1.82; pw, pl = W / nx - 0.03, slope / ny - 0.03
    base_z = 0.32
    Rt = M((0, 0, base_z + math.sin(math.radians(tilt)) * slope / 2), (tilt, 0, 0))
    k = 0
    for j in range(ny):
        for i in range(nx):
            c = Rt @ Vector((-W / 2 + (i + 0.5) * W / nx, -slope / 2 + (j + 0.5) * slope / ny, 0.03))
            module(tuple(c), pw, pl, tilt, tier, state, cells=cols[k % len(cols)], frame=TIER_FRAME[tier], seed=20 + k,
                   crack=crack and k == (2 if tier != "workshop" else 5))
            k += 1
    xs = (-0.85, 0.0, 0.85) if tier != "workshop" else (-0.88, -0.29, 0.29, 0.88)
    for x in xs:
        front, back = Rt @ Vector((x, -slope / 2 + 0.08, 0)), Rt @ Vector((x, slope / 2 - 0.08, 0))
        if tier == "makeshift":
            box((0.07, 0.07, front.z), (x, front.y, front.z / 2), frame); box((0.07, 0.07, back.z), (x, back.y, back.z / 2), frame)
            tube(front, back, 0.03, frame, 4)
            cinder((x, front.y, 0.1), 90)
        else:
            tube((x, front.y, 0), front, 0.022, frame, 8); tube((x, back.y, 0), back, 0.026, frame, 8)
            tube(front, back, 0.02, frame, 8)
            box((0.09, 0.09, 0.06), (x, front.y, 0.03), p["concrete"]); box((0.09, 0.09, 0.06), (x, back.y, 0.03), p["concrete"])
    jb = Rt @ Vector((0.6, slope / 2 - 0.05, -0.08))
    jbox(tuple(jb)); path([tuple(jb), (0.62, 0.95, 0.05), (0.8, 0.98, 0.02)], 0.008, p["wire_k"])


# ------------------------------------------------------------------ batteries
def car_battery(c, rot=0.0, worn=0.0):
    c = Vector(c)
    R = M(c, (0, 0, rot))
    case = mat("#2a2b2d", 0.6, var=0.12, dirt=0.25 + worn)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.25, 0.17, 0.18), verts=b.verts)
    obj(b, case, R @ M((0, 0, 0.09)), bevel=0.01)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.252, 0.172, 0.02), verts=b.verts)
    obj(b, mat("#55575b", 0.55, dirt=0.2), R @ M((0, 0, 0.175)), bevel=0.005)
    for x, col in ((-0.08, "#a8322a"), (0.08, "#1c1c1c")):
        b = bmesh.new(); bmesh.ops.create_cone(b, cap_ends=True, cap_tris=False, segments=10, radius1=0.016, radius2=0.016, depth=0.03)
        obj(b, mat(col, 0.5, dirt=0.1), R @ M((x, -0.045, 0.195)), smooth=True)
    b = bmesh.new(); bmesh.ops.create_cube(b, size=1.0); bmesh.ops.scale(b, vec=(0.06, 0.004, 0.035), verts=b.verts)
    obj(b, mat("#d0c9a8", 0.6, dirt=0.1), R @ M((0.04, -0.086, 0.12)))


def jumper(a, b, red=True):
    a, b = Vector(a), Vector(b); mid = (a + b) / 2 + Vector((0, 0, 0.05))
    path([a, mid, b], 0.006, P()["wire_r"] if red else P()["wire_k"])


def bank_ground(tier, n):
    p = P()
    if tier == "makeshift":
        wood = p["wood"]
        box((0.86, 0.5, 0.03), (0, 0, 0.05), wood)
        for x in (-0.42, 0.42): box((0.03, 0.5, 0.32), (x, 0, 0.2), wood)
        box((0.86, 0.03, 0.32), (0, 0.24, 0.2), wood)
        for z in (0.12, 0.28): box((0.86, 0.03, 0.08), (0, -0.24, z), wood)
        for x in (-0.3, 0.3): box((0.06, 0.06, 0.04), (x, 0, 0.02), p["wood_dark"])
        slots = [(-0.27, 0), (0.0, 0), (0.27, 0)]
        for i in range(n): car_battery((slots[i][0], 0.0, 0.065), random.Random(i).uniform(-6, 6), 0.15)
        for i in range(n - 1): jumper((slots[i][0] + 0.08, -0.045, 0.26), (slots[i + 1][0] - 0.08, -0.045, 0.26), i % 2 == 0)
        path([(0.42, 0.1, 0.3), (0.46, 0.3, 0.05), (0.46, 0.42, 0.02)], 0.008, p["wire_k"])
        if n == 0: box((0.3, 0.2, 0.01), (0.1, 0.05, 0.072), mat("#6d5a3f", 0.9))
    elif tier == "salvaged":
        steel = mat("#5f6c74", 0.5, 0.4, rust=0.25)
        for x in (-0.4, 0.4):
            for y in (-0.2, 0.2): box((0.035, 0.035, 0.78), (x, y, 0.39), steel)
        shelves = (0.06, 0.42)
        for z in shelves: box((0.84, 0.44, 0.025), (z * 0 + 0, 0, z), steel)
        box((0.84, 0.44, 0.02), (0, 0, 0.78), steel)
        slots = [(x, z) for z in shelves for x in (-0.27, 0.0, 0.27)]
        for i in range(n): car_battery((slots[i][0], 0.0, slots[i][1] + 0.013), random.Random(i + 9).uniform(-5, 5), 0.1)
        for i in range(n - 1):
            if slots[i][1] == slots[i + 1][1]: jumper((slots[i][0] + 0.08, -0.045, slots[i][1] + 0.21), (slots[i + 1][0] - 0.08, -0.045, slots[i][1] + 0.21), i % 2 == 0)
        box((0.12, 0.06, 0.1), (0.3, -0.2, 0.86), mat("#2c2d30", 0.5), bevel=0.01)
        path([(0.3, -0.2, 0.82), (0.42, 0.2, 0.6), (0.45, 0.4, 0.02)], 0.008, p["wire_k"])
    else:
        cab = mat("#7b8389", 0.45, 0.35, dirt=0.15)
        box((0.8, 0.48, 0.06), (0, 0, 0.03), mat("#2e3134", 0.5, 0.3))
        box((0.78, 0.46, 0.84), (0, 0, 0.48), cab, bevel=0.015)
        box((0.36, 0.01, 0.74), (-0.19, -0.233, 0.48), mat("#6f777d", 0.45, 0.35), bevel=0.004)
        box((0.36, 0.01, 0.74), (0.19, -0.233, 0.48), mat("#6f777d", 0.45, 0.35), bevel=0.004)
        for x in (-0.03, 0.03): box((0.012, 0.02, 0.12), (x, -0.245, 0.5), mat("#26282c", 0.5))
        for i in range(5): box((0.2, 0.008, 0.012), (-0.19, -0.24, 0.22 + i * 0.03), p["dark"])
        box((0.3, 0.008, 0.06), (0.19, -0.24, 0.8), mat("#1f2124", 0.5))
        for i in range(8):
            lamp((0.06 + i * 0.035, -0.246, 0.8), i < n, "#6fe07a", 0.009)
        box((0.09, 0.005, 0.05), (-0.19, -0.24, 0.8), mat("#d7b43c", 0.6))
        path([(0.39, 0.1, 0.8), (0.43, 0.3, 0.6), (0.44, 0.42, 0.02)], 0.01, p["wire_k"])


def bank_wall(tier, n):
    """Hangs with its back on the wall behind (+Y); front faces -Y."""
    p = P(); back = 0.5; z = 0.95
    if tier == "makeshift":
        box((0.7, 0.03, 0.36), (0, back - 0.015, z + 0.1), p["ply"])
        box((0.7, 0.28, 0.03), (0, back - 0.16, z - 0.08), p["wood"])
        for x in (-0.3, 0.3): box((0.03, 0.28, 0.2), (x, back - 0.16, z - 0.18), p["wood"], rot=(45, 0, 0))
        slots = [(-0.15, 0), (0.15, 0)]
        for i in range(n): car_battery((slots[i][0], back - 0.16, z - 0.065), random.Random(i).uniform(-6, 6), 0.15)
        if n == 2: jumper((-0.07, back - 0.2, z + 0.13), (0.07, back - 0.2, z + 0.13), True)
        box((0.7, 0.012, 0.025), (0, back - 0.29, z + 0.05), mat("#c86f24", 0.6))
        path([(0.32, back - 0.05, z + 0.25), (0.34, back - 0.03, 0.3), (0.34, back - 0.03, 0.02)], 0.008, p["wire_k"])
    elif tier == "salvaged":
        bx = mat("#6a7378", 0.5, 0.4, rust=0.25)
        box((0.82, 0.3, 0.42), (0, back - 0.15, z), bx, bevel=0.01)
        box((0.76, 0.01, 0.3), (0, back - 0.302, z + 0.02), p["dark"])
        slots = [-0.25, 0.0, 0.25]
        for i in range(n): car_battery((slots[i], back - 0.16, z - 0.19), random.Random(i).uniform(-4, 4), 0.1)
        box((0.82, 0.02, 0.06), (0, back - 0.31, z - 0.18), bx)
        path([(0.36, back - 0.1, z - 0.2), (0.38, back - 0.05, 0.3), (0.38, back - 0.03, 0.02)], 0.008, p["wire_k"])
    else:
        cab = mat("#7b8389", 0.45, 0.35, dirt=0.15)
        box((0.78, 0.26, 0.48), (0, back - 0.13, z), cab, bevel=0.012)
        box((0.72, 0.01, 0.4), (0, back - 0.265, z), mat("#6f777d", 0.45, 0.35), bevel=0.004)
        for i in range(5): box((0.3, 0.008, 0.012), (-0.15, back - 0.272, z - 0.12 + i * 0.03), p["dark"])
        for i in range(4): lamp((0.12 + i * 0.05, back - 0.274, z + 0.14), i < n, "#6fe07a", 0.01)
        box((0.1, 0.005, 0.05), (-0.2, back - 0.272, z + 0.14), mat("#d7b43c", 0.6))
        path([(0.39, back - 0.1, z - 0.2), (0.4, back - 0.04, 0.3), (0.4, back - 0.03, 0.02)], 0.01, p["wire_k"])


# ------------------------------------------------------------------ controllers, transformer, lamps, gauge
def controller(tier, state):
    p = P(); on = state == "on"
    lcd = glow("#9ee37d", 1.6) if on else mat("#0d1610", 0.3, dirt=0, wear=False)
    if tier == "makeshift":
        for x in (-0.28, 0.28):
            box((0.05, 0.05, 0.86), (x, 0.05, 0.43), p["wood"]); box((0.05, 0.32, 0.05), (x, 0.05, 0.025), p["wood"])
        box((0.66, 0.02, 0.56), (0, 0.04, 0.58), p["ply"])
        box((0.2, 0.06, 0.14), (-0.15, 0.0, 0.74), mat("#2f3a46", 0.5, 0.2), bevel=0.008)
        box((0.09, 0.01, 0.05), (-0.15, -0.031, 0.76), lcd)
        lamp((-0.08, -0.031, 0.71), on, "#6fe07a", 0.008)
        box((0.22, 0.09, 0.12), (0.12, -0.015, 0.48), mat("#6b6e70", 0.45, 0.5, rust=0.2), bevel=0.01)
        for i in range(5): box((0.008, 0.005, 0.08), (0.04 + i * 0.035, -0.062, 0.48), p["dark"])
        box((0.26, 0.04, 0.03), (0.08, 0.01, 0.74), p["steel"])
        for i in range(4): box((0.03, 0.05, 0.06), (-0.02 + i * 0.045, -0.01, 0.74), mat("#e2ded3", 0.55, dirt=0.15))
        for i, col in enumerate(("wire_r", "wire_k")):
            path([(-0.15 + i * 0.03, -0.02, 0.66), (-0.1 + i * 0.03, -0.04, 0.5), (0.04, -0.07, 0.48)], 0.006, p[col])
        path([(0.25, 0.0, 0.4), (0.3, 0.1, 0.1), (0.42, 0.3, 0.02)], 0.008, p["wire_k"])
        tape((-0.28, 0.05, 0.6), 0.04, "Z", 0.04)
    else:
        body = mat("#26282c", 0.5, 0.35, dirt=0.15)
        box((0.56, 0.32, 0.06), (0, 0, 0.03), p["concrete"])
        box((0.52, 0.28, 0.72), (0, 0, 0.42), body, bevel=0.015)
        box((0.3, 0.01, 0.18), (-0.07, -0.142, 0.56), mat("#16171a", 0.5))
        box((0.27, 0.008, 0.15), (-0.07, -0.147, 0.56), lcd)
        for i, col in enumerate(("#6fe07a", "#6fe07a", "#f2b63c", "#6fe07a", "#d84a3a")):
            lamp((-0.19 + i * 0.06, -0.147, 0.7), on and i in (0, 1, 3), col, 0.009)
        for i in range(5): box((0.05, 0.012, 0.025), (-0.19 + i * 0.06, -0.146, 0.44), mat("#3b3d42", 0.5))
        box((0.1, 0.01, 0.2), (0.18, -0.145, 0.5), mat("#d8d3c4", 0.6, dirt=0.15))
        cyl(0.03, 0.03, (0.18, -0.16, 0.53), mat("#2a2a2a", 0.5), axis="Y")
        box((0.012, 0.012, 0.06), (0.18, -0.175, 0.53), mat("#b8332a", 0.5), rot=(0, 0 if on else 90, 0))
        box((0.12, 0.004, 0.03), (-0.07, -0.145, 0.73), mat("#f2b63c", 0.6))
        for i in range(6): box((0.008, 0.2, 0.012), (0.262, 0, 0.2 + i * 0.03), p["dark"])
        path([(0.0, 0.14, 0.15), (0.0, 0.25, 0.05), (0.2, 0.4, 0.02)], 0.012, p["wire_k"])


def transformer(state):
    p = P(); on = state == "on"
    body = mat("#4c5d4a", 0.55, 0.3, var=0.1, rust=0.15, dirt=0.25)
    box((0.8, 0.62, 0.08), (0, 0, 0.04), p["concrete"], bevel=0.01)
    box((0.66, 0.5, 0.58), (0, 0.02, 0.37), body, bevel=0.02)
    for x in (-0.16, 0.16): box((0.3, 0.01, 0.48), (x, -0.235, 0.36), mat("#465643", 0.55, 0.3), bevel=0.003)
    box((0.012, 0.02, 0.1), (0.0, -0.245, 0.4), mat("#2a2a2a", 0.5))
    box((0.04, 0.02, 0.05), (0.0, -0.25, 0.32), p["brass"])
    box((0.14, 0.004, 0.1), (-0.16, -0.243, 0.52), mat("#d7b43c", 0.6, dirt=0.1))
    for i in range(8): box((0.04, 0.42, 0.42), (0.36 + 0.0 * i, 0.02 - 0.0, 0.34), body) if i == 0 else None
    for i in range(7): box((0.06, 0.012, 0.4), (0.36, -0.15 + i * 0.05, 0.34), body)
    for x in (-0.2, 0.0, 0.2):
        cyl(0.035, 0.12, (x, 0.12, 0.72), mat("#6e4a32", 0.35, var=0.08), segs=14)
        for k in range(3): cyl(0.05, 0.012, (x, 0.12, 0.68 + k * 0.035), mat("#6e4a32", 0.35), segs=14)
        cyl(0.012, 0.04, (x, 0.12, 0.8), p["copper"])
    lamp((-0.24, -0.24, 0.6), on, "#f2b63c", 0.012)
    path([(0.0, 0.27, 0.2), (0.1, 0.35, 0.05), (0.2, 0.42, 0.02)], 0.012, p["wire_k"])


def lamp_part(mount, tier, state):
    p = P(); on = state == "on"
    warm = glow("#ffd9a0", 9) if on else mat("#d9d4c4", 0.2, alpha=0.75, dirt=0, wear=False)

    def light(at, energy):
        if not on: return
        ld = bpy.data.lights.new("l", "POINT"); ld.energy = energy; ld.color = (1.0, 0.85, 0.65); ld.shadow_soft_size = 0.05
        lo = bpy.data.objects.new("l", ld); MODEL.objects.link(lo); lo.location = HEAD[-1] @ Vector(at); BUILT.append(lo)
    if mount == "garden":
        if tier == "makeshift":
            box((0.04, 0.04, 0.62), (0, 0, 0.31), p["wood"])
            uv_quad(0.13, 0.13, cells_mat(3, 3), M((0, 0, 0.65), (20, 0, 0)))
            box((0.15, 0.15, 0.015), (0, 0, 0.64), p["ply"], rot=(20, 0, 0))
            cyl(0.05, 0.1, (0, -0.07, 0.5), warm, segs=16); cyl(0.052, 0.02, (0, -0.07, 0.56), p["steel"], segs=16)
            tube((0, -0.02, 0.58), (0, -0.07, 0.57), 0.004, p["wire_k"], 6); tape((0, 0, 0.45), 0.03, "Z", 0.03)
            light((0, -0.07, 0.5), 6)
        else:
            blk = mat("#2a2b2e", 0.4, 0.5, dirt=0.15)
            cyl(0.07, 0.04, (0, 0, 0.02), blk, segs=20); cyl(0.045, 0.42, (0, 0, 0.24), blk, segs=20)
            cyl(0.06, 0.12, (0, 0, 0.51), warm, segs=20)
            cyl(0.085, 0.03, (0, 0, 0.585), blk, segs=24)
            uv_quad(0.11, 0.11, cells_mat(3, 3), M((0, 0, 0.602)))
            light((0, 0, 0.5), 8)
    else:
        if tier == "makeshift":
            box((0.1, 0.1, 2.25), (0, 0.05, 1.125), p["wood_grey"])
            for rot in (0, 90): box((0.5, 0.08, 0.06), (0, 0.05, 0.03), p["wood"], rot=(0, 0, rot))
            box((0.05, 0.42, 0.05), (0, -0.12, 2.05), p["wood"])
            cyl(0.06, 0.07, (0, -0.32, 1.99), mat("#2b2c2f", 0.5), axis="Z", segs=16)
            cyl(0.05, 0.01, (0, -0.32, 1.955), warm, segs=16)
            box((0.38, 0.5, 0.02), (0, 0.05, 2.32), p["ply"], rot=(25, 0, 0))
            uv_quad(0.34, 0.46, cells_mat(4, 6, tint="#26364e"), M((0, 0.05, 2.332), (25, 0, 0)))
            box((0.25, 0.17, 0.19), (0.0, -0.06, 1.1), mat("#2a2b2d", 0.6)); box((0.27, 0.02, 0.03), (0, -0.15, 1.12), mat("#c86f24", 0.6))
            path([(0, -0.02, 2.2), (0.05, -0.01, 1.6), (0.04, -0.12, 1.2)], 0.006, p["wire_k"])
            light((0, -0.32, 1.9), 30)
        else:
            pole = mat("#8d9295", 0.4, 0.55, dirt=0.15)
            box((0.26, 0.26, 0.04), (0, 0.05, 0.02), pole)
            cyl(0.055, 2.3, (0, 0.05, 1.17), pole, r2=0.035, segs=16)
            path([(0, 0.05, 2.2), (0, -0.1, 2.28), (0, -0.3, 2.24)], 0.025, pole)
            box((0.14, 0.3, 0.04), (0, -0.36, 2.22), mat("#3a3d40", 0.45, 0.3), bevel=0.01)
            box((0.11, 0.24, 0.006), (0, -0.36, 2.197), warm)
            box((0.5, 0.36, 0.02), (0, 0.12, 2.42), mat("#c4c7ca", 0.4, 0.5), rot=(30, 0, 0))
            uv_quad(0.46, 0.32, cells_mat(6, 4), M((0, 0.12, 2.432), (30, 0, 0)))
            tube((0, 0.05, 2.3), (0, 0.12, 2.38), 0.02, pole)
            box((0.16, 0.1, 0.24), (0, -0.01, 1.2), mat("#3a3d40", 0.45, 0.3), bevel=0.01)
            light((0, -0.36, 2.1), 40)


def gauge_part(state):
    """A small dial panel on the wall behind (+Y); the needle and lamp show the band."""
    p = P(); back = 0.5; z = 1.35
    needle = {"off": 0.0, "low": 0.2, "mid": 0.52, "full": 0.88}[state]
    col = {"off": None, "low": "#d84a3a", "mid": "#f2b63c", "full": "#6fe07a"}[state]
    box((0.22, 0.05, 0.3), (0, back - 0.025, z), mat("#5d666c", 0.45, 0.4, dirt=0.2), bevel=0.01)
    gauge((0, back - 0.052, z + 0.03), (0, 0, 0), 0.07, needle, rim="#c9ccd0")
    lamp((0, back - 0.055, z - 0.1), col is not None, col or "#6fe07a", 0.014)
    tube((0.0, back - 0.025, z + 0.15), (0.0, back - 0.025, 2.4), 0.012, mat("#8d9295", 0.4, 0.5))


def rod_part():
    p = P(); cu = mat("#b4703f", 0.35, 0.8, var=0.1, dirt=0.15)
    for a in (90, 210, 330):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        tube(d * 0.24, Vector((0, 0, 0.4)), 0.012, p["galv"], 8)
    cyl(0.02, 0.1, (0, 0, 0.42), p["galv"], segs=10)
    cyl(0.011, 2.0, (0, 0, 1.42), cu, segs=10)
    cyl(0.018, 0.12, (0, 0, 2.48), cu, r2=0.001, segs=10)
    for k in range(3):
        a = k * 2.1
        tube((0, 0, 2.38), (math.cos(a) * 0.05, math.sin(a) * 0.05, 2.46), 0.005, cu, 6)
    path([(0.0, 0.0, 0.5), (0.05, -0.05, 0.3), (0.2, -0.25, 0.02), (0.34, -0.32, 0.02)], 0.007, mat("#4c8f3a", 0.6))
    cyl(0.012, 0.08, (0.34, -0.32, 0.03), cu, segs=8)


def bench_part(state):
    p = P(); on = state == "on"
    top = mat("#8c6f4e", 0.8, var=0.2, dirt=0.3)
    leg = mat("#4b5157", 0.5, 0.4, rust=0.15)
    box((0.9, 0.52, 0.05), (0, 0, 0.76), top, bevel=0.008)
    for x in (-0.4, 0.4):
        for y in (-0.21, 0.21): box((0.04, 0.04, 0.74), (x, y, 0.37), leg)
    box((0.84, 0.46, 0.02), (0, 0, 0.18), top)
    car_battery((-0.18, 0.0, 0.785), 8)
    car_battery((0.2, 0.05, 0.19), -10, 0.2)
    ch = mat("#c9a23a", 0.5, 0.2, dirt=0.2)
    box((0.22, 0.16, 0.16), (0.2, 0.04, 0.865), ch, bevel=0.015)
    box((0.14, 0.008, 0.06), (0.2, -0.042, 0.89), mat("#1a1c1e", 0.4))
    gauge((0.17, -0.046, 0.89), (0, 0, 0), 0.022, 0.65 if on else 0.0)
    lamp((0.25, -0.046, 0.89), on, "#6fe07a", 0.008); lamp((0.25, -0.046, 0.87), not on, "#d84a3a", 0.008) if on else None
    box((0.16, 0.01, 0.025), (0.2, -0.083, 0.83), mat("#2b2c2f", 0.5))
    for red, x in ((True, -0.26), (False, -0.1)):
        path([(0.12, 0.0, 0.84), (0.0, -0.12, 0.9), (x, -0.045, 0.99)], 0.006, p["wire_r"] if red else p["wire_k"])
        box((0.03, 0.02, 0.02), (x, -0.045, 0.99), mat("#a8322a" if red else "#1c1c1c", 0.5))
    path([(0.31, 0.1, 0.8), (0.42, 0.25, 0.4), (0.44, 0.4, 0.02)], 0.008, p["wire_k"])


def hydro_part(state):
    p = P(); turning = state == "turning"
    frame = p["wood_dark"]
    c = Vector((0.0, 0.0, 0.46)); r = 0.38
    for x in (-0.2, 0.2):
        box((0.06, 0.06, 0.62), (x, 0.0, 0.31), frame); box((0.06, 0.7, 0.06), (x, 0.0, 0.03), frame)
        tube((x, -0.33, 0.04), (x, 0.0, 0.58), 0.025, frame, 4); tube((x, 0.33, 0.04), (x, 0.0, 0.58), 0.025, frame, 4)
    iron = mat("#3c3e40", 0.55, 0.4, rust=0.3)
    cyl(0.03, 0.46, c, iron, axis="X", segs=12)
    for sx in (-0.1, 0.1): torus(r - 0.02, 0.018, c + Vector((sx, 0, 0)), iron, axis="X", seg=40)
    wood = mat("#7a6046", 0.8, var=0.2, dirt=0.3)
    if turning:
        cyl(r - 0.02, 0.2, c, mat("#6d5a44", 0.8, alpha=0.45, dirt=0, wear=False), axis="X", segs=40)
        for i in range(12):
            a = 2 * math.pi * i / 12 + 0.13
            box((0.2, 0.012, 0.1), c + Vector((0, math.cos(a), math.sin(a))) * (r - 0.05), mat("#7a6046", 0.8, alpha=0.5, dirt=0, wear=False), rot=(math.degrees(a), 0, 0))
    else:
        for i in range(12):
            a = 2 * math.pi * i / 12
            box((0.2, 0.012, 0.11), c + Vector((0, math.cos(a), math.sin(a))) * (r - 0.06), wood, rot=(math.degrees(a), 0, 0))
            tube(c + Vector((0.09, 0, 0)), c + Vector((0.09, math.cos(a), math.sin(a))) * 1 * (r - 0.05) + Vector((0, 0, 0)) * 0, 0.006, iron, 5) if i % 3 == 0 else None
    box((0.18, 0.5, 0.03), (0.0, 0.32, 0.92), wood, rot=(-12, 0, 0))
    for x in (-0.09, 0.09): box((0.02, 0.5, 0.08), (x, 0.32, 0.95), wood, rot=(-12, 0, 0))
    for y in (0.5,): box((0.05, 0.05, 0.9), (0.0, y - 0.05, 0.45), frame)
    gen = mat("#3e5a46", 0.5, 0.3, dirt=0.2)
    cyl(0.09, 0.18, (0.36, 0.1, 0.22), gen, axis="X"); box((0.2, 0.2, 0.06), (0.36, 0.1, 0.1), frame)
    tube((0.27, 0.1, 0.22), (0.25, 0.0, 0.46), 0.006, p["rubber"])
    path([(0.42, 0.15, 0.2), (0.44, 0.35, 0.05), (0.45, 0.45, 0.02)], 0.008, p["wire_k"])
    if turning:
        wat = mat("#7fa6c4", 0.1, alpha=0.5, dirt=0, wear=False)
        box((0.14, 0.45, 0.02), (0.0, 0.3, 0.945), wat, rot=(-12, 0, 0))
        puffs((0, 0.02, 0.88), 4, 0.04, "#cfe0ea", 0.45, (0.0, -0.3, -0.6), seed=4)
        puffs((0, -0.32, 0.1), 4, 0.05, "#d8e6ee", 0.35, (0.0, -0.1, 0.2), seed=8)


def point_light(at, energy, col=(1.0, 0.6, 0.25)):
    """A small point lamp in the model (a fire, an element, a spark), placed through the head transform."""
    ld = bpy.data.lights.new("pl", "POINT"); ld.energy = energy; ld.color = col; ld.shadow_soft_size = 0.05
    lo = bpy.data.objects.new("pl", ld); MODEL.objects.link(lo); lo.location = HEAD[-1] @ Vector(at); BUILT.append(lo)


def spark(c, size=0.035):
    """A crackle on a live wire: three crossed glowing slivers and a pinch of blue light."""
    c = Vector(c); g = glow("#e9f7ff", 14)
    for rot in ((0, 0, 0), (0, 60, 0), (0, -60, 0)):
        box((size * 2, 0.003, 0.004), c, g, rot=rot, bevel=0)
    ball(size * 0.35, c, g, segs=8)
    point_light(c + Vector((0, -0.05, 0)), 1.5, (0.65, 0.85, 1.0))


def fence_part(state):
    """A charged fence section across the square: wooden end posts, a steel T-post, four strands on yellow
    insulators, a warning plate and the energizer box. Live strands glow faintly and crackle."""
    p = P(); on = state == "on"
    tpost = mat("#4c5a4e", 0.55, 0.45, var=0.12, rust=0.2, dirt=0.3)
    yellow = mat("#d9b23a", 0.45, dirt=0.15)
    zs = (0.22, 0.46, 0.7, 0.94)
    for x in (-0.44, 0.44):
        box((0.075, 0.075, 1.14), (x, 0, 0.57), p["wood_grey"], bevel=0.008)
        cyl(0.045, 0.02, (x, 0, 1.15), p["wood_dark"], segs=12)
    box((0.032, 0.022, 1.08), (0, 0, 0.54), tpost); box((0.07, 0.008, 1.08), (0, 0.012, 0.54), tpost)
    box((0.1, 0.02, 0.05), (0, 0, 0.06), tpost, rot=(0, 0, 0))
    for x in (-0.44, 0.0, 0.44):
        for z in zs:
            cyl(0.017, 0.05, (x, -0.055, z), yellow, axis="Y", segs=10)
    strand = glow("#6fbcff", 1.3) if on else mat("#b9bcbf", 0.35, 0.8, dirt=0.1)
    for z in zs:
        tube((-0.46, -0.075, z), (0.46, -0.075, z), 0.006, strand, 8)
    # the warning plate hung on the second strand
    box((0.17, 0.006, 0.11), (0.22, -0.085, 0.52), mat("#e2b93b", 0.5, dirt=0.2), bevel=0.003)
    k = mat("#1b1b1b", 0.6, dirt=0, wear=False)
    box((0.012, 0.003, 0.05), (0.212, -0.0895, 0.535), k, rot=(0, 28, 0), bevel=0)
    box((0.012, 0.003, 0.05), (0.228, -0.0895, 0.505), k, rot=(0, 28, 0), bevel=0)
    box((0.018, 0.003, 0.008), (0.22, -0.0895, 0.52), k, bevel=0)
    # the energizer on the left end post, its lead to the top strand and its ground wire
    box((0.11, 0.07, 0.14), (-0.44, -0.075, 1.05), mat("#5f6a70", 0.5, 0.35, dirt=0.2), bevel=0.01)
    box((0.07, 0.004, 0.03), (-0.44, -0.111, 1.08), mat("#d8d3c4", 0.6, dirt=0.15))
    lamp((-0.415, -0.112, 1.02), on, "#e04a3a", 0.01)
    path([(-0.4, -0.08, 0.98), (-0.36, -0.08, 0.95), (-0.32, -0.075, 0.94)], 0.006, p["wire_r"])
    path([(-0.47, -0.08, 0.98), (-0.48, -0.1, 0.5), (-0.46, -0.2, 0.05), (-0.36, -0.28, 0.02)], 0.006, mat("#4c8f3a", 0.6))
    cyl(0.012, 0.1, (-0.36, -0.28, 0.04), p["copper"], segs=8)
    if on:
        spark((0.0, -0.08, 0.7), 0.05); spark((0.3, -0.08, 0.22), 0.04)


def cooler_part(state):
    """A walk-in-cooler evaporator high on the wall behind (+Y): a galvanized housing with two fans, a drain
    and conduit down the wall. Running: blurred fans, a lit lamp and cold mist falling from the fans."""
    p = P(); on = state == "on"; back = 0.5; z = 1.86
    housing = mat("#bfc3c4", 0.42, 0.45, var=0.08, dirt=0.2)
    box((0.76, 0.3, 0.38), (0, back - 0.15, z), housing, bevel=0.012)
    front = back - 0.3
    box((0.74, 0.012, 0.05), (0, front - 0.004, z + 0.155), mat("#9ea3a6", 0.45, 0.45))
    for i in range(3): box((0.6, 0.006, 0.008), (0, front - 0.011, z + 0.14 + i * 0.012), p["dark"], bevel=0)
    grille = mat("#d0d3d5", 0.35, 0.7, dirt=0.1)
    for x in (-0.18, 0.18):
        cyl(0.12, 0.006, (x, front - 0.002, z - 0.02), mat("#1a1c1e", 0.7, dirt=0, wear=False), axis="Y", segs=32)
        if on:
            cyl(0.105, 0.004, (x, front - 0.012, z - 0.02), mat("#8a9096", 0.5, alpha=0.4, dirt=0, wear=False), axis="Y", segs=32)
        else:
            for a in (20, 140, 260):
                r = math.radians(a)
                box((0.045, 0.004, 0.095), (x + math.cos(r) * 0.055, front - 0.012, z - 0.02 + math.sin(r) * 0.055),
                    mat("#4a5056", 0.5, 0.4), rot=(0, -a + 90, 0), bevel=0.002)
        cyl(0.022, 0.016, (x, front - 0.016, z - 0.02), p["steel_dark"], axis="Y", segs=14)
        for rr in (0.12, 0.085, 0.05): torus(rr, 0.004, (x, front - 0.022, z - 0.02), grille, axis="Y", seg=36, rseg=6)
        for a in (0, 90): box((0.24, 0.005, 0.006), (x, front - 0.022, z - 0.02), grille, rot=(0, a, 0), bevel=0)
    box((0.12, 0.004, 0.04), (0.0, front - 0.004, z - 0.15), mat("#d8d3c4", 0.6, dirt=0.15))
    lamp((0.31, front - 0.008, z - 0.15), on, "#6fe07a", 0.011)
    box((0.78, 0.28, 0.025), (0, back - 0.14, z - 0.2), mat("#a9aeb1", 0.45, 0.45, dirt=0.25))
    bracket = mat("#5b6266", 0.5, 0.4, rust=0.15)
    for x in (-0.3, 0.3):
        box((0.03, 0.28, 0.03), (x, back - 0.14, z - 0.225), bracket)
        tube((x, back - 0.27, z - 0.235), (x, back - 0.02, z - 0.42), 0.01, bracket, 6)
    # the drain dips under the tray and goes into the wall; the supply runs in a short conduit to a box beside it
    path([(0.28, back - 0.12, z - 0.21), (0.28, back - 0.1, z - 0.34), (0.28, back - 0.02, z - 0.4), (0.28, back, z - 0.4)], 0.012, p["copper"])
    conduit = mat("#9aa0a4", 0.45, 0.5, dirt=0.2)
    path([(-0.38, back - 0.12, z + 0.05), (-0.42, back - 0.1, z + 0.05), (-0.44, back - 0.05, z - 0.06)], 0.012, conduit)
    box((0.07, 0.05, 0.1), (-0.44, back - 0.025, z - 0.1), mat("#6a7378", 0.5, 0.4), bevel=0.006)
    if on:
        for i, x in enumerate((-0.18, 0.18)):
            puffs((x, front - 0.05, z - 0.14), 3, 0.035, "#eef6fb", 0.2, (0.0, -0.2, -0.55), seed=21 + i)


def heater_part(state):
    """A cabinet space heater on the floor: cream steel body, chrome grille over three element rods that glow
    orange while it runs, two knobs and a lamp on top, the cord trailing off the square."""
    p = P(); on = state == "on"
    body = mat("#d6cdb8", 0.5, 0.2, var=0.08, dirt=0.25)
    for x in (-0.16, 0.16): box((0.07, 0.28, 0.03), (x, 0, 0.015), p["steel_dark"], bevel=0.006)
    box((0.46, 0.22, 0.47), (0, 0, 0.27), body, bevel=0.025)
    box((0.38, 0.01, 0.32), (0, -0.108, 0.25), mat("#2a2826", 0.7, dirt=0, wear=False))
    box((0.36, 0.004, 0.3), (0, -0.112, 0.25), mat("#c9c8c2", 0.25, 0.85, dirt=0.05))
    elem = glow("#ff7a2a", 10) if on else mat("#5a5048", 0.6, 0.4, dirt=0.1)
    for zz in (0.15, 0.25, 0.35):
        cyl(0.016, 0.33, (0, -0.124, zz), elem, axis="X", segs=12)
        for x in (-0.17, 0.17): cyl(0.022, 0.02, (x, -0.124, zz), p["steel_dark"], axis="X", segs=10)
    chrome = mat("#cfd2d5", 0.22, 0.9, dirt=0.08)
    for i in range(8): box((0.38, 0.006, 0.007), (0, -0.142, 0.105 + i * 0.041), chrome, bevel=0)
    for x in (-0.12, 0.0, 0.12): box((0.007, 0.006, 0.31), (x, -0.142, 0.25), chrome, bevel=0)
    box((0.4, 0.014, 0.012), (0, -0.14, 0.41), chrome); box((0.4, 0.014, 0.012), (0, -0.14, 0.09), chrome)
    for x in (0.08, 0.16):
        cyl(0.026, 0.024, (x, 0.02, 0.515), mat("#2a2b2d", 0.5), segs=16)
        box((0.006, 0.03, 0.006), (x, 0.01, 0.53), mat("#e8e2cf", 0.5))
    lamp((-0.15, -0.06, 0.508), on, "#ff6a2a", 0.012)
    box((0.16, 0.035, 0.012), (-0.06, 0.06, 0.506), p["dark"])
    for s in (-1, 1):
        for i in range(5): box((0.006, 0.14, 0.012), (0.231 * s, 0, 0.28 + i * 0.03), p["dark"], bevel=0)
    path([(0.15, 0.11, 0.1), (0.2, 0.18, 0.02), (0.38, 0.34, 0.012), (0.46, 0.45, 0.012)], 0.007, p["wire_k"])
    if on:
        point_light((0, -0.3, 0.25), 7, (1.0, 0.5, 0.2))


# ------------------------------------------------------------------ wood gas generators
def gas_line(pts, r, m, flange=None):
    """A pipe run with a flange ring at each joint (salvaged / workshop lines)."""
    path(pts, r, m)
    if flange:
        for a, b in zip(pts, pts[1:]):
            a, b = Vector(a), Vector(b); d = (b - a)
            if d.length < 0.05: continue
            ax = "X" if abs(d.x) > max(abs(d.y), abs(d.z)) else ("Y" if abs(d.y) > abs(d.z) else "Z")
            cyl(r * 1.6, 0.014, a + d.normalized() * 0.03, flange, axis=ax, segs=14)


def wg_glow(at, state, w=0.1, h=0.05):
    """The ash-door slit or air nozzle of the firebox: dark when cold, dull red warming, bright running."""
    if state == "running":
        box((w, 0.01, h), at, glow("#ff8a30", 9)); point_light(Vector(at) + Vector((0, -0.12, 0)), 6, (1.0, 0.55, 0.2))
    elif state == "warming":
        box((w, 0.01, h), at, glow("#c4521f", 4)); point_light(Vector(at) + Vector((0, -0.12, 0)), 2, (1.0, 0.45, 0.15))
    else:
        box((w, 0.01, h), at, mat("#161412", 0.95, dirt=0, wear=False))


# dz2's woodgasfire rows (the client's fire frames, DP_GenFx): "fire1".."fire4" or "embers" while one is built, else None.
WG_FRAME = None
WG_FLICKER = {1: 7.0, 2: 10.5, 3: 6.0, 4: 9.0}     # the open ash door's own light per flame frame


def wg_door(size, loc, m, slit, state, sw, sh):
    """The gasifier's ash door: shut, with the glowing slit under it (the plain sprites), or, on a fire frame, swung
    open on the left hinge over a mouth of flames (fire1..fire4) or of embers (the warming gasifier)."""
    if not (WG_FRAME and state in ("running", "warming")):
        box(size, loc, m, bevel=0.008); wg_glow(slit, state, sw, sh)
        return
    p = P(); w, d, h = size; o = Vector(loc) - Vector((0, d / 2, 0))
    # The mouth: an iron frame standing off the shell, the glowing bed inside it.
    for x in (-1, 1): box((0.012, d + 0.01, h + 0.012), o + Vector((x * (w / 2 + 0.004), d / 2, 0)), p["iron"], bevel=0.003)
    for z in (-1, 1): box((w + 0.02, d + 0.01, 0.012), o + Vector((0, d / 2, z * (h / 2 + 0.004))), p["iron"], bevel=0.003)
    hot = WG_FRAME != "embers"
    n = int(WG_FRAME[-1]) if hot else 0
    back = (glow("#ff7a26", (4.0, 6.5, 3.6, 5.5)[n - 1]) if hot else glow("#a8381a", 2.2))
    box((w, 0.006, h), o + Vector((0, 0.008, 0)), back, bevel=0)
    rnd = random.Random(23)
    base = o.z - h / 2 + 0.006
    for i in range(int(8 + 50 * w)):
        c = rnd.choice(["#ff5a14", "#d23c0c", "#ff7c2a", "#9a2a08"])
        ball(rnd.uniform(0.006, 0.011), (o.x + rnd.uniform(-0.44, 0.44) * w, o.y + rnd.uniform(-0.004, 0.008), base + rnd.uniform(0, 0.014)),
             glow(c, rnd.uniform(5, 9) if hot else rnd.uniform(1.6, 3.2)), segs=8)
    if hot:
        rnd = random.Random(200 + 17 * n)
        for k in range(3):
            x = o.x + ((k + 0.5) / 3 - 0.5) * w * 0.8 + rnd.uniform(-0.08, 0.08) * w
            ht = h * rnd.uniform(0.5, 0.92); r = w * rnd.uniform(0.09, 0.13); lean = rnd.uniform(-0.25, 0.25) * r
            ball(r, (x + lean, o.y + 0.002, base + ht * 0.45), glow("#ff6a16", 9), scale=(1, 0.6, ht * 0.5 / r))
            ball(r * 0.55, (x + lean * 0.5, o.y - 0.002, base + ht * 0.32), glow("#ffd47a", 16), scale=(1, 0.6, ht * 0.32 / (r * 0.55)))
        energy, col = WG_FLICKER[n], (1.0, 0.55, 0.2)
    else:
        energy, col = 2.0, (1.0, 0.32, 0.1)
    # The door, swung open on its left hinge.
    hinge = o + Vector((-w / 2 - 0.008, -0.004, 0)); a = math.radians(-118)
    box((w, 0.014, h * 1.04), hinge + Vector((math.cos(a), math.sin(a), 0)) * (w / 2), m, rot=(0, 0, -118), bevel=0.004)
    point_light(o + Vector((0, -0.1, 0)), energy, col)


def wg_flare(tip, state):
    """The flare stack's mouth: a lick of flame and thick smoke while the gasifier warms (the gas is burnt off
    until it is clean enough for the engine), nothing once the valve turns it to the engine."""
    tip = Vector(tip)
    if state != "warming": return
    cyl(0.022, 0.07, tip + Vector((0, 0, 0.04)), glow("#ffb04a", 10), r2=0.002, segs=10)
    cyl(0.013, 0.05, tip + Vector((0, 0, 0.035)), glow("#fff0b0", 14), r2=0.001, segs=8)
    point_light(tip + Vector((0, -0.06, 0.06)), 3, (1.0, 0.6, 0.25))
    puffs(tip + Vector((0, 0, 0.05)), 8, 0.065, "#9c9a95", 0.55, (0.06, -0.06, 0.9), seed=31)


def tilt_head(pivot, rot):
    """Push a head transform that tips everything built next about `pivot` (a broken, knocked-over part)."""
    pv = Vector(pivot)
    HEAD.append(HEAD[-1] @ Matrix.Translation(pv) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
                @ Matrix.Translation(-pv))


def wg_engine(tier, state):
    """The engine-generator set on the front half of the square; returns (intake, exhaust) points."""
    p = P(); run = state == "running"
    if tier == "makeshift":
        for x in (-0.34, 0.0, 0.34): box((0.06, 0.34, 0.07), (x, -0.25, 0.035), p["wood"])
        for i in range(3): box((0.8, 0.1, 0.022), (0, -0.37 + i * 0.12, 0.081), p["wood_grey"])
        eng = mat("#6d6e6a", 0.55, 0.35, rust=0.35, dirt=0.35)
        box((0.2, 0.18, 0.15), (-0.1, -0.25, 0.17), eng, bevel=0.01)
        for i in range(4): box((0.21, 0.19, 0.008), (-0.1, -0.25, 0.25 + i * 0.016), p["alu"], bevel=0)
        box((0.2, 0.18, 0.1), (-0.1, -0.25, 0.36), mat("#8c2f28", 0.55, 0.2, rust=0.35, dirt=0.35), bevel=0.03)
        cyl(0.06, 0.03, (-0.1, -0.25, 0.42), p["dark"], segs=16)
        cyl(0.03, 0.1, (0.05, -0.25, 0.2), p["steel"], axis="X")
        cyl(0.07, 0.13, (0.17, -0.25, 0.2), p["alu"], axis="X"); cyl(0.04, 0.03, (0.25, -0.25, 0.2), p["steel_dark"], axis="X")
        tape((0.13, -0.25, 0.2), 0.075, "X", 0.025)
        box((0.18, 0.06, 0.08), (0.17, -0.25, 0.12), p["wood_dark"])
        path([(0.22, -0.21, 0.25), (0.32, -0.12, 0.27), (0.4, 0.02, 0.1)], 0.007, p["wire_r"])
        path([(0.22, -0.22, 0.22), (0.34, -0.16, 0.2), (0.42, -0.02, 0.1)], 0.007, p["wire_k"])
        cyl(0.035, 0.12, (-0.27, -0.3, 0.22), p["iron"], axis="X")
        lamp((0.17, -0.33, 0.27), run, "#6fe07a", 0.01)
        return Vector((-0.1, -0.16, 0.3)), Vector((-0.34, -0.3, 0.22))
    if tier == "salvaged":
        rail = mat("#3a3c3e", 0.5, 0.4, rust=0.35)
        for y in (-0.37, -0.13): box((0.78, 0.05, 0.05), (0, y, 0.025), rail)
        box((0.7, 0.28, 0.025), (0, -0.25, 0.06), rail)
        eng = mat("#4e6b45", 0.5, 0.3, var=0.15, rust=0.35, dirt=0.35)
        box((0.26, 0.2, 0.2), (-0.08, -0.25, 0.18), eng, bevel=0.015)
        box((0.24, 0.12, 0.05), (-0.08, -0.25, 0.305), mat("#3d5537", 0.5, 0.3, rust=0.3), bevel=0.012)
        for i in range(3): cyl(0.016, 0.03, (-0.16 + i * 0.08, -0.25, 0.34), p["steel_dark"])
        flywheel((-0.26, -0.25, 0.2), 0.13, 0.03, p["iron"], "running" if run else "off")
        cyl(0.095, 0.24, (0.2, -0.25, 0.19), mat("#6b2a24", 0.5, 0.3, rust=0.3, dirt=0.3), axis="X", segs=24)
        for x in (0.08, 0.32): cyl(0.1, 0.02, (x, -0.25, 0.19), p["steel_dark"], axis="X", segs=24)
        cyl(0.03, 0.06, (0.06, -0.25, 0.19), p["steel"], axis="X")
        box((0.1, 0.06, 0.08), (0.2, -0.37, 0.24), mat("#2c2d30", 0.5), bevel=0.008)
        gauge((0.18, -0.402, 0.25), (0, 0, 0), 0.018, 0.6 if run else 0.0)
        lamp((0.23, -0.402, 0.26), run, "#6fe07a", 0.008)
        tube((0.0, -0.3, 0.33), (0.0, -0.3, 0.6), 0.02, p["iron"]); cyl(0.035, 0.03, (0.0, -0.3, 0.62), p["iron"], r2=0.02)
        path([(0.32, -0.2, 0.2), (0.4, -0.05, 0.12), (0.44, 0.1, 0.02)], 0.008, p["wire_k"])
        return Vector((-0.08, -0.15, 0.25)), Vector((0.0, -0.3, 0.64))
    olive = mat("#56603e", 0.48, 0.22, var=0.08, dirt=0.15)
    box((0.8, 0.34, 0.05), (0, -0.25, 0.025), mat("#2f3330", 0.5, 0.3, dirt=0.2), bevel=0.008)
    box((0.7, 0.3, 0.32), (0, -0.25, 0.21), olive, bevel=0.02)
    box((0.72, 0.32, 0.012), (0, -0.25, 0.37), mat("#2f3330", 0.5, 0.3))
    for s in (1, -1):
        for i in range(5): box((0.01, 0.2, 0.014), (0.35 * s, -0.25, 0.1 + i * 0.045), p["dark"], rot=(0, 25 * s, 0), bevel=0)
    box((0.24, 0.012, 0.14), (-0.16, -0.405, 0.24), mat("#2a2b2d", 0.45, 0.3))
    gauge((-0.22, -0.413, 0.26), (0, 0, 0), 0.03, 0.62 if run else 0.0, rim="#b08c4a")
    lamp((-0.1, -0.414, 0.28), run, "#6fe07a", 0.011); lamp((-0.1, -0.414, 0.22), state == "warming", "#f2b63c", 0.011)
    box((0.06, 0.006, 0.03), (0.16, -0.405, 0.3), p["brass"])
    for i in range(4): box((0.24, 0.008, 0.012), (0.14, -0.405, 0.14 + i * 0.035), p["dark"], bevel=0)
    tube((0.3, -0.2, 0.37), (0.3, -0.2, 0.56), 0.022, p["iron"]); cyl(0.038, 0.035, (0.3, -0.2, 0.58), p["iron"], r2=0.024)
    path([(0.36, -0.12, 0.1), (0.42, 0.0, 0.05), (0.45, 0.1, 0.02)], 0.01, p["wire_k"])
    return Vector((-0.1, -0.12, 0.3)), Vector((0.3, -0.2, 0.6))


def woodgas_part(tier, state):
    """A WWII-style wood gas generator: a tall firebox-and-hopper gasifier at the back left, a cooler / filter at the
    back right with the flare stack, and an engine-generator set across the front."""
    p = P(); brk = state == "broken"
    gx, gy = -0.2, 0.13
    if tier == "makeshift":
        for dy in (-0.1, 0.1): cinder((gx, gy + dy, 0.095), 0)
        fb = mat("#4f6a7a", 0.6, 0.3, var=0.22, rust=0.5, dirt=0.4)
        cyl(0.2, 0.56, (gx, gy, 0.19 + 0.28), fb, segs=32)
        for zz in (0.37, 0.56): torus(0.202, 0.01, (gx, gy, zz), fb, seg=40)
        wg_door((0.14, 0.03, 0.1), (gx, gy - 0.195, 0.3), p["iron"], (gx, gy - 0.212, 0.3), "off" if brk else state, 0.09, 0.03)
        tube((gx - 0.12, gy - 0.12, 0.62), (gx - 0.2, gy - 0.26, 0.62), 0.022, p["iron"]); cyl(0.03, 0.03, (gx - 0.2, gy - 0.26, 0.62), p["steel_dark"], axis="Y")
        if brk: tilt_head((gx + 0.2, gy, 0.75), (0, 14, -8))
        hp = mat("#7a3b2e", 0.6, 0.3, var=0.22, rust=0.5, dirt=0.35)
        cyl(0.2, 0.5, (gx, gy, 0.75 + 0.25), hp, segs=32)
        for zz in (0.92, 1.1): torus(0.202, 0.01, (gx, gy, zz), hp, seg=40)
        tape((gx, gy, 0.76), 0.205, "Z", 0.04)
        if not brk:
            cyl(0.212, 0.03, (gx, gy, 1.265), mat("#5c5a55", 0.55, 0.4, rust=0.4), segs=32)
            box((0.14, 0.03, 0.03), (gx, gy, 1.295), p["iron"])
            for a in (0, 180): box((0.03, 0.02, 0.07), (gx + math.cos(math.radians(a)) * 0.21, gy, 1.24), p["iron"])
        else:
            box((0.004, 0.06, 0.2), (gx - 0.05, gy - 0.198, 0.98), p["dark"], rot=(0, 15, 0))
            box((0.004, 0.05, 0.12), (gx + 0.05, gy - 0.198, 1.06), p["dark"], rot=(0, -25, 0))
        if brk:
            HEAD.pop()
            cyl(0.15, 0.03, (0.36, 0.03, 0.04), mat("#5c5a55", 0.55, 0.4, rust=0.4), segs=32, rot=(14, -18, 0))
        cinder((0.27, 0.27, 0.095), 90)
        bucket = mat("#d9d6cc", 0.6, var=0.1, dirt=0.4)
        cyl(0.11, 0.3, (0.27, 0.27, 0.34), bucket, r2=0.12, segs=24); cyl(0.125, 0.025, (0.27, 0.27, 0.5), bucket, segs=24)
        path([(gx + 0.19, gy, 0.3), (0.06, gy, 0.3), (0.06, gy, 0.8), (0.16, 0.27, 0.8), (0.16, 0.27, 0.45), (0.17, 0.27, 0.42)], 0.024, p["iron"])
        tape((0.06, gy, 0.55), 0.03, "Z", 0.03)
        tube((0.3, 0.27, 0.51), (0.3, 0.27, 1.18), 0.016, p["steel_dark"]); box((0.05, 0.03, 0.03), (0.3, 0.27, 0.86), mat("#b8302a", 0.5))
        flare = (0.3, 0.27, 1.19)
    elif tier == "salvaged":
        leg = mat("#3a3c3e", 0.55, 0.4, rust=0.4)
        for a in (45, 135, 225, 315):
            d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0)) * 0.17
            box((0.035, 0.035, 0.24), (gx + d.x, gy + d.y, 0.12), leg)
        torus(0.2, 0.014, (gx, gy, 0.22), leg, seg=40)
        if brk: tilt_head((gx + 0.19, gy - 0.1, 0.24), (6, 9, 0))
        shell = mat("#6b6e5e", 0.6, 0.35, var=0.18, rust=0.55, dirt=0.4)
        cyl(0.19, 0.92, (gx, gy, 0.24 + 0.46), shell, segs=36)
        for zz in (0.3, 0.55, 0.85, 1.1): torus(0.193, 0.012, (gx, gy, zz), shell, seg=40)
        for k in range(16):
            a = 2 * math.pi * k / 16
            for zz in (0.55, 0.85): ball(0.008, (gx + math.cos(a) * 0.196, gy + math.sin(a) * 0.196, zz + 0.02), p["steel_dark"], segs=6)
        cyl(0.19, 0.12, (gx, gy, 1.22), shell, r2=0.1, segs=36)
        if not brk:
            cyl(0.11, 0.04, (gx, gy, 1.3), p["iron"], segs=24)
            box((0.03, 0.2, 0.025), (gx, gy - 0.02, 1.335), p["iron"], rot=(-10, 0, 0))
        else:
            box((0.004, 0.08, 0.24), (gx - 0.03, gy - 0.188, 0.72), p["dark"], rot=(0, 20, 0))
        wg_door((0.15, 0.03, 0.13), (gx, gy - 0.19, 0.36), p["iron"], (gx, gy - 0.21, 0.33), "off" if brk else state, 0.08, 0.02)
        if not (WG_FRAME and state in ("running", "warming")):
            for x in (-0.06, 0.06): ball(0.01, (gx + x, gy - 0.208, 0.41), p["steel_dark"], segs=6)
        for a in (200, 250, 290):
            d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
            tube((gx + d.x * 0.18, gy + d.y * 0.18, 0.5), (gx + d.x * 0.26, gy + d.y * 0.26, 0.5), 0.016, p["iron"])
        if brk:
            HEAD.pop()
            cyl(0.11, 0.04, (0.36, 0.0, 0.04), p["iron"], segs=24, rot=(14, -18, 0))
        cyc = mat("#5d5e58", 0.6, 0.35, rust=0.5, dirt=0.35)
        cyl(0.08, 0.22, (0.08, 0.32, 0.85), cyc, segs=24); cyl(0.08, 0.2, (0.08, 0.32, 0.64), cyc, r2=0.025, segs=24)
        filt = mat("#556066", 0.6, 0.35, var=0.15, rust=0.45, dirt=0.4)
        box((0.2, 0.2, 0.5), (0.3, 0.24, 0.27), filt, bevel=0.012)
        box((0.22, 0.22, 0.03), (0.3, 0.24, 0.53), p["iron"], bevel=0.006)
        for x in (0.22, 0.38):
            for y in (0.16, 0.32): ball(0.012, (x, y, 0.55), p["steel_dark"], segs=6)
        gas_line([(gx + 0.18, gy + 0.05, 1.0), (0.0, 0.32, 1.0), (0.08, 0.32, 0.97)], 0.022, p["iron"], p["steel_dark"])
        gas_line([(0.08, 0.32, 0.55), (0.08, 0.32, 0.45), (0.2, 0.3, 0.45)], 0.02, p["iron"], p["steel_dark"])
        tube((0.36, 0.3, 0.55), (0.36, 0.3, 1.3), 0.016, p["iron"]); cyl(0.03, 0.03, (0.36, 0.3, 1.31), p["iron"], r2=0.02)
        cyl(0.03, 0.02, (0.36, 0.25, 0.75), mat("#b8302a", 0.5), axis="Y")
        flare = (0.36, 0.3, 1.32)
    else:
        olive = mat("#56603e", 0.45, 0.22, var=0.08, dirt=0.15)
        box((0.5, 0.5, 0.06), (gx, gy, 0.03), mat("#2f3330", 0.5, 0.3, dirt=0.2), bevel=0.008)
        if brk: tilt_head((gx + 0.18, gy - 0.18, 0.06), (7, 10, 0))
        cyl(0.19, 0.95, (gx, gy, 0.06 + 0.475), olive, segs=40)
        for zz in (0.18, 0.62, 1.0): torus(0.192, 0.009, (gx, gy, zz), p["brass"], seg=40)
        ball(0.19, (gx, gy, 1.01), olive, scale=(1, 1, 0.38))
        if not brk:
            cyl(0.08, 0.05, (gx, gy, 1.09), olive, segs=24)
            torus(0.06, 0.009, (gx, gy, 1.14), mat("#9c2b24", 0.45, 0.3), seg=24)
            for a in (0, 120, 240):
                r = math.radians(a); tube((gx, gy, 1.14), (gx + math.cos(r) * 0.06, gy + math.sin(r) * 0.06, 1.14), 0.005, mat("#9c2b24", 0.45, 0.3), 6)
        else:
            box((0.004, 0.08, 0.26), (gx - 0.02, gy - 0.188, 0.66), p["dark"], rot=(0, 18, 0))
            box((0.004, 0.06, 0.12), (gx + 0.06, gy - 0.188, 0.8), p["dark"], rot=(0, -30, 0))
        wg_door((0.15, 0.025, 0.12), (gx, gy - 0.19, 0.24), mat("#3f4734", 0.45, 0.25), (gx, gy - 0.205, 0.22), "off" if brk else state, 0.07, 0.02)
        if not (WG_FRAME and state in ("running", "warming")):
            cyl(0.014, 0.04, (gx + 0.06, gy - 0.21, 0.26), p["brass"], axis="Y")
        gauge((gx + 0.1, gy - 0.17, 0.78), (0, 0, 25), 0.035, {"running": 0.7, "warming": 0.35}.get(state, 0.0), rim="#b08c4a")
        if brk:
            HEAD.pop()
            cyl(0.08, 0.05, (0.38, 0.0, 0.06), olive, segs=24, rot=(0, 75, 20))
            torus(0.06, 0.009, (0.38, -0.06, 0.04), mat("#9c2b24", 0.45, 0.3), seg=24, rot=(10, 0, 0))
        lag = mat("#cfc9b8", 0.85, var=0.1, dirt=0.25)
        gas_line([(gx + 0.17, gy + 0.05, 0.9), (0.06, 0.3, 0.9), (0.06, 0.3, 0.6)], 0.028, lag, p["brass"])
        cool = mat("#6c7378", 0.4, 0.6, dirt=0.15)
        cyl(0.06, 0.5, (0.06, 0.3, 0.33), cool, segs=20)
        for i in range(9): cyl(0.085, 0.008, (0.06, 0.3, 0.14 + i * 0.046), cool, segs=24)
        gas_line([(0.06, 0.3, 0.1), (0.3, 0.3, 0.1), (0.3, 0.3, 0.16)], 0.022, lag, p["brass"])
        can = mat("#56603e", 0.45, 0.22, var=0.08, dirt=0.15)
        cyl(0.09, 0.42, (0.3, 0.3, 0.37), can, segs=28); ball(0.09, (0.3, 0.3, 0.58), can, scale=(1, 1, 0.35))
        torus(0.091, 0.008, (0.3, 0.3, 0.3), p["brass"], seg=32)
        box((0.03, 0.006, 0.18), (0.3, 0.208, 0.4), p["glass"], bevel=0)
        tube((0.3, 0.3, 0.6), (0.3, 0.3, 1.36), 0.016, mat("#3a3c3e", 0.45, 0.45))
        torus(0.03, 0.006, (0.3, 0.255, 0.95), mat("#9c2b24", 0.45, 0.3), axis="Y", seg=20)
        cyl(0.03, 0.03, (0.3, 0.3, 1.37), p["iron"], r2=0.02)
        flare = (0.3, 0.3, 1.38)
    intake, exhaust = wg_engine(tier, state)
    hose = p["rubber"] if tier == "makeshift" else (p["iron"] if tier == "salvaged" else mat("#cfc9b8", 0.85, var=0.1, dirt=0.25))
    start = Vector((0.27, 0.27, 0.48)) if tier == "makeshift" else (Vector((0.24, 0.17, 0.4)) if tier == "salvaged" else Vector((0.24, 0.24, 0.5)))
    path([start, Vector((start.x, -0.02, start.z)), Vector((intake.x, -0.02, intake.z + 0.05)), intake], 0.014 if tier == "makeshift" else 0.018, hose)
    wg_flare(flare, "off" if brk else state)
    if state == "running":
        # A fire frame's smoke climbs a quarter of a puff per frame (WG_FRAME fire1..fire4); the plain sprite's is still.
        ph = (int(WG_FRAME[-1]) - 1) / 4.0 if (WG_FRAME or "").startswith("fire") else None
        puffs(exhaust, 4 if ph is not None else 3, 0.034 if ph is not None else 0.03, "#9a9894", 0.36 if ph is not None else 0.3,
              (-0.3, -0.05, 0.6) if tier == "makeshift" else (0.05, -0.05, 0.8), seed=37, phase=ph)
    if brk:
        cyl(0.18, 0.003, (0.05, -0.05, 0.002), mat("#0f0e0d", 0.15, alpha=0.7, dirt=0, wear=False), segs=24)
        ash = mat("#5e5b57", 0.95, var=0.3, dirt=0, wear=False)
        for i, (x, y) in enumerate(((-0.12, -0.12), (-0.28, -0.1), (-0.05, -0.02))):
            ball(0.05 - i * 0.01, (x, y, 0.0), ash, scale=(1.4, 1.1, 0.35), segs=10)
        rnd = random.Random(41)
        for i in range(4):
            box((rnd.uniform(0.03, 0.07), rnd.uniform(0.02, 0.05), 0.01), (rnd.uniform(-0.4, 0.4), rnd.uniform(-0.46, -0.38), 0.006),
                p["steel_dark"], rot=(0, 0, rnd.uniform(0, 90)))


# ------------------------------------------------------------------ zombie treadwheel
def stained(col, rough=0.8, amt=0.35, blood="#4e1914", scale=6.0):
    """A cloth or skin material with dark dried-blood blotches over the usual wear."""
    key = ("stained", col, rough, amt, blood, scale)
    if key in MATS: return MATS[key]
    m = mat(col, rough, var=0.22, dirt=0.35).copy(); m.name = "stained%d" % len(MATS)
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    src = b.inputs["Base Color"].links[0].from_socket
    blot = ramp(nt, noise(nt, scale, 8), 0.66 - amt * 0.25, 0.7 - amt * 0.25)
    nt.links.new(mix(nt, blot, src, lin(blood)), b.inputs["Base Color"])
    MATS[key] = m
    return m


TREAD_C = Vector((0.0, 0.0, 0.8))        # the drum's centre: no axle, it rides on four rollers
TREAD_R = 0.69                           # the iron tyre the rollers bear on
TREAD_W = 0.27                           # half the drum's width (the hoops), along X; R + W stays inside the cell


def zombie_walker(floor, k=0.83):
    """A shambling zombie mid-stride on the drum's floor (z `floor` at its middle), facing the model front (-Y):
    grey-green skin, a torn blood-stained shirt and jeans, head lolling, arms reaching ahead. Modelled about 1.45
    tall and drawn at `k` of that so it fits the drum. Returns its waist, for the rope."""
    pv = Vector((0, 0, 0.17))
    HEAD.append(HEAD[-1] @ Matrix.Translation((0, 0, floor)) @ Matrix.Scale(k, 4) @ Matrix.Translation(-pv))
    skin = stained("#7c9468", 0.75, 0.1, "#5a2a22", 9.0)
    shirt = stained("#8d9184", 0.85, 0.4, "#4e1914", 5.0)
    jeans = stained("#3d475c", 0.9, 0.2, "#2a1512", 4.0)
    shoe = mat("#2a2420", 0.7, dirt=0.3)
    face = mat("#7c9468", 0.75, var=0.22, dirt=0.2)                       # no blotch, so the face reads grey-green
    hair = mat("#4a4a44", 0.9, dirt=0.1)
    # legs mid-stride: the left one planted ahead, the right pushing off behind with its heel up
    for x, hip, knee, ankle, toe in ((-0.08, (-0.08, 0.0, 0.8), (-0.085, -0.13, 0.5), (-0.085, -0.19, 0.24), (-0.085, -0.3, 0.2)),
                                     (0.08, (0.08, 0.0, 0.8), (0.085, 0.07, 0.49), (0.085, 0.2, 0.28), (0.085, 0.27, 0.205))):
        tube(hip, knee, 0.058, jeans, 10, r2=0.05); ball(0.05, knee, jeans, segs=10)
        tube(knee, ankle, 0.05, jeans, 10, r2=0.042)
        a, t = Vector(ankle), Vector(toe)
        tube(a, t, 0.036, shoe, 8, r2=0.03); ball(0.04, a, shoe, segs=10)
    box((0.27, 0.17, 0.15), (0, 0.0, 0.83), jeans, bevel=0.03)                     # hips
    # torso leaning into the walk, shoulders hunched forward
    tube((0, 0.01, 0.84), (0, -0.1, 1.25), 0.13, shirt, 14, r2=0.15)
    ball(0.15, (0, -0.1, 1.25), shirt, scale=(1.15, 0.8, 0.6), segs=14)
    box((0.3, 0.03, 0.12), (0.02, -0.03, 0.9), shirt, rot=(18, 0, 6), bevel=0.01)  # a torn shirt-tail flap
    tube((0, -0.12, 1.3), (0.01, -0.17, 1.38), 0.045, face, 10)                    # neck
    ball(0.1, (0.025, -0.21, 1.43), face, scale=(0.9, 1.0, 1.08), segs=16)         # head, lolling to one side
    ball(0.09, (0.03, -0.16, 1.47), hair, scale=(0.95, 0.85, 0.8), segs=14)    # thin hair on the back of the skull
    for ex in (-0.03, 0.065):
        ball(0.017, (ex, -0.295, 1.44), mat("#2b1c18", 0.6, dirt=0, wear=False), segs=8)  # sunken eyes
    box((0.06, 0.01, 0.015), (0.025, -0.3, 1.37), mat("#3a1814", 0.7, dirt=0, wear=False))   # slack mouth
    # arms out in front, the zombie's reach: torn short sleeves, bare grey forearms
    for s, sh, el, wr in ((-1, (-0.19, -0.1, 1.26), (-0.2, -0.33, 1.19), (-0.15, -0.55, 1.17)),
                          (1, (0.19, -0.1, 1.26), (0.21, -0.32, 1.13), (0.17, -0.53, 1.08))):
        ball(0.065, sh, shirt, segs=12)
        mid = Vector(sh).lerp(Vector(el), 0.5)
        tube(sh, mid, 0.06, shirt, 10, r2=0.055)
        tube(mid, el, 0.042, skin, 10); ball(0.042, el, skin, segs=10)
        tube(el, wr, 0.038, skin, 10, r2=0.032)
        w = Vector(wr); d = (w - Vector(el)).normalized()
        ball(0.04, w + d * 0.03, skin, scale=(0.7, 1.3, 0.6), segs=10)                 # limp hand
        for f in (-0.022, 0.0, 0.022):
            tube(w + d * 0.05 + Vector((f, 0, 0)), w + d * 0.1 + Vector((f, 0, -0.03)), 0.009, skin, 6)
    HEAD.pop()
    return Vector((0, 0, floor)) + (Vector((0.0, -0.02, 0.86)) - pv) * k


def treadwheel_part(state):
    """A zombie treadwheel: an open slatted drum on two wooden hoops shod with iron tyres, riding on four rollers on
    a timber base, held upright by guide posts with rollers at the hoops' sides. The back roller drives a car
    alternator by a belt on the left. Empty, the tether rope hangs off the short post at the front right; walking,
    a grey-green zombie strides in the drum, tied by the waist to that post."""
    p = P(); walking = state == "walking"
    wood = mat("#8b7155", 0.85, var=0.22, dirt=0.4)
    weath = mat("#7e7262", 0.9, var=0.25, dirt=0.4)
    dark = p["wood_dark"]
    iron = mat("#3c3e40", 0.55, 0.45, rust=0.35, dirt=0.3)
    rope = mat("#b39a6c", 0.9, var=0.15, dirt=0.25)
    C, R, W = TREAD_C, TREAD_R, TREAD_W
    # base: two skids along Y, cross ties, roller blocks
    for x in (-0.4, 0.4): box((0.1, 0.96, 0.09), (x, 0, 0.045), dark, bevel=0.01)
    for y in (-0.42, 0.42): box((0.9, 0.08, 0.05), (0, y, 0.115), weath, bevel=0.008)
    rr = 0.05
    rollers = []
    for sy in (-1, 1):
        a = math.radians(38)
        rc = C + Vector((0, sy * math.sin(a), -math.cos(a))) * (R + rr + 0.012)
        rollers.append(rc)
        for x in (-0.4, 0.4): box((0.1, 0.12, rc.z - 0.07), (x, rc.y, 0.09 + (rc.z - 0.07) / 2), wood, bevel=0.01)
        cyl(0.016, 0.9, rc, iron, axis="X", segs=10)
        for x in (-W, W): cyl(rr, 0.06, (x, rc.y, rc.z), iron, axis="X", segs=16)
    # guide posts at the drum's sides, each with a braced foot and a small roller bearing on the hoop
    for x in (-0.4, 0.4):
        box((0.07, 0.07, C.z + 0.02), (x, 0, 0.09 + (C.z - 0.07) / 2), wood, bevel=0.008)
        for sy in (-1, 1): tube((x, sy * 0.3, 0.1), (x, sy * 0.03, 0.5), 0.024, wood, 6)
        cyl(0.03, 0.06, (x - math.copysign(0.07, x), 0, C.z), iron, axis="X", segs=12)
        box((0.1, 0.05, 0.05), (x - math.copysign(0.03, x), 0, C.z + 0.05), dark)
    # the drum: two hoops with iron tyres, slats between them, corner blocks inside the open ends
    for x in (-W, W):
        torus(R - 0.032, 0.032, C + Vector((x, 0, 0)), wood, axis="X", seg=56, rseg=6)
        torus(R - 0.004, 0.011, C + Vector((x, 0, 0)), iron, axis="X", seg=56, rseg=6)
    n = 24
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        d = Vector((0, math.sin(a), -math.cos(a)))
        box((2 * W + 0.05, 0.075, 0.028), C + d * (R - 0.078), weath if i % 3 else wood, rot=(math.degrees(a), 0, 0), bevel=0.006)
    for x in (-W, W):
        for k in range(4):
            a = 2 * math.pi * k / 4 + math.pi / 4
            d = Vector((0, math.sin(a), -math.cos(a)))
            box((0.04, 0.045, 0.045), C + Vector((x, 0, 0)) + d * (R - 0.078), dark, rot=(math.degrees(a), 0, 0))
    # drive: a pulley on the back roller's left end, a belt down to a car alternator on the left skid
    back = rollers[1]
    pul = Vector((-0.425, back.y, back.z))
    cyl(0.055, 0.03, pul, mat("#5d5f61", 0.45, 0.6, rust=0.2), axis="X", segs=24)
    alt = Vector((-0.4, 0.17, 0.155))
    box((0.16, 0.18, 0.025), (-0.43, 0.17, 0.077), dark)
    cyl(0.066, 0.11, alt, mat("#9a9a94", 0.45, 0.55, rust=0.15, dirt=0.35), axis="X", segs=20)
    for k in range(6): box((0.09, 0.004, 0.02), alt + Vector((0, math.cos(k), math.sin(k))) * 0.064, p["steel_dark"], rot=(math.degrees(k), 0, 0), bevel=0)
    ap = alt + Vector((-0.05, 0, 0))
    cyl(0.033, 0.03, ap, p["steel_dark"], axis="X", segs=16)
    for s in (-1, 1):
        dd = (pul - ap); nrm = Vector((0, -dd.z, dd.y)).normalized()
        tube(ap + nrm * 0.033 * s, pul + nrm * 0.055 * s, 0.008, p["rubber"], 6)
    path([(-0.38, 0.24, 0.17), (-0.34, 0.34, 0.1), (-0.38, 0.46, 0.015), (-0.44, 0.52, 0.012)], 0.007, p["wire_r"])
    path([(-0.39, 0.23, 0.13), (-0.36, 0.32, 0.06), (-0.41, 0.46, 0.012), (-0.47, 0.5, 0.01)], 0.007, p["wire_k"])
    # the tether post at the front right, the rope knotted round its head
    tp = Vector((0.4, -0.36, 0.0))
    box((0.08, 0.08, 0.74), tp + Vector((0, 0, 0.42)), wood, bevel=0.01)
    knot = tp + Vector((0, 0, 0.66))
    torus(0.052, 0.014, knot, rope, seg=16, rseg=6); torus(0.052, 0.014, knot + Vector((0, 0, 0.03)), rope, seg=16, rseg=6)
    if walking:
        waist = zombie_walker(C.z - (R - 0.092))
        torus(0.125, 0.014, waist, rope, seg=20, rseg=6, rot=(8, 0, 0))
        mid = knot.lerp(waist, 0.5) + Vector((0, 0, -0.05))
        path([knot + Vector((-0.04, 0.02, 0)), mid, waist + Vector((0.11, -0.02, 0.0))], 0.012, rope, segs=8)
    else:
        path([knot + Vector((-0.03, -0.04, -0.01)), knot + Vector((-0.06, -0.07, -0.2)), knot + Vector((-0.05, -0.08, -0.4)),
              knot + Vector((-0.02, -0.07, -0.5))], 0.012, rope, segs=8)
        torus(0.065, 0.012, knot + Vector((-0.02, -0.07, -0.56)), rope, seg=18, rseg=6, rot=(0, 75, 20))


def treadmill_icon():
    """The Treadmill Generator for its inventory icon: a gym treadmill (deck, belt, motor hood, uprights, console
    and rails) with a car alternator bolted to the hood and red and black leads up to the console."""
    p = P()
    frame = mat("#3a3c40", 0.5, 0.3, dirt=0.2)
    grey = mat("#8e9297", 0.4, 0.55, dirt=0.15)
    box((0.42, 1.1, 0.09), (0, 0.05, 0.065), frame, bevel=0.015)
    box((0.34, 1.0, 0.012), (0, 0.06, 0.114), mat("#1c1d1f", 0.85, dirt=0.05))
    for x in (-0.195, 0.195): box((0.05, 1.04, 0.02), (x, 0.06, 0.118), grey, bevel=0.004)
    for x in (-0.18, 0.18): cyl(0.022, 0.05, (x, 0.58, 0.03), p["rubber"], axis="X", segs=12)
    box((0.46, 0.22, 0.17), (0, -0.55, 0.105), mat("#4a4d52", 0.45, 0.3, dirt=0.15), bevel=0.03)   # motor hood
    for x in (-0.2, 0.2): tube((x, -0.52, 0.18), (x, -0.6, 0.95), 0.03, grey, 12)
    con = Vector((0, -0.63, 1.0))
    box((0.5, 0.16, 0.2), con, frame, rot=(-30, 0, 0), bevel=0.025)                               # console
    box((0.22, 0.01, 0.09), con + Vector((0, 0.07, 0.035)), glow("#7fe08a", 4), rot=(-30, 0, 0), bevel=0)
    for x in (-0.13, 0.15): cyl(0.016, 0.01, con + Vector((x, 0.075, -0.03)), mat("#c23a2e", 0.4), rot=(60, 0, 0), segs=12)
    for x in (-0.24, 0.24):
        path([(x * 0.85, -0.6, 0.93), (x, -0.45, 0.82), (x, 0.0, 0.8)], 0.018, grey, segs=10)
        cyl(0.024, 0.14, (x, -0.12, 0.8), p["rubber"], axis="Y", segs=12)
    alt = Vector((0.31, -0.58, 0.1))
    cyl(0.075, 0.13, alt, mat("#9a9a94", 0.45, 0.55, rust=0.1, dirt=0.3), axis="X", segs=20)
    cyl(0.04, 0.03, alt + Vector((0.08, 0, 0)), p["steel_dark"], axis="X", segs=16)
    path([(0.3, -0.52, 0.17), (0.24, -0.5, 0.35), (0.23, -0.56, 0.7), (0.2, -0.6, 0.92)], 0.011, p["wire_r"])
    path([(0.33, -0.52, 0.16), (0.27, -0.48, 0.34), (0.26, -0.55, 0.68), (0.23, -0.59, 0.9)], 0.011, p["wire_k"])


def rod_icon():
    """The grounding rod laid down for its inventory icon: a thick copper rod with its clamp and a coil of ground wire."""
    p = P(); cu = mat("#b4703f", 0.35, 0.8, var=0.1, dirt=0.1)
    cyl(0.035, 0.62, (0, 0, 0.04), cu, axis="X", segs=16)
    cyl(0.035, 0.08, (0.35, 0, 0.04), cu, axis="X", r2=0.001, rot=(0, 90, 0), segs=16)
    box((0.06, 0.09, 0.09), (-0.22, 0, 0.04), p["brass"], bevel=0.01)
    torus(0.09, 0.016, (-0.05, 0.16, 0.02), mat("#4c8f3a", 0.6), seg=32)
    path([(-0.22, 0.04, 0.06), (-0.15, 0.12, 0.03), (-0.1, 0.16, 0.02)], 0.016, mat("#4c8f3a", 0.6))


def gauge_icon_model():
    """The wall gauge face-on for its icon, without the conduit that makes its world sprite so tall."""
    box((0.24, 0.05, 0.32), (0, 0, 0), mat("#5d666c", 0.45, 0.4, dirt=0.15), bevel=0.014)
    gauge((0, -0.027, 0.04), (0, 0, 0), 0.085, 0.86, rim="#c9ccd0")
    lamp((0, -0.03, -0.1), True, "#6fe07a", 0.02)


# ------------------------------------------------------------------ DazedPower taxonomy (mirrors tools/dp_taxonomy.py)
DP_KINDS = ["array", "bank", "controller", "transformer", "lamp", "pedal", "windmill", "steam", "windsock", "vane",
            "propane", "petrol", "gauge", "rod", "bench", "hydro"]
DP_MOUNTS = {"array": ["ground", "tracker", "xl"], "bank": ["ground", "wall"], "controller": ["ground"], "transformer": ["ground"],
             "lamp": ["garden", "street"], "pedal": ["ground"], "windmill": ["ground"], "steam": ["ground"], "windsock": ["ground"],
             "vane": ["ground"], "propane": ["ground"], "petrol": ["ground"], "gauge": ["wall"], "rod": ["ground"], "bench": ["ground"],
             "hydro": ["ground"]}
THREE = ["makeshift", "salvaged", "workshop"]
DP_TIERS = {"array": THREE, "bank": THREE, "controller": ["makeshift", "workshop"], "transformer": ["standard"],
            "lamp": ["makeshift", "workshop"], "pedal": THREE, "windmill": THREE, "steam": THREE, "windsock": ["basic"],
            "vane": ["basic"], "propane": THREE, "petrol": THREE, "gauge": ["standard"], "rod": ["standard"], "bench": ["standard"],
            "hydro": ["standard"]}
DP_STATES = {"array": ["clear", "snow", "cracked"], "controller": ["off", "on"], "transformer": ["off", "on"], "lamp": ["off", "on"],
             "pedal": ["off", "on"], "windmill": ["still", "turning", "furled", "broken"], "steam": ["cold", "warming", "running", "broken"],
             "windsock": ["limp", "half", "full"], "vane": ["set"], "propane": ["off", "running", "broken"],
             "petrol": ["off", "running", "broken"], "gauge": ["off", "low", "mid", "full"], "rod": ["set"], "bench": ["off", "on"],
             "hydro": ["still", "turning"]}
BANK_CELLS = {"ground": {"makeshift": 3, "salvaged": 6, "workshop": 8}, "wall": {"makeshift": 2, "salvaged": 3, "workshop": 4}}


def dp_states(kind, mount, tier):
    return DP_STATES[kind] if kind != "bank" else ["c%d" % i for i in range(BANK_CELLS[mount][tier] + 1)]


DP_ROWS = []
for _k in DP_KINDS:
    for _m in DP_MOUNTS[_k]:
        for _t in DP_TIERS[_k]:
            for _s in dp_states(_k, _m, _t):
                for _p in range(1, (4 if (_k == "array" and _m == "xl") else 1) + 1):
                    DP_ROWS.append((_k, _m, _t, _s, _p))
# The sheet has grown past the lists above (fence, cooler, heater, windspin); the taxonomy is the one true order, so
# use it when it is beside this folder. Rows with no builder here are skipped by dp_render.
try:
    sys.path.insert(0, os.path.normpath(os.path.join(_here, "..")))
    import dp_taxonomy as _T
    DP_ROWS = list(_T.ROWS)
    DP_TIERS = dict(_T.TIERS)
except Exception as _e:
    print("dz2: dp_taxonomy not found, using the built-in rows:", _e)
DP_FAMILY = {("array", "ground"): "arrays", ("array", "tracker"): "trackers", ("array", "xl"): "xl", ("bank", "ground"): "banks",
             ("bank", "wall"): "walls", ("controller", "ground"): "controllers", ("transformer", "ground"): "transformer",
             ("lamp", "garden"): "lamps", ("lamp", "street"): "lamps", ("gauge", "wall"): "gauges", ("rod", "ground"): "rod",
             ("bench", "ground"): "bench", ("hydro", "ground"): "hydro", ("windspin", "ground"): "windspin",
             ("treadwheel", "ground"): "treadwheel", ("steamfire", "ground"): "steamfire",
             ("woodgasfire", "ground"): "woodgasfire", ("petrolrun", "ground"): "petrolrun", ("propaneflame", "ground"): "propaneflame"}
MP_TIER = {"makeshift": "makeshift", "salvaged": "salvaged", "workshop": "manufactured", "basic": "basic"}
PIECE_OFFSET = {1: (0, 0), 2: (1, 0), 3: (0, 1), 4: (1, 1)}


def dp_family(kind, mount):
    return DP_FAMILY.get((kind, mount), kind)


def set_wear(state, kind):
    WEAR["rust"] = 0.35 if state in ("broken", "cracked") else 0.0
    WEAR["dirt"] = 0.15 if state in ("broken", "cracked") else 0.0
    WEAR["scorch"] = 0.7 if state == "broken" and kind in ("steam", "propane", "petrol", "woodgas") else 0.0


DP_BUILT_KINDS = {"array", "bank", "controller", "transformer", "lamp", "gauge", "rod", "bench", "hydro", "windspin",
                  "fence", "cooler", "heater", "woodgas", "treadwheel", "steamfire", "woodgasfire", "petrolrun", "propaneflame"}


def dp_build(kind, mount, tier, state):
    set_wear("broken" if state == "wobble" else state, kind)
    if kind == "windspin": return build_windmill(MP_TIER[tier], state)
    if kind == "steamfire": return steamfire_part(tier, state)
    if kind == "woodgasfire": return woodgasfire_part(tier, state)
    if kind in ("petrolrun", "propaneflame"): return gasfx_part(kind, tier, state)
    if kind in BUILDERS: return BUILDERS[kind](MP_TIER[tier], state)
    if kind == "array": return {"ground": array_static, "tracker": array_tracker, "xl": array_xl}[mount](tier, state)
    if kind == "bank": return (bank_ground if mount == "ground" else bank_wall)(tier, int(state[1:]))
    if kind == "controller": return controller(tier, state)
    if kind == "transformer": return transformer(state)
    if kind == "lamp": return lamp_part(mount, tier, state)
    if kind == "gauge": return gauge_part(state)
    if kind == "rod": return rod_part()
    if kind == "bench": return bench_part(state)
    if kind == "hydro": return hydro_part(state)
    if kind == "fence": return fence_part(state)
    if kind == "cooler": return cooler_part(state)
    if kind == "heater": return heater_part(state)
    if kind == "woodgas": return woodgas_part(tier, state)
    if kind == "treadwheel": return treadwheel_part(state)


def steamfire_part(tier, frame):
    """A steam engine's fire frame (the client cycles these, DP_SteamFx): the running engine with its firebox door
    open on flames, fire1..fire4, the smoke climbing a quarter puff a frame; or the idle engine (the warming sprite)
    with the door open on banked embers. Everything but the firebox and the smoke is the plain sprite's model."""
    global STEAM_FRAME
    STEAM_FRAME = frame
    try:
        build_steam(MP_TIER[tier], "warming" if frame == "embers" else "running")
    finally:
        STEAM_FRAME = None


def woodgasfire_part(tier, frame):
    """A wood gas generator's fire frame (DP_GenFx): the running set with the gasifier's ash door open on flames,
    fire1..fire4, its exhaust smoke climbing a quarter puff a frame; or the warming set with the door open on embers."""
    global WG_FRAME
    WG_FRAME = frame
    try:
        woodgas_part(tier, "warming" if frame == "embers" else "running")
    finally:
        WG_FRAME = None


def gasfx_part(kind, tier, frame):
    """A running petrol engine shaking with its thin exhaust puff (run1..run3), or a running propane engine's blue
    burner flame and heat shimmer (flame1..flame3): dz_render's build_gas with GAS_FRAME set (DP_GenFx)."""
    global GAS_FRAME
    GAS_FRAME = frame
    try:
        build_gas("petrol" if kind == "petrolrun" else "propane", MP_TIER[tier], "running")
    finally:
        GAS_FRAME = None


def make_root(start):
    root = bpy.data.objects.new("root", None); MODEL.objects.link(root)
    fixed = bpy.data.objects.new("fixed", None); MODEL.objects.link(fixed)
    for ob in BUILT[start:]:
        if ob not in (root, fixed): ob.parent = fixed if ob in FIXED else root
    return root, fixed


MASK = None


def mask_material():
    """Emits white where a surface stands over the square under the camera (|x|,|y| < 0.5 in world space)."""
    global MASK
    if MASK: return MASK
    m = bpy.data.materials.new("dz_mask")
    try: m.use_nodes = True
    except Exception: pass
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    geo = nt.nodes.new("ShaderNodeNewGeometry"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    t = []
    for ax in ("X", "Y"):
        ab = nt.nodes.new("ShaderNodeMath"); ab.operation = "ABSOLUTE"; nt.links.new(sep.outputs[ax], ab.inputs[0])
        lt = nt.nodes.new("ShaderNodeMath"); lt.operation = "LESS_THAN"; lt.inputs[1].default_value = 0.5
        nt.links.new(ab.outputs[0], lt.inputs[0]); t.append(lt)
    both = nt.nodes.new("ShaderNodeMath"); both.operation = "MULTIPLY"
    nt.links.new(t[0].outputs[0], both.inputs[0]); nt.links.new(t[1].outputs[0], both.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (1, 1, 1, 1)
    nt.links.new(both.outputs[0], em.inputs["Strength"])
    out = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0], out.inputs["Surface"])
    MASK = m
    return m


def render_mask(path):
    vl = bpy.context.view_layer; keep = scene.cycles.samples
    hidden = [o for o in MODEL.objects if o.type == "LIGHT"]
    for o in hidden: o.hide_render = True
    vl.material_override = mask_material(); scene.cycles.samples = 8
    try: render(path)
    finally:
        vl.material_override = None; scene.cycles.samples = keep
        for o in hidden: o.hide_render = False


def dp_render(families=None, only_rows=None):
    tile_camera(); done = set()
    for ri, (k, mo, t, s, piece) in enumerate(DP_ROWS):
        fam = dp_family(k, mo)
        if families and fam not in families and "all" not in families: continue
        if only_rows is not None and ri not in only_rows: continue
        if (k, mo, t, s) in done: continue
        if k not in BUILDERS and k not in DP_BUILT_KINDS: continue        # no model here
        done.add((k, mo, t, s))
        clear(); start = len(BUILT); dp_build(k, mo, t, s); root, fixed = make_root(start)
        out = os.path.join(OUT, "dp", fam); os.makedirs(out, exist_ok=True)
        pieces = 4 if mo == "xl" else 1
        for col, (fname, deg) in enumerate(FACINGS):
            root.rotation_euler = fixed.rotation_euler = (0, 0, math.radians(deg))
            for p in range(1, pieces + 1):
                dx, dy = PIECE_OFFSET[p]
                off = (0.5 - dx, dy - 0.5, 0) if pieces > 1 else (0, 0, 0)
                root.location = fixed.location = off
                idx = (ri + (p - 1)) * 4 + col
                render(os.path.join(out, "%d.png" % idx))
                if pieces > 1: render_mask(os.path.join(out, "%d_m.png" % idx))
        log("dp", ri, k, mo, t, s)


# ------------------------------------------------------------------ DazedPlumbing
PL_TYPES = ["propane", "gas", "water"]; PL_TIERS = ["salvaged", "crafted"]
PL_SIZES = [("small", 1), ("large", 2), ("xl", 3)]; PL_BLOCK = {"small": 0, "large": 24, "xl": 72}
TANK_COL = {"propane": "#e2e0d8", "gas": "#a8342b", "water": "#3366ad"}
TANK_FADED = {"propane": "#d2ccbe", "gas": "#92402f", "water": "#4d76a6"}
PIPE_R, GROUND_Z, OVERHEAD_Z, CEILING_Z = 0.055, 0.075, 1.76, 2.62
ARMS = {1: (0, 1), 2: (1, 0), 4: (0, -1), 8: (-1, 0)}
PIPE_BASE, VALVE_BASE, PORT_BASE = 144, 196, 216
PUMP_BASE, PURIFIER_BASE, SPOUT_BASE, SPRINKLER_BASE, STROKE_BASE = 176, 184, 192, 204, 212
MAIN_BASE, FUEL_BASE, DIGESTER_BASE = 232, 236, 244


def tank_paint(typ, tier):
    if tier == "crafted": return mat(TANK_COL[typ], 0.45, 0.15, var=0.06, dirt=0.15)
    return mat(TANK_FADED[typ], 0.6, 0.1, var=0.2, rust=0.35, dirt=0.4)


def stand(h=0.3, w=0.62):
    """The low steel stand every small tank sits on, so a pipe can rise into its belly."""
    s = mat("#4f5458", 0.5, 0.4, rust=0.2, dirt=0.3)
    box((w, w, 0.03), (0, 0, h - 0.015), s)
    for x in (-w / 2 + 0.03, w / 2 - 0.03):
        for y in (-w / 2 + 0.03, w / 2 - 0.03): box((0.04, 0.04, h - 0.03), (x, y, (h - 0.03) / 2), s)
    for x in (-w / 2 + 0.03, w / 2 - 0.03): box((0.03, w, 0.03), (x, 0, 0.05), s)


def small_tank(typ, tier):
    p = P(); paint = tank_paint(typ, tier); z0 = 0.3
    stand()
    if typ == "propane":
        cyl(0.2, 0.72, (0, 0, z0 + 0.4), paint, segs=32)
        ball(0.2, (0, 0, z0 + 0.76), paint, scale=(1, 1, 0.5)); ball(0.2, (0, 0, z0 + 0.04), paint, scale=(1, 1, 0.25))
        cyl(0.17, 0.04, (0, 0, z0 + 0.02), paint, segs=28)
        cyl(0.13, 0.14, (0, 0, z0 + 0.92), paint, segs=24, caps=False)
        cyl(0.02, 0.06, (0, 0, z0 + 0.9), p["brass"], segs=10)
        box((0.06, 0.015, 0.015), (0.025, 0, z0 + 0.94), mat("#2b2c30", 0.6))
        box((0.12, 0.004, 0.1), (0, -0.2, z0 + 0.45), mat("#d6d2c4" if tier == "crafted" else "#bdb6a2", 0.6, dirt=0.2))
    elif typ == "gas":
        cyl(0.28, 0.86, (0, 0, z0 + 0.43), paint, segs=36)
        for z in (0.29, 0.57): torus(0.28, 0.012, (0, 0, z0 + z), paint, seg=40)
        torus(0.27, 0.015, (0, 0, z0 + 0.86), paint, seg=40)
        cyl(0.03, 0.02, (0.15, 0.08, z0 + 0.87), p["steel_dark"], segs=10)
        if tier == "crafted":
            cyl(0.025, 0.25, (-0.12, 0, z0 + 0.98), mat("#3a3c40", 0.5, 0.4), segs=10)
            box((0.08, 0.08, 0.1), (-0.12, 0, z0 + 1.1), mat("#3a3c40", 0.5, 0.4), bevel=0.01)
            tube((-0.12, 0, z0 + 1.14), (-0.02, 0, z0 + 1.18), 0.008, p["steel"]); tube((-0.16, 0, z0 + 1.12), (-0.24, -0.06, z0 + 1.0), 0.012, p["rubber"])
        box((0.14, 0.004, 0.14), (0, -0.281, z0 + 0.45), mat("#d7b43c", 0.6, dirt=0.2), rot=(0, 45, 0))
    else:
        cyl(0.28, 0.78, (0, 0, z0 + 0.41), paint, segs=36)
        ball(0.28, (0, 0, z0 + 0.8), paint, scale=(1, 1, 0.22)); ball(0.28, (0, 0, z0 + 0.02), paint, scale=(1, 1, 0.12))
        for z in (0.3, 0.55): torus(0.282, 0.01, (0, 0, z0 + z), paint, seg=40)
        for x in (-0.12, 0.12): cyl(0.04, 0.03, (x, 0.05, z0 + 0.86), mat("#2d4d86" if tier == "crafted" else "#45618c", 0.5), segs=12)
        cyl(0.018, 0.08, (0, -0.31, z0 + 0.12), p["brass"], axis="Y", segs=10); box((0.04, 0.012, 0.03), (0, -0.35, z0 + 0.15), p["brass"])


def oil_tank(n, typ, tier):
    """A horizontal cylinder on saddles, n squares long along X; the belly sits at z 0.31."""
    p = P(); paint = tank_paint(typ, tier)
    r = 0.42 if n == 2 else 0.5; L = n - 0.12 - 0.6 * r; zc = 0.31 + r            # domes stay inside the footprint, or the masks cut them
    cyl(r, L - r * 0.6, (0, 0, zc), paint, axis="X", segs=40)
    for s in (-1, 1): ball(r, (s * (L / 2 - r * 0.3), 0, zc), paint, scale=(0.6, 1, 1), segs=32)
    sad = mat("#4f5458", 0.5, 0.4, rust=0.25 if tier == "salvaged" else 0.05)
    xs = [-L / 2 + 0.35 + i * (L - 0.7) / max(1, n) for i in range(n + 1)] if n > 2 else [-L / 2 + 0.35, L / 2 - 0.35]
    for x in xs:
        box((0.1, r * 1.5, 0.31 + r * 0.4), (x, 0, (0.31 + r * 0.4) / 2), sad, bevel=0.01)
        box((0.18, r * 1.7, 0.05), (x, 0, 0.025), p["concrete"])
    cyl(0.12, 0.06, (L / 4, 0, zc + r), paint, segs=20); cyl(0.13, 0.015, (L / 4, 0, zc + r + 0.03), paint, segs=20)
    cyl(0.03, 0.08, (-L / 4, 0, zc + r), p["steel_dark"], segs=12)
    gauge((-L / 4 + 0.15, -0.05, zc + r + 0.06), (-60, 0, 0), 0.035, 0.6, rim="#b08c4a")
    for x in (-L / 2 + 0.25, L / 2 - 0.25):
        torus(r + 0.004, 0.01, (x, 0, zc), paint, axis="X", seg=40)
    label = {"propane": "#c9c4b5", "gas": "#d7b43c", "water": "#d9dde2"}[typ]
    box((0.16, 0.004, 0.16), (0, -r - 0.003, zc), mat(label, 0.6, dirt=0.2), rot=(0, 45, 0))
    if tier == "salvaged":
        box((0.22, 0.006, 0.07), (L / 4, -r * 0.98, zc - r * 0.2), mat("#5a4636", 0.7, 0.3, rust=0.7), rot=(15, 0, 0))
    if n == 3:
        for k in range(5): box((0.3, 0.02, 0.02), (L / 2 - 0.1, -r - 0.05, 0.15 + k * 0.22), sad) if False else None
        for y in (-r - 0.05, -r - 0.05):
            pass
        tube((L / 2 - 0.15, -r * 0.7, 0.05), (L / 2 - 0.15, -r * 0.7, zc + r), 0.012, sad); tube((L / 2 - 0.35, -r * 0.7, 0.05), (L / 2 - 0.35, -r * 0.7, zc + r), 0.012, sad)
        for k in range(1, 5): tube((L / 2 - 0.35, -r * 0.7, k * (zc + r) / 5), (L / 2 - 0.15, -r * 0.7, k * (zc + r) / 5), 0.008, sad)


def pl_tank(size, typ, tier):
    set_wear("ok", "tank")
    if size == "small": small_tank(typ, tier)
    else: oil_tank(2 if size == "large" else 3, typ, tier)


def pipe_mats():
    return mat("#e6e8ec", 0.42, var=0.05, dirt=0.1, wear=False), mat("#cfd3d8", 0.38, var=0.05, dirt=0.15, wear=False)


def pipe_cell(mask, outdoor):
    pipe, fit = pipe_mats()
    z = GROUND_Z if outdoor else OVERHEAD_Z
    bits = [b for b in (1, 2, 4, 8) if mask & b]; reach = 0.56
    if not bits:
        tube((-0.22, 0, z), (0.22, 0, z), PIPE_R, pipe, 20)
        for x in (-0.22, 0.22): cyl(PIPE_R * 1.3, 0.05, (x, 0, z), fit, axis="X")
    for b in bits:
        dx, dy = ARMS[b]; tube((0, 0, z), (dx * reach, dy * reach, z), PIPE_R, pipe, 20)
    if mask in (5, 10):
        ax = "Y" if mask == 5 else "X"
        cyl(PIPE_R * 1.3, 0.09, (0, 0, z), fit, axis=ax)
        for s in (-1, 1): cyl(PIPE_R * 1.15, 0.015, ((0.055 * s) if ax == "X" else 0, (0.055 * s) if ax == "Y" else 0, z), fit, axis=ax, segs=6)
    elif bits:
        ball(PIPE_R * 1.4, (0, 0, z), fit)
        for b in bits:
            dx, dy = ARMS[b]; cyl(PIPE_R * 1.25, 0.06, (dx * 0.075, dy * 0.075, z), fit, axis="X" if dx else "Y")
        if len(bits) == 1:
            dx, dy = ARMS[bits[0]]; cyl(PIPE_R * 1.32, 0.05, (-dx * 0.04, -dy * 0.04, z), fit, axis="X" if dx else "Y")
    if outdoor:
        for b in bits or [2]:
            dx, dy = ARMS[b]; box((0.1, 0.1, 0.03), (dx * 0.32, dy * 0.32, 0.015), mat("#9c9a93", 0.95, dirt=0.2, wear=False), bevel=0.006)
    else:
        torus(PIPE_R + 0.012, 0.008, (0, 0, z), fit, axis="Y" if (mask & 5) and not (mask & 10) else "X")
        tube((0, 0, z + PIPE_R), (0, 0, CEILING_Z), 0.008, fit, 8)
        cyl(0.035, 0.012, (0, 0, CEILING_Z), fit)


def holdout():
    m = bpy.data.materials.get("dz_holdout") or bpy.data.materials.new("dz_holdout")
    try: m.use_nodes = True
    except Exception: pass
    nt = m.node_tree; nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial"); h = nt.nodes.new("ShaderNodeHoldout"); nt.links.new(h.outputs[0], o.inputs[0])
    return m


def valve_cell(outdoor, ns, closed):
    brass = mat("#c99d45", 0.32, 0.7, dirt=0.15, wear=False); nut = mat("#a17f3a", 0.4, 0.6, wear=False)
    lever = mat("#b8302a", 0.5, dirt=0.1, wear=False)
    z = GROUND_Z if outdoor else OVERHEAD_Z; ax = "Y" if ns else "X"; d = (0, 1) if ns else (1, 0)
    tube((-d[0] * 0.6, -d[1] * 0.6, z), (d[0] * 0.6, d[1] * 0.6, z), PIPE_R * 1.01, holdout(), 20)
    cyl(PIPE_R * 1.5, 0.12, (0, 0, z), brass, axis=ax, segs=24)
    for s in (-1, 1): cyl(PIPE_R * 1.32, 0.045, (d[0] * 0.08 * s, d[1] * 0.08 * s, z), nut, axis=ax, segs=6)
    top = z + PIPE_R * 1.5
    cyl(0.014, 0.05, (0, 0, top + 0.02), brass, segs=12); cyl(0.022, 0.012, (0, 0, top + 0.045), nut, segs=6)
    run = d if not closed else (-d[1], d[0]); L = 0.2
    box((L if run[0] else 0.03, L if run[1] else 0.03, 0.012), (run[0] * L / 2, run[1] * L / 2, top + 0.05), lever, bevel=0.004)
    box((0.045, 0.045, 0.022), (run[0] * L, run[1] * L, top + 0.05), lever, bevel=0.008)


def port_cell(bit, overhead, belly):
    pipe, fit = pipe_mats(); dx, dy = ARMS[bit]; ax = "X" if dx else "Y"

    def at(r, z): return (dx * r, dy * r, z)
    start = 0.56
    if overhead:
        tube(at(0.56, OVERHEAD_Z), at(0.42, OVERHEAD_Z), PIPE_R, pipe, 20); ball(PIPE_R * 1.4, at(0.42, OVERHEAD_Z), fit)
        tube(at(0.42, OVERHEAD_Z), at(0.42, GROUND_Z), PIPE_R, pipe, 20); ball(PIPE_R * 1.4, at(0.42, GROUND_Z), fit)
        start = 0.42
    stop = 0.14 if belly else 0.08
    tube(at(start, GROUND_Z), at(stop, GROUND_Z), PIPE_R, pipe, 20)
    box((0.1, 0.1, 0.03), at((start + stop) / 2, 0.015), mat("#9c9a93", 0.95, dirt=0.2, wear=False), bevel=0.006)
    if belly:
        ball(PIPE_R * 1.4, at(stop, GROUND_Z), fit); tube(at(stop, GROUND_Z), at(stop, 0.31), PIPE_R, pipe, 20)
        cyl(PIPE_R * 1.75, 0.035, at(stop, 0.3), fit)
    else:
        cyl(PIPE_R * 1.4, 0.07, at(0.3, GROUND_Z), fit, axis=ax, segs=6); ball(PIPE_R * 1.2, at(stop, GROUND_Z), fit)


def hand_pump(stroke=False):
    p = P(); iron = mat("#2f3133", 0.6, 0.35, var=0.12, rust=0.35, dirt=0.3)
    plank = p["wood_grey"]
    for i in range(5): box((0.7, 0.13, 0.04), (0, -0.28 + i * 0.14, 0.03), plank, rot=(0, 0, random.Random(i).uniform(-2, 2)))
    for x in (-0.3, 0.3): box((0.06, 0.7, 0.05), (x, 0, 0.005), p["wood_dark"])
    box((0.16, 0.16, 0.04), (0, 0.05, 0.07), iron, bevel=0.01)
    cyl(0.07, 0.42, (0, 0.05, 0.3), iron, segs=20); cyl(0.09, 0.05, (0, 0.05, 0.52), iron, segs=20)
    cyl(0.08, 0.06, (0, 0.05, 0.57), iron, segs=20); ball(0.05, (0, 0.05, 0.6), iron)
    tube((0, -0.02, 0.43), (0, -0.2, 0.4), 0.025, iron, 12); tube((0, -0.2, 0.4), (0, -0.23, 0.33), 0.022, iron, 12)
    piv = Vector((0, 0.13, 0.62))
    tip = Vector((0, 0.5, 0.86)) if not stroke else Vector((0, 0.5, 0.42))
    tube(piv, tip, 0.016, iron, 10); ball(0.022, tip, iron)
    box((0.02, 0.04, 0.1), (0, 0.11, 0.6), iron)
    box((0.2, 0.2, 0.18), (0.0, -0.3, 0.13), mat("#7e7f7c", 0.5, 0.5, rust=0.3), bevel=0.01) if False else None
    cyl(0.1, 0.16, (0.0, -0.3, 0.13), mat("#7d8285", 0.45, 0.6, rust=0.2), r2=0.12, segs=20, caps=True)


def electric_pump():
    p = P(); blue = mat("#3a62a0", 0.45, 0.3, dirt=0.2)
    box((0.7, 0.55, 0.08), (0, 0, 0.04), p["concrete"], bevel=0.01)
    cyl(0.16, 0.5, (0.17, 0.08, 0.33), mat("#5d7186", 0.4, 0.4, dirt=0.15), segs=28); ball(0.16, (0.17, 0.08, 0.58), mat("#5d7186", 0.4, 0.4), scale=(1, 1, 0.4))
    cyl(0.1, 0.24, (-0.15, -0.05, 0.2), blue, axis="X", segs=24)
    for i in range(8): box((0.22, 0.006, 0.012), (-0.15, -0.05 + 0.0, 0.2), blue) if False else None
    box((0.12, 0.14, 0.16), (-0.02, -0.05, 0.2), mat("#2f3a46", 0.45, 0.4), bevel=0.01)
    cyl(0.1, 0.02, (-0.28, -0.05, 0.2), mat("#20242a", 0.5), axis="X", segs=24)
    box((0.08, 0.06, 0.06), (-0.15, -0.05, 0.33), mat("#2a2b2d", 0.5), bevel=0.008)
    gauge((0.05, -0.12, 0.32), (0, 0, 0), 0.03, 0.55)
    path([(0.02, -0.05, 0.28), (0.02, 0.0, 0.36), (0.1, 0.05, 0.36)], 0.016, p["galv"])
    cyl(0.04, 0.12, (-0.02, 0.12, 0.08), p["galv"], segs=14)
    path([(-0.15, -0.01, 0.36), (-0.3, 0.2, 0.2), (-0.4, 0.42, 0.02)], 0.008, p["wire_k"])


def purifier():
    p = P(); post = p["wood"]
    for x in (-0.32, 0.32): box((0.07, 0.07, 1.2), (x, 0.1, 0.6), post)
    box((0.72, 0.03, 0.7), (0, 0.13, 0.75), p["ply"])
    for i, x in enumerate((-0.2, 0.0, 0.2)):
        clear = mat("#b9cbd4", 0.15, alpha=0.6, dirt=0.05, wear=False) if i < 2 else mat("#dfe2e3", 0.4, dirt=0.1)
        cyl(0.065, 0.32, (x, 0.04, 0.68), clear, segs=20); cyl(0.07, 0.06, (x, 0.04, 0.87), mat("#2f5f9e", 0.45), segs=20)
        if i < 2: cyl(0.04, 0.26, (x, 0.04, 0.68), mat("#efe8d8", 0.8), segs=14)
    pipe, fit = pipe_mats()
    tube((-0.3, 0.04, 0.95), (0.3, 0.04, 0.95), 0.018, pipe, 12)
    for x in (-0.2, 0.0, 0.2): tube((x, 0.04, 0.9), (x, 0.04, 0.95), 0.014, fit, 10)
    cyl(0.03, 0.5, (0.0, 0.08, 1.2), mat("#d9d6cc", 0.4), axis="X", segs=14); cyl(0.022, 0.48, (0, 0.06, 1.2), glow("#9fd8ff", 2.5), axis="X", segs=14)
    tube((0.3, 0.04, 0.95), (0.3, 0.04, 0.25), 0.018, pipe, 12); tube((0.3, 0.04, 0.25), (0.3, -0.1, 0.25), 0.018, pipe, 12)
    box((0.03, 0.06, 0.03), (0.3, -0.13, 0.27), p["brass"])
    tube((-0.3, 0.04, 0.95), (-0.3, 0.04, 0.075), 0.018, pipe, 12)
    box((0.2, 0.2, 0.18), (0.3, -0.15, 0.09), mat("#5c6c78", 0.5, 0.2), bevel=0.01) if False else None


def downspout():
    """The wall is on the front edge (-Y); the pipe runs down it and kicks out toward the square."""
    p = P(); al = mat("#e2e0d9", 0.4, 0.2, var=0.06, dirt=0.3)
    y = -0.46
    box((0.9, 0.12, 0.1), (0, y + 0.02, 2.42), al, bevel=0.01)
    box((0.012, 0.13, 0.11), (0.45, y + 0.02, 2.42), al)
    path([(0.0, y + 0.02, 2.37), (0.0, y + 0.04, 2.3), (0.0, y + 0.02, 2.22)], 0.035, al)
    box((0.07, 0.05, 2.1), (0, y, 1.17), al, bevel=0.008)
    for z in (0.6, 1.4, 2.0): box((0.09, 0.012, 0.02), (0, y - 0.03, z), mat("#8d9295", 0.4, 0.5))
    path([(0, y, 0.15), (0, y + 0.08, 0.07), (0, y + 0.3, 0.05)], 0.035, al)
    box((0.22, 0.4, 0.03), (0, y + 0.42, 0.015), p["concrete"], bevel=0.008)


def sprinkler(on):
    p = P(); brass = mat("#c39a48", 0.32, 0.7, dirt=0.2)
    for a in (90, 210, 330):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        tube(d * 0.2, Vector((0, 0, 0.3)), 0.008, p["steel"], 6)
    cyl(0.012, 0.42, (0, 0, 0.34), p["steel"], segs=8)
    cyl(0.025, 0.06, (0, 0, 0.58), brass, segs=12)
    tube((0, 0, 0.6), (0.0, -0.13, 0.66), 0.01, brass, 8)
    box((0.02, 0.1, 0.012), (0.0, -0.04, 0.64), brass, rot=(0, 0, 30 if on else 0))
    path([(0, 0, 0.1), (0.1, 0.1, 0.03), (0.25, 0.3, 0.02), (0.4, 0.45, 0.02)], 0.012, mat("#3a6b3a", 0.5))
    if on:
        wat = puff("#d6e7f2", 0.45)
        wat = puff("#d6e7f2", 0.28)
        for k in range(30):
            t = k / 29
            x = 0.03 * math.sin(k * 1.7) * t; y = -0.13 - t * 0.9; z = 0.66 + 0.5 * t - 0.65 * t * t
            ball(0.008 + 0.012 * t, (x, y, z), wat, segs=8)
        for k in range(8):
            t = k / 7; ball(0.02 + 0.03 * t, (0.15 * t, -0.1 - 0.4 * t, 0.62 + 0.15 * t - 0.4 * t * t), puff("#e0edf5", 0.3), segs=10)


def water_main():
    p = P()
    box((0.5, 0.5, 0.1), (0, 0.05, 0.05), p["concrete"], bevel=0.015)
    box((0.36, 0.36, 0.012), (0, 0.05, 0.106), mat("#38393b", 0.6, 0.4, rust=0.3), bevel=0.004)
    for i in range(4): box((0.3, 0.012, 0.004), (0, -0.06 + i * 0.07, 0.113), mat("#2a2b2c", 0.6))
    blue = mat("#2f5f9e", 0.45, 0.2, dirt=0.2)
    cyl(0.04, 0.42, (0.0, -0.12, 0.3), blue, segs=14)
    torus(0.07, 0.01, (0.0, -0.12, 0.52), mat("#2d5aa0", 0.4, 0.3), seg=24)
    for a in range(3): tube((0, -0.12, 0.52), (math.cos(a * 2.1) * 0.07, -0.12 + math.sin(a * 2.1) * 0.07, 0.52), 0.007, blue, 6)
    tube((0, -0.12, 0.3), (0, -0.4, 0.3), 0.035, blue, 14); ball(0.04, (0, -0.12, 0.3), blue)
    tube((0, -0.4, 0.3), (0, -0.4, GROUND_Z), 0.035, blue, 14)
    cyl(0.045, 0.06, (0, -0.25, 0.3), p["brass"], axis="Y", segs=6)


def fuel_pump(electric):
    p = P(); red = mat("#ad3128", 0.5, 0.2, var=0.1, dirt=0.25)
    box((0.42, 0.42, 0.06), (0, 0.05, 0.03), p["concrete"], bevel=0.01)
    box((0.2, 0.2, 0.9), (0, 0.05, 0.51), red, bevel=0.02)
    box((0.22, 0.22, 0.06), (0, 0.05, 0.99), mat("#d7b43c", 0.5) if electric else red, bevel=0.015)
    box((0.14, 0.01, 0.12), (0, -0.052, 0.8), mat("#e8e2cf", 0.5, dirt=0.15))
    gauge((0, -0.06, 0.62), (0, 0, 0), 0.045, 0.3)
    box((0.04, 0.06, 0.12), (0.12, 0.02, 0.6), mat("#2b2c2f", 0.5), bevel=0.008)
    path([(0.12, -0.02, 0.56), (0.24, -0.14, 0.4), (0.22, -0.16, 0.2), (0.14, -0.1, 0.68)], 0.014, p["rubber"])
    box((0.03, 0.12, 0.05), (0.14, -0.08, 0.66), mat("#2b2c2f", 0.5), rot=(-30, 0, 0))
    if electric:
        box((0.1, 0.06, 0.1), (-0.13, 0.05, 0.7), mat("#3a3d40", 0.45, 0.3), bevel=0.008)
        lamp((-0.13, 0.015, 0.73), True, "#6fe07a", 0.008)
        path([(-0.13, 0.08, 0.65), (-0.2, 0.25, 0.2), (-0.3, 0.42, 0.02)], 0.008, p["wire_k"])
    else:
        cyl(0.05, 0.03, (-0.115, 0.05, 0.75), p["steel_dark"], axis="X", segs=16)
        tube((-0.13, 0.05, 0.75), (-0.13, 0.05, 0.6), 0.012, p["steel"]); tube((-0.13, 0.05, 0.6), (-0.2, 0.05, 0.6), 0.015, p["rubber"])
    pipe, fit = pipe_mats()
    tube((0, 0.05, 0.08), (0, 0.05, GROUND_Z), PIPE_R, pipe)


def digester():
    p = P(); poly = mat("#2e3a30", 0.55, var=0.12, dirt=0.3)
    box((0.86, 0.86, 0.06), (0, 0, 0.03), p["concrete"], bevel=0.01)
    cyl(0.4, 0.6, (0, 0.04, 0.36), poly, segs=40); ball(0.4, (0, 0.04, 0.66), poly, scale=(1, 1, 0.45))
    for z in (0.22, 0.48): torus(0.4, 0.012, (0, 0.04, z), poly, seg=48)
    cyl(0.12, 0.06, (0, 0.04, 0.85), poly, segs=20)
    bag = mat("#7a6a4c", 0.75, var=0.15, dirt=0.2)
    ball(0.16, (-0.22, 0.24, 0.8), bag, scale=(1.3, 0.9, 0.35))
    path([(0, 0.04, 0.88), (0, 0.04, 0.94), (-0.12, 0.16, 0.86)], 0.012, p["rubber"])
    cyl(0.1, 0.25, (0.3, -0.24, 0.3), mat("#5d5e5c", 0.6, 0.3, rust=0.2), r2=0.06, segs=16, rot=(-30, 0, 0))
    tube((0, 0.04, 0.8), (0.3, -0.25, 0.5), 0.012, p["galv"])
    gauge((0.0, -0.37, 0.5), (0, 0, 0), 0.035, 0.4)
    cyl(0.02, 0.04, (0.12, 0.04, 0.9), p["brass"])


def facings_render(build_fn, out, index_of):
    clear(); start = len(BUILT); build_fn(); root, fixed = make_root(start)
    os.makedirs(out, exist_ok=True)
    for col, (fname, deg) in enumerate(FACINGS):
        root.rotation_euler = fixed.rotation_euler = (0, 0, math.radians(deg))
        root.location = fixed.location = (0, 0, 0)
        render(os.path.join(out, "%d.png" % index_of(col)))


def fixed_render(build_fn, out, idx):
    clear(); build_fn(); os.makedirs(out, exist_ok=True)
    render(os.path.join(out, "%d.png" % idx))


def pl_render(families):
    tile_camera(); allf = "all" in families
    WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)

    def want(f): return allf or f in families
    if want("tanks"):
        for size, n in PL_SIZES:
            for ti, typ in enumerate(PL_TYPES):
                for ri, tier in enumerate(PL_TIERS):
                    clear(); start = len(BUILT); pl_tank(size, typ, tier); root, fixed = make_root(start)
                    r = ti * 2 + ri; out = os.path.join(OUT, "pl", "tanks"); os.makedirs(out, exist_ok=True)
                    for col, (fname, deg) in enumerate(FACINGS):
                        root.rotation_euler = (0, 0, math.radians(deg))
                        along_x = fname in ("S", "N")
                        centre = ((n - 1) / 2, 0) if along_x else (0, -(n - 1) / 2)
                        for pc in range(n):
                            piece = (pc, 0) if along_x else (0, -pc)
                            root.location = (centre[0] - piece[0], centre[1] - piece[1], 0)
                            idx = PL_BLOCK[size] + (r * 4 + col) * n + pc
                            render(os.path.join(out, "%d.png" % idx))
                            if n > 1: render_mask(os.path.join(out, "%d_m.png" % idx))
                    log("pl tank", size, typ, tier)
    if want("pipes"):
        for i in range(32): fixed_render(lambda i=i: pipe_cell(i % 16, i < 16), os.path.join(OUT, "pl", "pipes"), PIPE_BASE + i)
        log("pl pipes")
    if want("valves"):
        for i in range(8): fixed_render(lambda i=i: valve_cell(i < 4, (i % 4) >= 2, i % 2 == 1), os.path.join(OUT, "pl", "valves"), VALVE_BASE + i)
        log("pl valves")
    if want("ports"):
        for i in range(16): fixed_render(lambda i=i: port_cell((1, 2, 4, 8)[i % 4], (i // 4) % 2 == 1, i >= 8), os.path.join(OUT, "pl", "ports"), PORT_BASE + i)
        log("pl ports")
    out = os.path.join(OUT, "pl", "machines")
    if want("machines"):
        facings_render(hand_pump, out, lambda c: PUMP_BASE + c)
        facings_render(electric_pump, out, lambda c: PUMP_BASE + 4 + c)
        facings_render(lambda: hand_pump(True), out, lambda c: STROKE_BASE + c)
        facings_render(purifier, out, lambda c: PURIFIER_BASE + c)
        facings_render(downspout, out, lambda c: SPOUT_BASE + c)
        facings_render(lambda: sprinkler(False), out, lambda c: SPRINKLER_BASE + c)
        facings_render(lambda: sprinkler(True), out, lambda c: SPRINKLER_BASE + 4 + c)
        facings_render(water_main, out, lambda c: MAIN_BASE + c)
        facings_render(lambda: fuel_pump(False), out, lambda c: FUEL_BASE + c)
        facings_render(lambda: fuel_pump(True), out, lambda c: FUEL_BASE + 4 + c)
        facings_render(digester, out, lambda c: DIGESTER_BASE + c)
        log("pl machines")


# ------------------------------------------------------------------ icons
def book(cover, emblem):
    p = P()
    box((0.2, 0.28, 0.04), (0, 0, 0.02), mat(cover, 0.7, var=0.15, dirt=0.25), bevel=0.006)
    box((0.19, 0.27, 0.032), (0.005, 0, 0.02), mat("#e8e2cf", 0.8, dirt=0.15))
    box((0.012, 0.28, 0.042), (-0.099, 0, 0.02), mat(cover, 0.6, dirt=0.2))
    box((0.2, 0.28, 0.006), (0, 0, 0.042), mat(cover, 0.7, var=0.15, dirt=0.25), bevel=0.003)
    emblem()


def manual_basic():
    book("#5d6e3c", lambda: (uv_quad(0.1, 0.1, cells_mat(3, 3), M((0.01, 0.03, 0.046))),
                              box((0.14, 0.03, 0.002), (0.01, -0.09, 0.046), mat("#e8e2cf", 0.6))))


def manual_adv():
    book("#3a4a66", lambda: (uv_quad(0.1, 0.1, cells_mat(3, 3), M((0.01, 0.03, 0.046))),
                              box((0.03, 0.06, 0.002), (0.01, -0.08, 0.046), mat("#f2b63c", 0.6)),
                              box((0.14, 0.015, 0.002), (0.01, 0.105, 0.046), mat("#f2b63c", 0.6))))


def almanac_book():
    book("#7a4e2e", lambda: (cyl(0.035, 0.002, (0.01, 0.03, 0.046), mat("#f2c44c", 0.6), segs=20),
                              [box((0.006, 0.03, 0.002), (0.01 + math.cos(a) * 0.055, 0.03 + math.sin(a) * 0.055, 0.046),
                                   mat("#f2c44c", 0.6), rot=(0, 0, math.degrees(a) - 90)) for a in [k * math.pi / 4 for k in range(8)]],
                              box((0.14, 0.012, 0.002), (0.01, -0.09, 0.046), mat("#e8e2cf", 0.6))))


def filter_cartridge():
    cyl(0.06, 0.26, (0, 0, 0.13), mat("#efe8d8", 0.85, var=0.1, dirt=0.15), segs=24)
    for z in (0.005, 0.255): cyl(0.065, 0.012, (0, 0, z), mat("#2f5f9e", 0.45), segs=24)
    for k in range(10): box((0.004, 0.124, 0.22), (0, 0, 0.13), mat("#ddd5c2", 0.85), rot=(0, 0, k * 18))


def pipe_section():
    pipe, fit = pipe_mats()
    tube((-0.3, 0, 0.05), (0.3, 0, 0.05), PIPE_R, mat("#9aa0a6", 0.4, 0.6, dirt=0.15), 20)
    for x in (-0.3, 0.3): cyl(PIPE_R * 1.3, 0.06, (x, 0, 0.05), mat("#7f868d", 0.4, 0.6), axis="X")


def valve_icon():
    valve_cell(True, False, False)


DP_ITEMS = {("array", "ground"): "DazedArray%s", ("array", "tracker"): "DazedTracker%s", ("array", "xl"): "DazedArrayXL%s",
            ("bank", "ground"): "DazedBank%s", ("bank", "wall"): "DazedWallBank%s", ("controller", "ground"): "DazedController%s",
            ("transformer", "ground"): "DazedTransformer", ("lamp", "garden"): "DazedGardenLamp%s", ("lamp", "street"): "DazedStreetLamp%s",
            ("pedal", "ground"): "DazedPedal%s", ("windmill", "ground"): "DazedWind%s", ("steam", "ground"): "DazedSteam%s",
            ("windsock", "ground"): "DazedWindsock", ("vane", "ground"): "DazedWeatherVane", ("propane", "ground"): "DazedPropane%s",
            ("petrol", "ground"): "DazedPetrol%s", ("gauge", "wall"): "DazedPowerGauge", ("rod", "ground"): "DazedGroundingRod",
            ("bench", "ground"): "DazedChargerBench", ("hydro", "ground"): "DazedWaterWheel",
            ("fence", "ground"): "DazedElectricFence", ("cooler", "wall"): "DazedRoomCooler", ("heater", "ground"): "DazedSpaceHeater",
            ("woodgas", "ground"): "DazedWoodGas%s", ("treadwheel", "ground"): "DazedTreadwheel"}
ICON_STATE = {"array": "clear", "bank": None, "controller": "on", "transformer": "on", "lamp": "off", "pedal": "off", "windmill": "still",
              "steam": "cold", "windsock": "full", "vane": "set", "propane": "off", "petrol": "off", "gauge": "full", "rod": "set",
              "bench": "off", "hydro": "still", "fence": "on", "cooler": "off", "heater": "on", "woodgas": "off",
              "treadwheel": "empty"}
# Parts whose world model makes a poor 32 px icon (too thin, or a long conduit) get a model of their own.
ICON_MODEL = {"DazedGroundingRod": rod_icon, "DazedPowerGauge": gauge_icon_model}
# Items with an icon but no sheet row of their own (the treadmill places vanilla's tile).
EXTRA_ICONS = {"DazedTreadmill": treadmill_icon}


def icon_shot(name, fn, folder, wall=False):
    clear(); start = len(BUILT); fn(); root, fixed = make_root(start)
    bpy.context.view_layer.update()
    icon_camera([o for o in BUILT[start:] if o.type == "MESH"], 256)
    os.makedirs(folder, exist_ok=True); render(os.path.join(folder, name + ".png"))


def dp_icons(only=None):
    """Every Dazed Power icon, or only the item names in `only`."""
    folder = os.path.join(OUT, "dp", "icons")
    for (k, mo), pat in DP_ITEMS.items():
        for t in DP_TIERS[k]:
            name = pat % t.capitalize() if "%s" in pat else pat
            if only and name not in only: continue
            st = ICON_STATE[k] or "c%d" % BANK_CELLS[mo][t]
            fn = ICON_MODEL.get(name)
            if fn: WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
            icon_shot(name, fn or (lambda k=k, mo=mo, t=t, st=st: dp_build(k, mo, t, st)), folder, wall=(mo == "wall"))
    for name, fn in EXTRA_ICONS.items():
        if only and name not in only: continue
        WEAR.update(rust=0.0, dirt=0.0, scorch=0.0); icon_shot(name, fn, folder)
    if only: log("dp icons done", sorted(only)); return
    WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
    for name, fn in (("DazedPowerManual", manual_basic), ("DazedPowerManualAdv", manual_adv), ("DazedAlmanac", almanac_book),
                     ("DazedAmplifier", lambda: build_icon("OffGridAmplifier")), ("DazedGearKitLow", lambda: build_icon("OffGridGearKitLow")),
                     ("DazedGearKitStock", lambda: build_icon("OffGridGearKitStock")), ("DazedGearKitRacing", lambda: build_icon("OffGridGearKitRacing"))):
        icon_shot(name, fn, folder)
    log("dp icons done")


def pl_icons():
    folder = os.path.join(OUT, "pl", "icons"); WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
    for size, n in PL_SIZES:
        for typ in PL_TYPES:
            for tier in PL_TIERS:
                name = "DazedTank%s%s%s" % ({"small": "Small", "large": "Large", "xl": "XL"}[size], typ.capitalize(), tier.capitalize())
                icon_shot(name, lambda s=size, t=typ, r=tier: pl_tank(s, t, r), folder)
    for name, fn in (("DazedPumpHand", hand_pump), ("DazedPumpElectric", electric_pump), ("DazedPurifier", purifier),
                     ("DazedDownspout", downspout), ("DazedPurifierFilter", filter_cartridge), ("DazedPipeSection", pipe_section),
                     ("DazedValve", valve_icon), ("DazedSprinkler", lambda: sprinkler(False)), ("DazedWaterMain", water_main),
                     ("DazedFuelPumpHand", lambda: fuel_pump(False)), ("DazedFuelPumpElectric", lambda: fuel_pump(True)),
                     ("DazedDigester", digester)):
        icon_shot(name, fn, folder)
    log("pl icons done")


def ui_renders():
    """Whole-object renders the interface art is cut from: the almanac book, from the front three-quarter view."""
    folder = os.path.join(OUT, "ui"); WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
    icon_shot("almanac_book", almanac_book, folder)


def dp_test():
    rows = set()
    for want in [("array", "ground", "salvaged", "clear"), ("array", "tracker", "workshop", "snow"), ("array", "xl", "makeshift", "cracked"),
                 ("bank", "ground", "workshop", "c5"), ("bank", "wall", "salvaged", "c3"), ("controller", "ground", "workshop", "on"),
                 ("transformer", "ground", "standard", "on"), ("lamp", "street", "workshop", "on"), ("lamp", "garden", "makeshift", "on"),
                 ("gauge", "wall", "standard", "mid"), ("rod", "ground", "standard", "set"), ("bench", "ground", "standard", "on"),
                 ("hydro", "ground", "standard", "turning")]:
        for i, r in enumerate(DP_ROWS):
            if r[:4] == want and r[4] == 1: rows.add(i)
    dp_render(["all"], rows)


for job in JOBS:
    t0 = time.time()
    if job == "test":
        dp_test(); pl_render(["machines"])
    elif job.startswith("dp:"): dp_render(job[3:].split(","))
    elif job.startswith("pl:"): pl_render(job[3:].split(","))
    elif job == "icons:dp": dp_icons()
    elif job.startswith("icons:dp:"): dp_icons(set(job[9:].split(",")))
    elif job == "icons:pl": pl_icons()
    elif job == "ui": ui_renders()
    log("job", job, "took %.0fs" % (time.time() - t0))
log("finished")
