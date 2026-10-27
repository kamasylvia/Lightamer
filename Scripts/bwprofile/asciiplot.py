import sys, json
d = json.load(open(sys.argv[1]))
key = sys.argv[2]
pts = d[key]["points"] if "points" in d[key] else None
if pts is None and "curves" in d[key]:
    for idx, c in d[key]["curves"].items():
        print(f"--- {key} curve{idx} ---")
        plot(c["points"]); 
    sys.exit()
def plot(rows):
    W, H = 100, 26
    grid = [[" "] * W for _ in range(H)]
    vals = [v for _, v in rows if v is not None]
    if not vals: print("(empty)"); return
    lo, hi = min(vals), max(vals)
    xs = [x for x, _ in rows]
    for x, v in rows:
        if v is None: continue
        cx = int((x - min(xs)) / (max(xs) - min(xs)) * (W - 1))
        cy = int((1 - (v - lo) / (hi - lo + 1e-9)) * (H - 1))
        grid[cy][cx] = "*"
    print(f"range [{lo:.3f}, {hi:.3f}] over x [{min(xs)}, {max(xs)}]")
    for r in grid: print("".join(r))
plot(pts)
