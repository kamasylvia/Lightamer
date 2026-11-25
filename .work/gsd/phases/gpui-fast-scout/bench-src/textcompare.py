#!/usr/bin/env python3
"""Build the T6 text comparison: crop the text block from two 2x window
screenshots and stack pre above fast with labels.

usage: textcompare.py <pre.png> <fast.png> <out.png> [x y w h]
Crop box is in 2x device pixels of the window capture.
"""
import sys
from PIL import Image, ImageDraw

pre, fast, out = sys.argv[1:4]
box = tuple(int(v) for v in sys.argv[4:8]) if len(sys.argv) >= 8 else (70, 90, 1150, 560)

a = Image.open(pre).convert("RGB")
b = Image.open(fast).convert("RGB")
print("pre", a.size, "fast", b.size)
ca = a.crop(box)
cb = b.crop(box)
label = 34
W = box[2]
H = box[3]
canvas = Image.new("RGB", (W, H * 2 + label * 2 + 12), (18, 18, 18))
d = ImageDraw.Draw(canvas)
d.text((8, 4), "pre  (gpui-pre 0.3.14)", fill=(255, 220, 120))
canvas.paste(ca, (0, label))
d.text((8, label + H + 8), "fast (gpui-fast 0.1.19)", fill=(120, 220, 255))
canvas.paste(cb, (0, label + H + label + 12))
canvas.save(out)
print("wrote", out, canvas.size)
