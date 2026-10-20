# LENS-02 DECISIONS — plan L2 裁定记录

> 正本 = CONTEXT.md(D-LENS-1/-2/-5/-7 + X5/X6);本文件只记执行期裁定与偏差申报。

## D-L2-1 autoScale 默认 = **false**(plan T3 字面「nil = true」的偏差申报)

plan T3 action 3 写「autoScale: Bool?(nil = true)」;执行取 **nil = false(auto-crop 显式 opt-in)**。理由:plan 自身的红线 12(默认中性零行为——「scale=1」渲染逐字节不变)与 LENS-04 T2 裁决预期(「scale 默认 1.0」→ 不 bump)要求默认 resolved scale 恒 1;若 nil=true,凡边框超界的 warp(pincushion 族)默认即改写 pre-L2 渲染 = 默认观感漂移 = 强制 bump。两硬约束冲突,取「默认中性」交集。**执行中途曾以 nil=true 落地并触发 track-A pincushion golden 大红(max rel 1507)——实证该偏差方向正确。** RawLab per-photo autoCrop=true 默认不采纳(其无 pre-existing 文档基线包袱)。

## D-L2-2 环境 flake 事故记录(stale-build 双容器)

T3 执行期出现 LensParityTests pincushion×checkerboard 持续红(max rel 1507/999),追踪耗时一整个调试周期;真相 = **两层叠加**:
1. **真回归一层**:T3 早期块替换把 modifyROIIn 的 `yM = max(yM, q.y)` 误写为 `yM = max(ym, q.y)`(从会话开头一次文件读取的误读复制)——yM 被 y-walk 段的低值重置(RC bug:running-max 用了 min 变量),ROI 从 62×62 缩到 62×54 → pincushion 边缘采样 clamp → 红。**已修复(commit fix(lens02)),ROI 测试 ROINegotiationTests.testLensShrinkNegotiationBoundsInput 恰好钉住此值(62)——既有测试抓到回归,门网有效。**
2. **环境层一层**:修复验证期间多 worktree 基线对照引入第二个 DerivedData 容器;`Scripts/test-direct.sh` 的容器定位 = 全局 `Lightamer-*` glob 取 mtime 最新 → **多容器并存时可能跑到非预期代际的产物**(同源码两轮一红一绿的假象来源)。**教训(LESSONS 候选):多 worktree 并行时 test-direct 必须钉 -derivedDataPath 或跑前核对容器身份;--all 轮前统一单容器重建。**

## D-L2-3 ROI 面语义(T3)

modifyROIIn 的 border map 维持 **manual 系数 G 通道**(pre-L2 语义:纯 lensfun 文档在 isNeutral 短路,ROI verbatim——lensfun 系数从不进 ROI 协商,过宽 ROI 是保守方向)。scale 收缩只作用于显式启用面(auto on / user > 1);默认(scale=1)逐字节 = pre-L2。LENS-03 T1 的投影折入将走 `roiFaceScale`/`scaleFromKernel` 的 kernel 注入点(LENS-02 T3 已泛化 edgeMap 入参)。

## D-L2-4 scale 折算语义(X5/review m6 落地)

×1/scale 施于**映射后采样偏移**(kernel:pr/pg/pb × invScale;modifyROIIn:AABB 围绕 center 收缩;edgeSample:同式)——纯视场收窄,非畸变前缩 ru。scale=1 时 invScale = 1.0f,float 乘法精确恒等(红/绿轮已双向验证)。

## D-L2-5 Clear 终形(T4)

Clear 按钮退役为**条件臂**:仅 `params.source == .lensfun` 时显示,语义 = 回 manual(保留全部存储值——lensKey/滑杆/resolve 输入不动,`LensProfileBrowserModel.clearedParams`)。Apply 不保留(语义被 browser 选型吸收;`panel_lens_apply_match` 键入 zh-audit allowlist,catalog 条目按尾块纪律保留)。

## D-L2-6 detected 确认终形(T4,D-LENS-2 v1 面属主)

browser 选型在 `embeddedGeometry == .detected` 时弹确认 alert(标题/正文/「仍然叠加」/取消);确认前 pendingSelection 挂 @State,取消 = 清 pending,params 零触。非 detected 四态(unknown/notApplicable/nil)直接 commit。

## D-L2-7 store 打分面(T4)

App 侧不能持 internal LensfunDB → 打分内移 `LensfunStore.candidateRows(search:)`(public;全库 modelScore 扫描,score>0 行,**未排序**);排序 + 低置信标注留在 App 模型(`LensProfileBrowserModel.candidates(rows:)`,纯函数可测)。plan 的「withDatabase 闭包」形态因 public/internal 边界弃用。

## D-L2-8 browser 列表与去抖(T4)

候选上限 30 行(超出显示 truncation 注记);去抖 150ms(Task.sleep,off body path);打分在 store 锁外(capture 后处理)。

## 键清单终表(T5)

新增(xcstrings 尾块纯插入,累计 21 键):
- L2-T1:`panel_lens_enabled` / `panel_lens_apply_distortion` / `panel_lens_apply_tca` / `panel_lens_apply_vignette`
- L2-T2:`panel_lens_auto_apply`
- L2-T3:`panel_lens_scale_section` / `panel_lens_auto_scale` / `panel_lens_user_scale` / `panel_lens_scale_unsupported` / `panel_lens_scale_readout` / `panel_lens_relay_crop` / `panel_lens_relay_no_crop`
- L2-T4:`panel_lens_browser_search_placeholder` / `panel_lens_browser_scoring` / `panel_lens_browser_empty` / `panel_lens_browser_no_match` / `panel_lens_browser_low_confidence` / `panel_lens_browser_truncated` / `panel_lens_detected_confirm_title` / `panel_lens_detected_confirm_body` / `panel_lens_detected_confirm_apply` / `panel_lens_detected_confirm_cancel`

复用既有键:`panel_lens_clear`(T4 重挂)/ `history_crop`(接力 commit 标签)/ `history_lens`(全部 toggle)。
UserDefaults:**`lensfun.autoApply`** 一键(AGENTS.md 键族节已登记)。

## 偏差清单

- D-L2-1(autoScale 默认)——上申报。
- ΔN +33 越带(+18..28)——SUMMARY 申报。
- yM 回归事故(引入 + 修复)——D-L2-2,修复以 fix(lens02) commit 单独落盘。
