import sys
from pathlib import Path
from PIL import Image
import numpy as np

for p in sorted(Path(sys.argv[1]).glob("*.png")):
    im = np.asarray(Image.open(p).convert("RGB")).astype(int)
    h, w, _ = im.shape
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    dark = (r < 120) & (g < 120) & (b < 120)
    reddish = (r > 130) & (r - g > 50) & (r - b > 50)
    bluish = (b > 130) & (b - r > 40) & (b - g > 30)
    greenish = (g > 120) & (g - r > 40) & (g - b > 40)
    print(f"{p.name}: {w}x{h} dark={dark.sum()} red={reddish.sum()} blue={bluish.sum()} green={greenish.sum()}")
