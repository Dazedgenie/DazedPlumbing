"""Placeholder sprites for the biogas digester (dazedplumb_01_244..247, facings E S W N), its icon and tiles; run `python3 tools/digester_art.py [--preview out.png]`.
The sheet already has 248 tiles, so no `pack_tiles.py grow` is needed first."""
import sys, argparse
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "pzformat"))
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))
from machine_art import Canvas, parts_draw, STEEL, DARK, LIGHT, STONE  # noqa: E402
from pipe_art import CW, CH, PACK, repack  # noqa: E402
import pack_tiles  # noqa: E402

BASE = 244
FACINGS = ("E", "S", "W", "N")
DRUM = (70, 112, 74)
DOME = (196, 204, 150)
HATCH = (150, 112, 58)
TEX = HERE.parent / "common/media/textures"


def digester(facing, outline=1.2):
    cv = Canvas(outline); cv.shadow(0.85)
    parts_draw([
        (-0.55, 0.55, -0.55, 0.55, 0, 6, STONE),                  # base slab
        (-0.45, 0.45, -0.45, 0.45, 6, 70, DRUM),                  # the drum
        (-0.47, 0.47, -0.47, 0.47, 38, 42, DARK),                 # a hoop around it
        (-0.47, 0.47, -0.47, 0.47, 66, 72, STEEL),                # its rim
        (-0.3, 0.3, -0.3, 0.3, 72, 92, DOME),                     # gas-holder dome
        (-0.12, 0.12, -0.12, 0.12, 92, 100, DARK),                # gas cock on top
        (0.45, 0.58, -0.22, 0.22, 36, 58, HATCH),                 # feed hatch on the facing side
        (0.56, 0.6, -0.14, 0.14, 44, 50, LIGHT),                  # its handle
        (-1.0, -0.45, -0.12, 0.12, 14, 26, LIGHT),                # gas outlet stub on the back
    ], cv, facing)
    return cv.done()


def icon():
    cell = digester("S", 5.0)
    cell = cell.crop(cell.getbbox())
    cell.thumbnail((30, 30), Image.LANCZOS)
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(cell, ((32 - cell.width) // 2, 31 - cell.height if cell.height < 28 else (32 - cell.height) // 2))
    return out


def cells():
    return {BASE + i: digester(f) for i, f in enumerate(FACINGS)}


def tiles():
    """Tile properties for 244..247, copied from the hand water pump (176..179) with a new name, item and weight."""
    td = pack_tiles.load()
    ts = td.tilesets[0]
    for i in range(4):
        props = dict(ts.tiles[176 + i].props)
        props.update({"CustomName": "Biogas Digester", "CustomItem": "Base.DazedDigester", "PickUpWeight": "280"})
        ts.tiles[BASE + i] = type(ts.tiles[176 + i])(props)
    pack_tiles.save(td)


def build():
    TEX.mkdir(exist_ok=True)
    icon().save(TEX / "Item_DazedDigester.png")
    page = repack(PACK, cells())
    tiles()
    return page


def preview(out):
    sheet = Image.new("RGBA", (CW * 4, CH), (88, 98, 80, 255))
    for n, cell in sorted(cells().items()):
        sheet.alpha_composite(cell, ((n - BASE) * CW, 0))
    sheet.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    print("page", build())
    if a.preview: preview(a.preview)
