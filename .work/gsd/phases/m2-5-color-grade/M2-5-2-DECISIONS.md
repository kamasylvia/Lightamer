# M2-5-2 DECISIONS — 执行期签注（2026-09-30/10-01 夜间批）

> plan = M2-5-2-PLAN.md（checker 修正版 87c039d）。执行 = 本 subagent（ZCode），T1-T8
> 逐任务独立提交，每任务边界读 config.toml [gsd]（paused=false/auto=true 全程未变）。
> 语义忠实优先级：Alcedo 源码（GPL 只读，代码零复制）> plan 假设。

## 一、KD-1 分组 IA 的两处拼写落地

- **D-1（note 载体 String? 非 StaticString?）**：KD-1 草图 `var note: StaticString?`
  —— StaticString 无值 `==`/hash，synthesized `Equatable` 不可满足（EditorPanelDescriptor
  既有 Equatable 面），且其 `==` 是 metatype 比较（编译实测）。落地 = `note: String?`
  （承载**本地化键**，call site 仍为字面量键；渲染处 `String(localized:
  String.LocalizationValue(note))`）。分组纯呈现投影的 KD-1 论证不受影响。
- **D-2（compat 组复用 advanced 折叠槽 + 组头跟随行）**：KD-1 字面「compat 组行用
  advanced 既有位」落地 = compat 行 `isAdvancedGroup = true` + `group = .compat`；
  尾部折叠组的**组头按行内容选择**（任一行 .compat → 「Darktable compatibility」，
  否则既有 "Advanced"）——Geometry 页行为逐字节保持，Tone 页 compat 组零新机制。

## 二、m2 单行双滑杆的行账落点

- Tone 页 shadhi 恒 1 descriptor（`.page(ShadhiModule.opName, .tone)`），行标签 =
  新键 `module_shadows_highlights`「Shadows / Highlights」；双滑杆 = 既有
  ShadhiPanelView（shadows/highlights 两字段本就同面板）——「单行双滑杆」由
  routing 单行 + 既有面板共同构成，`panelExposures` 双键模型面零动（AC#1）。
- routing 测试钉 `tone.filter { $0.opName == shadhi }.count == 1`（两行分支删除的
  静态 id 冲突由测试注释承载）。

## 三、KD-2 trackball 的 Alcedo UI 映射精读终式（P1 未交付件，本 plan 落地）

- **disc↔point 纯函数落 ColorWheelsModule（IOP）**：`discFrom(point:relativeTo:
  radius:)`（Alcedo ClampDiscPoint + view-y 翻转，单位圆钳制）/ `pointFrom(disc:
  radius:)`（逆变换，返回相对轮心偏移）。P1 实际未含此二函数（plan T4 read_first 4
  所指「P1 disc 换算纯函数面」不存在），**本 plan T4 补建**——落点 = KD-2 钦定的
  `LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift`（**front-matter 申报外
  文件一处，KD-2 字面钦定位点，已声明**）。
- **拖拽 → colorOffset 派生（Alcedo editor_cdl_trackball_model.cpp UpdateDerived +
  editor_support color_wheel.cpp DiscToCdlDelta/HueToUnitRgb 逐式）**：
  `colorOffset = base(lift 0 / gamma·gain 1) ± DiscToCdlDelta(disc, strength)`，
  gamma 取负号；`DiscToCdlDelta` = hue(atan2) → 六段 hue RGB → 减均值零和化 →
  归一化 → × (strength × disc 半径)。拖拽是**绝对位置**（派生自 disc 直接计算，
  非增量叠加）。disc/strength 为随行 UI 态（P1 D1 装配语义照抄），colorOffset =
  像素真相——UI 拖写在**同一次 write 中**落 disc + 派生 colorOffset。
- **strength/luminance 滑杆量程（Alcedo editor_support hls.hpp/color_wheel.hpp
  常量）**：strength 0…0.1（kStrengthDefault 0.10）、luminanceOffset ±1；payload
  pristine strength = 1.0（payload 默认与 UI 工作量程分立 = Alcedo 同款双面，reset
  回 payload 默认）。
- **Reset**：单轮双击 = `ColorWheelsModule.resetting(wheel:)`（该轮控制体回 payload
  默认）；Reset wheels = GradeCatalog colorWheel 行 identityJSON 解码（P1 单源）→
  一次 discrete commit。测试：经真 EditorState 层会话的 reset commit 链上字节 ==
  identityJSON（AC#5）。

## 四、KD-3 HLS 面的 Alcedo QML 对齐

