# Plan 02-02 Task 02-02-01 — checkpoint:decision 记录

**日期:** 2026-09-18 · **执行者:** GSD executor（自主授权 YOLO，用户可审阅推翻）
**判定:** 八项锁全部确认，无争议项，02-02-02 起按锁执行。

| # | 锁 | 判定 | 依据 |
|---|---|---|---|
| 1 | `IOPModule.process` → Texture 签名：`process(input: any MTLTexture, output: any MTLTexture, roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext) async throws`；`IOPiece.data` 保持 `MTLBuffer?`（uniforms）；Passthrough + kernel 同批迁移（无混合签名编译窗口） | ✅ COSTLY 锁定 | RESEARCH §1.4 建议采纳；纹理是管线货币（缓存/displayTexture/PREVIEW 全是纹理，`dispatch2DTexture` 已存在）；第二个模块出现前是迁移最廉价时点 |
| 2 | `IOPiece.paramsHash: Int → UInt64`，由模块 `commitParams` 内 `StableHash.hash(JSON 编码 params)` 计算 | ✅ COSTLY 锁定 | D-H4：缓存身份原子 == history 身份原子（FNV-1a 64），否则 02-06 sidecar 漂移检测与缓存失效静默不一致 |
| 3 | `PipeCacheKey = (imageID: UUID, pipeType: PipeResolution, position: Int, upstreamHash: UInt64, roi: ROI)`；`upstreamHash` = 从 `decodeParamsHash` 起对启用 piece 的 `paramsHash` 增量 `StableHash.combine`（position 0 混入 decode hash）；`position` 是链内序号非 iop_order；pass-through 时代 ROI 全链恒等（assert 不利用） | ✅ COSTLY 锁定 | pixelpipe_cache.c:99-172 直译；SC#2 失效语义由 hash 链免费获得；Risk #7 不变量 assert |
| 4 | per-pipeType 缓存政策：PREVIEW/THUMBNAIL → per-module 中间缓存 ON；FULL → 只缓存输入平面 + 最终输出，中间 ping-pong 不缓存；EXPORT → 无缓存。编码为 `PipeResolution.cachesIntermediatePlanes` + processRec 分支 | ✅ COSTLY 锁定 | spike-b §4：3×100MP float32 平面 ≈ 4.7GB > 4GB 预算（行 93）；Darktable 同构（pixelpipe_hb.h:346-355 export/thumbnail 不建 history cache） |
| 5 | `PipeCache` 淘汰 = LRU by `lastHit`，字节预算 3GB（`PipeCache.defaultBudget`，D-C1），滞回 evict-to-2GB（0.66×budget）；无 Darktable cacheline 池/老化/size-脏机制 | ✅ 锁定 | 字典 key 结构性免除该机制（RESEARCH §1.2）；MetalContext LRU 同款模式按字节 |
| 6 | `ModuleBox<M: IOPModule>`（Core, public final class, `@unchecked Sendable`）= 类型擦除管线公民：`instanceID/opName/multiPriority/multiName/iopOrder/enabled/paramsData/paramsHash` + `processErased(...)`；`ModuleBoxing` public 协议为擦除接口；管线走 `[Piece] = (box, pieceState)` | ✅ 锁定 | `any IOPModule` 因 associatedtype 不可形成（Phase 1 gotcha）；02-04 registry / 02-05 history 的物化目标 |
| 7 | 纹理契约：缓存平面 write-once-then-read-only（处理期 `[.shaderRead, .shaderWrite]`，产出后只读缓存）；跨 actor 仅经 `@unchecked Sendable` 包装（Phase 1 `RenderedTexture` 所有权契约）；ping-pong scratch 平面管线私有，永不入缓存 | ✅ 锁定 | Risk #6；绝不缓存会被二次写入的纹理 |
| 8 | TestGain 落位：LightamerIOP，整文件 `#if DEBUG`，`opName "testgain"`，`iopOrder 50.5`（与 passthrough_spike 50.5 撞位合法——Darktable 有意 order 撞位先例），不注册任何默认链（仅测试注册） | ✅ 锁定 | Open Question #5 解决；SC#2 演示载体（RESEARCH Validation Architecture） |

**环境注记:** L009 触发——`xcodebuild -version` 4.27s（>2s 阈值），Resilio Sync（pid 668）已 SIGSTOP，复测 0.095s。会话结束 SIGCONT 恢复。

**下一步:** 02-02-02 process 签名迁移。
