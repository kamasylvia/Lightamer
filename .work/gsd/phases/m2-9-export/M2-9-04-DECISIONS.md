# M2-9-04 DECISIONS — 检查器 Export 页 + App 装配点（wave 3）

**Status:** 执行期底稿（2026-10-03 夜间；执行 = ZCode subagent worker）。
晨审可逐条推翻；行号锚以符号检索为准（plan read_first 7）。

## §1 越界申报（front-matter 外增量，全部声明）

1. **Core 载体两面（`ExportQueue.swift` + `ExportRenderer.swift`，fix 家族外的
   feat 内增量）**：exifSoftware 载体缺口（M2-9-03 SUMMARY 交接节 + DECISIONS
   §11 明示「04 需经 enqueue 增参 + carrier 递缝」）——03 波 front-matter 不许
   加，04 plan front-matter 漏列 Core 文件（checker-E5 同族遗漏）。落地形态 =
   02/03 递缝先例：`ExportRenderer.$jobExifSoftware` TaskLocal + `enqueue`
   增 `exifSoftware: String? = nil` 批参 + `execute` encode 腿 withValue 包装 +
   默认 encodeLeg 消费。**另加 per-image `instancesOverrides` 载体**（§2 裁决）。
   两文件 diff = 纯载体（Engine pump/cancel/retry/generation/markState/
   markTerminal/finish/finishCancelled **零 hunk**，262f98e..c97924e 机检；
   ExportRenderer 恰 1 additive hunk）。
2. **`WorkspaceHostView.swift`**：KD-1「M2 face toolbar 导出按钮」的正主落点
   （M2 面无 window toolbar，topBar = 其等位物）+ KD-4 目标推导的 provider
   臂（L036 装配点注入）。front-matter 漏列（同 E5 族）。
3. **`Tests/LightamerTests/ToastFaceTests.swift`（越界测试随动，晨审可推翻）**：
   WorkspaceHostView 新读 ExportState/InspectorState 两 environment——该测试的
   最小 HostRoot 只注入旧两面 → 挂载即 trap（`No Observable object of type
   ExportState found`，实测抓于 T3 首轮）。修复 = HostRoot 补两面注入（生产码
   零改动；3a1ecb8/8e810a0 测试侧先例族）。
4. **`ExportState.installQueueForTesting(_:)`**：装配测试缝（Core
   `inFlightCountForTesting` 同族先例，app 代码零调用）——`queue` 为
   private(set) 而 rebuild 腿 metal-gated，注入腿队列是装配面可断言的唯一路径。

## §2 per-image instancesOverrides 载体（KD-4 的实现形态裁决）

queue 的 `instancesOverride` 是**批级单值**（11-04 契约面）。KD-4 要求逐图
「open 图 = 活投影、其余 = nil（盘上 sidecar 真相）」→ 批级参数装不下。
落地 = drtTails 同款 per-image 索引载体：`enqueue` 增
`instancesOverrides: [[ModuleInstance]?]? = nil`（nil = legacy 批参语义；
非 nil 时 precondition 等长——enqueueExportM2 先行 typed 拒绝，M2-9-02
验收 O-2 前车之鉴）。Job init 折叠规则 =
`instancesOverrides?[imageIndex] ?? instancesOverride`。默认 nil = legacy
字节稳定（Export bundle 338/1/0 零漂移实证）。

## §3 「projection(upTo:)」API 落点 + 层语义边界（晨审重点注记）

- plan KD-4 字面 `EditorState.history.projection(upTo:)` 在现行 API 面 =
  `projectedState(at:)`（peek 面，非本消费）；M2-8-3-SUMMARY 交接原文 =
  「**EditorState.instances/layerStack 投影**」→ 落点取
  `editorState.instances`（= baseInstances ∪ history.effectiveInstances()，
  活管线投影、与 sidecar 持久集同源——装配测试以注入值断言载体保真）。
- **已知边界（如实登记，非缺陷掩盖）**：渲染器 override 分支现语义 = 纯
  base 链（`layerRecord = nil`，ExportRenderer step-3 现行实现——11-04 起如
  此，非本波引入）。带层图在 M2 面走 override 腿导出 = base 链像素；其余批量
  图（nil override）恒盘上真相含层。flush 腿照跑（命名 rating 盘读 + 未开图
  sidecar 落盘）。若晨审判层语义必须进 M2 面 → Core override 面加 layer 座位
  是后续 plan 级决策（本 plan「纯 App 波」红线内不动 Core 渲染面）。走查批
  （M2-9-05 KD-1 #4）会暴露该差异。

## §4 页开关非持久 + 挂载形态

- `exportPageActive` = InspectorState 会话态（不进 UserDefaults——KD-4 注入
  纪律；与 `layout.inspectorVisible` 布局记忆分立：后者是 ContentView
  @AppStorage 用户偏好，前者是瞬态页路由）。
- 挂载 = ContentView M2 分支 `.inspector(isPresented:)`（macOS 27 列呈现）+
  File > Export 菜单复用 `\.exportPanelRequest` focused 键（LightamerApp
  **零 diff**——M2 分支发布同名键，set 臂开页）。workspace 剥离门双向：legacy
  分支零调用点（source fact，diff 机检）+ M2 分支唯一武装位。
- M2 面无 window toolbar → 「toolbar 导出按钮」落 topBar（§1.2）。

## §5 目标集语义（plan 风险节落地）

