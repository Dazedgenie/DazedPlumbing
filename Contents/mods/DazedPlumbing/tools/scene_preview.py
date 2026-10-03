"""Compose rendered cells into a small isometric scene, the way the game draws them, to check the art.

    python3 tools/scene_preview.py <cells dir> <out.png> <spec>
spec: "index@gx,gy;index@gx,gy;..." drawn back to front by (gx + gy).
"""
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pack_art import load  # noqa: E402


def main(cells, out, spec, W=1200, H=700, ox=520, oy=180):
    items = []
    for part in spec.split(";"):
        idx, at = part.split("@")
        gx, gy = (int(v) for v in at.split(","))
        items.append((gx + gy, gx, gy, int(idx)))
    canvas = Image.new("RGBA", (W, H), (96, 104, 84, 255))
    for gx in range(-2, 12):                                   # a faint floor grid
        for gy in range(-2, 12):
            sx, sy = ox + (gx - gy) * 64, oy + (gx + gy) * 32
            tile = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
            from PIL import ImageDraw
            ImageDraw.Draw(tile).polygon([(64, 0), (127, 32), (64, 63), (0, 32)], outline=(80, 88, 70, 255))
            canvas.alpha_composite(tile, (sx - 64, sy - 32))
    for _, gx, gy, idx in sorted(items):
        p = Path(cells) / ("%d.png" % idx)
        if not p.exists():
            for d in Path(cells).parent.iterdir():
                if (d / ("%d.png" % idx)).exists(): p = d / ("%d.png" % idx)
        cell = load(p)
        sx, sy = ox + (gx - gy) * 64, oy + (gx + gy) * 32
        canvas.alpha_composite(cell, (sx - 64, sy - 224))
    canvas.save(out)


if __name__ == "__main__":
    main(*sys.argv[1:4])
