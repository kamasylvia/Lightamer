# Phase 8: HDR/Stacking & Effects iops — Research

**Created:** 2026-09-27
**输入:** `08-CONTEXT.md`（D-08-CONTEXT-1..12）+ `08-RESEARCH-QUESTIONS.md`（RQ-08-1..13）+ ROADMAP §Phase 8 + REQUIREMENTS IOP-HDR-01..05 / IOP-FX-01..05 + 底座源码走查 + darktable 只读参考
**探针环境:** Apple M4（4P+6E）/ 16GB / macOS 27.0 (26A428) / Swift 6.4 `-O` 单线程 CPU 原型；探针源码为 /tmp 即弃合成 fixture（100MP = 11656×8742 = 101.9MP，GFX100 级）。**零预置数字，五项★探针全部实测。**

---

## 0. 探针结果汇总（五项全绿）

| # | 探针 | 实测结果 | 一句话结论 |
|---|---|---|---|
| P1 | MTB 对齐 @100MP（RQ-08-2★） | 整数位移**精确命中**两对（(17,-11) 与 (-9,23)，含 4×/0.25× 曝光差）；ref 位图构建 0.45s + 每对（构建 0.45s + 搜索 1.21s）≈ **1.65s/对单线程 CPU** | 对齐是**廉价段**；3-bracket 全程 ≈ 3.8s CPU，后台任务绰绰有余，GPU 腿是优化非必需 |
| P2 | HDR 权重数学（RQ-08-1★） | ±2EV 括号、1% 拍噪声下恢复误差 **0.04–0.6%**；gaussian σ∈{0.15,0.25} 与三角帽误差同量级（噪声地板）；全源裁剪 → wsum=0 **HOLE 检出 OK**；残差 ghost 拒绝（k=3，5% 噪声地板）非裁剪 ghost 拒绝 OK；合并内循环 **11.2ns/px** → 100MP×3src ≈ 1.1s 单线程 / ~0.33s 4P | Robertson 族数学一次成型；权重形状不敏感（取 gaussian σ=0.2 参数化）；信息洞语义 = 黑 + HOLE 标记成立 |
| P3 | 内存形态（RQ-08-6★） | N=5 全驻 RGB = **7.3GB / RGBA 9.8GB**（16GB 机不可行）；流式行带累积：**峰值 footprint 增量 ≈ 0**（常量工作集 = 累积平面 + 行带缓冲）；sigma-clip N=8 = 136.6ns/px → **13.9s 单线程 / ~4.0s 4P @100MP** | **流式强制**（架构约束，非优化项）；sigma-clip 可接受（4s 并行估） |
| P4 | EDR spike（RQ-08-7★） | `CAMetalLayer` 接受 `.rgba16Float` + `wantsExtendedDynamicRangeContent=true` + `CGColorSpace(name: .extendedLinearSRGB)` 全通（macOS 27.0）；本机当前仅 SDR 外接 BenQ PD2705U：headroom current=1.0 / potential=1.0 | API 面全验证；**XDR 目检 = Manual-Only**（本环境无 XDR 屏）；headroom=1.0 时 toggle 合法、>1.0 值被合成器钳到 SDR 白 |
| P5 | blur 择优 + 焦点度量（RQ-08-9★/RQ-08-5★） | 100MP r=64：3-pass box **1.87s** vs ÷8 级联 **0.29s**（6.5×）；SML 1.5ns/px → 0.15s/源@100MP；真 defocus 代理下 sharp/blurred SML 比 **59×**；软权重融合清晰区归属 **PASS**（双向 MAE ≈ 0.004） | bloom blur = **降采样级联**；SML 度量分离度充分；融合数学验证通过 |

---

## 1. RQ-08-1（P0★）HDR merge 数学落地

### 1.1 权重函数终形

实测（P2）gaussian σ=0.15/0.25 与三角帽在 1% 拍噪声下**不可区分**（误差都在噪声地板内）。终形定为**单权重 + 双门**：

```
w(p) = 0                                  若 p ≥ clipGate (0.995) 或 p ≤ floorGate (0.001)
w(p) = exp(−(p − 0.5)² / (2σ²))           其余；σ 默认 0.2（参数化，D-08-CONTEXT-1 Reversibility 兑现）
L̂   = Σᵢ wᵢ · (pᵢ/tᵢ) / Σᵢ wᵢ
```

- **噪声帽权不进 v1 默认**：P2 证明权重形状不敏感；`1/σ_shot² ∝ 1/p` 型帽权会把权重质心推向暗部，与高斯帽叠加后解释成本高。保留为 additive 参数位（`weightNoiseFloor`，默认关）。
- **clip 门即响应域答案**：p≥0.995 视为传感器裁剪（信息不可信），p≤0.001 视为欠曝噪声。这两个门同时是 HOLE 检测器。

### 1.2 响应函数问题（CONTEXT 质疑点）的操作性消解

Lightamer 全链 RAW 解码 = `CIRAWFilter` → linear Rec2020 float32（Phase 2 定案 + `RAWDecoder.swift` RAW-03 float 保深先例 `LightamerCore/Sources/Decode/RAWDecoder.swift:158-175`）。**残余风险**：CIRAW 内部 per-image boost/tone 预修饰（ProRAW boost 因子族）不可静态排除——若存在，pᵢ/tᵢ 的比例关系被破坏，权重域失真。

