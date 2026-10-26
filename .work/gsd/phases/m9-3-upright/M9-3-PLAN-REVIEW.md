# M9-3 PLAN 独立评审（2026-10-25，零 commit 纯读评）

> 评审对象：`M9-3-PLAN.md`（v1）+ `CONTEXT.md`。
> 依据正本：`RESEARCH.md` / REQUIREMENTS M9GEO-01..02（:741-742）/ ROADMAP §M9 站 3（:143）/ AGENTS 跨批不变量 / ashift 现役面 + lightcraft origin/main（HEAD `bb08a697`，本地工作树落后 1031 commits——**upstream 一律以 `git show origin/main:` 读**，见观察项 3）。
> 评审方式：纯读 + 亲核抽锚（我方仓 20 锚 + upstream 11 锚，共 **31 锚**，29 精确吻合、2 处 plan 汇总注记/语义小瑕）。

## 结论：PASS-with-notes（0 error / 3 minor / 4 observation）

Plan 可执行、红线完备、OQ-1 修正成立、量级申报诚实。三条 minor 均为文字/语义级瑕疵，执行批在对应任务的 DECISIONS 内定夺即可，不需 plan 重开。

---

## 六维评审

### 1. 目标回溯 — PASS

- **M9GEO-01（charter 勘误读解 = 联动 UX 缺口）全兑现**：REQUIREMENTS 行（:741）三要素 = 旋转 90/任意角 golden（T3 验收末条，flip 位集 + ashift.rotation 两腿）+ sidecar 持久化（既有 paramsData 面，零 schema 红线承接）+ 视口交互探针（CropToolRotationTests App 域 + 走查 MANIFEST ①②③）；勘误后真缺口（角度手柄/拉直滑杆/90°/联动重算/auto straighten 防呆/Constrain Crop）逐件落 T3。
- **M9GEO-02 全兑现**：upright.rs MIT 移植（T1 UprightMath）+ 导线交互（T4）+ 合成梯形逆解 golden（门 1）。REQUIREMENTS 行文「M5-3 Pano homography 复用」与勘误（warp 锚点改判 ashift_warp）的冲突已在 CONTEXT charter 勘误节显式登记（晨审可翻）——处置合规。
- **golden 六门判别力成立**：六门各钉独立失效模式（逆解 = 数学正确性 / 1e-9 = 符号与旋转纯度 / 分辨率无关 = 归一化 / −6° = 用户可见方向 / 病态三防线 = 不崩承诺 / 防呆三态 = 误转门），无可删并的门。

### 2. 坐标真实性 — PASS（31 锚亲核，29 命中）

我方仓 20 锚全部命中（file:line 级）：V50Order 几何段（lens 13.0→ashift 15.0→flip 16.0→…→crop 24.5，15.5 空位在）/ `AshiftKernel.functionName = "ashift_warp"`（AshiftModule.swift:73 形态 = 字符串常量）/ AshiftModule.Params :86-127 / Registry defaultFaceDisabledOpNames :39-47 六件不含 ashift / Registry :517「rotation + perspective share one kernel」共名先例 / Registry :653 ashift 默认 seed / AshiftKernels.metal:79 `ashift_warp`（3×3 后向 + 像素中心 + clamp-edge + 域外透明，通用 warp 骑用成立）/ Homography compose:69·dlt:200·fitParams:249 / **IopCatalog 头注「geometry 族 deliberately NOT cataloged + catalog is the key REFERENCE, not a whitelist」**（CONTEXT 转写勘误①属实）/ GeometryPointMapper :42-52 `.affine`+`.homography` 双段 / FlipModule :63-103 八位+`.auto`(−1)+`resolved(forEXIF:)` non-auto 直通（rotCW90=5/rotCCW90=6）/ CropModule.Params 四边+ratio :63-69 / CropOverlayView :27-28 旋转手柄 linkage 注记（原文在案）/ EditorTabRoute :266-278 Geometry 页基础排+Advanced 组 / detectionSourceImage :2029-2034 / EditorState.recordChange :217 / HistoryStack :144-146（document 先例 CodingKeys）+:342-350（单步 undo、无组机制）/ LightamerSidecar :255 v11 + :741-752 paramsData / LensModule :297 LensAutoCrop / R6-SUMMARY:55 `4292/35/0`。

