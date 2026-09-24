# Plan 07-3 — Decisions（执行期决策正本）

> 体例对齐 07-1/07-2-DECISIONS。T1-T4 决策由续班 executor 自 commit message（2fae8ca/
> 62117cd/7aab710/f4c3c3a）与 FINDINGS 回收登记；T5 = 终签核决策。plan 纪律要求：
> UI 挂点执行期定稿入本文件，不臆造。

## D-07-3-T1-1: `AIMaskEditing` = 全部 AI 生成路径的唯一 bake 通道（App/State 层）

**决策**：层 A 一键 / instance 浮层确认 / 层 B 精修确认 / skinSmooth「定位皮肤」四条
生成路径全部漏斗到 `AIMaskEditing.commitRasterMask`——上采样（双线性，永不 nearest）
→ bake → `MaskSpec.raster` 写**选中层** mask 槽 = 恰 1 条 `__layerStack__` stackSnapshot
结构项 → 热层 + display tint + 蒙版编辑模式武装。

**理由**：AI-06 交互形态红线（用户看到的是普通 raster 蒙版，永非 AI 伪影）只需实现
一次；四路径共享 = 文件名稳定派生（per-layer）天然承载 D-07-CONTEXT-5 同 maskID
覆盖重 bake（hash 翻转 → Phase 6 缓存链失效，零新机制）。

## D-07-3-T1-2: T1+T2 合并为单 commit（原子缝）

**决策**：plan 原定 T1/T2 两 commit 实际合并为 2fae8ca。

**理由**：第 4 编辑模式（segment）是跨 LayerEditingState/EditorAreaView/toolbar 的
compile-exhaustive switch——AI 组按钮（T1）进入 ready 态即路由该模式，两任务共享
一条原子缝，拆开则中间态不可编译。无逻辑混装（各自测试面独立可辨）。

## D-07-3-T1-3: display tint 扩展至任意 payload（raster/parametric 回落 effectivePlane）

**决策**：`PipeCoordinator` 显示蒙版染色从 drawn-only 扩展为任意 MaskSpec payload——
raster/parametric 回落 `MaskCombiner.effectivePlane`（与合成同源装配）。

**理由**：AI 蒙版 = raster payload，不扩展则 overlay 开关对 AI 蒙版完全不可见（GUI
红线 ΔR 量化必挂）。同源装配 = 显示与合成一致性免费获得。**此为 T4 GUI 轮 ΔR 量化
达标的前置修复**（在本 commit 内先行落地）。

## D-07-3-T1-4: 层 B 下载门控复用 app 级 `AIDownloadModel`（environment 注入，一个状态机）

**决策**：MaskToolbar 层 B 入口三态（needsDownload→引导 / downloading→spinner /
ready→进入编辑模式 / failed→retry）直接消费 07-1 `AIDownloadPrompt` 同一观察对象
（environment 注入），不建第二状态机。

**理由**：07-1 交付面承诺「AIAssetStore 三态 = 同一 actor 无副本」；toolbar 与首启
弹窗分叉会造成双源真相（下载中一真一假）。首启「暂不」→ 层 B 置灰引导、层 A 全程
可用 = D-07-CONTEXT-1 交互兑现。

## D-07-3-T2-1: segment 路由插位 mask>liquify>retouch>**segment**>crop；scribble 升级缝不接

**决策**：第 4 编辑模式插 retouch 与 crop 之间（交互邻近性：segment 与 mask 绘制同属
蒙版域但依赖服务 ready 态）；种子枚举预留 scribble case + 头注升级缝，数据腿/手势
v1 不接（D-07-CONTEXT-4）。Y 翻转留在 `AIMaskPoint`——overlay 只记录 view-normalized
点（换算已单测，UI 层零重复）。

## D-07-3-T3-1: skinSmooth variant Picker 以禁用态呈现（v2 位可视化）

**决策**：Variant enum v1 单 case（twoBandGaussian），Picker 渲染为 disabled（v2
多频/bilateral 位对用户可见不可选）。

**理由**：D-07-CONTEXT-6 升级缝的可视化承诺；隐藏 vs 禁用——禁用传达「规划中」，
避免 v2 上线时 UI 突变。

## D-07-3-T3-2: 「定位皮肤」在 decode 帧上锚定 + 走 AIMaskEditing 同通道

**决策**：SkinRegionService.locate 输入 = 解码帧（demosaic 后、无编辑——继承定案
「mask 语义内容锚定」）；bake 走 D-07-3-T1-1 同一 commitRasterMask 通道。

**理由**：皮肤区域与蒙版同属层属性，双通道会造成挂层语义分叉；yaw 门 typed warning
→ toast（含脸序号/角度，非静默）、空 landmarks → 错误 toast——永不产坏 mask
（07-CONTEXT「生成失败 ≠ 降级全一」红线）。

## D-07-3-T3-3: PanelWiring 启用态差异测试选低幅条纹板（防空转且不空转）