**消解 = 运行时一致性自检（不再依赖静态确认）**：合并前在双方均未裁剪的重叠亮度带内取中位像素，实测 `median(pᵢ)/median(p_ref)` 对比 EXIF 预期 `2^ΔEV`（ΔEV 由快门比 + ISO 比合成，光圈必须相等——见 §2.4）；偏差 >5% → 对该源发警告并降级为「未校正比例合并」（权重照常，产物 provenance 标注 `exposureRatioVerified=false`）。**两点灰卡标定**降级为 Manual-Only 单次确认项（plan 08-1 执行时跑一次真 RAW bracket 即可），不阻塞。

### 1.3 退化行为与信息洞语义

P2 实测：全源裁剪（L=8.0 @ ±2EV 括号，覆盖上限 ≈ 3.98·full-well）→ Σw=0、0 contributors。终语义：

- Σw=0 像素输出 **0.0（黑）** + 同 Pass 产出 **weight-map（单通道 float）** 临时面；
- weight-map 的零区 = 信息洞/ghost 候选区，进入 §4（RQ-08-4）的 ghost mask 生成与**用户提示面**（合并完成 toast 报百分比，如「0.3% 区域超出括号覆盖」）；
- 括号覆盖域换算：ΔEV=±2 时物理覆盖 ≈ 0.00025–3.98（full-well 归一）≈ **14.2 EV 场景跨度**——UI 预检时可静态展示。

### 1.4 数值 golden 设计（进 08-1 plan）

- 合成 fixture：已知 L 集（P2 同款 patch 表）× {1/4,1,4} 快门 → 断言 |L̂−L|/L < 1%（1% 噪声注入下）；
- HOLE 断言：全裁剪 patch → wsum==0；
- ghost 断言：单源 0.8/0.5 非裁剪偏离 → k=3 残差拒绝后 |L̂−clean| < 0.02。

---

## 2. RQ-08-2（P0★）MTB 对齐落地与性能

### 2.1 算法参数定表

| 参数 | 定值 | 依据 |
|---|---|---|
| 金字塔层数 | 8 级（100MP → 91×68 底层） | P1 实测配置；底层像素数足以稳定取中位 |
| 灰度化 | RGB→luma（0.2126/0.7152/0.0722）在解码后线性域直接做（MTB 阈值对单调增益不变，无需 gamma 预矫正） | Ward MTB 定义 + P1 验证 |
| 阈值 | 256-bin 直方图中位数（8-bit 量化仅用于阈值判定，位图 1bit/px） | P1 实测（构建 0.45s/全塔） |
| 搜索 | 逐级 ±1px 粗到细（底层独立 ±1，每升一级 ×2 后再 ±1）→ 全res覆盖 ±128px | P1 命中验证 |
| 位图比较 | packed UInt64 XOR + popcount，重叠窗内（位移收缩边界——P1 首版越界教训：大位移必须按 (dx,dy) 收缩比较窗） | P1 修正后精确命中 |
| 倾转 | **v1 = 平移 only**；小角度倾转（±1°、0.25° 步进、在 level 4–6 搜）作 additive 旋钮（估 +0.5–1s，P1 未实测——plan 内定夺是否进默认路径） | D-08-CONTEXT-1 说「含小角度倾转」，本 research 降级为旋钮（探针未覆盖，不写默认数字） |

### 2.2 性能终数（RQ-08-2②）

100MP 3-bracket（2 比较 + 1 参考塔）：

| 段 | 单线程 CPU 实测 |
|---|---|
| 参考塔位图（一次性） | 0.45s |
| 每比较源（塔 + 位图 + 搜索） | 1.65s |
| **对齐段合计（3 源）** | **≈ 3.8s** |

多核/GPU 结论：位图构建与 XOR 搜索都是天然并行形（按行切分），4P 并行估 <1s；**GPU 腿列为 plan 内可选优化**（MTLComputeKernel 位图 + popcount，一次 dispatch/level），不进关键路径。产品形态判定：**后台任务但「可等待」**——全 merge 预算见 §12。

### 2.3 对齐失败判定与降级（RQ-08-2③）

- **失败信号**：最优 XOR 距离/像素 > 阈值（默认 0.25，位图噪声地板 ≈ 0.5 为全随机；0.25 = 结构匹配但弱）；或命中位移 = 搜索界（±128px 满幅）。
- **降级**（hdrmerge 惯例）：**不对齐直合并 + 警告**，不硬失败——三脚架场景位移本来就 ≈0，低纹理图（长曝光天空）搜不出位移 ≠ 没位移。provenance 记 `alignment: "skipped-low-texture"` / `"degraded"`。
- 解码失败 = 硬失败（§12 分型）。

### 2.4 EXIF 一致性预检（RQ-08-2④）

| 字段 | 判定 | 容差 |
|---|---|---|
| 机身/镜头型号 | 必须相同 | 严格 |
| 焦距 | 必须相同 | 严格（EXIF 焦距整 mm 量化） |
| 光圈 f-number | 必须相同 | 严格（1/3 档量化；光圈漂移 bracket = 超出线性合并前提，**默认拒绝 + 用户 override 放行 + 警告**——override 后 ΔEV 换算只算快门/ISO，光圈差进比例自检 §1.2 兜底） |
| ISO | 必须相同 | 严格（不同 ISO = 噪声权重失真；override 同上） |
| 快门 | **必须不同**（bracket 本体） | ΔEV 由 `log2(t_ref/t_i) + log2(ISO_i/ISO_ref)` 合成 |

---

## 3. RQ-08-3（P0）合并产物落位与浏览可见性

### 3.1 代码走查事实

