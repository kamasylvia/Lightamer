# Phase 13 Discussion Log

## 2026-09-27 — discuss（起草；`.work/config.toml [gsd]` auto=true/paused=false 已查）

- **输入**：ROADMAP §Phase 13（:209-232——SYS-01..05/DIST-01..04/COLOR-02/03 十一需求 + SC#1-4 +
  Notes 扩展独立 entitlements/deep-sign/notarytool warnings=errors/Bundle.main 纪律 + :232
  蒙版命令面 UI 批登记 + :319 蒙版算法扩展 v2 节）；REQUIREMENTS SYS/DIST/COLOR 节
  （:212-216/:220-223/:166-167）+ Traceability :384-421；**Phase 12 移交清单五条**
  （12-DISCUSSION-LOG :48-101：DB v2 34 列 = Spotlight 索引源 / XMP 例外集复审位[HEIF/
  AVIF/WebP，Phase 14 同批] / Quick Filter+谓词翻译层 = MCP 消费面 / `.lightamer-preset` =
  MCP-09 上游 / Manual-Only 13 行承接 + F-12-5-2 随色彩批同轮）；09-CONTEXT（D-09-CONTEXT-2
  `.lightamer/` 落位 :41 / 双档缩略图硬约束 :77 / teardown 五步 :82）；代码锚点实测——
  `Project.swift:27-48`（Manual signing + Developer ID 切换预告 + per-config hardened）、
  `ColorOutModule.swift:54-56/:76/:79-95/:101-109/:128`（D-COL3 预留位 + 双 override socket
  先例）、`DisplayProfile.swift:31-32/:53-82/:104-123/:136-151`（Phase 13 预告 + 四级匹配 +
  stableID 翻键 + workalike 注释）、`SessionIndexSchema.swift:49/:66-102`（34 列冻结）、
  `ExportRenderer.swift:1-56`（headless 全链无 PipeCoordinator——QL 渲染孪生模板）、
  `SessionThumbnailProvider.swift:63/:112` + `ThumbnailDiskStore.swift:75`（双档资产读面）、
  `EditorMTKView.swift:12/:318`（D-13 near-static + fit/100% 预留注释）、`ViewportFit.swift
  :7-16/:33`（三消费者单点数学）、`EditorAreaView.swift:227`（SpatialTapGesture 既有锚）、
  `EmptyStateView.swift:57`（onDrop fileURL 先例）、`AdjustmentLayer.swift:43/:76-81` +
  `MaskCombiner.swift:47/:266`（蒙版命令内核语义全在）、`MaskToolbarView.swift`（334 行）/
  `LayersPanelView.swift`（673 行）/`LayerEditingState.swift`（325 行）三件套、
  `Resources/Localizable.xcstrings`（zh/en 1000+ 键——SYS-05 收口判据）、git remote
  （ADO 私有，无 LICENSE/无 `.github/`——DIST 面零起点）、TODO :296（蒙版命令面 + GUI-19/
  GUI-20 登记）/:302（v2 排除表）。
- **产出**：`13-CONTEXT.md`（Phase Boundary + D-13-CONTEXT-1..10 全按推荐自动裁决，
  **〔晨审追认〕** + 追认清单表含推翻代价列）。
- **关键裁决摘要**：QL = 单 appex 双能力（thumbnail+preview 同 QLPreviewingController）+
  非沙盒 + 薄壳逻辑下沉 Core；QL 数据源三查回退链（thumbs 直读 → headless 渲染@请求尺寸 →
  档 A 嵌入预览）+ 预览语义 = 编辑器视口孪生（sRGB 终态、无 yiyin/导出 sizing）+ 渲染有界
  超时；Spotlight = lindex 只读行读 + 标准属性集映射（34 列 = 抽取源，移交①字面承接）+
  自定义 schema defer；软打样 = 显示腿 runtime override（形状同 displayProfileOverride
  per-run data 先例）+ colorout 上游 proof 段（rel-colorimetric + BPC）+ ColorSync 腿 +
  OOG gamut check 黑裁剪 + **BPC 可达性探针先行**；多显示器 = 通知 + window↔screen 追踪 →
  既有 re-resolve/翻键（三层已交付底座）+ Settings 手动覆盖（顺带还 fallback 腿 exact-TRC
  文档债）；手势 = AppKit NSGestureRecognizer 面 + fit/100%/自由 zoom + ViewportFit 单点
  扩展 + crop/liquify/retouch 激活锁 fit 互斥；拖放 = 默认复制入 Capture/（Option=Move）+
  网格/编辑器双落点 + openSession 路由复用；分发 = MIT + GitHub 新仓全历史（敏感审计前置
  闸）+ Developer ID 切换 + notarytool warnings=errors + DMG/zip 双载体 + CI tag 流水 +
  凭据人工阻塞项登记；蒙版命令面批 = 13-3 UI 装配（内核零改，GUI-19 同批/GUI-20 挂 13-4）；
  波次 = 4 plans / 3 waves（13-1 扩展底座根 → 13-2 色彩 ∥ 13-3 交互 UI → 13-4 收口）。
- **识别到的新分叉/风险**：①**BPC 可达性 = COLOR-02 头号技术不确定**——CGColorConversionInfo
  的黑点补偿无公开开关证据，探针不可达则 proof 段手做黑点补偿或降级注记，管线形状二选一在
  research 定；②**overlay zoom 化是 SYS-03 最大回归面**——crop/liquify/retouch host 坐标
  假设 fit 布局（06-06 遗留），v1 互斥锁 fit 是风险摘除策略，zoom 内编辑 defer；③**appex
  非沙盒 vs 系统惯例**——QL/Spotlight 扩展常见沙盒形态，本项目为读 `.lightamer/` 兄弟资产
  选非沙盒一致主 app（分发合规面不受影响，但属非典型形态，Gatekeeper 走查必须覆盖 appex
  单体）；④**凭据断链风险**——Developer ID 证书/AC API key/GitHub 仓公开是人工供件，13-4
  前不就位即阻塞，须在 GOAL-STATE 阻塞节早登记；⑤**公开仓敏感审计**——全历史推送为默认，
  审计闸（凭证/内部域名/绝对路径扫描）是 13-4 第一任务，命中改 squash 起点是用户裁决位；
  ⑥**QL 预览语义预期差**——「编辑态」非「导出成品态」（无印框），UX 文案须诚实（plan 教学节
  已入 CONTEXT specifics）；⑦34 列契约跨进程延伸——importer 读面改动须同批过 frozen-spelling
  测试（移交①原文），否则 Spotlight 抽取源静默漂移。
- **晨审注意**：10 项均为推荐项自动裁决，用户晨间任一推翻 → 回注 planner 重开受影响面
  （推翻代价列在 CONTEXT 追认清单表）。特别提请过目：D-1（appex 非沙盒——与系统常见沙盒
  扩展形态不同，是否接受该非典型形态）与 D-8（GitHub 全历史推送 vs squash 起点——公开仓
  不可逆决策，默认全历史 + 审计闸）。
