# ColorChecker ARW 采集记录（02-04 遗留 → 2026-10-26 网上寻获，标定完毕）

> **2026-10-27 调查批结案：两项首启发现均已归因闭环，坐标表已回填，两 ARW 门解禁常跑（定向 6/0/0 全绿）——正本 = `.work/gsd/phases/cc-arw-investigation/{SUMMARY,DECISIONS}.md`。**

## 首启发现（2026-10-26 20:17，IOPParity GoldenColorTests）→ 2026-10-27 调查批裁决

1. **中性门红（样本表型级）→ 确证 + 分档容差**：六中性补丁透过产线呈一致
   **+B 偏**，fence 后干净帧实测 |G−B| 随暗度单调增（N9.5 白被 255 钳制掩盖 →
   N8.0 3.4 → N3.5 7.4 → N2.0 黑 31.2，线性域 B ≈ 40× R/G）；|R−G| 恒 <2。
   EXIF WhiteBalance=0（Auto，日光）+ 合成腿 PASS + 交叉一致性 PASS 三证 =
   as-shot AWB 蓝增益样本表型，非管线缺陷。处置落地 = ARW 腿分档容差
   `neutralARW=8` / `neutralARWBlack=40`（GoldenTolerance），合成腿 2/255 不动。
2. **交叉一致性门红（首启判「真发现」）→ 证伪：读回竞争，非色彩分歧**。
   pipe 腿帧 = `readRGB8` 裸 getBytes 在 60MP 全链 GPU 编码 in-flight 时读回 =
   **整帧全零**（转储逐像素验证 nonzero=0.0；中性转储 1.5 分钟后同路径正常）；
   diff-table p50=110/maxInZone=255 全是 |0−baseline|。修复 = drain fence
   （L014，AgXTests idiom）后 **交叉门直接 PASS（42.7s 真跑）**——pipe 全链 vs
   ColorSync 直渲真分歧在容差内，四个候选归因（premultiply/黑位 clip/working
   space 差/PRC）全部证伪。产线零改动（PixelPipe 无同步是产线 FIFO 安全形态）。
   失败转储 = `.work/plans/02-04/golden-dump-1793017{011,846}-*-arw/`
   （plane.pfm 均为 pipe 帧——首启注记「产线帧+基线帧」有误，dumpFailure 只落
   pipe 腿）。

## 产线帧变换勘误（重要）

首版记录假设「纹理 = 传感器帧（RAWDecoder 不应用 orientation）」——**错**：实测
产线输出为 6336×9504 竖构图（orientation 8 = 90° CCW 已应用；八变换穷举采样定
罪：变换 8 六点呈 255/252/240/217/179/46 精确中性序列，其余变换散度 ≤14 或
域外）。RAWDecoder 不在 decode 显式应用——**应用发生在 CI 链下游**（CIRAW 内建
方向；meta.orientation 仅供上层消费）。**后续标定一律以 dump 帧为准**（本档坐标
已按产线帧给出）。

## 结果

`ColorChecker.ARW`（117MB，Sony ILCE-7RM4，9504×6336 传感器帧 → 6336×9504 产线
帧）已落 `~/Library/Application Support/Lightamer/TestRAW/`（Fixtures 首选腿）。
灰补丁**产线帧归一化坐标**（x = 行向,白→黑；y ≈ 0.94997 恒行心）：

| 补丁 | 产线帧 (x, y) | 传感器帧 y (px, 参考原标定) |
|---|---|---|
| N9.5 white | (0.28117, 0.94997) | 1781.5 |
| N8.0 | (0.30721, 0.94997) | 1946.5 |
| N6.5 | (0.33286, 0.94997) | 2109 |
| N5.0 | (0.35906, 0.94997) | 2275 |
| N3.5 | (0.38573, 0.94997) | 2444 |
| N2.0 black | (0.41383, 0.94997) | 2622 |

变换式：产线 (nx', ny') = 传感器 (ny, 1−nx)。激活开关 = Fixtures
`colorCheckerGrayPatches`（现为空——首启双红后回退，待专项批结论再启）。

## 来源与许可

- 来源链 = photo.stackexchange.com/questions/117345（「How to use X-Rite
  ColorChecker with Sony a7R IV?」公开求助贴）附件 Google Drive
  `1H3Fke4QMcin1BqLSSWniGdGl3CV5G1oQ`（zip：image.ARW 117M + image.DNG 60M +
  自制 DCP）。
- 拍摄：2020-06，室外日光，ColorChecker Passport（2019 Edition）置于米色坐垫上。
- **许可状态：源帖未附显式许可（非 CC0）**——公开求助贴共享样本，用途 = 本仓
  untracked 本地测试供件（永不入 git、永不分发）。与 02-04 原定「release CC0」
  的偏差如实登记；日后觅得 CC0 色卡 RAW 可换装（坐标重标即可）。

## 标定方法与风险注记

分隔暗线中点（上四）+ 平坦带剖面（N3.5/N2）+ 六点十字标记视觉复验；产线帧端由
八变换穷举 + 中性序列判据定罪。中间件 /tmp 即弃。sips 预览即传感器帧渲染（无
EXIF 旋转）——首版据此误判产线帧亦无旋转，已勘误。
