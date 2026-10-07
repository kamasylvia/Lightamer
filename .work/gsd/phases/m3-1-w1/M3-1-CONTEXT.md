# M3-1-CONTEXT — W1 前置批（M2GRADE-08 + YIYIN-09 + 小件族）讨论/研究定稿

> **Phase 定位**：Milestone 3「胶片暗房」W1 前置批 = M2GRADE-08（LUT 作者编码建模，FSIM-01 软前置基建）+ YIYIN-09（yiyin sheet 预览拖拽 mini-plan）+ 小件族（冲突档选择器 UI / peak-ICC 标注 / denoise 拖动降档预览语义 / V14+V15 zh 清算）。
> **立项依据**：`phases/v2-station/V2-PROPOSAL.md` §二/§五 W1 行 + `OQ.md` OQ-V2-7/9/10 裁决记录（2026-10-08 用户预裁「按推荐」全部生效，`6e265ee`）。
> **C 档第 1 停**：本文件定稿即本 phase 规划动作终点；§六 Open Questions（OQ-M3-1-1..7）交用户裁决后才进 plan。上游 V2 站 OQ 预裁只覆盖「做不做/哪波做」，**不覆盖本文件的实现语义分叉**——每个 OQ 仍须用户点头（或「按推荐」批注）。
> **研究正本**：同目录 `RESEARCH-NOTES.md`（Alcedo `c740f7b` / yiyin `a7ab9f8` file:line 实测 + 底座锚点）。

---

## 一、任务面盘点（W1 范围与不范围）

| 面 | 来源 | W1 交付口径 | 明确不做 |
|---|---|---|---|
| M2GRADE-08 LUT 编码建模 | REQUIREMENTS :388（→ M3-W1 注记） | 编码目录 + LMT 生效 + 库内逐 LUT 记忆 + 面板双选择器 + golden | 传递曲线/色域目录的 FSIM 复用面（目录建好即止，FSIM 消费归 M3-3）；色域矩阵已有 `LutColorspace` 不重做 |
| YIYIN-09 预览拖拽 | REQUIREMENTS :278 | 上游 PR #126 拖拽语义映射到 yiyin sheet（映射方式 = OQ-M3-1-5） | yiyin M2 导出页 yiyin 节（V17 既有挂账维持）；上游图像列表形态不移植 |
| 冲突档选择器 | M2-9-VALIDATION 挂账#4 + :59 行晨审判定 | Export M2 页暴露三档 Picker + `enqueueExportM2` 消费选择值 | 引擎零改动（`ExportCollisionPolicy` 三档已交付钉死）；legacy sheet 零触碰 |
| peak-ICC 标注 | M2-9-02-DECISIONS §2 + M2-9-05 挂账 | HDR 档导出页 DRT readout 补 peak 语义说明面 | `DrtOutputColorSpace` 加 peak 参数位（§2 明文「有意缺席」——注释面不动签名面）；UltraHDR 容器（ALCE-02，M4） |
| denoise 拖动降档语义 | perf.md §OQ-7-A + M2 栏 M2 挂账行 | 拖动态降档 + 松手全质量（自动 vs 手动 = OQ-M3-1-6） | nlmeans kernel 重写/时域复用（C 案，L，继续挂后）；decimate 三档引擎腿已 revert 不复活 |
| V14+V15 zh 清算 | FINDING-G（VALIDATION-INPUT :127）+ V15 | 标记菜单裸键清算 + zh-audit 提取器硬化 + 存量 zh 缺口 sweep | 新键批零预期（doc/UI 修补面）；M2-7 动态族 52 键式全族对账方法论沿用 |

## 二、M2GRADE-08 语义设计（推荐形态，细节随 OQ 裁决定）

### D-M3-1-CONTEXT-1：编码目录 = 表驱动 Encoding 目录（Core 级新建）

