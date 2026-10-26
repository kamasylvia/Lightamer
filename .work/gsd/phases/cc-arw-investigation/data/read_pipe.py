import numpy as np, sys

path = ".work/plans/02-04/golden-dump-1793016846-cross-arw/plane.pfm"
with open(path, "rb") as f:
    assert f.readline().strip() == b"P7"
    w, h = map(int, f.readline().split())
    scale = float(f.readline())
    data = np.fromfile(f, dtype="<f4", count=w*h*3)
print(f"w={w} h={h} scale={scale} n={data.size}")
img = data.reshape(h, w, 3)  # physical order = top-down (dumpFailure writes array order)

# patches: N9.5..N2.0 at y=0.94997
patches = [("N9.5",0.28117),("N8.0",0.30721),("N6.5",0.33286),("N5.0",0.35906),("N3.5",0.38573),("N2.0",0.41383)]
for name, x in patches:
    px, py = int(x*(w-1)), int(0.94997*(h-1))
    s = img[py-1:py+2, px-1:px+2].reshape(-1,3).mean(axis=0)*255
    print(f"{name}: R={s[0]:.1f} G={s[1]:.1f} B={s[2]:.1f}")

# corners + stats
print("corner TL", img[5,5]*255, "BR", img[h-6,w-6]*255)
print("global mean", img.mean(axis=(0,1))*255)
np.save(".work/gsd/phases/cc-arw-investigation/data/pipe_frame.npy", img.astype(np.float32))
