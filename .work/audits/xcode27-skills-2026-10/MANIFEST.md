# Xcode 27 Skills 三路审计 — 合并对账 MANIFEST（2026-10-19）

- **性质**：A/B/C 三路 findings 的合并对账批产物（纯文档，零源码触碰）。
- **输入**：`LANEA-FINDINGS.md`（A 路机械扫描，2026-10-13，31 finding + 9 note）／`LANEB-FINDINGS.md`（B 路深读抽样，2026-10-13，0E+5M+11m+9obs）／`OMP-FINDINGS.md`（C 路 omp 全量深读，2026-10-19，3E+25M+127m+44obs）＋归档件（`omp-task.md` / `OMP-FINDINGS.blocked-note.md` / `omp-stdout.log` / `slices/`）。
- **对账人**：ZCode 合并对账批（第二双眼睛）——error 三条逐条亲核产线源码 + catalog 机检 + **编译运行实验**；抽验 major 五条；全量复扫软废弃残留。
- **关键背景**：AR-01/02/03 修复批已于 2026-10-19 01:36 收工（closeout `03830b01`）；C 路（omp）于同日 08:48-09:06 交付——**C 路全部 findings 针对修复后 HEAD，即当前在账积压**。AR-03「C 路并入条款」（AUDIT-REPAIR-CONTEXT §C 路并入条款活线）因 omp 凭证阻塞（401 api_key_expired，见 blocked-note）顺延至本 MANIFEST——本文件即该条款等待的合并 MANIFEST。

## 结论头

**PASS / 0 error（实锤）+ 28 major（在账）+ 98 minor（在账条目）+ 补扫 35 处（合并批新增）**；A 路全量销账/挂账、B 路全量处置完毕（修复批 AR-01/02/03 兑现），在账积压 = C 路全集（-销账项）+ 合并批补扫。error 三条全部**降级 major**（运行时行为今日正确，判级依据 = 形态禁令 + 抽取链断，非功能缺陷）。

---

## §1 error 三条甄别（本批最高优先产出）

C 路 error 定级口径 = 「违反房内硬禁令**且** catalog 证据链断裂（运行时裸 key 或静默回退），或功能正确性缺陷（静态可定罪）」。亲核结论：**三条均不满足运行时断裂——今日查表全部命中**，按 C 路自己的 major 口径（「违反房内硬禁令但 catalog 手工在册：行为正确、形态被禁、抽取链断」）**全部降级 major**。房内禁令本体（V14 动态键显式 switch 定式 + M2-9-05 F-2 `String.LocalizationValue("prefix_\(x)"` 插值禁形）**真实在案**，形态改造义务成立。

### E1 · InstancePickerOverlay.swift:53 —— 判定：降级 major

- **C 路论据**：`"ai_picker_subject_n \(instance)"` 运行时构 key；catalog 仅手工在册 `ai_picker_subject_n %lld`（extractionState: manual），构建期抽取已断。
- **亲核证据**：
  1. 源码形态（:53-54）：`Text(String(localized: String.LocalizationValue("ai_picker_subject_n \(instance)")))`——插值**直写**在 `LocalizationValue` 字面量内，非 String 先拼。
  2. `instance` 类型亲核：`AIInstanceCatalog.instances: [Int]`（`LightamerCore/Sources/AI/AIMaskService.swift:817`）。
  3. catalog 机检：键 `ai_picker_subject_n %lld` **在册**，`extractionState: manual`。
  4. **运行时实验（决定性）**：mini-bundle（en.lproj 含 `"ai_picker_subject_n %lld" = "SUBJ-%lld"`）+ swiftc 编译实测——`String(localized: String.LocalizationValue("ai_picker_subject_n \(3)"))` 查表**命中**（输出 `SUBJ-3`）。直插值合形走 `ExpressibleByStringInterpolation`，运行时键 = `ai_picker_subject_n %lld` + 参数替换，与手工在册键精确匹配。
