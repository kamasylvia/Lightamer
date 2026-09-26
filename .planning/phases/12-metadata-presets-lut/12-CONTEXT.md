# Phase 12: Metadata, Rating, Presets & LUT - Context

**Gathered:** 2026-09-26
**Status:** Draft for planning — 10 项 OQ 全按推荐自动裁决〔晨审追认〕（D-12-CONTEXT-1..10，追认清单表见 decisions 末）；Phase 11 移交清单五条已逐条对位（11-DISCUSSION-LOG 终节 ↔ 本文件 `<code_context>` Integration Points）

<domain>
## Phase Boundary

本 Phase 把 Phase 9 建好的「会话骨架」填充为「可组织的照片库」，并交付两条独立能力线（预设、LUT）：11 项需求（META-01..06 + PRES-01..04 + IOP-COLOR-08）。核心架构事实：

1. **元数据真身恒 sidecar，索引列恒缓存**（SESS-07 黑体延续，D-12-CONTEXT-1）——Phase 9 预留的 `rating`/`color_label`/`keywords` 三列（`LightamerCore/Sources/Session/SessionIndexSchema.swift:76-78` 注释即本 Phase 回填义务）从本 Phase 起从 sidecar 回填；「写索引不写 sidecar」= 评分在删库重建后蒸发，违背 Phase 9 契约。**元数据写入不产生 history 项、不翻 `paramsHash`（→ 缩略图不 stale 再生）**——评分不是管线参数变更；sidecar 重写经既有 sidecar_mtime 漂移检测走行回填，零新渲染路径。
2. **`.xmp` 红线语义澄清后不推翻**（D-12-CONTEXT-2，本 Phase 最大分叉）——Phase 9 红线「.xmp 读写删永不」（09-CONTEXT:27）针对的是**原片同目录 `.xmp` 附件**（C1/Darktable sidecar 形态）；XMP **格式本身**不是禁区。META-04 的「标准 XMP 同步」= ①导出图**内嵌** XMP packet（自建序列化 + 容器注入——宿主 ImageIO 五途径全不序列化 XMP，11-02 D3 字节级验证是硬事实）+ ②第三方 `.xmp` 只读导入（桥不写）。原片旁 `.xmp` 写入仍永不。
3. **DB 首次真迁移落在本 Phase**（D-12-CONTEXT-1）——Phase 9 冻结契约「later plans CONSUME, never migrate」的例外条款由 META-05 触发：25 列 v1 **不含**相机/镜头/ISO/焦距/光圈列（只有 `orientation/width/height/capture_date` 四个 EXIF 轻量列，`SessionIndexSchema.swift:64-70`），也没有 `flag`/`note` 列（MCP-06 set_flag/append_note 的过滤前提）；`SessionIndexSchema.schemaVersion = 1` 且 `>1 → REFUSE`（`SessionIndexSchema.swift:23`）→ 本 Phase 升 v2 = additive ALTER + 迁移函数，`v99 拒开`语义保留、`1 → migrate to 2` 语义新增。
4. **预设 = 磁盘上的同构快照，apply = Phase 9 paste 同构路径**（D-12-CONTEXT-5）——`.lightamer-preset` 与 9-4 剪贴板 PastePayload 同构（instances + skip 集语义一致，D-09-CONTEXT-5 正本）；`ExportRecipe`/`ExportVariant` 已 Codable 零哈希字段（Phase 11 移交①），挂载是接线不是重造。
5. **LUT 是标准互操作点，预设不是**（ROADMAP §Phase 12 Notes locked）——`.cube` 走标准解析（1D/3D + DOMAIN_MIN/MAX + tetrahedral，`data/kernels/lut3d.cl:29-60` 移植正本）；V50Order 36.0 槽位**已预留**（`LightamerCore/Sources/Foundation/V50Order.swift:126`）；应用色彩空间选择器是防「sRGB authored LUT 应用在 Rec2020」bug 的显式参数（INTEROP-2/3 风险正主），dt 同款 lut_profile ↔ work_profile 转换（`darktable/src/iop/lut3d.c:1029-1031`）。

**Phase 12 不做**：