**决策**：`testSkinSmoothEnabledCompositeDiffersFromDisabled` 用 ±0.01 ripple、
t=0.02 的条纹合成板。

**理由**：平场 = 恒等三元组 #3 的 no-op（断言空转）；大幅板骑 detail-preserve 腿
（衰减不作用，同样空转）；低幅板精确落在 raised-cosine 衰减的作用域——测的正是
模块要 ship 的衰减行为。

## D-07-3-T4-1: GUI-19 / GUI-20 登记（不阻塞 07-3 收口）

**决策**：两缺陷记 FINDINGS 07-3 节，转 Phase 8+ 处置，不在本 plan 内修。

- **GUI-19（中）**：添加模块到图层后模块行未在 Inspector 层链列表显示（sidecar 链
  证据确凿——渲染/刷新路径嫌疑）；AX 对 tap-gesture 行不可驱动，复验需真鼠标 → UI
  打磨轮。
- **GUI-20（低-中）**：dev-signed 构建层 B `downloadAssets()` 无错误返回但
  assetStatus 恒 notReady——macOS 27 beta 资产供给对 development 签名不放行（与
  07-1 测试宿主 entitlement 同根）；三态 UI 行为诚实（引导态保持/无静默假就绪/层 A
  全程可用）→ **Developer ID / 正式分发签名复验 = v1 后观察项**；下载卡顿超时提示
  = v1.1 候选。

**理由**：两者根因均在 beta 系统行为/既有 UI 面，非 07-3 交付面缺陷；修复需签名形态
或 UI 打磨轮资源，强行修 = 范围蔓延。

## D-07-3-T5-1: SC#5 门 = warm 路径裁定（继承 D-07-1-T1-3）+ C 档第 3 停执行记录

**决策**：SC#5「acceptable for interactive use」按 warm median 裁定 PASS（层 A
15-16ms / 层 B accurate 85-126ms，全 ≪1s；cold = 进程内模型首编译一次性，后台 Task
+ spinner 承接）。GUI 磨皮质感真机复验范围如实登记：层 A 真机闭环（IMG_4276.CR3 +
ΔR 量化）；层 B ready 态跃迁受 GUI-20 阻断；pore-level 目检待含人脸样张（Manual-Only
挂账）。

**C 档第 3 停（签核前停）执行记录**：07-2 闭环时用户已确认「继续 → 07-3」（2026-09-24，
git `f9ed133` user gate passed）；T4 战果 + FINDINGS 已落盘；本签核轮由 orchestrator
直接派遣 T5 收口（续班 executor 指令 = 终签核授权），签核结论以 07-VALIDATION
frontmatter 为准，用户终验留 verify-work 轮。

**Reversibility**：SC#5 cold 路径若正式版实测恶化（>1s 常态化），门重开 = perf plan
项；GUI-20 若 Developer ID 下复现，升级为 v1 阻塞重开。

## D-GUI20-FIX: GUI-20 修复轮裁定——「dev-signed 阻断」不复现；修复口径 = 无错误未就绪路径明示化（2026-09-24）

**背景**：GUI-19/20/21 修复轮（2026-09-24）对 GUI-20 的诊断结论与 07-3 登记不同。

**诊断矩阵**（探针二进制 = `GenerateIterativeSegmentationRequest.downloadAssets` +
`assetStatus` 打印，本机 Mac16,10 / macOS 27.0 26A428）：

| 上下文 | 结果 |
|---|---|
| 裸 swiftc 二进制（ad-hoc 签名，无 entitlements） | ready（3-11ms 级） |
| + 测试 entitlements 组（get-task-allow + mach-lookup testmanagerd 三项 + 只读根路径例外） | ready |
| + `Lightamer Dev` 证书（app 同款签名身份，TeamIdentifier 未设） | ready |
| .app bundle（同证书 + 同测试 entitlements）经 `open` 启动 | ready |
| **Lightamer Debug 产物本体**（AX 驱动「下载模型」按钮） | choice→accepted 落盘 + 工具条三态跃迁（非 spinner/非原下载钮形态） |

**裁定**：
1. **「macOS 27 beta 资产供给对 development 签名不放行」不成立**（本机今日不可复现）。07-3 验收时的 notReady 观测更可能属于当时机器/构建瞬时状态（OS 侧资产供给 beta 抖动）或 07-1 已知的**测试宿主 entitlement** 上下文（唯一可复现的阻断族）。
2. **资产为机器级**：任一二进制完成一次 `downloadAssets` 后，所有上下文读 ready——「替代供给路径」workaround = 用普通二进制（如 `.work/07/bench` 或独立探针）先行供给一次即可，无需手动放置模型文件（无已知的合法手动放置位置；DownloadableAssets 由 OS 管理）。
3. **修复落地（UI 明示化）**：`AIDownloadModel.startDownload` 在「下载无错误返回但资产仍 notReady」时经既有非静默 alert 弹出 `ai_download_not_ready_body`（解释 beta 供给/构建上下文 + 机器级资产语义 + 可重试）；下载按钮加 tooltip `ai_mask_download_help`。回归 = `testNoErrorNotReadyDownloadSurfacesNotice`。
4. **Developer ID 签名复验仍保留为 v1 后观察项**（分发形态终验）；若正式分发下复现 notReady，按 D-07-3-T5-1 升级为 v1 阻塞重开。