- **判定**：**降级 major**。行为今日正确；违规面 = F-2 禁形 + zh-audit 抽取链断（键靠手工维持，非 scanner 在册）。非「误报」（形态违规与抽取链断均属实），亦非「实锤 error」（无运行时裸键）。
- **修复建议**：与 E2/E3 同批显式 switch 化，或改 `String(localized:)` 裸字面量插值形并经 zh-audit 提取器面核（V15 对 `localized:` 行插值前缀 continuation 有 golden 覆盖——改造后实跑 `--check` 对账一轮，L057 惯例）。

### E2 · LayerEditingState.swift:45（消费点 MaskToolbarView.swift:85）—— 判定：降级 major

- **C 路论据**：`MaskTool.labelKey = "mask_tool_\(rawValue)"` 插值拼装（`followEdges` 等驼峰 rawValue 尤脆），catalog 全手工在册但抽取链断。
- **亲核证据**：
  1. 定义点（:45）：`var labelKey: String { "mask_tool_\(rawValue)" }`——**普通 String 插值 stem**，非 LocalizationValue 直插值；消费点 `String(localized: String.LocalizationValue(tool.labelKey))` 走 `init(_ value: String)` 包壳 = 整串作键、无参数。
  2. catalog 机检：`mask_tool_*` **6/6 全在册**（brush/eraser/gradient/ellipse/path/followEdges，含驼峰 followEdges），manual。
  3. 运行时实验：`String(localized: String.LocalizationValue("mask_tool_followEdges"))` 精确键查表**命中**（输出 `TOOL-FE`）。
- **判定**：**降级 major**。C 路的潜在陷阱论据成立且是本条最高价值点：`MaskTool` 是 `CaseIterable`，**新增 case 即静默裸键**（labelKey 插值自动生成 catalog 外新键，无编译期破口）——这正是 V14 要求显式 switch 的理由（switch 穷举使新增 case 编译期报错）。
- **修复建议**：`labelKey` 改显式 switch 返回静态字面量（6 臂）；16 键已在册，改造后 zh-audit 扫描面自然闭合。

### E3 · LayerEditingState.swift:75,102（消费点 MaskToolbarView.swift:144、LayersPanelView.swift:397）—— 判定：降级 major

- **C 路论据**：`MaskOverlayStyle.labelKey` / `MaskCommand.labelKey` 同款插值拼装（`onBlack`/`duplicateAndInvert` 驼峰）。
- **亲核证据**：定义点同款 String 插值 stem；catalog 机检 `mask_overlay_style_*` **3/3**、`mask_command_*` **7/7** 全在册（含驼峰 onBlack/duplicateAndInvert/addMaskItem/removeMaskItem），manual；消费点包壳形态与 E2 相同。
- **判定**：**降级 major**（同 E2——潜在陷阱 = CaseIterable 新 case 静默断键；`panelMenuCases` 白名单只护菜单枚举面、不护 labelKey 面）。
- **修复建议**：两处 labelKey 改显式 switch（3 臂 + 7 臂），与 E2 同 commit 自洽。

### 甄别附注

- C 路方法注记自认「error 判的是形态禁令 + 抽取链断而非当前裸 key」——与自家定级口径（catalog 手工在册 = major）冲突；本批按口径回正。
- 三条降级后与本卷交叉状态：与 B 路 o2（动态查表键，已销账）**同族不同形**——B 路 o2 销账覆盖的是「显式 switch 返回静态键 + `LocalizationValue(变量)` 双重包装」合规子形（SidebarView 等，C 路合规确认节同样点名）；E1-E3/J2-J9 属**禁形子族**（插值构 stem/直插值），两路无矛盾，是 C 路细分更精。
- E 族修复 = 小批机械件（10 定义臂 + 1 直插值点 + J2-J8 调用点约 7 处），建议并入下一修复批（见 §7 R1）。

---

## §2 三路量纲校准注记（防误读）

