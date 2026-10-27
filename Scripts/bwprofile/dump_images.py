import sys
from pathlib import Path
import pdfplumber

src, outdir = sys.argv[1], Path(sys.argv[2])
outdir.mkdir(parents=True, exist_ok=True)
with pdfplumber.open(src) as pdf:
    for i, page in enumerate(pdf.pages):
        for j, img in enumerate(page.images):
            bbox = (img["x0"], img["top"], img["x1"], img["bottom"])
            w, h = bbox[2]-bbox[0], bbox[3]-bbox[1]
            if w < 40 or h < 40:
                continue
            cropped = page.crop(bbox).to_image(resolution=300)
            cropped.save(outdir / f"p{i+1}_img{j}_{int(w)}x{int(h)}.png")
            print(f"p{i+1} img{j}: bbox={tuple(round(v,1) for v in bbox)} {w:.0f}x{h:.0f}pt")