**Reversibility**：若后续真机再现「无错误恒 notReady」，alert 文案即取证入口（区分 OS 供给失败 vs app 上下文阻断）。

## D-GUI22-FIX: GUI-22 修复轮裁定——undo 暖/冷渲染分叉根因 = CIRAW 输入平面重执行非确定 × 预算驱逐迫使变体重嵌（2026-09-24）

**诊断链**（状态级字节门复现 → 逐腿二分，real sample `input/RAW/DSC00012.ARW`，工具 = `Tests/LightamerTests/GUI22UndoWarmColdTests.swift` 诊断期探针，已收敛为常驻门）：

1. **复现**：层栈（层 + 链模块 + 笔刷蒙版）→ blend 正常→正片叠底 → ⌘Z —— 暖路 undo 渲染 vs 同态首渲染 max=56（合成图 0.0 不复现——identity 色彩管理路径触发不了缝；真实 RAW 必要）。
2. **逐腿二分**：暖缓存 vs 新缓存全链渲染差 14%（float32 bytes）；**输入平面定位探针**（preview 缓存全平面 + 同键前缀重探 = 纯回读）钉死**分歧从 position 1（= 输入平面）开始**；逐模块扫排：全部 identity 模块（flip NONE/crop 全幅）单跑也差 ~0.058%/max255 —— **差异源 = 输入平面本身**；`shadhi` 单跑放大至 18%（局部对比算子把 speckle 重组为大 blotch——GUI-22 的 mid-tone 纹理区集中、零均值、max>128 签名的成因）。
3. **根因（两层叠加）**：
   - **CIRAWFilter 支撑的 CI 位图渲染逐次执行非字节稳定**（`cacheIntermediates:false` 下每次 render 重新执行 RAW 链；speckle 级方差 ~0.06% float bytes / 字节 max 255，宿主 Mac16,10 / macOS 27.0 26A428 实测）；
   - **会话缓存预算驱逐**（2560px PREVIEW 一族 ≈1.9GB，26 条平面互相踩踏 3GB 预算）迫使输入平面 MISS → 重渲染捕获**不同 speckle 变体** → 各路径各自冻结（= GUI-22 三铁证的机制学解释：冷重启==首帧——皆为处女渲染；暖路自洽——变体被缓存冻结；逐字节可复现——按进程史确定）。

**修复（渲染一次冻结）**：`CIContextPool` 输入平面 memo——键 = `DecodedImage.contentDedupeID`（RAWDecoder 计算：路径 UTF-8 ⊕ size ⊕ mtime 的 StableHash）⊕ decodeParamsHash ⊕（region, scale）；CI 链每（文件, 请求）至多执行一次，此后 MISS 一律复用冻结纹理。合成/内存图像 contentDedupeID=nil → 回退 CIImage 身份键（**第一版用 (decodeParamsHash ⊕ imageID) 作内容键是错的**：测试单 imageID 渲多张合成图 → 碰撞 → RetouchParity/GoldenColor 回归，已改）。memo 有意**穿过 `clearCaches()` 存续**（该扫除针对 CI/RawCamera 内部态 = D-32 的 GB 级累赘；同图重载 = sidecar 冷恢复必须复用冻结平面），按字节上限 512MB LRU（数量上限会在 60MP FULL 下持 3×962MB 爆预算）。

**验证**：状态级字节门（undo 暖路 == 冷加载 sidecar 恢复 == 同态首渲染，逐字节）三项全 0.0；全套 **853/6skip/0fail**（基线 852+1）。GUI 真机：undo → 回退态渲染 == 编辑前 **0.0000%**；冷重启×3 互比 **0.0000%**。

**残余（GUI-23 登记）**：跨进程首渲染方差——warm 进程与 cold 进程各自的处女渲染互差（viewport 裁剪 strong>60 0.39% / meanAbs 1.39 / max 255；冷×3 互比恒 0 → 按进程启动史确定，Apple CI 内部行为，非本修复层可达）；暖会话内 flat 首帧 vs composite 帧 0.22%/max56（状态级同转移 0.0——GUI 上下文特有变量待查）。另：`GoldenColorTests` neutrality/cross 断言在本机为**既有 flake**（pristine stash 对照 2/3 挂——同一 CI 首渲染方差打在金测试容差上，与本修复无关，登记待办）。

**Reversibility**：memo 键域 = pipe 缓存自身 §1.3 域（同文件+同解码参数+同请求才合一；原位改写文件 mtime 变 → 新键新渲染，无新增 stale 类）。若 Apple 后续版本修复 CI 重复执行确定性，memo 退化为纯性能优化，无行为依赖。
