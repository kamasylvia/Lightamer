# spektra-module P1 执行 SUMMARY（2026-11-04，omp execute lane）

> 执行正本 = `PLAN.md` v4（52KB，PASS / 0 blocking + 0 major + 3 minor）。
> 设计背景 = `RESEARCH.md`；用户裁决 = `DECISIONS.md`（D-SM-0 五条生命线全量）。
> 基线 HEAD = `91ae73fd`（亲核：PLAN v4 + 四轮评审全账）；执行批 = 7 commits。

## 逐 T' 战果

| T | commit | 内容 | 测试 |
|---|---|---|---|
| T1' | `efb860c9` | V50Order 46.7（dt-verbatim backfill）+ GradeCatalog 第 21 行 + 恒注册 + `isFilmModuleRequested` 纯门 + templateInstance case | RegistryFilmModuleTests 5（APP）+ V50 +1 + GradeCatalog +1；add-face 14→15 |
| T2' | `fd51fd7b` | module 本体七步（材料缝→ACEScc→自持面→直方图→工厂→box 转发→ACEScc）+ FilmMaterialSeam + FilmLegFactory + D-SM-1 戳记 + pristine 早恒等 | SpektraFilmTests 15（LAYERS）；T2'-0 基线 Layers 540/5/0 803MB；md5 双臂钉死 |
| T3' | `aeaa2bd5` | 在场谓词单源 + 基链拒收 + merge 预检 toast + mergeDown refuse（⑯）+ legacy 谓词 + sync 门控 + version 钩子 | WorkspaceLegacyTests 9（APP）+ History +2 + Sidecar +3 + LayerCore +1；toast 键 1 |
| T4' | `d91a93c1` | 双轨门 + tags 纯函数 + seam 安装 + convert case/门 + process 三源 + 通用行/sheet + convert runner（快照+合成+清+落盘）+ env 接线 | PipeCoordinatorLegacyTests 8 + Gate +2 + Registry +2；convert 键族 4；PixelPipe 注释 |
| T5' | `5f53846c` | tile 政策钉死（doc + 三重否决 + 全帧锚 + 确定性重钉 + 源码冻结） | SpektraTilePolicyTests 4（LAYERS） |
| T6' | `fbdfbfa4` | 导出 per-target + 四 strip + QL 独立装配 + 面板换锚 + 卡退役（−4）+ MCP 拒绝 + 预设/transfer/paste 三修 | +28/−4（Export +4/Panel +5/Preset +2/Strip 4/MCP 3/QL 2/面内 8）；preset_error 键 1 |
| T7' | `6c602a81` | 双宿主 ε 带桥接（8e-3）+ 双形态参数化 + golden 冻结 | SpektraBridgeTests 12（LAYERS）+ Leg +2 + Coordinator +2；.bin/.png 零触 |

## ΔN 实数对账（分项）

| T | PLAN | 实数 | 说明 |
|---|---|---|---|
| T1' | 7 | 7 | Registry 5 + V50 1 + GradeCatalog 1（add-face 期望改不增法） |
| T2' | 15 | 15 | SpektraFilmTests 15（LAYERS） |
| T3' | 14 | 14 | Workspace 9 + History 2 + Sidecar 3 + LayerCore 1（⑯ refuse） |
| T4' | 15 | 15 | Coordinator 8（含备份 2）+ Gate 2 + Registry 2（5→7）+ 面内 3 |
| T5' | 4 | 4 | TilePolicy 4 |
| T6' | 28 | 28 | Export 4 + Panel 5 + Preset 2 + Strip 4 + MCP 3 + QL 2 + 面内 8 |
| T7' | 18 | 18 | Bridge 12 + Leg 2 + Coordinator 2 + Export 2（面内复核） |
| T8' | 0 | 0 | — |
| 退役 | −4 | −4 | FilmCardTests（OQ-5(a)） |
| 合计 | 净增 97 | **净增 97**（101 − 4） | 与 PLAN §0.2 逐位一致 |

## 定向域终值

