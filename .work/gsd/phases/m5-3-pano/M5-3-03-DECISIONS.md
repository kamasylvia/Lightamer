# M5-3-03 DECISIONS — 全景 UI 与收口批（wave 3）偏差与定案正本

> 执行批 2026-10-16（夜间全自动授权「开跑，不要停」在案）。规格 =
> M5-3-03-PLAN.md + 派发注记「checker 回注 5 minor 同批采纳，照办勿疑」；
> 本文件 = 执行期偏差/定夺/落点正本（§1-§6）。事实基础亲核：
> 五 minor 原文 = `M5-3-CHECKER.md`（minor-1..5）；采纳落点分账先例 =
> `M5-3-02-DECISIONS.md` §6.1（「checker 回注」引注块在 plan 文本零命中
> ——同形转写残迹判定，本批沿用其分账结论不重开）。

## §1 派发注记五项采纳落点（照办勿疑 → 分账申报）

| 注记项 | 本批动作 |
|---|---|
| ① 03 files_modified 补 ContentView.swift | **本批 T1 落**：plan front-matter 补 `App/Sources/Lightamer/UI/ContentView.swift` 行（checker minor-1 处方原形）+ `onPano` 穿线第四段随 T1 commit `fe3fc5f` |
| ② 预览灰度双编码缝拆 encoded 入参缝 | **01/02 批已落**（01 `preparePreviewGray` rgbaLinear/rgbaEncoded 双缝 + 02 `panoPreviewGrayFromEncoded` 消费，`M5-3-01-SUMMARY` T1 段 + `M5-3-02-DECISIONS` §6.1 在案）——本批零 pano 腿触碰（G5 全域零 diff 亲证），无二次动作 |
| ③ 基线勘误链笔误 +32 正本 | **转写残迹判定**（02-DECISIONS §1 先例：「+32」字面在 CHECKER/plan 全文零命中；基线对账正本 = 02-SUMMARY 记账口径 **3623**〔+41 净增〕，其验收波实测增量 +3〔第 11 腿 straggler + E-omp-1 回归法 + Gain 14 登记差〕→ **enter-03 实测基线 = 3626**，IOP 684 亲证）——本批对账链以实测 bundle 和为锚：3539 + 43 + 44 + 5 = **3631/24/0**（`--all` TOTAL 逐位闭合），无 plan 文本需改 |
| ④ T1 真值表行数 6 非 8 | **01 批已落**（`M5-3-01-SUMMARY` T1-T4 段：「④预览降采样尺寸表 6 行（非 8）」在案）——本批零对应面，无二次动作 |
| ⑤ 02 test_bundles 口径 | **02 批已载**（BUNDLE-MAP 底部官方「M5-3-02 增行记录」五行 = IOP×4 + EXPORT×1，终态计数）——本批核对无二次动作；03 增行 = APP 1 行（PanoMergeUITests 5 法，T2 commit） |

## §2 T3/T4 主仓 commit 形态定夺：evidence 与 MANIFEST = 政策 B gitignore 路径（磁盘产物）

`.work/gsd/phases/*/evidence/` 与 `.work/gui-acceptance/` 均在主仓
`.gitignore`（M4-0 证据分仓政策 B，`db5b064`）——G4 evidence
（`evidence/opencv-structural-compare/` 三件：probe 脚本 + 原始输出 +
report.md）与 G6 MANIFEST（`.work/gui-acceptance/m5-3/MANIFEST.md`）=
**磁盘产物，零主仓 commit**（M5-2 先例亲核：`lumen-structural-compare` +
`gui-acceptance/m5-2/MANIFEST.md` 同形，`git log --all` 零跟踪历史）。
T4 的主仓可跟踪交付 = **G5 机检 transcript 落 phase 根**
`g5-redline-checks.txt`（perf.md 同位 tracked 账本先例），commit
`6699da3e`。T3 主仓零 commit（产物全在忽略路径）——任务表如实申报。

## §3 typed 三态 zh 映射面定夺（KD-3 细化）

- **双层拆分**：`PanoFailureCopy.failureKey(for:)` = 纯函数（canonical
  前缀 → 键名，nil = 透传；机检三前缀正反）+
  `failureMessage(for:)` = failureHook 消费面（键 → 静态 `String(localized:)`
  经**显式 switch** 返回——V14「动态键位一律显式 switch 返回静态键」纪律，
  零 `String.LocalizationValue(运行时串)` 查表形态；G5 §6 门零代码命中）。
- **substitution 语义**：命中时替换 canonical 短语并**剥 AppError 样板头**
  （`Invalid setting: `），保留 typed detail（`<zh 文案>: <detail>`）；
  空细节 = 裸文案。非 pano 消息逐字节透传（既有错误面零变化不变式，
  `testPanoFailureMessagePassthroughAndSubstitution` 三臂钉死）。
- **挂载点** = `mergeService.setFailureHook` 既有 toast 通道
  （`toast_hdr_merge_failed` 包装保留——Mertens FAIL 同路，KD-3 原文）。

