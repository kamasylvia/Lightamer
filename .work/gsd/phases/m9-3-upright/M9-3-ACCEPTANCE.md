# M9-3 ACCEPTANCE — 双路 zcode 独立验收·第一路（2026-10-29）

> 验收对象：五 commits `d111ef2a`（T1 数学面）+ `3cf962be`（T2 upright op）
> + `e6bbac45`（T3 联动面）+ `e5e14b60`（T4 导线交互）+ `bee6b4bc`（T5 账本），
> refs #13；HEAD = `bee6b4bc`。AC 源 = REQUIREMENTS M9GEO-01..02（charter 勘误
> 后语义）。正本 = M9-3-SUMMARY.md + DECISIONS + PLAN v2 + CONTEXT。全套
> `--all` 经 orchestrator 预批，本轮独立复跑。

## 结论

**PASS / 0 error + 2 minor + 6 obs**。两条 AC（M9GEO-01 勘误后 =
rotate/straighten 的 crop 工具联动 + 检测防呆 + Constrain；M9GEO-02 =
Guided Upright 导线系）逐条落 file:line 全对上；**三封存件
（HistoryStack / HistoryHash / PipelineDocument）零触碰机检成立**——封存面
17 件中 14 处抽查全零 diff，唯二 additive 例外（V50Order +8 / Registry +17）
恰形；AshiftKernels.metal 零 diff；V50Order 15.5 add-only（现行序逐字节零改）；
off 恒等 byte-exact 读验（`accuracy: 0` 断言）成立；数学面四防线逐道验 +
CropFitAngle 与 upstream crop.rs 逐段对齐（`git show origin/main:` 读法，
两代 #1794/#1388 测试同参直译）；**全套独立复跑 4386/34/0 与申报值逐位
一致**（ΔN +23 精确 = 23 新法逐文件点数吻合；七 bundle 全绿、零 MEMFAIL、
monitor 零 kill）；反自取消双探针两处真红且还原复绿。

## §1 AC 逐条核对

### M9GEO-01（勘误后）— rotate/straighten 的 crop 工具联动 ✓

| AC 面 | 落点 | 独立核验 |
|---|---|---|
| 角度手柄 | `CropRotationHandleMath`（CropOverlayView.swift:124-185 纯函数，orbit/liveDegrees ±45° 折）+ D-H1 三段（`onRotateBegin/Live/Commit`）+ `:27-28` 旧 linkage 注记兑现改写 | 手柄 AX id `crop.handle.rotation` 在案；头注记 sign hand-off 与测试钉死对齐 |
| 单漏斗联动批 | `CropToolRotation.linkedSnapshots`（CropToolRotation.swift:124-202）——angle 先 crop 后的 commit 序 + frameMoved 1e-6 Float 容差 | CropToolRotationTests testLinkedBatchAtomicityAndUndoOrder 两 item + LIFO undo 三断言绿 |
| 联动重算单源谓词（#742/#1388/#1794） | `CropFitAngle.withAngle` 三分支（CropFitAngle.swift:219-268）+ `shouldAutoRefit` 单源（:275-282） | CropFitAngleTests testWithAngleThreeGenerationSemantics (a)-(e) 段同参直译绿（upstream 600×400 / (-3,0.5,2,5) / 角隅 (0,0,0.6,0.6)×5 角 / grow-back [None,1,16/9]×[10,25,−25,7,0] 全同参） |
| 90° 显式位覆盖 | `ninetyDegreeSnapshot`（CropToolRotation.swift:223-245）+ `isClockwiseBit` 探针（:209-215） | testNinetyDegreeBitProbeAndPersistence：`.auto` 种子落显式位 + `resolved(forEXIF:)` 直通断言绿 |
| auto straighten 防呆 | `StraightenDetect`（STRAIGHTEN_MAX_DEGREES=10.0 / MIN_LINES=3，:39-43）+ `autoStraightenDegrees`（PipeCoordinator.swift:2116-2154，decoded 裸探针 → 512 software 采样） | StraightenDetectTests testStraightenGuardGates 五态全绿（单线 None / 4° 带纹 −4±0.5 / 20° None / 8° −8±0.5 / 符号 −6±0.5） |
| Constrain Crop | `constrainedCropRect` 绕心像素 aspect 保二分收缩（CropToolRotation.swift:257-302，20 轮 ≈ 1e-6 span） | testConstrainCropShrinksBlankEdges：blank_fraction<0.002 + 像素 aspect 1.5±0.02 + 已贴合 nil 三断言绿 |
| 旋转 golden（AABB 闭式） | `RotatedFrameBridge.span`（:45-49，floor 闭式 = ashift modifyROIOut 形） | testRotatedFrameSpanHandValue 手值 719×646（600·cos30+400·sin30）+ 桥往返 1e-12 绿 |
| 持久化 + 零 schema | ashift.rotation / flip.orientation 既有 params 面；LightamerSidecar 零 diff（机检 0 行）；schemaVersionCurrent diff 计数 0 | sidecar 持久走既有 paramsData（MIN-2 语义：off 实例 paramsData 恒写，parity 测试显式断言） |
| AshiftPanelView 现役面零 diff | `git diff --stat` 空输出 | Vision Auto Level 回落位不动 ✓ |