- **写原片旁 `.xmp` 附件 / 与 Darktable sidecar·预设互通**——红线不动（D-12-CONTEXT-2）；Out of Scope 表已锁（REQUIREMENTS:271-272）
- **跨会话智能相册求值**——v1 智能相册求值域 = 当前打开会话（跨会话聚合需多 session.lindex 联合查询，新架构面，defer v2，D-12-CONTEXT-4）
- **MCP-06/MCP-09 工具面本体**——MCP-06（set_rating/set_flag/set_color_label/append_note）与 MCP-09 preset 三件套是 Phase 14；本 Phase 交付其**上游服务层**且要求 GUI/MCP 同源单实现（D-12-CONTEXT-8）
- **EXIF 写回修正面全量**（拍摄时间/版权编辑器）——v1 只同步评级/色标/关键字/flag 的 XMP 面 + EXIF properties dict 既有路（11 移交⑤）；完整元数据编辑面板 defer
- **IPTC IIM legacy 写入**——XMP packet 内含 IPTC Core 等价字段（dc:subject 等）；IIM 老格式不写
- **预设内蒙版/层栈快照、LUT 打包进预设**——层栈含蒙版几何坐标绑图、粘贴语义未定义（D-09-CONTEXT-5 同源）；LUT 经导入库引用不打包（D-12-CONTEXT-5/6）
- **Quick Look/Spotlight 元数据出口**——Phase 13 SYS 面（本 Phase 的 DB 列是其索引源）
- **搜索语法式过滤（dt 式 `rating>=3 lens:X100` 文本查询语言）**——v1 = 结构化谓词 chips + 行内 Quick Filter（D-12-CONTEXT-7）
</domain>

<decisions>
## Implementation Decisions

> 10 项 = discuss 起草识别的 OQ，全部按推荐项自动裁决〔晨审追认〕。晨间任一推翻 → 回注 planner 重开受影响面（推翻代价见追认清单表）。

### D-12-CONTEXT-1: 元数据真身落位 = sidecar v3 真身 + DB v2 列缓存；flag/note/EXIF 列触发首次真迁移
- **裁决**：①sidecar 升 **schemaVersion 3**（additive：`rating: Int?`、`flag: Int?`（0=none/1=pick/2=reject）、`colorLabel: Int?`、`keywords: [String]?`、`note: String?` 五字段，全部 decodeIfPresent、encode 恒写，`LightamerSidecar.swift:334` 的 additive 模式照抄；reader 容忍 >current 降级既有契约 `:94-97` 不动）；②索引 DB 升 **schemaVersion 2**：新增 `flag`/`note` 两列 + EXIF 轻量七列（`camera_make`/`camera_model`/`lens_model`/`iso`/`focal_length`/`aperture`/`exposure`——META-05 过滤键面，dt `collection.h:74-136` 属性枚举同构对齐），迁移 = `ALTER TABLE ADD COLUMN` 序列 + meta 表记版本，`1 → migrate` 新语义、`>2 → REFUSE` 不变；Phase 9 预留 `rating`/`color_label`/`keywords` 三列直接回填零 ALTER（D-09-CONTEXT-7 兑现）。
- **理由**：MCP-06（REQUIREMENTS:466）黑体「写回以 sidecar 为真」已钉真身；flag/note 是 MCP-06 写面必需字段且 Phase 9 未预留（识别到的新分叉——25 列 v1 无 flag/note/camera/lens/iso/focal）；迁移代码是 Phase 14 前**唯一**的低成本窗口（DB 行数尚少、基线稳定）。
- **Reversibility**: 字段级 reversible（additive 列可弃用）；schemaVersion 一旦发版不可逆——v2 列集冻结前须 research 复核 MCP-09/Phase 13/14 全部下游列需求一次到位。

### D-12-CONTEXT-2: META-04 XMP 同步 = 红线语义澄清（不推翻）+ 自建 XMP 写入路径 + 第三方 .xmp 只读导入
- **裁决**：**案 A**（推荐）——①`.xmp` 红线不动：原片同目录 `.xmp` 附件永不读写删（Phase 9 Boundary 原文）；②导出图 XMP = **自建写入路径**：XMP packet 生成（优先验证 `CGImageMetadataCreateXMPData` 序列化可用性——11-02 D3 只证伪了**写入端**，序列化端未测）+ per-format 容器注入缝挂 Phase 11 ExportEncoder 之后（JPEG APP1 / TIFF tag 700 / PNG iTXt 标准明确可行）；③第三方 `.xmp` 只读导入 = 用户显式动作（导入对话框读 rating/label/keywords 入 sidecar），自动桥接/扫描不进 v1。
  **案 B**（否决）——推翻红线写原片旁 `.xmp`：连锁推翻 PROJECT 互通性 locked 决策 + 09-CONTEXT Phase Boundary 显式「永不」条款 + C1 Session 语义（外部工具 sidecar 污染会话文件夹、reconcile exclude 表重设计），代价横跨三个 phase 的契约面。
- **理由**：红线防的是「第二 sidecar 分裂真身」，不是 XMP 字节格式；导出物内嵌 XMP 是 EXP 面的自然延伸（导出图已脱离会话真身链）；自建注入是 11-02 D3 宿主事实下的**唯一**可行路径（「不得假设 ImageIO 能写 XMP」硬约束）。reject 的 XMP 互通惯例 = `xmp:Rating = -1`（dt/Lr 同款）；pick 无 XMP 正位，仅 sidecar/DB 本地维度（文档化）。
- **Reversibility**: 序列化器/注入缝是纯函数插件位，可换实现；「只读导入」扩大为「双向写 .xmp」随时可做但**永不**默认（红线语义已澄清，扩大须用户显式重裁）。