- `SessionTreeScanner.isExcludedDirectory`（`App/Sources/Lightamer/Session/SessionTreeScanner.swift:98-105`）：排除 `.` 前缀、`.tmp-`、**根级直接子目录且属于 reserved 集**（`SessionLayout.reservedRootDirectoryNames` = Capture/Crop/Output，`App/Sources/Lightamer/Session/SessionLayout.swift:40-44`）。**非保留、非点前缀的子目录（如 `Stacks/`）可浏览**（`isDirectlyUnderRoot && reserved` 不命中，且 `skipDescendants` 不触发）。
- 文件排除 `isExcludedFile`（:72-74）：`.lra` 一律排除（sidecar 附件语义）；`.tif/.tiff` 在 `rasterExtensions`（:61-63）→ **float TIFF 产物默认可浏览**。
- RAW-03 float 读保深已锚（`RAWDecoder.swift:158-175`：bpp=32/96 TIFF、bpp=32/128 EXR 保深直通，`RAW03Tests` 极值存活）。

### 3.2 三落位推演表

| 落位 | grid 可见 | 副作用 | 判定 |
|---|---|---|---|
| **会话根**（`<base>_hdr.tif`） | ✅ 零疑义 | 根目录与源文件混放 | **采纳（默认）** |
| `Capture/` | ❌ 根级 reserved 目录整支 `skipDescendants` | 违背 SC#1「进 grid 继续编辑」 | 否 |
| `.lightamer/stacks/` | ❌ 点前缀排除 | 需显式收录 = 新扫描语义，违背「普通文档」 | 否 |
| （变体）`Stacks/` 非保留子目录 | ✅ 可浏览 | 根目录整洁；但引入新顶级目录约定 | 记为 planner 可选变体（语义零差，仅观感） |

### 3.3 命名防撞

**复用 ExportNamer 惯例**（`LightamerCore/Sources/Export/ExportNamer.swift:53,82-83`：`<stem>[_<tag>].<ext>` + 冲突 `-1/-2/-3…` 递增）→ `<base>_hdr.tif`、`<base>_hdr-1.tif`、`<base>_hdr-2.tif`。时间戳否决（不可读、破坏同批产物排序）。focus-stack/降噪 tag：`_fstack` / `_stack`（+ 可选 `_avg`/`_med`/`_sig`）。

### 3.4 provenance sidecar 字段终表（`LightamerSidecar` v3 → v4 additive）

`LightamerCore/Sources/Sidecar/LightamerSidecar.swift:113`（`schemaVersionCurrent = 3`）升级 4，新增 optional 字段（nil = 普通文档，round-trip 完全向后兼容）：

```jsonc
"provenance": {                       // v4 additive, optional
  "kind": "hdr-merge" | "focus-stack" | "stack-average" | "stack-median" | "stack-sigma",
  "algorithm": { "name": "robertson02-mtb", "implementationVersion": "1",
                 "params": { ...算法参数快照... } },
  "sources": [ { "relPath": "DSC_0001.NEF",            // 会话根相对路径
                 "stableHash": "14243…",               // UInt64String，FNV-1a over 文件字节（L013）
                 "exposureEV": -2.0 } ],
  "alignment": "full" | "degraded" | "skipped-low-texture" | "skipped-user-override",
  "exposureRatioVerified": true,
  "holeFraction": 0.003,
  "createdAt": "2026-09-27T12:00:00Z",
  "appVersion": "…"
}
```

- one-way 格式锁 + UInt64String 纪律照抄（CONVENTIONS Phase 2 增量）；`relPath` 相对会话根（跨机/跨卷可迁）。
- **源漂移检测**：载入产物时对 `sources[].stableHash` 重算比对，不符 → 「源已变更」标脏 + 重合并入口（§12 服务入口直取 provenance 重放）。
- **删产物重合并幂等**：重跑同源同参 = ExportNamer 递增出新文件（不覆盖）——幂等在 provenance 层（同 provenance hash 可检测「已有等价产物」并提示复用），不在文件系统层。

### 3.5 编辑链零改验证

产物 = 普通 float TIFF 文档：浏览集进 grid（§3.2）→ `RAWDecoder.decodeRaster` 保深读 → 常规 preview/thumbnail/full/export 四管线（`PipeResolution.swift:10-27`）→ `.lra` sidecar 独立于 provenance 正常挂接（history/评分/层栈全可用）。**零新机制**；唯一新代码 = 合并服务本体 + sidecar v4 字段。

---

## 4. RQ-08-4 ghost mask 自动生成与用户编辑闭环

1. **阈值域**：**线性亮度域的归一化残差**——对每源算 `rᵢ = |pᵢ/tᵢ − L̂| / max(L̂, ε)`，rᵢ > k·σ̂（σ̂ = 5% 噪声地板 + 拍噪声模型，P2 实测 k=3、5% 地板有效拒绝 0.6 幅度非裁剪 ghost）→ 该源该像素权零化。**噪声域而非权重域**（权重域在帽沿处梯度大，阈值不平稳）。
2. **生成物**：偏离像素位图 → 3×3 膨胀 2 轮（形态学）→ 16-bit PNG 落 **`<base>_hdr.tif.lra.masks/<maskID>.png`**（`RasterMaskRef` 既有文件约定，`LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift:13-17`：`{fileName, maskHash, invert}`，maskHash = StableHash over PNG 字节）。旁挂 PNG 采纳（vs 仅 sidecar 参数）：重算可重现性由 provenance 保证，但**用户编辑过的 mask 必须持久化**，且 Phase 7 AI mask 旁挂 PNG 是已验证形态（磁盘成本：1MP mask PNG ≈ 数十 KB）。
3. **编辑闭环**：合并文档的 `.lra` 初始 `layerStack` 带一个「Ghost Suppression」调整层（Phase 6 层栈面零新机制），其 mask = 上述 `RasterMaskRef`——用户在 Phase 6 蒙版面反选/羽化/组合（IOP-MASK-04 全套既有）。
4. **de-ghost 关闭档**：参数 `deGhost: false` → 跳过残差统计与 mask 生成（零 IO 零开销），层栈不含该层。N=3 括号的诚实局限：3 样本残差统计弱（P2 v1 教训——N=3 时 sigma-clip 退化），de-ghost 质量随 N 升，文档与 UI 均注明。

