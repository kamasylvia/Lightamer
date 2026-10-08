# M3-3-02-SUMMARY — FSIM 管线批（wave 2）

> 执行：2026-10-08/09 夜间（executor subagent，夜间全自动授权「开跑，不要停」
> 在案）。基线：`d68ebf8`（全套推算 3081/16/0；本批首个全套轮实测校正为
> **实际基线 3085**，见 §四）。产出 commits（执行序 = m9 修正式 T 序）：
> T1+T3 `feat(core): film sub-run seam with demoted display tail replay` →
> T4 `feat(iop): filmPlacement masked grade op with catalog row` → T2
> `feat(core): print bake and fused film kernel with solve cache` → T5
> `feat(app): film record persistence legs and material store wiring` → T6
> `feat(export): job film tail task-local seam for export chain` → T7 本批。
> **未 push**（纪律）。断点条款未触发（T1+T2 未超支 ~2×，T6 留在批内）。

## 一、交付面（对表 plan front-matter files_modified）

| 文件 | 变更 | commit |
|---|---|---|
| `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift` | 新建：FilmTailParams/FilmTailPolicy + FilmTailAssembly（seed = fnv(recordHash ⊕ tag ⊕ solvedPackHash ⊕ upstream)）+ FilmMethodBox（T1 blit 恒等载体 → T2 fused kernel 双态）+ FilmGPUPayloads + FilmStatsSeam + FilmSolveCache + FilmRuntimeSolve | T1/T2 |
| `LightamerCore/Sources/Pipe/Film/FilmSubRunKernels.metal` | 新建：fused 单 pass（查表→base→滤色→LUT 四面体→log 域强度混） | T2 |
| `LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift` | 新建：65³ Float64 concurrentPerform + LRU 16 + K 标定 + session 系统反演 | T2 |
| `LightamerCore/Sources/Pipe/PixelPipe.swift` | filmTail/isFilmTailLeg 属性 + runTerminalTails 共享序（run/runSub 两调用点）+ 3×2 降出矩阵 + runFilmLeg（统计腿+求解+GPU 载体装配）+ runFilmDisplayReplayLeg + RenderPipeline/Driver additive 传参 | T1/T2/T3 |
| `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift` | composite filmTail additive 默认参 + terminal leg 贯通 | T3 |
| `LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift` + `FilmPlacementKernels.metal` | 新建：RFC-023 置位曲线（恒等核 + 双侧 smooth-min 压缩支，delta 形 bit-exact；CPU 膝点解算） | T4 |
| `LightamerCore/Sources/Foundation/V50Order.swift` | LIGHTAMER 原生行 ("filmPlacement", 20.8)（add-only；acesccIn 20.5 与 exposure 21.0 之间）+ 头注释计数更新 | T4 |
| `LightamerIOP/Sources/NodeOwnershipCatalog.swift` | GradeCatalog 第 19 行（filmPlacement, .grade, identityJSON = 恒等点）+ 头注释 | T4 |
| `LightamerIOP/Sources/Registry.swift` | filmPlacement 注册（默认面，seed 缺席）+ prewarm + FilmStatsSeam 装配 | T4/T2 |
| `App/Sources/Lightamer/State/PipeCoordinator.swift` | FilmRecord 四件套（carrier 写读/写腿/恢复腿/filmTailPolicy）+ store 座位 + undo/redo/jump 同步补线 + makeSidecarDocument 成对写入 | T5 |
| `App/Sources/Lightamer/State/EditorState.swift` | recordFilmChange/notifyFilmChange + templateInstance 第 19 case | T5/T4 |
| `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift` | filmRecords carrier + closeEditor drop | T5 |
| `App/Sources/Lightamer/UI/LightamerApp.swift` | FilmMaterialStore 装配 + 坏目录 typed 降级 + toast | T5 |
| `Resources/Localizable.xcstrings` | `toast_film_store_unavailable` 键（append 式） | T5 |
| `LightamerCore/Sources/Export/ExportRenderer.swift` | `$jobFilmTail` TaskLocal + Request.filmTail + consult + 两 pipe 调用点传参 | T6 |
| `LightamerCore/Sources/Export/ExportQueue.swift` | **E1 三编辑点**（Job.filmTail :60 旁 / enqueue filmTails: + precondition / 腿内 withValue 嵌套） | T6 |
| `App/Sources/Lightamer/State/ExportState.swift` | enqueueExportM2 filmTails per-image 参数（typed 计数门） | T6 |
| `App/Sources/Lightamer/Export/ExportInspectorView.swift` | RunAssembly.filmTails（loaded 图 carrier 经 coordinator policy） | T6 |
| `Tests/LightamerTests/FilmLegTests.swift` | 新建（LAYERS）9 法 = 矩阵六格 + seed 折叠 + 防重入 + FULL smoke + resolved-materials fused kernel smoke | T1/T2 |
| `Tests/LightamerTests/FilmPlacementTests.swift` | 新建（IOP）7 法 | T4 |
| `Tests/LightamerTests/FilmPlacementKernelTests.swift` | 新建（IOPP）3 法（恒等 bit-exact/GPU-vs-Float64/m 阶接触） | T4 |
| `Tests/LightamerTests/FilmPlacementDriverTests.swift` | 新建（LAYERS）3 法（envelope 包夹/蒙版合法+恒等复合/几何禁面不受扰） | T4 |
| `Tests/LightamerTests/FilmPrintBakeTests.swift` | 新建（LAYERS）7 法（确定性/域标定/中灰回环/LRU/整数秩/键判别/手动叠加） | T2 |
| `Tests/LightamerTests/FilmCoordinatorTests.swift` | 新建（APP）5 法 | T5 |
| `Tests/LightamerTests/ExportFilmChainTests.swift` | 新建（EXPORT）4 法（detached 腿交付证明/per-image fan-out/零漂移/计数门） | T6 |
| `Tests/LightamerTests/GradeCatalogTests.swift` `V50OrderTests.swift` `CatalogAddFaceTests.swift` | m8 计数闭合修订（18/14/17→19/15/18；105→106；add-face 12→13）+ filmPlacement pins | T4 |
| `Project.swift` / `M2-4-0-BUNDLE-MAP.txt` | 测试登记（L041 批尾 generate；BUNDLE-MAP 增行 + 方法数终态） | 随各任务 |