| 路 | 方法 | 覆盖 | 产出量纲 |
|---|---|---|---|
| A | 机械扫描（~110 token `rg -w` + 形态后滤 + 构建设置对照） | App/Sources 全量但**仅软废弃清单 + 构建面**两个维度；判断级不覆盖 | 31 finding 全部为「真用法存在性」，无判断级发现；多行实参形存在机扫盲区（见 §6） |
| B | 深读**抽样**（~20 文件逐行 + 全仓机扫定位） | 面板族/图库族/宿主族代表 + 九族软废弃 | 5M+11m 小基数是抽样使然；major 集中在失效边界/d6 面 |
| C | 全量深读（114/114 SwiftUI 文件，无抽样） | 七维全覆盖 | 3E+25M+127m+44obs 全表面计数；其 error 判级用「形态违规」口径（严于 A/B 的「行为缺陷」直觉），error 数字不可与 A/B 直比 |

三点校准：
1. **B 路量小 ≠ 仓更干净**——B 抽样基数小；C 全量后 minor 面放大 ~10 倍属预期。
2. **C 路 minor 计数口径**：结论头 127 vs 逐条落账 114 条（N-S 28 / N-I 19 / N-D 18 / N-F 11 / N-L 37 / N-K 1）——差 13 为归一合并/升降级未回写结论头所致（C 路方法注记自认 slice 计数与正本有差）；本 MANIFEST 以逐条落账 114 为工作口径。
3. **时序决定语义**：A/B 对 2026-10-13 HEAD（`363117ee`），C 对修复后 HEAD——A/B 的 findings 已被 AR-01/02/03 消化，**不可直接当作在账积压**；在账 = C + 本批补扫（§6）。

---

## §3 三路命中矩阵（语义族级）

| # | 语义族 | A | B | C | 合并判定 |
|---|---|---|---|---|---|
| X1 | 软废弃 overlay/background 旧重载 | ✓（15 处，#7/#8） | ✓（m3 部分） | ✓（J25 = EmptyStateView 点） | 家族三点命中；AR-03 已修清单内 15 处；**EmptyStateView 为 A 漏检 C 补获**；本批补扫扩至 35 处（§6） |
| X2 | 其余软废弃（showsIndicators/foregroundColor/menuStyle/cornerRadius/onCommit/coordinateSpace/dropDestination/onChange 旧形） | ✓（13 处） | ✓（m3 增量 15 处） | 零直接命中 | AR-03 全清（本批机检复核零残留） |
| X3 | 动态查表键 | — | o2（obs，销账） | E1-E3 + J2-J9 + N-L15..17 | 同族不同形：合规子形两路一致销账；**禁形子族 C 独获、判级回正为 major** |
| X4 | params 每次解码 | — | M2（major） | N-I1..15（minor，init 形） | B-M2 已修（AR-02 stored-params，本批亲核 `private let params` 在位）；C 的 init 残余形态 = **D-M7-AR-5 已裁形态，销账** |
| X5 | 宿主/根失效放大（d6 面） | — | M1/M4（major） | 零对等命中（O-36/O-37 组织面残留） | B-M1/M4 已修（AR-01 `1765f0ca`/`36322b5f`）；C 的修复后观察与修复形态自洽（N-D9 引 `PendingAIEnhanceModifier` 为既存定式） |
| X6 | Film/Drt 面板分节（d6 面） | — | M5（major） | N-S25/N-D11（残留） | B-M5 已修（AR-01 `17b95f2b`）；C 点名 AR-01 后残留 header/enableEntry——**部分交叉，残留面入随触随迁** |
| X7 | Filmstrip 索引记账 | — | M3/m6（major/minor） | N-F10（minor） | B-M3 已修（AR-01 `e7a51667`）；C 的 N-F10 是修后代码的 PREFER-Identifiable 加分项 |
| X8 | LutPanelView `.id(libraryRevision)` 子树重置 | — | o6（obs→挂账 D-6 卷） | N-F11（minor） | **两路同点交叉确认**——维持挂账 D-6 专项卷 |
| X9 | xcstrings 复数/注释缺失 | — | m10/o4（挂账） | N-L35（minor 家族） | 相邻不同项：m10 维持 D-M7-AR-8 挂账；N-L35 入卫生批（comment 补注单源裁定） |
| X10 | CullingView pair 重载缺陷 | — | — | J1（major） | C 独获（B 未深读 Culling），本批亲核机制成立（§5 M-1） |
| X11 | KD-4 body 直读 UserDefaults / @AppStorage | — | — | J14 + N-K1 + O-18/O-19 | C 独获（KD-4 为 B 审计后收紧的约定）；J14 本批亲核属实 |
| X12 | 构建设置（enhanced-security 族） | F1/F2/F3（finding） | — | 零覆盖 | D-M7-AR-1 全挂账（unsigned 分发终裁），维持 |
| X13 | XCTest→Testing 迁移 | A §4 快评 | — | 零覆盖 | 「随触随迁不立项」维持 |

