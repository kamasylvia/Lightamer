# M9-3 CONTEXT — 几何校正 Upright 系（charter 勘误登记 + OQ-M9-3-1..6 裁决落定批，2026-10-25）

> **裁决正本**：research 期新开 **OQ-M9-3-1..6 全部按 `RESEARCH.md` §6 推荐落定**
> （charter 2026-10-27 夜间授权「M9 直接按推荐自动推进」制度，M7-2..M7-6 /
> M9-1 / M9-2 同款「OQ 全按推荐」auto-advance；**晨审可推翻**——推翻 = 修订
> 本文件对应 D-M9G 条，下游 plan 受影响任务面重开）。读解正本 = 同目录
> `RESEARCH.md`（上游测绘 §2 / 我方盘点 §3〔含勘误〕/ 差距矩阵 §4.1 / 方案
> 骨架 §4.2 / 坐标系 §4.3 / 数值精度 §5 / 风险 R-1..R-5 + OQ §6 / 许可 §7）；
> planner 2026-10-25 HEAD 抽核 **16 点亲核吻合 + 1 处转写勘误**（见 §转写勘误）：
> V50Order 几何段（lens 13.0 → cacorrectrgb 13.5 → ashift 15.0 → flip 16.0 →
> … → crop 24.5，`V50Order.swift:38-76`）/ `defaultFaceDisabledOpNames` 六件
> 不含 ashift（`Registry.swift:39-47`）/ AshiftModule.Params（rotation/
> lensShiftV/H/shear `:86-127` + `pointMapSegment :310` + neutral eps
> `:143-181`）/ `ashift_warp` kernel（`AshiftKernels.metal:79`）/
> `functionName = "ashift_warp"` 字符串常量形态（`AshiftModule.swift:73`）+
> Registry `:517` 「perspective share one kernel」共名先例 / Homography
> `compose :69 / dlt :200 / fitParams :249` / CropModule.Params 四边+ratio
> （`:63-69`）/ FlipOrientation 八位 + `.auto` EXIF 解析（`FlipModule.swift:
> 63-103`）/ CropOverlayView 旋转手柄注记（`:27-28`「Rotation handles
> belong to 04-03 ashift」）/ GeometrySegment `.affine` + `.homography`
> 双段（`GeometryPointMapper.swift:42-52`）/ sidecar v11（`:255`）+
> paramsData base64（`:741-752`）/ `detectionSourceImage()`（`PipeCoordinator
> .swift:2029-2034`）/ LensAutoCrop 消费（`LensModule.swift:297`）/
> EditorTabRoute Geometry 页基础排 + Advanced 组（`:266-278`）/
> `EditorState.recordChange :217` 单实例单 item 形态 / HistoryStack case
> 面（drtRecord/filmRecord document 先例 + 无 undo-group 机制，
> `HistoryStack.swift:144-146/:342-350`）/ R6 收口终值 **4292/35/0**
> （`R6-SUMMARY.md:55` 亲核）。
>
> **规格上游**：ROADMAP §M9 站 3 行（M，ΔN +12..18）+ REQUIREMENTS
> M9GEO-01..02 + `research/M9-CHARTER-INPUT.md` §2.3（**已被 research 勘误，
> 见 §charter 勘误**）。charter 生效值 = lightcraft（MIT OR Apache-2.0）
> upright.rs 可移植带归属 + 零新 SPM + 零模型依赖。
>
> **编排现势（2026-10-25）**：M9-1 / M9-2 plan 已起草、执行 pending；本 phase
> 执行批**排 M9-2 闭环后**（站序串行 + 机器级单重活制）；plan/CONTEXT =
> 零 commit 产物由 orchestrator 收割。全套对账锚 = **R6 收口终值
> `4292/35/0` ⊕ ΔN_M9-1（charter +20..28 / plan v2 +20..29）⊕ ΔN_M9-2
> （plan +15..20）**——本批开工前亲核 GOAL-STATE 与 M9-1/M9-2 SUMMARY 实数
> 落基线，全套带式按执行时序实数落，不写死数。

---

## Charter 勘误登记（晨审可翻——勘误正本 = RESEARCH §3.1，本节为 plan 落位叙事）

