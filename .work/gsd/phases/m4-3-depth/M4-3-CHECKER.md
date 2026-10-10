# M4-3-01 Plan Checker Report（从严）

- **结论：PASS / 0 error + 7 minor + 6 obs**（全部 minor 带处方，执行批同批采纳；无阻塞项）
- 审查人：zcode checker subagent（2026-10-10）；审查对象 = `M4-3-01-PLAN.md`（commit `af0ecec`）
  + `M4-3-CONTEXT.md`（裁决记录 2026-10-10）+ `RESEARCH-NOTES.md`。
- 审查方式 = 源码亲核 + Lumen 只读锚亲核 + 数学独立复算（uv/numpy）+ 机检命令试跑；
  非 plan 转述。

## 1. 锚亲核结果（全部命中）

| 锚 | 亲核结论 |
|---|---|
| `.work/config.toml [gsd]` | `auto = true` / `paused = false` / `dual_acceptance = true` ✓（T8 双重验收编排有配置依据） |
| 基线 3335/16/0 | `M4-1-VALIDATION.md` :19-34 亲证：`TOTAL|3335/16/0|1604s`，逐 bundle IOP 562 / IOPParity 427 / Layers 394 / Library 619 / Sessions 279 / Export 350 / App 704，求和 3335 自洽 ✓；M4-2 删除批后 Layers 394 / App 704 回落 = GOAL-STATE 续接点在案 ✓ |
| `ModelAssetStore.download` zip 晋升面 | `:175-181` 只晋升 zip（`finalDir/<assetFileName>`）；`EnhancementSession.resolvePackage`（`AIWorkerEnhancement.swift :52-72`）找的是去 `.zip` 后缀的**解压目录**；三个 release 档 digest 全 nil（`ModelAssetDigests.generated.swift` :85-89 亲读）→ 全链从未走通。**plan 的 latent gap 勘误断言属实** ✓ |
| `AIWorkerMain :258` 二分 | `:258` `guard manifest.embeddingDim != nil else { openEnhancementLeg(...) }` 逐字命中 ✓；crash hook `:244-248` 在 manifest 解析 `:251` **之前** → 「depth profile 免费生效、零改动」断言成立 ✓ |
| `AIWorkerProtocol` inPath/outPath | `AIWorkerPayload :108-109` 两字段在场；PATH 通道语义（8MB 界只管 BYTE 通道 `:21-29`）→ depth 帧零协议破坏可行 ✓ |
| `AIWorkerClient` enhanceTile 模板 | `:222-248` withFallbackChain 包裹 + run 级 requestFailed 不耗链（`:331-336` rethrow 路径亲证）→ runDepth 同构可行 ✓；`ensureOpen` 对无 facts 的 open 置 `lastEnhancementModelFacts = nil`（`:391-395`）→ depth open 不留陈旧 facts ✓ |
| `AIMaskEditing.commitRasterMask` 唯一缝 | `:125-198` 签名与 plan KD-5 用法逐参匹配（plane/source/invert/featherRadius/decodeWidth/decodeHeight/label/activateTool/expectedRevision 默认 nil）✓；`AIMaskSource` `:29-53` additive `.depth` 可行，`source(ofFileName:)` 循环 additive ✓ |
| `LayerEditingState :278` segment 判别 | `armSegmentSession`（`:277-285`）按 `source(ofFileName:) == .segment` 判别；`ai-depth` 前缀不同 → 不受扰 ✓ |
| `AIMaskTypes.swift:131-152` 错误面 | 生成失败严格语义头注 + typed 集合亲证；`noDepthStructure` additive 一 case 合容 ✓ |
| `AIMaskEntryGate.layerBEntry` | `:58-85` 四态纯函数先例在册 → DepthEntryGate 同构成立；`ModelAssetStatus` 六态（bundled/installed/notInstalled/digestUnpublished/downloading/corrupt）→ 四态映射可全（bundled 对 depth tier 不出现）✓ |
| `Registry.swift :81` LastValue adapter | `LightamerIOP/Sources/Registry.swift :80-93`（`FilmStatsSnapshot.last = value` :91）在册（本 plan 仅作先例引用，非消费面）✓ |
| Lensfun Process 先例 | `LensfunDownloadService.swift :81` `/usr/bin/unzip` Process（plan 写 :82，±1 行，非实质）→ resolver 用 `/usr/bin/ditto -x -k` 同形成立 ✓ |
| digest sentinel 机制 | `ModelAssetDigests.generated.swift :75/:90` BEGIN/END REWRITABLE ENTRIES + `build_default_bundle.sh :148-202` 按 sentinel 名唯一匹配重写正则 → build-depth-release-asset.sh 复用形态成立 ✓ |
| MaskToolbarView AI Subject 入口 | `aiGroup` `:275-396`（accessibility `ai.mask.subject` 先例 :305）→ Depth 组同款形态成立 ✓ |
| Project.swift 显式清单 | LAYERS 数组 `:464`（AIMaskEditPathsTests :474 在内，且依赖含 `Lightamer` :449——App 级测试落 LAYERS 有先例）/ LIB `:536`（ModelAsset*Tests :579-580）/ APP `:680+`（AIWorkerClientTests :754）→ plan 的四个新测试文件归置与先例一致 ✓ |
| 红线文件存在性 | Sidecar/`Aces2Kernels.metal`/`MaskEdgeKernels.metal`/DrtRecord/HistoryHash/LayerEditingState/NodeGraphCommand/ExportFormatSpec·ImageIOEncoders·WebPEncoder 全部在盘 → T8 零 diff 自证清单可执行 ✓ |
| `.gitignore` | `Resources/AIModels/**` 既有（:49-54）；模型产物落 `~/Library/Caches/LightamerModels/depth/`（仓外）→ 「仓内零模型字节」机检可保持 ✓ |
| test-direct.sh | `--bundle` 旗标在册；`BUNDLES=(IOP IOPParity Layers Library Sessions Export App)`（:165）——**CLI 名与 plan 书写不一致，见 m1** |
| Lumen `selection.py:71-74` | 四段管线逐行命中（percentile [10,95] / `(r-.48)/.22` / smoothstep）；`:65` ImageNet mean/std；`:67-68` isfinite 守卫；`auto_masks.py` 0.0003 守卫 + document token 比对；`v11-models.json:3-6` sha256 锁；`ai_worker.py:108-142` CompatRecord（`:132` 双模型→全禁）——全部与 plan/NOTES 转写一致 ✓ |
| `RasterMaskRef.invert` | `:29-30` 在册 → 远景 = invert 位承载（OQ-4）零新代码成立 ✓ |

