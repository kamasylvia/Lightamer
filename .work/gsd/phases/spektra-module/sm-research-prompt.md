# 光谱核 module 化调研 lane（zcode 只读侦察）

你是 Lightamer 的架构调研员。**全程只读（除最终 RESEARCH.md 外零写入、零 commit、零构建）**。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。中文正文，file:line 引用保持原文。**注意：主仓有一个执行 lane 正在飞（改 Film/ 与 Tests/），你读到的未提交 diff 属它在制品——引用行号时注明「@工作区（在制）」；dt 仓只读。**

## 任务背景（用户令）

用户指示：「dt 把 spektrafilm 做成了一个 module，我们也这样做」——即把我方光谱核（当前以 document 级 FilmRecord + film sub-run 尾段挂载形态存在）改造为与 darktable spektrafilm 同构的 **iop module**（管线内节点、可独立启停/调参/排序）。

## 输入集合

**dt 侧**（/Volumes/UNITEK/Documents/Development/darktable，只读）：
- `src/iop/spektrafilm.c`（模块壳：params 结构/commit process/GUI/自动求解按钮）
- `src/common/spektra_sim.c` + `spektra_core.c`（材料/求解/光谱核）
- `data/kernels/spektrafilm.cl`（OpenCL 腿）
- 注册链：`src/iop/order.ll` 或 iop order 定义处 spektrafilm 的槽位；`src/develop/imageop.h` 的 so/get_flags 模式
- ROI/tiling 处理：`src/iop/*.c` 中 `process_tiling` / roi 系列在 spektrafilm 的用法

**我方侧**（主仓，只读）：
- `LightamerCore/Sources/Film/`（FilmProfile/FilmMaterialStore/PaperGradeTable/SpectralBuildEngine/Spectral* 全部）
- `LightamerCore/Sources/Pipe/`（FilmMethodBox、runTerminalTails、filmTailPolicy、FilmSubRunKernels、PixelPipe.prepareChain）
- `LightamerCore/Sources/Graph/`（DrtRecord、TerminalTailPolicy——film 与 DRT 的尾段共享序）
- `LightamerCore/Sources/Sidecar/`（FilmRecord 字段、schemaVersionCurrent=13、HistoryItem.filmRecord）
- `LightamerIOP/Sources/`（IOPModule 协议、V50Order、GradeCatalog/NodeOwnershipCatalog——module 化的目标形态样本：看 filmPlacement 恒等占位与 Lut3dModule/ColorWheelsModule 两个成熟 module 先例）
- App 侧 `App/Sources/Lightamer/`（FilmPanelModel/FilmPanelView、InspectorView 挂载、NodeCanvasGeometry.filmCardID、ExportQueue filmTail）
- 文档：`.work/gsd/phases/m8-fsim-spectral/`（M8 RESEARCH/SUMMARY/DECISIONS、M8-3、M8-FIX-1）、`.work/gsd/phases/m8-3plus-spectral/`（RESEARCH/SUMMARY/DECISIONS/PLAN）、`.work/gsd/phases/m9-2-bwspectral/`（RESEARCH/PLAN/SUMMARY）、AGENTS.md「M3-3/M8/M9-4 架构增量」节
- 调研正本：`.work/gsd/phases/m3-2-fsim-research/DT-SPEKTRAFILM-IMPORT-RESEARCH.md`（dt 上游动态，含 10 月新机制注记）

## 变换规则（产出 RESEARCH.md 的章节骨架）

1. **dt module 解剖**：spektrafilm 作为 iop 的完整接线——注册（iop order 槽位、flags、默认 off/on）、params 结构与持久化（dt db preset/ctrl）、commit→process 数据流（CPU 腿 + OpenCL 腿分工）、ROI/tiling、GUI 参数族、auto-solve 钩子。全部 file:line。
2. **我方现状解剖**：film sub-run 全链精确映射——FilmRecord(document 级) → carrier/history/sidecar → runTerminalTails 共享序(film→DRT→display replay) → FilmMethodBox.runContext → FilmSolveCache → process v2/v3 语义。全部 file:line。明确「film 当前不是 module」的结构性原因（为何挂在尾段而非 V50Order 槽）。
3. **差距映射表**：dt 形态 vs 我方形态逐维度对照（参数载体/启停语义/排序能力/蒙版交互可能性/预设/导出/MCP）。
4. **module 化设计案**：V50Order 槽位提案（filmPlacement 已有 20.8 占位——分析真挂载 vs 现恒等占位的关系）；参数从 document 级 FilmRecord 迁到 module instance params 的路径；蒙版能力解锁面（module 化后 per-node mask 可用——dt 形态的核心收益）；FilmSolveCache 键控是否变；sidecar schema 影响（v13→v14? 还是 FilmRecord 兼容保留+module params 双轨）；process version 语义（是否 bump v4 或不 bump——film 挂载位置改变但视觉恒等?）；DRT 尾段交互（module 化后 film 从尾段共享序退出，DRT 交接面改动）；导出腿/缩略图恒 legacy/MCP/Film 面板/节点 Film 卡的各自改动面。
5. **迁移与兼容**：既有 .lra（filmRecord 字段）档的迁移策略；filmPlacement 恒等占位的退役或转正；feature flag/回退面。
6. **风险清单**：封存面 17 件中会破哪些（申报例外形态）；双臂 golden 冻结面；性能面（module 化后 ROI/tile 语义 vs 现全图 sub-run）。
7. **Open Questions**（≤6 条，每条带推荐选项）：呈 orchestrator/用户裁决。

## 验收清单

- [ ] dt 侧解剖含注册链事实（槽位/flags/kernel 数）与 CPU/OpenCL 分工，file:line 可核
- [ ] 我方侧解剖含 FilmMethodBox/runTerminalTails/filmTailPolicy/FilmSolveCache 精确 file:line
- [ ] 差距映射表 ≥8 维度
- [ ] 设计案明确回答：sidecar schema 是否动（判定+理由）、process version 是否 bump（判定+理由）、filmPlacement 占位如何处置
- [ ] Open Questions ≤6 带推荐
- [ ] 全程只读零 commit；产出单文件 `.work/gsd/phases/spektra-module/RESEARCH.md`（chunked 写：每段 ≤8KB 追加，防截断）

产出 = stdout 一次性完整输出摘要 + RESEARCH.md 正本。