1. **charter §2.3「v50 序无对应 iop（旋转/拉直/透视全缺）」不成立**。实况：
   `ashift`（v50 slot 15.0）已注册 + 默认 seed + 默认面启用 +
   Geometry 页 Advanced 组 + ±45° 旋转 + 透视 + `ashift_warp` Metal warp +
   Vision auto-detect 面板（RESEARCH §3.1 表，planner 逐行亲核吻合）。
   **M9GEO-01 的「自由旋转」本体已达**（滑杆 + 持久化 + golden 在案——
   AshiftParityTests）。
2. **修正后的真缺口**（本批正业）= ①crop 工具面旋转/拉直联动（角度手柄 /
   拉直滑杆 / 90° 按钮 / 角度→裁切框重算——upstream `with_angle` 单漏斗 +
   `crop_fit_angle` 闭式无对应物）+ ②Guided Upright 导线系全缺（导线画/选/
   拖/删 + 消失点求解 + K·R·K⁻¹ recentre + overlay）+ ③拉直检测防呆（现单线
   Vision 地平线，无 lightcraft ≥3 线共识实证防线）。REQUIREMENTS
   M9GEO-01 的 charter 措辞「真缺口：Crop 纯裁切框无旋转」按此修正叙事
   读解：**真缺口 = Guided Upright + rotate/crop 联动 UX，非旋转本身**。
3. **方案量级翻转**：从「rotate 基座新建」翻转为「**既有件扩展（ashift/
   crop/flip）+ 导线系新建（upright op + UprightMath + overlay）**」。连带
   勘误两则：charter「M5-3 Pano homography 复用」→ warp 复用锚点改判
   **`ashift_warp`**（形态全同、更近；Pano 只借 Rodrigues/矩阵族纪律）；
   「rotate 新 op」→ **rotate 零新 op**（写 ashift.rotation / flip.
   orientation 既有 params 面）。
4. 勘误不缩站：charter M 档（12-18N）成立，research 复核 14-22N（auto
   模式若入批另计），本 plan 实分解 **+14..19**（见 PLAN ΔN 预算表）。

---

## Phase Goal（M9GEO-01..02 锚定，勘误后语义）

把几何校正补到我方既有 ashift/crop/flip 基座上的两个真缺口：**M9GEO-01
（勘误后）rotate/straighten 的 crop 工具联动**——角度手柄 + 拉直滑杆（写
ashift.rotation）+ 90° 步进按钮（写 flip.orientation 显式位）+ 角度变更时
裁切框联动重算（`cropFitAngle` 最大内接闭式 + #1794「非最大框永不放大 /
最大框随角回 0 复原」语义）+ auto straighten 段检测防呆（lightcraft
detect_segments + levelAngle + ≥3 线共识 + ≤10° 门移植；Vision 地平线
回落）+ Constrain Crop 一键（upright/ashift 后黑边收缩）；**M9GEO-02
Guided Upright**——`UprightMath` Core 纯函数件（VP 特征向量精化 + 正交
估焦 + K·R·K⁻¹ + recentre + solveGuided，f64，lightcraft MIT 移植带 NOTICE）
+ `upright` 新 op（v50 15.5，骑 `ashift_warp` 零新 kernel）+ 导线 overlay
（画/选/拖端点/删 ≤4 条 + 求解 live）。验收形态 = 两条 REQUIREMENTS 行的
机检断言（合成梯形逆解 golden + 单线 level 精确门 + 病态防线负测 + 旋转
联动探针 + 导线交互探针）+ 定向 bundle 全绿 + 全套 ΔN 对账 + gui-acceptance
走查。

---

## 决议（D-M9G-1..6 = research OQ-M9-3-1..6 采纳值，硬约束，执行中不重开）

