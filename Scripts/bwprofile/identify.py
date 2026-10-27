import sys
import pdfplumber

src = sys.argv[1]
with pdfplumber.open(src) as pdf:
    for i, page in enumerate(pdf.pages):
        for j, img in enumerate(page.images):
            x0, top, x1, bottom = img["x0"], img["top"], img["x1"], img["bottom"]
            if (x1-x0) < 40 or (bottom-top) < 40:
                continue
            # words above the image (title) and below (caption)
            above = [w["text"] for w in page.extract_words()
                     if w["bottom"] <= top + 2 and w["top"] >= top - 40
                     and w["x0"] < x1 and w["x1"] > x0]
            below = [w["text"] for w in page.extract_words()
                     if w["top"] >= bottom - 2 and w["bottom"] <= bottom + 40
                     and w["x0"] < x1 and w["x1"] > x0]
            inside = [w["text"] for w in page.extract_words()
                     if w["top"] >= top and w["bottom"] <= bottom]
            print(f"p{i+1} img{j}: ABOVE={' '.join(above)[:80]} | BELOW={' '.join(below)[:60]} | INSIDE({' '.join(inside)[:60]})")
