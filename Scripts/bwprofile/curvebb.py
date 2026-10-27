import sys
import pdfplumber
src, pageno = sys.argv[1], int(sys.argv[2])
with pdfplumber.open(src) as pdf:
    page = pdf.pages[pageno - 1]
    for i, c in enumerate(page.curves):
        pts = c.get("pts") or []
        if not pts:
            continue
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        n = len(pts)
        stroked = c.get("stroke", False)
        print(f"curve{i}: n={n} x[{min(xs):.0f},{max(xs):.0f}] y[{min(ys):.0f},{max(ys):.0f}] stroke={stroked} w={c.get('linewidth')}")
