# Plan 02-02 — Summary

**Executed:** 2026-09-18 → 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE

process 签名 Buffer→Texture 迁移 + TestGainModule（SC#2 演示载体）+ PipeCacheKey/PipeCache（字节预算 LRU actor）+ PixelPipe.processRec（hash 链快路径）。FOUND-04 的核心机制落地：**拖动参数只重算变更模块及其下游，上游平面原样复用**。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 02-02-01 | checkpoint：八项锁全部确认（纹理签名/UInt64 paramsHash/PipeCacheKey 组成/per-pipeType 缓存政策/LRU 淘汰/ModuleBox/纹理所有权契约/TestGain 落位），无争议项 | 376ba45 |
| 02-02-02 | `IOPModule.process` → `(input: any MTLTexture, output: any MTLTexture, roiIn:roiOut:piece: inout IOPiece:metal:)`；`IOPiece.paramsHash: UInt64`（StableHash 为唯一合法生成器）；PassthroughModule 删除 buffer↔texture staging 桥，直走 `dispatch2DTexture`；IOPModuleTests 迁移纹理域 | 10d301c |
| 02-02-03 | `TestGainModule`（LightamerIOP 整文件 `#if DEBUG`，opName `testgain`，iopOrder 50.5，Params.gain=1.0 恒等）+ `test_gain` kernel + `commitParams` = paramsHash 契约参考实现；Release 构建验证编译剔除 | b808292 |
| 02-02-04 | `PipeResolution`（public, 4 case + `cachesIntermediatePlanes`/`isLazy`）+ `PipeCacheKey`/`PipeHash`（internal）+ `PipeCache` actor（LRU、命中/未命中计数、signpost、invalidate）；ROI 补 Hashable | 0ea7358 |
| 02-02-05 | `ModuleBoxing`/`ModuleBox<M>`（类型擦除管线公民）+ `PixelPipe.processRec` 递归（禁用跳过/levelHash 链/decodeParamsHash 播种/命中快路径/ping-pong 政策分支/ROI 恒等 assert）+ `RenderPipeline.process`（`PipeRunStats`）；`render` no-op 路径保留，EditorState 零改动 | 43d058b |
| 02-02-06 | `PipeCacheTests` 9/9 绿（SC#2 主链/禁用跳过/FULL 政策/LRU×2/命中计数/decodeHash 失效/PipeHash 组成/invalidate 扫除）；全量 52 tests 0 fail | 9cc69a4 |
| 收尾 | API.md 表面同步 + SUMMARY + LESSONS L013 | （本提交） |

## 验证（SC#2 语义实证）

`PipeCacheTests.testParamChangeInvalidatesOnlyDownstream`：链 `[TestGain#1, Passthrough#1, TestGain#2, Passthrough#2]`（.preview，合成 CIImage，无 RAW 依赖）：

- **run1**（首渲）：hits 0 / misses 5（输入平面 + 4 模块行）/ planesRendered 5
- **run2**（参数不变）：hit 即短路返回，**零 GPU 派发**（planesRendered 0）
- **run3**（g2 gain 1.0→1.5）：p1 缓存行命中喂给 g2；g2/p2 精确重算（hits 1 / misses 2）
- **run4**（撤销回 1.0）：p2 旧 key 命中 run1 的原始行 → 零重算

其余：禁用模块零 key 步进零 process 调用；FULL 分辨率只持 2 平面（4 模块）且第二轮零工作；LRU 超预算逐出保 recently-touched；decodeParamsHash 变更全失效；`invalidate(imageID:)` 只扫本图。

## 测试暴露并修复的缺陷（本 plan 最大收获）

1. **hash 链方向反转（关键）**：初版在递归下降时折叠当前模块 hash → 每行的 upstreamHash 只含"上方"模块 → 改 g2 时 p2 的 key 不变 → **命中陈旧下游平面**（SC#2 语义完全反转）。修复：`run()` 预计算 `levelHash[i] = decodeParamsHash ⊕ (启用模块 ≤ i)`，行 i+1 以之入 key。
2. **decodeParamsHash 不稳定（LESSONS L013）**：`FNV(JSONEncoder 字节)` 依赖 keyed 容器发射顺序 — macOS 27 Foundation 实测乱序且无契约稳定。改为**字段显式折叠**（bitPattern）。**02-05 sidecar paramsHash/historyHash 必须复核此坑**（同二进制同进程内 JSON 稳定 → 缓存够用；跨进程漂移检测前需规范化编码）。
3. **ROI 恒等 assert 打空 ROI**：run() 现在先算全幅 ROI 再下传。
4. **小预算淘汰失效**：evictTarget 固定 2GB 常量使 8MB 测试预算永不淘汰 → 改为 `min(2GB, budget×2/3)` 实例级滞回。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | `PipeCache` internal → **public** | plan 同时要求 internal cache 与 public `RenderPipeline.process(cache:)` — Swift 不允许 public 参数暴露 internal 类型。key 机制（PipeCacheKey/PipeHash/CachedPlane）保持 internal |
| 2 | `RenderPipeline.process` 增参 `imageID: UUID` | 缓存 key 需要稳定图 UUID；测试跨 run 传同一 UUID 才能证明命中（02-03 传 sidecar 锚 UUID） |
| 3 | SC#2 计数 plan 值 2/3 → 实测 1/2（run2/run4 的 hits=5→1） | plan 自身算术不一致（其 run1=5 含输入行、run3=5 hits 要求输入行缓存，与 run2 的 2/3 矛盾）；按实现模型（输入行缓存 + 下降方向首中即停）写精确断言，语义等价 |
| 4 | `processErased` 带 `piece: inout IOPiece` 参数（plan 签名无） | plan 同时定义 `Piece = (box, pieceState)` 且要求"以 committed IOPiece 派发" — 带参形态让 per-run piece 真正载荷（几何戳记/Phase 4 ROI），与 module.process 一一对应 |
| 5 | `tuist generate` 必须（plan 说"应不需要"） | 新源文件只有重新生成才进 xcodeproj；02-02-04 的"构建绿"曾是空验证（无人引用新文件），02-02-05 接线后即暴露 |
| 6 | FULL 管线最终输出以 fresh 平面缓存，EXPORT 全程不缓存 | plan 只说"cache only the final output"未区分 EXPORT — Darktable parity（pixelpipe_hb.h:346-355）要求 EXPORT 无缓存，已按 lock #4 字面执行 |

## 交接给下游

- **02-03**：`PipeResolution.isLazy`（thumbnail dirty 生命周期）、`longEdge` 形参（scale-at-entry 接入点，现恒全幅）、`invalidate(imageID:)`（load 入口清扫）、`PipeRunStats`（coordinator signpost 汇总）
- **02-04**：`ModuleBoxing` = registry 制造目标；terminal trio 落地后 `GoldenColorTests` 复用 SC#2 断言（PipeCacheTests 内已留注释指向）
- **02-05**：`paramsHash`/`StableHash`（D-H4）共享；⚠️ L013 — sidecar 的 paramsHash 编码稳定性需规范化方案；`ModuleBoxing` 身份字段 = `ModuleInstance` 镜像
- **02-06**：hash 链即失效语义正确性证据；`PipeCache` 预算/budget 执行器直接驱动 `totalBytes`

## 环境注记

- L009：Resilio Sync（pid 668）SIGSTOP 全程，收工 SIGCONT 恢复（`xcodebuild -version` 4.27s → 0.095s）
- `git commit --amend` 陷阱：gsd-tools commit 静默失败（gitignored 路径入 --files）后 amend 会改写上一提交 — 已现场修复历史（f86600a → 0ea7358 + 43d058b），无内容损失
