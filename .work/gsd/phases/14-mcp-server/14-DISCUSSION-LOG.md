# Phase 14 Discussion Log

## 2026-09-28 — discuss（起草；`.work/config.toml [gsd]` auto=true/paused=false 已查）

- **输入**：ROADMAP §Phase 14（:258-269——MCP-01..10 + SC#1-7 + Notes：筛选能力面 2026-09-26 扩充 /
  MCP-09 组三研究项 A/B/C / MCP-10 launcher V1 用户裁决「agent provider 配置归 agent 自身体系，
  app 零 AI 代码；B 路不做 v2 再议」/ lightroom-mcp 筛片流方法论来源）；REQUIREMENTS MCP 节
  （:477-488）+ Traceability :422-431；**Phase 12 移交清单五条**（12-DISCUSSION-LOG :61-79）；
  **Phase 13 移交面**（⚠️ 13-DISCUSSION-LOG 无签核终节——13-4 已闭环、verify-work 未行，移交面自
  13-CONTEXT :16/:48/:89/:171/:199 + 13-VALIDATION 重构五条，见下）；16-CONTEXT Boundary 不做节
  :23 + deferred :177（MCP catalog 求值 defer 正本）+ D-16-CONTEXT-8 缝体例；16-RESEARCH-QUESTIONS
  F1-F5（keyset 分页形状同源）；16-2 交付的 FilterSQL/SmartAlbums/`FilterDomain` 缝实测
  （`FilterSQL.swift:135-150`）；GOAL-STATE :89 开环指令 + :14 需求登记批（`351817d`）；
  代码锚点实测——`ExportRenderer.swift:8-27`（headless 编排 + yiyin 注入器缝）、
  `QuickLookRenderer.swift`（减法孪生 + 有界超时正本，13-VALIDATION SC#1「QL parity 逐字节」）、
  `SessionIndexStore.swift:561-584`（query 消费面）/:1074/:1177（claim 面 live-target 保护）、
  `FilterSQL.swift:56`（排序白名单）/`:135-150`（FilterDomain 域分派）/`:160`（translateConjoining）、
  `MetadataService.swift:81-:141`（六 API 单源）、`PresetApplier.swift:10-32`（apply=paste 三段同构）、
  `SessionThumbnailProvider.swift:43-50`（tier appointment + has_edits 红线）、`ThumbnailDiskStore.swift:75`、
  `SkinRegionLocator.swift:12`（Vision landmarks + person seg）、`SidecarStore.swift:32/:41-42`
  （per-image actor + 2s debounce——研究项 A 的单进程边界证据）、`SessionIndexSchema.swift:76/:84/:93`
  （has_edits/thumb_state/flag 列）、`LightamerApp.swift:39-65/:1087`（AppDelegate flush + Settings 挂点）、
  `LightamerIOP/Sources/Ashift/VisionDetect.swift`；外部事实核验——官方
  `modelcontextprotocol/swift-sdk` 0.12.1（2026-05-07，spec 2025-11-25，stdio + Streamable HTTP 双传输，
  传递依赖 swift-nio/swift-log/swift-system/eventsource，macOS 13+，tools 6.1）+ 2026-07-28 spec RC
  （stateless core，不预写）。
- **产出**：`14-CONTEXT.md`（Phase Boundary + D-14-CONTEXT-1..12 全按推荐自动裁决，
  **〔晨审追认〕** + 追认清单表含推翻代价列）+ `14-RESEARCH-QUESTIONS.md`（RQ-14-1..15，
  P0/P1 分级 + research 首探针三项标注）。
- **Phase 13 移交五条（重构提取，orchestrator 审）**：①**XMP 三格式内嵌复审位转记 Phase 14 同批**
  （13-CONTEXT :199 原文；本环处置 = **关闭**——v1 MCP 元数据真身 = sidecar/lindex 不经内嵌 XMP，
  deferred 留痕）；②**34 列 frozen-spelling 契约跨进程延伸**（13-CONTEXT :89——Spotlight importer
  先例；MCP list_photos 读同库同契约，列终表改动须过 frozen 断言）；③**QL 渲染孪生先例**
  （QuickLookRenderer = ExportRenderer 减法孪生 + 三查回退 + 有界超时——MCP render_preview 的形状
  正本与 parity 测试模板，13-VALIDATION SC#1）；④**lindex 只读投影纪律先例**（Spotlight 形态——
  MCP 筛选读面同款只读纪律，34 列单源）；⑤**分发/公开仓形态既定**（unsigned unhardened + MIT +
  审计闸已立——swift-sdk 新依赖与端口/token 安全面代码入公开树 = 14-4 走查批审计注意项；CI
  macos-27 runner 可承载 MCP 测试）。
