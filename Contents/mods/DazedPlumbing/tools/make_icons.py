"""Inventory icons (32x32) from the Blender icon renders (dup_render.py, family "icons").

    python3 tools/make_icons.py <icon renders dir>
Each render is named by its item's Icon (DazedPumpHand.png -> textures/Item_DazedPumpHand.png).
"""
import sys
from pathlib import Path
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
TEX = HERE.parent / "common/media/textures"


def fit(im):
    """Trim, shrink with premultiplied alpha to fit 30x30, sharpen a touch and centre on 32x32."""
    im = im.crop(im.getbbox()).convert("RGBa")
    im.thumbnail((30, 30), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1)).convert("RGBA")
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(im, ((32 - im.width) // 2, (32 - im.height) // 2))
    return out


def main(renders):
    made = 0
    for p in sorted(Path(renders).glob("*.png")):
        fit(Image.open(p).convert("RGBA")).save(TEX / ("Item_%s.png" % p.stem))
        made += 1
    print("%d icons" % made)


if __name__ == "__main__":
    main(sys.argv[1])