---

## 5. RQ-08-5（P1★）focus stacking 度量与融合参数

1. **度量终选 = modified Laplacian 幅值和（ML），窗口求和（3×3）成 quality map**：`ML = |2f(x)−f(x−1)−f(x+1)| + |2f(x)−f(y−1)−f(y+1)|`，SML = 3×3 ΣML²。P5 实测：真 defocus 代理下 sharp/blurred SML 比 **59×**（分离度充分）；成本 1.5ns/px → **0.15s/源@100MP 单线程**。tenengrad 作 additive 备选枚举（D-08-CONTEXT-2 Reversibility）。
2. **金字塔融合层数 = 5 级 + 权重平滑**：quality map 先 5×5 box 软化（P5 软权重融合已 PASS），拉普拉斯金字塔 5 级（1024px 边界过渡带经验值，参数化）。层数 additive 旋钮。
3. **对焦轨缩放差容忍**：微距近焦源放大率漂移使纯平移 MTB 失准；**v1 判据 = 残差自检**——对齐后对重叠带算归一化互相关，<0.9 → 警告「源间放大率差异大，边缘可能重影」，照常融合（软权重对深度边界小错位天然宽容）。homography/光流 = v2 缝（D-08-CONTEXT-2 已留后端插拔位）。
4. **读回 fence**：quality map 生成在 GPU（SML kernel），读回走 L014 fence（`drain()` 模式，07 AI `AIMaskInput` 先例）；**N 源 map 全驻留**（N×407MB @100MP 单通道 float —— N=8 = 3.3GB 偏肥；**定形 = map 以 half 存**（质量图无需 float32 精度）→ N=8 = 1.6GB；或按行流式融合（与 §6 同骨架）——**plan 取行流式**，map 只留行带）。

---

## 6. RQ-08-6（P0★）N 源大图内存形态

- **全驻否决（算术 + 实机）**：100MP float32 RGB 1.22GB/plane、RGBA 1.63GB；N=5 全驻源 + 输出 = 7.3–9.8GB——16GB 实机（P3）直接不可行；与 `PipeResolution.swift:30-45` full 管线不缓存中间面的既有判断同源。
- **终形 = 行带流式两遍**：
  1. **对齐遍**：逐源解码 → 逐级下采样**只留位图**（1bit/px，8 级全塔 ≈ 17MB/源）→ 释放像素面；
  2. **合并遍**：逐行带（256 行）解码/累积 `Σw` 与 `Σw·p/tᵢ`（float32 累积面 ≈ **2.0–2.4GB**，全图驻留的唯一大头）+ 行带缓冲 179MB（P3 实测常量）→ 末段流式写 float TIFF（`CGImageDestination` 分行 append，EXP-01 既有写面）。
  - **median/sigma-clipped 流式**：行带内 N 值栈（N=8、256 行、RGB = 286MB）→ 带内排序/σ-剔除 → 单遍完成（P3 实测 136.6ns/px → 13.9s 单线程/~4.0s 4P@100MP）。**无需两遍/滑动窗口**。
- **preview 桶先行 = 否**：不出 preview 分辨率产物（双文档语义污染 §3 落位）；合并是带进度的后台操作（§12），完成即全幅产物入 grid。
- **TilingPlan 复用边界**：`TilingPlan`（`LightamerCore/Sources/Pipe/Tiling/TilingPlan.swift`）是纯 tile 几何，行带 = 特例（tile 高 = band）——**用其几何函数生成行带网格，不引入 in-pipe tile driver**（合并不走 PixelPipe）。

---

## 7. RQ-08-7（P0★）EDR 显示腿形状与 SDR 不变断言

1. **管线形状**：`EditorMTKView.swift:20-21` 预留位兑现——toggle on 时 blit PSO 切 `.rgba16Float` 色附件（`EditorMTKView.swift:294-306` 的 `.bgra8Unorm` PSO 加一个 16F 变体）+ `wantsExtendedDynamicRangeContent = true` + `CAMetalLayer.colorspace = extendedLinearSRGB`（P4 验证存在且可挂）；**终端段旁路** = gamma/colorout 后不进 SDR 钳制（PixelPipe 终端段短路开关，13-2 SoftProofStage 同位语义）。display tint/D-COL2 挂接（`EditorMTKView.swift:336-339`）在 EDR on 时**跳过 display colorspace 附加**（compositor 不再匹配，值即显示意图）；择优结论：**extendedLinearSRGB 直接用**（显示器原生 EDR 色彩空间查询无稳定公开 API，extendedLinearSRGB 是 WWDC 惯例路径）。
2. **headroom 联动**：`NSScreen.maximumExtendedDynamicRangeColorComponentValue` 查询 + `NSWindow.didChangeScreenNotification`/`NSApplication.didChangeScreenParametersNotification` 触发视图失效（跨屏拖动重查）。P4 实测 API 全通。
3. **非 XDR 屏（headroom=1.0）**：P4 实测本机外接 SDR headroom=1.0/1.0——toggle 保持合法，>1.0 值被合成器钳到 SDR 白（无自动回落必要）；UI 显示「当前显示器无 EDR 余量」徽标。
4. **SDR 不变断言**：EDR off = 零代码路径差（16F PSO/旁路仅在 toggle on 分支）→「逐字节一致」由**既有 golden + 新增 blit 快照对比测试**钉：toggle off 渲染 texture 与既有输出 hash 相等；EDR on 不进 export/history/sidecar 三断言（soft proof 四断言形状，`SoftProofStage.swift` 先例）。XDR 目检 + 外接 HDR 双实测 = **Manual-Only**（P4 环境无 XDR 屏，实测已证）。

