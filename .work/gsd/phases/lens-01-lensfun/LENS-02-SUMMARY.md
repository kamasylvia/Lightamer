# LENS-02 SUMMARY — plan L2:enable/per-correction/scale/auto-apply/profile browser

> status: executed | date: 2026-10-21 | 起算基 = LENS-01 终态(6108b1d9)
> 裁决正本 = CONTEXT.md(D-LENS-1/-2/-5/-7 + X5/X6 + 红线 15 条)

## 逐任务记账

| 任务 | commit | 内容 | ΔN | 验收 |
|---|---|---|---|---|
| T1 | `cc58d643` | Params.enabled/applyDistortion/applyTCA/applyVignette(nil=true)+ gated 纯函数(resolve 后 uniforms 前单点,manual 臂同缝)+ 中性谓词 enable 臂 + 面板 §2 四 toggle + setCommittedForTesting seam | +6 | IOP 6/0/0 |
| T2 | `a5d22c70` | `lensfun.autoApply`(批唯一应用级键,默认 false)+ LensAutoApplySetting 注入式读法 + reloadDefaults 硬守卫(notApplicable 唯一生效域)+ 面板 toggle | +4 | IOP 4/0/0 |
| T3 | `5a406820` + `fix(lens02)` | LensAutoCrop(RawLab 二分 GPL 移植三件套)+ LensWarpUniforms.scale 尾插(112B stride)+ kernel ×1/scale 施于映射后采样偏移 + modifyROIIn 显式面收缩 + Params.autoScale(nil=false,**偏差 D-L2-1**)/userScale + 面板 §2.5 scale 段 + 接力 crop(siblingInstance 缝)+ LensScaleGolden(IOPParity CPU twin)+ LensAutoCropTests | +16 | IOP 7/0/0;IOPParity 3/0/0 + 7/1/0 |
| T4 | `895fa64f` | profile browser(模型+薄壳 View)+ Apply/Clear 退役(Apply 吸收进选型;Clear = lensfun 态回 manual 臂)+ detected 确认 alert(D-LENS-2 v1 面属主)+ LensfunStore.candidateRows + `panel_lens_apply_match` allowlist | +7 | App 7/0/0 |
| T5 | 本 commit | AGENTS.md 键登记(lensfun.autoApply)+ zh-audit 双 PASS(各任务随批跑)+ 键清单终表 | +0 | — |
| T6 | 本 commit | 定向三 bundle + docs | 0 | 见下 |

**ΔN 终账 = +33**(6+4+16+7)。预算 +18..28,越带 +5 申报:T3 组合(二分纯函数 7 法 + kernel golden 3 法 + ROI/接力断言)比预算密;逐方法仍单断言面。

## 定向 bundle(L2 收口轮,yM 修复后终值)

- `--bundle IOP`:**735/5/0**
- `--bundle IOPParity`:**463/3/0**
- `--bundle App`:**955/6/0**
- skip 均既有族(golden/环境门控),零新增 skip。

## 红线核验

- LensKernels.metal diff = scale 采样一处 + struct 尾插 + 头注释(半径约定/求值序零改)✓
- crop_bounds/CIRCLE 零命中 ✓;UserDefaults 恰一键 lensfun.autoApply + reader 恰一消费点 ✓
- LensAutoCrop GPL 头三件套 ✓;scale=1 恒等 golden(track-A EXR 复跑 + CPU twin)✓
- xcstrings 尾块纯插入 ✓;detected/unknown auto 硬守卫双负例 ✓

## 指针

- DECISIONS = `LENS-02-DECISIONS.md`(D-L2-1 autoScale 默认偏差 + D-L2-2 环境 flake + D-L2-3 ROI 面语义 + Clear 终形 + 键清单)
