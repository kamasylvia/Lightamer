import sys
from pathlib import Path
import pdfplumber
src, outdir, res = sys.argv[1], Path(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 200
outdir.mkdir(parents=True, exist_ok=True)
with pdfplumber.open(src) as pdf:
    for i, page in enumerate(pdf.pages):
        page.to_image(resolution=res).save(outdir / f"page{i+1}.png")
        print(f"page{i+1}: {page.width:.0f}x{page.height:.0f}pt -> {res}dpi")