---

## 8. RQ-08-8 grain 确定性种子与缓存键

1. **seed 派生终表**：`seed = StableHash(canonicalParamsBytes ⊕ imageID-UUID-bytes)`（FNV-1a 64，L013；`StableHash.swift` 既有）。image id = **sidecar `imageID`（UUID，持久化后跨机稳定）**，非文件哈希（文件哈希每次载入重算 100MP 太贵，且换文件名不改身份——dt 用文件名 hash（`grain.c:446`）是它的弱身份，Lightamer 不跟）。同图同参 → 同 seed 逐字节重现；换图同参 → 异图案（UUID 异）。
2. **缓存键**：无漏钉面——seed 是 (params, imageID) 的纯函数，而 `PipeCacheKey` 已含 (image 身份， paramsHash) → 同键 ⇔ 同 seed，**不可能**同参跨图假命中。回归测试钉不变量：同参异图输出必异 + 同图同参两次渲染逐字节相等。
3. **谱形移植正本（CONTEXT 精化⚠）**：dt 噪声 = **3-octave simplex 梯度噪声**（`grain.c:292-327`：octave 频率 f={0.4910,0.9441,1.7280}、幅值 a={0.2340,0.7850,1.2150}，终值 `32·Σ` 缩进 [-1,1]（:312）），**不是白噪声**——CONTEXT「白噪声」措辞不精确。移植 = simplex 3-octave verbatim（film 谱形是 dt 对标语义本体），确定性由坐标域 (x,y 全图归一 + zoom) + seed 保证。
4. **域适配**：dt 在 Lab L 上注入（`grain.c:494` 只写 out[0]）+ `paper_resp` midtones 曲线 LUT（:331-345，`GRAIN_LUT_DELTA_MAX=2.0/MIN=0.0001/PAPER_GAMMA=1.0`，128×128）；Lightamer = **luma 域**（Rec2020 luma 系数）注入 `pixel += noise·strength·0.15 · paperRespCurve(luma)`；scale 滑杆 = ISO 标注（`GRAIN_SCALE_FACTOR=213.2`，`grain.c:44,540-543` 语义 verbatim）。

---

## 9. RQ-08-9（P1★）bloom 线性域阈值映射与 blur 择优

1. **dt 正本域**：bloom 作用于 **Lab L ∈ [0,100]**（`bloom.c:151-180`：`L = in[0]·scale`、`scale = 1/2^(−(min(100,strength+1)/100))`（strength→指数提亮）、`blurlightness = L > threshold ? L : 0`、3× box mean `dt_box_mean(..., hr, BOX_ITERATIONS)`（:155）、screen 混合 `out_L = 100 − (100−L)(100−blur)/100`（:165-172））。
2. **线性域映射（RQ 终答）**：`L_lin = luminance / 4.0`（4.0 = filmic 白锚暂定，常量参数化）→ `thr_lin = (threshold/100)³`（threshold=90 → 0.729 → 只取 >2.9·0.25 ≈ 白域高光，对位 dt L>90 的「顶部 10%」直觉）；`strength` 保留 dt 指数提亮形；screen blend 在线性域直接 `1−(1−a)(1−b)`（dt 的 100−… 式就是它的 [0,100] 归一形）。**默认手感 = Manual-Only 观感轮预定项**（数值锚 = 上式，手感校准不改结构）。
3. **blur 择优（P5 实测）**：**降采样级联**（÷8 box → 1/8 分辨率小 σ gaussian → bilinear 上采）0.29s vs 3-pass box r=64 1.87s（6.5×），且级联省 64× 中间带宽 → **bloom blur = 级联**（自研 kernel，MPS 不引入——`MPSImageGaussianBlur` 不支持任意级联形状且 dtype 约束多，STACK「selective use」判定不适用）。dt 的 box-mean O(N) 形保留作大 radius 档备选。
4. **>1.0 值源语义**：HDR 文档上 bloom 行为 = 同一公式零改（screen 对 >1 值良定义，bloom 光晕可超 1.0 继续进 HDR 域）——无需特判。

---

## 10. RQ-08-10 dehaze 参数面与 scene-referred 域适配

1. **参数终表**（`hazeremoval.c:66-67`）：`strength` −1..1（默认 0.2）、`distance` 0..1（默认 0.2）、`adaptive`（窗口随分辨率缩放开关，:576）。14.0 槽位（`V50Order.swift:48`）= dt 同位 scene-referred 前段。
2. **数学直译表**（四 kernel + CPU 段）：
   - 暗通道/亮通道 box：`hazeremoval.cl:28-93`（`box_min_x/y` + `box_max_x/y`，滑动 min/max O(N)）；
   - 大气光 A0 + distance_max：`_ambient_light`（暗通道最亮区百分位，`hazeremoval.c:~400-447`）；**preview 管线算 A0/distance_max、full/export 复用**（dt 经 gui_data + hash 同步，`hazeremoval.c:595-645`）——Lightamer 同形（模块内 cached 值 + 输入 hash 校验），否则 full 管线 ROI 内 A0 估计不稳（dt 明文坑）；
   - 透射率：`t = 1 − min_c(p_c/A0_c)·strength`（:338-352）→ box min 细化（w1）→ **guided filter**（w2, ε=√0.025）——guided filter 是 dt 内置 C 实现，**移植决策：v1 用 box mean 两遍近似替代 guided filter**（kernel 表少一个复杂件，视觉差记 Manual-Only 对比项）或全移植（plan 定，工程量 +1 天估）；
   - 还原：`t_min = clamp(exp(−distance·distance_max), 1/1024, 1)`，`out = (in − A0)/max(t,t_min) + A0`（:678-692）。
   - 窗口：`w1 = 2+ceil(4·wscale)`、`w2 = 3+ceil(6·wscale)`，`wscale = adaptive ? roi_in.scale/pipe.iscale : 1`（:576-583）。
