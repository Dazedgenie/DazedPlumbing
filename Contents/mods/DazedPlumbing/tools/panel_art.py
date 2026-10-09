"""Placeholder sprites for the wall water panel (dazedplumb_01_256..259, facings E S W N) and its icon.

Usage:  python3 tools/panel_art.py [--preview out.png]
Needs Pillow and the core's pzformat (tools/pack_tiles.py finds it). Grows the sheet to 8x33 if needed, gives the
four tiles their properties and packs a grey cabinet with two gauges, hung on the wall on its facing side (like the
downspout, the sprite faces the wall it is fixed to). Blender renders replace these later.
"""
import sys, argparse
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from machine_art import Canvas, parts_draw, STEEL, DARK, LIGHT, WATER  # noqa: E402
from pipe_art import CW, CH, PACK, repack  # noqa: E402
import pack_tiles  # noqa: E402

BASE = 256
FACINGS = ("E", "S", "W", "N")
BODY = (120, 132, 138)
FACE = (226, 222, 204)
RED = (184, 44, 34)


def panel(facing, outline=1.2):
    cv = Canvas(outline)
    parts_draw([
        (0.80, 0.98, -0.46, 0.46, 64, 124, BODY),                 # the cabinet on the wall
        (0.76, 0.80, -0.40, -0.04, 96, 118, FACE),                # left gauge
        (0.76, 0.80, 0.04, 0.40, 96, 118, FACE),                  # right gauge
        (0.75, 0.80, -0.30, 0.30, 72, 86, DARK),                  # the fixture strip
        (0.72, 0.80, 0.26, 0.38, 68, 80, RED),                    # the shut-off handle
        (0.86, 0.98, -0.06, 0.06, 24, 64, LIGHT),                 # conduit down the wall
    ], cv, facing)
    return cv.done()


def icon():
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([3, 5, 28, 26], fill=BODY + (255,), outline=(40, 40, 44, 255))
    d.ellipse([6, 8, 14, 16], fill=FACE + (255,), outline=(40, 40, 44, 255))
    d.ellipse([17, 8, 25, 16], fill=FACE + (255,), outline=(40, 40, 44, 255))
    d.rectangle([6, 19, 20, 23], fill=DARK + (255,))
    d.rectangle([22, 19, 26, 24], fill=RED + (255,))
    d.line([10, 12, 12, 9], fill=RED + (255,), width=1)
    d.line([21, 12, 23, 10], fill=WATER + (255,), width=1)
    return im


def tiles():
    """Grow the sheet to 33 rows if needed and give tiles 256-259 the panel's properties."""
    td = pack_tiles.load()
    if td.tilesets[0].rows < 33:
        pack_tiles.grow(33)
    for i, f in enumerate(FACINGS):
        pack_tiles.add_tile(BASE + i, [
            ("CustomName", "Water Panel"), ("GroupName", "Dazed Plumbing"), ("Facing", f),
            ("Material", "MetalPlates"), ("Material2", "MetalScrap"), ("MaterialType", "Metal_Light"),
            ("IsMoveAble", ""), ("CustomItem", "Base.DazedWaterPanel"), ("PickUpWeight", "40"),
            ("PickUpLevel", "0"), ("MoveType", "Object"),
            ("Eoffset", "0"), ("Soffset", "1"), ("Woffset", "2"), ("Noffset", "3"),
        ])


def build(pack_path=PACK):
    tiles()
    icon().save(HERE.parent / "common/media/textures/Item_DazedWaterPanel.png")
    return repack(pack_path, {BASE + i: panel(f) for i, f in enumerate(FACINGS)})


def preview(out):
    sheet = Image.new("RGBA", (CW * 4, CH), (88, 98, 80, 255))
    for i, f in enumerate(FACINGS):
        sheet.alpha_composite(panel(f), (i * CW, 0))
    sheet.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    print("page", build())
    if a.preview: preview(a.preview)
