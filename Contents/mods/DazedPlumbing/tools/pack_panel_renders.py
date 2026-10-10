"""Pack the Main Water Panel's Blender renders into the mod (never draws placeholders; that is tools/panel_art.py).

    python3 tools/pack_panel_renders.py --renders <out dir> [--dry-run]

<out dir> is the out/ folder both Blender scripts wrote to:
    board/*.png                   tools/blender/board_render.py  -> common/media/ui/DazedPlumbing/Board/*.png (as rendered, 2x)
    wallpanel/256..259.png        dup_render.py family wallpanel -> sprites 256-259 of dazedplumbing.pack (E, S, W, N)
    icons/DazedWaterPanel.png     dup_render.py family icons     -> common/media/textures/Item_DazedWaterPanel.png
Whatever is present is packed; a missing group is skipped. Tiles 256-259 get their properties again (panel_art.tiles(),
the same ones), `pack_tiles.py check` runs, and media/ui/DazedPlumbing/Board/.rendered records what was packed, which
stops panel_art.py from overwriting the renders. --dry-run reads and checks everything and writes nothing.
"""
import argparse, shutil, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
MEDIA = MOD / "common/media"
BOARD_DIR = MEDIA / "ui/DazedPlumbing/Board"
MARKER = BOARD_DIR / ".rendered"
ICON = MEDIA / "textures/Item_DazedWaterPanel.png"
BASE, FACINGS = 256, ("E", "S", "W", "N")                  # DUP_WallPanels.BASE and FACINGS
# The parts DUP_BoardLayout looks for in Plumbing's folder, at their 2x render sizes.
BOARD_PARTS = {"tank_column": (120, 340), "knob": (72, 72), "wheel_open": (184, 184), "wheel_turned": (184, 184)}
# Where the core's pzformat may be: beside this repo in a Workshop folder or a checkout (pack_tiles also looks).
for cand in (MOD.parents[3] / "DazedCore/Contents/mods/DazedCore/tools/pzformat",
             MOD.parents[3] / "dazedcore/Contents/mods/DazedCore/tools/pzformat"):
    if cand.is_dir():
        sys.path.insert(0, str(cand))
sys.path.insert(0, str(HERE))


def find(renders):
    """What the renders folder holds: (board {name: path}, cells {index: path}, icon path or None, problems)."""
    from PIL import Image
    problems = []
    board = {}
    bdir = renders / "board"
    for p in sorted(bdir.glob("*.png")) if bdir.is_dir() else []:
        want = BOARD_PARTS.get(p.stem)
        if want is None:
            print("note: board/%s is not a part Board.tex looks for in Plumbing's folder; copying it anyway" % p.name)
        else:
            size = Image.open(p).size
            if size != want:
                problems.append("board/%s is %dx%d, not %dx%d (render at 2x)" % (p.name, size[0], size[1], want[0], want[1]))
        board[p.stem] = p
    if board:
        for name in BOARD_PARTS:
            if name not in board:
                print("note: board/%s.png missing; the board keeps drawing that part" % name)
    cells = {}
    wdir = renders / "wallpanel"
    for i in range(len(FACINGS)):
        p = wdir / ("%d.png" % (BASE + i))
        if p.exists():
            size = Image.open(p).size
            if size not in ((128, 256), (256, 512)):
                problems.append("wallpanel/%s is %dx%d, not 256x512 (or 128x256)" % (p.name, size[0], size[1]))
            cells[BASE + i] = p
    if cells and len(cells) != len(FACINGS):
        problems.append("wallpanel/ has %s; all four facings (256-259) are needed" % sorted(cells))
    icon = renders / "icons/DazedWaterPanel.png"
    return board, cells, (icon if icon.exists() else None), problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--renders", required=True, type=Path, help="the out/ folder of board_render.py and dup_render.py")
    ap.add_argument("--dry-run", action="store_true", help="read and check, write nothing")
    a = ap.parse_args(argv)
    renders = a.renders.expanduser().resolve()
    if not renders.is_dir():
        sys.exit("no such folder: %s" % renders)
    board, cells, icon, problems = find(renders)
    say = "would " if a.dry_run else ""
    print("renders: %s\nmod:     %s" % (renders, MOD))
    print("board parts: %s" % (", ".join(sorted(board)) or "none"))
    print("wall panel sprites: %s" % (", ".join("%d (%s)" % (n, FACINGS[n - BASE]) for n in sorted(cells)) or "none"))
    print("icon: %s" % (icon.name if icon else "none"))
    for p in problems:
        print("PROBLEM:", p)
    if problems:
        return 1
    if not (board or cells or icon):
        print("nothing to pack in %s (expected board/, wallpanel/ or icons/DazedWaterPanel.png)" % renders)
        return 0 if a.dry_run else 1

    for name, p in sorted(board.items()):
        print("%scopy %s -> %s" % (say, p.name, (BOARD_DIR / p.name).relative_to(MOD)))
    if cells:
        print("%spack sprites %d-%d into %s and set their tile properties" % (say, BASE, BASE + 3, "texturepacks/dazedplumbing.pack"))
    if icon:
        print("%swrite %s" % (say, ICON.relative_to(MOD)))
    print("%swrite %s" % (say, MARKER.relative_to(MOD)))
    if a.dry_run:
        print("dry run: nothing written")
        return 0

    if board:
        BOARD_DIR.mkdir(parents=True, exist_ok=True)
        for p in board.values():
            shutil.copyfile(p, BOARD_DIR / p.name)
    if cells:
        import pack_art, panel_art                                 # panel_art only for tiles(): no placeholder art
        loaded = {n: pack_art.load(p) for n, p in cells.items()}
        panel_art.tiles()
        print("page", pack_art.repack(loaded))
    if icon:
        import make_icons
        from PIL import Image
        make_icons.fit(Image.open(icon).convert("RGBA")).save(ICON)
    BOARD_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["Blender renders packed by tools/pack_panel_renders.py on %s; tools/panel_art.py will not overwrite them"
             " without --force." % time.strftime("%Y-%m-%d %H:%M")]
    lines += ["board %s.png" % n for n in sorted(board)]
    lines += ["sprite %d %s" % (n, FACINGS[n - BASE]) for n in sorted(cells)]
    if icon:
        lines.append("icon Item_DazedWaterPanel.png")
    old = MARKER.read_text(encoding="utf-8").splitlines()[1:] if MARKER.exists() else []
    MARKER.write_text("\n".join(lines[:1] + sorted(set(old) | set(lines[1:]))) + "\n", encoding="utf-8")
    import pack_tiles
    return 0 if pack_tiles.check() else 1


if __name__ == "__main__":
    sys.exit(main())
