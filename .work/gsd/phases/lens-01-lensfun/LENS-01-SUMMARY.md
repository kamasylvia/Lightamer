# LENS-01 SUMMARY — plan L1:互斥三态探测 + 匹配硬化 + 匹配移出 process 期

> status: executed+accepted | date: 2026-10-21 | HEAD 起点cb2cb5e8 → 终点 = 本文件 commit
> 裁决正本 = CONTEXT.md(D-LENS-1..8 / X1..X4 / 红线 15 条);执行 = ZCode subagent(四 plan 连跑批,orchestrator 已授权连续执行 + 全套 --all 批准)

## 逐任务记账

| 任务 | commit | 内容 | ΔN | 验收 |
|---|---|---|---|---|
| T1 | `7f80f82a` | EXIF 字段接线核验(勘误③——零产线 diff,复用既有 focalLength35mm/lensMake)+ decodeParamsHash 覆盖核验(结论:已覆盖,见 DECISIONS)+ 手织 TIFF fixture(ImageIO 写侧丢 0xA405,探针实证) | +4 | IOP 4/0/0 |
| T2 | `00a6ac5e` | DNGOpcodeProbe(Core 纯函数,51008-51010 存在性,seek 式有界读 + 窗口语义)+ EmbeddedGeometryState(Core 单源,String-Codable)+ DecodedImage additive + 四构造点赋值(RAW 腿 DNG/非 DNG 条件分支;退役 decodeRaster + RasterDecoder 两腿 = notApplicable) | +12 | IOP 12/0/0;RasterDecodeLegTests 19/0/0 |
| T3 | `1d961771` | crop gate 复活(resolveCommitted 全参化 + resolve crop 实参 = 相机 imageCrop,review m5)+ 阈值 ≥60 分档(40 档摘除自动资格)+ 歧义拒绝(RawLab 语义)+ camera 唯一命中 + Params additive 四字段 + reloadDefaults X4 优先链折入 + EmbeddedGeometryState String-Codable | +9 | IOP 9/0/0;LensfunDBTests 15/0/0;LensParityTests 7/0/0(fixture 补 imageCrop = 硬化语义适配) |
| T4 | `e9d9ecb7` | LensfunStore 进程内 memo(键 = 匹配输入 stableHash + DB stamp;值 = 匹配结果非系数;LRU 32;打分锁外)+ scanCounter 测试观测面 | +6 | IOP 6/0/0 |
| T5 | `ed059c6e` | 面板 §1 互斥三态 + 匹配状态机 readout(LensPanelReadout App 纯模型,静态键 switch)+ refreshMatchState 真跑(matchName=key stub 退役)+ LensMatchedProfile public 面 + xcstrings 七键尾块 + zh-audit 双 PASS | +5 | App 5/0/0 |
| T6 | 本 commit | Project.swift 五文件数组(随批)+ BUNDLE-MAP 五行 + 本 docs | 0 | — |

**ΔN 终账 = +36**(4+12+9+6+5)。**越带申报**:预算 +13..18,实际 +36——越带根因 = 表驱动密度(每方法 = 一个完整断言面,非膨胀):DNGOpcodeProbe 12(双端序/SubIFD/ExifIFD/负例/畸形 5 例/磁盘面/UTI 谓词/三腿 stamp/nil 负测)vs 预算 4..6;LensMatchHardening 9 vs 4..6;LensPanelReadout 5 含冻结键集 ledger 断言。全批终值对账归 LENS-04 T5。

## 定向 bundle 全绿(IOP + App 全量)

- `--bundle IOP`:**718/5/0**(433s)
- `--bundle App`:**948/6/0**(411s)
- skip 均为既有 fixture/环境门控族,零新增 skip(probe 族归 LENS-04 T5)。

## 红线核验

- LensKernels.metal 零 diff ✓(本 plan 零 kernel 面)
- Registry/V50Order/LightamerSidecar/RenderProcess 零 diff ✓
- FIX2③ McpServerController.swift 零 diff ✓
- xcstrings 尾块纯插入(七键 append,历史键字节零触碰)+ zh-audit `--check`/`--self-test` 双 PASS ✓
- `String.LocalizationValue("prefix_\(x)")` 禁形零命中 ✓(copyKey = 显式 switch 静态字面量)
- L041 tuist generate 恒末位(每任务 commit 前)✓
- X2 边界:RAWTechnicalOverrides 结构零触碰(只核验不扩缝)✓

## 指针

- DECISIONS = `LENS-01-DECISIONS.md`(hash 覆盖核验结论 + 各裁定)
- 下一 plan = LENS-02(enable/per-correction/scale/auto-apply/browser)