| D | OQ | 采纳值 | 落地形态（planner 修正处标注） |
|---|---|---|---|
| **D-M9G-1** | OQ-1 旋转×裁切联动 history 粒度 | **单用户动作单语义批（research 推荐①的目标），落地 = ②同批双 item（planner 修正落地形态）** | research 推荐①document 级 item 的实现路径（HistoryItem 新 case + HistoryStack scope + HistoryHash 折入）**必触封存面三件**（HistoryStack/HistoryHash/PipelineDocument——DRT/film 落 document item 时是当时批的正业，今天是零 diff 红线）；且 record 镜像进 document item = 参数双真相（违反 params 唯一真相架构纪律）。落地 = `EditorState`（App 侧，非封存）additive `recordLinkedChanges(_ snapshots: [ModuleInstance], label:)` 原子批 API：两 item 同批连续 commit、零中间渲染、单次 historyDidChange；undo = 两次（LIFO 序 = 先撤框重算再撤角度，中间态一瞬，DECISIONS 登记）。**联动重算单源语义（upstream #742/#1388/#1794 三代 issue 收敛件）**：角度为真相、框为联动派生——仅当现框 == 旧角度的 `cropFitAngle` 输出（或框 == 全图）时自动重算；用户手调过的框**永不自动改**、非最大框**永不放大** | 
| **D-M9G-2** | OQ-2 upright 新 op vs ashift 扩展 | **新 op `upright` v50 15.5**（research 推荐①） | 语义/history/封存面干净（ashift 的 dt GENERIC 模型不动、封存面清单不新增改动点）；与 upstream 合成序一致（upright 消费手动几何后帧，导线画在用户所见帧）；add-only 一行（filmPlacement 20.8 半步先例）。**upright 落 Geometry 页基础排**（非 Advanced——Guided 导线是 framing 主工具，LR/Alcedo 级；ashift 留 Advanced 不动） |
| **D-M9G-3** | OQ-3 auto upright 模式范围 | **P1 Guided only**（research 推荐） | `Params.mode` 枚举恰两 case `off/guided`（未来 auto 族 = 加 case 编译期扩点，DrtMethod 先例）；**不移植** detect_segments 的 RANSAC/reliable 全防线族 + analyze_source 缓存 + upright_transform 持久化（届时才是 schema 触碰点）——挂 `research/UPSTREAM-QUEUE.md` |
| **D-M9G-4** | OQ-4 auto straighten 检测路线 | **lightcraft 段检测 + ≥3 线共识移植**（research 推荐①），Vision 地平线回落保留 | detect_segments + level_angle + STRAIGHTEN 常量（MAX_DEGREES=10.0 / MIN_LINES=3，68+300 张标定值）Swift CPU 移植（~150 行级，MIT 归属）；既有 AshiftPanelView 的 Vision Auto Level 按钮零动（回落位）；检测源 = `detectionSourceImage()`（decoded 裸探针，现成）起步，lens 校正后探针（followEdgesSurface 截断栈形）为质量升级选项——T3 一次对比实测，DECISIONS 申报选型 |
| **D-M9G-5** | OQ-5 导线拖动 live 形态 | **live 重渲每 tick（debounce）**（research 推荐①），探针先行 | 导线解 = 闭式 μs 级 + preview bucket 一 warp——hitch 门（>50ms=0）内；T4 首动作 = 预算探针（LIGHTAMER_PERF_PROBE + L014 fence）；实测越门 → 回落②crop-T0 disabled+scrim 形（保底预案在案，DECISIONS 申报）。同理 T3 旋转手柄拖动 = ashift live tick（直显旋转用 live 而非 disable） |
| **D-M9G-6** | OQ-6 90° 按钮与 EXIF orientation | **显式位覆盖 `.auto` 后持久**（upstream 同款；plan 内核即可） | CW/CCW 按钮 → `flip.orientation` 显式位（`.rotCW90`/`.rotCCW90` 等位集语义）；`.auto` 解析点唯一性已在案（`FlipModule.swift:98-103` `resolved(forEXIF:)`——non-auto 直通）；换图不迁移（per-photo params 语义自然）；**符号约定探针钉死**：90° 按钮 ⇄ 位集映射 + viewport 旋转方向，AX/探针断言（golden 4 号门同族） |

> 附带裁定（planner 补，晨审可推翻）：**upright 不入 MCP `IopCatalog`**——
> IopCatalog 是 19 tone/color grading ops 的 apply_params 键参考白名单，
> geometry 族（crop/flip/ashift/lens/liquify）deliberately NOT cataloged
> （`IopCatalog.swift` 头注亲核，见 §转写勘误①）；upright 循此惯例零
> IopCatalog 触碰（apply_params 全 JSON replace 仍可用——catalog 是参考
> 非白名单）。

## 复用件清单（file:line，planner 亲核吻合）