### M9GEO-02 — Guided Upright 导线系 ✓

| AC 面 | 落点 | 独立核验 |
|---|---|---|
| 合成梯形逆解 golden | UprightMathTests gate 1（:70-103）：spread<1.5px（720×480 face）+ 四角差<0.01 + 确定性双跑逐位 | 全绿；executor 前探针 8e-16 钉值注记在法头 |
| UprightMath 数学件 | UprightMath.swift（族分 ≤45° 折 :366-367 / Σ w·l·lᵀ Jacobi :129-183 / 正交估焦 0.5..6.0 :190-198 / Rodrigues :210-231 / K·R·K⁻¹ :266-270 / recentre :275-284 / solveGuided 降级链 :364-426） | 与 upstream upright.rs（smallest_eigvec/refine_vp/focal_from_vps/solve_vertical/solve_full/level_angle_within/solve_guided）逐段对照同构 |
| upright op v50 15.5 骑 ashift_warp | UprightModule.swift（`functionName = "ashift_warp"` :65 共名 / `iopOrder = 15.5` :120 / Registry 注册行族 + seed） | **AshiftKernels.metal 零 diff 机检 0 行**；PSO 清单共名 dedupe 注记在案；零新 kernel 红线成立 |
| off 恒等 byte-exact | UprightModuleParityTests testOffIdentityByteExactAndParamsPersist（:116-156，`accuracy: 0` = byte-exact GPU 腿）+ off 实例 paramsData 恒写断言（:127-130，MIN-2） | 全绿；pointMapSegment off nil 断言在案 |
| 产线 warp 梯形恢复 | testGuidedWarpStraightensKeystoneThroughRealKernel（:160-264）：真 kernel 腿 spread<1.5px + formula-mirrored landing anti-vacuum | 全绿；ROI 协商 hooks 走产线面 |
| params 往返 + StableHash + V50Order | testParamsRoundTripStableHashAndV50Order（:268-302）：Double 精度逐位 + V50Order 邻位（ashift 15.0 / upright 15.5 / flip 16.0）+ seed 含 upright + disable 集不含 | 全绿；V50OrderTests 107→108 计数增补（T5 账本）同批 |
| mapper 唯一坐标通道 | `uprightGuideMapper`（PipeCoordinator.swift:2160-2169，pre-upright box 过滤 <15.5）+ `pointMapSegment`（UprightModule.swift:273-284，`.homography` 段，mapper 本体零 diff） | testPointMapSegmentRoundTrip <1px + testMapperRoundTripUnder1px（ashift 8° 复合帧）双绿 |
| 导线交互态机（5+5 面） | `UprightGuidesModel`（UprightGuidesOverlay.swift:32-193：按下即画 :89-108 / 端点拖近跟远不动 :112-129 / release 零长不成线 :135-146 / lineHit 选择 :168-174 / Delete 无选中零动作 :180-185 / ≤4 上限 :105） | UprightGuidesInteractionTests 5 法全绿（①②③④⑤ + 持久逐步 undo + 选中 UI-only 负测 params 无 selection 键 + mapper 往返 + live 零 item D-H1） |
| 选中态 UI-only | UprightGuidesModel.selected 注释 + InspectorState.uprightGuideSelected 会话态 + params JSON 无 "select" 断言（UprightGuidesInteractionTests:144-146） | 负测绿（serde-skip 语义承载） |

