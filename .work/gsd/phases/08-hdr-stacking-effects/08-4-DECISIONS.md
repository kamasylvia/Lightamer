# Plan 08-4 — DECISIONS（执行期决策账）

> 纪律节授权：RESEARCH/CONTEXT 未覆盖细节标注执行期决策入本档，不臆造。
> 全部决策服从两条硬闸：SDR off 逐字节不变（①）+ EDR on 三不进（②）。

## D-08-4-T1-1：EDR 层色彩空间 = 字面 extendedLinearSRGB（不用 resolved-profile 线性变体）

- **裁决**：EDR on 时 `CAMetalLayer.colorspace = CGColorSpace(name:
  .extendedLinearSRGB)!`，恒定、不跟随 resolved display profile。
- **理由**：plan AC 与 research §7.1 择优定案字面（「extendedLinearSRGB 直接用」）；AC 同时要求
  「display colorspace 跟随逻辑 on 分支跳过」——若改用 `DisplayProfile.linearCGColorSpace`
  （P3 屏 → extendedLinearDisplayP3）即构成第二种 display follow，违背 AC 字面。
- **已知边界（登记非遗留）**：P3-resolved 屏上 colorout 输出 linear-P3 值被 extendedLinearSRGB
  标签按 sRGB 原色解释 → 宽域屏上轻微过饱和。由 Manual-Only ③（headroom>1.0 屏观感确认）覆盖；
  v2 缝 = 层色彩空间映射到 resolved profile 的线性变体（一行改）。

## D-08-4-T1-2：16F PSO 只出一个变体（displayReady=false 特化），两 PSO 共存由 regime picker 表达

- **裁决**：`makeBlitPipelineState(device:displayReady:colorPixelFormat:)` 加第三个参数；
  EDR 变体 = (displayReady:false, .rgba16Float)。`blitRegime(edrActive:sourceIsDisplayReady:)`
  三臂枚举（legacyFloat / displayReadySDR / edr16F）成为 draw() 的唯一择路源（非 test-only orphan）。
- **理由**：EDR 腿的输入恒为 float32 colorout 平面（T2 剥 gamma 后）——displayReady=true 的 16F
  特化不可达，造出来是死 PSO；「共存不替换」由两个 SDR PSO 原样保留 + 16F 变体并存表达。

## D-08-4-T1-3：clearColor 线性解码（canvasClearColorLinear）

- **裁决**：EDR on 时 drawable clearColor 用 #161619 的 sRGB EOTF 解码值（≈0.008/0.008/0.0097）。
- **理由**：extendedLinearSRGB 把 framebuffer 值当线性解释；SDR bgra8 存的是编码字节原值。两侧各按
  自己的语义存同一视觉色。层背景（layer backgroundColor）不动（2D UI 色，不经 Metal）。

## D-08-4-T1-4：toggle 状态面挂 PipeCoordinator（soft proof 同位），re-render 只动 PREVIEW

- **裁决**：`edrDisplayEnabled` + `setEDRDisplay(_:)` 与 `setSoftProof` 同形（generation++ +
  renderPreview）；THUMBNAIL 永不 dirty（镜像 soft proof 的 thumbnail 守卫）。
- **理由**：13-2 先例形状正本；浏览器缩略图不是 EDR 面。

## D-08-4-T1-5：EDRControlView = Menu 胶囊（SoftProofControlView 同位）；headroom 读数常显

- **裁决**：菜单内 toggle + Divider + headroom 读数行（被动 readout）。>1.0 灰色
  「EDR 余量 N.N×」；≤1.0 橙色「当前显示器无 EDR 余量」。toggle 在 1.0 屏保持合法、无自动回落（P4）。
- **理由**：research §7.3「headroom 值随 EDRControlView 展示」未定可见性——取常显（打开菜单即见，
  胶囊本体保持单图标+标题不变宽）。挂载 = EditorAreaView topTrailing HStack 与 soft proof 胶囊并排。

## D-08-4-T2-1：旁路形状 = gamma 尾模块整体 SKIP（非「仅去 clamp」）