### D-12-CONTEXT-3: 层级关键字 = `|` 分隔 path 数组 + 打子隐含父语义 + DB LIKE 查询面
- **裁决**：①sidecar `keywords: [String]` 存完整层级路径（`"Nature|Flower|Rose"`，`|` 分隔——dt `tags.c:817`「keep also tags in the path」与 Lr `lr:hierarchicalSubject` 同惯例）；②给图打子标签**自动隐含全部祖先可查**（不打平铺物化——查询时 LIKE 展开或入索引时物化双案留 research 定夺，语义钉死：按 `Nature` 过滤必含 `Nature|Flower` 图）；③DB `keywords` 列存 `|`-join 的物化扁平串，过滤谓词 = `LIKE '%Nature%'` 直翻 SQL（dt `collection.c:1355 get_query_string` 同构）；④XMP 同步写 `lr:hierarchicalSubject`（层级）+ `dc:subject`（扁平叶子）双字段。
- **理由**：层级语义在查询面展开而非存储面复制 = 单一真身无同步漂移；`|` 是三方（dt/Lr/C1）事实标准分隔符，互操作零翻译成本；MCP-09 set_keywords（REQUIREMENTS:469）消费同一路径数组。
- **Reversibility**: reversible——物化形态（列内容格式）可重导；path 分隔符入 XMP 后即锁 `|`。

### D-12-CONTEXT-4: 智能相册 = 谓词规则 JSON + app 级存储；v1 求值域 = 当前会话
- **裁决**：①规则模型 = 结构化谓词组（字段 ∈ META-05 键面 × 操作符 × 值，AND/OR 组合，Codable JSON）；②存储 = **app 级** `Application Support/Lightamer/SmartAlbums/*.json`（一规则一文件，原子写——跨会话虚拟分组天然是 app 级资产，与「预设 app 级」同位）；③**求值域 v1 = 当前打开会话的索引 DB**（谓词翻译 SQL，D-12-CONTEXT-7 同一翻译层）；侧栏智能相册入口列出全部规则、点入后在当前会话内求值。
- **理由**：跨会话求值需聚合多 `session.lindex`（会话级文件无中央库——Phase 9 哲学「文件夹即会话」的正交推论），是新架构面不是本 Phase 过滤面的增量；dt collection 同为「当前库内」过滤（`collection.c` 全族无跨库语义）；app 级存储让规则随应用走（会话无关），求值结果随会话（数据无关）——两个自由度解耦。
- **Reversibility**: reversible——规则 JSON schema 加 `scope` 字段即可日后扩跨会话；谓词翻译层是共享函数。

### D-12-CONTEXT-5: 预设 = `.lightamer-preset` 统一容器（kind: develop|export）+ paste 同构 apply + ExportRecipe 直挂
- **裁决**：①格式 = 单文件 JSON/Codable：`{schemaVersion, kind, name, category, appVersion, instances[]（全局链快照，skip 集语义同 D-09-CONTEXT-5：跳 decode 域 + 跳恒等默认实例）, exportRecipe?（kind=export 时挂 `ExportRecipe`/`ExportVariant` Codable 全量，Phase 11 移交①兑现）}`；②存储 = **app 级** `Application Support/Lightamer/Presets/*.lightamer-preset`（一预设一文件——PRES-02 导入/导出 = 文件拷贝零格式转换）；③apply（PRES-04 单图/批量）= **Phase 9 paste 三段管线同构复用**（预设是磁盘上的 PastePayload：段1 内存 merge + 段2 索引事务 + 段3 sidecar 写队列；批量走 9-4 懒渲染语义零新渲染）；④预设目录扫描 + 启动重扫自愈模式对齐 YiyinFontStore 先例（YIYIN-05）。
- **理由**：同构快照 = 一套 merge/skip 逻辑服务剪贴板与预设两个入口（D-H1 语义、D-09-CONTEXT-5 skip 集不重写）；kind 字段让 develop/export 预设共用管理器与文件格式（PRES-02 一个入口）；recipe 直挂是 Phase 11 移交①「面板内联编辑面不变」的字面兑现。
- **Reversibility**: 格式 additive 可扩（层栈快照留 `layerStack?` 空位不实现）；kind 枚举扩 kind 纯 additive。

