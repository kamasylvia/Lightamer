# Plan 12-5 SUMMARY — LUT iop + Phase 12 收口签核（W4）

> **终轮全 suite：1436 tests / 6 skip / 0 fail**（`caffeinate -dis Scripts/test-direct.sh`，466.6s；
> 基线 1390 → 1436，净增 46：CubeLutParserTests 22 + Lut3dKernelTests 8 + Lut3dGoldenImageTests 5
> + LutLibraryStoreTests 10 + MetadataServiceTests promotion +1）。
> 七提交（T1 `dbee91e` / T2 `814d601` / T3 `274c6ef` / T4 `a7dfdc6` / T5 `d71e830` /
> 移交消费 `9e70338` / T6 签核本提交），未 push。
> 每任务边界查 `.work/config.toml [gsd]`（auto=true / paused=false 全程 ×7）。

## 任务表

| 任务 | 内容 | commit | 证据 |
|---|---|---|---|
| T1 | CubeLutParser：键全集（TITLE 整行取值 = dt 差异；DOMAIN 1-float 广播/3-float 双形态；LUT_1D_INPUT_RANGE；`#` 行内注释；CRLF 容错）+ 八名 typed throw（7 抛 + titleAfterData 容忍 warning）+ red-fastest 锁序 + 脏样本 3 fixtures 入仓 `input/cube/` | `dbee91e` | CubeLutParserTests 22 绿（golden/八类/锁序/脏样本） |
| T2 | Lut3dKernels.metal（lut3d.cl:29-60 tetrahedral verbatim + trilinear；texture3d 手动八角点无 sampler；DOMAIN remap + 色彩空间矩阵融合 uniform）+ Lut3dModule（V50 36.0 + L031 路由 blit + LutResolving 缝）+ LutColorspaceMatrices（四态资产）+ Registry 注册/prewarm | `814d601` | Lut3dKernelTests 7 绿（CPU float64 双写 ≤1/1024 四域/格点精确/identity cube/neutral/missing/kernel 路径） |
| T3 | lut3d_1d：per-channel 分段线性 + INPUT_RANGE remap（§6.3 公式）+ 无域声明 sRGB face 文档化 + texture1d 主案（回退案未触发） | `274c6ef` | test1DRamp（identity 全链 + 端点 clamp + remap 已知点 vs CPU） |
| T4 | 色彩空间四态 golden：矩阵往返恒等 + 灰中性（sRGB/P3 行和 1；ProPhoto Bradford 白点映射）+ ColorOut 资产同源逐位核对 + identity cube 全链恒等（灰 ramp 四态 + rec2020 全网格）+ 非恒等表真矩阵 ≤1/1024 | `a7dfdc6` | Lut3dGoldenImageTests 5 绿 |
| T5 | LutLibraryStore（FNV-1a 查重折叠 + 同名更新 + 三拆自愈 + 库名引用 D-6）+ LutPanelView（导入/库 picker/四态/插值/1D 提示/缺失红字+toast）+ seed + InspectorState 注册 + zh +18 键 | `d71e830` | LutLibraryStoreTests 10 绿 + PanelWiringTests 71 绿（含 lut3d dispatch 断言） |
| 移交消费 | sidecar_present 缺陷修复（backfill 第三 pending 类 promotion）+ convertTexture L029 复核（11-05 已闭环）+ 12-4 D10 复核注记 | `9e70338` | MetadataServiceTests 11 绿（含 testBackfillPromotesLateSidecarRows）；L029 parity 测试复跑绿 |
| T6 | 终轮 1436/6/0 + 12-VALIDATION + DISCUSSION-LOG 终节（Phase 13 移交清单五条 + 遗留对表 10 行）+ REQUIREMENTS/TODO/GOAL-STATE 翻账 + C 档第 3 停 | 本提交 | 12-VALIDATION.md（status: validated + nyquist_compliant: true） |

## AC 自检（plan 验收标准逐条）