3. **scene-referred 适用性**：dt 本就跑在 scene-referred 线性 RGB 管线（模块序 14.0 在曝光之后）——**暗通道先验对线性域直接适用，零域翻译**；A0 是线性亮度三元组，语义自洽。
4. **golden**：合成雾 fixture（已知 A0、已知 t 场、线性合成 `I = J·t + A0(1−t)`）→ 反演 |Ĵ−J| 容差断言（CPU float64 参考实现双写）。

---

## 11. RQ-08-11 text overlay 槽位与渲染管线

1. **槽位终值 = 66.7**：全表扫描（`V50Order.swift:146-165`）——66.0 = soften（dt 行）、66.5 = skinSmooth（非 dt 行先例）、67.0 = splittoning（dt 行）。**66.5–67.0 空隙**内取 66.7（避开 66.5 邻近，便于后续 66.x 非 dt 行继续 additive）；`< 70.0` 终端尾窗达标（`LayerCompositeDriver.terminalTailFloor`）→ 层蒙版资格成立。`V50OrderTests` strip-to-93 钉同步 +1 行。
2. **渲染路径**：CoreText 排版 → 灰度+alpha 位图 → `MTLTexture`（`YiyinTextRenderer` 复用面核对结论：**复用其排版/字体管理（YiyinFontStore），渲染输出改挂 MTLTexture**——yiyin 渲染目标是 CGImage 出图，iop 需要 GPU 纹理 + 每参数变更重烘焙缓存（PSO 不变、纹理缓存按 `StableHash(textParams)` 键）。COLOR-2 float[9] 矩阵惯例不涉及（无色彩矩阵变换，纯 alpha 合成 + 颜色 uniform）。
3. **参数面 v1**：内容（多行）/字体/字号/颜色/位置（归一 xy）/旋转/不透明度；**描边/阴影不进 v1**（SC#4 无字面要求，additive 位）——与 yiyin watermark（模板/EXIF 字段/77.0 终端）分工照 D-08-CONTEXT-9。
4. **挂层蒙版合成**：非终端段 + `blendTriple` 既有面（Phase 7 层栈 API）——模块实现 `IOPModule` 常规注册即得，零新机制。

---

## 12. RQ-08-12 合并服务运行形态与队列关系 + 性能预算

- **形态**：`StackMergeService`（actor）+ **独立低优先级 `MTLCommandQueue`**（Phase 11 export queue 惯例）+ 进度/取消面**复用 ExportQueue 形状**（`LightamerCore/Sources/Export/ExportQueue.swift:43-115`：actor + cancel epoch + `(done,total)` progressHook + 无自动重试/显式 `retry`）。服务接口 = `N 源 → 1 float32 文档`（D-08-CONTEXT-1 Reversibility 的抽象位：Mertens/深度图后端只是末段替换）。
- **失败分型**：解码失败（硬失败，retry 入口）｜对齐失败（降级续跑 + provenance 标注，§2.3）｜写盘失败（硬失败，retry）。
- **互斥语义**：源图在编辑器打开**无冲突**（合并服务对源只读解码，与 pixelpipe 缓存面零共享；唯一耦合 = 内存压力，enforceBudget 60s sweep 既有兜底）。
- **100MP 3-bracket 全程预算表**（探针实测 + 解码估）：

| 段 | 估时（100MP, 4P 并行估） | 依据 |
|---|---|---|
| 解码 ×3（两遍流式：对齐遍 + 合并遍 = ×6 次 CIRAW） | 12–30s | CIRAW 100MP 单张 2–5s（Phase 2 量级，plan 首任务实测钉） |
| MTB 对齐 | 0.5–3.8s | P1 实测 3.8s 单线程上界 |
| 权重合并 | 0.4–1.1s | P2 实测 1.1s 单线程上界 |
| ghost/quality 面 | 0.3–4s | P3/P5 实测 |
| float TIFF 写 | 2–4s | EXP-01 既有量级 |
| **合计** | **≈ 15–40s** | **后台任务 + 进度条**；预算门 = <60s @100MP×3 入 perf.md |

sigma-clip N=8 全程 ≈ 解码主导同上 + 聚合 4s；focus stacking N=8 同形。

---

## 13. RQ-08-13 HDR-04 验证矩阵 + LUT 精度结论（Phase 12 移交消费）

1. **验证矩阵终表**（08-1 建基、08-5 收口补 lut3d 列）：

| 合成文档源 | 流经模块 | 断言 |
|---|---|---|
| HDR stack torture 图（ROADMAP:60 既有 golden harness） | exposure → filmicrgb → sigmoid → toneequal 全链 | 数值 parity = 全 float32 CPU 参考实现逐点容差（Phase 3 golden 形状） |
| 合成 float32 文档（已知值 patch：0.001/0.5/1.0/4.0/16.0/65504 通道灰阶 + RGB 彩条） | 同上 + lut3d（HDR 域 .cube） | 同上 + LUT 列（下条） |
| 真合并产物（08-1 探针 fixture 出的 32F TIFF） | preview 管线 | 平面内存预算实测（下下条） |

