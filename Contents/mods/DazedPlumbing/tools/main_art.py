"""Placeholder sprites for the water main (dazedplumb_01_232..235, facings E S W N) and its icon.

Usage:  python3 tools/main_art.py [--preview out.png]
Needs Pillow. A low concrete stop-cock box with a blue valve wheel on top and a pipe stub out of the
facing side, drawn with machine_art's isometric boxes so it lines up with the pipes. Blender renders
replace these later (tools/blender/dup_render.py).
"""
import sys, argparse
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from machine_art import Canvas, parts_draw, STEEL, DARK, LIGHT, WATER  # noqa: E402
from pipe_art import CW, CH, PACK, repack  # noqa: E402

BASE = 232
FACINGS = ("E", "S", "W", "N")
CONCRETE = (142, 140, 134)
LID = (110, 108, 102)
VALVE = (52, 110, 200)


def water_main(facing, outline=1.2):
    cv = Canvas(outline); cv.shadow(0.8)
    parts_draw([
        (-0.5, 0.5, -0.5, 0.5, 0, 26, CONCRETE),                  # the box
        (-0.52, 0.52, -0.52, 0.52, 26, 30, LID),                  # its lid
        (-0.12, 0.12, -0.12, 0.12, 30, 44, STEEL),                # riser
        (-0.3, 0.3, -0.3, 0.3, 44, 50, VALVE),                    # valve wheel
        (-0.04, 0.04, -0.3, 0.3, 50, 53, VALVE),                  # wheel spokes
        (-0.3, 0.3, -0.04, 0.04, 50, 53, VALVE),
        (0.5, 1.0, -0.12, 0.12, 8, 20, LIGHT),                    # pipe stub to the facing side
        (0.92, 1.0, -0.16, 0.16, 6, 22, DARK),                    # its flange
        (-0.44, 0.44, 0.5, 0.56, 10, 22, (28, 30, 36)),           # a dark slot on the south face
    ], cv, facing)
    return cv.done()


def icon():
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([4, 14, 27, 28], fill=CONCRETE + (255,), outline=(40, 40, 44, 255))
    d.rectangle([3, 12, 28, 15], fill=LID + (255,))
    d.rectangle([14, 6, 17, 13], fill=STEEL + (255,))
    d.ellipse([9, 2, 22, 10], outline=VALVE + (255,), width=3)
    d.rectangle([22, 18, 30, 23], fill=LIGHT + (255,))
    return im


def cells():
    return { BASE + i: water_main(f) for i, f in enumerate(FACINGS) }


def build(pack_path=PACK):
    icon().save(HERE.parent / "common/media/textures/Item_DazedWaterMain.png")
    return repack(pack_path, cells())


def preview(out):
    sheet = Image.new("RGBA", (CW * 4, CH), (88, 98, 80, 255))
    for i, f in enumerate(FACINGS):
        sheet.alpha_composite(water_main(f), (i * CW, 0))
    sheet.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    print("page", build())
    if a.preview: preview(a.preview)
