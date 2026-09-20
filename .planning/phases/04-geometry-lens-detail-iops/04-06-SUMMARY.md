# 04-06 SUMMARY — GUI 显示腿修复（GUI-1..4）

> Plan 04-06（wave 4，depends 04-01..05）执行收尾。任务书 `.planning/phases/04-geometry-lens-detail-iops/04-06-PLAN.md` 逐字执行：T1 探针先行独立提交 → T2/T3/T4 按证据修复 → T5 真实 GUI 复验闭环。

## 交付（5 commits）

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `bc90581` | 判别探针 `GUIProbeTests`（DSC00012 真 RAW 消融 A–Q7）+ `probe-gui1.md` + DECISIONS D-GUI-1 |
| T2 | `e832817` | `CropModule.modifyROIIn` 去 double-scale + `testScaledFullFrameCropMatchesTrioOnly` |
| T3 | `52c5266` | 顶点矩形 strip blit（FitQuad + shader 重写）+ `testFitQuadMatchesFittedRect` |
| T4 | `4398c46` | 列宽收窄（侧栏 200 / Inspector 280） |
| T5 | （本批） | FINDINGS 闭环 + 探针退役 + LESSONS L021 + TODO + 本 SUMMARY |

## 根因（D-GUI-1，证据见 DECISIONS + probe-gui1.md）

- **GUI-1**：crop `modifyROIIn` double-scale（dscIn 已 entry 缩放又 ×scale）→ 760 档协商 roiIn 60×40 → 左上小窗 blit、其余全零。plan 候选 a/b/c（texture 选择/链启用/CI 域）全部实测排除：displayTexture 一直是 bgra8Unorm（gamma tail 到达），trio-only 亮，线性域 sane。
- **GUI-2+3**：大三角形 + uv 反算（同根，顶点矩形 strip 根治）。
- **GUI-4**：列宽默认值均分（收窄 + 持久化说明）。

## 复验量化（T5.2，PLAYBOOK §2，Debug 产物 + DSC00012.ARW）

| 项 | 修复前 | 修复后 | 门 |
|---|---|---|---|
| GUI-1 视口 <16 | 30.6% | **13.7%** | 显著下降 ✓ |
| GUI-1 视口 ≥128 | 1.3%（全 overlay） | **2.8%** | 上升 ✓ |
| GUI-1 饱和像素 | 0 | **75480** | >100 ✓ |
| GUI-1 in-process A 腿 | mean (0,6,5), <16 94.2% | mean (20,49,37), <16 51.8% | 因果一致 ✓ |
| GUI-2 对角线 | 左上白斜线 | 无（zoom 目检；off-grid 5835px 为照片白光源） | ✓ |
| GUI-3 包络 | 800×1120 vs fit 800×533 | 内容 == 全幅（边距 ≤11px），网格贴合 | ✓ |
| GUI-4 三列 | 均分，视口非主体 | 侧栏 13.9% / **视口 54.1%** / Inspector 32.0%（1440pt 窗，侧栏 200 / 视口 779 / Inspector 461pt） | ≥50% ✓ |

证据：`.work/gui-acceptance/2026-09-21-fix-DSC00012-{window,window2,fresh}.png` + FINDINGS.md 逐项闭环。无 app 实例残留（osascript quit，已验证）。

## 验收标准对照

- [x] D-GUI-1 有探针证据（pixelFormat + 像素值 + 域判定），修复因果一致
- [x] 复验四项全过（上表），截图 + 数字落 FINDINGS.md
- [x] 全套 LightamerTests 绿：**389 tests，3 skip，0 fail**（基线 387 + crop scaled 回归 + fitQuad 回归；探针退役不计数）
- [x] 布局红线三条实测入 SUMMARY（上表 GUI-4 行；990pt 窗待补，1440pt 窗已达标）
- [x] Core 管线零改动（改动在 LightamerIOP CropModule + App 显示腿；DECISIONS 论证）
- [x] 无常驻 app 实例残留
- [x] 注册/seed 零改动（全量回归 389 绿即证；PanelWiring seed 门全过）

## 遗留（非阻塞）

- Inspector 首次顶 max 460（NSSplitView 行为，用户拖窄一次即记忆 280）；990pt 窗三列复验待补。
- toneequal blending 直径 / flip bw-bh 的同类 `dscIn × scale` 模式留 Phase 5 审计（D-GUI-1 附带观察）。
- tone seed 三 filmic 栈同开的“风格化强、中间调少”观感（D-GUI-1 附带）→ Phase 8/实机校准（TODO Phase 3 遗留行已覆盖）。