## 二、AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | film sub-run 缝位 + 3×2 矩阵 + film 未激活逐位 | ✅ 六格逐格断言（off 三格 = 既有族全绿 + nil byte 门；on 三格 = FilmLegTests）；`DrtTailAssembly.seed(upstream:)` 签名零改（数源替换亲核）；DRT+film 叠序经 cache locality 证明 |
| 2 | 运行期腿确定性 | ✅ 整数秩 ramp 钉死；键判别三分量；同图跨 ROI 同解的结构性兑现（tag 无 ROI 项 + box 恒不 tile）；手动叠加测试钉死 |
| 3 | 印相段 bake | ✅ 双 bake bit-identical；65³ Float64 concurrentPerform + LRU 16 + LutEncodingCatalog 零 diff；域标定 per-channel pin；中灰回环 0.184 |
| 4 | filmPlacement | ✅ 恒等 bit-exact（byte 门）；可蒙版（masked composite 渲染绿）；V50 20.8 add-only（测试 pin）；E7 19 行闭合（18 unique ops 全 resolve）；envelope 包夹断言 |
| 5 | 持久化四件 App 半面 | ✅ 缺键 pristine / 恢复腿三态（真写路径含 switch-back skip）/ thumbnail 恒 nil / 坏目录 typed throw / undo 同步 |
| 6 | 导出递缝 | ✅ Contract 零 diff（机检空）；detached 腿交付证明（injected leg 捕获 TaskLocal）；per-image fan-out；无 film 零漂移；计数 typed 门 |
| 7 | 登记闭环 + 封存面零命中 | ✅ 三方对表（Project.swift = BUNDLE-MAP = 文件实况）；§八机检全净 |

## 三、测试数字（vs 实际基线 3085/16/0）