- **形态对表**：Alcedo `color_encoding_catalog.cpp` = 22 gamuts + **26 encodings** 常量表，每条 `{id, gamut, transfer, referral(scene|display), peakLuminanceNits, displayName}`（`kEncodings` :139-172；`kGamuts` :35-57）。查找 `FindColorEncoding(id)` 线性扫 :205-215，未知 id typed 拒绝（`lut_bake.cpp` `RequireEncoding` :293-300）。
- **我方落点**：`LightamerIOP/Sources/Lut3d/` 新文件（如 `LutEncodingCatalog.swift`）——纯数据 + 传递函数纯函数（Float64 参考 + Metal 表达式双落笔，M2-6 EOTF 先例同款方法论）。GPL 零复制：数学自各公开标准（BT.709/BT.2100/ARRI/Sony 等厂白皮书），Alcedo 只对表**行集与字段形**。
- **与既有 `LutColorspace` 的关系**：现有 `Lut3dModule.Params.colorspace`（`Lut3dModule.swift:39-44`：sRGB/displayP3/rec2020/proPhotoLinear）= **色域矩阵**维（`LutColorspaceMatrices.swift:82-105` 已有 Rec2020↔sRGB/P3/ProPhoto 正逆阵）；M2GRADE-08 新增的是**传递曲线 + referral + peak** 维。两维正交并存——面板上现有 colorspace Picker 不动，新 input/output encoding 两 Picker 另立（组合语义 = OQ-M3-1-2 裁目录集时一并定：是否以 encoding 目录吸收 colorspace Picker〔display 家族行已含 gamut〕，倾向**不吸收**，零破坏旧档）。

### D-M3-1-CONTEXT-2：未标注默认 = working space 直通（保现状逐字节）

- **对表**：Alcedo 默认 id = `kDefaultLutEncodingId = "acescc"`（`lmt_model.hpp:23`）= **其 working space 本身**（`lut_bake.cpp` `IsWorkingSpace` :33-35 以 id 判定；static_assert `lmt_model.cpp:15-16` 钉 LMT 默认 = 目录默认）——即「未标注 = 双端 working space = 直通快路径」（:321-323 源表原样返回，零烘焙）。
- **我方**：默认对 = `{"linear_rec2020", "linear_rec2020"}`（id 拼写随目录集定）——语义 = **现行 working space 直套行为逐字节保持**。拒绝 sRGB 假设方案：那会改变全部既有文档的渲染面，且与「M2GRADE-08 修偏差而非引入新默认偏差」目标相反。
- **快路径**：双端 working + 表域 [0,1] 单位域 → 解析表原样直通（对表 `HasUnitDomain` :195-203 + :321-323）。

### D-M3-1-CONTEXT-3：LMT 生效点 = 宿主侧复合表重烘焙（零新 kernel）

- **对表**：Alcedo 不做 kernel 前后双 pass——`ResolveLmtSampledTable`（`lut_bake.cpp:317-352`）把编码对**烘进 3D 表本体**：逐 voxel `inputDecode(voxel) → 源表采样 → outputEncode`（`BakeLmtCompositeTable`，宿主线程池 + Float64 矩阵乘 :46-56）；复合表 65³ RGBA32F ≈4.4MiB，进程级 LRU 16 张（`CompositeCache` :117-158），键 = `{sourceHash, domain, input_id, output_id}`（`CompositeKey` :88-101）；烘焙数计数器可观测（`LmtCompositeBakeCount`）。
- **display 臂语义**（对表 `DisplayEncode/DisplayDecode` :60-108）：display-referred 行以 **display light（1.0 = 100 nits）** 为中介——decode 时 PQ/HLG clamp、HLG 施加参考显示器 OOTF、SDR 按 peak 换算；encode 反向。scene log 臂走传递曲线正逆。peak nits 只对 display 家族生效。
- **我方落点**：`Lut3dModule` 的解析表装配缝（`commitParams` → `resolver.lut(named:)` → 纹理上传，`Lut3dModule.swift:139-143/:194` 一带）插入烘焙步：CPU Float64 复合表 → 照常上 GPU。**缓存失效免费**：编码对入 `Params` → `paramsHash`（D-H4 既有，:139-141）随值变化 → PipeCacheKey 链自动 miss，无需新缓存层；烘焙本身再挂模块内 LRU（对表 Alcedo 16 张）防切档抖动。tiling 路径零触碰（烘焙发生在表装配，非 per-tile）。
- **优势**：零新 kernel（红线传承）；golden 测试 = Float64 CPU 参考对照 Metal 表采样（`Lut3dGoldenImageTests` 家族沿用）；替代方案（kernel 前后双 pass）列为 OQ-M3-1-3 选项。

### D-M3-1-CONTEXT-4：库内逐 LUT 记忆 + 三层读取序（Alcedo 同构）

