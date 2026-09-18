# 02-04-06 — ColorChecker ARW 采集记录

**结论(2026-09-19):CC0 ColorChecker RAW 未能自动采集,合成 fixture 承担 D-COL1 gate;ARW 路径 XCTSkip 待人工补拍。**

## 采集尝试

1. **raw.pixls.us(RawPedia,Phase 1 样本同源,CC0)**:全站 Sony/ILCE 目录扫描(60 机型 × 文件名 grep `color|cc|chart|target|check`)零命中。其上传政策明文排除 color target("if you can provide a more useful photo … but **NOT** a photo of a color target")——存量已清退,新增不再收。
2. **等效 CC0 源网络检索**(web_search_prime):dpreview 论坛帖(个人求助帖,非 CC0 授权)、pixls 论坛(流程讨论)、无公开 CC0 ColorChecker RAW 仓库命中。

## 待人工补拍(激活路径)

- 用户以任意相机拍 X-Rite ColorChecker(24 色块,平光,Raw 格式),以 CC0 放出;
- 保存为 `input/RAW/ColorChecker.ARW`(目录 gitignored,样本不入库);
- 在 `Tests/LightamerTests/Fixtures.swift` 标定 `colorCheckerGrayPatches`(6 个灰块的归一化坐标,解码 PNG 目视或脚本标定);
- `GoldenColorTests` 的 ARW 双判据测试自动从 XCTSkip 转为实跑(定位逻辑已就位:`Fixtures.colorCheckerARW`)。

## 已就位的合成 gate

- `Resources/TestFixtures/NeutralTarget.tif`(committed,6.3MB):1024×1024 16-bit sRGB TIFF,3×3 patch 网格,
  6 灰块(线性 Rec2020:1.0/0.75/0.5/0.18/0.09/0.0)+ 3 饱和色块;
  生成器 `.work/02-04/make-neutral-target.swift`(16-bit byteOrder16Little gotcha 见脚本内注释),
  像素级 QA:`.work/02-04/verify-neutral2.swift` 线性值逐块精确匹配。