### D-12-CONTEXT-6: .cube LUT iop = 解析器（1D/3D + DOMAIN_MIN/MAX）+ tetrahedral texture3d + 应用色彩空间选择器 + LUT 导入库
- **裁决**：①解析器 = 纯 Swift：`LUT_3D_SIZE`/`LUT_1D_SIZE`/`DOMAIN_MIN`/`DOMAIN_MAX`/`TITLE`/`LUT_1D_INPUT_RANGE` 全识别，非法文件 typed throw；②kernel = `lut3d.cl:29-60` tetrahedral 逐行移植（level 索引数学 + P000-P111 六四面体重心权值 verbatim），CLUT 载 `texture3d`（rgba16Float；>1.0 域 LUT 经 DOMAIN_MIN/MAX remap 后 float16 精度论证入 research，不足则 rgba32Float）；1D = per-channel 分段线性（独立轻 kernel）；③V50Order 槽位 = **36.0 已预留**（`V50Order.swift:126`，dt `iop_order.c:261` 「creative style / film emulation」段同值）——36.0 < terminalTailFloor 70.0 → 可作层内 iop（非几何禁槽，无冲突）；④**应用色彩空间选择器**（显式 UI 参数：LUT 输入域声明 ∈ sRGB/Display P3/Rec2020/ProPhoto linear，默认 sRGB——INTEROP-2/3 正主防呆）：应用前 working→LUT 域矩阵转换、应用后 LUT 域→working 转换（dt `lut3d.c:1029-1031` lut_profile ↔ work_profile 同构；矩阵走既有 colorin/colorout 系数资产）；⑤LUT 文件**导入拷贝入库** `Application Support/Lightamer/LUTs/`（iop 实例引用库内名而非原始路径 → 预设可移植；dt config 目录同款），PRES-03 与 IOP-COLOR-08 同一次交付（ROADMAP Notes locked）。
- **理由**：tetrahedral 是 ROADMAP SC#4 点名默认插值；V50Order 36.0 零迁移成本；应用色彩空间选择器是需求原文（「explicit application color space selector」）非自由裁量；导入库隔离「原文件被移动/删除」的引用腐烂 + 让 `.lightamer-preset` 跨机器可用。
- **Reversibility**: kernel 参数化（插值方法枚举 tetrahedral/trilinear 可选）；色彩空间选项集 additive；库路径常量。

### D-12-CONTEXT-7: META-05 过滤/排序 UI = grid 工具条谓词 chips + Quick Filter + 排序菜单；谓词→SQL 单一翻译层
- **裁决**：①过滤栏落位 = **grid 工具条**（三态 segmented 同行/相邻行，`ContentView.swift:37` BrowserMode 三态旁），chips 型谓词（评分≥N / 色标 / 关键字 / 相机 / 镜头 / 日期区间 / ISO 区间 / 焦距区间 / flag / has_edits），可叠加 AND；②Quick Filter = 工具条行内搜索框（文件名/关键字子串即时过滤——Nitro 式键盘驱动：`/` 聚焦、Esc 清除；快捷过滤预设 chips「星级≥3」「pick」入 v1）；③排序键面 = 文件名/评分/拍摄日期/ISO/焦距/导入序（scan_epoch），asc/desc 持久化；④谓词模型 = D-12-CONTEXT-4 智能相册**同一** Codable 谓词组 + **同一** SQL 翻译层（智能相册 = 持久化的谓词组，过滤栏 = 临时谓词组——一套代码两个消费面）。
- **理由**：翻译层单实现是 MCP-14 风格「GUI/MCP 同源」纪律的前置（Phase 14 MCP 筛选工具直接消费翻译层）；chips 型非文本语法 = L025 zh/en 目录负担最小 + 结构化可持久化（智能相册白得）；排序键全部有 DB 列（v2 后），无文件系统排序路径。
- **Reversibility**: chips 集 additive；Quick Filter 快捷键方案 plan 期定；文本查询语言 defer 不堵路。

### D-12-CONTEXT-8: 评分 UI 兑现 = grid overlay 接线 + 全局 0-5/flag 快捷键 + MetadataService 单源（GUI/MCP 同一实现）
- **裁决**：①grid cell rating overlay 接数据（Phase 9 预留壳 `SessionBrowserView.swift:139-149`，identifier `.rating` 既有）；②快捷键 = **0-5 星级 / X flag-reject / P flag-pick / ⌘0-6 色标**，三态全域生效（grid 焦点行 / culling 双格选中格 / 单图编辑器当前图）；③写面唯一入口 = `MetadataService`（本 Phase 新建，Core 或 App 层 plan 期定）：**GUI 快捷键、菜单、拖星级、Phase 14 MCP-06 全部调同一方法**，内部 = Phase 9 批量管线三段（段1 sidecar 内存变换 → 段2 索引单事务回填列 → 段3 sidecar 写队列）；**元数据写入不产生 history 项、不翻 paramsHash、缩略图不 stale**（D-12-CONTEXT-1 事实 1 的机制面）。
- **理由**：MCP-06 已黑体「复用 Phase 9 批量管线」（REQUIREMENTS:466）——服务层现在收口 = Phase 14 只写工具壳；三态全域快捷键是 culling 工作流（META-01 主场景）的最低可用形态；「评分触发缩略图再生」是必须显式防住的性能陷阱（万张批量打分 = 万次重渲染）。
- **Reversibility**: 快捷键映射表可调；service 接口签名 plan 期冻结后 MCP 消费。

