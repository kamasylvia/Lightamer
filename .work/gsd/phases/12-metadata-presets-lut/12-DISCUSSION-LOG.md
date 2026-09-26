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

## 2026-09-27 — 签核终节（12-5；SC#1-4 证据指针 + Phase 13 移交清单 + 遗留对表）

> 正本 = `12-VALIDATION.md` 对照表（三列证据逐条）。本节只留指针 + 移交 + 遗留。

### SC#1-4 证据指针

| SC | 判定 | 一手证据锚 | 测试锚 | GUI 实证锚 |
|---|---|---|---|---|
| SC#1 元数据编辑 + sidecar/XMP 双写 | ✅ | sidecar v3 五字段 + MetadataService 六 API + XMPWriter 三格式注入 + DB v2 34 列 | SidecarMetadataV3 9 + Migration 11 + MetadataService 11（含 12-5 promotion）+ XMPWriterTests | 12-1 走查 6 证据 + 12-3 走查 4 证据 |
| SC#2 过滤/排序/智能相册 | ✅ | FilterPredicateGroup + FilterSQL（四联式祖先谓词）+ SmartAlbums；**排序键口径 = checker W-2 声明（过滤 16 字段全覆盖/排序六键 D-7）** | FilterPredicate/FilterSQL（快照+精确行集+对照组）+ SmartAlbumStoreTests | 12-2 走查（chips/QuickFilter/排序/侧栏第四区） |
| SC#3 预设系统全链 | ✅ | .lightamer-preset 容器 + PresetsStore + PresetApplier（paste-twin 等价性）+ 管理器 + ExportRecipe 直挂 | Container/Store/Applier 三族（等价性核心 + 万张门 0.679s） | 12-4 走查 8 证据（含 export 预设三次真实导出字节全等） |
| SC#4 .cube LUT iop | ✅ | CubeLutParser（DOMAIN remap 超 dt 面 F4）+ tetra/trilinear/1D kernel + 四态色彩空间矩阵 + LutLibraryStore + LutPanelView | Parser 22 + Kernel 8 + Golden 5 + Store 10 + Wiring 断言 | 12-5 启动 zh smoke + 会话打开截图；深交互 F-12-5-1 Manual-Only |

### Phase 13 移交清单（五条）

1. **DB v2 34 列 = Spotlight 索引源**（SYS 面）：rating/color_label/keywords/flag/note
   五元数据列 + EXIF 七列已在索引库（12-1 T2/T5）；Spotlight importer（Phase 13）直接以
   该列集为抽取源——列集冻结断言（SessionIndexStoreTests 34 列 verbatim）即schema 契约，
   importer 读面改动须同批过 frozen-spelling 测试。
2. **XMP 例外集复审位**（HEIF/AVIF/WebP，Phase 14 同批）：12-3 已证宿主对三格式不序列化
   XMP packet（mountXMP tally 反向锚在）；Phase 13 SYS-01 Spotlight 与 Phase 14 MCP 若需
   三格式元数据载体，复审输入 = 12-3-SUMMARY 例外集 + 11-02 D3/D8。
3. **Quick Filter/谓词翻译层 = Phase 14 MCP 筛选工具直接消费面**（MCP-05..08）：FilterSQL
   `translate(_:)` 单一函数 + `SessionIndexStore.query` 即 MCP list_photos 筛选参数的
   服务端语义（结构化谓词 JSON 可直作 MCP 工具入参 schema）；零新翻译层。
4. **`.lightamer-preset` = MCP-09 preset 三件套上游**：PresetsStore CRUD/Applier 路由
   （targetsProvider/livePaste 闭包缝）即 MCP 侧 apply_preset/set_preset 的现成管线；
   partial apply 语义（复用 9-4 对话框的 `filtered(by:)`）为 MCP 面的子集应用参照。
5. **Manual-Only 13 行承接**（VALIDATION 汇总表）：全部「自动化腿已钉数值/语义」型；
   Phase 13 verify-work / 发布前走查批量人工确认；其中 F-12-5-2（dt-GUI golden 交叉
   对照）建议随 Phase 13 色彩管理批（soft proofing）同轮做——同一 dt 参考环境。

### 遗留对表（各 plan SUMMARY 遗留合并；零静默）

| # | 遗留 | 来源 | 处置 |
|---|---|---|---|
| 1 | ~~sidecar_present 永不刷新（先图后 sidecar 行）~~ | 12-2 | **12-5 已闭环**：backfill 第三 pending 类 promotion（`9e70338` + `testBackfillPromotesLateSidecarRows`）；GOAL-STATE 阻塞#4 关闭 |
| 2 | ~~convertTexture L029 镜像 + 双腿 parity~~ | 11-02/11-03 | **11-05 已闭环**（12-5 收口复核复跑绿，零残留） |
| 3 | ~~12-4 D10 LUT 跨机器前提复核~~ | 12-4 | **12-5 已关闭**：LutLibraryStore 落库兑现（D10 复核注记） |
| 4 | rgba16Float 默认被 golden 门槛破 → rgba32Float 升格 | 12-5 D7 | §6.4 预案正身（kernel 零重写）；129³ 34MB 内存预算在账；如需省内存可回 half + 相对容差（DECISIONS D7 记录） |
| 5 | dt golden 参考为 CPU float64 双写（非 dt-cli 直出） | 12-5 | L017 先例在案（dt-cli 本 host 空间损坏）；dt-GUI 人工对照 = F-12-5-2 |
| 6 | 真实 .cube 变体网络采集未成（px 代理链不可达 + 探测未命中） | 12-5 | 预案合成替代落账（D5）；真实脏样本出现时补 fixture 入 `input/cube/` |
| 7 | LUT 面板深交互（导入驱动/picker/toast 观感） | 12-5 | F-12-5-1 Manual-Only（store/wiring 单测钉逻辑） |
| 8 | 万张门数字为 Debug/SSD 计量（0.457s/0.679s） | 12-1/12-4 | Release 门 ≤5s 余量 ~11×；Release 复测随 Phase 15 perf 清算 |
| 9 | Quick Filter IME 候选吃键（L032）走查受限 | 12-2 | F-12-2-1 Manual-Only（AX 直点可达） |
| 10 | XMP IPTC Core 扩展字段全表 | 12-3 | defer 面（EXIF 编辑面板 v2；RESEARCH §8.4 在案） |

### 签核判定

**Phase 12 签核：PASS（SC#1-4 ✅；status: validated + nyquist_compliant: true；终轮
1436/6skip/0fail；基线演变 1258→1436 净增 178）。** 三处移交消费全部闭环（行 1-3）；
Manual-Only 13 行 pending-manual 不阻塞；**C 档第 3 停**按夜间授权先例
（D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1）先翻账、晨审追认——用户晨间可推翻
（推翻 = 回注修复批）。