- **对表**：Alcedo 库用户态 JSON `remembered_encodings: {entry_id: {input, output}}`（`lut_library_inventory.cpp` 读 :98-118 / 写 :172-179 **仅在非空时写字段 = 无记忆档字节零漂移**）；控制器载入序 = `RememberedEncodings(entry_id).value_or(默认对)`（`lut_library_controller.cpp:320-324`——库记忆优先于默认，**无库记忆 = 默认对**）；「记住编码」是**开关**（`setRememberEncodings` :333-339，仅库内 LUT 可记 :334-336）；面板枚举模型条目按 scene/display 分组（`editor_lut_encoding_model.cpp:23-40` groupLabel Tr("Scene")/Tr("Display")），默认 index = acescc。
- **我方落点**：
  1. `InstalledLut` 增 additive 可选字段 `{inputEncoding?, outputEncoding?}`（`LutLibraryStore.swift:52-80`）——synthesized decode 宽容 + 迁移幂等（M2-5 key 升级先例同款）。
  2. **三层读取序**：文档 params 显式值 > 库记忆对 > 默认对。选择库 LUT 时自动载入库记忆对进 params（若有）；用户改 Picker 即写 params（history 单 commit，D-H1 惯例）；「记住到库」开关控制 Picker 变更是否回写库条目。
  3. **旧档兼容**：旧 sidecar/history 无编码字段 → decode 缺省 = 默认对 → **渲染逐字节不变**；编码字段进 params 后随 history item 持久化（schemaVersion 不动——Params Codable additive，v7 双键拼写惯例同款纪律）。
- **内置集补标（渲染观感变化点，OQ-M3-1-4 裁）**：40 张内置 spectral film LUT 的作者编码对**有案可查**——生成参数 = `input ARRI Wide Gamut 4 / output Rec.709 + Gamma 2.4`（`phases/m2-5-color-grade/evidence/spectral-film-lut-license.md:150-152`）——即它们本该以 LogC4/AWG4 编码进、Rec709 BT.1886 族出，**当前直套 working space = M2GRADE-08 要修的系统性偏差本体**。补标 = seeder 写入记忆对（seed 时自动）→ 新选这些 LUT 即得正确管线；既有已选文档按三层序停在默认对（旧渲染），用户重选/手动改编码后迁移。是否顺带强制翻转既有文档 = 不做（非破坏性红线）。

### D-M3-1-CONTEXT-5：golden 与验收锚

- log 域 LUT 对照 golden：合成 log 编码梯度表（已知逆变换）+ 内置集抽样（AWG4/Rec709g24 对走通全链）；容差带沿用 p99.9≤1e-5 分级（M2-5 golden 惯例）。
- 上游对表锚：`lut_encoding_render_paths_test.cpp` / `lut_remembered_encodings_controller_test.cpp`（Alcedo 测试名即行为清单）；烘焙计数器断言（快路径零烘焙 / 换对恰一次烘焙）。
- 快路径回归：全部既有 LUT 测试零 diff 全绿（`Lut3dKernelTests` / `CubeLutParserTests` / `LutLibraryStoreTests` / `BuiltInLutSetTests` / `Lut3dGoldenImageTests`）。
- FSIM-01 软前置交付物：目录表 + 传递曲线正逆函数族即 FSIM 消费面（M3-3 直接复用，不二次返工——V2-PROPOSAL §三推荐理由 1）。

## 三、YIYIN-09 语义设计（上游形态实测 → 我方映射）

