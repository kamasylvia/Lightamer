import sys
import pdfplumber
with pdfplumber.open(sys.argv[1]) as pdf:
    i = int(sys.argv[2]) - 1
    print(pdf.pages[i].extract_text() or "(no text)")