### D-12-CONTEXT-9: 波次分解建议 = 5 plans / 4 waves（W2 双 plan 可并行）
- **裁决**（给 planner 的依赖序基线）：**12-1**（元数据真身 + 服务层：sidecar v3 五字段 + DB v2 迁移 + EXIF 轻量列回填 + MetadataService 三段写面 + grid overlay/快捷键接线 + flag/note）→ **12-2**（过滤排序 + 智能相册：谓词模型/SQL 翻译层 + filter bar chips + Quick Filter + 排序 + SmartAlbums 存储/求值/侧栏）∥ **12-3**（XMP/EXIF 同步：XMP 序列化验证 + per-format 注入缝 + 只读导入 + ExportEncoder 后置挂载；依赖 12-1 字段、与 12-2 无依赖）→ **12-4**（预设系统：`.lightamer-preset` 格式 + 管理器 UI + apply/batch + recipe 挂载；依赖 12-1）→ **12-5**（LUT iop + 收口：解析器 + kernel + 面板 + 色彩空间选择器 + 签核；GPU 腿独立，可与 12-4 调序）。
- **理由**：12-1 是全 Phase 依赖根（字段/服务/迁移）；12-2/12-3 无相互依赖可并行（自动阵容 cap 内两 worker）；LUT 独立 GPU 腿放尾段吸收 12-1..4 的验收回注余量。
- **Reversibility**: plan 边界可并/拆；唯一刚性 = 12-1 先行、12-5 收口含签核。

### D-12-CONTEXT-10: XMP 缺席下的互操作兜底矩阵 = 三格式内嵌 + 两文档化例外 + 只读导入兜底
- **裁决**：①**内嵌可行集 = JPEG / TIFF / PNG**（APP1 / tag 700 / iTXt 标准明确，注入缝 plan 期 golden 断言字节布局）；②**文档化例外 = HEIF/HEIC / AVIF / WebP**（HEIF/AVIF 的 XMP 是 item 级容器结构、WebP 无 mux 面——11 遗留 #5/#6 先例延续，golden 反向锚断言缺席 + 宿主行为变化即红）；③**兜底面 = 第三方 `.xmp` 只读导入**（D-12-CONTEXT-2③）+ sidecar/DB 本地位全量——「互操作」承诺在 v1 = 「导出 JPEG/TIFF/PNG 带全量 XMP + 能读别家 .xmp」，EXIF properties dict 路全格式照旧（11 移交⑤）；④SC#1「synced to standard EXIF/IPTC/XMP」的字面拆解：EXIF = 拍摄元数据既有读路 + properties dict 写路；IPTC = XMP packet 内 IPTC Core 字段（IIM legacy 不写）；XMP = 上述矩阵——三段各有明确定义域，无隐藏缺口。
- **理由**：兜底矩阵是 11-02 D3 硬事实的必然推论，research 只需验证「序列化 API + 三格式注入」不再开放「全格式」幻觉面；反向锚是 11-02 同款防宿主漂移手段。
- **Reversibility**: 例外集可随宿主/macOS 升级收窄（复审位 = Phase 14 WebP/mux 复审同批）。

### 继承定案（非 OQ，上游已论证、下游不得重开）

- **真身恒 sidecar / 索引可重建**（SESS-07 黑体 + 09-CONTEXT 事实 2）——本 Phase 一切列回填走「sidecar → 索引」单向；reconcile/重建parity 语义不变。
- **批量管线三段式**（09-CONTEXT 事实 3 + MCP-06 黑体）——元数据批量编辑（关键字批量 META-03、预设批量 apply PRES-04、评分批量）全走段1+段2+段3；万张 ≤5s 门语义（段1+段2）延续 PERF-07。
- **复制 skip 集语义**（D-09-CONTEXT-5）——预设 instances 快照同款：跳 decode 域、跳恒等默认实例、自动检测 verbatim。
- **L013 哈希纪律**——预设/preset JSON 里一切 UInt64 哈希 decimal String（`UInt64String` wrapper）；ExportRecipe 已零哈希字段（移交①前提）。
- **依赖红线**——零新 SPM 依赖（XMP 序列化/注入自建；解析器自建；libwebp/libavif 两件既有不动）。
- **one-way 格式锁**——`.lra`/`.lightamer-preset` 均为自有格式 + schemaVersion 前瞻 + sortedKeys 稳定序列化（`LightamerSidecar.swift:7-8` 模式）。
- **管线/Phase 8 契约不动**——LUT iop 是常规 v50 实例，`LayerCompositeDriver.terminalTailFloor=70.0`、`injectYiyinRunContext`、split 语义零改动。
- **执行纪律**——`.work/config.toml [gsd]`（auto/paused）每任务边界检查；C 档门控三点停（research 定稿停已过 / 每 plan 闭环停 / 签核前停）。

