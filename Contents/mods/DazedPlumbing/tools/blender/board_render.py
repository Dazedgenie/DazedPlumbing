"""Blender script: renders the Main Water Panel board's own parts (tank column, LINE RATE knob, MAIN SHUT-OFF
handwheel open and turned) top-down at 2x for media/ui/DazedPlumbing/Board. Same camera, lights and helpers as
Dazed Power's tools/blender/board_render.py, so the parts sit with its gauge face, lamps and toggles.
Run inside Blender (4.2+ / 5.x): BOARD_OUT = r"C:\\...\\out\\board"; exec(open(path).read())
or headless:  blender -b -P board_render.py -- <BOARD_OUT> [part ...]
Optional globals: BOARD_OUT (default <this folder>/out/board), BOARD_SAMPLES (default 96), BOARD_ONLY (list of names).
Then: python3 tools/pack_panel_renders.py --renders <the out folder holding board/>.
The gauge face, needle, hub, lamps, toggles and number wheel are not rendered here: DUP_BoardLayout's Board.tex finds
them in Dazed Power's folder when that mod is loaded and draws plain stand-ins without it.
"""
import bpy
import math
import os
import sys

if "BOARD_OUT" not in globals() and "--" in sys.argv:
    _argv = sys.argv[sys.argv.index("--") + 1:]
    if _argv:
        BOARD_OUT = _argv[0]
    if _argv[1:]:
        BOARD_ONLY = _argv[1:]
OUT = globals().get("BOARD_OUT") or os.path.join(os.path.dirname(os.path.abspath(globals().get("__file__", "."))), "out", "board")
SAMPLES = globals().get("BOARD_SAMPLES", 96)
ONLY = globals().get("BOARD_ONLY")
U = 0.1          # one base pixel in Blender units; renders come out at 2 px per base pixel


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def mat(name, col, rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def srgb(r, g, b):
    """sRGB 0-255 to the linear values Blender's colour inputs take."""
    def f(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b))


def put(obj, m):
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def cyl(r, depth, z, m, verts=96, x=0, y=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r * U, depth=depth * U, location=(x * U, y * U, z * U))
    return put(bpy.context.object, m)


def box(w, h, d, z, m, x=0, y=0, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x * U, y * U, z * U))
    o = bpy.context.object
    o.scale = (w * U, h * U, d * U)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel * U
        mod.segments = 4
    return put(o, m)


def torus(R, r, z, m, x=0, y=0):
    bpy.ops.mesh.primitive_torus_add(major_radius=R * U, minor_radius=r * U, major_segments=128, minor_segments=24,
                                     location=(x * U, y * U, z * U))
    return put(bpy.context.object, m)


def sphere(r, z, m, x=0, y=0, flat=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * U, segments=48, ring_count=24, location=(x * U, y * U, z * U))
    o = bpy.context.object
    o.scale = (1, 1, flat)
    return put(o, m)