- [x] **解析器**：识别键全集（TITLE 取值差异/DOMAIN 双形态/LUT_1D_INPUT_RANGE/CRLF 容错）+ 八名 typed throw + red-fastest 角点锁序 golden（2³ 逐角 + 3³ 步进序）+ 脏样本 fixtures（**真实采集失败 → 合成替代**，D5；CRLF/tab/行内注释混合 + HDR DOMAIN ± + 科学计数 1D + 尾置 TITLE）
- [x] **kernel**：tetrahedral verbatim（lut3d.cl:29-60 六分支权重逐行核对）+ texture3d rgba32Float 手动八角点（无 sampler；**rgba16Float→32F 升格 D7**）+ DOMAIN remap uniform（超 dt 能力面文档化 F4）+ trilinear 第二态 + 1D kernel（texture1d 主案，回退案未触发 D8）+ **identity/blit 走 `makeRoutedCommandBuffer()`**（L031：Lut3d 源 grep 零 `commandQueue` 直取）+ neutral（lutName nil）= 恒等零管线行为（blit 字节恒等测试）
- [x] **精度**：tetrahedral/trilinear vs CPU float64 ≤1/1024（unit/HDR/negative/mixed 四域全绿；rgba16Float 破门 → 32F 升格，D7 在账）
- [x] **色彩空间选择器**：四态默认 sRGB + 矩阵同源（sRGB/P3 与 ColorOut 资产**逐位一致**；ProPhoto Bradford numpy 推导）+ 往返恒等（1e-7）+ 灰中性（行和 1/ProPhoto 白点映射）+ identity cube 全链恒等（灰 ramp 四态 + rec2020 全网格）+ 非恒等表 golden ≤1/1024
- [x] **导入库**：LUTs/ 目录 + FNV-1a 查重折叠（同哈希改名不重拷）+ 库内名引用（导入即弃路径）+ 同名更新 + 缺失降级恒等（routed blit）+ 面板红字 + toast 键 + by-name 预设 params round-trip；面板四件套 + zh catalog（L025 smoke zh 944==en）
- [x] **收口**：终轮 0 fail（1436 = 1390+46 逐类吻合）+ 12-VALIDATION（SC#1-4 三列证据 + **SC#2 排序键口径 checker W-2 声明** + 缺陷处置记录 + Manual-Only 13 行汇总）+ DISCUSSION-LOG 终节（Phase 13 移交清单五条 + 遗留对表 10 行零静默）+ REQUIREMENTS（×11 翻账）/TODO/GOAL-STATE 三处翻账 + C 档第 3 停按夜间授权先例执行
- [x] **全 suite 0 fail**；每任务独立提交 + 边界查 config 开关 ×7；不 push；无 /tmp 产物入工作区（fixtures 全部 `input/cube/` 入仓或临时目录）；SUMMARY + DECISIONS 落盘

## 移交消费三件（plan 协议第 4 条）

| 移交 | 处置 | 锚 |
|---|---|---|
| sidecar_present 回读缺口（12-2 验收发现，GOAL-STATE 阻塞#4） | **修复**：backfill 第三 pending 类（present=0 stat `.lra` → work + UPDATE 翻 present=1）；「先图后 sidecar」行增量打开即回读 | `9e70338` + `testBackfillPromotesLateSidecarRows` |
| convertTexture L029 镜像 + 双腿 parity（11-02/11-03 双移交） | **已于 11-05 闭环**——复核复跑绿，零残留工作 | `testColorSyncFallbackLegParityWithExportLeg` |
| 12-4 D10 LUT 跨机器前提复核 | **落库兑现**：库名引用 + 查重 + 自愈 + 缺失降级（blit + 红字 + toast）；F-12-4-3 关闭 | 12-4-DECISIONS D10 复核注记 + `testRemovalDegradesModuleToIdentity` |

## GUI 走查记录（2026-09-27 02:0x；控制台解锁）

- `12-5-01-launch-zh-smoke.png`：app 启动首屏 zh 全量中文渲染（L025 smoke；xcstrings 编译产物 zh.lproj 944 键 == en 944 键；zh-Hans.lproj 空壳无害——无 Localizable 表，回退链完整）
- `12-5-02-session-open.png`：la-uat-session 打开 + 编辑器渲染（RAW 解码 + Inspector 模块列表 + 既有编辑链显示）
- **面板交互逻辑覆盖说明**：库/查重/自愈/降级链由 LutLibraryStoreTests 10 测钉死；面板 dispatch 由 PanelWiringTests 断言；picker/导入的深交互合成（CGEvent 对 SwiftUI toolbar/List 不可达，L032 同族限制）→ **F-12-5-1 Manual-Only**（NSOpenPanel 驱动 + picker 观感 + 降级 toast 观感待人工）
- 走查痕迹清理：走查用 RAW 副本与 LUT 库预放文件已删净（L032 纪律）

## Manual-Only 登记（合成驱动限制，人工确认项）

| # | 项 | 自动化腿状态 |
|---|---|---|
| F-12-5-1 | LUT 面板深交互走查（NSOpenPanel 导入驱动/picker 观感/降级 toast 观感） | store 10 测 + wiring 断言 + 降级链单测 ✅；合成 CGEvent 未达 SwiftUI 工具条 |
| F-12-5-2 | dt-GUI 侧 .cube golden 人工交叉对照 | CPU float64 双写参考（L017 先例在案：dt-cli 本 host 空间损坏 + CrashReporter 记录）+ 权重表 verbatim 核对 ✅ |

## 基线演变（Phase 12 全程）

1258（Phase 11 末）→ 12-1 **1290**（+30）→ 12-2 **1334**（+44）→ 12-3 **1364**（+30）→ 12-4 **1390**（+26）→ 12-5 **1436**（+46）。全程 0 fail（12-4 收尾轮无 fail；LayerE2ERoundTripTests 在案 flake 未现身）。