## 2. 四段管线数学独立复算（uv/numpy 实跑）

- **percentile 语义**：numpy `'linear'`（默认）= 虚拟序 `q/100·(n−1)` + 线性插值；10 元素样张
  实跑 `np.percentile(a,10)=1.45` / `np.percentile(a,95)=7.65`，与 plan 公式独立复算**逐位一致**
  → T2「对 numpy 预计算参考值硬编码锚定」的锚定法成立。
- **合成两级靶**（远 0.2 占 92% + 近 0.9 占 8%）：low=0.2 / high=0.9 → 近 α=1、远 α=0 精确命中
  → 三断言中的前两条成立；**注意近区面积须 >5%**（见 m6）。
- **窗带**：0.48+0.22=0.70 ✓（≥0.48 起算前景 / ≥0.70 全前景，与 plan/NOTES 表述一致）。
- **守卫交互**：守卫 (a) 先抛时 `max(high−low, 1e-6)` 分母地板成死代码（保 Lumen 公式逐字节，
  无害，obs-o3）；**NaN 输入路径**：percentile 传播 NaN → 全平面 α=NaN → `α>0.5` 全 false →
  守卫 (b) 触发 typed `noDepthStructure` → **永不 all-ones 红线在 NaN 输入下仍成立**，但归因
  应为 inferenceFailed（见 m3）。

## 3. 裁决一致性（七项生效值 + 5 低分叉 → AC 逐条对）

| 裁决 | plan 落点 | AC | 判定 |
|---|---|---|---|
| OQ-1 A（DA V2 Small 官方 F16 直采，MiDaS 后手不入） | KD-1 第六 profile / KD-7 精度门 abs-rel ≤0.01（官方自报 0.0089 + 余量） | AC#1 | ✓ |
| OQ-2 A（GitHub Release，不内置） | KD-1 tier/releaseTag/digest fail-closed 保持 + 仓外产物位 | AC#2 | ✓ |
| OQ-3 B（M2AI-10 worker） | KD-2 三腿分派 + runDepth 降档链 + 零编辑器推理面 | AC#3 | ✓（grep 门措辞见 m7 关联的 AC#3 精确化，m-注） |
| OQ-4 A（单「深度」入口 + Lumen 固定参数） | KD-4 带名常量 + KD-6 零参数面 + invert 承载远景 | AC#4 | ✓ |
| OQ-5 A（双线性 + 既有羽化，零新 kernel） | 全批零 `.metal` 新文件 + AIMaskResample/RasterMaskStore.bake 既有通道 | AC#5 | ✓ |
| OQ-6 A（golden 三件套门值） | KD-7 三门 + XCTSkipUnless 门控 | AC#6 | ✓ |
| OQ-7 A（inputShortEdge additive） | KD-1 additive optional + `==` 新行 + 五 profile nil 零漂移负测 | AC#7 | ✓（constructor 破面单文件 + 测试构造点同批修已预申明） |
| D-1（不占 iop 槽位） | 零 diff 清单含 V50Order/Registry/DrtRecord/pixelpipe 面 | AC#8 | ✓ |
| D-2（三门 typed 永不 all-ones） | KD-4 两守卫 + KD-5/KD-3 typed 面 | AC#9 | ✓（含 NaN 路径，§2 复算） |
| D-3（Core 纯函数） | DepthMaskPipeline.swift 落 Core + LAYERS 直驱 | AC#10 | ✓ |
| D-4（静态形状 + spike 亲核） | T1 spike 先行 → T3 钉值实现 | AC#11 | ✓（方向性预承诺见 m2） |
| D-5 + 许可（零新 SPM + Apache-2.0 全链） | Project.swift 依赖面零 diff + zip 随行三件 + NOTICE 署名 | AC#12 | ✓（zip 清单断言之家见 m4） |
| 基线对账 | T8 定向轮 + zh-audit +7 | AC#13 | ✓（bundle CLI 名见 m1） |

