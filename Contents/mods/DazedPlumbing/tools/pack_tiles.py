"""Check and grow the mod's tile sheet: dazedplumbing_tiles.tiles (+ .tiles.txt) and the texture pack.

    python3 tools/pack_tiles.py check            # do the tile definitions, the pack and the Lua agree?
    python3 tools/pack_tiles.py grow --rows 26   # make room for new sprites (existing indices never move)

Sprite N lives at row N // cols, column N % cols, so growing only ever adds rows at the end. To add art,
draw cells with a script like tools/machine_art.py (pipe_art.repack adds new indices to the pack), give
the new tiles properties here (see add_tile), then bump the constants in the Lua. Saved worlds remember
sprite names, so never renumber. The tile files are read and written with tools/pzformat/tiledef.py, which
round-trips the game's own files byte for byte (and ours: `check` proves it).
"""
import argparse, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "pzformat"))                      # a local copy, if any
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))   # the shared copy in Dazed Core
from tiledef import TileDefinitions, Tile  # noqa: E402
from packfile import TexturePack  # noqa: E402

MEDIA = HERE.parent / "common/media"
TILES = MEDIA / "dazedplumbing_tiles.tiles"
TXT = MEDIA / "dazedplumbing_tiles.tiles.txt"
PACK = MEDIA / "texturepacks/dazedplumbing.pack"


def load():
    return TileDefinitions.read(TILES)


def save(td):
    td.write(TILES)
    TXT.write_text(td.to_text(), encoding="utf-8")


def pack_indices():
    page = TexturePack.read(PACK).pages[0]
    return {int(e.name.rsplit("_", 1)[1]) for e in page.entries}, page.name


def check():
    problems = []
    raw = TILES.read_bytes()
    td = TileDefinitions.read(TILES)
    if td.dumps() != raw: problems.append("the .tiles file does not round-trip byte for byte")
    if td.to_text() != TXT.read_text(encoding="utf-8"): problems.append(".tiles.txt is out of step with the .tiles file")
    ts = td.tilesets[0]
    have, page = pack_indices()
    for i, t in enumerate(ts.tiles):
        if not t.empty and i not in have: problems.append("tile %d has properties but no sprite in the pack" % i)
    for n in sorted(have):
        if n >= len(ts.tiles): problems.append("pack sprite %d is outside the %dx%d grid" % (n, ts.cols, ts.rows))
    items = set(re.findall(r"item\s+(\w+)", (MEDIA / "scripts/dup_items.txt").read_text()))
    for i, t in enumerate(ts.tiles):
        ci = t.props.get("CustomItem", "")
        if ci and ci.split(".")[-1] not in items: problems.append("tile %d names item %s that no script defines" % (i, ci))
    filled = [i for i, t in enumerate(ts.tiles) if not t.empty]
    print("tileset %s: %dx%d = %d tiles, %d with properties, %d sprites in the pack (page %s)" % (
        ts.name, ts.cols, ts.rows, len(ts.tiles), len(filled), len(have), page))
    for p in problems: print("PROBLEM:", p)
    if not problems: print("ok")
    return not problems


def grow(rows):
    td = load()
    ts = td.tilesets[0]
    if rows <= ts.rows: sys.exit("already %d rows; nothing to do" % ts.rows)
    ts.tiles.extend(Tile() for _ in range((rows - ts.rows) * ts.cols))
    ts.rows = rows
    save(td)
    print("grown to %dx%d (%d tiles)" % (ts.cols, ts.rows, len(ts.tiles)))


def add_tile(index, props):
    """Give tile `index` its properties (copy a similar tile's and change what differs)."""
    td = load()
    td.tilesets[0].tiles[index] = Tile(dict(props))
    save(td)


def set_prop(indices, key, value=""):
    """Give every tile in `indices` the property `key` (value '' is a flag); returns how many changed."""
    td = load()
    tiles = td.tilesets[0].tiles
    n = 0
    for i in indices:
        if not tiles[i].empty and tiles[i].props.get(key) != value:
            tiles[i].props[key] = value
            n += 1
    save(td)
    return n


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    g = sub.add_parser("grow"); g.add_argument("--rows", type=int, required=True)
    a = ap.parse_args()
    if a.cmd == "check": sys.exit(0 if check() else 1)
    if a.cmd == "grow": grow(a.rows)