- **上游语义全量**（`a7ab9f8`，`web/main/components/actions/index.svelte`）：双分割线（width 轴 = 预览面板宽 vs 图像列表；height 轴 = 预览图区高），拖拽 = pointer capture + 容器 rect 相对坐标；**双重钳制**（绝对 px 界 120-720 / 160-560 × 可用域比例界 0.15-0.75 / 0.35-0.92，且扣除 SPLITTER 6 + gap 15×2 + IMG_LIST_MIN 180）；**比例持久化只在 pointerup**（3 位小数，`persistPreviewRatio`）；**拖动中禁内容重算**（`isDragging` 早退 `applyPreviewSize` + 预览更新键剔除布局字段 `delete options.preview_pane_*`，防拖拽触发 300ms debounce 重渲染）；容器 ResizeObserver 按比例重排；实时尺寸读数 `${w} × ${h}`。持久化键 `preview_pane_width_ratio: 0.5` / `preview_pane_height_ratio: 0.85`（`electron/src/config.ts` + `web/store/config.ts` 默认值块）。
- **我方现状**：`YiyinTopBarSheet`（`WorkspaceHostView.swift:1216-1285`）= 固定 `.frame(width: 420, height: 560)`（:1273），内容纯控制面（YiyinPanelView + TextOverlayPanelView 滚动列），**无预览区**；`YiyinPanelView.swift:28-29` 明文「The main viewport IS the preview（no panel canvas — the pipe renders live）」——主视口即活预览。
- **映射方案**（OQ-M3-1-5 裁）：推荐 **A = sheet 自身拖拽调尺寸**——右/下缘分割线双方向，SwiftUI 等效 = `GeometryProxy` 读容器 + `DragGesture` 换算，双重钳制 + 拖动中零 history 零重排 + 松手写 UserDefaults ratio 键 + 尺寸读数；上游五条语义（双钳制/松手持久/拖动禁重算/ResizeObserver 等效 `onGeometryChange`/读数）逐条移植，**不新增 in-sheet 预览渲染腿**（主视口已活预览，in-sheet 快照 = 冗余渲染负载）。方案 B（in-sheet 预览区 + 双分割线，最贴上游像素形态）= M 级（新增 pipe 快照渲染腿），列为选项。

## 四、小件族语义设计

### D-M3-1-CONTEXT-6：冲突档选择器（引擎零改动纯 UI 暴露）

- 现状：`enqueueExportM2` 固定 `.increment`（M2-9-VALIDATION 挂账#4 + :44/:59 行——引擎/模型三档单测+E2E 钉死，档位选择器从未暴露；晨审判「必须暴露」）。
- 交付：Export M2 页「文件命名」节加三档 Picker（Increment 默认 / Fail / Replace——键族随 zh 审计入账）→ `ExportVariant`/装配链消费用户选择值替换写死档。引擎 `ExportNamer.swift:21` 零 diff；legacy sheet 零 diff；`testDefaultOverloadEqualsIncrementTier` 等既有钉死测试零改全绿。

### D-M3-1-CONTEXT-7：peak-ICC 标注（说明面，签名面零触碰）

- 边界正本 = `M2-9-02-DECISIONS.md:41-45`：peakLuminance **有意不进 ICC**（ICC 只承 space+TRC；渲染消费在 EotfBox record、入队校验在 `ExportVariant.validate` peak 闸门）；真 HDR peak 容器 = UltraHDR（ALCE-02，M4）。
- 交付：Export M2 页 DRT readout 在 HDR 编码档（st2084/hlg）补一行说明（peak nits 当前值 + 「ICC 嵌入仅含色彩空间与传递函数，峰值亮度不进 ICC；真 HDR 容器 UltraHDR 规划中」）——纯文案 + 本地化键；`DrtOutputColorSpace` 签名零改。

### D-M3-1-CONTEXT-8：denoise 拖动降档预览语义（UX 化，非引擎腿）

- 在案事实：nlmeans 拖动本征 ~65/57.5ms 超 16.6ms 预算；decimate 三档（57→37→29 趟）引擎级全不达 revert（`perf.md:43-64`，OQ-7-A 默认退出路径）；「V2 备选语义（拖动降档预览）」明文移交（perf.md:60）。
- 设计（自动 vs 手动 = OQ-M3-1-6）：推荐**自动**——拖动中该图 denoise 实例临时降档（跳过/减趟，降档参数不进 params 不进 history），状态条提示「预览降档」，松手恢复全质量恰一 commit（D-H1 三件套惯例：拖动零 history、松手一次）。降档选择器维度（禁用 vs 减趟 K）plan 期按实测观感定。
- 隔离注记：只动 App 层交互面（拖动态判定 + 临时参数旁路），`NLMeansModule` kernel/参数面零改——与 M2 挂账「kernel 重写 C 案」不混。

### D-M3-1-CONTEXT-9：zh 清算批范围清单