- 面四滑杆量程照抄 Alcedo EditorLookPanel.qml：Hue Shift ±30（° 读数）/ Lightness
  ±100 / Chroma ±100 / **Hue Smoothness 1…180°**（写选中 bin 的 hRangeTable[bin] +
  hRange 镜像——applyTargetEdit 不覆盖 smoothness，直接字段写 + D4 映射的「同步
  不改动」腿）。Target Hue = 8 色板（45° 步进，选中环标）。
- 面板零映射逻辑：adj 三滑杆全部经 `HlsModule.applyTargetEdit`（P1 golden 钉面）；
  bin 切换 = 本地显示态（8-bin 表唯一真相）。displayValues/写漏斗 = 静态可测缝，
  CatalogAddFaceTests 直测（AC#6）。

## 五、T6 add 面「恰 14」计数对账（plan 内部矛盾的裁决）

- plan 三处表述互斥：KD-4/T6「枚举 = GradeCatalog.gradeItems()（14 项）」vs
  AC#7/files_modified 测试描述「LMT 归 LUT 页 / 四 DRT 件不在枚举」。**gradeItems()
  = 14 行且含 lmt 行**（P1 GradeCatalogTests 钉 14 = 13 grade + tint，13 含 lmt），
  两个约束不可同时成立。
- **裁决 = LMT 排除为绑定语义**（D10 字面「LMT 归 LUT 页不动」+ 空 lut3d add 无
  意义），另加 opName 去重（shadows/highlights 共享 shadhi 一个 op——checker m2
  单行语义；第二条同优先级记录会被 effectiveChain 静默合并，菜单出两条是假选择）。
  **终态 = 12 个唯一 op 条目**，测试按目录 id 逐项断言；计数对账在
  EditorState.gradeScopeEntries 注释 + 本节承载。
- **add 种子 = identityJSON 快照而非面板默认**：shadhi 的 Params()（50/−50 工作点）
  ≠ identityJSON（0/0，checker m5 分立）——add 落 identity 快照（KD-9「reset/
  new-grade 单源」的 new-instance 消费），shadhi case 从行 identityJSON 解码，其余
  11 op 的 Params() 即 identity（P1 m5 表）。
- **Develop 作用域面** = .develop Owned 且有面板的 9 op（temperature/crop/flip/
  lens + ashift/liquify + yiyin 三件）；M2-1 禁用六件 develop-owned 但无面板不入
  菜单（M2-1 收窄的菜单推论）。Section 划分：Develop（temperature/crop/flip/lens）
  + compat（ashift/liquify/yiyin 三件，Alcedo 无对应物）。**base 链插入 = 新
  `addModuleToBaseChain`**（recordChange 形状，恰一条 D-H1 commit，undo 一步回）；
  「Add Adjustment 菜单宿主」执行期定位结论 = **只在 InspectorView**（M1 列的
  layers.addmodule——EditorAdjustmentStackView 全文无 add 菜单，plan T6 预案的
  「若在 stack view 则随 T1 改」分支不触发）。

## 六、KD-5 默认 look 的消费点与 mint 终式

- **flag 消费点 = KD-5 fallback（预声明选型）**：编辑器会话无 imageRowID 通道 →
  **打开图入口注入 Bool**。实态 = `EditorWorkspaceShellView.loadCurrentImage()`
  （workspace.currentRow 即 library rowid 持有者）：LibraryStore 读 flag → 传入
  `EditorState.load(defaultLookPending:)` → **开图即清 flag**（幂等；mint 分支内部
  再做 .lra 文件级复核——flag 被 open 消费即「未打开过的导入」标记语义）。连带走
  线 = WorkspaceHostView 把 projectController 传入 shell（**两文件在 front-matter
  申报外，KD-5 fallback 条款钦定的接线面，已声明**）。
- **mint 时点** = EditorState.load 的 decodeTask 内、`await pipeCoordinator.load`
  返回之后（sidecar probe 已定局：restore 或 pristine 二选一已发生）+ 取消守卫
  之后。`.lra` 存在 → 零注入（restore 恒压过 flag，文件级事实复核，非内存推断）。
- **mint 本体（checker E5 形态逐条）**：单个 AdjustmentLayer 内存构造（chain =
  GradeCatalog.defaultLook 三 entry 经各模块 Codable 面解码 → setParams 同款编码
  路径）；**恰一条 history item** 经 `commitLayerStructure(schedulePersist: false)`
  —— persist 调度零发生（既有参数化通道，非时序巧合），渲染腿照跑（预览即时见
  默认观感）；`layerStack` 已有 adjustment layers（restore 赢了）则不 mint。
  **flushNow 亦无 .lra** 由 DefaultLookTests 双断言①机检；undo 一步 pristine 由
  单次提交构造保证（断言②）。