- **关键裁决摘要**：官方 swift-sdk 0.12.1 pin + spec 2025-11-25 + **Core 零 import**（registry 纯
  Swift 缝收口，SPM 第二次扩军登记）；单内核 × 双宿主（GUI 内嵌 HTTP @ 127.0.0.1 + CLI 无头 stdio
  为主）× 端点发现文件（`.lightamer/mcp-endpoint.json` 协议）；工具粒度 = 一动词一工具 ~18 个 +
  **tools/list 快照断言**（工具面即安全面）；图片 = base64 inline 单通道 + 默认上限表 +
  export_image 唯一落盘例外；研究项 A 预裁 = 元数据写 MetadataService 单源汇合 + params 写对
  GUI-live 图 typed error + 端点文件单实例锁（后开者只读降级）；安全 = 127.0.0.1 硬编码 + 非回环
  token 必须 + load_image 限会话成员 + 无 shell/删除/移动/上传；修图 = ExportRenderer 减法孪生 +
  MCP-03 口径钉 sRGB 编码域（GUI EDR 域不对齐，QL 预览语义跨域）；筛选 = FilterSQL 直连零新层
  （12 移交③兑现）+ 双档直读 + burst 查询层聚类 + SkinRegionLocator 脸框复用；Catalogs = v1 恒
  会话域（16 期字面 defer），FilterDomain 缝留而不接；launcher = 用户自担 shell 模板 + 占位符 +
  日志面板 + 串行（与 EXP-08 路径制纪律**显式不同源**：用户 = 命令作者）；研究项 B = history
  append 既有语义、版本面 defer v2，C = 零实装零 schema 占用（封闭枚举下预留未实现 = 假 API）；
  波次 = 4 plans / 3 waves（14-1 底座含 stdio hello-world 探针 → 14-2 修图 ∥ 14-3 筛选 → 14-4
  launcher+收口）。
- **识别到的新分叉/风险**：①**研究项 A 仍是头号架构风险**——预裁三策（单源/拒写/锁）覆盖了
  已知路径，但「GUI-live 判据来源」（PipeCoordinator 活动集的精确形态）与「锁原语选型」
  （O_EXCL vs flock）必须 research 走查终判，MCP 直写 SidecarStore 字节是永禁红线；②**swift-sdk
  0.x churn**——0.12.1 pin 是止损不是保险，spec 2026-07-28 RC 的 stateless core 若成 stable，
  SDK 大版本升级 = 适配器层修正（registry 缝是唯一防波堤）；③**headless 进程可行性未证**——
  SwiftUI @main 进程剥离 NSApplication UI 循环跑 server 未验证（回退 = executor 新 target，
  RQ-14-1 探针头项）；④**MCP-03 口径预期差**——「与本地 GUI 渲染量化一致」的字面在 EDR/soft
  proof 域不可满足，CONTEXT 已钉 sRGB 编码域口径，但 SC 字面与口径的差需晨审知悉；⑤**token
  安全面公开**——GitHub 公开仓 + 端口/token 代码公开 = 实现走查必须含安全审计（14-4）；⑥
  **launcher shell 模板与 EXP-08 纪律不同源**——两处 Process 执行面一窄（路径制）一宽（用户
  模板），文档必须写清分界，防审计误报与纪律漂移；⑦**burst 阈值/脸框 Vision 批量成本**——
  万张会话 get_face_regions 的 Vision 延迟未计量（RQ-14-10 探针），缓存策略影响 SC#6 可用性。
- **晨审注意**：12 项均为推荐项自动裁决，用户晨间任一推翻 → 回注 planner 重开受影响面
  （推翻代价列在 CONTEXT 追认清单表）。特别提请过目：**D-1**（swift-sdk SPM 依赖扩军——依赖
  最小化约束第二次修订，与 PROJECT.md 收口修正绑定）与 **D-6**（load_image 限会话成员——
  MCP-01「Session/RAW 路径」的收敛解释，v1 不开任意绝对路径）与 **D-7**（MCP-03 口径钉
  sRGB 编码域——SC 字面「与本地 GUI 渲染量化一致」在 EDR 域不可满足的诚实条款）。
