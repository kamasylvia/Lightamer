# M3-3-03-SUMMARY — FSIM golden 与收口批（wave 3）

> 执行：2026-10-09 夜间（executor subagent，夜间全自动授权在案）。
> 基线：`2fee806`（全套实测 3125/16/0）。产出 commits：
> `9f4a649` fix(iop) → `6c83505` test(iop) golden → `b10df2c` test(core)
> determinism → `94168f8` feat(app) film panel → `5a8a2f8` feat(app) film
> card → T5 本批 docs。**未 push**（纪律）。

## 一、交付面（对表 plan front-matter files_modified）

| 文件 | 变更 | commit |
|---|---|---|
| `Tests/LightamerTests/FilmGoldenTests.swift` | 新建（IOPP，Golden* 域）：四门 12 法 = kernel 两级门（1a 同表采样 8.7e-5/钉 1e-4 + 1b 理想模型凸性门 + 平面元 6.2e-3/钉 2e-2）+ bake 体素级 ≤1e-5 + 置位曲线族 + 中性闭合 1.4e-3/钉 2e-3 | 6c83505 |
| `LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift` | **m=1 阴影闭式符号修正**（K = t ± √…，分支方向定号；golden 门逮住，见 DECISIONS §5） | 9f4a649 |
| `Tests/LightamerTests/FilmDeterminismTests.swift` | 新建（LAYERS）：solve bit-identity + 键折叠精确值钉死（小端 FNV 双写）+ 跨 ROI 同解端到端（周期夹具 A/B 窗一条目 + 重叠字节相等）+ 整数秩手算 + 平面 hash 哨兵 `FilmGoldenConsts` | b10df2c |
| `App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift` | 新建：三级读（live → history → carrier）+ 单 discrete commit + D-H1 三件套 + 启用默认对 + solve readout + invalidateAll | 94168f8 |
| `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift` | 新建：启用入口/双 Picker/Y·M·强度·曝光滑杆/内容自适应 Toggle/readout+Solve/关闭面 | 94168f8 |
| `App/Sources/Lightamer/State/InspectorState.swift` | `filmPageActive` 会话开关（exportPageActive 孪生） | 94168f8 |
| `App/Sources/Lightamer/State/PipeCoordinator.swift` | 只读三面 additive（filmMaterialStore/currentFilmRecord/hasFilmRecord——面板与卡的唯一数据源） | 94168f8 |
| `App/Sources/Lightamer/UI/InspectorView.swift` | filmPageActive 整列分支（inactive 面逐字节现状） | 94168f8 |
| `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift` | `FilmSolveCache.invalidateAll()` 失效缝（Solve 按钮） | 94168f8 |
| `Resources/Localizable.xcstrings` | film_* 19 键 + history_film_* 4 键 + editor_node_film* 3 键（尾块纯插入；zh-audit PASS 1557/1795） | 94168f8 / 5a8a2f8 |
| `App/Sources/Lightamer/UI/Shell/Nodes/NodeCanvasGeometry.swift` | `filmCardID` 常量 + `layout(includesFilmCard:)` additive 默认参（ grades/DRT 之间 = sub-run 物理座位；默认调用零改） | 5a8a2f8 |
| `App/Sources/Lightamer/UI/Shell/Nodes/NodesPanelModel.swift` | `FilmCardProjection`（pair 名 + active）+ pipeCoordinator 注入 | 5a8a2f8 |
| `App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift` | Film 卡视图（只读/导航面/AX 三件）+ cardsLayer 渲染支 | 5a8a2f8 |
| `App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift` | 构造点传 coordinator/inspector（卡数据源） | 94168f8 / 5a8a2f8 |
| `Tests/LightamerTests/FilmPanelTests.swift` / `FilmCardTests.swift` | 新建（APP）：面板事务面 6 法 + 卡 4 法 | 94168f8 / 5a8a2f8 |
| `Project.swift` / `M2-4-0-BUNDLE-MAP.txt` | 测试登记（L041 批尾 generate ×3）+ 增行四条 | 随各任务 |
| `.work/gui-acceptance/m3-3/` | MANIFEST + 画布 Film 卡实机截图 + zh-audit PASS | T5 |