- **定向实跑**（`Scripts/test-direct.sh` + `caffeinate -dis`，全部七 bundle
  本批均实跑）：
  - Layers **366/3/0**（基线 346 + 23：FilmLegTests 9 + FilmPlacementDriver 3
    + FilmPrintBake 7 + V50OrderTests +1 + …）
  - IOP **483/1/0**（+ FilmPlacementTests 7 等）
  - IOPParity **392/3/0**（+ FilmPlacementKernelTests 3）
  - App **665/0/0**（+ FilmCoordinatorTests 5 + CatalogAddFace/GradeCatalog
    修订面）
  - Export **342/1/0**（+ ExportFilmChainTests 4）
  - Library **598/4/0** / Sessions **279/4/0**（既有族回归，零改全绿）
- **全套实测 = 3125/16/0**（七 bundle 逐值求和）= 实际基线 3085 + 本批 +40。
  基线校正：M3-3-01 obs-2 的 3081 系推算值，与实差 +4（该批推算时点后的
  method 增量未计入）——**本轮为首个全套实测轮，3085/16/0 成为新账面基线**。
- func test 计数对账：+40（9+7+3+4+7+5+4+1）逐位一致。

## 四、「FSIM-03 不立项」注记（plan 头裁定的登记即止）

印相域蒙版（film sub-run 内 mask plane）本批零实现零挂账——D-M3-2-6 注记即
止；印相域蒙版需求出现前不扩（M4+ 候选）。本批交付的 film sub-run 结构不
预置 mask plane 挂点（fused kernel 单 pass 的语义面无蒙版输入槽）。

## 五、光谱不可达边界（承 01/02 架构注记，交付语义）

本批 kernel/CPU 参考全部在 RGB 密度域（256×3 status M/A 打印密度 +
三点投影 base 常数 + 滤色标量）；81 波长光谱重放零消费。用户可见措辞 =
「物理流程建模，非光谱重放」。K 标定与 session 系统反演是密度域自洽闭环
（DECISIONS §3）。

## 六、偏差与发现（全部已处置，无阻塞；细目 = DECISIONS §7）

1. replay filter v50 序修正（首版输入序——测试逮住）。
2. planesRendered 只计主管线（既有 DRT-tail 口径；测试改 misses 断言）。
3. 膝点牛顿切点发散 → 括号守护形。
4. K 标定两连修（pack 后操作点标定 + session 系统反演——测试逮住）。
5. solve cache 分半（AUTO core 缓存 / record 层消费叠加——测试逮住）。
6. undo/redo/jump 导航面补 film carrier sync（测试逮住）。
7. T1+T3 合并为单 commit（相关变更合并纪律；T1 测试消费 T3 签名）。

## 七、密封面机检对表

`git diff d68ebf8..HEAD` 对 ExportQueueContract / DrtEotf / Lut3dKernels /
LightamerSidecar / HistoryStack / HistoryHash / ModuleInstance **零 diff**；
TerminalTailPolicy/DrtTailParams/DrtTailAssembly/`policyTag "lightamer.drt"`
在 PixelPipe diff 内零命中；defaultFaceDisabledOpNames 零命中；V50Order
entry 数组 add-only；六格式导出矩阵零 diff。全净（DECISIONS §8 正本）。

## 八、续接点增量（正本回写 GOAL-STATE）

M3-3-02 七任务闭环 + docs 批 = 本文件；**下一步 = M3-3-03**（golden/
确定性/预设注册面——FilmRecord.PresetNames 填充 + 置位曲线逐像素 golden +
串扰矩阵回填复核 + D-5d sanity 解值随模型重标）。M3-3-03 依赖面全部就位：
fused kernel 在 Core metallib（`film_subrun` 可寻址）、FilmPrintBake CPU
参考双写、filmPlacement CPU 参考与 kernel、solve/bake 确定性门。移交清单：
①golden 体（M3-3-03 主门）②串扰常量与 sanity 解值重标 ③PresetNames 注册
④descriptor 臂（M3-4 FSIM-02）⑤export 的 grid-only 图 filmRecord 消费面
（M3-4 导出 UI）。
