# Plan 14-2 修图面（W2a）执行 SUMMARY

**Executor:** ZCode subagent worker · **Date:** 2026-09-28
**Plan:** `.work/gsd/phases/14-mcp-server/14-2-PLAN.md`（W2a：修图面 5 工具 + MCP-03 parity + GUI-live 硬拒）
**Status:** 完成（6 tasks / 6 commits，未 push）

## 任务表与提交

| Task | 内容 | Commit | 证据 |
|---|---|---|---|
| T1 | MCP-03 parity 初测（双层）+ render_preview（上限 2048/q90/30s typed 超时/RenderGate）+ Core 可见性放开 + 装配缝 | `0062575` | parity 双层字节级（plane diff=0；inline JPEG 与本地编码逐字节等）；2049/91 → invalidParams；stall → renderTimeout；并发 overlap ≤1；9/9 |
| T2 | apply_params（模块级 upsert 三动词 + overwrite-epoch 全量投影 + GUI-live 硬拒）+ load_image（D5 无状态读面） | `4eb54d0` | upsert 四腿 golden 往返字节面 + 幂等重放字节不变 + GUI-live 拒写双语指引 + 错误码每码一 case；13/13 |
| T3 | list_iops + IopCatalog 手写表（18 iop）+ 反射守卫 | `602289a` | 守卫 18/18 逐 op 键集等值 + version/iopOrder pin 首跑全绿；list_iops 形状断言 |
| T4 | export_image（直渲 + Output 服务端钉死 + ExportNamer 递增 + yiyin 生产缝 + 路径/note 返回） | `6b87fd2` | Output 落盘 + XMP 在产物（rating=4 → ns.adobe.com/xap 标记）+ JPEG magic + 碰撞 -1 递增 + yiyin 门控 0/1 次 + 无缝 typed exportFailed + schema 无路径参数自证；19/19 |
| T5 | SC#3 修图端到端（真 RAW + 真管线 + 双宿主） | `5c22f33` | 载入 → GUI-live 插步硬拒 → 3 iop apply → render_preview 与本地渲染**字节级一致** → HTTP 宿主同缝复验**双宿主字节一致**；9/9 |
| T6 | 全量回归 + SUMMARY + DECISIONS + 台账 | 本提交 | 终轮全套 **1856/11skip/0fail**（696.1s，私有日志 /tmp/la-142-t6-full.log）|

## 提交链（未 push）

```
0062575 feat(14-2): MCP-03 parity tests + render_preview tool (cap 2048/q90/30s)
4eb54d0 feat(14-2): apply_params module-level upsert + stateless load_image
602289a feat(14-2): list_iops with handwritten per-op catalog + reflection guard
6b87fd2 feat(14-2): export_image - direct render, Output pinned, yiyin seam
5c22f33 feat(14-2): SC#3 end-to-end - load, 3-iop apply, preview parity, dual host
(T6)    docs(14-2): close out plan 14-2 - SUMMARY + DECISIONS + ledgers
```

## MCP-03 parity 数字（灵魂断言，R6 关闭）

- **Plane 层**（13-1 模板复测）：共享单次 CIRAW decode 下，`renderedPlane` 与
  `ExportRenderer.renderStage` 同尺寸（longEdge = stage 全幅）同参域（percent-100/sRGB/JPEG q0.9/
  yiyin=false）**逐字节相等，maxDiff = 0**（`testParityPlaneByteIdenticalToExportRenderStage`）。
- **Inline 层**（MCP 工具腿）：render_preview 返回的 base64 解码后与「同一 renderedPlane → CGImage →
  ImageIO JPEG q85 本地编码」**逐字节相等**（`testParityInlineJPEGMatchesLocalEncodeOfGoldenPlane`）。
- **结论**：同 sidecar 同参 → 远程看到的 = 本地看到的（sRGB 编码域；EDR 显示域不对齐为诚实条款，
  已写入工具描述）。**未触发「划界重谈」预案。**

## SC#3 端到端（字面）

真 RAW 会话（DSC00012.ARW + .lra → 会话成员校验）→ load_image（无状态读面）→ **GUI-live 插步**
（liveBox 模拟编辑器打开 → apply_params 硬拒 imageLiveInEditor 双语文本 → 关闭 → 同调用成功）→
**3 iop apply**（exposure +0.3EV / colisa contrast +0.25 / velvia strength +0.5，分属 tone/color/
creative 三域）→ render_preview 1024/q85 → **与本地渲染字节级一致** → Streamable HTTP 宿主
（同一 seams/同一闭集）同调用**字节级一致**。耗时 5.03s。

