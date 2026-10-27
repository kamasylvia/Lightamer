import sys
import pdfplumber

src, pageno = sys.argv[1], int(sys.argv[2])
with pdfplumber.open(src) as pdf:
    page = pdf.pages[pageno - 1]
    print(f"page {pageno}: {page.width}x{page.height}pt, {len(page.curves)} curves, {len(page.lines)} lines")
    words = page.extract_words(extra_attrs=["size"])
    # group words into lines by top coordinate
    for w in words:
        print(f"  WORD ({w['x0']:.0f},{w['top']:.0f})-({w['x1']:.0f},{w['bottom']:.0f}) '{w['text']}'")