---

## §4 已修销账清单（AR-01/02/03 对账）

**A 路（31 finding + 9 note）**：
- §1.2 软废弃 28 处 → AR-03 全清（本批机检复核：`showsIndicators:` / `.foregroundColor(` / `borderlessButton` / `.cornerRadius(` 零命中；menuStyle 新形在位）。
- §3 构建面 F1/F2/F3 → 挂账（D-M7-AR-1，复活条件 = 分发回签名 ∨ 内存安全专项）；F4/F5/W1/W2/A1 维持 N/A note。
- §1.3 notes ×3（Font.system/GeometryProxy.frame/Stepper）→ 销账（重载消歧，AUDIT-REPAIR-CONTEXT 登记在案）。
- §4 modernize-tests → 「随触随迁不立项」维持。

**B 路（5M + 11m + 9obs，全部处置完毕）**：
- M1→AR-01 `1765f0ca`；M2→AR-02 `4452e10c`；M3（含 m6）→AR-01 `e7a51667`；M4→AR-01 `36322b5f`；M5（含 m2②③/m11/m9/o9）→AR-01 `17b95f2b`。
- m1/m3/m4/m5/m7/m8 → AR-03（`3bcb5b83`/`e22fa21a`+`2ab27a40`/`3fa89a40` 等）。
- m2① 勘误降级销账（FilmSolveCache 内 consult）；m10 挂账（D-M7-AR-8）。
- o1/o2/o3/o5/o7/o8 销账（约定豁免，AUDIT-REPAIR-CONTEXT §销账 8 项正本）；o4 挂账；o6 挂账 D-6 专项卷。

**C 路销账项（对既有裁决的覆盖判令）**：
- **N-I1..15（init 期 params 解码 26 处）→ 已裁销账**：AR-02 已落 D-M7-AR-5 stored-params 形态，init 一次解码 = 该裁决的接受面；C 路草图（Provider 备 Params/模型层缓存）等于重开已裁 OQ，不立项。
- N-S25（FilmPanel header/enableEntry 残留）→ 大部已修（AR-01），残留面归随触随迁（不计新账）。

---

## §5 去重合并总清单（在账积压，severity 排序）

> 记法：M-x = major、m-x = minor；「来源」= C（全部在账项来自 C 路）+ 本批补扫；「交叉」列引用 §3 矩阵行。「亲核」= 本批第二双眼睛已验证代码形态/机制。

### 5.1 major（28 条）

