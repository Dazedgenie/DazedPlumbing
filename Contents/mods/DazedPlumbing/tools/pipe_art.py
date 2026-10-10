"""Redraw the 32 pipe sprites (dazedplumb_01_144..175) and write them into the texture pack.

Usage:  python3 tools/pipe_art.py [--preview out.png]
Needs Pillow. tools/pzformat/packfile.py is from pz-sprite-forge (MIT, see its licence file).
The art is light grey on purpose: the game tints it per fluid (water blue, propane white, petrol red).
"""
import io, sys, argparse
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "pzformat"))                      # a local copy, if any
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))   # the shared copy in Dazed Core
from packfile import TexturePack, PackEntry  # noqa: E402

PACK = HERE.parent / "common/media/texturepacks/dazedplumbing.pack"
BASE, SS = 144, 4                      # first pipe sprite index, supersampling
CW, CH = 128, 256                      # cell size
GROUND_CY, OVERHEAD_CY = 219, 86       # pipe centre line (tile centre is y=224 on the floor)
# mask bits N=1 E=2 S=4 W=8 -> the way each arm runs on screen (to the tile edge's middle)
ARMS = {1: (32, -16), 2: (32, 16), 4: (-32, 16), 8: (-32, -16)}
OVERSHOOT = 1.12                       # arms run a little past the edge so neighbours overlap

OUTLINE, BODY, LIGHT, SHADE = (34, 37, 46, 255), (205, 209, 218, 255), (248, 250, 253, 255), (150, 155, 170, 255)