upstream 11 锚全部命中（**origin/main 真身**）：upright.rs 634 行（RESEARCH 对；charter 记 611 = 落后工作树的旧数）/ detect_segments :76 / refine_vp :259 / vanishing_point :275 / focal_from_vps :367 / level_angle :377 / solve_guided :508（四臂 match 与 plan T1 读解逐语义吻合，含 90° 共轭 `(x,y)→(y,−x)` 与 `take(4)`）/ STRAIGHTEN_MAX_DEGREES :583=10.0 / STRAIGHTEN_MIN_LINES :587=3 / level_degrees :592；transform.rs DEFAULT_FOCAL :13=1.5 / rotation_homography :34 / recentre :51；**五 commit 锚全真**（fbc927f0 merge #2347 导线画/拖端点、7635b38c 选中/删除、693c3593 LR-CROP-AUTO ≤10°+≥3 线、54c6c43b Constrain Crop #1927、7d3cd8af XMP upright）；**三条 issue 语义全真**（#742 = 各入口设角保持框在图内、#1388 = 直角收缩的框随角回 0 长回、#1794 = 转角时框绕中心收缩而非换成最大框——plan 断言读解与 commit message 逐条对上）；tests_guided_guides.rs 在 origin/main 在案（交互态机测试名与 plan T4 断言面逐语义吻合）；tests_geometry.rs 526 行（RESEARCH 对）测试名/门全在；settings.rs guides「up to 4 line segments, normalized, lens-corrected frame」；crop.rs with_angle:99 / crop_fit_angle:167 / constrained:59 + `with_angle_shrinks_a_crop_that_no_longer_fits_keeping_its_aspect`（#1794 中段语义，见 minor-2）。

### 3. 红线完备 — PASS

- **V50 add-only**：15.5 一行 + 「不重排/现行序逐字节」断言（filmPlacement 20.8 先例亲核在 V50Order 注释可查）。
- **ashift_warp 零改**：git diff 机检条款 + 共名 dispatch（:517 先例亲核）+ 需 wrapper = 逐 hunk 申报豁免停手。kernel 形态亲核证实通用 3×3 后向 warp，upright 直骑无需 wrapper 的判断成立。
- **零 schema**：paramsData 既有编码（:741-752 亲核）+ M9-2 v12 预定让位说明；UserDefaults 零新键。
- **封存面 17 件口径自洽**：15 严格零 diff（含 HistoryStack/HistoryHash/PipelineDocument/LightamerSidecar/GradeCatalog/ModuleInstance）+ 唯二 additive 例外（V50Order/Registry）= 17。**OQ-1 修正真避开封存面**：亲核证实 HistoryItem 是 HistoryStack.swift 内嵌类型（CodingKeys :144-146），document 级 item 加 case = 改封存文件；recordLinkedChanges 落 EditorState（App 侧，非封存面，recordChange :217 邻位可 additive）——回避论证结构面成立。
- **MIT 归属不可延后**：双文件头注 + NOTICE + 五 commit 锚（全亲核为真）。
- AshiftPanelView 零 diff 断言在 T3/T4 验收双落。

### 4. 可执行性 — PASS

- **T 序依赖正确**：T1 数学 → T2 op（消费 solveGuided）/T3 联动（消费 cropFitAngle）→ T4 导线（消费 T2 op + T3 Constrain 座位）→ T5 收口；串行 + 机器级单重活 + M9-2 让位条款齐。
- **ΔN +14..19 构成自洽**：下限和 5+3+4+2+0=14、上限和 7+4+5+3+0=19，逐任务区间算术闭合；越 charter 上沿（18）至多 +1 的申报句三处在案（front-matter / ΔN 表注 / 风险节）。
- **带式对账锚亲核**：R6 终值 4292/35/0 = R6-SUMMARY:55 精确命中；ΔN_M9-1/M9-2 引 plan 估值且声明「开工前以 SUMMARY 实数落」= 诚实形态；STATE.md M9 ledger 亲核（M9-1/2 pending、M9-3 本批）与 CONTEXT 编排现势一致。

### 5. OQ 采纳（planner 修正是否成立）— PASS

- **D-M9G-1（OQ-1 修正 = 同批双 item）成立**：①document 级 item 的三重代价亲核坐实——HistoryItem CodingKeys 内嵌（触 HistoryStack 封存）+ HistoryHash 折入 + PipelineDocument 同批写（DRT/film 先例即此形）；「参数双真相」论证成立（DRT/film record 是 document 级真相本体，旋转/裁切是 instance params，镜像入 document item = 两处真相）；③undo 组机制不存在亲核（:342-350 单步）。②的落地缝（EditorState additive 批 API）与非封存性均亲核可行。#742/#1388/#1794 三代 issue 的教训本体定位为「框语义非 undo 计数」有 upstream commit 语义背书。
- **#1794 框语义承接大体充分**：单源谓词 + 手调框保护 + 非最大框不放大 + 角回 0 复原四断言承接了 #1794 的两端语义；唯中段「no-longer-fits 框绕中心收缩保 aspect」未显式钉（minor-2）。
- D-M9G-2..6 采纳均与 research 推荐一致且无越权（附带裁定「upright 不入 IopCatalog」有头注亲核背书）。

### 6. 量级诚实 — PASS（一处汇总注记错，见 minor-1）