| ID | 位置 | 语义 | 交叉 | 亲核 | 路由 |
|---|---|---|---|---|---|
| M-1（原 J1） | `UI/CullingView.swift:76-99`（调点 ContentView.swift:448） | pair 切换后新 pane 永不加载：`panesContent` 每 body 新建 `CullingPaneModel`，外层 `.task` 无 `id:` 结构身份稳定不重跑；`CullingPaneView` 无内部装载腿（本批亲核 ：239-285） | X10 | ✓ 机制成立 | **R1 修复批首项候选**（行为缺陷；验收附一次真机 pair 切换复验 + O-38 transition 同文件顺路核） |
| M-2（原 E1） | `UI/Overlay/InstancePickerOverlay.swift:53` | F-2 禁形 + 抽取链断（运行时实验证明今日查表命中） | X3 | ✓（含运行时实验） | R1（显式化小批） |
| M-3（原 E2） | `State/LayerEditingState.swift:45` | 同上 + CaseIterable 新 case 静默断键陷阱 | X3 | ✓ | R1 |
| M-4（原 E3） | `State/LayerEditingState.swift:75,102` | 同上（两枚举 + 两消费点） | X3 | ✓ | R1 |
| M-5（原 J23） | `Export/ExportPanelView.swift:174` | `ForEach(state.recipe.indices, id: \.self)` 作用可增删数组（:183 remove/:187 append）——增删后身份错位 | — | ✓ 形态属实 | **R1**（variant 稳定 id 化） |
| M-6（原 J24） | `UI/FilterBarView.swift:192-196` | `Array(enumerated()) id: \.offset` 位置作身份 | — | 待复验 | R3 复验队列（与 M-5 同批小件） |
| M-7（原 J25） | `UI/EmptyStateView.swift:52-62` | overlay/background 旧 View 重载（X1 的 A 漏检点） | X1 | ✓ | **R2 卫生批**（与 §6 补扫 35 处同批） |
| M-8（原 J14） | `Export/ExportPanelView.swift:261-303`（源 `Export/PostExportActions.swift:47-53`） | KD-4 body 直读 UserDefaults（`wantsRunScript` getter + `resolveScript()`） | X11 | ✓ 属实 | R1 小件（注入化） |
| M-9（原 J15） | `Library/ImportModeDialog.swift:85,149` | app-root sheet 裸读 `@Environment(AgentControlCoordinator.self)`（M2-8-3 规则禁形；调点 LightamerApp:1667；今日实机可用） | — | ✓ 结构性 | R1 小件（init 参数注入 `holdsControl`）＋走查面验证 agent-control 期 confirm 门 |
| M-10..M-14（原 J2-J6） | FilterBarView:165-185／ExportInspectorView:534／SigmoidPanelView:121／ToneEqualPanelView:84／MaskGroupsPanelView:337（+Equalizer:51、LuminanceColorRange:332 = M-15/M-16） | 禁形子族调用点（变量构 key，调用点静态可枚举，键在册） | X3 | 待复验（轻） | R1（与 E 族同批显式 switch/LocalizedStringResource 化） |
| M-17/M-18（原 J7/J8） | EqualizerPanelView:51／LuminanceColorRangePanelView:332 | 同上 | X3 | 待复验（轻） | R1 |
| M-19/M-20（原 J9/J10） | InspectorRowView.swift:73,80 | 运行时变量包 key / 已解析串二次查表（locale 切换失效） | X3 | 待复验 | R3 → 随 R1 本地化件顺路 |
| M-21..M-23（原 J11-J13） | PresetPanelView:107／FilmPanelView:384-393／EDRControlView:46 | 本地化组句拼接/format 键形 | X9 邻 | 待复验 | R3 → R2 本地化卫生件 |
| M-24（原 J16） | InstancePickerOverlay.swift:34-36,100-129 | body 期 plane/CGImage 重建（CPU mask 读取 + 缓冲分配） | — | 待复验 | R3 复验队列 |
| M-25..M-27（原 J17-J19） | EditorNodesPanelView:82-117／SidebarView:182-206／FilterBarView:45-202+EditorAreaView:61-328 | 千行级单失效边界（structure.md 分节族 major 档） | X6 邻 | 待复验 | R3 复验（与 AR-01 已修族同型，可信度高；EditorAreaView 部分随 F0'-prod） |
| M-28..M-30（原 J20-J22） | MaskGroupsPanelView:88-149／RetouchPanelView:90-227／CatalogBrowserView:81 | 分节 major + 整行 struct 深哈希 id | — | 待复验 | R3 复验 |

### 5.2 minor（在账 96 条目 + 补扫 1 条）

