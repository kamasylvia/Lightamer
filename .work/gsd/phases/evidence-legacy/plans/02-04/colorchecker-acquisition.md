# ColorChecker ARW 采集记录（02-04 遗留 → 2026-10-26 网上寻获，标定完毕）

> **2026-10-26 晚首启结局：标定成功（含产线帧变换勘误），双 ARW 门真红 = 两个真发现，坐标表回退为空（门维持 skip），专项调查批已立项登记（见下「首启发现」节）。**

## 首启发现（2026-10-26 20:17，IOPParity GoldenColorTests）

1. **中性门红（样本表型级）**：六中性补丁透过产线呈一致 **+7/255 蓝偏**（如 N8.0 =
   R234 G236 B243；|G−B|≈7 > 2/255 门）——日光 AWB 表型（相机 as-shot WB 蓝偏），
   非管线缺陷；合成目标同门通过 = 管线中性处理本身正确。处置方向（调查批裁决）：
   ARW 腿独立容差（如 8/255 + 注记）或样本 WB 预处理,合成腿维持 2/255。
2. **交叉一致性门红（真发现）**：pipe 全链 vs CIContext/ColorSync 直渲（**同一
   decode 输出**）在**暗区**（floor=60 下）maxInZone = **255**（门 = 完全分歧）——
   合成 TIFF 无此表型。两腿同源排除朝向错配；疑似真传感器暗部（黑位/线性低段）
   处理分歧。**这是该供件本要抓的实传感器分歧类——最有价值产出**，需专项归因
   （候选：黑位/线性段 vs ColorSync 内嵌 profile 换算、premultiply、暗部 clip
   语义）。失败转储 = `.work/plans/02-04/golden-dump-1793017{011,846}-*-arw/`
   （plane.pfm 产线帧 + 基线帧）。

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