| 件 | 位置 | 本批用法 |
|---|---|---|
| `ashift_warp` kernel | `LightamerIOP/Sources/Ashift/AshiftKernels.metal:79`（通用 3×3 后向 warp：uniforms 三行 float4 + 像素中心 + clamp-edge + 域外透明） | upright process **骑现成 kernel**：`UprightModule.functionName = "ashift_warp"`（字符串常量，`AshiftModule.swift:73` 同形）+ Registry PSO 清单共名 dedupe（`:517`「perspective share one kernel」先例）→ **AshiftKernels.metal 零 diff、零 wrapper、零新 kernel 数学** |
| AshiftModule 形 | `AshiftModule.swift`（Params :86-127 / commit+neutral :162-181 / pointMapSegment :310 / process :340+ / ROI 协商） | upright op 的结构模板（params 持久化 + neutral→blit identity + 前向角点 AABB / 逆向后向 + 2px 边距） |
| Homography 件 | `Homography.swift`（compose :69 / dlt :200 / fitParams :249） | 零触（4 点 DLT 语义不同 = Auto Detect 用，Guided 走特征向量法） |
| Mat3D + Rodrigues 族 | `LightamerCore/Sources/Stack/PanoCamera.swift`（rotation/axisAngle 同族） | UprightMath 的矩阵原语（复用 Mat3D，Double） |
| GeometryPointMapper | `GeometryPointMapper.swift:42-52`（`.affine` / `.homography(forward:inverse:clip:)` 段；ashift 供段先例） | 导线视口坐标 ⇄ upright 输入帧坐标逆映射通道（upright `pointMapSegment` 供 `.homography` 段，mapper 本体零 diff——勿开第二映射点） |
| `detectionSourceImage()` | `PipeCoordinator.swift:2029-2034`（decoded 只读探针，L014-clean） | T3 段检测源（D-M9G-4） |
| CropOverlayView 形 | `App/.../UI/Overlay/CropOverlayView.swift`（16 态命中位集 + D-H1 三段 + 归一⇄视口换算；:27-28 旋转手柄 linkage 注记） | 角度手柄/导线 overlay 的直系模板；:27-28 注记本批兑现后改写 |
| MaskOverlayHost / 工具栏族 | `App/.../UI/Overlay/` | 导线工具槽位（mask 工具栏族形态） |
| LensAutoCrop 形 | `LensModule.swift:297`（最小内接 scale 闭式消费） | Constrain Crop 一键的同族先例（upright 后黑边收缩；upstream 数值版 48×4 边采样对照） |
| params 持久化 | `LightamerSidecar.swift:741-752`（per-instance paramsData base64）+ StableHash（D-H4/L013） | upright.Params（mode + guides ≤4×4 Double）走既有 ModuleInstance 编码——**零 schema 触碰**（M2-1 colormatch「Params 直存」先例） |
| V50Order | `V50Order.swift:38-76` | 15.5 add-only 一行（ashift 15.0 后 flip 16.0 前；filmPlacement 20.8 半步先例） |
| flip orientation | `FlipModule.swift:63-103`（八位 + `.auto` EXIF 解析 + swapsXY） | 90° 步进的既有能力面（零新 op） |
| EditorState.commit 面 | `EditorState.swift:217`（recordChange 单实例单 item）+ HistoryStack（:144-146 document 先例 / :342-350 单步 undo、无组机制） | D-M9G-1 的 `recordLinkedChanges` additive 批 API 落点（EditorState 非封存面） |

## 转写勘误（RESEARCH → 本批 planner 亲核批，执行以勘误为准）

1. **IopCatalog 表述偏差**：RESEARCH §3.6「MCP IopCatalog：crop/flip/ashift/
   lens/liquify 已列 payload/geometry 组（IopCatalog.swift:22）」——` :22`
   附近是 `enum IopCatalog` 声明 + 头注；实况 = **geometry 族 deliberately
   NOT cataloged**（头注明文「the catalog is the key REFERENCE, not a
   whitelist」）。对本批影响 = upright **零 IopCatalog 触碰**（D-M9G-2
   附带裁定），MCP 面零增量。
2. 其余抽核 16 点全部吻合（见头部清单）；引用以本文件头部亲核行号为准。

## 红线（plan 正本引用，执行批违者即错）