### 验证与 GUI 红线（全 plan 写死，执行期不得放宽）

- **DB 迁移专项**：v1→v2 迁移函数对旧库 fixture 逐列断言（新列 NULL 初值 + 旧列逐字节不变）+ 二次打开幂等 + v99 拒开保留 + 删库重建 parity 扩到 v2 全列（SESS-07 门增量）。
- **sidecar v3 专项**：v2 文件可读（缺字段降级）+ v3 文件被旧 reader 读（下游无旧 reader，以 decode 容忍测试代替）+ sortedKeys 稳定 diff。
- **XMP golden 双向锚**：三格式注入字节布局 golden（正向）+ HEIF/WebP/AVIF 缺席断言（反向，11-02 同款）；XMP packet 内容 golden（rating/label/keywords/flag-reject 映射）。
- **LUT golden**：.cube 解析 golden（1D/3D/DOMAIN 变体 + 非法输入 typed throw）+ tetrahedral vs dt 参考输出（golden-image 纪律，CONVENTIONS 测试条款）+ DOMAIN remap 已知点。
- **过滤谓词内容级断言**：翻译层 SQL 对 fixture 库精确行集（禁「返回非空即过」，L020）。
- **防空转/L014/L010/L025/面板四件套**：同 09-CONTEXT 全套（identifier `browser.cell.<pathhash>.rating` 既有锚、新增面板 D-H1 三件套 + 280pt + zh catalog）。
- **回归纪律**：每任务全套 suite 绿（现基线 **1260/6skip/0fail**，Phase 11 R2 收尾批后）；每任务边界查 `.work/config.toml [gsd]`。

### Open Questions 晨审追认清单（10 项全按推荐自动裁决）

