"""Compose side-by-side comparison images (darktable | gpui prototype)."""

import sys
from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Helvetica.ttc"


def load(path, width):
    im = Image.open(path).convert("RGB")
    h = round(im.height * width / im.width)
    return im.resize((width, h), Image.LANCZOS)


def compose(left_path, right_path, out_path, label_l="darktable 5.6.2", label_r="gpui prototype"):
    width = 900
    a = load(left_path, width)
    b = load(right_path, width)
    height = max(a.height, b.height)
    gutter = 16
    header = 30
    canvas = Image.new("RGB", (width * 2 + gutter, height + header), (24, 24, 24))
    canvas.paste(a, (0, header))
    canvas.paste(b, (width + gutter, header))
    d = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype(FONT, 18)
    except Exception:
        font = ImageFont.load_default()
    d.text((8, 6), label_l, fill=(240, 240, 240), font=font)
    d.text((width + gutter + 8, 6), label_r, fill=(240, 240, 240), font=font)
    canvas.save(out_path, quality=90, optimize=True)
    print(out_path, canvas.size)


if __name__ == "__main__":
    compose(*sys.argv[1:5])