- **N-F11（LutPanelView `.id` 子树重置）→ 不入常规队列**：与 B-o6 同点交叉确认（X8），**维持挂账 D-6 专项卷**。
- **N-S1..N-S24、N-S26..N-S28（分节族 26 条）→ R6 随触随迁**：与 A 路 modernize-tests 同判——全量分节改造是大工程低单位收益；D-H1 热路径面板（Film/Drt）AR-01 已拆，其余按「触到哪个文件顺手拆哪节」执行，不立项专项。
- **N-L1..N-L36（本地化族 36 条，N-L37 为肯定项非 finding）→ R2 卫生批本地化件**：eager 解析族（N-L1/L2/L3/L14，LightamerSlider `label: String` 为根因约 40 调用点——改型是跨文件协调件，单独立小批候选）、format-style 族（N-L4..L8/L10..L12/L18..L28）、verbatim 补明族（N-L9/L25/L29/L31/L32/L36）。机械度中高，逐处面核执行。
- **N-D1..N-D18（数据流族 18 条，N-D13 为指针）→ R6 随触随迁/低优先**；其中 N-D7/N-D8/N-D9/N-D10/N-D17 触 F0'-prod 文件面 → **R5 顺路评估**。
- **N-F1..N-F10（ForEach 族 10 条）→ R2 卫生批小件**（F6 popover item id、F8 空白分类碰撞两处有真实边界，优先面核）。
- **N-K1 → R5**（ContentView @AppStorage，F0P 触达文件）。
- **补扫 35 处（§6）→ R2 卫生批机械件**。

### 5.3 obs（C 44 + B 9，指针化处置）

- **R5 随 F0'-prod 顺路评估**（F0P-01/02/03 触达文件面）：O-11（EditorMTKView updateNSView——**P1 T2 恰触同函数**）、O-14/O-15/N-D17（InspectorView——P1 T3 触达）、O-16/O-36/O-37/O-41（WorkspaceHostView/ContentView）、O-43/N-D7/N-D8/N-L30/N-L16-WHV 半边（LightamerApp——**N-D7/N-L30 预期随 P3「SwiftUI App/Scene/Commands 全族退役」自然消解，顺路核销**）。
- O-38（CullingView transition）→ 随 M-1 同文件顺路核。
- 其余 O-1..O-10/O-12/O-13/O-17/O-20..O-35/O-39/O-40/O-42/O-44 + B 路 o1..o9（已处置）：维持「需运行时验证」清单指针化，不逐条展开（正本 = OMP-FINDINGS §obs + LANEB 对应条）。

---

## §6 合并批补扫发现（本批新增，三路均未全数命中）