| OQ | 裁决一句 | 关键理由 | 推翻代价 | Reversibility |
|---|---|---|---|---|
| 1 真身落位 | sidecar v3 真身 + DB v2 列缓存；flag/note/EXIF 七列触发首次真迁移 | MCP-06 黑体 sidecar 为真；25 列无过滤列 | sidecar-only 或 DB-only 各破一角（删库丢分/删库丢真身）；迁移推迟到 14 更贵 | 字段可弃；v2 列集冻结需一次到位 |
| 2 XMP vs 红线 | 红线不动（澄清=禁原片旁附件）；自建序列化+注入；.xmp 只读导入 | 11-02 D3 宿主硬事实；案 B 连锁破三 phase 契约 | 案 B = 推翻 PROJECT locked + 09 边界 + reconcile 重设计 | 注入缝插件位可换 |
| 3 层级关键字 | `\|` path 数组 + 打子隐含父 + LIKE 查询 + lr:hierarchicalSubject 同步 | 三方事实标准；语义在查询面展开 | 分隔符/物化形态改动 = 数据重导 | 物化可重导；XMP 侧锁 `\|` |
| 4 智能相册 | 谓词 JSON + app 级存储；求值域 = 当前会话 | 跨会话 = 新架构面；app 级规则/会话级数据解耦 | 跨会话求值 = 多 lindex 联合层，phase 级增量 | 加 scope 字段可扩 |
| 5 预设 | 统一容器 kind:develop\|export + paste 同构 apply + recipe 直挂 | 一套 merge/skip 服务两入口；移交①字面兑现 | 分格式 = 双管理器双格式 | additive 可扩层栈位 |
| 6 LUT | tetrahedral texture3d + V50 36.0（已预留）+ 色彩空间选择器 + 导入库 | SC#4 点名；INTEROP 正主；库引用保预设可移植 | 36.0 改位 = order 表迁移；无选择器 = INTEROP-2/3 复发 | 插值/选项集 additive |
| 7 过滤 UI | grid 工具条 chips + Quick Filter + 排序菜单；谓词/SQL 单一翻译层 | 智能相册与过滤同代码；MCP 前置收口 | 文本语法 = L025 + 持久化双负担 | chips additive |
| 8 评分 UI | overlay 接线 + 全域快捷键 + MetadataService 单源；不翻 paramsHash | MCP-06 同源前置；防万张重渲染陷阱 | 双实现漂移 = MCP-06 重写 | 映射表可调 |
| 9 波次 | 5 plans / 4 waves；12-1 依赖根；12-2∥12-3 | 依赖序自然；并行度在 cap 内 | 串行拉长日历；深并行破 12-1 根 | plan 边界可调 |
| 10 兜底矩阵 | JPEG/TIFF/PNG 内嵌；HEIF/AVIF/WebP 例外反向锚；只读导入兜底 | 宿主事实必然推论；「全格式」幻觉面关死 | 追 HEIF/WebP 注入 = 容器解析自研，phase 级 | 例外集随宿主收窄 |

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/ROADMAP.md` §Phase 12（SC#1-4 + Notes：preset 不互通 locked / IOP-COLOR-08=PRES-03 同 feature / .cube 显式应用色彩空间 / 风险 INTEROP-2/3、NDE-6）+ §Phase 13 Notes（本 Phase DB 列是 Spotlight 索引源）+ §Phase 14 MCP-06/MCP-09 条目（上游依赖面）；`.planning/REQUIREMENTS.md` META-01..06（:185-190）/ PRES-01..04（:194-197）/ IOP-COLOR-08（:78）/ MCP-06（:466）/ MCP-09（:469）/ Out of Scope 表（:265，预设互通否）
- `.planning/phases/09-session-management/09-CONTEXT.md`（D-09-CONTEXT-5 skip 集 / D-09-CONTEXT-7 预留列 / SESS-07 真身 / `.xmp` 永不红线 :27 / 批量三段式 + 继承定案节）+ `09-01-SUMMARY.md`（SessionIndexSchema v1 冻结 25 列 + EXIF 轻量列 + v99 拒开）
- `.planning/phases/11-export-pipeline/11-DISCUSSION-LOG.md` 终节（**Phase 12 移交清单五条** + 遗留对表 #4/#5/#6/#9）+ `11-02-DECISIONS.md` D3（XMP 全格式不写宿主事实五途径）/ D8（Swift-WebP 零 mux 面）——META-04 设计的硬事实底座
- `.planning/phases/02-pixelpipe-core-color-management-history-stack/`（`.lra` schema v1→v2 演进先例 + ONE-WAY 格式锁 + UInt64String——v3 additive 照抄模式）
- dt 对标正本（本地 `/Volumes/UNITEK/Documents/Development/darktable`）：`src/common/collection.h:74-136`（过滤属性枚举）/ `collection.c:1355`（谓词→SQL）/ `:2625-2668`（过滤谓词族）/ `src/common/tags.c:163/:817/:939`（层级关键字 path 语义）/ `data/kernels/lut3d.cl:29-60`（tetrahedral 移植正本）/ `src/iop/lut3d.c:1029-1031`（lut_profile↔work_profile）/ `src/common/iop_order.c:261`（v50 lut3d=36.0）/ `src/common/presets.c`（per-module preset 语义参考）
- `AGENTS.md`（Phase 执行模型 + 暂停机制 + Conventions：sidecar/依赖最小化/目录惯例）+ `LESSONS.md` L009/L010/L013/L014/L020/L025/L031
- `.work/GOAL-STATE.md`（Phase 12 续接上下文 + Phase 11 全闭环记录）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **索引 DB 面**：`LightamerCore/Sources/Session/SessionIndexSchema.swift`（v1 冻结 25 列 + `schemaVersion=1` :23 + `rating/color_label/keywords` 预留 :76-78 + `imagesColumns` 逐列表 + meta 表）；`SessionIndexStore` actor（单事务增量同步 + 10k UPDATE 12.9ms 前提）——DB v2 迁移与列回填的全部落点。
- **sidecar 面**：`LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（`schemaVersionCurrent=2` :102、v2 layerStack additive 先例 :99-101/:219-222、reader 降级容忍 :94-97、additive decodeIfPresent :334、sortedKeys :7）；`SidecarStore.swift`（per-image actor + 2s debounce + tmp 原子晋升 + flushNow）——v3 五字段零新写路径。
- **批量管线**：Phase 9 三段式（内存变换/索引事务/sidecar 写队列）+ 9-4 stale 再生接线——MetadataService 与预设批量 apply 的机械复用面。
- **paste 面**：PastePayload instances + skip 集判定（D-09-CONTEXT-5 实现）——`.lightamer-preset` 快照与 merge 的同构源。
- **导出面**：`ExportEncoder` 五格式编码器 + `ExportRecipe`/`ExportVariant`（Codable 零哈希）+ `ExportState.defaultVariant`（移交①现成形态）——XMP 注入缝的挂点与 export preset 的载荷。
- **LUT 槽位**：`LightamerCore/Sources/Foundation/V50Order.swift:126`（`("lut3d", 36.0)` 已预留）+ `IOPModule` 协议 + `.swift`/`.metal` 文件对惯例（CONVENTIONS）——LUT iop 的注册位。
- **UI 面**：`SessionBrowserView.swift:139-149`（rating overlay 壳 + `.rating` identifier）；`ContentView.swift:37`（BrowserMode 三态 + 工具条落位）；`InspectorView.swift`（24+ 面板体系，LUT/预设面板各占一席）；侧栏三段（智能相册入口位）。
- **目录资产先例**：YiyinFontStore（会话注册 + 启动重扫自愈 + typed 错误）——预设/LUT/智能相册三个 app 级目录的运营模式范本。