- App：RegistryFilmModule 7/0/0 · GradeCatalog 16/0/0 · CatalogAddFace 9/0/0 · WorkspaceLegacy 9/0/0 · PipeCoordinatorLegacy 8/0/0 · ProcessMigrationGate 6/0/0 · FilmPanel 11/0/0 · McpFilm 3/0/0 · FilmCoordinator 8/0/0
- IOP：V50Order 18/0/0 · DefaultFace 8/0/0（全 bundle 轮 790+ 法零红后卡 100MP 重测超时——环境面非回归）
- LAYERS：SpektraFilm 15/1/0（1 skip = RSS 探针默认 skip）· Bridge 12/0/0 · TilePolicy 4/0/0 · FilmLeg 11/0/0 · FilmDeterminism 5/0/0 · History 10/0/0 · LayerCore 12+5/0/0
- LIB：FilmSidecar 9/0/0 · PresetsStore 14/0/0 · PresetApplier 8/0/0
- EXPORT：ExportFilmChain 8/0/0 · QuickLookFilm 2/0/0
- SESS：ThumbnailStrip 4/0/0
- 全套 `--all`：未跑（orchestrator 批准制）——申请全套批准轮。

## 封存面终声明（逐 hunk）

| 封存件 | 终态 | hunk |
|---|---|---|
| V50Order | 实质 1 行 | `("spektraFilm", 46.7)` + dt-verbatim 注释（add-only） |
| GradeCatalog | 实质 1 行 + 注释 | 第 21 行（owner .grade + identityJSON + exposures）+ 头注/gradeItems 注 |
| LayerStack.mergeDown | 实质 1 hunk（⑯） | into-base refuse guard（restore + nil）+ D-03 字面注；枚举零改 |
| PixelPipe | 注释例外 | runTerminalTails legacy 回放臂标注 4 行；逻辑零改 |
| ExportQueueContract / sidecar / HistoryStack / HistoryHash / DRT 四件 / Lut3dKernels / 六格式矩阵 / NodeGraphCommand / PipelineDocument / FilmTailPolicy / FilmPrintBake / FilmMaterialStore / LayerCompositeDriver / SessionThumbnailRenderer / filmPlacement | 零 diff | grep 机检全空 |
| Core Presets（r4-m1） | 非封存两小 hunk | PresetError.layerOnlyOpPresent + makePayload 防御过滤（结论句补记） |

## 机制实报（二选一/留白）

- T2'-1 pristine 门：module 侧 `isFilmRecordDefault` 提前恒等（seam 保持纯 holder）。
- D-SM-15③ QL tags：TaskLocal 直装臂（appex 不能 import App 纯函数）。
- r4-m2 async 装配：actor-owned once-flag（`QLAssembly.shared.ensure`，两腿首用调；static let 内零等待）。
- AC-T6'-13：Registry 断言 + Core `QuickLookFilmResources`（Bundle 形参）+ T8'-3 走查兜底（本批走查未执行，见偏差）。

## 偏差申报

1. **T8'-3 GUI 走查未执行**：本 lane 无 GUI 运行时（computer-use 不可用）；迁移行/sheet/备份/换锚/toast/蒙版/grid/QL 八目视项移交 orchestrator 走查轮。AC-T8'-2 的 grep 面已绿（退役面零命中、封存 == 终表）。
2. **RegistryFilmModuleTests 落 APP 非 IOP**：IopCatalog 在 App 面，IOP 域不可达；PLAN 落域行按实修正（T8' 对账列）。
3. **全套 `--all` 未跑**：批准制——定向域全绿，申请批准轮。
4. **键预算 +1**：`preset_error_layer_only`（PresetError 穷举 switch 需消息臂；PLAN 键预算 5→实数 6）。
5. **App 全 bundle 轮中断**：AIMask 族既有 crash（基线复现）+ AIWorker hang（基线复现）——非本批回归；定向类全绿。
6. **IOP 全 bundle 轮中断**：TilingOverlap 100MP 重测超时（907s 贴线先例）——定向类全绿；基线侧 95/98 suite 零红。

## 环境门终态

- `LIGHTAMER_FILM_MODULE` 默认 off 全程贯穿；注册恒开；已迁移档 env-off 照常渲染（AC-T4'-6 机检）。
- process 恒 3（`current.rawValue == 3`，case 未增）；sidecar v13（零 bump 零新键）；UserDefaults 零新键。
- G4 透明越门：20.8GB < 25GB（M9 既定先例，本 SUMMARY 登记）；G1 实质 PASS（仅自身命令行误匹配）；G2 70% PASS。