2. **preview float32 预算**：2560px long-edge float32 平面 = 2560×1707×16B ≈ **70MB/平面**（`PipeResolution.swift:36-39` 注记实测复核）；enforceBudget 五档阈值注入缝既有——复核结论写进 08-5 收口（预期：合并不进 preview 缓存面，预算零增；EDR viewport 一个 16F drawable ≈ 62MB @3008×1692×8B，增量可忽略）。
3. **LUT 精度结论（12-5 移交④/遗留#4 消费）**：`.cube` DOMAIN remap 把输入域归一到 [0,1] 采样坐标（`CubeLutParser` 既有，`LightamerIOP/Sources/Lut3d/CubeLutParser.swift:10-14`），坐标精度无损；精度面在 **LUT 数据存储 = rgba16Float texture3d**：half 相对误差 ~5e-4 < 1e-3 相对容差（12-5 D7 先例口径）→ **默认 rgba16Float 达标，升格 rgba32Float 不启用**；08-5 用 12-5 tetrahedral golden 面对 HDR 域样本点（输出 >1.0 的 DOMAIN_MAX>1 LUT）实测误差，**若任一点 >1e-3 相对误差 → 启用 D7 升格预案**（判定写死进测试断言，不留人肉判断）。

---

## 14. 效果簇 dt 映射总表（FX-01..04 参数面 + 移植规格 + golden）

| iop | dt 参数面（正本 file:line） | Metal kernel 规格 | CPU float64 参考实现 | golden 断言 |
|---|---|---|---|---|
| **vignette** 68.0 | scale 0-200(80)/falloff 0-200(50)/brightness −1..1(−0.5)/saturation −1..1(−0.5)/center ±1/whratio 0-2(1)/shape 0-5(1)/unbound(true)/autoratio——`vignette.c:57-72`；数学 `:715-820` | 单 kernel 直译 `extended.cl:308-349`（cplen 幂距 + 线性 falloff + 加/乘亮度 + 均值去饱和）；dither 参数不移植（CONTEXT⑤）；**dt CPU/OpenCL 分歧注意**：cosine 权重平滑 CPU 仅 dither 分支（`vignette.c:790-795`）而 OpenCL 恒用（`extended.cl:331-332`）——**取 OpenCL 形**（平滑无劣势） | float64 同式直译 | 合成渐变图 × 默认参数 → 已知 falloff 曲线采样点 1e-6 容差；brightness ± 两支路；unbound 裁剪语义 |
| **grain** 65.0 | scale(ISO≈coarseness)/strength(0-100,25)/midtones_bias(0-100,默认 0)——`grain.c:65-70,542-543`；zoom=`(1+8·scale/100)/800`(:450) | 3-octave simplex（f/a 表 :318-321）+ paper_resp LUT 预烘焙（128² 或直算，:331-345）+ luma 注入；seed = §8 派生 | float64 simplex 参考实现（与 kernel 同 seed 逐位比对） | 同 seed 同参逐字节确定性；同参异图图案必异；谱形功率谱对照 dt 数值锚 |
| **bloom** 61.0 | size 0-100(20)/threshold 0-100(90)/strength 0-100(25)——`bloom.c:47-51`；rad=256·(size+1)/100(:140) | 级联 blur（§9 实测择优）+ threshold kernel（`bloom.cl:22-38` 直译，线性域映射 §9）+ screen blend | float64 三段参考 | 已知高光点光源 → 光晕半径/幅值断言；threshold 线性映射数值锚；HDR >1.0 输入行为 |
| **dehaze** 14.0 | strength −1..1(0.2)/distance 0..1(0.2)/adaptive——`hazeremoval.c:66-67,576` | 四 kernel 直译表（§10.2）；guided filter v1 取舍 plan 定 | float64 A0/t/还原全链 | 合成雾反演容差（§10.4） |
| **text overlay** 66.7（新非 dt 行） | 无 dt 正本——参数面 §11.3；YiyinFontStore 复用 | CoreText → 纹理 → alpha 合成 kernel（uniform 颜色/旋转/不透明度） | Swift 参考渲染 | 位置/旋转/不透明度解析断言 + 层蒙版局部化走查 |

---

## 15. 波次分解验证（任务简报 RQ-16-13 → D-08-CONTEXT-10 复核）

**结论：5 plans / 3 waves 维持不修正**（探针数据消除了唯一潜在拆分压力——对齐/合并数学在单 plan 内可完成，无需拆「对齐基建」与「HDR 合并」两 plan）：

- **W1: 08-1**（堆栈簇底座 + HDR merge：服务骨架 + MTB + Robertson + ghost + 落位/provenance v4 + HDR-04 矩阵基座——IOP-HDR-01/04）∥ **08-2**（vignette + grain + bloom——FX-01/02/03）。
- **W2: 08-3**（focus stacking + 三模式堆栈降噪，复用 08-1 对齐段与服务接口——IOP-HDR-02/03）∥ **08-4**（EDR 显示腿——IOP-HDR-05）。
- **W3: 08-5**（dehaze + text overlay + HDR-04 LUT 精度判定 + 全 Phase 收口签核——FX-04/05）。

### 每 plan 任务/AC 草案（给 planner 的起点，非终稿）