落域与 BUNDLE-MAP 惯例逐件吻合（亲核）：UprightMathTests/CropFitAngleTests/StraightenDetectTests → IOP（HomographyTests:142 / LensAutoCropTests:801 / VisionDetectTests:196 同域先例均在 IOP）；UprightModuleParityTests → IOPP（`*Parity*` glob，AshiftParity:77/CropParity:85 先例）；CropToolRotationTests/UprightGuidesInteractionTests → APP（CropOverlayTests:215 先例）。Project.swift 显式数组 + BUNDLE-MAP 六行 + tuist 末位条款齐。

---

## 分级清单

**Error（阻断）：0**

**Minor（执行批 DECISIONS 定夺，plan 不重开）：**

1. **ΔN 预算表合计行 + T5 Action 1 的落域注记数错**：两处写「二 IOP + 一 IOPParity + 三 App」，实为**三 IOP + 一 IOPParity + 二 App**（按 files_modified 与各 T 内标注：UprightMath/CropFitAngle/StraightenDetect = IOP，UprightModuleParity = IOPP，CropToolRotation/UprightGuidesInteraction = App；六文件总数对）。执行批按正确落域登记 BUNDLE-MAP 六行即可，收口时 SUMMARY 更正注记。
2. **T2 验收「off 不入档负测（默认 params 不写 sidecar 语义同 pristine 惯例）」语义张力**：upright 进默认 seed（Registry 注册行族亲核形态）⇒ instance paramsData 恒入 sidecar（ashift/flip 同形）；「pristine 惯例」（DRT/film document record 缺席不写）是 document 面语义，不适用 instance params 面。真意推测 = off 不产生渲染/行为差异（blit identity）或不写 history item——T2 执行时 DECISIONS 钉死该断言的机器形态，防执行员按字面实现出与 seed 形态冲突的「不写 sidecar」分支。
3. **shouldAutoRefit 中段语义未显式钉**：upstream #1794 修复 = 「仍 fit 的框不动 / 不再 fit 的框**绕中心收缩保 aspect** / 最大框随角重算」三分支（crop.rs `with_angle_keeps_a_crop_that_still_fits` + `with_angle_shrinks_a_crop_that_no_longer_fits_keeping_its_aspect` 双测试亲核）；plan 谓词二值化（重算最大框 / 不动）承接两端，中段 shrink-keeping-ascept 仅以 T3「aspect 保持」一词隐含。T3 执行时 DECISIONS 定夺：手调框在转角后不再 fit 时 = 完全不动（可能悬空含黑边）还是绕中心收缩（upstream 行为）；若采后者需补一条 golden。

**Observation（不强制，建议采纳）：**

1. `AshiftModule.swift:73` 的 functionName 实属 `AshiftKernel` enum（文件内 ：73 邻域）——plan 说「字符串常量同形」成立，UprightModule 照建 `UprightKernel` enum 同形即可，无需改文。
2. golden 门 1 的 spread 门 <1.5px 统一取了 upstream 最宽值（upstream vertical/guided 门 = 1.2px、full = 1.5px）；判别力仍足，若愿收严可按 upstream 分域 1.2/1.5。
3. **lightcraft 工作树 ≠ origin/main**（本地 HEAD 落后 1031 commits，upright.rs 工作树 611 行 vs origin/main 634 行，tests_guided_guides.rs 工作树不存在）：RESEARCH §2 头部已注明 fetch 语义，但建议执行批在 T1 read_first 注记「upstream 引用一律 `git show origin/main:<path>`，勿读工作树」——评审过程亲历工作树误判（常量/测试文件双缺），此提示可省执行员一轮困惑。
4. R-1「我方 crop 存 ashift-AABB 帧分数与 upstream 旋转帧归一不同构」是真实结构差——plan 用「谓词判框 == 旧角输出」而非「几何同构」来弥合，是务实选择；走查样张建议含一张「手调框 + 大角度 + 框不再 fit」的边界样例（与 minor-3 联动验证）。

---

## 抽核命中统计

- 我方仓锚：**20/20 命中**（V50Order / AshiftKernel.functionName / Ashift.Params / Registry×3 / ashift_warp kernel / Homography×3 / IopCatalog 头注 / GeometryPointMapper / FlipModule / Crop.Params / CropOverlayView:27-28 / EditorTabRoute / detectionSourceImage / EditorState:217 / HistoryStack×2 / Sidecar v11+paramsData / LensAutoCrop:297 / R6-SUMMARY:55）。
- upstream 锚：**11/11 命中**（upright.rs 函数六件 + STRAIGHTEN 常量两件 + transform.rs 三件 + 五 commit 锚 + 三 issue 语义 + tests_guided_guides/tests_geometry/settings.rs/crop.rs 配套件）。
- 合计 31 锚亲核，关键 file:line 全命中；plan/CONTEXT 引用行号与实况零漂移（唯汇总注记 minor-1 一处数字错）。

**终裁：PASS-with-notes**——三条 minor 移交执行批 DECISIONS（T2 off 入档语义 / T3 中段框语义 / 落域注记更正），晨审若翻 D-M9G-1 单 undo 需同步解封 HistoryStack 三件（plan 已自载该破口申报，维持不建议翻案判断）。