- **HistoryStack 空栈种子依赖**：commitLayerStructure 的 placeholder 取
  `instances.first ?? baseInstances.first`——mint 前必须已有 pristine seed（真 load
  链的 resetHistoryForNewImage 保证；纯 EditorState 空栈下 mint 静默 no-op，测试
  经真 load 链兜底）。

## 七、KD-6 schema v1→v2 首迁的落地细节

- `schemaVersion = 2`；`imagesColumns` 尾 append `("default_look_pending",
  "INTEGER")`——**freeze 元组的 type 字段 = PRAGMA table_info 拼写**（"INTEGER"），
  DDL 侧保留 `INTEGER DEFAULT 0`（DEFAULT 不入 table_info type 列，两者拼写分立是
  freeze 测试逐字节对账的要求）。
- migrate slot 首填：`from <= 1 && to >= 2` 门 + `addImagesDefaultLookPendingColumn`
  （table_info 探针幂等 + ALTER TABLE ADD COLUMN）+ writeUserVersion(2)，ONE
  BEGIN IMMEDIATE + ROLLBACK。**ProjectFileStore.dispatchSchema 的 pre-migrate
  `sqlite3_backup` 快照钩子首次消费**（v1 预埋的 dead pin 转活），DefaultLookTests
  断言 `.pre-migrate.bak` 落盘 + 二次打开幂等（不重迁不重照）。
- insertImage INSERT 列尾写常量 1（`VALUES (…, 1)`——无开关 OQ-8 A）。
- **申报外测试随动（声明偏差，V50OrderTests 先例）**：LibrarySchemaTests（版本钉
  1→2 / future 2→3 / 列数 28→29 方法改名）+ LibraryDocumentTests（三处版本钉）——
  schema bump 使「既有测试全绿」与「静态字面量」不可兼得，同批修订随 T7 commit。

## 八、其它执行签注

- **行/provider 同批到位纪律的执行序**：m3 恰一次断言域 = populated provider 面 →
  routing 行与 provider 注册必须同 commit。T1/T2 批只重排既有行（populated 不变，
  基数 33→33）；T3 +6（39）/T4 +1（40）/T5 +1（41），cardinality 钉值随批修订。
- **m2 「Tone 主面六行」的批序**：T1 只挂 provider 已填充的三行（exposure/
  tonecurve/shadhi），contrast/white/black 随 T3 provider 批同 commit 挂入——每
  commit 独立绿（m3 域约束的必然批序，T1 测试注释承载）。
- **新面板实例的可达性**：行渲染以链上实例存在为前提；新 op 不入 pristine seed
  （M2-5-1 移交项维持）→ 面板走查依赖 T6 add 面（T6 后 add 即见、即开面板）。
  走查清单入 P3 收口观察项（trackball 手感 Manual-Only 同款）。
- **LightamerSlider 无 step**：共享组件面无 step 参数，本 plan 不扩组件（申报文件
  集外）；范围/默认值常量引用已实现「零手抄漂移」，粒度由读数精度承载。
- **新增键族**（zh 随手入账，en+zh 双写）：组头 5（panel_group_master/look/color/
  detail_texture + editor_stack_compat）+ 注记 1（panel_note_pre_drt）+ 行标签 8
  （module_shadows_highlights/cat02_white_balance/contrast/white/black/tint/
  saturation/color_wheels/selective_color）+ 面板键 21（panel_cat02_* ×4/
  panel_contrast_* ×2/panel_white_* ×2/panel_black_* ×2/panel_tint_* ×2/
  panel_saturation_* ×2/panel_wheels_* ×6/panel_hls_* ×6+bin）+ history 9
  （history_cat02/contrast/white/black/tint/saturation/colorwheels/hls/
  default_look/base_module_add）+ add 面 1（add_face_develop_section）。
  phase 尾 P3 收口 `Scripts/zh-audit.py --check` 对账。
- **DefaultLookTests 会话②教训（测试脚手架级，LESSONS 候选）**：makeFreshStatePair
  丢弃 coordinator 会让管道腿静默失联（EditorState 持 coordinator 弱引用；coordinator
  持 editorState 弱引用——两侧都需测试持有）——修正 = 双 keep-alive；已修非 flake。
