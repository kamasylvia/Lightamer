# 05-04-SUMMARY.md — vibrance + velvia + colorzones 执行总结

> 决策见 `05-04-DECISIONS.md`（D-05-04-T2-1–T5-1）。T5 修复轮（R1/R2 + 还账）后收工。

## 任务表（5 项；每任务独立提交 + T5 修复 3 提交）

| 任务 | 内容 | commit |
|---|---|---|
| T1 | vibrance 模块（58.0，Lab `sw=hypot/256`，amount·0.01 uniforms）+ velvia 模块（57.0，RGB pmax/pmin→psat→pweight→clamp 本体，strength/100）+ 双 kernel（LabMath fuse / 纯 RGB）+ 注册/prewarm/seed-ENABLED-neutral ×2 + V50 57.0/58.0 + CPU 9 测试（手算点 + 恒等 + clamp 钉 + 低饱和方向） | `ea6a80f` feat(vibrance,velvia) |
| T2 | colorzones：V2 splines 核对（cubic/catmull 与 V1 同式→委托；monotone=G-variant 新增；周期腿新增，MONOTONE→variant）+ `ColorZonesLUT`（strength 折叠 + 3×0x10000 构建，select h 时周期）+ `colorzones_v3` kernel（CL 腿 NEAREST documented 偏离）+ 模块（60.0，520B 侧写忠实，SMOOTH/v3 only）+ 注册/prewarm/seed + 11 测试 | `ff57256` feat(colorzones) |
| T3 | gen_fixtures（vib/vel float64 镜 + V2 colorzones 镜 + 9 XMP 4B/8B/520B + refs 生成器）+ parity（vib 2×6 + vel 3×6 <1e-5 + 恒等门 + clamp 钉；CZ 4×6 双层门 + LUT-direct + hue-sweep 全环）+ dt 采纳（vib/vel 5/5 version-ok；cz 插件坏记录）+ 平场 probe 6/6 + manifest（待 05-08 台账轮落账） | `9da6f89` test(05-04) |
| T4 | 面板 ×3（vibrance 单滑块 / velvia strength+bias / colorzones L-C-h 三 tab + CurveEditorView 复用 + hue 色带 + select/strength/mode）+ providers + 23 catalog 键 zh/en + a11y + PanelWiring +5（3 拖动=1 commit 含曲线离散化 + reset seed-hash + dispatch）+ seed 断言 ×3 | `600ed00` feat(panels-05-04) |
| T5 | 轨 B（3 中性件插链，双判据绿）+ PERF（`.work/05-04/perf.md`，3 趟 +6ms）+ GUI 走查（FINDINGS GUI-10/11 + 量化）+ label 修（`fix(inspector)`）+ 全量回归 + SUMMARY/DECISIONS | 本轮（`de62b4f` + 下述修复） |

## 证据指针

- T1：`VibranceVelviaCommitTests` 9/9（amount 25→0.25 / strength 25→0.25+bias；
  Lab(50,20,10)@0.25 → (49.727,20.437,10.218)手算；amount/strength 0 恒等；
  velvia (1.5,0.2,0.2) → clamp=(1.0,0.2,0.2) + pweight 0 floor 解剖；
  (0.7,0.4,0.35)@1.0 → boosting 方向）。V50 57.0/58.0（velvia<vibrance）。
- T2：`ColorZonesCommitTests` 11/11（cubic/catmull V2≡V1 逐点 1e-12；
  monotone 手算 V1 m[1]=0.8416/m[2]=0.1629 vs VARIANT G=0.5783；
  周期接缝/过 knot 三型；恒等表 <1e-9；commit 3×0x10000 全 0.5 + channel=2；
  参考恒等三通道 + hue 低饱和抑制方向）。V50 60.0。
