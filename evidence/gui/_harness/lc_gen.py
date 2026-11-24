#!/usr/bin/env python3
"""Generate N unique JPEGs for the LightCraft M3 batch test, and lay out the nested batch dirs.

Files are one base image plus a unique trailer, so every file's bytes (content hash) differ while
the image is the same: the library's content-hash dedupe keeps all N.
"""
import os, shutil, sys
import numpy as np
from PIL import Image

G = '/Users/Shared/lightamer-gui-test'
A = G + '/lightcraft'
B = A + '/batch'
N = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
OUT = B + '/n10000'
W, H = 1024, 683


def base_jpeg(path):
    rng = np.random.default_rng(7)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    img = np.stack([
        40 + 180 * x / W + 30 * np.sin(y / 40),
        40 + 180 * y / H + 20 * np.cos(x / 55),
        60 + 120 * (1 - x / W) + 40 * np.sin((x + y) / 70),
    ], axis=-1)
    img += rng.normal(0, 6, img.shape)
    img = np.clip(img, 0, 255).astype(np.uint8)
    Image.fromarray(img, 'RGB').save(path, 'JPEG', quality=72, optimize=False)


def main():
    os.makedirs(OUT, exist_ok=True)
    base = OUT + '/base.jpg'
    if not os.path.exists(base):
        base_jpeg(base)
    data = open(base, 'rb').read()
    for i in range(1, N + 1):
        p = f'{OUT}/img{i:05d}.jpg'
        if os.path.exists(p):
            continue
        with open(p, 'wb') as f:
            f.write(data)
            f.write(b'\nLCTEST%08d\n' % i)   # unique bytes after EOI; decoders ignore them
    for n, d in ((100, B + '/n100'), (1000, B + '/n1000')):
        os.makedirs(d, exist_ok=True)
        for i in range(1, n + 1):
            src = f'{OUT}/img{i:05d}.jpg'
            dst = f'{d}/img{i:05d}.jpg'
            if not os.path.exists(dst):
                os.link(src, dst)
    print('files', N, 'base bytes', len(data))


if __name__ == '__main__':
    main()
