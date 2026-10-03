"""Draw the mod's inventory icons (32x32) for the pipe section, valve, pumps, purifier, filter and downspout.

Usage:  python3 tools/icon_art.py [--preview out.png]
Same isometric box style as the world sprites (tools/machine_art.py). The tank icons are not touched.
"""
import sys, argparse
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import machine_art as m  # noqa: E402
from machine_art import Canvas, parts_draw, PIPE, LIGHT, STEEL, DARK  # noqa: E402

TEX = HERE.parent / "common/media/textures"
OUT = 5.0                                                        # outline width, so it survives the shrink to 32 px
RED = (205, 55, 50)
BLUE = (64, 132, 214)


def fit(cell):
    """Crop a drawn cell to its content and fit it into a 32x32 icon, centred."""
    cell = cell.crop(cell.getbbox())
    cell.thumbnail((30, 30), Image.LANCZOS)
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(cell, ((32 - cell.width) // 2, 31 - cell.height if cell.height < 28 else (32 - cell.height) // 2))
    return out


def pipe_section():
    cv = Canvas(OUT)
    parts_draw([
        (-0.9, 0.9, -0.2, 0.2, 10, 38, PIPE),                    # the length of pipe
        (-0.9, -0.7, -0.27, 0.27, 7, 41, LIGHT),                 # a flange at each end
        (0.7, 0.9, -0.27, 0.27, 7, 41, LIGHT),
    ], cv, "E")
    return cv.done()


def valve():
    cv = Canvas(OUT)
    parts_draw([
        (-0.9, 0.9, -0.16, 0.16, 10, 34, PIPE),                  # the pipe either side
        (-0.3, 0.3, -0.3, 0.3, 8, 40, STEEL),                    # the valve body
        (-0.06, 0.06, -0.06, 0.06, 40, 62, DARK),                # the stem
        (-0.4, 0.4, -0.4, 0.4, 62, 68, RED),                     # the red handwheel
    ], cv, "E")
    return cv.done()


def filter_cartridge():
    cv = Canvas(OUT)
    parts_draw([
        (-0.4, 0.4, -0.4, 0.4, 0, 74, (232, 236, 242)),          # the cartridge
        (-0.43, 0.43, -0.43, 0.43, 28, 46, BLUE),                # its blue band
        (-0.3, 0.3, -0.3, 0.3, 74, 82, STEEL),                   # the cap
    ], cv, "E")
    return cv.done()


def icons():
    return {
        "DazedPipeSection": pipe_section(),
        "DazedValve": valve(),
        "DazedPumpHand": m.hand_pump("S", 3.5),
        "DazedPumpElectric": m.electric_pump("S", OUT),
        "DazedPurifier": m.purifier("S", OUT),
        "DazedPurifierFilter": filter_cartridge(),
        "DazedDownspout": m.downspout("S", 2.2),
    }


def build():
    made = icons()
    for name, cell in made.items():
        fit(cell).save(TEX / ("Item_%s.png" % name))
    return list(made)


def preview(out):
    names = build()
    sheet = Image.new("RGBA", (len(names) * 140, 160), (88, 98, 80, 255))
    for i, n in enumerate(names):
        sheet.alpha_composite(Image.open(TEX / ("Item_%s.png" % n)).resize((128, 128), Image.NEAREST), (i * 140 + 6, 16))
    sheet.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    if a.preview: preview(a.preview)
    else: print(build())