- **裁决**：`edrDisplayLeg = true` 时 `prepareChain` 把 gamma 从 topEnabled 候选中除名、
  `processRec` 把 gamma 当 disabled 直通；终平面 = colorout 的 float32 线性输出。
- **理由**：extendedLinearSRGB 解释**线性**值——若保留 gamma 的 sRGB TRC 编码仅去 clamp，
  编码值被当线性解释 = 画面发白（双重解释错误）。plan 术语「SDR 钳制旁路」在 D-COL4
  （clamp 与 encode 同属 gamma 一体）下只能整体短路。零新 kernel、零管线数学改动。

## D-08-4-T2-2：开关落位 = PixelPipe run 级 `edrDisplayLeg`（默认 false），非 App 层剥链

- **裁决**：`PixelPipe.edrDisplayLeg`（run-level data，同 `captureExif` 注入面）；
  `RenderPipeline.process` / `processComposite` / `LayerCompositeDriver.composite` 各加
  缺省 false 参数；composite 路径只设**终端腿**（gamma 只在 ≥70.0 尾窗）。
- **理由**：①files_modified 点名 PixelPipe；②flat 与 composite 两条路一次覆盖；③缓存身份：
  gamma 被旁路时其 hash 不进任何 key（key 根本不被访问），colorout key 两态全等——
  「off→on→off 全命中」测试钉死零失效。曾考虑 App 层 chainWithSoftProof 式剥 gamma（等价但
  不动 Core）——为守 files_modified 申报面取 Core 开关。

## D-08-4-T2-3：before/after 比较腿同穿 EDR 旗

- **裁决**：`renderPreview(instances:layerStack:bucket:)`（override 渲染 = 比较平面唯一来源）
  也传 `edrDisplayLeg: edrDisplayEnabled`。
- **理由**：EDR 模式下 split blit 两侧平面必须同编码（16F PSO + float32 线性源）；若 before 平面
  走 SDR 腿（bgra8 编码值）会与 after 平面（线性值）在同一 EDR 视口内混解释。比较平面键
  （upstreamHash 线）不变——只换终端段行为，upstream 平面共享两侧模式。

## D-08-4-T3-1：EDRHeadroomMonitor = app-lifetime @Observable + 注入式 windowProvider + invalidationCount 测试缝

- **裁决**：query = `(screen?.maximumExtendedDynamicRangeColorComponentValue).map(Double.init)
  ?? 1.0`（CGFloat→Double 边界转换；nil 屏 = 1.0 SDR 安全答）；通知对 = D-COL2 同款双通知
  （NSWindow.didChangeScreen + NSApplication.didChangeScreenParameters），Task per notification
  （PipeCoordinator.screenWatchTasks 同形）；`invalidationCount` 每次重查 +1 供单测断言。
- **理由**：与 13-2 D-COL2 观察者同构但**不交叉**（headroom 数字 ≠ display profile follow）。

## D-08-4-T4-1：三不进断言的实现面

- **裁决**：①export = 数据级钉（`.export` 分辨率下旗 on/off 字节全等 + 剥 gamma 真形态旗 moot）
  + 既有导出 golden 全量复跑（协调器导出面从不消费该旗 = 结构保证，SUMMARY 登记 grep 证据）；
  ②history = 协调器 harness 真实 commit 后 toggle，items/position/instances 三重不变；
  ③sidecar = 真实 commit → flushSidecar 落盘 → 字节快照 → toggle → 再 flush → 字节全等。
  三断言独立用例（L020）。

## D-08-4-X-1：共享树并行竞态处置（执行环境事实）

- 08-3（同 wave）executor 在共享工作树活跃：`build db locked` ×N（重试循环消解）、
  `/tmp/la-direct-tests.log` 被并行测试轮覆写（对策 = 跑后立即私有路径副本
  `/tmp/la-edr-t1.log`）、其未提交 Stack/ WIP 多次挡共享构建（等待其构建闭环 + 归因登记，
  08-2 SUMMARY 先例）。本 plan 每 commit 的绿证 = 08-3 WIP 稳定窗内的隔离复跑 +
  收尾轮全套（08-3 搅动不在本 plan 计数违约面，计划纪律节同款条款）。
