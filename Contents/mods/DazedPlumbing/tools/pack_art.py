"""Drop rendered cells (128x256, or 2x renders at 256x512, named by sprite index) into dazedplumbing.pack.

A tank piece may come with <index>_m.png, a mask of what stands on its own square: the piece keeps only that.

    python3 tools/pack_art.py <cells dir> [<cells dir> ...]
Each cell is trimmed to its content and the whole page is shelf-packed again; sprites not given keep
their current art. tools/pzformat/packfile.py is from pz-sprite-forge (MIT).
"""
import io, sys
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "pzformat"))                      # a local copy, if any
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))   # the shared copy in Dazed Core
from packfile import TexturePack, PackEntry  # noqa: E402

PACK = HERE.parent / "common/media/texturepacks/dazedplumbing.pack"
CW, CH, PAGE_W = 128, 256, 2048


def shrink(im):
    """Halve a 2x render with premultiplied alpha (no dark fringes), then sharpen lightly."""
    small = im.convert("RGBa").resize((CW, CH), Image.LANCZOS)
    small = small.filter(ImageFilter.UnsharpMask(radius=0.8, percent=70, threshold=1))
    return small.convert("RGBA")


def load(p):
    """A cell, cut to its own square by its mask when it has one, then shrunk to 128x256."""
    im = Image.open(p).convert("RGBA")
    m = p.with_name(p.stem + "_m.png")
    if m.exists():                                    # PNG alpha is straight, so the mask's red is the share
        keep = Image.open(m).convert("RGBA").getchannel("R")
        # grow the mask a pixel past the cut: two pieces' complementary anti-aliased edges, drawn one over the
        # other, leave a hairline of floor showing through; overlapping them closes it (same surface both sides)
        keep = keep.filter(ImageFilter.MaxFilter(3))
        im.putalpha(ImageChops.multiply(im.getchannel("A"), keep))
    if im.size == (CW * 2, CH * 2):
        im = shrink(im)
    return im


def repack(cells, pack_path=PACK):
    """Replace (or add) sprites by index; returns the page size."""
    pk = TexturePack.read(pack_path)
    page = pk.pages[0]
    old = Image.open(io.BytesIO(page.png)).convert("RGBA")
    stem = page.entries[0].name.rsplit("_", 1)[0]
    sprites = []
    for e in page.entries:
        n = int(e.name.rsplit("_", 1)[1])
        if n not in cells:
            sprites.append((e, old.crop((e.x, e.y, e.x + e.w, e.y + e.h))))
    for n in sorted(cells):
        cell = cells[n]
        bb = cell.getbbox()
        sprites.append((PackEntry("%s_%d" % (stem, n), 0, 0, bb[2] - bb[0], bb[3] - bb[1], bb[0], bb[1], CW, CH),
                        cell.crop(bb)))
    sprites.sort(key=lambda s: int(s[0].name.rsplit("_", 1)[1]))
    order = sorted(range(len(sprites)), key=lambda i: -sprites[i][0].h)
    x = y = shelf = 0
    pos = {}
    for i in order:
        e = sprites[i][0]
        if x + e.w + 2 > PAGE_W:
            x, y, shelf = 0, y + shelf + 2, 0
        pos[i] = (x, y)
        x += e.w + 2
        shelf = max(shelf, e.h)
    height = 1
    while height < y + shelf: height *= 2
    sheet = Image.new("RGBA", (PAGE_W, height), (0, 0, 0, 0))
    for i, (e, im) in enumerate(sprites):
        e.x, e.y = pos[i]
        sheet.paste(im, pos[i])
    buf = io.BytesIO(); sheet.save(buf, "PNG")
    page.png = buf.getvalue()
    page.entries = [e for e, _ in sprites]
    pk.write(pack_path)
    return sheet.size


if __name__ == "__main__":
    cells = {}
    for d in sys.argv[1:]:
        for p in Path(d).glob("*.png"):
            if p.stem.isdigit():
                im = load(p)
                if im.size != (CW, CH): sys.exit("%s is %s, not 128x256 (or 256x512)" % (p, im.size))
                cells[int(p.stem)] = im
    print("replacing %d sprites; page %s" % (len(cells), repack(cells)))
