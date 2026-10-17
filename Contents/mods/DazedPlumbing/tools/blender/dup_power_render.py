"""Dazed Plumbing -- the tanks, pipes, fittings, pumps, purifier, downspout, sprinkler and wall panel in DazedPower's
base style (0.17.2). The machines at 232-255 stay with dup_machines_render.py.

It loads dz2.py (and through it dz_render.py) from its own folder as a library, so camera, lights, the painterly worn
material, bevels and the 2:1 ortho tile camera are exactly DazedPower's. Small tanks, pipes, valves, ports, both pumps,
the downspout and the sprinkler are dz2.py's own Plumbing models. The large and XL tanks (the oval basement tanks),
the purifier and the wall panel keep Plumbing's shapes: their builders are read from dup_render.py and run through
small adapters onto dz2.py's primitives and material. Sprite indices are dup_render.py's, so saves keep every object.

    python tools/blender/dup_power_render.py -- <out dir> [all | tanks pipes valves ports machines icons]   (pip install bpy)
    python3 tools/blender/dup_machines_post.py <out dir> <final dir>     (cuts tank pieces by mask, grades, shrinks)
    python3 tools/pack_art.py <final dir>/cells                          (then copy <final>/icons/*.png to textures/)
Icons rendered: the 12 large and XL tanks, the purifier and the wall panel (the others were already Power renders).
"""
import ast, math, os, sys

_ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
_OUT_DIR = os.path.abspath(_ARGS[0] if _ARGS else "dup_power_out")
_WANT = _ARGS[1:] or ["all"]
_HERE = os.path.dirname(os.path.abspath(__file__))
_MOD = os.path.join(_HERE, "dup_render.py")
sys.argv = [sys.argv[0], "--", _OUT_DIR, "_library"]
__file__ = os.path.join(_HERE, "dz2.py")
exec(compile(open(__file__).read(), __file__, "exec"))
__file__ = os.path.join(_HERE, "dup_power_render.py")
import bmesh  # noqa: E402

CELLS, ICONS = os.path.join(_OUT_DIR, "cells"), os.path.join(_OUT_DIR, "icons")
WALLPANEL_BASE = 256


# ------------------------------------------------------------------ dup_render.py's helpers onto dz2.py's
def _deg(r):
    return tuple(math.degrees(a) for a in r)


def a_mat(hexcol, rough=0.6, wear=0.0, emit=0.0, alpha=1.0, rust=0.0):
    return mat(hexcol, rough, 0.0, var=0.12 + wear * 0.5, rust=rust, dirt=0.3, alpha=alpha, emit=emit)


def a_box(size, center, material, rot=(0, 0, 0), bevel=0.012):
    return box(size, center, material, _deg(rot), bevel)


def a_cyl(radius, depth, center, material, axis="Z", radius2=None, segs=28, rot=None):
    return cyl(radius, depth, center, material, axis, segs, radius2, _deg(rot) if rot else None)


def a_ball(radius, center, material, scale=(1, 1, 1)):
    return ball(radius, center, material, scale, 20)


def a_tube(a, b, radius, material, segs=12):
    return tube(a, b, radius, material, segs)


def a_torus(R, r, center, material, axis="Z", segs=32, rsegs=8):
    return torus(R, r, center, material, axis, segs, rsegs)


