import sys
import pdfplumber
src, pageno, idx = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with pdfplumber.open(src) as pdf:
    page = pdf.pages[pageno - 1]
    c = page.curves[idx]
    pts = c.get("pts") or []
    print(f"curve{idx}: {len(pts)} pts, stroke={c.get('stroke')} colorish keys={[k for k in c.keys() if 'stroking' in k or 'color' in k]}")
    stroking = c.get("stroking_color")
    print("stroking_color:", stroking)
    for p in pts[::max(1, len(pts)//25)]:
        print(f"  ({p[0]:.1f}, {p[1]:.1f})")