## §4 G4 结构对照定夺（KD-5 执行面）

- OpenCV 版本 = **5.0.0** headless（uv 一次性拉取，仓外 `/tmp/m53-g4/`）；
  5.0 Python 绑定**已移除** Stitcher 组件 getter（`featuresFinder()` 等）
  与 `cv2.detail.SIFT_create`——结构探针改走两条路：①Stitcher 面可求值
  门值（panoConfidenceThresh 1.0 / registrationResol 0.6 /
  seamEstimationResol 0.1 / compositingResol −1）+ 文档化 C++ 管线段序；
  ②**Lumen 腿六段中 OpenCV 承担段的活体实跑**（computeImageFeatures2 /
  BestOf2NearestMatcher_create / HomographyBasedEstimator /
  BundleAdjusterRay + f+R refinement mask / waveCorrect /
  PyRotationWarper 全数在 5.0 可用且链级跑通：conf 2.9624 / inliers 213 /
  BA focals 2553.605/2553.503）——比 4.x 组件内省更强的结构证据。
- `apply2` 返回形态 = **2×2 展平 tuple**（[00,01,10,11]，非 4.x 的
  ndarray[0,1] 寻址）——探针首版索引即踩，一轮修正（记录供后用）。
- 结论面：七段段序一一对应；匹配/BA/波/帽门值族同源同值；增益（逐通道
  GainCompensator vs scalar min-norm）与融合/裁切（multiband+GraphCut vs
  几何羽化带+直方图栈）两处分叉 = OQ 裁决记录在案的有意 Lumen 形采纳，
  **零意外缺口**。报告正本 = `evidence/opencv-structural-compare/report.md`
  （**非门值**声明卷首；数值并记不断言）。

## §5 G5 机检形（KD-6 执行面）

十一项终验电池（transcript 正本 = phase 根 `g5-redline-checks.txt`，
commit `6699da3e`）：红线路径全域零 diff（LightamerIOP/ + LightamerCore/
+ `*.metal`，base 60aad61）⊂ 腿体/FloatTIFFWriter/ProvenanceReplay 字节
零 diff ⊂ dependencies 块零 diff（Project.swift diff = 测试登记单行）⊂
hardened 随机源 grep 零（**minor-4 处方 `\.random\(` 形已并入**）⊂
runModal 门零 ⊂ LocalizationValue 插值前缀禁形代码零（唯一命中 =
:1921 禁形文档注释）⊂ Sidecar/schemaVersion 零触 ⊂ xcstrings 尾块纯
插入（136/0）⊂ SessionBrowserView 0 deletions（菜单前两项/focus/stack
字节不动）⊂ zh-audit --check PASS（1651/1890）⊂ App 定向轮 757/4/0
（六 kind 零回归证人之一；全套拼表见 VALIDATION）。

## §6 其他定夺与申报

1. **PanoMergeUITests 5 法**（估数 +5..8 下沿）：seam nil 门 + 接线 /
   enqueue 参数映射 + defaultTag 消费 / 纯函数三前缀正反 + 非前缀 nil /
   消费面透传-替换-不漏英文 / **sibling mertens seam 共存**（OQ-7 三选项
   并存零干扰——共享 service 双 kind 实跑）。菜单「可见性 gate」的可测面
   = nil 缺省（MertensMergeUITests 同形——SwiftUI 菜单单半声明式）。
2. **测试桩腿 bump 契约** = 2N+5（stepTotal 3N+6 − decode N − settle 1，
   M5-3-02 DECISIONS §6.4 产线恒式；mertens 桩 3N+2 同构）。
3. **收口轮**：App 定向轮（T2 后，757/4/0）+ 批准全套 `--all` 轮
   （派发计划含收口轮申请 = 批准依据；运行中监视 + MEMFAIL 机检兜底，
   L077 预检 df/swap 在案）——**TOTAL 3631/24/0 exit 0**（七 bundle 全绿
   零 MEMFAIL：IOP 684/453s/7731MB · IOPParity 456/775s/7803MB ·
   Layers 466/1169MB · Library 636/617MB · Sessions 279/1626MB ·
   Export 353/6455MB · App 757/366s/2832MB；原始日志 =
   phase 根 `all-run-m53-03.log`）；对账链实测锚见 SUMMARY。
4. **双重验收待派**（config `dual_acceptance = true`，m1）：本批执行完成，
   待 orchestrator 派 zcode 独立验收（PASS 后**串行** omp 二验，严禁并发；
   可选 omp 实机 G6 取证回填——M5-2 先例），结论落
   `M5-3-03-ACCEPTANCE.md`（本批未创建——验收波产物，02 同款申报）。
5. **C 档第 3 门（Phase 签核前停）**：`M5-3-VALIDATION.md` 本批成文为
   **drafted** 态（七门全表 + 对账链闭合）；签核待 verify-work 结论给
   用户过目——GOAL-STATE 续接点如实登记。
