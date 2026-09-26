# 04-04 match-ledger — Lensfun EXIF 匹配落账（T2 acceptance）

> v1 从简口径：miss 不算失败，落账即可（plan T2 acceptance）。
> 匹配器 = `LensfunMatch.match`（归一化 + 等值/包含 + cropfactor ≥0.96 门）；
> 测试库 = 全量 `/opt/homebrew/share/lensfun/version_1/`（55 xml，测试机读取，非 git）。

## 输入 EXIF（CGImageSource 实测，2026-09-20）

| 文件 | Make/Model | LensModel | Focal/FNumber | 结论 |
|---|---|---|---|---|
| DSC00012.ARW | SONY / ILCE-7RM5 | `----`（无镜头：机身盖/转接哑铃） | 0 / 0 | 无有效镜头键 |
| DSC09991.ARW | SONY / ILCE-7RM5 | `----`（同上） | 0 / 0 | 无有效镜头键 |
| DSC00012.jpg | SONY / ILCE-7RM5 | `----`（同上） | 0 / 0 | 来自同一机身盖拍摄 |

（另有 corrupt.ARW 4KB — 解码失败样本，非匹配对象。）

## 全库匹配结果

| 输入 lensKey | 命中/miss | 原因 |
|---|---|---|
| `----`（DSC00012/09991/JPG 三文件相同） | miss | 无有效镜头键：`----` 归一化后为空 / 无词命中；`focal=0` 使 resolve 门（focal>0）同样拒绝。matcher 返回 nil。 |

- miss 率：3/3 有效文件 miss（100%）——**原因全部是输入侧无镜头数据**（机身盖样本），
  非 matcher 缺陷。对照证据：同一 matcher 在 `LensfunDBTests.testMatchSonyE16`
  对 `E 16mm F2.8` 精确命中（score 100），`sony-e24za` linear、`compact-poly5`
  同库解析可用。
- 真实镜头样本（含 EXIF LensModel + focal>0，如 Sony E 卡口实拍 ARW）待用户提供后
  复测（`input/RAW/` 新增实拍文件时更新本表）。

## 降级路径（已实现 + 已测试）

- miss/无 lensKey/focal≤0 → `LensfunStore.resolveCommitted` 返回 nil →
  `LensModule.process` 走 blit 恒等 + `AppError.logger` 警告（D5）。
- 手动层（sliders → 同一 kernel）全程可用，不依赖任何数据文件。
