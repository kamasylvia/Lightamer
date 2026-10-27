import sys
import pdfplumber

path = sys.argv[1]
with pdfplumber.open(path) as pdf:
    print(f"{path}: {len(pdf.pages)} pages")
    for i, page in enumerate(pdf.pages):
        text = (page.extract_text() or "")[:200].replace("\n", " | ")
        ncurves = len(page.curves) if page.curves else 0
        nlines = len(page.lines) if page.lines else 0
        nrects = len(page.rects) if page.rects else 0
        nimgs = len(page.images) if page.images else 0
        print(f"  p{i+1}: curves={ncurves} lines={nlines} rects={nrects} images={nimgs} :: {text[:150]}")
