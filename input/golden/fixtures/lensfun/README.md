# lensfun fixtures (04-04-T2)

Hand-picked MINIMAL subset of the lensfun-data library (github.com/lensfun/lensfun-data,
CC-BY-SA 3.0 — same license family as the upstream data; files are TRIMMED to one
lens (+ its camera) each for parser/resolve pinning, NOT the full library).

| file | lens | models covered |
|---|---|---|
| sony-e16.xml | Sony E 16mm f/2.8 | ptlens distortion + poly3 TCA + pa vignetting grid |
| canon-efs24.xml | Canon EF-S 24mm f/2.8 STM | poly3 distortion + sparse poly3 TCA (vr/vb only) |
| compact-poly5.xml | Canon PowerShot G12 fixed lens | poly5 distortion (5 focal rows → spline) |
| sony-e24za.xml | Sony E 24mm f/1.8 ZA | linear TCA (kr/kb direct) + ptlens |

The FULL library (~4.2MB, 55 xml) is downloaded at first run (LensfunDownloadService)
and NEVER enters git (D-G1). `LensfunDBTests` uses hermetic inline XML literals;
these files serve manual cross-checks + future cross-implementation review.