- V14 / FINDING-G：标记菜单裸键 `metadata_rating_1..5` / `metadata_color_0..5`（`M2-11-VALIDATION-INPUT.md:127`，F-2 插值键陷阱同族——动态查表键 scanner 不可见，修复形态禁 `String.LocalizationValue("prefix_\(x)")` 新写法）。
- V15：zh-audit 提取器硬化（continuation 漏提面）。
- 存量 sweep 输入：M2-6-3 F1（ProjectWorkspaceFace 4 处 zh 缺口，GOAL-STATE 挂账）+ M2-7 方法论（SUMMARY 键清单并集对账：静态 MISSING + 动态族双清单核对，AGENTS「M2-7 架构增量」xcstrings 节）。
- 验收：`zh-audit --check` PASS + 走查标记菜单实机 zh 呈现。

## 五、隔离前提（在飞修复批，强制）

- **FINDING-F = LUT 导入面板取消 SIGSEGV**（L057 家族，`LutPanelView:159` 导入按钮取消链；正本 `M2-11-VALIDATION-INPUT.md:123`，.ips = `profile/guiwalk-crash-2026-10-07-0937-lut-import-panel.ips`）+ **ToneEqual encode 路径悬垂 retain 排查**（:186 M4 行）——用户裁决走修复批，**已派遣在飞**（:221）。
- **owned 面交叉**：修复批 owned = `LutPanelView` 导入取消腿 + IOP ToneEqual 面；M3-1 的 M2GRADE-08 面 = `LutPanelView`（新增 encoding Picker 区）+ `LutLibraryStore`/`Lut3dModule`（IOP 包）——**`LutPanelView.swift` 文件级交叉**。
- **隔离纪律**：本批（docs research）零源码触碰已合规；**M3-1 执行波派发前必须复核 `git log` / GOAL-STATE 确认修复批 FINDING-F 腿已落**（或 orchestrator 显式协调顺序）；若未落，LUT 面任务后置、小件族/zh 清算先行（互不 owned）。冲突档选择器（Export 页）与两修复面零交集。V2-PROPOSAL §六 :171 同款纪律对全部 M3 waves 生效。
- 修复批落地形态未知（属他人 owned）——plan 期 `LutPanelView` 改动以**增量 hunk** 为准，不假设行号基线。

## 六、Open Questions（OQ-M3-1-1..7，交用户裁决）

> 每条 = 选项 + 推荐 + 理由；「按推荐」批注可整批快速通过（V2 站预裁先例），用户可逐条推翻。

- **OQ-M3-1-1 LUT 未标注默认编码策略**
  ①默认对 = working space 双端直通（= 现行为逐字节保持）②默认 input 假 sRGB ③选 LUT 时强制用户选编码。
  **推荐 ①**——对表 Alcedo（默认 id = 其 working space acescc，直通快路径）；② = 引入新系统性偏差且翻全部旧档渲染；③ = 破坏「选上即用」流。
- **OQ-M3-1-2 编码目录集首波范围**
  ①精选子集（scene：acescc/acescct + 主流量产机 log〔slog3/clog3/vlog/flog/nlog/applelog 等 8-10 条〕；display：sRGB/BT.1886/gamma22/PQ 族/PQ/HLG + linear；≈14-18 条）②首波镜像 Alcedo 全 26 条（22 gamuts 随行）③最小集（acescc/acescct + sRGB + BT.1886 + linear 共 5-6 条）。
  **推荐 ①**——表驱动可扩（加行 = 加条目，编译期穷举 switch 破缺警告）；② = 每条传递曲线都是真数学+golden 工作量，22 gamuts 里相机原生域大多无 LUT 语料拉动，L 化失控；③ = 欠 FSIM-01 前置宽度（相机 log 族是胶片 LUT 语料主群）。内置 40 张的对（AWG4/Rec709g24）必在集内。
- **OQ-M3-1-3 LMT 编码生效机制**
  ①宿主侧复合表重烘焙（Alcedo 同形，零新 kernel，paramsHash 免费失效 + 模块内 LRU）②Metal kernel 前后双 pass（decode pass → LUT → encode pass）③烘进现 tetrahedral kernel 加 uniforms 分支。
  **推荐 ①**——上游对表 + 零新 kernel 红线传承 + tiling 零触碰 + golden 走既有 CPU 参考通道；②每帧两趟额外全屏 pass 性能劣；③触碰热 kernel 违红线精神。
- **OQ-M3-1-4 内置 spectral film 40 张补标作者编码对（观感变化点）**
  ①seeder 自动补标（input arri_logc4_awg4 / output rec709_bt1886 族）+ 交付注记声明「新选档观感变化 = 修正非回归」②不补标（内置集维持直通，用户手动设）③补标 + 既有已选文档一次性翻转。
  **推荐 ①**——生成参数有案（`spectral-film-lut-license.md:150-152`），补标后新选即正确管线；既有文档按三层读取序停在旧渲染（非破坏性红线，③违之）；② = 把已知偏差留作默认。