### Integration Points

| 移交面（Phase 11） | Phase 12 落位 |
|---|---|
| ① `ExportRecipe`/`ExportVariant` Codable 直挂预设存储 | D-12-CONTEXT-5：kind=export 载荷 + `ExportState.defaultVariant` 为预设默认值形态；面板内联编辑面不变 |
| ② WebP mux 元数据复审位（OQ-11-5） | D-12-CONTEXT-10：维持文档化例外 + 反向锚；与 HEIF/AVIF 例外同表管理；Phase 14 复审同批 |
| ③ XMP rating/flag 字段面 API 位（D-11-CONTEXT-5 预留） | D-12-CONTEXT-2：自建序列化+注入落地；reject→`xmp:Rating=-1` 惯例；EXIF properties dict 写路复用（移交⑤同路） |
| ④ `yieldsToEditor` + perf 清算位 | Phase 15 义务，本 Phase 不动 |
| ⑤ EXIF/IPTC/XMP 读写面与 META-03 汇合点 | D-12-CONTEXT-2/10：keywords/日期写回应复用 properties dict 同路并同批定 XMP 裁决（已裁） |

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：12-1（真身+服务+迁移+UI 接线）→ 12-2∥12-3（过滤/智能相册 ‖ XMP 同步）→ 12-4（预设）→ 12-5（LUT+收口签核）。12-1 迁移是破坏性操作密集区（DB v2 + sidecar v3 双 bump），独立成 plan 最利于验收回滚。
- **XMP 序列化验证前置到 12-3 research 头项**：`CGImageMetadataCreateXMPData` 本机可用性一探针定生死——可用则注入缝只做容器 append；不可用则自写 XMP XML 模板序列化（工作量 +1 天级，不改裁决）。
- **C 档门控**：每 plan 执行+验收闭环后停（汇报战果 + 下一 plan 摘要）；Phase 12 签核（VALIDATION）前停。worker 每任务边界查 `.work/config.toml [gsd]`。
- **DB v2 列集冻结在 12-1 research**：一次性扫 MCP-09/Phase 13 Spotlight/Phase 14 筛选工具全部列需求（宁多一列空置勿二次迁移——Phase 9 预留列先例的价值即在此）。
- **万张批量打分是 12-1 计量门**：PERF-07 同款 fixture（10k sidecar）上批量 rating 批处理段1+段2 ≤5s 复用门数字；元数据写路径禁触发缩略图再生（断言 thumb_state 不变）。
- **预设管理器面板位置**：Inspector 面板体系一席（应用面）+ 菜单/独立窗口管理器（CRUD/分类/导入导出面）双入口——具体形态 plan 期 UI 走查定。
- **执行期决策边界**：XMP 注入的 JPEG APP1 长度上限处理（64KB 扩展段 vs 标准 32KB）、keywords 物化 vs 查询展开、1D LUT 的 texture1d 不可用回退（texture2d 宽条）、快捷键与既有冲突表——标注执行期决策入各 plan DECISIONS，不臆造。

</specifics>

<deferred>
## Deferred Ideas

- **跨会话智能相册求值**（多 lindex 聚合）——v2（D-12-CONTEXT-4 scope 字段扩展位）
- **自动 `.xmp` 桥接扫描**（打开会话自动读第三方 .xmp）——v2（只读导入显式动作先行）
- **EXIF/IPTC 元数据编辑面板全量**（拍摄时间修正/版权/联系人）——v2 候选（XMP 包字段面已备）
- **预设层栈/蒙版快照**——语义未定义（蒙版坐标绑图），v2 议题；格式已留 additive 位
- **文本查询语言**（dt 式过滤表达式）——v2（谓词模型已可序列化）
- **LUT 打包进预设**（跨机器自包含）——导入库引用先行；打包 = 格式 additive
- **flag 的 XMP 双向**（pick 无正位）——reject(-1) 已同步；pick 互通等 XMP 生态
- **WebP/HEIF/AVIF XMP 内嵌**——随宿主能力复审（11 遗留 #5/#6 复审位，Phase 14 同批）

</deferred>

---

*Phase: 12-Metadata, Rating, Presets & LUT*
*Context gathered: 2026-09-26（discuss 起草；10 项 OQ 全按推荐自动裁决〔晨审追认〕——用户晨间任一推翻即回注 planner 重开受影响面）*