M2 腿直持 URL 集（无 relPath 投影）；`queue.enqueue` 的 relPath 载体传
**展示名**（lastPathComponent；快照显示面不受影响——装配测试断言钉）。选中
序 = 队列批内盖章（imageIndex+1，FIFO = 网格行序——provider 按
`grid.rows` 过滤保序）。provider = 编辑面网格选择（filmstrip/grid 同一选择
状态机；library 阶段选择不进导出腿——页入口在 editor topBar/菜单）。

## §6 质量记忆生命周期 + 键面

- 四键 = 登记拼写常量（`ExportState.*QualityKey`，AC4 grep 面）+ kind→key 映射。
- 生命周期 = Alcedo QML:271-288 同构：mount/切格式载入；run + 离页写回（只有
  活格式旋钮写——`qualityMemoryWriteback` 单值面）。PNG/TIFF 无旋钮 → 无键。
- typed 读 = `object as? Double` 域校验（缺席/异型/越域 → nil 降解；**存储
  0.0 是真记忆**——首版 presence-check 被测试抓出异型 0.0 假记忆，改 typed 读，
  DECISIONS 记过程）。
- 首用默认 0.95（Alcedo 95/100）；`export.lastDirectory` 存 path 字符串
  （destinationSection 先例对齐——无书签，OQ-3「以现状对齐」）。

## §7 命名编辑器裁决

- token 插入 = **尾追**（非光标位——plan KD-3 明示「简化：追加尾亦可」）；11
  枚拼写 = OQ-4 语法（`{sequence:0000}` 位宽参数随 token）。
- 预设选择锚 = `selectedTemplateID`；手改 pattern → 掉回 Custom（下拉尾项）。
  存预设 sheet + 改名 inline + 删除（内置于 store CRUD，既有
  ExportNamingTemplateStoreTests 盖 CRUD，本波测试盖 parse/preview/token/
  deletable 面）。
- 无效模板 = 该节红字 + `canRun` 禁用（add 按钮 + run 同一门）；空白 pattern
  「   」= 合法（literal 渲染空 → fallback "image"——引擎语义，测试如实钉）。

## §8 四态映射 + 队列节形态

- 映射：pending→Queued / rendering+encoding→Exporting / done→Done /
  **failed+cancelled→Failed**（取消归失败档——plan 已定裁决，测试穷举钉）。
- Alcedo 两段式「Add to queue → StartExport」塌缩为单 enqueue（引擎即入即
  泵，并发 1 红线不动——「无新状态、无队列引擎感知」裁决的直接推论）；clear =
  cancelAll（既有语义）。36 帽 + `…(N more)` = `previewSlice` 纯函数面。
- OMIT 不可达档 = HEIC/AVIF/WebP + embedICC 关 → 说明文案（不禁用——variant
  照带 embedICC=false，encodeStage typed 降解面如实可达，M2-9-03 §8）。
- 「含编辑摘要」开关不上 UI（OQ-6-A 单开关裁决；includeEditingHistory 默认关
  = 现行为，无显式传参点——DECISIONS 对 03 交接节的回答）。

## §9 exifSoftware 面

- 组合 = `Lightamer <CFBundleShortVersionString>`（`exifSoftwareString(version:)`
  纯函数可注入；Bundle.main 面在 app——测试 host 断言前缀）。座位 = mountMetadata
  的 {TIFF} Software（03 探针链正本；editorSignature 预留面胜出次序不变）。
- 批参随 enqueue 走 `$jobExifSoftware` 递缝（§1.1）；直接渲染面（Request 腿）
  不经此载体——Request 无此字段，直接渲染消费面维持 03 形态。

## §10 测试增量对账（vs front-matter 预估 18）

**+31**（App bundle 481 → 512：9 + 11 + 11）。偏差 +13：
- 装配面 = 真链捕获（注入腿读 TaskLocal/context，非 stub 断言）→ 逐字段展开
  独立方法（01-03 波复合方法组织口径同族）；
- 记忆键面 = 键拼写/四键 round-trip/typed 降解三态/模型默认值对表 Alcedo/
  尺寸模型域穷举/六格式 makeFormat/单开关 policy 变体映射各自独立；
- 页挂载 AX = 双向两法 + 命名编辑器四态层法 + 落点记忆两面。
全部为 AC 逐条机检服务，无凑数法。

## §11 运行记录

- T1 定向：App 490/0/0（+9）；T2：501/0/0（+11）；T3：512/0/0（+11）+
  Export bundle 338/1/0 零漂移门。T3 首轮遇 host 中途 crash ×2（①
  DrtPersistenceTests 中途「command terminated abnormally」——L055 签名，
  03 波同款瞬态；② ToastFaceTests 真因 §1.3 环境缺注入，修复后复跑干净）。
- T4 全套 --all 终跑数字见 SUMMARY（对账基线 2662/16/0）。
- zh-audit `--check`：T1/T2/T3 每任务自跑 PASS（1622 键净增 46 = 15+21+10，
  孤儿 1 即插即删 export_face_done）。

## §12 晨审清单（显式裁决点）

1. §1 三处越界（Core 载体两面 / WorkspaceHostView / ToastFaceTests 随动）
   追认或回退；
2. §3 层语义边界——M2 面导出带层图的 base 链行为是否接受（或立项 Core
   layer 座位）;
3. §5 目标集 = 编辑面网格选择（library 阶段多选不进导出腿）是否接受；
4. §8 add/start 塌缩形态是否接受。