- T3：轨 A parity——vib 2×6（default/strong 75）+ vel 3×6（default/strong 75/
  clamp 100+bias 0，bias 0 极端腿）× 6 fixture（含 hue_sweep + stair_1d 间接）——
  全 <1e-5（strict 1e-5/2.5e-5@99% + envelope 1e-4/5e-4）；
  CZ 4×6（default/lightness-CatMull/chroma-Hermite/hue-Hermite+strength 50）：
  MAIN 5 fixture strict **100%**（0 违反，59.7 万样本）+ SPECTRAL envelope
  （1e-2）0 违反（strict 85.8% 上报，maxAbs=0.43）；
  LUT-direct（stair_1d 倾斜 L）：envelope 0 违反 + bias 界（maxAbs=8.5e-5 < 1e-4）；
  hue-sweep 全环 live（360 列，span>0.5）；中性恒等门（gray_staircase @1e-5，
  saturated 除外——velvia clamp 设计语义）。
  dt 三证据：vib/vel 5/5 `params v.2 version ok params ok`（实跑日志）；
  cz 0/4（host `libcolorzones.so` 符号缺失，DECISIONS D-T3-4）；
  blob 格式断言（4B/8B/520B `struct.calcsize` = dt `sizeof`）；
  平场 probe 6/6（vib 灰场恒等 paradox + vel 双档恒等 + cz_lightness L 提升
  0.5→0.87 directional + cz_chroma/cz_hue 灰场恒等）。
- T4：`PanelWiringTests` 45/45（既有 40 + 本轮 5：vib/vel 拖动=1 commit +
  cz 曲线离散化拖动=1 commit + vib reset seed-hash + 三 dispatch）。
  catalog 23 键（panel_vibrance_×2/panel_velvia_×3/panel_cz_×15/history_×3）。
  a11y：panel ×3 + slider ×3 + channel/select/mode + huestrip + curveeditor 节点。
- T5：见下节。

## 防空转自检声明

| 套件 | compared |
|---|---|
| VibranceVelviaCommitTests（9） | 手算点逐值 + 恒等 + clamp/nail（非循环，逐断言） |
| ColorZonesCommitTests（11） | V2-vs-V1 全网格逐点（cubic 21 点）+ 表全扫描（identity 0.5 全表；commit 997 步进）+ 参考三通道 |
| VibranceVelviaParityTests（3） | 全像素双循环（2×6 + 3×6 ×RGB；compared>0）+ ramp≠flat 非空转门 ×2 + 中性恒等门 |
| ColorZonesParityTests（3） | 全像素双循环（MAIN 59.7 万 + SPECTRAL 7.7 万；compared>0 双层）+ ramp≠flat + sweep 方差 + 全环 2.3 万列均值 |
| PanelWiringTests（45：既有 40 + 本轮 5） | drag 6 ticks → history==1 ×4（含曲线）；reset hash；dispatch 非 nil ×3 |
| V50Order（+2 方法：velvia/vibrance 槽位；colorzones 槽位在 CPU 测试内） | order 数值 + 两侧序关系 |
| GUI 走查 | 渲染变化量化（vib 322k px / vel 81k px）+ AX 可达 + 布局红线（FINDINGS GUI-10/11） |

## 验收标准核对（plan §验收标准 7 条）

- [x] vibrance/velvia：轨 A <1e-5 + 恒等门 + velvia clamp 行为钉死 + 弃用/局限头注 ×2
- [x] colorzones：轨 A 4×6（MAIN strict 100% + SPECTRAL envelope）+ LUT 双闸（99% 档实测入账：MAIN 100%/SPECTRAL 85.8%/LUT-direct 上报）+ hue sweep 全环实跑 + V2 splines 核对结论落 DECISIONS
- [x] 三槽位 V50 断言（57.0/58.0 方法 + 60.0 在 CPU 测试）；seed 中性恒等论证（neutral-identity 门 + PanelWiring reset-hash）
- [x] dt 三证据 ×3（vib/vel 5/5 version-ok + cz 插件坏记录 + blob 格式断言；manifest 落账待 05-08 台账轮——05-03 同口径，不在本 plan 交付内）
- [x] 面板 ×3（CurveEditorView 复用 + hue 色带）+ PanelWiring +5 + catalog + a11y
- [x] GUI 走查登记（GUI-10/11 + 通过项量化）；轨 B 双判据不回归；PERF 记录落 `.work/05-04/perf.md`
- [x] 全 suite 绿（512/0fail/3skip）；ROI 头注钉死 ×3（恒等 + tileHalo=0 + 禁 dscIn×scale）