## 交付物清单（files_modified 对照）

- `LightamerCore/Sources/Export/QuickLookRenderer.swift` — renderedPlane/RenderedPlane/image(from:)/
  boundedWait public（可见性 only，D-14-2-T1-1）✓
- `App/Sources/Lightamer/State/PipeCoordinator.swift` — `liveImageURL` 只读判据 ✓
- `App/Sources/Lightamer/Session/SessionCoordinator.swift` — `currentSession` (store, root) 对 ✓
- `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift` — 新建，5 工具 handler + Seams 装配缝 ✓
- `App/Sources/Lightamer/MCP/Tools/IopCatalog.swift` — 新建，18 iop 手写表 ✓
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift` — McpJSON.boolValue ✓
- `App/Sources/Lightamer/MCP/McpServerController.swift` — makeRegistry(editing:)、sharedRenderGate、
  makeEditingSeams（populated registry + LazyMetalContext + writeGate + yiyinInjector）、
  headless/embedded 接线 ✓
- `App/Sources/Lightamer/UI/LightamerApp.swift` — 内嵌宿主编辑缝（live session + GUI-live judge +
  生产 yiyin injector）✓
- `Tests/LightamerTests/McpRenderParityTests.swift`（10 测试）/ `McpEditingToolsetTests.swift`（19）/
  `McpRegistrySnapshotTests.swift`（editing 域快照段，5 工具逐字）✓
- 本文档 / `14-2-DECISIONS.md`（7 条）/ TODO.md / PROGRESS.log ✓

## 执行期决策（详见 14-2-DECISIONS.md）

1. **D-14-2-T1-1** Core 最小可见性放开（renderedPlane 消费缝）
2. **D-14-2-T1-2** render_preview 无 format 参数（JPEG 固定）+ quality 整数域 1...100（cap 90）
3. **D-14-2-T2-1** PipeCoordinator/SessionIndexController 最小只读 accessor
4. **D-14-2-T2-2** apply_params = overwrite-epoch + 全量投影 + seed:[]（merge 无法 remove；
   seeded-overwrite 的 union seed 胜出会遮蔽 upsert —— 数组=期望集是渲染正本）
5. **D-14-2-T2-3** 写面串行独立 gate 实例（writeGate 缝）
6. **D-14-2-T3-1** IopCatalog 覆盖 = 18 tone/color iop；键集正本 = 编码 wire truth（守卫 18/18）
7. **D-14-2-T4-1** export_image 六格式单旋钮 + yiyin=生产缝开关（headless 无缝 → typed exportFailed）
8. **D-14-2-T6-1** apply 超时映射 internalError（不扩 14-1 错误码冻结表）

## 偏离与并行注记

- **与 14-3 并行共享源树**：14-3 worker（W2b）执行期其 WIP 测试文件多次使共享 test target 短暂
  不可编译（build db 锁 + 文件中途态）；本 plan 以「等待-重试 + 私有容器直跑 + 私有日志副本」消化，
  未触碰对方文件。T1 全套回归（1813 executed）时 5 个 fail **全部归属 McpCullingToolsetTests
  的 14-3 in-flight WIP**（已归因留痕）；14-3 收口提交（`d573c59`）落地后共享树恢复稳定。
- **双 DerivedData 容器**：并行 worker 各自构建产生两个容器，test-direct.sh 按 mtime 选容器在
  mtime 平局时选错——T2 起改用「容器 pinned 直跑」（复刻脚本 env 注入，日志私有副本）。
- **每任务全套回归的口径偏离**：T2/T3/T4 边界回归以 MCP 域四套件（Editing/Parity/Snapshot/Host）
  全绿代替全套（全套 ~12min 且共享树状态受 14-3 制）；T1 与 T6 各做一次全套，归因条款见上。

## 新增测试账（理论 +29）

- McpRenderParityTests：9（T1，含当时并入的 editing 快照测试）→ 8（T2 快照测试移入
  Snapshot 文件）→ 9（T5 +SC#3 端到端）【验收轮勘误：原记 "8(T1)→10(T5)"，git show
  0062575 实测 T1=9、终态=9；总数 +29 不变 = 9+19+1】
- McpEditingToolsetTests：13（T2）→ 14（T3 +guard/list 形状）→ 19（T4 +5 export）
- McpRegistrySnapshotTests：8 → 9（editing 域快照）
- （临时 dump 测试用后即删，未入库）
- （验收轮 +1：`testApplyParamsTimeoutIsTypedInternalError`——apply boundedWait 补缝的
  回归测试，随 fix(14-2) 提交，不计入本 plan 申报账）