def draw_cell(mask, outdoor):
    img = Image.new("RGBA", (CW * SS, CH * SS), (0, 0, 0, 0))
    cy = GROUND_CY if outdoor else OVERHEAD_CY
    d = ImageDraw.Draw(img)

    def P(dx, dy): return ((64 + dx) * SS, (cy + dy) * SS)

    def line(a, b, width, fill, off=(0, 0)):
        d.line([P(a[0] + off[0], a[1] + off[1]), P(b[0] + off[0], b[1] + off[1])], fill=fill, width=int(width * SS))

    def disc(rx, ry, fill, off=(0, 0)):
        x, y = P(off[0], off[1])
        d.ellipse([x - rx * SS, y - ry * SS, x + rx * SS, y + ry * SS], fill=fill)

    bits = [b for b in (1, 2, 4, 8) if (mask // b) % 2 == 1]
    back = [b for b in bits if ARMS[b][1] < 0]      # arms that run up the screen are drawn first
    front = [b for b in bits if ARMS[b][1] > 0]
    count = len(bits)
    if outdoor:                                      # a soft shadow on the ground
        for b in bits or [0]:
            tip = (ARMS[b][0] * OVERSHOOT, ARMS[b][1] * OVERSHOOT) if b else (0, 0)
            line((0, 0), tip, 13, (0, 0, 0, 70), off=(0, 5))
    else:                                            # hanger rod and plate from the ceiling
        line((0, -70), (0, 0), 2.2, OUTLINE)
        disc(6, 3, OUTLINE, off=(0, -70))

    def arm(b):
        tip = (ARMS[b][0] * OVERSHOOT, ARMS[b][1] * OVERSHOOT)
        line((0, 0), tip, 15, OUTLINE)
        line((0, 0), tip, 11, BODY)
        line((0, 0), tip, 3, LIGHT, off=(0, -2.5))
        line((0, 0), tip, 3, SHADE, off=(0, 3))

    for b in back: arm(b)
    # the coupling at the middle: a collar on elbows, junctions, ends and bare stubs
    straight = count == 2 and (mask in (5, 10))
    if not straight:
        disc(10, 7.5, OUTLINE)
        disc(8, 5.8, (176, 181, 193, 255))
        disc(5, 3, LIGHT, off=(-1.5, -1.5))
    for b in front: arm(b)
    if straight:                                     # a flange where the run crosses the tile's middle
        disc(7, 5.5, OUTLINE)
        disc(5.6, 4.2, (190, 195, 206, 255))
    return img.resize((CW, CH), Image.LANCZOS)


def repack(pack_path, cells):
    """Replace (or add) sprites by index with full 128x256 cells ({index: RGBA image}); trims each,
    shelf-packs every sprite onto a 2048-wide page and writes the pack. Returns the page size."""
    pk = TexturePack.read(pack_path)
    page = pk.pages[0]
    old = Image.open(io.BytesIO(page.png)).convert("RGBA")
    sprites = []                                     # (entry, image) in the original order
    for e in page.entries:
        n = int(e.name.rsplit("_", 1)[1])
        if n in cells:
            cell = cells[n]
            bb = cell.getbbox()
            ne = PackEntry(e.name, 0, 0, bb[2] - bb[0], bb[3] - bb[1], bb[0], bb[1], CW, CH)
            sprites.append((ne, cell.crop(bb)))
        else:
            sprites.append((e, old.crop((e.x, e.y, e.x + e.w, e.y + e.h))))
    # new indices are added to the pack, in order
    have = {int(e.name.rsplit("_", 1)[1]) for e, _ in sprites}
    stem = sprites[0][0].name.rsplit("_", 1)[0]
    for n in sorted(set(cells) - have):
        cell = cells[n]
        bb = cell.getbbox()
        ne = PackEntry("%s_%d" % (stem, n), 0, 0, bb[2] - bb[0], bb[3] - bb[1], bb[0], bb[1], CW, CH)
        sprites.append((ne, cell.crop(bb)))
    # shelf-pack onto a 2048-wide page, tallest first
    order = sorted(range(len(sprites)), key=lambda i: -sprites[i][0].h)
    x = y = shelf = 0
    pos = {}
    for i in order:
        e = sprites[i][0]
        if x + e.w + 2 > 2048:
            x, y, shelf = 0, y + shelf + 2, 0
        pos[i] = (x, y)
        x += e.w + 2
        shelf = max(shelf, e.h)
    height = 1
    while height < y + shelf: height *= 2
    sheet = Image.new("RGBA", (2048, height), (0, 0, 0, 0))
    for i, (e, im) in enumerate(sprites):
        e.x, e.y = pos[i]
        sheet.paste(im, pos[i])
    buf = io.BytesIO(); sheet.save(buf, "PNG")
    page.png = buf.getvalue()
    page.entries = [e for e, _ in sprites]
    pk.write(pack_path)
    return sheet.size


def build(pack_path=PACK):
    return repack(pack_path, {BASE + i: draw_cell(i % 16, i >= 16) for i in range(32)})


def preview(out):
    """A run, an elbow, a T and a cross, ground and overhead, side by side."""
    W, H = 900, 640
    canvas = Image.new("RGBA", (W, H), (88, 98, 80, 255))
    pk = TexturePack.read(PACK)
    pg = pk.pages[0]
    sheet = Image.open(io.BytesIO(pg.png)).convert("RGBA")
    by = {e.name: e for e in pg.entries}

    def cell(n):
        e = by["dazedplumb_01_%d" % n]
        c = Image.new("RGBA", (CW, CH), (0, 0, 0, 0)); c.paste(sheet.crop((e.x, e.y, e.x + e.w, e.y + e.h)), (e.ox, e.oy)); return c

    def tint(im, rgb):
        r, g, b, a = im.split()
        return Image.merge("RGBA", (r.point(lambda v: v * rgb[0] // 255), g.point(lambda v: v * rgb[1] // 255), b.point(lambda v: v * rgb[2] // 255), a))

    def put(gx, gy, n, rgb, ox, oy):                 # grid square -> screen (x right-down, y left-down)
        sx, sy = ox + (gx - gy) * 64, oy + (gx + gy) * 32
        canvas.alpha_composite(tint(cell(n), rgb), (int(sx) - 64, int(sy) - 224))

    water, gas, prop = (77, 153, 255), (224, 46, 46), (245, 245, 245)
    for k in range(5): put(k, 0, BASE + 16 + 10, water, 120, 230)             # E-W run, outdoors
    for k in range(5): put(0, k, BASE + 16 + 5, gas, 120, 230)                # N-S run, outdoors
    put(0, 0, BASE + 16 + 2 + 4, gas, 120, 230)                               # elbow where they meet
    for k in range(1, 4): put(k + 6, 2, BASE + 10, prop, 120, 230)            # overhead run
    put(5, 5, BASE + 16 + 1 + 2 + 8, water, 120, 230)                         # a T
    put(7, 6, BASE + 16 + 15, water, 120, 230)                                # a cross
    canvas.resize((W * 2 // 2, H), Image.LANCZOS).save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    print("page", build())
    if a.preview: preview(a.preview)
