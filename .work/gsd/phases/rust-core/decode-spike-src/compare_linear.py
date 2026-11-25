#!/usr/bin/env python3
"""compare_linear.py — our MHC demosaic (camera RGB) vs CIRAW linear sRGB dump.

usage: uv run --with numpy compare_linear.py OUR.f32 CIR.f32 OW OH CW CH
  OUR: float32 RGB (camera-native, black-sub, white-normalized), OW x OH
  CIR: float32 RGBA (extended linear sRGB), CW x CH
Steps: WB gains (2536/1024/1778 G-normalized) -> camera->XYZ (inverse of
cameras.xml matrix) -> XYZ->linear-sRGB (Bradford D65) -> center-crop align ->
global-gain fit -> mean/max diff (raw + gain-normalized).
"""
import sys
import numpy as np

# rawspeed cameras.xml for ILCE-7RM5 (XYZ->camera, D65), from demosaic_dump.log
XYZ2CAM = np.array([[0.820000, -0.297600, -0.071900],
                    [-0.429600, 1.205300, 0.253200],
                    [-0.042900, 0.128200, 0.577400]], dtype=np.float64)
# Bradford XYZ(D65) -> linear sRGB (IEC 61966-2-1)
XYZ2SRGB = np.array([[3.2404542, -1.5371385, -0.4985314],
                     [-0.9692660, 1.8760108, 0.0415560],
                     [0.0556434, -0.2040259, 1.0572252]], dtype=np.float64)
WB = np.array([2536.0 / 1024.0, 1.0, 1778.0 / 1024.0])  # R,G,B multipliers


def main():
    our_p, cir_p, ow, oh, cw, ch = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:7])
    ours = np.fromfile(our_p, dtype=np.float32).reshape(oh, ow, 3).astype(np.float64)
    cir = np.fromfile(cir_p, dtype=np.float32).reshape(ch, cw, 4)[:, :, :3].astype(np.float64)
    print(f"ours: {ours.shape} range [{ours.min():.4f}, {ours.max():.4f}] mean {ours.mean():.5f}")
    print(f"cir:  {cir.shape} range [{cir.min():.4f}, {cir.max():.4f}] mean {cir.mean():.5f}")
    # WB + color
    bal = ours * WB.reshape(1, 1, 3)
    cam2xyz = np.linalg.inv(XYZ2CAM)
    m = XYZ2SRGB @ cam2xyz
    print("M(cam->lin-sRGB)=\n", np.round(m, 5))
    lin = bal @ m.T
    print(f"ours->srgb range [{lin.min():.4f}, {lin.max():.4f}] mean {lin.mean():.5f}")
    # center-crop align
    oy, ox = (oh - ch) // 2, (ow - cw) // 2
    print(f"crop offset in ours: y={oy} x={ox} (centered)")
    a = lin[oy:oy + ch, ox:ox + cw]
    d = np.abs(a - cir)
    mean, mx = float(d.mean()), float(d.max())
    print(f"RAW mean_abs_diff={mean:.6f} max_abs_diff={mx:.6f} (linear sRGB units)")
    # global gain fit (isolate exposure-scale from hue/structure)
    g = float((a * cir).sum() / (a * a).sum())
    d2 = np.abs(a * g - cir)
    print(f"gain_fit={g:.5f} NORM mean={float(d2.mean()):.6f} max={float(d2.max()):.6f}")
    ma = a.reshape(-1, 3).mean(axis=0)
    mc = cir.reshape(-1, 3).mean(axis=0)
    print(f"mean_rgb_ours={np.round(ma, 5)} mean_rgb_cir={np.round(mc, 5)}")
    print(f"mean_rgb_ours*gain={np.round(ma * g, 5)}")


if __name__ == "__main__":
    main()