## T5 证据（轨 B / PERF / GUI）

- 轨 B：`makeChainWithCropFlip` 插 vibrance + velvia + colorzones 中性件
  （ENABLED-neutral ×3）。`GeometryGoldenTests` 4/4（neutrality +
  cross-consistency 双判据，终轮全绿即回归证据）。
- PERF：`.work/05-04/perf.md`（3 趟单 pass，链增量 +3–6ms@2560 Debug；
  colorzones LUT 768KB commit 期上传，per-frame 零上传；seed 政策 + SC#4 口径）。
- GUI 走查（PLAYBOOK §2+§3，真机 DSC00012.ARW）：
  - 通过：三模块行注册 + 中文标签（颜色区域/Velvia/自然饱和度，`fix(inspector)`
    修裸 opName 回落）；vibrance 0→60 渲染变化（max 100/mean 0.36，322k px）；
    velvia 0→75 渲染变化（max 134/mean 0.15，81k px）；colorzones 通道 radio
    AX 可达（hue 选中 value=1）；280pt 约束未破。
  - GUI-10（高）：colorzones 曲线面板体被模块列表挤出可视区（moduleList VStack
    无 ScrollView/高度约束；AX radio×3+slider×1 可达，体未目验）。
  - GUI-11（中）：velvia/vibrance 体同因需滚（AX 径已验 slider + 渲染变化）。
  - 附带：陈旧 sidecar（23 实例）致新行缺席——删 .lra 后 26 行齐现（02-06
    persisted-only 语义，非回归；已恢复用户 sidecar）。
  - 证据截图 /tmp/la-0504-*（7 帧）+ FINDINGS 登记；实例已 `osascript quit`。

## 全量回归

终轮全 suite：**512 passed / 0 failed / 3 skipped**（基线 05-03 的 480 + 本轮
32 新增：Commit 9 + CZ-Commit 11 + V/V parity 3 + CZ parity 3 + PanelWiring 5 +
V50 1 方法…口径：V50 +2 方法中 velvia/vibrance 槽位 1 方法 + colorzones 槽位在
CZ-Commit 内；skip 3 既有合规）。
轨 B 双判据终轮全绿；MDB_MAP_FULL 杂音未现（本轮无）。

## 修复轮 R1/R2 + 还账（T5 全量回归暴露，2026-09-22）

| 项 | 内容 | commit |
|---|---|---|
| R1 | 注册表 colorcontrast 行丢失事故恢复（T1 编辑误删；T2 起三轮构建静默通过——删行无引用方编译不报错；T5 512/7fail 暴露：contrast parity + perf 双链 `makeBox` nil）。教训：注册改动后必跑全量（单类绿对此删除免疫） | 待本轮（Registry 一行） |
| R2 | hue_sweep PEDELTA 还账：`NoiseFixtureStatisticsTests` 指纹更新（0.0→0.001 ×2）+ colorbalance refs 重生成（JzAzBz/DTUCS×sweep 失配；`gen refs` 死模式确认——main 无 `"refs"` 分支，跨 fixture 改动须直调 `gen_*_refs` + 核时间戳） | 待本轮（pin 测试 + 输出 EXR 重生成*） |
| 还账 | 轨 B 插链三中性件（`makeChainWithCropFlip`）+ `fix(inspector)` 中文标签 + FINDINGS GUI-10/11 + perf.md + SUMMARY/DECISIONS | `de62b4f` + 本轮 |

（*输出 EXR 属 gitignore 再生成物，不进 commit；XMP + 生成器进仓，manifest 台账
落账按 05-03 口径归 05-08 签核轮。）
