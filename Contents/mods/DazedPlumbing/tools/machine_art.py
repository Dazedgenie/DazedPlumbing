"""Redraw the pump and purifier sprites (dazedplumb_01_176..187) and write them into the texture pack.

Usage:  python3 tools/machine_art.py [--preview out.png]
Needs Pillow. Machines are built from shaded isometric boxes centred on the tile (ground centre at
y=224 in the 128x256 cell), so they line up with the pipes. 176-179 hand pump, 180-183 electric pump,
184-187 purifier, 192-195 downspout; each in facings E, S, W, N (a downspout faces the wall it is bolted to).
"""
import io, sys, argparse
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pipe_art  # noqa: E402
from pipe_art import CW, CH, PACK, repack  # noqa: E402

SS = 4
BASE = 176
OUTLINE = (30, 32, 40, 255)


def shade(c, k): return (int(c[0] * k), int(c[1] * k), int(c[2] * k), 255)


class Canvas:
    def __init__(self, outline=1.2):
        self.outline = outline                                   # outline width in cell pixels
        self.img = Image.new("RGBA", (CW * SS, CH * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def pt(self, u, v, z):
        """(u east, v south) in half tiles, z in pixels up -> supersampled screen point."""
        return ((64 + 32 * u - 32 * v) * SS, (224 + 16 * u + 16 * v - z) * SS)

    def poly(self, pts, fill):
        self.d.polygon(pts, fill=fill)
        self.d.line(pts + [pts[0]], fill=OUTLINE, width=max(1, int(self.outline * SS)))

    def shadow(self, r):
        pts = [self.pt(-r, -r, 0), self.pt(r, -r, 0), self.pt(r, r, 0), self.pt(-r, r, 0)]
        self.d.polygon(pts, fill=(10, 12, 16, 85))

    def box(self, u0, u1, v0, v1, z0, z1, col):
        top = [self.pt(u0, v0, z1), self.pt(u1, v0, z1), self.pt(u1, v1, z1), self.pt(u0, v1, z1)]
        east = [self.pt(u1, v0, z1), self.pt(u1, v1, z1), self.pt(u1, v1, z0), self.pt(u1, v0, z0)]
        south = [self.pt(u0, v1, z1), self.pt(u1, v1, z1), self.pt(u1, v1, z0), self.pt(u0, v1, z0)]
        self.poly(south, shade(col, 0.62))
        self.poly(east, shade(col, 0.80))
        self.poly(top, col + (255,) if len(col) == 3 else col)

    def done(self):
        return self.img.resize((CW, CH), Image.LANCZOS)


def place(facing, a0, a1, b0, b1):
    """A box given along the facing axis (a) and across it (b) -> (u0, u1, v0, v1)."""
    if facing == "E": u, v = (a0, a1), (b0, b1)
    elif facing == "S": u, v = (-b1, -b0), (a0, a1)
    elif facing == "W": u, v = (-a1, -a0), (-b1, -b0)
    else: u, v = (b0, b1), (-a1, -a0)                         # N
    return u[0], u[1], v[0], v[1]


def parts_draw(parts, cv, facing):
    """parts: (a0, a1, b0, b1, z0, z1, colour) in facing coordinates; drawn far to near."""
    boxes = []
    for a0, a1, b0, b1, z0, z1, col in parts:
        u0, u1, v0, v1 = place(facing, a0, a1, b0, b1)
        boxes.append(((u0 + u1 + v0 + v1) / 2, z0, (u0, u1, v0, v1, z0, z1, col)))
    for _, _, b in sorted(boxes, key=lambda t: (t[0], t[1])):
        cv.box(*b)


STEEL, DARK, LIGHT = (84, 90, 102), (58, 62, 72), (176, 182, 194)
STONE = (150, 150, 156)
WATER = (64, 132, 214)


def hand_pump(facing, outline=1.2):
    cv = Canvas(outline); cv.shadow(0.8)
    parts_draw([
        (-0.55, 0.55, -0.55, 0.55, 0, 6, STONE),                 # base slab
        (-0.17, 0.17, -0.17, 0.17, 6, 72, DARK),                 # column
        (-0.27, 0.27, -0.27, 0.27, 60, 80, STEEL),               # head
        (0.1, 0.9, -0.08, 0.08, 38, 48, STEEL),                  # spout, toward the facing
        (0.72, 0.9, -0.05, 0.05, 24, 38, WATER),                 # the water running out
        (-1.0, 0.3, -0.07, 0.07, 80, 88, LIGHT),                 # handle, swung back
        (-1.0, -0.8, -0.1, 0.1, 80, 92, STEEL),                  # its grip
    ], cv, facing)
    return cv.done()


def electric_pump(facing, outline=1.2):
    cv = Canvas(outline); cv.shadow(0.85)
    parts_draw([
        (-0.55, 0.55, -0.55, 0.55, 0, 42, (46, 112, 82)),        # motor housing
        (-0.58, 0.58, -0.58, 0.58, 42, 48, (216, 186, 60)),      # yellow cap
        (0.5, 1.0, -0.14, 0.14, 14, 28, LIGHT),                  # outlet
        (-1.0, -0.5, -0.14, 0.14, 14, 28, DARK),                 # inlet
        (-0.2, 0.2, -0.2, 0.2, 48, 56, DARK),                    # terminal box
    ], cv, facing)
    return cv.done()


def purifier(facing, outline=1.2):
    cv = Canvas(outline); cv.shadow(0.85)
    parts_draw([
        (-0.55, 0.55, -0.55, 0.55, 0, 92, (186, 191, 201)),      # cabinet
        (-0.57, 0.57, -0.57, 0.57, 92, 98, (240, 243, 248)),     # lid
        (0.55, 0.62, -0.3, 0.3, 30, 72, WATER),                  # window on the facing side
        (0.5, 1.0, -0.14, 0.14, 12, 26, LIGHT),                  # outlet
        (-1.0, -0.5, -0.14, 0.14, 12, 26, DARK),                 # inlet
        (-0.25, 0.25, -0.25, 0.25, 98, 104, STEEL),              # vent
    ], cv, facing)
    return cv.done()


PIPE = (205, 209, 218)


def downspout(facing, outline=1.2):
    """A pipe down a wall (the wall is on the facing side, a = 1), an elbow and a short run out."""
    cv = Canvas(outline); cv.shadow(0.5)
    parts_draw([
        (0.72, 0.96, -0.11, 0.11, 18, 118, PIPE),                # the pipe down the wall
        (0.55, 1.0, -0.4, 0.4, 118, 128, LIGHT),                 # the gutter outlet at the top
        (0.62, 0.98, -0.15, 0.15, 40, 46, STEEL),                # lower bracket
        (0.62, 0.98, -0.15, 0.15, 88, 94, STEEL),                # upper bracket
        (0.1, 0.96, -0.11, 0.11, 8, 22, PIPE),                   # elbow and run out from the wall
        (-0.1, 0.1, -0.14, 0.14, 6, 24, STEEL),                  # open end
    ], cv, facing)
    return cv.done()


FACINGS = ("E", "S", "W", "N")


def cells():
    out = {}
    for i, f in enumerate(FACINGS):
        out[BASE + i] = hand_pump(f)
        out[BASE + 4 + i] = electric_pump(f)
        out[BASE + 8 + i] = purifier(f)
        out[192 + i] = downspout(f)
    return out


def build(pack_path=PACK):
    return repack(pack_path, cells())


def preview(out):
    """Each machine on its tile with a blue pipe leading in on the east and south sides."""
    from packfile import TexturePack
    W, H = 900, 980
    canvas = Image.new("RGBA", (W, H), (88, 98, 80, 255))
    pg = TexturePack.read(PACK).pages[0]
    sheet = Image.open(io.BytesIO(pg.png)).convert("RGBA")
    by = {e.name: e for e in pg.entries}

    def cell(n):
        e = by["dazedplumb_01_%d" % n]
        c = Image.new("RGBA", (CW, CH), (0, 0, 0, 0)); c.paste(sheet.crop((e.x, e.y, e.x + e.w, e.y + e.h)), (e.ox, e.oy)); return c

    def tint(im, rgb):
        r, g, b, a = im.split()
        return Image.merge("RGBA", (r.point(lambda v: v * rgb[0] // 255), g.point(lambda v: v * rgb[1] // 255), b.point(lambda v: v * rgb[2] // 255), a))

    def put(ox, oy, gx, gy, n, rgb=None):
        im = cell(n)
        if rgb: im = tint(im, rgb)
        canvas.alpha_composite(im, (int(ox + (gx - gy) * 64) - 64, int(oy + (gx + gy) * 32) - 224))

    blue = (77, 153, 255)
    for row in range(4):
        for col in range(4):
            ox, oy = 90 + col * 215, 150 + row * 215
            # neighbours first so the machine stands in front of the pipes' ends
            put(ox, oy, 1, 0, pipe_art.BASE + 16 + 8, blue)       # pipe with an arm west
            put(ox, oy, 0, 1, pipe_art.BASE + 16 + 1, blue)       # pipe with an arm north
            put(ox, oy, 0, 0, (192 + col) if row == 3 else BASE + row * 4 + col)
    canvas.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    sys.path.insert(0, str(HERE / "pzformat"))                      # a local copy, if any
    sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))   # the shared copy in Dazed Core
    print("page", build())
    if a.preview: preview(a.preview)
