# C4 oracle commands (verbatim, re-runnable)

Isolation prefix (every run; each leg its own HOME — back-to-back runs on the SAME HOME
can hit `database is locked ... aborting` from a stale lock, use independent HOMEs or retry
after the previous process exits; always double-check output file + rc):

```bash
DT=/Volumes/darktable/darktable.app/Contents/MacOS/darktable-cli
export HOME=/tmp/dt-oracle/runcpu CFFIXED_USER_HOME=/tmp/dt-oracle/runcpu   # CPU leg
export HOME=/tmp/dt-oracle/run1  CFFIXED_USER_HOME=/tmp/dt-oracle/run1      # OpenCL leg
```

Config: `--core --conf key=value` applies at RUNTIME but does NOT persist to darktablerc
(self-verified: bpp=8 override on a bpp=16 file yields IHDR 8, file stays 16; first draft
wrongly claimed it does nothing). Pre-seeded darktablerc below is the recommended persistent form:

```bash
# first run once tiny to generate darktablerc, then:
sed -i '' 's#^plugins/imageio/format/png/bpp=8$#plugins/imageio/format/png/bpp=16#' darktablerc
# OpenCL leg additionally:
sed -i '' 's/^opencl=false$/opencl=true/' darktablerc
```

Exports (full-res 16-bit PNG; XMP optional positional; prefix `/usr/bin/time -p` for wall/user/sys):

```bash
# G0 no history (CPU leg):
/usr/bin/time -p $DT /tmp/dt-oracle/work/7RM5-LosslessCompressedLarge.ARW /tmp/dt-oracle/out/g0-full-cpu.png
# G1 exposure +1EV:
/usr/bin/time -p $DT /tmp/dt-oracle/work/7RM5-LosslessCompressedLarge.ARW /tmp/dt-oracle/work/g1m-exposure.xmp /tmp/dt-oracle/out/g1-full-cpu.png
# G2 exposure + flip-horizontal:
/usr/bin/time -p $DT /tmp/dt-oracle/work/7RM5-LosslessCompressedLarge.ARW /tmp/dt-oracle/work/g2m-exposure-flip.xmp /tmp/dt-oracle/out/g2-full-cpu.png
# OpenCL leg: same with run1 env. Backend proof: append `--core -d opencl` once per leg and grep:
#   CPU: "device 'Apple Apple M4' id=0: NOT utilized"
#   CL:  "161 out of 161 events were successful" + "tiled direct bayer demosaic RCD"
```

Probes (1600px validation, uint8-scale checks in RESULTS.md):

```bash
$DT /tmp/dt-oracle/work/7RM5-LosslessCompressedLarge.ARW /tmp/dt-oracle/out/g0-probe.png --width 1600
$DT /tmp/dt-oracle/work/7RM5-LosslessCompressedLarge.ARW /tmp/dt-oracle/work/g1m-exposure.xmp /tmp/dt-oracle/out/g1m-probe.png --width 1600
$DT /tmp/dt-oracle/work/7RM5-LosslessCompressedLarge.ARW /tmp/dt-oracle/work/g2m-exposure-flip.xmp /tmp/dt-oracle/out/g2m-probe.png --width 1600
```

Prefs snapshot: org.darktable.before.plist (in this dir) = `defaults export org.darktable` BEFORE first run.

Compare (cv2 reads 16-bit RGB; Pillow truncates to 8-bit):

```bash
uv run --with opencv-python-headless --with numpy cmp16.py A.png B.png [--tol T] [--shift]
```

XMP rules found the hard way:

- Minimal history (only changed modules) + `auto_presets_applied="0"` + `xmp_version="4"` works; darktable fills defaults per-camera. `iop_order_version` omissible (absent => LEGACY->V50 default); explicit 4 or 5 both accepted (review tested 6 variants, all pass).
- NO XML comments in sidecars: a leading `<!-- ... -->` fails the whole read with `error: can't open XMP file` (probe-comment.xmp in this dir reproduces; this was the true cause misattributed to version 5 in the first draft).
- Copying full history across cameras breaks geometry (probe height 1095 vs 1066: foreign rawprepare crop).
- Exposure +1EV params v7 hex (28 bytes LE):
  `00000000 00000000 0000803f 00004842 000080c0 00000000 01000000`
  = mode 0 (MANUAL), black 0.0, exposure 1.0, percentile 50.0, target -4.0, bias FALSE, hilite TRUE.
- flip-horizontal params v2 hex: `02000000` (ORIENTATION_FLIP_X = 2).

C3-DNG diagnosis commands (T0/T1/T2; outputs dngfix-cmp-t{0,1,2}.log in this dir):

```bash
RS=/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike
SPIKE=/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/core-design-spike
# T0 baseline DNG (built by the rawspeed lane): $RS/work/a7r5-ds0.dng
# T1/T2 DNGs (this lane, rs2dng_fix --neutral; sources decode-spike-src/rs2dng.cpp+dngwriter.h):
#   $SPIKE/fix-t1-unit.dng  (--neutral 1,1,1)
#   $SPIKE/fix-t2-fit.dng   (--neutral 0.38772,0.88989,0.44585)
cd $RS
./bin/bench cmp samples/7RM5-LosslessCompressedLarge.ARW work/a7r5-ds0.dng        # T0 -> 22.784
./bin/bench cmp samples/7RM5-LosslessCompressedLarge.ARW $SPIKE/fix-t1-unit.dng   # T1 -> 55.935
./bin/bench cmp samples/7RM5-LosslessCompressedLarge.ARW $SPIKE/fix-t2-fit.dng    # T2 -> 23.275
# cmp dims note: 2560x1707 vs 2560x1706 (DNG renders 1 row short); scale 0..255.
```
