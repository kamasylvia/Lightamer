# Phase 12 Discussion Log

## 2026-09-26 — discuss（起草；`.work/config.toml [gsd]` auto=true/paused=false 已查）

- **输入**：ROADMAP §Phase 12（META-01..06 + PRES-01..04 + IOP-COLOR-08 + SC#1-4 + Notes
  preset 不互通 locked / IOP-COLOR-08=PRES-03 同 feature / .cube 显式应用色彩空间）；
  REQUIREMENTS META/PRES 节 + MCP-06（:466 set_rating/set_flag/set_color_label/append_note
  「复用 Phase 9 批量管线」黑体）/ MCP-09（:469 上游依赖）+ Out of Scope 表；
  09-CONTEXT（D-09-CONTEXT-5 skip 集 / D-09-CONTEXT-7 预留列 / SESS-07 真身 / `.xmp`
  永不红线 :27）+ 09-01 交付面（SessionIndexSchema v1 冻结 25 列 + EXIF 轻量列 + v99 拒开）；
  **Phase 11 移交清单五条**（11-DISCUSSION-LOG 终节：recipe Codable 直挂 PRES /
  WebP mux 复审位 / XMP rating-flag API 位 / yieldsToEditor+perf（Phase 15，与本 phase
  无关但记录）/ META-03 汇合点）；**XMP 宿主事实**（11-02 D3 五途径字节级验证全不序列化 +
  D8 WebP 零 mux——硬约束）；02 侧车 conventions（schema v1→v2 additive 先例 / ONE-WAY
  格式锁 / UInt64String）；darktable 参考（`collection.h:74-136` 过滤属性枚举 /
  `collection.c:1355` 谓词→SQL / `tags.c:817/:939` 层级关键字 path 语义 /
  `lut3d.cl:29-60` tetrahedral 正本 / `lut3d.c:1029-1031` 应用色彩空间 / `iop_order.c:261`
  v50 lut3d=36.0）；现有 UI 锚点（`SessionBrowserView.swift:139-149` rating overlay 壳 /
  `ContentView.swift:37` BrowserMode 三态 / `InspectorView.swift` 面板体系 /
  `V50Order.swift:126` lut3d 槽位已预留）。
- **产出**：`12-CONTEXT.md`（Phase Boundary + D-12-CONTEXT-1..10 全按推荐自动裁决，
  **〔晨审追认〕** + 追认清单表含推翻代价列）。
- **关键裁决摘要**：sidecar v3 五字段真身 + DB v2 首次真迁移（flag/note/EXIF 七列——
  识别到 25 列 v1 无 MCP-06 过滤前提，新分叉）；`.xmp` 红线语义澄清不推翻（禁原片旁附件，
  非禁 XMP 格式）+ 自建 XMP 序列化/注入 + 第三方 .xmp 只读导入；层级关键字 `|` path +
  打子隐含父；智能相册 app 级存储 + 求值域 = 当前会话（跨会话 defer）；`.lightamer-preset`
  统一容器 kind:develop|export + paste 同构 apply + recipe 直挂（移交①兑现）；LUT
  tetrahedral texture3d + V50 36.0 已预留 + 应用色彩空间选择器 + 导入库（预设可移植）；
  过滤 UI = grid 工具条 chips + Quick Filter + 谓词/SQL 单一翻译层（智能相册同代码）；
  评分 UI 兑现 = overlay 接线 + 全域快捷键 + MetadataService 单源（**元数据写不翻
  paramsHash、缩略图不 stale**——防万张重渲染陷阱）；波次 = 5 plans / 4 waves
  （12-1 依赖根，12-2∥12-3 并行）；兜底矩阵 = JPEG/TIFF/PNG 内嵌 + HEIF/AVIF/WebP
  例外反向锚（11 遗留 #5/#6 延续）。
- **识别到的新分叉/风险**：①25 列 v1 无 flag/note/camera/lens/iso/focal 列——DB v2
  迁移是 Phase 9 冻结契约的首次真例外，列集须在 12-1 research 一次扫全下游（Phase 13
  Spotlight/Phase 14 MCP）；②`CGImageMetadataCreateXMPData` 序列化端未验证（11-02 D3 只
  证伪写入端）——12-3 research 头项探针；③元数据写与 paramsHash 的隔离是隐性性能契约，
  需测试断言显式钉死；④LUT float16 vs float32 纹理精度论证（HDR 域 LUT）入 research。
- **晨审注意**：10 项均为推荐项自动裁决，用户晨间任一推翻 → 回注 planner 重开受影响面
  （推翻代价列在 CONTEXT 追认清单表）。特别提请过目：D-2（红线语义澄清——「只读导入」
  是否越过用户对红线的预期口径）与 D-1（DB v2 迁移——Phase 9「never migrate」契约的
  显式例外条款）。

## 2026-09-26 晨审追认（用户裁决）

- **D-12-CONTEXT-1..10 全部追认**——含两大分叉：D-1（DB v2 首迁移 = Phase 9「never migrate」首次显式例外，34 列冻结集确认）与 D-2（`.xmp` 红线口径澄清：禁原片旁 .xmp 附件文件，XMP 格式不禁；自建序列化内嵌导出容器 + 第三方 .xmp 只读导入）。无推翻项。
