"""Dazed Plumbing -- render the world sprites and icons in Blender with the pz-sprite-forge rig.

Run inside Blender (4.2+) from the Python console:
    ART = r"C:\\Users\\<you>\\Zomboid\\dup_art"; FAMILIES = ["pumps"]; exec(open(ART + r"\\dup_render.py").read())
or headless:  blender -b -P dup_render.py -- <ART folder> [family ...]
Families: tanks, pipes, valves, pumps, purifier, downspout, sprinkler, wallpanel, icons (or a subset such as tanks:water
or icons:DazedWaterPanel).
Cells go to ART/out/<family>/<sprite index>.png (2x, 256x512). A tank piece also writes <index>_m.png,
the mask of what stands on its own square; tools/pack_art.py cuts the piece out with it.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Euler

if "ART" not in globals():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ART = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
    FAMILIES = argv[1:] or ["pumps"]
else:
    FAMILIES = globals().get("FAMILIES", ["pumps"])
sys.path.insert(0, ART)
import pz_sprite_forge as F  # noqa: E402

try:
    F.register()
except (ValueError, RuntimeError):
    pass                                                        # already registered this session


# ------------------------------------------------------------------ scene
scene = bpy.data.scenes.get("DUP_Render") or bpy.data.scenes.new("DUP_Render")
if bpy.context.window is not None:
    bpy.context.window.scene = scene
scene.render.engine = "CYCLES"
props = scene.pz_forge
props.scale_2x, props.show_guide, props.ground_occlusion = True, False, True
F.build_rig(bpy.context)
# Crisper than the rig's defaults: render at twice the cell size with no denoiser (it smears fine
# detail), and let tools/pack_art.py shrink and sharpen to 128x256.
scene.render.resolution_percentage = 200
scene.render.filter_size = 0.7
scene.cycles.samples = 256
scene.cycles.use_denoising = False
SUBJECT = bpy.data.objects[F.SUBJECT_NAME]
MODEL = bpy.data.collections.get("DUP_Model") or bpy.data.collections.new("DUP_Model")
if MODEL.name not in scene.collection.children:
    scene.collection.children.link(MODEL)


def clear_model():
    for o in list(MODEL.objects):
        bpy.data.objects.remove(o, do_unlink=True)


# ------------------------------------------------------------------ materials
def lin(hexcol):
    """An sRGB hex colour as linear RGB (what Base Color expects)."""
    h = hexcol.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


_mats = {}


def mat(hexcol, rough=0.6, wear=0.0, emit=0.0, alpha=1.0, rust=0.0):
    """Painted, essentially diffuse material (vanilla art is painted, not metallic), with optional wear and rust."""
    key = (hexcol, rough, wear, emit, alpha, rust)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("dup_%s_%d" % (hexcol.strip("#"), len(_mats)))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    base = lin(hexcol)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.12
    b.inputs["Alpha"].default_value = alpha
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*base, 1)
        b.inputs["Emission Strength"].default_value = emit
    colour = None
    if wear > 0:                                                    # soft, broad paint wear
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 6.0
        noise.inputs["Detail"].default_value = 3.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.30
        ramp.color_ramp.elements[1].position = 0.75
        ramp.color_ramp.elements[0].color = (*(c * (1 - wear) for c in base), 1)
        ramp.color_ramp.elements[1].color = (*(min(1.0, c * (1 + wear * 0.3)) for c in base), 1)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        colour = ramp.outputs["Color"]
    if rust > 0:                                                    # rust in patches, not speckle
        mask = nt.nodes.new("ShaderNodeTexNoise")
        mask.inputs["Scale"].default_value = 3.0
        mask.inputs["Detail"].default_value = 6.0
        mramp = nt.nodes.new("ShaderNodeValToRGB")
        mramp.color_ramp.elements[0].position = 0.50
        mramp.color_ramp.elements[1].position = 0.62
        mramp.color_ramp.elements[1].color = (rust, rust, rust, 1)
        nt.links.new(mask.outputs["Fac"], mramp.inputs["Fac"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        fac = [i for i in mix.inputs if i.name == "Factor" and i.type == "VALUE"][0]
        a = [i for i in mix.inputs if i.name == "A" and i.type == "RGBA"][0]
        bb = [i for i in mix.inputs if i.name == "B" and i.type == "RGBA"][0]
        out = [o for o in mix.outputs if o.type == "RGBA"][0]
        nt.links.new(mramp.outputs["Color"], fac)
        if colour is not None:
            nt.links.new(colour, a)
        else:
            a.default_value = (*base, 1)
        bb.default_value = (*lin("#6e3a22"), 1)
        colour = out
    if colour is not None:
        nt.links.new(colour, b.inputs["Base Color"])
    else:
        b.inputs["Base Color"].default_value = (*base, 1)
    _mats[key] = m
    return m


# ------------------------------------------------------------------ geometry helpers
def _obj(name, bm, material, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    MODEL.objects.link(o)
    o.location, o.rotation_euler = loc, Euler(rot, "XYZ")
    me.materials.append(material)
    o.parent = current_parent()
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width, mod.segments, mod.limit_method = bevel, 2, "ANGLE"
    return o


_PARENTS = []


def current_parent():
    """What new parts hang from: the innermost `group`, else the turning subject (None when fixed)."""
    return _PARENTS[-1][0] if _PARENTS else SUBJECT


class group:
    """Build parts in a local frame at `loc` with rotation `rot`; fixed=True keeps them still while facings turn."""
    def __init__(self, loc=(0, 0, 0), rot=(0, 0, 0), fixed=False):
        e = bpy.data.objects.new("pivot", None)
        MODEL.objects.link(e)
        e.parent = None if fixed else current_parent()
        e.location, e.rotation_euler = loc, Euler(rot, "XYZ")
        self.empty = e

    def __enter__(self):
        _PARENTS.append((self.empty,))
        return self.empty

    def __exit__(self, *a):
        _PARENTS.pop()


def box(size, center, material, rot=(0, 0, 0), bevel=0.012):
    """A box `size` (x, y, z) centred at `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    return _obj("box", bm, material, center, rot, bevel)


def cyl(radius, depth, center, material, axis="Z", radius2=None, segs=28, rot=None):
    """A cylinder (or cone with radius2) along an axis, centred at `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    for f in bm.faces:
        f.smooth = abs(f.normal.z) < 0.7
    r = rot or {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    return _obj("cyl", bm, material, center, r)


def ball(radius, center, material, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    for f in bm.faces:
        f.smooth = True
    return _obj("ball", bm, material, center)


def tube(a, b, radius, material, segs=12):
    """A round bar from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    q = d.normalized().to_track_quat("Z", "Y")
    o = cyl(radius, d.length, (a + b) / 2, material, segs=segs)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = q
    return o


# ------------------------------------------------------------------ shared parts
def torus(R, r, center, material, axis="Z", segs=32, rsegs=8):
    """A ring of major radius R and tube radius r around an axis through `center`."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ring = []
        for j in range(rsegs):
            b = 2 * math.pi * j / rsegs
            ring.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
        rings.append(ring)
    for i in range(segs):
        for j in range(rsegs):
            f = bm.faces.new((rings[i][j], rings[(i + 1) % segs][j], rings[(i + 1) % segs][(j + 1) % rsegs], rings[i][(j + 1) % rsegs]))
            f.smooth = True
    rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    return _obj("torus", bm, material, center, rot)


def obround(L, W, H, center, material, segs=12, bevel=0.03):
    """A basement-oil-tank body along X: flat sides, round top and bottom (W wide, H tall, L long)."""
    r = W / 2
    prof = []
    for i in range(segs + 1):                                   # top half-round, then bottom
        a = math.pi * i / segs
        prof.append((r * math.cos(a), H / 2 - r + r * math.sin(a)))
    for i in range(segs + 1):
        a = math.pi + math.pi * i / segs
        prof.append((r * math.cos(a), -H / 2 + r + r * math.sin(a)))
    bm = bmesh.new()
    ends = []
    for x in (-L / 2, L / 2):
        ends.append([bm.verts.new((x, y, z)) for (y, z) in prof])
    n = len(prof)
    for i in range(n):
        f = bm.faces.new((ends[0][i], ends[0][(i + 1) % n], ends[1][(i + 1) % n], ends[1][i]))
        f.smooth = True
    bm.faces.new(list(reversed(ends[0])))
    bm.faces.new(ends[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _obj("obround", bm, material, center, bevel=bevel)


# ------------------------------------------------------------------ the sheet's layout (DUP_Parts, DUP_Pipes, DUP_Pumps ...)
FACINGS = {"E": (0, 90), "S": (1, 0), "W": (2, 270), "N": (3, 180)}   # column, degrees about Z
SIZES = [("small", 1), ("large", 2), ("xl", 3)]
TYPES = ["propane", "gas", "water"]
TANK_TIERS = ["salvaged", "crafted"]
BLOCK = {"small": 0, "large": 24, "xl": 72}
PIPE_BASE, PUMP_BASE, PURIFIER_BASE, SPOUT_BASE = 144, 176, 184, 192

COLOURS = {"propane": "#e6e4dc", "gas": "#ad2a22", "water": "#2f63ae"}
FADED = {"propane": "#d6d0c2", "gas": "#94392c", "water": "#4a74a8"}
STEEL, DARK, BRASS, BLACK = "#7d8288", "#2f3236", "#b8913e", "#1d1e21"
CONCRETE = "#9c9990"


def paint(typ, tier):
    """The tank's body paint: clean when crafted, faded, worn and stained when salvaged."""
    if tier == "crafted":
        return mat(COLOURS[typ], 0.5, wear=0.04)
    return mat(FADED[typ], 0.6, wear=0.16, rust=0.45 if typ != "water" else 0.3)


# ------------------------------------------------------------------ small tanks (one square, standing)
def small_propane(tier):
    """A 100 lb propane cylinder: foot ring, tall body, domed top, guard collar and valve."""
    body = paint("propane", tier)
    steel = mat(STEEL, 0.45, wear=0.1, rust=0.4 if tier == "salvaged" else 0)
    cyl(0.17, 0.07, (0, 0, 0.035), steel)
    cyl(0.19, 0.70, (0, 0, 0.42), body)
    ball(0.19, (0, 0, 0.77), body, scale=(1, 1, 0.42))
    cyl(0.11, 0.15, (0, 0, 0.90), body, radius2=0.12)                     # guard collar
    cyl(0.085, 0.14, (0, 0, 0.91), mat(DARK, 0.6))                        # inside the collar
    cyl(0.025, 0.09, (0, 0, 0.92), mat(BRASS, 0.35))                      # valve
    torus(0.04, 0.008, (0, 0, 0.97), mat(BLACK, 0.5))                     # handwheel
    box((0.05, 0.05, 0.05), (0, -0.12, 0.92), mat("#8d8f92", 0.4), bevel=0.01)   # regulator, out the front
    box((0.12, 0.004, 0.08), (0, -0.191, 0.55), mat("#3a6d3f" if tier == "crafted" else "#5b6b55", 0.5))  # label


def drum(r, h, body, rings=(0.33, 0.66)):
    cyl(r, h, (0, 0, h / 2 + 0.01), body)
    for k in rings:
        torus(r, 0.012, (0, 0, 0.01 + h * k), body)                        # rolling hoops
    for z in (0.012, h + 0.008):
        torus(r - 0.006, 0.011, (0, 0, z), body)                           # chimes


def small_gas(tier):
    """A red 55-gallon steel drum; the crafted one carries a rotary drum pump."""
    body = paint("gas", tier)
    drum(0.26, 0.82, body)
    cyl(0.03, 0.02, (-0.13, 0.06, 0.84), mat(DARK, 0.5))                  # vent bung
    if tier == "crafted":
        cyl(0.02, 0.30, (0.10, 0.0, 0.98), mat(STEEL, 0.4))
        cyl(0.06, 0.08, (0.10, 0.0, 1.08), mat("#6b7076", 0.4), axis="Y")
        tube((0.10, 0.0, 1.08), (0.10, -0.16, 1.02), 0.012, mat(STEEL, 0.4))
        tube((0.10, 0.05, 1.08), (0.10, 0.05, 1.20), 0.008, mat(BLACK, 0.5))  # crank
    else:
        cyl(0.04, 0.02, (0.11, -0.04, 0.84), mat(DARK, 0.5))


def small_water(tier):
    """A blue plastic drum with rounded shoulders, two bungs and a brass spigot at the front."""
    body = paint("water", tier)
    cyl(0.26, 0.74, (0, 0, 0.38), body)
    torus(0.205, 0.055, (0, 0, 0.75), body)                                # rounded top edge
    cyl(0.21, 0.06, (0, 0, 0.77), body)
    torus(0.205, 0.055, (0, 0, 0.065), body)
    for z in (0.30, 0.52):
        torus(0.262, 0.016, (0, 0, z), body)                               # moulded ribs
    for x in (-0.12, 0.12):
        cyl(0.035, 0.03, (x, 0.05, 0.81), mat("#e8e8e4", 0.5))           # bung caps
    tube((0, -0.25, 0.14), (0, -0.32, 0.14), 0.016, mat(BRASS, 0.35))
    tube((0, -0.32, 0.14), (0, -0.32, 0.09), 0.013, mat(BRASS, 0.35))
    box((0.012, 0.05, 0.012), (0, -0.30, 0.17), mat("#b3251f", 0.5), bevel=0.003)


# ------------------------------------------------------------------ large and XL tanks (2 or 3 squares)
def oil_tank(n, typ, tier):
    """A basement oil tank: a tall flat-sided body on four steel legs, along the model's X, centred."""
    L, W, H, legs = (1.70, 0.60, 1.05, 0.30) if n == 2 else (2.66, 0.70, 1.22, 0.30)
    body = paint(typ, tier)
    rusty = tier == "salvaged"
    leg = mat("#3b3e42", 0.55, wear=0.15, rust=0.6 if rusty else 0)
    zc = legs + H / 2
    obround(L, W, H, (0, 0, zc), body)
    foot = 0.07 if rusty else 0.0                                          # salvaged ones stand on bricks
    for sx in (-1, 1):
        x = sx * (L / 2 - 0.16)
        for sy in (-1, 1):
            y = sy * (W / 2 - 0.08)
            tube((x, y, foot), (x, y, legs + 0.12), 0.026, leg)           # threaded pipe legs
            cyl(0.045, 0.02, (x, y, foot + 0.01), leg)                     # flanges
            if rusty:
                box((0.18, 0.11, 0.07), (x, y, 0.035), mat("#8f5a44", 0.9, wear=0.2), bevel=0.008)
        tube((x, -W / 2 + 0.08, foot + 0.12), (x, W / 2 - 0.08, foot + 0.12), 0.012, leg)
    top = legs + H
    seam = mat(DARK, 0.6)
    if not rusty:
        for x in (-L / 2 + 0.05, L / 2 - 0.05):
            obround(0.02, W + 0.012, H + 0.012, (x, 0, zc), body, bevel=0.004)  # welded end seams
    if typ == "propane":
        cyl(0.12, 0.10, (0, 0, top + 0.04), body)                          # valve dome
        ball(0.12, (0, 0, top + 0.09), body, scale=(1, 1, 0.5))
        cyl(0.03, 0.06, (-0.3, 0, top + 0.02), mat(BRASS, 0.35))           # relief valve
        cyl(0.045, 0.02, (0.3, -0.05, top + 0.01), mat("#e8e8e2", 0.3))    # float gauge
        box((0.18, 0.004, 0.10), (-0.25, -W / 2 - 0.002, zc + 0.15), mat("#3d6a8f", 0.5))  # data plate
    elif typ == "gas":
        cyl(0.045, 0.06, (L / 2 - 0.35, 0, top + 0.03), mat(BLACK, 0.5))   # fill cap
        tube((-L / 2 + 0.3, 0, top), (-L / 2 + 0.3, 0, top + 0.28), 0.018, mat(STEEL, 0.45))  # vent
        cyl(0.04, 0.04, (-L / 2 + 0.3, 0, top + 0.30), mat(STEEL, 0.45), radius2=0.02)
        cyl(0.05, 0.03, (0.0, -0.06, top + 0.01), mat("#e8e8e2", 0.3))     # gauge
        torus(0.13, 0.02, (L / 2 - 0.18, -W / 2 - 0.03, zc), mat(BLACK, 0.6), axis="Y")  # hose on the end
        box((0.16, 0.004, 0.1), (0.0, -W / 2 - 0.002, zc + 0.2), mat("#e9d36a", 0.5))   # warning plate
    else:
        cyl(0.17, 0.05, (0, 0, top + 0.02), mat("#e2e2de", 0.5))           # screw lid
        for k in range(8):
            a = math.pi * k / 4
            box((0.03, 0.012, 0.03), (0.17 * math.cos(a), 0.17 * math.sin(a), top + 0.03),
                mat("#e2e2de", 0.5), bevel=0.003)
        tube((-L / 2 + 0.3, 0, top), (-L / 2 + 0.3, 0, top + 0.12), 0.02, mat("#e2e2de", 0.5))
    # the outlet: a ball valve low on the front, at one end
    x = -L / 2 + 0.22
    tube((x, -W / 2 + 0.06, legs + 0.12), (x, -W / 2 - 0.10, legs + 0.12), 0.02, mat(BRASS, 0.35))
    box((0.012, 0.09, 0.012), (x, -W / 2 - 0.08, legs + 0.16), mat("#c22b22" if typ != "gas" else "#d4b11e", 0.5), bevel=0.003)
    tube((x, -W / 2 - 0.10, legs + 0.12), (x, -W / 2 - 0.10, 0.04), 0.018, mat(STEEL, 0.45))
    if rusty:
        box((0.22, 0.004, 0.06), (L / 4, -W / 2 - 0.002, zc - 0.25), seam)   # a patched seam


def build_tank(size, typ, tier):
    if size == "small":
        {"propane": small_propane, "gas": small_gas, "water": small_water}[typ](tier)
    else:
        oil_tank(2 if size == "large" else 3, typ, tier)


# ------------------------------------------------------------------ pipes (tinted per fluid in game, so light grey)
PIPE_R, GROUND_Z, OVERHEAD_Z, CEILING_Z = 0.055, 0.075, 1.76, 2.62
ARMS = {1: (0, 1), 2: (1, 0), 4: (0, -1), 8: (-1, 0)}      # PZ N, E, S, W -> Blender (x, y); Blender +y is north


def pipe_cell(mask, outdoor):
    pipe = mat("#e6e8ec", 0.42, wear=0.05)
    fit = mat("#d2d5da", 0.38)
    z = GROUND_Z if outdoor else OVERHEAD_Z
    bits = [b for b in (1, 2, 4, 8) if mask & b]
    reach = 0.56                                            # just past the edge so neighbours overlap
    if not bits:                                            # a lone stub, capped both ends
        tube((-0.22, 0, z), (0.22, 0, z), PIPE_R, pipe, segs=20)
        for x in (-0.22, 0.22):
            cyl(PIPE_R * 1.3, 0.05, (x, 0, z), fit, axis="X")
    for b in bits:
        dx, dy = ARMS[b]
        tube((0, 0, z), (dx * reach, dy * reach, z), PIPE_R, pipe, segs=20)
    straight = mask in (5, 10)
    if straight:                                            # a coupling where two sections meet
        axis = "Y" if mask == 5 else "X"
        cyl(PIPE_R * 1.28, 0.10, (0, 0, z), fit, axis=axis)
        for s in (-1, 1):
            cyl(PIPE_R * 1.12, 0.02, ((0.06 * s) if axis == "X" else 0, (0.06 * s) if axis == "Y" else 0, z), fit, axis=axis)
    elif bits:                                              # an elbow, tee or cross fitting, or an end cap
        ball(PIPE_R * 1.38, (0, 0, z), fit)
        for b in bits:
            dx, dy = ARMS[b]
            cyl(PIPE_R * 1.25, 0.07, (dx * 0.07, dy * 0.07, z), fit, axis="X" if dx else "Y")
        if len(bits) == 1:
            dx, dy = ARMS[bits[0]]
            cyl(PIPE_R * 1.3, 0.05, (-dx * 0.04, -dy * 0.04, z), fit, axis="X" if dx else "Y")
    if outdoor:
        for b in bits or [2]:                               # small blocks keep it off the dirt
            dx, dy = ARMS[b]
            box((0.09, 0.09, 0.03), (dx * 0.32, dy * 0.32, 0.015), fit, bevel=0.006)
    else:                                                   # a clevis hanger on a threaded rod
        torus(PIPE_R + 0.012, 0.008, (0, 0, z), fit, axis="Y" if (mask & 5) and not (mask & 10) else "X")
        tube((0, 0, z + PIPE_R), (0, 0, CEILING_Z), 0.008, fit, segs=8)
        cyl(0.035, 0.012, (0, 0, CEILING_Z), fit)


VALVE_BASE = 196                                         # +4 overhead, +2 north-south, +1 closed


def holdout_mat():
    """A material that cuts the sprite away where it is in front: the pipe sprite underneath then shows through."""
    m = bpy.data.materials.get("DUP_Holdout") or bpy.data.materials.new("DUP_Holdout")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    hold = nt.nodes.new("ShaderNodeHoldout")
    nt.links.new(hold.outputs[0], out.inputs[0])
    return m


def valve_cell(outdoor, ns, closed):
    """A brass ball valve threaded onto the pipe: a slim body with hex ends, the pipe running through it.
    The pipe itself is drawn as a holdout, so the tinted pipe sprite shows wherever it passes in front of the valve."""
    brass = mat("#d0a548", 0.32, wear=0.05)
    nut = mat("#a8853a", 0.4)
    lever = mat("#c0271f", 0.5)
    z = GROUND_Z if outdoor else OVERHEAD_Z
    axis = "Y" if ns else "X"
    d = (0, 1) if ns else (1, 0)
    tube((-d[0] * 0.6, -d[1] * 0.6, z), (d[0] * 0.6, d[1] * 0.6, z), PIPE_R * 1.01, holdout_mat(), segs=20)
    cyl(PIPE_R * 1.45, 0.11, (0, 0, z), brass, axis=axis, segs=24)          # the body
    for sgn in (-1, 1):                                                      # hex ends where the pipe threads in
        cyl(PIPE_R * 1.3, 0.05, (d[0] * 0.075 * sgn, d[1] * 0.075 * sgn, z), nut, axis=axis, segs=6)
    top = z + PIPE_R * 1.45
    cyl(0.014, 0.05, (0, 0, top + 0.02), brass, segs=12)                     # stem
    cyl(0.022, 0.012, (0, 0, top + 0.045), nut, segs=6)                     # stem nut
    run = d if not closed else (-d[1], d[0])                                # along the pipe open, across it shut
    L = 0.20
    box((L if run[0] else 0.032, L if run[1] else 0.032, 0.012),
        (run[0] * L / 2, run[1] * L / 2, top + 0.05), lever, bevel=0.004)
    box((0.045, 0.045, 0.022), (run[0] * L, run[1] * L, top + 0.05), lever, bevel=0.008)   # grip end


PORT_BASE = 216                                          # + belly*8 + overhead*4 + side (N, E, S, W)


def port_cell(bit, overhead, belly):
    """The pipe's last stretch on the device's own square, coming in from side `bit`: under a tank and up into its belly,
    or up to a machine's foot; an overhead pipe drops to the ground first. Light grey, tinted per fluid in game."""
    pipe = mat("#e6e8ec", 0.42, wear=0.05)
    fit = mat("#d2d5da", 0.38)
    dx, dy = ARMS[bit]
    axis = "X" if dx else "Y"

    def at(r, z):
        return (dx * r, dy * r, z)
    start = 0.56                                          # just past the edge, over the pipe square's own arm
    if overhead:
        tube(at(0.56, OVERHEAD_Z), at(0.42, OVERHEAD_Z), PIPE_R, pipe, segs=20)
        ball(PIPE_R * 1.38, at(0.42, OVERHEAD_Z), fit)
        tube(at(0.42, OVERHEAD_Z), at(0.42, GROUND_Z), PIPE_R, pipe, segs=20)    # the drop
        ball(PIPE_R * 1.38, at(0.42, GROUND_Z), fit)
        start = 0.42
    stop = 0.14 if belly else 0.08                        # the device is drawn over this square's port, so it may reach in
    tube(at(start, GROUND_Z), at(stop, GROUND_Z), PIPE_R, pipe, segs=20)
    box((0.09, 0.09, 0.03), at((start + stop) / 2, 0.015), fit, bevel=0.006)    # a block keeps it off the dirt
    if belly:
        ball(PIPE_R * 1.38, at(stop, GROUND_Z), fit)                              # elbow, then up into the tank
        tube(at(stop, GROUND_Z), at(stop, 0.31), PIPE_R, pipe, segs=20)
        cyl(PIPE_R * 1.75, 0.035, at(stop, 0.30), fit)                            # flange on the belly
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            cyl(0.010, 0.02, (dx * stop + 0.075 * math.cos(a), dy * stop + 0.075 * math.sin(a), 0.325), fit, segs=6)
    else:
        cyl(PIPE_R * 1.4, 0.07, at(0.30, GROUND_Z), fit, axis=axis, segs=6)       # union nut at the machine's edge
        ball(PIPE_R * 1.2, at(stop, GROUND_Z), fit)                                # capped end under its foot


# ------------------------------------------------------------------ pumps, purifier, downspout (one square, front -Y)
HANDLE_DOWN_BASE = 212                                   # the hand pump mid-stroke, handle pressed down


def hand_pump(stroke=False):
    """A cast-iron pitcher pump on a well pipe, standing on a round concrete well cap; `stroke` presses the handle down."""
    iron = mat("#3a5243", 0.55, wear=0.14, rust=0.35)
    conc = mat(CONCRETE, 0.95, wear=0.25)
    cyl(0.38, 0.12, (0, 0.04, 0.06), conc, segs=36)
    cyl(0.06, 0.40, (0, 0.04, 0.32), mat(STEEL, 0.45, rust=0.4))           # well pipe
    cyl(0.10, 0.04, (0, 0.04, 0.52), iron)                                  # base flange
    cyl(0.115, 0.40, (0, 0.04, 0.74), iron)                                 # barrel
    cyl(0.13, 0.045, (0, 0.04, 0.95), iron)                                 # top rim
    cyl(0.09, 0.04, (0, 0.04, 0.99), iron)                                  # cap
    tube((0, -0.05, 0.78), (0, -0.27, 0.72), 0.04, iron)                    # spout
    cyl(0.045, 0.05, (0, -0.28, 0.69), iron)
    box((0.05, 0.06, 0.14), (0, 0.15, 1.02), iron, bevel=0.008)             # pivot bracket at the back
    with group(loc=(0, 0.15, 1.08), rot=(-0.35 if stroke else 0.55, 0, 0)):
        tube((0, 0, 0), (0, 0.42, 0), 0.022, iron)                          # handle, up and back
        tube((0, 0.42, 0), (0, 0.56, 0), 0.03, mat("#7a5634", 0.7))         # worn wooden grip
        tube((0, 0, 0), (0, -0.12, 0), 0.02, iron)                          # short arm to the pump rod
    tube((0, -0.05, 1.0), (0, -0.07, 1.16 if stroke else 1.08), 0.016, iron)  # pump rod, lifted by a pressed handle
    if stroke:
        tube((0, -0.28, 0.67), (0, -0.30, 0.14), 0.022, mat("#7fb2d9", 0.1, alpha=0.65))  # water running from the spout
    tube((0.08, 0.04, 0.56), (0.28, 0.04, 0.56), 0.026, mat(STEEL, 0.45))   # line out to the tank
    tube((0.28, 0.04, 0.56), (0.28, 0.04, 0.12), 0.026, mat(STEEL, 0.45))


def electric_pump():
    """A shallow-well jet pump with its pressure tank, on a concrete pad beside the well head."""
    pad = mat(CONCRETE, 0.95, wear=0.2)
    blue = mat("#2c5c9c", 0.45, wear=0.06)
    iron = mat("#5f6569", 0.5, wear=0.1)
    galv = mat("#a3a8ad", 0.4, wear=0.1)
    box((0.80, 0.62, 0.08), (0, 0.02, 0.04), pad, bevel=0.01)
    cyl(0.07, 0.28, (-0.27, 0.15, 0.22), mat("#ecebe6", 0.5))              # well casing cap
    cyl(0.08, 0.04, (-0.27, 0.15, 0.37), mat("#ecebe6", 0.5))
    box((0.30, 0.16, 0.04), (0.05, -0.08, 0.10), iron, bevel=0.006)         # pump foot
    cyl(0.12, 0.26, (0.08, -0.08, 0.25), blue, axis="X")                    # motor
    for i in range(6):
        cyl(0.124, 0.01, (0.0 + i * 0.035, -0.08, 0.25), blue, axis="X")     # cooling ribs
    ball(0.12, (0.21, -0.08, 0.25), blue, scale=(0.4, 1, 1))                # end bell
    cyl(0.13, 0.11, (-0.10, -0.08, 0.25), iron, axis="X")                   # pump volute
    cyl(0.04, 0.08, (-0.10, -0.08, 0.40), iron)                              # discharge
    box((0.08, 0.06, 0.07), (0.05, -0.08, 0.40), mat("#8a8f94", 0.45), bevel=0.008)  # pressure switch
    tube((0.05, -0.08, 0.44), (0.05, -0.08, 0.60), 0.012, mat("#555a5f", 0.5))        # conduit
    tube((-0.10, -0.08, 0.25), (-0.27, 0.15, 0.25), 0.022, galv)             # suction from the well
    cyl(0.16, 0.42, (0.22, 0.17, 0.32), mat("#3d6fa6", 0.4, wear=0.05))     # pressure tank
    ball(0.16, (0.22, 0.17, 0.53), mat("#3d6fa6", 0.4, wear=0.05), scale=(1, 1, 0.45))
    tube((-0.10, -0.08, 0.44), (0.22, 0.17, 0.44), 0.018, galv)             # tee across to the tank
    cyl(0.03, 0.02, (0.0, 0.05, 0.47), mat("#e8e8e2", 0.3), axis="Y")      # pressure gauge


def purifier():
    """Filter housings and a UV lamp on a plywood backboard between two posts, a manifold across the top."""
    post = mat("#6a5a44", 0.75, wear=0.2)
    board = mat("#b79a6c", 0.7, wear=0.15)
    galv = mat("#a3a8ad", 0.4, wear=0.1)
    box((0.80, 0.50, 0.05), (0, 0.05, 0.025), mat(CONCRETE, 0.95, wear=0.2), bevel=0.008)
    for x in (-0.34, 0.34):
        box((0.07, 0.07, 1.05), (x, 0.20, 0.55), post, bevel=0.008)
    box((0.76, 0.03, 0.80), (0, 0.18, 0.62), board, bevel=0.006)
    for i, (x, colour) in enumerate(((-0.22, "#e9ecef"), (0.0, "#2f6fb5"))):
        cyl(0.075, 0.36, (x, 0.07, 0.48), mat(colour, 0.35))                 # housing bowl
        cyl(0.09, 0.07, (x, 0.07, 0.70), mat("#e3e5e8", 0.4))                # head
        torus(0.077, 0.008, (x, 0.07, 0.40), mat("#d9dcdf", 0.4))
    cyl(0.05, 0.42, (0.22, 0.09, 0.56), mat("#cdd2d6", 0.25))               # UV chamber
    box((0.12, 0.05, 0.16), (0.22, 0.13, 0.86), mat("#2b2e33", 0.5), bevel=0.01)  # ballast box
    box((0.02, 0.01, 0.02), (0.22, 0.104, 0.90), mat("#3ee06a", 0.3, emit=5.0), bevel=0.003)
    tube((-0.36, 0.07, 0.78), (0.30, 0.07, 0.78), 0.018, galv)              # manifold
    for x in (-0.22, 0.0, 0.22):
        tube((x, 0.07, 0.72), (x, 0.07, 0.78), 0.016, galv)
    tube((-0.36, 0.07, 0.78), (-0.36, 0.07, 0.06), 0.018, galv)             # in, from the pump
    tube((0.30, 0.07, 0.78), (0.30, -0.10, 0.78), 0.018, galv)
    tube((0.30, -0.10, 0.78), (0.30, -0.10, 0.06), 0.018, galv)             # out, to the tank


def downspout():
    """A white aluminium downspout down the wall at the front edge, a gutter end above, kicking out at the foot."""
    alu = mat("#e8e5dc", 0.45, wear=0.08)
    y = -0.47
    box((0.30, 0.13, 0.10), (0, y + 0.04, 2.34), alu, bevel=0.01)          # gutter end, under the eave
    box((0.08, 0.06, 1.95), (0, y + 0.03, 1.27), alu, bevel=0.008)         # the downspout
    for z in (0.7, 1.5, 2.1):
        box((0.10, 0.075, 0.025), (0, y + 0.03, z), mat("#cfccc2", 0.45), bevel=0.004)  # straps
    with group(loc=(0, y + 0.03, 0.30), rot=(-0.75, 0, 0)):
        box((0.08, 0.06, 0.26), (0, 0, -0.12), alu, bevel=0.008)           # elbow
    box((0.08, 0.24, 0.06), (0, y + 0.28, 0.10), alu, bevel=0.008)         # kick-out
    box((0.20, 0.36, 0.04), (0, y + 0.30, 0.02), mat(CONCRETE, 0.95, wear=0.2), bevel=0.01)  # splash block
    cyl(0.04, 0.06, (0, y + 0.42, 0.10), mat(STEEL, 0.45), axis="Y")       # pipe connector at the end


WALLPANEL_BASE = 256                                     # DUP_WallPanels.BASE: 256-259 = facings E, S, W, N


def wallpanel(icon=False):
    """The wall water panel: a grey steel box (0.5 wide, 0.7 tall, 0.12 deep) on the front wall at head height, with a
    round gauge, two lamps and a red handwheel; like the downspout it hangs on the -Y wall and faces into the square.
    `icon` builds it centred on the ground with no conduit and turned so its face meets the camera, for the icon."""
    if icon:
        with group(rot=(0, 0, math.pi)):
            _wallpanel_parts(True)
    else:
        _wallpanel_parts(False)


def _wallpanel_parts(icon):
    """The panel's parts, built facing +Y (into the square)."""
    steel = mat("#8c949a", 0.5, wear=0.08)
    door = mat("#98a0a6", 0.45, wear=0.06)
    red = mat("#c0271f", 0.45)
    W, H, D = 0.50, 0.70, 0.12
    y0, z0 = (-D / 2, 0.02) if icon else (-0.47, 1.05)        # back face on the wall; the bottom edge
    yf = y0 + D                                               # the front face
    box((W, D, H), (0, y0 + D / 2, z0 + H / 2), steel, bevel=0.015)
    box((W - 0.06, 0.012, H - 0.06), (0, yf + 0.004, z0 + H / 2), door, bevel=0.006)   # the door, a little proud
    for x in (-0.19, 0.19):
        box((0.05, 0.03, 0.02), (x, yf + 0.012, z0 + H - 0.06), mat(STEEL, 0.4), bevel=0.004)  # hinges
    box((0.02, 0.025, 0.06), (0.21, yf + 0.016, z0 + 0.36), mat(DARK, 0.4), bevel=0.004)      # the latch
    zg = z0 + 0.50                                            # the gauge: a cream face in a dark bezel
    torus(0.09, 0.012, (0, yf + 0.018, zg), mat(BLACK, 0.4), axis="Y")
    cyl(0.088, 0.016, (0, yf + 0.014, zg), mat("#ede6d0", 0.6, emit=0.3), axis="Y")
    box((0.010, 0.004, 0.07), (0.018, yf + 0.024, zg + 0.024), red, rot=(0, math.radians(35), 0), bevel=0.0)
    cyl(0.012, 0.01, (0, yf + 0.026, zg), mat(BLACK, 0.4), axis="Y")
    for x, colour in ((-0.09, "#5cc854"), (0.09, "#f0aa32")):   # the lamps: supply green, paused amber
        torus(0.026, 0.006, (x, yf + 0.012, z0 + 0.32), mat("#c8c8c4", 0.3), axis="Y")
        ball(0.022, (x, yf + 0.012, z0 + 0.32), mat(colour, 0.25, emit=2.0), scale=(1, 0.6, 1))
    zw, yw = z0 + 0.16, yf + 0.06                             # the handwheel on its stem
    cyl(0.018, 0.06, (0, yf + 0.03, zw), mat(STEEL, 0.4), axis="Y")
    torus(0.075, 0.011, (0, yw, zw), red, axis="Y")
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        tube((0, yw, zw), (0.075 * math.cos(a), yw, zw + 0.075 * math.sin(a)), 0.007, red, segs=8)
    cyl(0.02, 0.02, (0, yw, zw), red, axis="Y")
    if not icon:
        tube((0.16, y0 + 0.02, z0 + H), (0.16, y0 + 0.02, CEILING_Z), 0.014, mat("#a3a8ad", 0.4))  # conduit up the wall
        for z in (z0 + H + 0.25, z0 + H + 0.6):
            box((0.04, 0.03, 0.015), (0.16, y0 + 0.02, z), mat(STEEL, 0.4), bevel=0.003)          # its straps


SPRINKLER_BASE = 204                                     # +4 spraying


def sprinkler(spraying):
    """A brass impact sprinkler on a tripod spike, the hose coming in at the foot; spraying adds the water jets."""
    steel = mat("#5d6368", 0.5, wear=0.12, rust=0.2)
    brass = mat("#d0a548", 0.32, wear=0.05)
    hose = mat("#2f6b34", 0.6)
    for k in range(3):                                                     # the tripod
        a = 2 * math.pi * k / 3 + 0.3
        tube((0, 0, 0.30), (0.22 * math.cos(a), 0.22 * math.sin(a), 0.0), 0.012, steel, segs=8)
    tube((0, 0, 0.02), (0, 0, 0.55), 0.018, steel, segs=12)               # the riser
    cyl(0.03, 0.05, (0, 0, 0.57), brass)                                    # bearing
    with group(loc=(0, 0, 0.62)):
        cyl(0.028, 0.06, (0, 0, 0), brass)                                  # body
        tube((0, 0, 0.0), (0, -0.16, 0.08), 0.014, brass, segs=10)          # nozzle, out the front
        tube((0, -0.02, 0.05), (0, -0.14, 0.10), 0.006, brass, segs=6)     # the impact arm
        box((0.02, 0.03, 0.02), (0, -0.15, 0.10), brass, bevel=0.004)       # its paddle
        tube((0, 0.0, 0.03), (0, 0.08, 0.06), 0.006, brass, segs=6)        # counterweight arm
    tube((0.0, 0.0, 0.05), (0.18, 0.12, 0.02), 0.022, hose, segs=10)        # hose connector and stub
    tube((0.18, 0.12, 0.02), (0.36, 0.36, 0.02), 0.022, hose, segs=10)
    if spraying:
        jet = mat("#d6ecff", 0.1, alpha=0.55, emit=0.4)
        mist = mat("#e8f4ff", 0.2, alpha=0.25)
        for j in range(14):                                                 # the main jet arcs out in front
            t = j / 13
            ball(0.018 + 0.012 * t, (0.04 * math.sin(t * 3), -0.18 - 0.62 * t, 0.70 + 0.30 * t - 0.62 * t * t), jet)
        for k in range(10):                                                 # a ring of falling drops
            a = 2 * math.pi * k / 10
            for j in range(3):
                r = 0.45 + 0.12 * j
                ball(0.015, (r * math.cos(a), r * math.sin(a), 0.25 - 0.08 * j), mist)


# ------------------------------------------------------------------ inventory-only items
def filter_cartridge():
    cyl(0.12, 0.42, (0, 0, 0.23), mat("#f1efe8", 0.8))
    for k in range(20):
        a = 2 * math.pi * k / 20
        box((0.012, 0.02, 0.40), (0.12 * math.cos(a), 0.12 * math.sin(a), 0.23), mat("#e4e1d8", 0.8), rot=(0, 0, a))
    for z in (0.02, 0.44):
        cyl(0.13, 0.03, (0, 0, z), mat("#2f6fb5", 0.4))


def pipe_section():
    galv = mat("#a3a8ad", 0.4, wear=0.1)
    tube((-0.6, 0, 0.07), (0.6, 0, 0.07), 0.06, galv, segs=20)
    for x in (-0.6, 0.6):
        cyl(0.077, 0.10, (x, 0, 0.07), mat("#b4b8bd", 0.38), axis="X")


def valve():
    brass = mat(BRASS, 0.35)
    tube((-0.30, 0, 0.12), (0.30, 0, 0.12), 0.05, mat("#a3a8ad", 0.4), segs=20)
    ball(0.11, (0, 0, 0.12), brass, scale=(1.1, 1, 1))
    cyl(0.04, 0.14, (0, 0, 0.26), brass)
    torus(0.10, 0.014, (0, 0, 0.34), mat("#c0271f", 0.5))
    for k in range(4):
        a = math.pi * k / 2
        tube((0, 0, 0.34), (0.10 * math.cos(a), 0.10 * math.sin(a), 0.34), 0.009, mat("#c0271f", 0.5))


# ------------------------------------------------------------------ rendering
_mask = None


def mask_material():
    """White where a surface stands over the square under the camera, black elsewhere (world position)."""
    global _mask
    if _mask:
        return _mask
    m = bpy.data.materials.new("dup_mask")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    tests = []
    for axis in ("X", "Y"):
        ab = nt.nodes.new("ShaderNodeMath"); ab.operation = "ABSOLUTE"
        nt.links.new(sep.outputs[axis], ab.inputs[0])
        lt = nt.nodes.new("ShaderNodeMath"); lt.operation = "LESS_THAN"; lt.inputs[1].default_value = 0.5
        nt.links.new(ab.outputs[0], lt.inputs[0])
        tests.append(lt)
    both = nt.nodes.new("ShaderNodeMath"); both.operation = "MULTIPLY"
    nt.links.new(tests[0].outputs[0], both.inputs[0]); nt.links.new(tests[1].outputs[0], both.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(both.outputs[0], em.inputs["Strength"])
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    _mask = m
    return m


def shoot(path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def shoot_mask(path):
    vl = bpy.context.view_layer
    keep = scene.cycles.samples
    vl.material_override = mask_material()
    scene.cycles.samples = 32
    try:
        shoot(path)
    finally:
        vl.material_override = None
        scene.cycles.samples = keep


def facings(fn, out, index_of):
    """Render a one-square model in all four facings; index_of(col) -> sprite index."""
    os.makedirs(out, exist_ok=True)
    for facing, (col, deg) in FACINGS.items():
        SUBJECT.location = (0, 0, 0)
        SUBJECT.rotation_euler = Euler((0, 0, math.radians(deg)), "XYZ")
        shoot(os.path.join(out, "%d.png" % index_of(col)))
    SUBJECT.rotation_euler = Euler((0, 0, 0), "XYZ")


def render_tanks(only=None):
    out = os.path.join(ART, "out", "tanks")
    os.makedirs(out, exist_ok=True)
    done = 0
    for size, n in SIZES:
        for ti, typ in enumerate(TYPES):
            if only and typ not in only and size not in only:
                continue
            for ri, tier in enumerate(TANK_TIERS):
                clear_model()
                build_tank(size, typ, tier)
                r = ti * 2 + ri
                for facing, (col, deg) in FACINGS.items():
                    SUBJECT.rotation_euler = Euler((0, 0, math.radians(deg)), "XYZ")
                    along_x = facing in ("S", "N")
                    centre = ((n - 1) / 2, 0) if along_x else (0, -(n - 1) / 2)
                    for p in range(n):
                        piece = (p, 0) if along_x else (0, -p)          # Blender -y is PZ +y (south)
                        SUBJECT.location = (centre[0] - piece[0], centre[1] - piece[1], 0)
                        idx = BLOCK[size] + (r * 4 + col) * n + p
                        shoot(os.path.join(out, "%d.png" % idx))
                        if n > 1:
                            shoot_mask(os.path.join(out, "%d_m.png" % idx))
                        done += 1
    SUBJECT.location = (0, 0, 0)
    SUBJECT.rotation_euler = Euler((0, 0, 0), "XYZ")
    return done


def render_pipes():
    out = os.path.join(ART, "out", "pipes")
    os.makedirs(out, exist_ok=True)
    SUBJECT.location, SUBJECT.rotation_euler = (0, 0, 0), Euler((0, 0, 0), "XYZ")
    for i in range(32):
        clear_model()
        pipe_cell(i % 16, i >= 16)
        shoot(os.path.join(out, "%d.png" % (PIPE_BASE + i)))
    return 32


def render_valves():
    out = os.path.join(ART, "out", "valves")
    os.makedirs(out, exist_ok=True)
    SUBJECT.location, SUBJECT.rotation_euler = (0, 0, 0), Euler((0, 0, 0), "XYZ")
    for i in range(8):
        clear_model()
        valve_cell(i < 4, (i % 4) >= 2, i % 2 == 1)
        shoot(os.path.join(out, "%d.png" % (VALVE_BASE + i)))
    return 8


def render_ports():
    out = os.path.join(ART, "out", "ports")
    os.makedirs(out, exist_ok=True)
    SUBJECT.location, SUBJECT.rotation_euler = (0, 0, 0), Euler((0, 0, 0), "XYZ")
    for i in range(16):
        clear_model()
        port_cell((1, 2, 4, 8)[i % 4], (i // 4) % 2 == 1, i >= 8)
        shoot(os.path.join(out, "%d.png" % (PORT_BASE + i)))
    return 16


def render_machines(fams):
    done = 0
    if "pumps" in fams:
        for k, fn in enumerate((hand_pump, electric_pump)):
            clear_model(); fn()
            facings(fn, os.path.join(ART, "out", "pumps"), lambda c, k=k: PUMP_BASE + k * 4 + c)
            done += 4
    if "pumpstroke" in fams:
        clear_model(); hand_pump(stroke=True)
        facings(None, os.path.join(ART, "out", "pumpstroke"), lambda c: HANDLE_DOWN_BASE + c)
        done += 4
    if "purifier" in fams:
        clear_model(); purifier()
        facings(purifier, os.path.join(ART, "out", "purifier"), lambda c: PURIFIER_BASE + c)
        done += 4
    if "sprinkler" in fams:
        for k, on in enumerate((False, True)):
            clear_model(); sprinkler(on)
            facings(None, os.path.join(ART, "out", "sprinkler"), lambda c, k=k: SPRINKLER_BASE + k * 4 + c)
            done += 4
    if "downspout" in fams:
        clear_model(); downspout()
        facings(downspout, os.path.join(ART, "out", "downspout"), lambda c: SPOUT_BASE + c)
        done += 4
    if "wallpanel" in fams:
        clear_model(); wallpanel()
        facings(wallpanel, os.path.join(ART, "out", "wallpanel"), lambda c: WALLPANEL_BASE + c)
        done += 4
    return done


def icon_list():
    out = []
    for size, n in SIZES:
        for typ in TYPES:
            for tier in TANK_TIERS:
                name = "DazedTank%s%s%s" % ({"small": "Small", "large": "Large", "xl": "XL"}[size], typ.capitalize(), tier.capitalize())
                out.append((name, (lambda s=size, t=typ, r=tier: build_tank(s, t, r)), {1: 1.4, 2: 0.75, 3: 0.5}[n]))
    out += [("DazedPumpHand", hand_pump, 1.4), ("DazedPumpElectric", electric_pump, 1.3), ("DazedPurifier", purifier, 1.1),
            ("DazedDownspout", downspout, 0.55), ("DazedPurifierFilter", filter_cartridge, 2.2),
            ("DazedPipeSection", pipe_section, 1.1), ("DazedValve", valve, 2.0),
            ("DazedSprinkler", lambda: sprinkler(False), 1.4), ("DazedWaterPanel", lambda: wallpanel(icon=True), 1.6)]
    return out


def render_icons(names=None):
    out = os.path.join(ART, "out", "icons")
    os.makedirs(out, exist_ok=True)
    n = 0
    for name, fn, scale in icon_list():
        if names and name not in names:
            continue
        clear_model(); fn()
        SUBJECT.location = (0, 0, 0)
        SUBJECT.rotation_euler = Euler((0, 0, math.radians(15)), "XYZ")
        SUBJECT.scale = (scale, scale, scale)
        shoot(os.path.join(out, name + ".png"))
        n += 1
    SUBJECT.scale = (1, 1, 1)
    SUBJECT.rotation_euler = Euler((0, 0, 0), "XYZ")
    return n


total = 0
for fam in FAMILIES:
    if fam == "tanks" or fam.startswith("tanks:"):
        total += render_tanks(fam.split(":", 1)[1].split(",") if ":" in fam else None)
    elif fam == "pipes":
        total += render_pipes()
    elif fam == "valves":
        total += render_valves()
    elif fam == "ports":
        total += render_ports()
    elif fam == "icons" or fam.startswith("icons:"):
        total += render_icons(fam.split(":", 1)[1].split(",") if ":" in fam else None)
total += render_machines(FAMILIES)
print("DUP render: %d images for %s -> %s" % (total, ", ".join(FAMILIES), os.path.join(ART, "out")))