## §2 三封存件与封存面机检（OQ-1 重点）

- **三封存件零触碰**：`git diff 5eef3d03..HEAD --` HistoryStack / HistoryHash /
  PipelineDocument **各 0 行**（机检）。recordLinkedChanges 落 EditorState（App
  additive 面，EditorState.swift:242-251）+ `HistoryStack.commit` 既有单实例
  API——实现结构上从未需要触三件，OQ-1 裁②的结构面依据兑现。
- **封存面 14 处抽查全零 diff**：AshiftKernels.metal / LightamerSidecar /
  GradeCatalog / DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe /
  ExportQueueContract / Lut3dKernels.metal / NodeGraphCommand / ModuleInstance
  （+ 上三件）全 0 行。
- **唯二 additive 例外恰形**：V50Order.swift +8 = 7 注记 + `("upright", 15.5)`
  一行（现行序逐字节零改，add-only）；Registry.swift +17/-1 = 注册行族 9 +
  共名注记 2 + seed 6（`defaultFaceDisabledOpNames` 零触——diff 无该符号）。
- **零 schema / 零 UserDefaults 新键**：schemaVersionCurrent diff 计数 0；
  Resources 仅 Localizable.xcstrings +357/-0 尾块纯插入。
- **门禁独立复验**：zh-audit `--check` PASS（1765/2081/10 interp）+
  `--self-test` PASS（V17 八 case）本轮实跑；NOTICE 条目 S（lightcraft 五锚
  fbc927f0/7635b38c/693c3593/54c6c43b/7d3cd8af）+ 三文件 MIT 头注在案。

## §3 数学面抽验

- **病态四防线逐道**（UprightMath.swift solveGuided + golden 5 号门）：
  1. 重合线（familyVP 内 maxCross²<1e-24 → nil，:374-382）——golden 用同线双导线断言 identity bitwise；
  2. 帧内 VP（radius²<4.0 拒，:387-391）——golden 用 (0,0) 共点三线断言 consensus 失败 → identity；
  3. focal 域外（0.5..6.0 外 → nil → DEFAULT_FOCAL=1.5，:190-198 + :403）——golden 手值 f²=40 → f≈6.32>6，逐位对照手组 homography；
  4. finite-output net（各臂 isFinite 检查，:401-425）——golden 用双 VP 落 y=0 线样例断言 9 元全有限（非 NaN）。
- **第四防线合理性复核（成立）**：双族 VP 同落 y=0 线 → solveFull 后 R 第三行
  归零方向 → K·R·K⁻¹ 齐次 w 行过零 → recentre 的 project 除零 → NaN。这是该
  guide 几何的**数学退化**（校正单应在无穷远有极点），非数值 bug；Guided 无
  RANSAC/reliable（D-M9G-3）故必须自兜底。isFinite net 只在矩阵含非有限值时
  降级——合法校正恒有限，无误伤面；降级臂 levelAngle 纯旋转恒有限。与第三
  防线样例的解耦（域外 focal 改用离 y=0 线 VP）正确——两防线各自独立成立。
- **CropFitAngle vs upstream crop.rs**（`git show origin/main:crates/geom/src/crop.rs`）：
  `with_angle` 七段结构逐段同构（aspect 退化回退 / isLargest 门 / fit 保持 /
  largest+nil 直 fitted / 绕心收缩 min_side 过滤〔MIN_CROP_FRACTION=0.01 同值〕/
  角隅 sliver 收缩 scale<1.0）/ `max_inscribed_scale` 闭式（abs(angle) 同）/
  `crop_fit_angle`（fit_aspect + min(s,1) 同）；上游 #1794/#1388 两测试同参
  直译（600×400 + 同 rect 集 + 同角度序）。
- **手值复核**：3:2@10° 闭式 = 200/249.056 = 0.8030322372（10 位有效）独立
  重算吻合；span 手值 719×646 吻合；符号门（右倾下降 y 增 → dev>0 →
  `return -median` 负角）与 levelAngleWithin 的 dev 折叠逐行验。
- **UprightGuidesModel 态机**：press 优先级（端点 > 线体 > 新画）与 ≤4 cap、
  零长不成线、Delete 无选中零动作逐行读验，与 upstream tests_guided_guides
  5+5 面一一对应。

## §4 全套独立复跑（orchestrator 预批）

