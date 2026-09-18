# Plan 02-03 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE

多分辨率管线家族落地（FOUND-04 SC#4 管线半边）：**PREVIEW 常热（D-C3 档位量化）/ THUMBNAIL 惰性 360px / FULL 按需 scale-1.0 / EXPORT 类型化占位**，共享模块链 + 单一 `PipeCache`；scale 在管线入口一次施加（`pixelpipe_hb.c:1930-1999` 镜像），pass-through 时代模块对 scale 无感。App 侧新增 **`PipeCoordinator`**（D-03b 隔离），把「什么变了」翻译成「哪条管线重渲」，成为 02-04/05/06 的接线缝。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 02-03-01 | `PreviewBucket` 纯函数（cap 2560 + 360px 阶梯 snap-DOWN + 5K/6K soft note）+ `PreviewBucketTests` 5 边界组（×2 表/原始目标/pixelScale 覆盖/退化输入/常量冻结） | 935104c |
| 02-03-02 | `CIContextPool.renderToTexture(_:longEdge:)`（scale-at-entry 单趟 bitmap 渲染 + `"render-scaled"` signpost + 引用 02-01 spike Test C：省的是**显存**不是解码时间）+ `MetalContext` 公共 facade | 3780aeb |
| 02-03-03 | `PipeResolution` 迁出独立文件 + `defaultLongEdge` + 四管线生命周期表；`PixelPipe` 增 `roi`（scale-at-entry）/`isDirty`/`runIfDirty`/`runOnce`；输入平面 `roi.scale<1` 走长边渲染（分档平面共存于缓存，抖动回跨档秒回）；EXPORT 在 `run` 入口抛类型化 `AppError.notImplemented("Phase 11")` | 064f40b |
| 02-03-04 | `PipeCoordinator`（App，@Observable @MainActor：`load/paramsDidChange/drawableDidChange/fetchThumbnail/requestFull` + 三条文档化缝）；`EditorState` 解码后委托 coordinator（弱引用互指、app root 强持有，无环）；删除无调用者的 `rerender(using:)`；`EditorAreaView` 保持 display-only + 几何输入事件 | f1f146d |
| 02-03-05 | `MultiResolutionTests` 6/6（scale-at-entry 2560/Risk#8 key 分离/THUMBNAIL lazy/FULL scale-1.0+只缓存两端/EXPORT typed/roi.scale<1）；**app 内 D-C3 resize 实证**（跨档=恰好 1 重渲、档内=0、回跨档=纯缓存命中，`.work/02-03/resize-verification.md` + 截图）；VALIDATION FOUND-04 行更新 | 8f6dadb |
| 冒烟 | `.work/02-03/smoke.swift` 真 RAW 11/11 PASS（PREVIEW 2560/FULL 全幅/THUMBNAIL 360/EXPORT typed + 内存账 2.07GB<3GB） | 22e3189 |
| 收尾 | API.md 表面同步 + SUMMARY（本提交） | — |

## 验证（质量门全过）

- 单元：**63 tests, 0 failures**（52 基线 + 11 新增；1 skip 为既有 RAW 样本跳过）——零回归
- app 内 resize 实证（1504×846pt 屏，DSC09991.ARW@RAW9）：
  - 档内微调 → `drawable Npx within bucket — no re-render (D-C3)` ×2，零重渲
  - 跨档 → 每个 crossing 恰好 1 次 `render-scaled` + 1 次 `pixelpipe output ready`
  - **回跨档 = `1 hits / 0 misses, 0 planes`**（RESEARCH §2.3 抖动回跨档命中，app 内实测）
  - 视口截图证实 PREVIEW 纹理上屏（`viewport-1120.png`）；`grep .task(id:` 干净（D-X1）
- headless 真 RAW 冒烟：11/11 PASS；60MP 的 PREVIEW+FULL+THUMBNAIL 同图共存 = 2.07GB < 3GB 预算（FULL 平面乘法防线生效）

## 验证过程抓出并修复的缺陷