## 二、AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | golden 主门四门零失败、复算独立自包含 | ✅ 12/12（凸性门 400 探针零违例；体素 ≤1e-5；m=1 双侧精确；中性闭合 1.4e-3） |
| 2 | 确定性门五件 | ✅ 5/5（bit-identity/键精确值/跨 ROI 同解一条目+重叠字节相等/手算秩/hash 哨兵） |
| 3 | Film 面板最小面 + DrtPanel 零 diff | ✅ 6/6；DrtPanelModel/View 零 diff（§8 机检）；**Film 页实机走查受阻**（DECISIONS §6 click-dead，挂 M3-4 走查清单——非本批门，事务面机检覆盖） |
| 4 | 只读卡 + NodeKind 零 diff + 命令面零扰 | ✅ 4/4；NodeGraphCommandTests 零改全绿（App 675/0/0 内） |
| 5 | SpektraLab 渲染物零入库 | ✅ 证据目录仅本仓走查截图 + MANIFEST；golden 零图像资产 |
| 6 | 登记闭环 + 封存面零命中 | ✅ BUNDLE-MAP 四行 + Project.swift 三方对表；§8 机检全净 |
| 7 | **SC 门**：全套终轮 0 fail/0 MEMFAIL；终值两式互证 | ✅ **TOTAL 3152/16/0**（1482s，exit 0，MEMFAIL 零，L055 双保险 = 脚本 verdict ok）= 基线 3125 + 登记 27（12+5+6+4，BUNDLE-MAP 四行 func test 实数）两式互证 |

## 三、全套终验数字（vs 基线 3125/16/0）

| bundle | 本轮 | 基线 | Δ |
|---|---|---|---|
| IOP | 483/1/0（7365MB） | 483/1/0 | 0 |
| IOPParity | 404/3/0（5999MB） | 392/3/0 | +12 golden |
| Layers | 371/3/0（1153MB） | 366/3/0 | +5 determinism |
| Library | 598/4/0（608MB） | 598/4/0 | 0 |
| Sessions | 279/4/0（1658MB） | 279/4/0 | 0 |
| Export | 342/1/0（6599MB） | 342/1/0 | 0 |
| App | 675/0/0（2831MB） | 665/0/0 | +6 panel +4 card |
| **TOTAL** | **3152/16/0** | 3125/16/0 | **+27** |

峰值 RSS 全 bundle < 8G 门（max IOP 7365MB），MEMFAIL 零。

## 四、golden 两级门证据（E5 兑现）

- **门 1a**：实测 8.7e-5（收集后单断言取真 max）、钉 1e-4——rtne 外推 ±0.5 格
  放大 f32 坐标噪声的机理登记（DECISIONS §1）；真实缺陷 ≥1e-2，门语义完好。
- **门 1b**：凸性门（≤1.5× 单元值域，400 探针零违例——最强语义）+ flat-cell
  线性带实测 6.2e-3（先例带中值）钉 2e-2。
- **门 2**：体素 ≤1e-5（Float64 双侧）；**门 3**：m=1 双侧闭式精确（含阴影符号
  修正回归）+ 单侧臂渐近线；**门 4**：中性闭合 1.4e-3 钉 2e-3。
- 比较空间纪律（L048）：全 linear 域比较 + f32 常数 `Double(Float(x))` 升维。

## 五、确定性门证据

键折叠序独立 FNV 精确值相等（小端序）+ 四向翻转；solve 双调 bit-identical；
跨 ROI：A/B 窗一条目 + 三渲重叠列逐字节相等（**stats 项 = 原始计数、解值比例
不变**双面登记 DECISIONS §2）；整数秩手算；哨兵 hash 常量 + 重钉流程入册。

## 六、偏差与发现（全部处置，细目 = DECISIONS）

1. **m=1 阴影闭式符号缺陷（生产修复 `9f4a649`）**：golden 渐近线扫逮住；零波及
   （默认面 + 既有测试面不变）；回归钉死。
2. **m≥2 落地方程根深离 t（登记不修）**：K_h 可低于 K_s；零用户可见面；M3-4
   descriptor 臂换锚消解；golden 单侧臂契约适配。
