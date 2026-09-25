# Lightamer

A macOS-native RAW editor and photo manager (Swift 6 + SwiftUI + Metal 3 +
Core Image RAW), pairing a Capture One-style Session workflow with
Darktable-grade adjustments and first-class 印框/水印 (border/watermark)
output tools.

## Trademarks & embedded brand logos (Plan 08-2, D-08-CONTEXT-5)

The 印框/水印 feature ships a set of camera-brand logos
(`LightamerIOP/Resources/Logos/*.pdf`, 13 brands × light/dark) so a photo's
watermark can display the manufacturer mark, matching the upstream yiyin
project's behavior:

| Logo | Owner |
|---|---|
| Canon | Canon Inc. |
| DJI | SZ DJI Technology Co., Ltd. |
| FUJIFILM | FUJIFILM Holdings Corporation |
| Hasselblad | Hasselblad AB |
| Leica | Leica Camera AG |
| Nikon | Nikon Corporation |
| Olympus | OM Digital Solutions Corporation (OM SYSTEM) |
| Panasonic | Panasonic Holdings Corporation |
| PENTAX | Ricoh Imaging Company, Ltd. |
| RICOH | Ricoh Company, Ltd. |
| SIGMA | Sigma Corporation |
| Songdian（松典） | Shenzhen Songdian Technology Co., Ltd. |
| SONY | Sony Group Corporation |

All names and logos are **trademarks of their respective owners**, used
here solely for the nominative purpose of identifying the manufacturer of
the equipment depicted in a photograph. Their inclusion does not imply any
affiliation with, sponsorship, or endorsement by these owners. Lightamer is
an independent open-source project; the logos are converted from the
[GPL-3.0-licensed yiyin](https://github.com/kamasylvia/yiyin) project's
brand SVG assets (the same author's work), and each artwork itself remains
the property of its trademark holder. Rights holders who object to
inclusion may open an issue and the asset will be removed.

### Fonts

The watermark renderer uses **system-provided fonts only** (PingFang SC
cascade via CoreText, plus user-imported `.ttf`/`.otf` files) — no third
party font is embedded with this application.

## License

Open source, free to use — see the LICENSE file (Developer ID signed,
notarized builds distributed independently).