def a_obround(L, W, H, center, material, segs=12, bevel=0.03):
    """dup_render.py's obround (flat sides, round top and bottom, along X) as a dz2.py object."""
    r = W / 2
    prof = [(r * math.cos(math.pi * i / segs), H / 2 - r + r * math.sin(math.pi * i / segs)) for i in range(segs + 1)]
    prof += [(r * math.cos(math.pi + math.pi * i / segs), -H / 2 + r + r * math.sin(math.pi + math.pi * i / segs)) for i in range(segs + 1)]
    bm = bmesh.new()
    ends = [[bm.verts.new((x, y, z)) for (y, z) in prof] for x in (-L / 2, L / 2)]
    n = len(prof)
    for i in range(n):
        bm.faces.new((ends[0][i], ends[0][(i + 1) % n], ends[1][(i + 1) % n], ends[1][i]))
    bm.faces.new(list(reversed(ends[0])))
    bm.faces.new(ends[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj(bm, material, M(center), smooth=True, bevel=bevel)


class a_group:
    """dup_render.py's group as a pushed head transform."""
    def __init__(self, loc=(0, 0, 0), rot=(0, 0, 0), fixed=False):
        self.m = M(loc, _deg(rot))

    def __enter__(self):
        HEAD.append(HEAD[-1] @ self.m)

    def __exit__(self, *a):
        HEAD.pop()


def _load_plumbing_shapes():
    """oil_tank, purifier and the wall panel from dup_render.py, without running its pz-sprite-forge setup."""
    tree = ast.parse(open(_MOD).read())
    names = {"oil_tank", "purifier", "wallpanel", "_wallpanel_parts"}
    consts = {"STEEL", "DARK", "BRASS", "BLACK", "CONCRETE", "CEILING_Z"}

    def assigns(n):
        ids = set()
        for t in n.targets:
            ids |= {getattr(e, "id", None) for e in t.elts} if isinstance(t, ast.Tuple) else {getattr(t, "id", None)}
        return ids & consts

    body = [n for n in tree.body if (isinstance(n, ast.FunctionDef) and n.name in names) or (isinstance(n, ast.Assign) and assigns(n))]
    ns = dict(math=math, mat=a_mat, box=a_box, cyl=a_cyl, ball=a_ball, tube=a_tube, torus=a_torus, obround=a_obround,
              group=a_group, paint=tank_paint)
    exec(compile(ast.Module(body=body, type_ignores=[]), _MOD, "exec"), ns)
    return ns


PL = _load_plumbing_shapes()


def big_tank(n, typ, tier):
    set_wear("ok", "tank")
    PL["oil_tank"](n, typ, tier)


def tank(size, typ, tier):
    if size == "small":
        pl_tank(size, typ, tier)
    else:
        big_tank(2 if size == "large" else 3, typ, tier)


# ------------------------------------------------------------------ jobs
def want(f):
    return "all" in _WANT or f in _WANT


WEAR.update(rust=0.0, dirt=0.0, scorch=0.0)
os.makedirs(CELLS, exist_ok=True)
tile_camera()
if want("tanks"):
    for size, n in PL_SIZES:
        for ti, typ in enumerate(PL_TYPES):
            for ri, tier in enumerate(PL_TIERS):
                clear(); start = len(BUILT); tank(size, typ, tier); root, fixed = make_root(start)
                r = ti * 2 + ri
                for col, (fname, d) in enumerate(FACINGS):
                    root.rotation_euler = (0, 0, math.radians(d))
                    along_x = fname in ("S", "N")
                    centre = ((n - 1) / 2, 0) if along_x else (0, -(n - 1) / 2)
                    for pc in range(n):
                        piece = (pc, 0) if along_x else (0, -pc)          # Blender -y is PZ +y (south)
                        root.location = (centre[0] - piece[0], centre[1] - piece[1], 0)
                        idx = PL_BLOCK[size] + (r * 4 + col) * n + pc
                        render(os.path.join(CELLS, "%d.png" % idx))
                        if n > 1:
                            render_mask(os.path.join(CELLS, "%d_m.png" % idx))
                log("tank", size, typ, tier)
if want("pipes"):                     # 144-159 overhead on a ceiling hanger, 160-175 on the ground (dup_render.py's order)
    for i in range(32):
        fixed_render(lambda i=i: pipe_cell(i % 16, i >= 16), CELLS, PIPE_BASE + i)
if want("valves"):
    for i in range(8):
        fixed_render(lambda i=i: valve_cell(i < 4, (i % 4) >= 2, i % 2 == 1), CELLS, VALVE_BASE + i)
if want("ports"):
    for i in range(16):
        fixed_render(lambda i=i: port_cell((1, 2, 4, 8)[i % 4], (i // 4) % 2 == 1, i >= 8), CELLS, PORT_BASE + i)
if want("machines"):
    facings_render(hand_pump, CELLS, lambda c: PUMP_BASE + c)
    facings_render(electric_pump, CELLS, lambda c: PUMP_BASE + 4 + c)
    facings_render(lambda: hand_pump(True), CELLS, lambda c: STROKE_BASE + c)
    facings_render(PL["purifier"], CELLS, lambda c: PURIFIER_BASE + c)
    facings_render(downspout, CELLS, lambda c: SPOUT_BASE + c)
    facings_render(lambda: sprinkler(False), CELLS, lambda c: SPRINKLER_BASE + c)
    facings_render(lambda: sprinkler(True), CELLS, lambda c: SPRINKLER_BASE + 4 + c)
    facings_render(lambda: PL["wallpanel"](False), CELLS, lambda c: WALLPANEL_BASE + c)
if want("icons"):
    for size, n in PL_SIZES[1:]:
        for typ in PL_TYPES:
            for tier in PL_TIERS:
                name = "Item_DazedTank%s%s%s" % ({"large": "Large", "xl": "XL"}[size], typ.capitalize(), tier.capitalize())
                icon_shot(name, lambda n=n, t=typ, r=tier: big_tank(n, t, r), ICONS)
    icon_shot("Item_DazedPurifier", PL["purifier"], ICONS)
    icon_shot("Item_DazedWaterPanel", lambda: PL["wallpanel"](True), ICONS)
log("dup_power_render done", _WANT)