3. **节点画布合成点击 click-dead（登记不修）**：Film 页实机走查受阻——卡片渲染/
   AX 正常、grade 卡选择同样无响应 = 画布级合成事件问题（非本批引入，M2-4 面）；
   挂 M3-4 走查清单（人工复核）。
4. **rtne 外推 + 反演平台面**：golden 门的三重平滑域筛选结构（DECISIONS §1/§4）。
5. **声明外扩面四件**（结构必经，如实申报）：PipeCoordinator 只读三面 /
   InspectorView 分支 / EditorToolRailView 传参 / FilmTailPolicy.invalidateAll。
6. **App 全量首轮 crash**：Film 卡 @Environment(InspectorState) 在裸宿主 fatal →
   注入式 optional 修复（教训：视图新增 environment 依赖先查裸宿主测试面）。

## 七、M3-3 phase 小结（验收锚状态表，M3-4 VALIDATION 翻账输入）

| M3-3 验收锚（ROADMAP 行） | 状态 | 正本 |
|---|---|---|
| FSIM-01a 阶段承载（FilmRecord + sub-run + 置位 op + UI 面） | ✅ 三波全交付 | 01/02/03 SUMMARY |
| FSIM-01b 配光自动求解（bake 中性包 + 运行期归一 + Y/M 手动恒在） | ✅ + 确定性门 suite | 01 §5 + 02 §2 + 03 T2 |
| FSIM-01c 染料近似域基线（golden 数学复算主门 + 光谱不可达注记） | ✅ 四门 + AGENTS 注记节 | 03 T1 + AGENTS「M3-3 架构增量」 |
| FSIM-01d 资产三态（c 混合五件套 + 许可面） | ✅（01 交付，03 复核引用） | 01 §2 + NOTICE |
| SC 门（全套终轮 0 fail/0 MEMFAIL + 对账链） | ✅ 3152/16/0 | 本 SUMMARY §三 |
| FSIM-02 宽容度面板 + descriptor + M3 VALIDATION | ▶ M3-4 | ROADMAP 行 |

对账链：3024（M3-1 终）→ 3081/3085（01 波推算/02 实测，验收勘误在案）→
**3125**（02 全套实测）→ **3152**（本批终轮实测）= 3125 + 27 逐 bundle 对表。

## 八、M3-4 交接（FSIM-02 宽容度面板 + M3 VALIDATION）

1. **宽容度面板**：descriptor 运行时（中性 ramp 过管线测 P99.9/P0.1——
   FilmStatsSeam + ScopeReduce 已备）+ filmPlacement 简化臂换精确锚（§6-2 的
   m≥2 根缺陷随换锚消解）+ 置位参数编辑面（filmPlacement 现为可加不可编占位）。
2. **Film 页实机走查补课**：节点画布 click-dead 待人工/真实设备复核（§6）；面板
   事务面已机检。
3. **拖尾小件**：FilmRecord.PresetNames 预设注册面（现悬置）；grid-only 图的
   disk sidecar filmRecord 消费面（02 DECISIONS §7-5 移交，导出 UI 归属）。
4. **M3 VALIDATION**：REQUIREMENTS FSIM-01a..d + M2GRADE/YIYIN 状态翻账统一在
   M3-4 签核批（本批只留 §七状态表）；挂账清单以 M3-1 VALIDATION 单一清单为底册。

## 九、密封面机检对表

`git diff 2fee806..HEAD`：DrtPanelModel/DrtPanelView/DrtRecord/
Lut3dKernels.metal/DrtEotf/ExportQueueContract/ExportFormatSpec/
ImageIOEncoders/WebPEncoder/NodeGraphCommand/LightamerSidecar/HistoryStack/
HistoryHash/PixelPipe/PipelineDocument（Core）/V50Order/GradeCatalog/Registry/
ModuleInstance **零 diff**；FilmTailPolicy 增量 = invalidateAll 一法（DECISIONS
§7.4）；产线触面 = FilmPlacementModule（符号修正）+ App 面板/卡五文件 +
PipeCoordinator 三面 + InspectorState/InspectorView + xcstrings。
