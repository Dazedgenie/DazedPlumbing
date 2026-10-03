"""Placeholder sprites for the fuel pumps (dazedplumb_01_236..243: hand E S W N, then electric E S W N), their icons and tiles.

Usage:  python3 tools/fuelpump_art.py [--preview out.png]
Needs Pillow. A red petrol-pump column drawn with machine_art's isometric boxes so it lines up with the pipes: the hand
build has a crank on its side, the electric one a yellow cap and a terminal box. Blender renders replace these later.
Run `python3 tools/pack_tiles.py grow --rows 31` first; this script then adds the sprites, the two icons and the tile properties.
"""
import sys, argparse
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "pzformat"))
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))
from machine_art import Canvas, parts_draw, STEEL, DARK, LIGHT  # noqa: E402
from pipe_art import CW, CH, PACK, repack  # noqa: E402
import pack_tiles  # noqa: E402

BASE = 236
FACINGS = ("E", "S", "W", "N")
RED = (196, 52, 46)
PANEL = (232, 232, 226)
HOSE = (36, 38, 44)
YELLOW = (216, 186, 60)
TEX = HERE.parent / "common/media/textures"


def pump_body(facing, electric, outline=1.2):
    cv = Canvas(outline); cv.shadow(0.8)
    parts = [
        (-0.5, 0.5, -0.5, 0.5, 0, 6, (150, 150, 156)),             # base slab
        (-0.38, 0.38, -0.38, 0.38, 6, 84, RED),                    # the column
        (-0.42, 0.42, -0.42, 0.42, 84, 92, DARK),                  # head cap
        (0.38, 0.42, -0.26, 0.26, 52, 76, PANEL),                  # price panel on the facing side
        (0.38, 0.44, -0.2, 0.2, 58, 68, (28, 30, 36)),             # its display
        (0.4, 0.58, -0.1, 0.1, 30, 36, HOSE),                      # hose leaving the column
        (0.5, 0.64, -0.06, 0.06, 20, 36, STEEL),                   # nozzle hanging on its holster
        (-1.0, -0.38, -0.14, 0.14, 14, 26, DARK),                  # inlet pipe on the back
    ]
    if electric:
        parts += [(-0.44, 0.44, -0.44, 0.44, 92, 98, YELLOW),      # yellow cap
                  (-0.2, 0.2, -0.2, 0.2, 98, 106, DARK)]           # terminal box
    else:
        parts += [(-0.1, 0.1, -0.7, -0.38, 60, 66, LIGHT),         # crank arm out of the side
                  (-0.1, 0.1, -0.72, -0.62, 40, 66, STEEL)]        # its handle
    parts_draw(parts, cv, facing)
    return cv.done()


def icon(electric):
    return fit_icon(pump_body("S", electric, 5.0))


def fit_icon(cell):
    cell = cell.crop(cell.getbbox())
    cell.thumbnail((30, 30), Image.LANCZOS)
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(cell, ((32 - cell.width) // 2, 31 - cell.height if cell.height < 28 else (32 - cell.height) // 2))
    return out


def cells():
    out = {}
    for k, electric in enumerate((False, True)):
        for i, f in enumerate(FACINGS):
            out[BASE + k * 4 + i] = pump_body(f, electric)
    return out


def tiles():
    """Tile properties for 236..243, copied from the water pumps (176..183) with new names, items and weights."""
    td = pack_tiles.load()
    ts = td.tilesets[0]
    spec = (("Hand Fuel Pump", "Base.DazedFuelPumpHand", 176, "160"), ("Electric Fuel Pump", "Base.DazedFuelPumpElectric", 180, "220"))
    for k, (name, item, src, weight) in enumerate(spec):
        for i in range(4):
            props = dict(ts.tiles[src + i].props)
            props.update({"CustomName": name, "CustomItem": item, "PickUpWeight": weight})
            ts.tiles[BASE + k * 4 + i] = type(ts.tiles[src + i])(props)
    pack_tiles.save(td)


def build():
    TEX.mkdir(exist_ok=True)
    icon(False).save(TEX / "Item_DazedFuelPumpHand.png")
    icon(True).save(TEX / "Item_DazedFuelPumpElectric.png")
    page = repack(PACK, cells())
    tiles()
    return page


def preview(out):
    sheet = Image.new("RGBA", (CW * 8, CH), (88, 98, 80, 255))
    for n, cell in sorted(cells().items()):
        sheet.alpha_composite(cell, ((n - BASE) * CW, 0))
    sheet.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    print("page", build())
    if a.preview: preview(a.preview)