五条低分叉裁决（D-1..D-5）与 CONTEXT 裁决记录（OQ-1..7 全 A 同批生效）逐条可追溯，无重开、
无漂移。

## 4. Minor（7 项，带处方；执行批同批采纳）

- **m1（bundle CLI 名拼写）**：`Scripts/test-direct.sh :165` 的合法名 = `Layers / Library / App`；
  plan 纪律节、T8（「`--bundle LAYERS/LIB/APP` 全绿」）与 AC#13 书写的 `LAYERS/LIB/APP` 是
  BUNDLE-MAP 域标签，**直接照抄会 `error: unknown bundle` 快速失败**。处方：执行与验收一律写
  `--bundle Layers / --bundle Library / --bundle App`；plan 文本不改（本报告为勘误正本），
  DECISIONS 注记一行。
- **m2（读回头校验方向性预承诺）**：KD-5「头校验 w==518/h==396」把 (H,W) 方向写死，而
  D-4/T1 spike 才钉 mlpackage 的真实方向（NOTES 仅记「518×396 固定形状」，未辨 H/W）。
  处方：T4 读回校验消费 **T1 spike 钉死的 (H,W) 单源常量**（与 DepthSession 同源），不字面
  写 `w==518 && h==396`；AC#11 的「静态形状 518×396」按 (long,short) 对解释不变。
- **m3（产线 isfinite 守卫缺位）**：Lumen `selection.py:67-68` 的 isfinite 守卫在 plan 里只
  出现为 golden **测试断言**（KD-7），DepthSession 输出腿（KD-3）无产线守卫。NaN 输入目前
  会穿透守卫 (a)（NaN 比较恒 false）落守卫 (b) → typed `noDepthStructure`（红线不破），
  但归因失真。处方：DepthSession 前向写出前加 `isfinite` 全查（Lumen :67-68 同型），不过
  即 typed `inferenceFailed`——与「noDepthStructure 保留给真平坦深度」语义正交，一行成本。
- **m4（zip 内容清单断言之家）**：AC#12「zip LICENSE/NOTICE 清单断言」未指明落点；zip 在
  仓外机器位，LIB 无门控单测不可见。处方（二选一并落 DECISIONS）：①build 脚本自检步
  （zipinfo 清单断言，缺件 exit≠0）+ DECISIONS 记录输出；②env 门控（资产在场 XCTSkipUnless）
  测试经 `/usr/bin/zipinfo`/`unzip -l` Process（Lensfun 先例形）读清单断言。
- **m5（T3 三腿路由负测的可观测性）**：资产缺席时三腿错误帧同为「profile assets absent」
  无 culprit——error 形状分辨不出腿。处方：路由钉 = (a) `family` 判别式六 profile 穷举单测
  （T1 已列）+ (b) env 门控真模型 open 形状断言（depth open 响应 `tileEdges/scale` 恒 nil，
  enhancement open 恒带——两腿 open 响应形状互斥可观测）；无资产轮只钉「无 culprit + 不耗链」。
- **m6（两级靶 fixture 参数）**：近区面积 ≤5% 时 percentile-95 落回远灰阶 → high=0.2 →
  守卫 (a) 触发，golden 误入负测分支；严格两级平面无带内像素，「窗过渡带位置」断言在两级靶
  上空转。处方：fixture 近区面积 ≥10%；过渡带断言由斜坡 fixture 承载（plan T2 已有
  「斜坡单调 + 窗带拐点 ±半格」，将 KD-7 第三断言的数据源显式归到斜坡件即可）。
