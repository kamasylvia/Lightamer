#!/usr/bin/env python3
"""Self-proof: correlate a darktable ready frame's image area with the RAW's embedded JPEG.

Usage: verify.py <first.png> <ready.png> <sample-basename-no-ext>
Prints Pearson r (grayscale, 256px) between the changed region of ready vs first and the embedded preview.
"""
import sys, numpy as np
from PIL import Image

def changed_bbox(a, b):
    g = np.abs(a.astype(np.int16) - b.astype(np.int16)).mean(axis=2)
    mask = g > 8
    rows = np.where(mask.sum(axis=1) > mask.shape[1] * 0.15)[0]
    cols = np.where(mask.sum(axis=0) > mask.shape[0] * 0.15)[0]
    if len(rows) < 5 or len(cols) < 5:
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1]), int(rows[-1])

def prep(im, size=256):
    im = im.convert('L').resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(np.float64)
    a -= a.mean()
    return a

def corr(a, b):
    va = a.ravel(); vb = b.ravel()
    d = (va.std() * vb.std())
    return float((va * vb).mean() / d) if d else 0.0

if __name__ == '__main__':
    first = Image.open(sys.argv[1]).convert('RGB')
    ready = Image.open(sys.argv[2]).convert('RGB')
    base = sys.argv[3]
    box = changed_bbox(np.asarray(first), np.asarray(ready))
    if not box:
        print('NO_VIEWPORT_CHANGE'); sys.exit(1)
    x0, y0, x1, y1 = box
    crop = ready.crop((x0, y0, x1 + 1, y1 + 1))
    import os
    d = '/Users/Shared/lightamer-gui-test/darktable/samples'
    for cand in (f'{base}-preview2.jpg', f'{base}-preview4.jpg', f'{base}-preview2.tif'):
        if os.path.exists(os.path.join(d, cand)):
            prev = Image.open(os.path.join(d, cand)); break
    else:
        print('NO_PREVIEW'); sys.exit(1)
    print('frame', ready.size, 'bbox', (x0, y0, x1, y1), 'crop', crop.size, 'preview', prev.size)
    print('corr=%.4f' % corr(prep(crop), prep(prev)))