- **OQ-M3-1-5 YIYIN-09 映射与双方向**
  ①sheet 自身拖拽调尺寸，双方向（width+height），上游五语义移植，零 in-sheet 预览 ②sheet 内新增预览区 + 双分割线（贴上游像素形态，需 pipe 快照渲染腿 = M 级）③仅高度方向单分割线。
  **推荐 ①**——主视口即活预览（`YiyinPanelView.swift:28-29` 在案），in-sheet 预览 = 冗余渲染；S 规模纯 UX；双方向都做（上游语义本就双轴，砍轴省不了什么）。②若用户要像素级对表可选，规模升 M。
- **OQ-M3-1-6 denoise 拖动降档自动 vs 手动**
  ①自动（拖动态临时降档 + 状态条提示，松手全质量一 commit）②手动开关（用户全局选「拖动时降档」）③不做（维持现状拖动卡顿）。
  **推荐 ①**——OQ-V2-3 预裁①「UX 语义搭车」的自然解读；引擎降档三档已证数学不可达常开，拖动态临时降正是剩余低成本路径；②多一个设置项但无额外能力（拖动者即在意流畅者）；③ = 挂账不消。
- **OQ-M3-1-7 小件族波内编排**
  ①合并 1 plan 多任务串行（冲突档选择器 + peak-ICC + denoise 语义 + zh 清算四任务面互不相干，一 plan 多 commit）②冲突档选择器随 fix(m2-9) 通道单独走（晨审原判通道），余三件合 1 plan ③四件各独立 mini-plan。
  **推荐 ①**——四任务面零文件交集（Export 页 / Export 页文案 / App 交互层 / 本地化面——前两件同页可同批触碰），一 plan 一验收一轮全套最省流程开销；②会把 Export 页拆两批触碰反而搅；③流程开销 > 任务本身。

## 七、验收锚草案（进 plan 的 AC 素材）

1. M2GRADE-08：内置集抽样走 LogC4→LUT→Rec709g24 全链 golden（p99.9≤1e-5）；快路径（默认对）既有 LUT 测试族零 diff 全绿 + 烘焙计数断言；库记忆三层序单测（params 显式 > 库记忆 > 默认）；旧 sidecar 解码零漂移断言；面板双 Picker scene/display 分组走查。
2. YIYIN-09：双方向拖拽走查（钳制边界两终端值 + 读数）+ ratio 持久化跨会话回归 + 拖动中零 history/零重排断言 + AX id 在册。
3. 冲突档：三档 Picker → 队列行为单测（Fail = typed 拒绝零写盘 / Replace 永不落 -N——既有引擎断言消费面复用）+ 走查；M2-9-VALIDATION 挂账#4 关闭条件达成。
4. peak-ICC：HDR 档说明行走查 + 键入 zh 账。
5. denoise：拖动降档态单测（临时参数不进 params/history）+ 松手一 commit 断言 + 实机拖动观感走查（26.5ms 引擎级数字不回归为本——UI 腿禁触 kernel）。
6. zh：`zh-audit --check` PASS + 标记菜单实机中文 + 提取器硬化负测（动态键可提）。
7. 全套：`Scripts/test-direct.sh --all` 终轮绿（MEMFAIL 机检在册）；红线文件机检零 diff（PipeCacheKey/V50Order/Registry/六格式矩阵编码器/WebPEncoder/NLMeans kernel）。

---

*定稿：2026-10-08（discuss/research 起草 subagent）。C 档第 1 停生效——OQ-M3-1-1..7 裁决后进 plan。*

## 裁决记录（用户回批 2026-10-08）

**OQ-M3-1-1..7 全部按推荐采纳**：①未标注默认 = working space 双端直通 ②编码目录精选 14-18 条表驱动 ③LMT 生效 = 宿主复合表重烘焙 ④内置 40 张 seeder 自动补标 AWG4/Rec709g24 + 观感变化交付注记 ⑤YIYIN-09 = sheet 自身双方向调尺寸 ⑥denoise 自动降档（拖动降档+状态条+松手一 commit）⑦小件族合并 1 plan 多任务。