def setup(w, h):
    """Camera straight down over a w x h base-pixel part, a soft key from the upper left, transparent film."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = int(w * 2), int(h * 2)
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(w, h) * U
    co = bpy.data.objects.new("cam", cam)
    co.location = (0, 0, 100 * U)
    sc.collection.objects.link(co)
    sc.camera = co
    for name, loc, power, size in (("key", (-60, 80, 120), 30000, 80), ("fill", (70, -40, 90), 10000, 120)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = power * U * U
        ld.size = size * U
        lo = bpy.data.objects.new(name, ld)
        lo.location = tuple(v * U for v in loc)
        lo.rotation_euler = (0, 0, 0)
        d = lo.location
        lo.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        sc.collection.objects.link(lo)
    world = sc.world or bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0


def shoot(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


BLACK = lambda: mat("black", srgb(28, 28, 26), 0.35, 0.6)
CHROME = lambda: mat("chrome", srgb(200, 200, 196), 0.18, 1.0)

# The tank column's sight glass in base px from the image's top left (x, y, w, h); DUP_BoardLayout's
# Board.TANK_WINDOW is the same rect, and the Lua draws the water into it over this render's dark glass.
TANK_W, TANK_H = 60, 170
TANK_WINDOW = (9, 19, 42, 140)


def px_to_world(px, py, w, h):
    """A point in base px from a w x h image's top left, as the setup() camera's world x, y in base px."""
    return px - w / 2, h / 2 - py


def tank_column():
    # A painted steel water-tower case: a vent cap on top, riveted bands above and below a tall sight glass.
    setup(TANK_W, TANK_H)
    steel = mat("case", srgb(92, 102, 110), 0.45, 0.3)
    dark = mat("band", srgb(58, 64, 70), 0.4, 0.5)
    box(58, 158, 10, 0, steel, y=-5, bevel=6)                    # the case, py 11-169
    box(40, 10, 8, 0, dark, y=78, bevel=3)                       # vent cap, py 2-12
    cyl(3, 4, 4, CHROME(), verts=32, y=82)
    for yb in (70, -79):                                         # bands just clear of the glass (py 15 and 164)
        box(58, 3.5, 11, 0.5, dark, y=yb, bevel=1)
        for xr in (-24, -12, 0, 12, 24):
            sphere(1.2, 6, CHROME(), x=xr, y=yb, flat=0.6)
    for xr in (-25.5, 25.5):                                     # rivet columns either side of the glass
        for k in range(7):
            sphere(1.1, 5, CHROME(), x=xr, y=60 - k * 21, flat=0.6)
    wx, wy, ww, wh = TANK_WINDOW
    cx, cy = px_to_world(wx + ww / 2, wy + wh / 2, TANK_W, TANK_H)    # (0, -4)
    box(ww + 4, wh + 4, 4, 4.5, BLACK(), x=cx, y=cy, bevel=1.5)  # the glass frame, 2 px round the window
    # The glass itself: exactly the window rect, no bevel, so its edges land on whole base pixels.
    box(ww, wh, 3, 5.5, mat("glass", srgb(24, 24, 23), 0.25), x=cx, y=cy)


def knob():
    # Points right (+x): DUP_BoardLayout turns it with Board.knobQuad to 225 - 270 * rate/flow degrees.
    setup(36, 36)
    cyl(17.5, 3, 0, BLACK())                                     # skirt
    grip = mat("grip", srgb(44, 44, 42), 0.5, 0.3)
    cyl(14, 6, 3, grip)
    for k in range(30):                                          # knurling round the grip
        a = 2 * math.pi * k / 30
        o = box(1.4, 2.6, 6, 3, grip, x=14 * math.cos(a), y=14 * math.sin(a))
        o.rotation_euler = (0, 0, a)
    cyl(12, 1.5, 6.5, mat("cap", srgb(141, 150, 156), 0.3, 0.8))  # steel cap
    cream = srgb(238, 230, 208)
    box(9.5, 2.2, 1, 7.4, mat("mark", cream, 0.5, emit=cream, strength=0.3), x=6.75)


SPOKES = 4        # four spokes, so a 60 degree turn reads clearly (five or six would look nearly the same as open)
TURN = 60         # the turned wheel's rotation in degrees


def wheel(turned):
    # A red gate-valve handwheel over its bonnet; turned is rotated, sunk 3 px and a shade darker in its shadow.
    setup(92, 92)
    cyl(12, 6, -8, mat("bonnet", srgb(70, 72, 74), 0.4, 0.8))       # the valve bonnet under the wheel
    turn = math.radians(TURN if turned else 0)
    dz, sc = (-3, 0.97) if turned else (0, 1.0)
    red = mat("red", srgb(150, 34, 26) if turned else srgb(192, 46, 36), 0.35, 0.1)
    torus(40 * sc, 3.6 * sc, dz, red)                             # the rim, 43.6 px out
    for k in range(SPOKES):
        a = turn + 2 * math.pi * k / SPOKES
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=2.4 * sc * U, depth=32 * sc * U,
                                            location=(22 * sc * math.cos(a) * U, 22 * sc * math.sin(a) * U, dz * U))
        o = put(bpy.context.object, red)
        o.rotation_euler = (0, math.pi / 2, a)
    cyl(8 * sc, 6, dz + 1, red, verts=48)                         # hub
    nut = box(7 * sc, 7 * sc, 4, dz + 5, CHROME(), bevel=0.8)      # square stem nut, turning with the wheel
    nut.rotation_euler = (0, 0, turn + math.pi / 4)
    cyl(2.2 * sc, 2, dz + 7.5, CHROME(), verts=24)


PARTS = {
    "tank_column": tank_column, "knob": knob,
    "wheel_open": lambda: wheel(False), "wheel_turned": lambda: wheel(True),
}

for name, build in PARTS.items():
    if ONLY and name not in ONLY:
        continue
    clear()
    build()
    shoot(name)
print("BOARD DONE", OUT)
