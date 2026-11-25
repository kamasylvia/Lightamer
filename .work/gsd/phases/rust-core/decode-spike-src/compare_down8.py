#!/usr/bin/env python3
"""compare_down8.py — WB-variant diagnosis at 1/8 stride (M9 archive).

usage: uv run --with numpy compare_down8.py mhc-linear.bin a7r5-ciraw-linear.f32
Reconstruction of the ad-hoc probe quoted in CORE-DESIGN.md:101
(no-WB mean 0.1285 vs WB mean 0.1699). Stride FIRST, then centered crop
(oy=2, ox=4 at stride 8) — this alignment is why full-res-first recomputes differ.
"""
import sys
import numpy as np

XYZ2CAM = np.array([[0.820000, -0.297600, -0.071900],
                    [-0.429600, 1.205300, 0.253200],
                    [-0.042900, 0.128200, 0.577400]])
XYZ2SRGB = np.array([[3.2404542, -1.5371385, -0.4985314],
                     [-0.9692660, 1.8760108, 0.0415560],
                     [0.0556434, -0.2040259, 1.0572252]])


def main():
    ours = np.fromfile(sys.argv[1], dtype=np.float32).reshape(6376, 9568, 3).astype(np.float64)
    cir = np.fromfile(sys.argv[2], dtype=np.float32).reshape(6336, 9504, 4)[:, :, :3]
    o, c = ours[::8, ::8], cir[::8, ::8]
    oy, ox = (o.shape[0] - c.shape[0]) // 2, (o.shape[1] - c.shape[1]) // 2
    print(f"stride8 shapes: o={o.shape} c={c.shape} oy={oy} ox={ox}")
    M = XYZ2SRGB @ np.linalg.inv(XYZ2CAM)
    for tag, gains in [('WBx(wb/g)', np.array([2536 / 1024, 1, 1778 / 1024])),
                       ('WBx(g/wb)', np.array([1024 / 2536, 1, 1024 / 1778])),
                       ('no-WB', np.array([1., 1., 1.]))]:
        a = ((o * gains) @ M.T)[oy:oy + c.shape[0], ox:ox + c.shape[1]]
        d = np.abs(a - c)
        print(f"{tag}: mean={float(d.mean()):.4f} max={float(d.max()):.3f} "
              f"ours_mean={a.reshape(-1, 3).mean(0).round(4)}")


if __name__ == "__main__":
    main()
