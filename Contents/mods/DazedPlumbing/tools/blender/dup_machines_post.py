"""Grade and shrink dup_machines_render.py output exactly like DazedPower (tools/grade_all.py + tools/import_art.py).

    python3 dup_machines_post.py <render out dir> <final dir>
<render out>/cells/<index>.png (256x512) -> <final>/cells/<index>.png (128x256)
<render out>/icons/Item_*.png (256x256)  -> <final>/icons/Item_*.png (32x32)
"""
import sys
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter

CW, CH = 128, 256
SHADOW = 0.85                                    # strength of the contact shadow pass


def grade(im):                                   # grade_all.py
    a = im.getchannel("A")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(im.convert("RGB")).enhance(0.86)).enhance(0.94)
    rgb = Image.merge("RGB", [c.point(lambda v, k=k: min(255, int(v * k))) for c, k in zip(rgb.split(), (1.02, 1.0, 0.95))])
    out = rgb.convert("RGBA"); out.putalpha(a); return out


def shrink(im):                                  # import_art.py
    small = im.convert("RGBa").resize((CW, CH), Image.LANCZOS)
    small = small.filter(ImageFilter.UnsharpMask(radius=0.8, percent=70, threshold=1))
    return small.convert("RGBA")


def icon(im):                                    # import_art.py
    im = im.crop(im.getbbox()).convert("RGBa")
    im.thumbnail((30, 30), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1)).convert("RGBA")
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(im, ((32 - im.width) // 2, (32 - im.height) // 2))
    return out


def main(src, dst):
    src, dst = Path(src), Path(dst)
    (dst / "cells").mkdir(parents=True, exist_ok=True); (dst / "icons").mkdir(parents=True, exist_ok=True)
    n = 0
    for p in sorted((src / "cells").glob("*.png")):
        if not p.stem.isdigit(): continue
        im = grade(Image.open(p).convert("RGBA"))
        sp = p.with_name(p.stem + "_s.png")                     # contact shadow pass: laid under the machine
        if sp.exists():
            sh = Image.open(sp).convert("RGBA")
            a = sh.getchannel("A")
            vals = sorted(v for v in (a.get_flattened_data() if hasattr(a, "get_flattened_data") else a.getdata()) if v > 0)
            base = vals[len(vals) // 2] + 6 if vals else 0       # the catcher's flat sky-fill darkening: drop it,
            a = a.point(lambda v: max(0, min(255, int((v - base) * 255 / max(1, 255 - base) * SHADOW))))  # keep the contact
            sh = Image.new("RGBA", sh.size, (24, 22, 18, 0)); sh.putalpha(a)
            sh.alpha_composite(im); im = sh
        shrink(im).save(dst / "cells" / p.name); n += 1
    for p in sorted((src / "icons").glob("*.png")):
        icon(grade(Image.open(p).convert("RGBA"))).save(dst / "icons" / p.name); n += 1
    print(n, "files")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