1. **双重缩放（关键）**：视图先把 point×backingScale 再传 `PreviewBucket.longEdge(forDrawable:)`，而契约是传 **POINTS**（函数自管 pixelScale）→ 所有 drawable 翻倍 → 全部钉死 2560 档、档位永不变化。修复：`sendDrawableGeometry` 传 point。契约文档 + 测试都在，是接线侧违例。
2. **load 档位对齐**：`onAppear` 几何输入先于解码完成到达、被 `decoded != nil` guard 丢弃 → 首渲走 cap 兜底。修复：coordinator 记 `lastDrawableLongEdge`（无图也记），`load` 渲染前对齐档位。
3. 冒烟 harness 两坑（已注释在案）：管道 dispatch 只 commit 不等待 → 读像素前必须 drain queue；`addCompletedHandler` 必须先于 `commit()`（L008 同族）。
4. 已知可接受项：launch 窗口动画期间的几何快照是中间态（首渲 1120 而非稳态 1480），下一个几何事件自纠、旧档平面留缓存——本机 app 无自发窗口动画，接受。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | coordinator 不持有 `PixelPipe?` 实例，改为持有**生命周期状态**（dirty 标志/当前档位/几何记忆）并经 `RenderPipeline.process` 驱动运行 | plan 的 artifacts 列表把 `roi/isDirty/runIfDirty/runOnce` 定为 internal——`PixelPipe` public 化会扩大被冻结的跨模块表面；缓存本就是持久层（02-02 已证管道实例是廉价的） |
| 2 | `coordinator.load(url:decoded:instances:metal:)` 增 `url` 形参 | plan 要求 `[URL: UUID]` 稳定 imageID 表，但其签名漏了 url；EditorState.load 本就持有它 |
| 3 | `EditorState`/`PipeCoordinator` 用 **post-init `attach` + 单条弱引用**（plan 原文「injected at init」） | 构造序死锁：coordinator 的 display sink 需要 EditorState 实例，EditorState 又要 coordinator；弱引用方案是 plan 明列的备选项，root 双强持有无环 |
| 4 | DEBUG `-la_resize_probe`（`#if DEBUG` + 启动参数门控，D-X2 探针策略）驱动窗口几何 | headless 驱动器无 Accessibility 授权（osascript -1719 / bounds AppleEvent -1712 超时），探针走真实 setFrame→GeometryReader→coordinator 链；**验证完成即退役** |
| 5 | EXPORT typed 抛出点在 `run()` 入口而非 processRec 分支 | plan 要求「run marked unimplemented-style」；入口抛出让 EXPORT 永不进入管线 walk（原 processRec 的 export 分支删除，不可达代码不保留） |
| 6 | 输入平面缓存 key 的 roi 现在承载分档尺寸（scale<1） | 必须项而非偏差：THUMBNAIL≠PREVIEW@360（Risk #8）与多档平面共存（抖动回跨档命中）都依赖 roi 入 key |

## 交接给下游

- **02-04**：terminal trio 渲染走 coordinator 的 PREVIEW 路径（`paramsDidChange` 已是单入口）；display-profile 变更接 `drawableDidChange` 邻近缝（注释已留）；golden harness 以桶位分辨率跑管线；**可顺手退役 `-la_resize_probe`**（`LightamerApp.swift` #if DEBUG 块）
- **02-05**：history 变更从 `paramsDidChange()` 进入（升级为实例集整体替换，seam 注释在位）
- **02-06**：clearCaches 触发点 = `load` 入口 + 60s 巡检（seam 注释在位）；`previousImageID`/`imageIDMap`（per-URL UUID）即 D-C1 `KeepingPolicy` 与 sidecar 锚的原材料
- **Phase 4**：`requestFull()` 即 zoom ROI 接缝；**Phase 9**：`fetchThumbnail()` 即浏览器接缝

## 环境注记

- L009 全程生效：Resilio（pid 668）构建时段 SIGSTOP、收工 SIGCONT（`xcodebuild -version` 3.5s → 慢卷态确认）
- 新源文件必须 `tuist generate` 才进 xcodeproj（02-02 偏差 #5 再证：`PipeResolution.swift` 首次构建 missing）