| Plan | 任务草案 | AC 草案 |
|---|---|---|
| 08-1 | T1 `StackMergeService` actor + 队列/进度/取消；T2 MTB 对齐（P1 参数表）+ EXIF 预检 + 降级；T3 Robertson 合并（P2 权重终形）+ HOLE/weight-map；T4 ghost mask（§4）+ `RasterMaskRef` 落盘；T5 产物落位 + ExportNamer 防撞 + sidecar v4 provenance + 漂移检测；T6 HDR-04 验证矩阵基座 + §1.4 golden | 合成 bracket 位移精确命中；L̂ 容差 <1%；HOLE 检出；产物进 grid 且可全链编辑；provenance round-trip + 源漂移标脏；100MP×3 全程 <60s |
| 08-2 | T1 vignette（kernel+参数面+golden）；T2 grain（simplex+seed+确定性 golden）；T3 bloom（级联 blur+线性阈值+screen）；各 T 含面板 D-H1 三件套 + zh catalog | 各 iop dt 参考采样点容差断言；grain 确定性双断言；60fps preview 预算不回退 |
| 08-3 | T1 SML 度量 kernel + fence 读回；T2 金字塔融合；T3 average/median/sigma 三模式聚合（行带流式）；T4 focus/stack 预检与警告 | §5 断言（清晰区归属）；sigma-clip 星野 fixture 拒绝离群；N=8 内存行带常量 |
| 08-4 | T1 16F PSO 变体 + toggle；T2 headroom 查询 + 跨屏失效；T3 终端旁路；T4 SDR 逐字节断言三件套 | P4 API 全通复验；EDR off 逐字节；EDR on 不进 export/history/sidecar；Manual-Only XDR 双屏登记 |
| 08-5 | T1 dehaze 四 kernel + A0 preview 复用；T2 text overlay 66.7 + CoreText 纹理；T3 LUT HDR 精度判定（1e-3 断言）；T4 全 Phase 验证 + 签核 | 雾反演 golden；overlay 蒙版局部化；LUT 判定写死；全 suite 绿 + 签核停（C 档第 3 停） |

---

## 16. 风险表

| # | 风险 | 等级 | 缓解 | 归属 |
|---|---|---|---|---|
| R1 | COLOR-4：EDR 色域/亮度标定（本环境无 XDR 屏，P4 已证） | 高 | API 面已验证；XDR+外接目检 Manual-Only 登记 | 08-4 + 人工 |
| R2 | CIRAW per-image boost/tone 预修饰破坏 p/t 比例 | 中 | §1.2 运行时比例自检（>5% 警告降级）+ 灰卡两点 Manual-Only 一次 | 08-1 |
| R3 | 16GB 机内存：全驻否决是硬约束 | 中 | §6 行带流式终形（累积面 2.4GB 上界） | 08-1/08-3 |
| R4 | bloom 线性阈值手感（映射曲线无 dt 直接对照） | 中 | §9 数值锚 + Manual-Only 观感轮 | 08-2 |
| R5 | guided filter 移植量（dehaze 精细化） | 低 | v1 box 近似备选已给；plan 定 | 08-5 |
| R6 | N=3 括号 de-ghost 统计弱 | 低 | UI/provenance 注明；质量随 N 升 | 08-1 |
| R7 | 解码耗时（CIRAW 100MP）未实测主导总时长 | 低 | 预算表 <60s 含上界；08-1 T1 首测钉 | 08-1 |
| R8 | MTB 倾转搜索未探针化 | 低 | v1 平移 only + 旋钮位（§2.1） | 08-1 |

---

## 17. 与 CONTEXT 的冲突/精化发现（回注 discuss 记录面，非裁决推翻）

1. **D-08-CONTEXT-6「白噪声」措辞不精确**：dt grain 正本是 **3-octave simplex 梯度噪声**（`grain.c:292-327`），非白噪声。移植按 simplex verbatim（§8.3）——确定性契约不变，谱形更忠实。**无裁决影响**（seed/确定性结论原样成立）。
2. **D-08-CONTEXT-1「含小角度倾转」降级为旋钮**：P1 未覆盖倾转搜索成本，v1 默认 = 平移 only（§2.1）——倾向非推翻（Reversibility 参数位保留），planner 过目。
3. **dt vignette CPU/OpenCL 自身分歧**（cosine 平滑条件）：移植取 OpenCL 形（§14）——dt 内部不一致非本方引入。
4. **噪「帽权」从默认路径移除**（P2 实测形状不敏感，§1.1）——D-08-CONTEXT-1 Reversibility 位保留 additive 参数，默认关。
5. **落位推荐会话根**（非 `Stacks/`）：两案皆满足浏览语义（§3.2），root 为默认、Stacks/ 为 planner 观感变体——比 CONTEXT③ 的三选一框架多出一个合法解。

---

## Sources（research 环新增引用，STACK/上游已有不重复）

- Robertson, G., et al. "Dynamic Range Improvement Through Multiple Exposures." SIGGRAPH 2003（线性域加权合并；OpenCV `createMergeRobertson` 同族）。
- Ward, G. "Fast, Robust Image Registration for Compositing High Dynamic Range Photographs from Handheld Exposures." jgt 8(2), 2003（MTB）。
- Pertuz, S., et al. "Focus measure: a qualitative approach." / enfuse（`Enblend/Enfuse` 参考手册）——modified Laplacian + quality-weighted 金字塔融合。
- Pech-Pacheco, J.L., et al. 2000（SML 度量）。
- 探针源码：/tmp 即弃（本档 §0 数字为唯一账面；perf.md 基线由 08-1 首任务以真实解码链重钉）。