**终值 `TOTAL|4386/34/0|4104s`，与申报值逐位一致**（acc1-all.log）：

| bundle | 申报 | 本轮 | peak RSS |
|---|---|---|---|
| IOP | 807/1/0 | **807/1/0**（949s） | 7196MB |
| IOPParity | 544/10/0 | **544/10/0**（1633s） | 6160MB |
| Layers | 528/5/0 | **528/5/0**（467s） | 1180MB |
| Library | 785/4/0 | **785/4/0**（174s） | 749MB |
| Sessions | 285/4/0 | **285/4/0**（62s） | 1239MB |
| Export | 385/4/0 | **385/4/0**（200s） | 5113MB |
| App | 1052/6/0 | **1052/6/0**（619s） | 2832MB |

- ΔN +23 精确核数：UprightMathTests 5 + CropFitAngleTests 2 + StraightenDetectTests 2
  + UprightModuleParityTests 4 + CropToolRotationTests 5 + UprightGuidesInteractionTests 5
  = 23 新法逐文件 `grep -c "func test"` 点数吻合；七 bundle 分值与基线链
  （M9-2 4363/34/0 ⊕ 本批 +23）自洽。
- 零 MEMFAIL（8G 机检门零触发）；monitor 21600 伴跑零 RSS-KILL（acc1-monitor.log
  仅 start 行）；G4 本轮以清缓存真实过门（25.48GB，无透明越门——处置见 obs-3）。
- 证据 = `.work/gsd/phases/m9-3-upright/all-runs/acc1-{all,monitor}.log`。

## §5 反自取消双探针（主树掏空还原法）

1. **VP 求解改错（探针 1，acc1-probe1-vp-red.log）**：`smallestEigvec` 的
   特征向量**选择器翻转**（最小代最大——比任务书示例「符号翻转」更强的真
   突变：纯投影域内符号翻转不改变线约束 l·v=0，测试本就不会红，不构成有效
   反自取消探针；选择器翻转 = 拿最大特征向量当 VP = 真「VP 求解改错」）。
   → `--bundle IOP UprightMathTests` 过滤轮 **5/0/2 真红**：gate 1 spread
   **382.33px**（门 <1.5）+ 四角差 **1.193**（门 <0.01）双爆 + 病态门 2 断言
   （identity / DEFAULT_FOCAL bitwise）双爆。**意外收获（obs-1）**：gate 2/3/4
   精确不红——单线/分辨率/符号门不经 refineVP，红面与被改函数调用面结构
   一致，覆盖面健康。还原后 5/0/0 复绿。
2. **联动拆单（探针 2，acc1-probe2-split-red.log）**：`linkedSnapshots` 的
   `frameMoved` 门恒 false（角度单飞、crop refit 丢失 = 联动批拆单的最小真
   突变）→ `--bundle App CropToolRotationTests` 过滤轮真红：
   **testLinkedBatchAtomicityAndUndoOrder:79 `("1") is not equal to ("2")`
   - the largest frame refits: two items**（原子性断言抓住）；连带
   items[1] 下标越界 fatal crash（obs-2）。还原净树 + 重建后 App 5/0/0 复绿。
- 两探针全程 git 状态机检：突变期唯一 diff = 目标行，还原后 `git status`
  零改动，产物以还原后重建恢复（IOP 5/0/0 + App 5/0/0 双复绿确认）。

## §6 执行期偏差复核