1. **封存面 17 件零 diff**（M7-6 全集口径：15 项速查 + IOP Registry +
   ModuleInstance），**唯二 additive 例外** = ①V50Order 15.5 一行（add-only
   纪律：不重排不改现行序，filmPlacement 20.8 先例）②Registry upright
   注册行族（默认 seed + kernel 清单共名行；**`defaultFaceDisabledOpNames`
   不触**——upright 默认面启用）。其余 15 件（DrtRecord/TerminalTailPolicy/
   DrtTailAssembly/PixelPipe/Lut3dKernels.metal/DrtEotf/ExportQueueContract/
   六格式导出矩阵/NodeGraphCommand/LightamerSidecar/HistoryStack/HistoryHash/
   PipelineDocument/GradeCatalog/ModuleInstance）**严格零 diff**——这正是
   OQ-1 裁②不裁①的结构面原因。AshiftKernels.metal = 零 diff（upright 共名
   骑 `ashift_warp`，零 wrapper；若执行中发现 pipeline 结构性需要 wrapper →
   逐 hunk 申报豁免 + 停手上报）。
2. **零 schema 触碰**：schemaVersionCurrent 不 bump（M9-2 已预定 v12，本批
   在其后执行时 v12 已在位——本批仍零触碰；LightamerSidecar 零 diff）；
   sidecar v-next 若被上游批占用与本批无争。
3. **ashift/flip/crop 既有 params 语义零改**：upright 联动写 ashift.rotation
   与 flip.orientation 既有字段，不改其 params 编码/neutral 语义/面板现役面
   （AshiftPanelView 仅 additive 挂点，现役滑杆/按钮零 diff）。
4. **MIT 归属（不可延后件）**：`UprightMath.swift` + `StraightenDetect.swift`
   文件头 = lightcraft 上游版权声明 + 「数学移植自 lightcraft（MIT OR
   Apache-2.0），实现独立 Swift 重写」注记 + 上游 commit 锚（fbc927f0 /
   7635b38c / 693c3593 / 54c6c43b / 7d3cd8af）；根 `NOTICE` 新增 lightcraft
   条目（ALCE-03 先例：当时移植臂降兜底封存零 NOTICE——本批移植臂**真落地
   入产线**，NOTICE 义务成立）；零归属入库 = 流程违规。
5. **数学域纪律**：UprightMath/StraightenDetect 全 Double（upstream f64
   对齐）；kernel 采样 float32（L006）；比较空间纪律 L048（golden 对照先
   decode 回线性域再比，产线常数 `Double(Float(x))` 升维——M3-3 同款）。
6. **坐标系统红线（RESEARCH §4.3 采纳）**：导线坐标 = upright op 输入帧
   归一 0..1（lens 后 + flip 后 + ashift 手动几何后）；视口 ⇄ 该帧唯一通道 =
   GeometryPointMapper（勿开第二映射点）；upright 解 H 在居中归一域，入
   kernel 前 ×平面像素缩放（ashift compose 同位换算，Double）；y 方向符号
   = 探针钉死 + 精确断言（golden 4 号门）。
7. **通用族**：xcstrings 尾块纯插入 + `zh-audit --check`/`--self-test` 双
   PASS + 动态键禁形（V14/L058——`String.LocalizationValue("prefix_\(x)")`
   禁；动态键显式 switch 返回静态键）/ UserDefaults **零新键**（无跨会话
   记忆面；出现需求 → 停手申报）/ 新测试落域（M2-4-0 E2）+ Project.swift
   显式数组 + BUNDLE-MAP 登记行 + `tuist generate` 恒末位（L041）/ 机器级
   单重活（`Scripts/machine-guard.sh` 前置；排程避让 M9-2 在飞轮）+
   `--all` orchestrator 预批 + 8G 门 + MEMFAIL 机检 + GUI 实例测试起跑前
   ps 清零验证 / commit-per-task（Conventional Commits 全英文，前缀
   `feat(m93)/fix(m93)/test(m93)/docs(m93)`）/ D-H1 三段（live 值不进
   discrete commit）/ disable-not-unmount / AX id 顺路浮出 / parentage
   纪律（M2-7-3）/ 测试宿主清理先核 `ps -o ppid`。

## 风险登记（R-1..R-5，消解绑定到 plan 任务）

