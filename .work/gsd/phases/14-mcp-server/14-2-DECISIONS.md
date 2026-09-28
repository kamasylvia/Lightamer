# Plan 14-2 执行期决策（DECISIONS）

> Executor: ZCode subagent worker · 2026-09-28 · plan `.work/gsd/phases/14-mcp-server/14-2-PLAN.md`
> 全部为执行期决策（plan 纪律 6 条申报位）；无推翻 CONTEXT/research 裁决项。

## D-14-2-T1-1: Core 最小可见性放开（renderedPlane 消费缝）

- **决策**：`QuickLookRenderer.renderedPlane` / `RenderedPlane` / `image(from:)` / `boundedWait`
  从 internal 改 `public`——**可见性变更，零函数体改动**。
- **背景**：plan §RQ-14-4 要求 MCP 腿「直接消费 renderedPlane 而非 preview()」，但该形状 13-1
  交付时仅 internal（QL 扩展消费 public 的 `preview()`）。App 层 EditingToolset 无法触及 internal 符号。
- **理由**：MCP 腿是同一条已验证无头链的第三消费面（QL pane → 13-1 parity → MCP inline）；重写即
  第二实现，违背「接线 phase」纪律。boundedWait 同步 public 使超时常量族单源（McpTimeouts ↔ QL 常数）。
- **代价/回退**：Core 公开面 +4 符号；替换实现 = 恢复 internal（单点）。

## D-14-2-T1-2: render_preview 参数域

- **format 参数：v1 砍除，JPEG 固定**。research §RQ-14-8 预算表实测支持「JPEG 为主」
  （HEIF client 支持面窄、PNG lossless 5-8× token 灾难）；单值 enum 是 schema 噪声。未来扩展 = schema
  additive + 快照显式改。
- **quality 为整数百分比 1...100，默认 85 / 上限 90**（D7 落码：>90 → invalidParams，含
  export_image 指引文本；>2048 longEdge 同理）。整数域对 LLM 比浮点 0...1 更不易错。

## D-14-2-T2-1: PipeCoordinator.liveImageURL 只读访问器 + SessionIndexController.currentSession

- **决策**：App 层两个最小 accessor——`PipeCoordinator.liveImageURL`（GUI-live 判据，
  MainActor-hop 读 currentImageURL）与 `SessionIndexController.currentSession`（(store, root) 对，
  openAndSync 记录 / close 清除）。均为只读投影，零写路径改动。

## D-14-2-T2-2: apply_params = overwrite-epoch 粘贴 + 全量投影 + seed:[]（本 plan 最重语义决策）

- **决策**：apply_params 组合**期望全量实例集**（disk truth + ops 投影；pristine = editing seed），
  经 `SessionBatchApplier.apply(mode: .overwrite, seed: [])` 单图单 epoch commit 落三段。
- **为什么不是 merge-paste**：merge 是 append-only history——**remove 动词无法表达**（旧记录仍从
  更早 history item 投影回来）。
- **为什么不是 seeded-overwrite（PresetApplier 字面同构）**：`.overwrite` 分支的持久化数组 =
  `v50(union(seedPlusBase, recast))`，union **primary（seed）胜出碰撞键**——seed 的 exposure
  默认参数会遮蔽 agent 上写的 exposure 参数（payload 记录被丢弃）。history 归 history，但
  ExportRenderer/QL/MCP 渲染读的是 `document.instances` 数组 → **渲染与写入意图分叉**。seed:[] +
  全量投影使数组恰等于期望集（碰撞时 base/投影记录字节一致），三动词（upsert/enable/remove）一次
  落齐，且 ⌘Z 一步回退（epoch 语义）。
- **幂等条款**：投影 == 当前数组 → 整体 no-op（"applied=nothing"）——同参重放字节不变
  （RQ-14-5② 幂等重试安全），由 `testApplyParamsIsByteIdempotent` 字节面钉死。
- **落盘时点**：apply 返回前 `writer.flushForTeardown()` 有界排空——agent 的下一次 render_preview
  读到的必然是新状态（「已保存编辑态」诚实条款的自洽前提）。
- **测试边界**：12-4 的 GUI preset 走 merge 模式不受影响；GUI overwrite 粘贴的 seed-遮蔽为**既有
  潜在 quirk**（不在本 plan 范围，建议 14-4 收口批复核）。

## D-14-2-T2-3: 写面串行 = 第二 McpRenderGate 实例（writeGate 缝）

- **决策**：apply_params 在 `Seams.writeGate`（FIFO 互斥 actor，类型复用 McpRenderGate）内执行，
  生产装配独立于渲染 gate 实例。§RQ-14-14「写面全局 actor 串行——请求级排队非拒绝」的单实现。

## D-14-2-T3-1: IopCatalog 覆盖清单 = 18 个 tone/color 标量域 iop

- **决策**：temperature / exposure / toneequal / equalizer / channelmixerrgb / colorbalancergb /
  sigmoid / agx / filmicrgb / colisa / tonecurve / levels / shadhi / colorcontrast / velvia /
  vibrance / colorzones / monochrome（18，agent 可调的 grading 核心面）。
- **排除**：几何/payload 模块（crop/flip/ashift/lens/liquify/borders/watermark/textOverlay）、
  降噪族（nlmeans/denoiseprofile/bilateral）、其余 creative 滑杆（highpass/sharpen/bilat/soften/
  skinsmooth/lut3d/vignette/grain/bloom/hazeremoval）——参数为复杂嵌套 payload 或低频调节面；
  apply_params 仍接受它们（catalog 是键参考不是白名单）。扩展 = additive 表行 + 守卫自动覆盖。
- **键集正本 = 编码 wire truth**：手写表逐 op 对照「模块默认参数经 ParamsCoding 编码后的 JSON 键集」
  （_dump 测试一次性导出全部 seed 记录键集后落表，导出测试即弃）——比 CodingKeys 声明更强
  （encodeIfPresent/可选键的省略形态直接可见）。修正一处：colorbalancergb 无 `midtonesWeight`、
  有 `maskGreyFulcrum`。守卫测试（18/18 逐 op 键集等值 + version/iopOrder pin）常驻防漂移。
- **type 注记口径**：range/enum 域仅在源码 pin 死处标注（exposure/temperature/colisa 等），其余用
  基元类型名；守卫不裁 type 串（只裁键集 + version）。

## D-14-2-T4-1: export_image 参数面口径

- **六格式单旋钮**：format 串选型，lossy 格式（jpeg/heic/avif/webp）吃 quality；png/tiff 用默认
  位深（eight/eight+zip）——bit-depth 菜单 = additive 参数位，v1 不开。
- **yiyin 语义钉死为「生产缝开关」**：default false 不跑 injector；true 无缝（headless）=
  typed exportFailed。injector 实际画布行为由 08/11 期 golden 覆盖，此处只测缝的门控（0/1 次计数器）。

## D-14-2-T6-1: apply_params 超时的错误码映射

- **决策**：apply 体经 `boundedWait(McpTimeouts.apply=10s)`；超时映射 `internalError`
  （"apply_params timed out..."）。McpToolError 枚举无 apply 专用超时码，不为此扩 14-1 冻结表；
  组合写（compose+claim+enqueue+flush）在 10s 预算内余量大，超时即内部异常语义。
