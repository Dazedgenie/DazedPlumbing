"""Apply the new style's colour grade to every render (masks untouched), mirroring the folder layout."""
import sys
from pathlib import Path
from PIL import Image, ImageEnhance
src, dst = Path(sys.argv[1]), Path(sys.argv[2])


def grade(im):
    a = im.getchannel("A")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(im.convert("RGB")).enhance(0.86)).enhance(0.94)
    rgb = Image.merge("RGB", [c.point(lambda v, k=k: min(255, int(v * k))) for c, k in zip(rgb.split(), (1.02, 1.0, 0.95))])
    out = rgb.convert("RGBA"); out.putalpha(a); return out


n = 0
for p in src.rglob("*.png"):
    q = dst / p.relative_to(src); q.parent.mkdir(parents=True, exist_ok=True)
    im = Image.open(p).convert("RGBA")
    (im if p.stem.endswith("_m") else grade(im)).save(q); n += 1
print(n, "files")