| 风险 | 机理 | 消解绑定 |
|---|---|---|
| **R-1 旋转×裁切联动 UX（最高）** | upstream `with_angle` 收敛三代 issue（#742 各入口同框 / #1388 最大框随角复原 / #1794 非最大框永不放大）；我方 crop 存 ashift-AABB 帧分数（与 upstream 旋转帧归一不同构），联动缝跨两 instance | Plan T3：`recordLinkedChanges` 原子批（D-M9G-1）+ 联动重算单源谓词（框 == 旧角 cropFitAngle 输出或全图才自动重算；手调框永不自动改）+ 解析例 golden（3:2 @10° 闭式对照）+ 手调框保护负测 |
| R-2 符号/坐标系三重奏 | crop angle（CW+）vs ashift.rotation（dt 约定）vs upright 居中域（y 上/下）vs Vision CG y-down | Plan T1 golden 4 号符号门（右倾 6° 地平线 → −6°±0.5）+ T3/T4 探针钉死（VisionDetect y-down 翻转头注先例）+ 单线 level 精确门 1e-9（符号错 = 门爆） |
| R-3 双 warp 叠加软化 | ashift.rotation + upright 同用 = 两遍 bilinear（upstream 单遍合成） | 短期：ashift neutral（纯 Guided 常态）只一遍；UI 提示挂 T4 观察项（upright 非空且 ashift.rotation ≠ 0 → 面板 note 提示拉直并入导线解）；单遍合成优化挂 `research/UPSTREAM-QUEUE.md` |
| R-4 导线拖动实时性 | 每 tick 重解（μs）+ preview 重渲（一 warp + 尾段）；M2-11 hitch 门（>50ms=0）；upright 尾段链长于 crop T0 先例 | Plan T4 首动作预算探针（PERF_PROBE + L014 fence）；越门 → D-M9G-5 回落②保底 |
| R-5 段检测探针源质量 | lens 校正后帧（upstream 分析域）vs decoded 裸探针的检测质量差未实测 | Plan T3 一次对比实测（detectionSourceImage 裸探针 vs followEdgesSurface 截断栈形），DECISIONS 申报选型；detect_segments 合成暗线 golden（方向 <0.7° / 长度 ≥0.6×）先行钉数学 |

## 测试策略总纲（六门 = RESEARCH §5 直取）

1. **合成梯形逆解门**（M9GEO-02 主门）：已知 H_shot 合成网格 → 导线沿真
   竖线经 H_shot⁻¹ 映入 → solveGuided → 竖线 x 迹 spread <1.5px（720×480
   级）+ 解 H 与 H_shot⁻¹·recentre 四角位移差 <0.01（居中单位）。
2. **单线 level 精确门**：单条垂直导线 → 纯旋转，端点变换后 x 差 <1e-9。
3. **分辨率无关**：1200×800 vs 600×400 解 H 四角差 <0.006。
4. **符号约定门**：右倾下降 6° 地平线 → 拉直角 −6°±0.5。
5. **病态防线**：近平行（夹角 <0.5°）→ identity 回落不崩；共点 VP 帧内
   拒；focal 正交解域外（<0.5 或 >6）→ DEFAULT_FOCAL=1.5 回落。
6. **拉直防呆**：单边线 → None；带纹地平线 → −4°±0.5；20° → None、
   8° → −8°±0.5（≤10° + ≥3 线门）。
- 附：cropFitAngle 闭式对照（已知角/aspect 解析例 + 非最大框不放大 + 角
  回 0 框复原）；upright off 恒等 byte-exact（blit identity）；params
  往返 + StableHash；旋转 90/任意角 golden（AABB 尺寸闭式断言）；确定性
  双跑逐位（solveGuided 闭式无 RNG；段检测确定性区域生长）。

## 晨审推翻点索引（可推翻面速查）

- **charter 勘误**：真缺口叙事翻转（rotate 本体已达）——翻案 = 仍按 charter
  原文立「rotate 新基座」（与实况冲突，不建议）。
- **D-M9G-1**：同批双 item（undo 两次）↔ document 级 item 单 undo（触封存
  面三件 + 参数双真相，判弃）。
- **D-M9G-2**：新 op 15.5 ↔ ashift.Params additive 直矩阵（污染 dt GENERIC
  语义 + 封存面新增改动点，判弃）；upright 面板基础排 ↔ Advanced 组。
- **D-M9G-3**：Guided only ↔ auto 族入批（+5-8N 超站预算，挂 UPSTREAM-QUEUE）。
- **D-M9G-4**：lightcraft 段检测 ↔ Vision 单线现状（防呆实证差距，保留
  Vision 为回落）。
- **D-M9G-5**：live 重渲 ↔ disabled+scrim 保底（探针实测后定）。
- **D-M9G-6**：显式位持久 ↔ 每次从 .auto 重解（语义抖动，判弃）。