| 偏差 | 复核结论 |
|---|---|
| **Float 判等门 1e-3px 重定**（DECISIONS §Float 记录域） | **成立**。upstream 1e-9 是全 f64 管线内部判等；我方 crop record 以 Float 分数持久（Float32 相对误差 ~6e-8 → 600px 帧 ~3.6e-5px 上界、实测噪声 6e-6px），1e-6px 门被噪声淹没（#1388 regrow 漏判实测在案）；1e-3px ≈ 170× 余量，且千分之一像素物理不可拖出（指针粒度 ≥1px）——语义无损。复原断言门 1e-6（残余实测 8.9e-9）同源合理。晨审如翻 f64 sidecar params = schema 触碰，不建议。 |
| **病态第四防线 finite-output net**（DECISIONS §病态防线第四形态） | **成立且必要**（§3 已详述）——退化几何的诚实降级，非吞错；golden 5 号门样例与第三防线解耦正确。 |
| App 宿主 sandbox 卡死 2h（SUMMARY §环境事件 2） | 透明登记充分；本轮探针 2 轮日志头复现同签名（`sandbox_extension_issue_file_to_process ... Operation not permitted`）但未挂死、测试跑完——间歇系统态先例一致（obs-4）。判据面不受扰（verdict 由测试结果行判定，非宿主退出态——脚本 L055 纪律）。 |
| G4 贴线（SUMMARY §环境事件 1） | 本轮无透明越门：清 tmp 残留 + 可再生缓存（go-build/playwright/uv prune/npm）+ Xcode 模块缓存后真实过门（20.5→25.48GB）。executor 两次 24.2-24.7GB 透明越门维持其登记论证（free 内存 71-75%、单 bundle 峰 ≤7.7GB vs 余量，G4 防 swap 挤爆本意不成立）——不推翻，但建议下批把 8G 门跑批的 scratch 预算纳入 G4 预估。 |
| 检测源选型（R-5）+ live hitch 探针（D-M9G-5）转办走查 | 申报链完整：DECISIONS 两节 + MANIFEST 走查⑦⑧配方在案（executor 无 GUI 探针窗的结构性限制；本验收路同无 GUI 窗，不动摇）。 |

## §7 发现清单（B/M/m/obs）

- **B（blocking）：无。**
- **M（major）：无。**
- **minor-1**：BUNDLE-MAP 登记行 `APP 6 UprightGuidesInteractionTests.swift` 的
  法数 6 与实测 5 不符（`grep -c "func test"` = 5；六文件中唯此一行错，其余
  五行 5/2/2/4/5 全对）。SUMMARY ΔN 账 +5 与全套 +23 正确不受扰（该行头注
  「行内 method 数以终态对账为准」下无实质影响），属账面登记笔误——建议
  下批顺路订正为 5。
- **minor-2**：`UprightMath.vpError`（UprightMath.swift:115-125）为死代码——
  全仓零消费点（upstream 中它服务 RANSAC 打分面，本批依 D-M9G-3 未移植
  RANSAC，直译件落空）。无害（internal 未用不告警），建议下批删除或补
  「保留待 auto 模式族」头注。
- **obs-1**：探针 1 的红/绿面与 refineVP 调用面结构精确对应（gate 2/3/4 不
  红）——测试覆盖拓扑健康的额外证据。
- **obs-2**：CropToolRotationTests 的 `items[1]` 直取下标无 guard——红断言后
  连带 fatal crash（截断同 suite 后续方法）。红已成立不动摇验收；建议下批
  给 items[1] 前置 count guard，避免红轮污染宿主（L055 crash verdict 面）。
- **obs-3**：G4 两波贴线处置——本轮真实过门（清缓存清单见 §6）；跑批自身
  消耗 ~0.4GB，下批可预估。
- **obs-4**：App 宿主 sandbox_extension 警告签名复现一次（探针 2 轮）未挂死——
  executor DECISIONS 间歇系统态先例同窗，计数不受扰。
- **obs-5**：走查六项配方 + 转办两项（⑦检测源对比 / ⑧live hitch）在
  `.work/gui-acceptance/m9-3/MANIFEST.md`——execute/validate 道消费件，本
  验收路无 GUI 探针窗不动摇。
- **obs-6**：tuist generate 末位（L041）以本轮 --all 新测试文件实际入 bundle
  运行（七 bundle 计数含 23 新法）间接证明；Project.swift 六文件归位
  （三 IOP + 一 IOPParity + 二 App）与 MIN-1 修复一致。

## §8 验收方法与纪律

- guard 前置四轮（初检 BLOCK → 清理后 PASS ×3）；全套轮同链 ps 清零验证
  （`MacOS/Lightamer` = 0）+ `machine-guard.sh --monitor 21600 &` 伴跑 +
  nohup disown；探针轮各自 guard 前置；还原后重建 + 双过滤轮复绿。
- upstream 对照一律 `git show origin/main:<path>`（OBS-3 纪律；本地 fetch
  网络失败但 origin/main 本地对象在位，读法成立）。
- 判据纪律：全套计数以 parse_bundle_log 测试结果行为准（非宿主退出态）；
  探针红以具体断言行为准（非 crash 签名）。

—— 验收第一路（zcode lane 1），2026-10-29。