- **m7（HEADLESS import 白名单措辞 + AC#3 grep 门精确化）**：AIWorkerEnhancement 实际
  imports = Foundation/CoreML/ImageIO/**LightamerCore**（ModelAssetManifest/ModelLocator 所需）；
  DepthSession 同需求，KD-3「only Foundation/CoreML/ImageIO」字面不完整（T3 grep 门「无
  SwiftUI/AppKit」本身正确）。AC#3「MLModel 构造点仅在 worker session 文件」需排除既有
  `SemanticEngine.swift`（Core 的 InProcessMLModelRunner，retained-as-test-fixture，产线
  构造点仅 AIWorkerMain :277 亲证）。处方：import 白名单补 LightamerCore；AC#3 grep 门
  表述为「App target 产线构造点仅在 AIWorkerMain/AIWorkerDepth/AIWorkerEnhancement 三文件，
  Core 既有 InProcessMLModelRunner 面零新增」。

## 5. Obs（6 项，登记不修）

- **o1**：BUNDLE-MAP 行合计（LAYERS 401 / LIB 618 / APP 695）与运行期终值（394 / 619 / 704）
  存在既有漂移（M4-1/M4-2 未全量回更增行记录）——非本 plan 引入；T7 只按「新文件增行」对账
  即可，触达 bundle 的行级 reconcile 可选。
- **o2**：KD-1「family 穷举互斥，编译器背书」——编译器背书的是 **exhaustiveness**（枚举
  switch）；互斥性靠谓词优先序（clip 先判）+ 六 profile 穷举单测钉。建议 family 计算属性
  doc comment 写明优先序，防未来双标记 profile 静默归 clip。
- **o3**：守卫 (a) 先抛使 Lumen `max(high−low, 1e-6)` 分母地板为死代码（保公式逐字节同构，
  无害）——DECISIONS 注记一行即可。
- **o4**：估测带 +26..32 偏紧：按 T2 清单（percentile ≥5 锚 + 靶 3 断言 + 斜坡 + 窗带 +
  双负测 + 纯函数性/参数扫描）+ Editing ~7 + LIB ~6 + APP ~9 望落在 30-40。估测漂移按惯例
  处理（M4-1 先例 +102 vs 申报 +75..85），T8 以实数对账。
- **o5**：`Tests/Fixtures/DepthPrecision/` 的 ref-f32.bin ≈0.8MB×≥4 件 ≈3.3MB 入 git——
  fixture ≠ 模型字节，红线不触；体积注记进 fixture README。
- **o6**：hf fallback rung 对 depth 是 **provenance 面**而非功能镜像：digest 锁的是 Release
  zip 字节，HF 直链（mlpackage 目录 resolve）即使可达也几乎必然 checksumMismatch typed
  fail-closed——与 jina 档同形、属 D-M2-10-CONTEXT-7 既有架构；T8「404 → allSourcesFailed
  无半态」表述与实测行为一致，无需动作。
- （附注）M4-1 挂账 #6（Export→App 跨 bundle 孤儿 `.lra` 轮间污染）对 T8 无扰：定向
  Layers/Library/App 轮不跑 Export 即无污染源；若收口轮跑 `--all`，脏树第二轮 App 可能
  704/0/1，按挂账 #6 口径解读，不计本批失败。

## 6. 测试对账与机检面

- 四个新测试文件归置：DepthMaskPipelineTests/DepthMaskEditingTests → LightamerTestsLayers、
  DepthGoldenTests/DepthWorkerLegTests → LightamerTestsApp——与 AIMaskEditPathsTests（LAYERS
  实例化 App 级 coordinator 先例）和 AIWorkerClientTests（APP）一致；Project.swift 显式清单
  追加 + `tuist generate` 尾闸（L041）流程在案。
- 基线 3335/16/0 亲证（M4-1-VALIDATION）；定向三 bundle 起点确认 Layers 394 / Library 619 /
  App 704；+26..32 增量对账口径清晰；模型在场门控 XCTSkip 不进 0-fail 门的处理与 M2-5
  探针惯例一致。
- 红线零 diff 面全部可机检（文件清单在盘亲证）；`AIWorkerProtocol.swift` 零 diff 断言 =
  `git diff` 单文件机检；「仓内零模型字节」= `.gitignore` 既有段 + 产物仓外路径，可机检。
- 双重验收编排（zcode PASS → 串行 omp，config `dual_acceptance = true`）与 M4-1 同款，无
  并发违规形态。

## 7. verdict

**PASS / 0 error + 7 minor + 6 obs** —— plan 可进执行；m1..m7 处方由执行批在对应任务
（m1/m5/m6→T3/T8，m2→T4，m3→T3，m4→T1/T8，m7→T3）同批采纳，采纳情况在 SUMMARY 里
逐条回勾；o1..o6 登记 DECISIONS 即可。