**R-NEW-1 · overlay/background 旧 View 重载残留 35 处 / 19 文件**（`rg "\.(overlay|background)\($" + 参数行形态机检 + 抽样面核；1 处合法 `ShapeStyle+in:` 形已排除＝MaskGroupsPanelView:108）：

- Library/Views：LibraryInspectorView :63/:91/:548、GlobalSearchDialog :50/:54/:93、LibraryGridView :321/:379、RelinkSheetView :84/:88/:131
- UI：CatalogFilterBarView :115/:156、EmptyStateView :52/:56（=M-7）、McpLauncherPanelView :281、FilterBarView :177
- UI/Shell：EditorWorkspaceShellView :62/:82、FilmstripView :311、VersionsPanelView :266、EditorToolRailView :87/:242、BackgroundTaskBarView :83、WorkspaceHostView :497/:685（HEAD 实证在位；**该 2 处随 F0'-prod 顺路**）、Nodes/EditorNodesPanelView :289/:292/:436/:533/:536
- UI/Views+Overlay+Inspector：EnhanceDialog :237、SegmentEditingOverlayHost :186、MaskGroupsPanelView :391、HlsPanelView :162

**根因**：A 路机扫按单行/符号命中，多行实参形（`.overlay(` 行尾 + 实参次行起）成盲区——A 路清单 15 处均单行形；C 路仅点名 EmptyStateView 一处（J25）。**全部为软废弃卫生件（无行为差）**，改尾闭包形机械等价 → R2 卫生批（AR-03 同款工序：grep 清零机检 + 观感零差预期）。

---

## §7 修复批次路由分布汇总

| 路由 | 内容 | 构成 |
|---|---|---|
| **R1 下一修复批**（行为缺陷 + 已亲核 major + 禁形小件） | M-1 CullingView pair 重载（首项）、M-5/M-6 ForEach 可增删身份、M-2/M-3/M-4 E 族显式化（10 定义臂 + 1 直插值）、M-10..M-18 动态键调用点族、M-8 KD-4 注入化、M-9 ImportModeDialog 注入化 | error 实锤 0；cross/亲核 confirmed major 9 + 禁形族 ~9 |
| **R2 卫生批（机械）** | §6 补扫 35 处尾闭包化 + M-7；N-L 本地化族 36 条（分 3 小件：eager 解析改型/format-style/verbatim 补明）；N-F1..F10 小件 | 全机械或半机械，grep 机检可验收 |
| **R3 复验队列**（单路独有 major 未亲核） | M-19..M-23 本地化拼接族、M-24 InstancePicker plane 重建、M-25..M-30 结构大件族（与 AR-01 已修族同型） | 6 组，复验后定级入 R1/R6 |
| **R4 D-6 专项卷**（挂账维持） | B-o6 + N-F11（LutPanelView `.id` 同点双确认） | 1 项 |
| **R5 随 F0'-prod 顺路评估** | M-27 的 EditorAreaView 半边、N-D7/N-D8/N-D9/N-D10/N-D17/N-K1/N-L16(WHV)/N-L30、O-11/O-14/O-15/O-16/O-36/O-37/O-38/O-41/O-43 | N-D7/N-L30 预期随 P3 退役自然消解（顺路核销）；WorkspaceHostView 补扫 2 处亦随路 |
| **R6 挂账/不立项/维持** | A F1/F2/F3（D-M7-AR-1）、A §4、B m10（D-M7-AR-8）、B o4、N-S 分节族 26 条、N-D 余量（随触随迁）、N-I1..15（已裁销账）、C 路 obs 余量（需运行时验证清单） | 维持既有裁决 |

**总量对账**：在账 major 28（R1 18 / R3 6 / R5 挂 4 半边）；minor 在账条目 96 + 补扫 1（R2 ~47 / R5 ~11 / R6 ~39）；obs 指针化 50（R5 14 / 维持 36）。error 实锤 **0**。

---

## §8 方法注记与勘误

1. **error 甄别协议**：源码定义点+消费点亲读 → catalog（`Resources/Localizable.xcstrings`，1958 键）python 机检（16+1 键在册性 + extractionState）→ `instance` 类型溯源（Core `AIMaskService.swift:817`）→ **mini-bundle 运行时实验**（`/tmp/lvtest`，swiftc 编译直证直插值合形与 String 包壳形分别的查表键）——C 路未跑构建的编译面推断由此闭环。
2. **抽验五条**：M-1（机制链完整亲读）、M-5/M-7/M-8（代码形态直证）、M-9（结构性证实 + 调点定位）；AR-02 修复形态亲核（`ChannelMixerRGBPanelView:26` `private let params` 在位）。
3. **补扫脚本**：行尾 `.(overlay|background)(` + 次行实参形态分类（SHAPE/VIEW-ARG vs 合法 SHAPESTYLE+in:），WorkspaceHostView 两处经 `git show HEAD:` 双验（在飞工作树不产差异）。
4. **C 路文档勘误两条**：①N-D13「见 O-38」为编号滑——WorkspaceHostView:622-692 对应条目实为 **O-37**（O-38 = CullingView transition）；②minor 结论头 127 vs 逐条落账 114（§2 校准 2）。
5. **时序事实**：AR-03 于 C 路交付前收工（omp 凭证 401 阻塞→当日解锁重跑）；「C 路并入条款」顺延至本 MANIFEST 之后的 R1/R2 批执行——AR-03 的 43 处机检判据（零命中）今日复核仍成立，补扫 35 处不在其清单口径内，不构成 AR-03 验收缺陷。
6. **在飞申报**：工作树 `M App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift` = F0'-prod P1 在制；本批零源码触碰，全部观察以 HEAD 为准（抽验点均双验）。
7. **产物登记**：本目录八件 = 三路 findings 正本 + 归档三件（task/blocked-note/stdout）+ slices（6 worker 分片）+ 本 MANIFEST；commit = `docs(audit): three-lane reconciliation — merged findings and repair routing`。
