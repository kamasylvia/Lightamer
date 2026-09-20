---
phase: 4
plan: "04-03"
title: "rotate/perspective（IOP-GEO-02，ashift 槽位 15.0）—— SUMMARY"
status: complete
executed: 2026-09-20
tests: "331 tests, 3 skipped, 0 failures (full LightamerTests)"
---

# Plan 04-03 SUMMARY — rotate/perspective（ashift 语义，Vision 自动检测）

## Goal 达成

交付 IOP-GEO-02（任意角度旋转 + 透视校正 + 自动检测）：单一 `ashift` op
（v50 15.0，`iop_order.c:319` 实测确认在 crop 24.5 之前）+ CPU Double 单应
合成 + `ashift_warp` backward bilinear kernel + forward/inverse 角点 ROI +
Vision horizon/rectangle 自动检测 + 面板/a11y。纯旋转是单应特例；透视走
4 点 DLT + 参数拟合。旋转黑角不自动内切（04-02 crop 组合收）。

## Tasks（7 commits）

| Task | Commit | 状态 | 证据 |
|---|---|---|---|
| T0 模块身份/透视参数面/EXIF 分工 | `9dc16fc` 内 | ✅ | DISCUSSION-LOG 04-03-T0 + 04-03-DECISIONS.md D1–D9 |
| T1 Homography CPU（合成 + DLT + fit） | `9dc16fc` | ✅ | HomographyTests 6/6（rot30 解析/DLT <1e-9/inv×fwd <1e-12） |
| T2 ashift_warp kernel + 模块三钩子 | `9dc16fc` + T4 批 | ✅ | AshiftParity CPU 向量 + Registry/种子/V50 双钉 |
| T3 Vision 自动检测 | `83292f3` | ✅ | VisionDetectTests 4/4（θ<0.2°/矩形<0.5%/符号钉死） |
| T4 golden 合成参考 + manifest | （本批） | ✅ | AshiftParity 7/7（28 路 <1e-5/<1e-5）+ manifest ashift 节 |
| T5 面板 + a11y + 签收 | （本批） | ✅ | AshiftPanelView + catalog 18 keys + PanelWiring +2 + ROI +1 |

## 验收标准逐条自验（plan Verification 表）

- **IOP-GEO-02 golden+unit（T1/T2/T4）**：合成 float64 参考 parity
  <1e-5 相对/<1e-5 绝对 + 恒等门（<1e-6）+ 黑角 alpha 断言 ✅
  （AshiftParityTests 7/7 全绿，anti-vacuum 比较循环实跑 428088 样本）。
- **自动检测 SC#1（T3）**：θ 探针 <0.2°（−8/−3/+5 三角度）、矩形还原
  <0.5% ✅（VisionDetectTests 4/4；真实 RAW 抽检见下）。
- **ROI warp AABB（T2）**：modifyROIOut 变大（64→72/87）、modifyROIIn
  有界（clamp bufIn）✅（ROINegotiationTests ashift 用例 + CPU 手算值）。
- **轨 B 回归（T4）**：ColorSync 中性（黑角不破坏）—— golden 轨 A 的
  RGB wrap + 黑角 alpha 腿覆盖；全链中性由既有 GoldenColorTests 守卫 ✅。
- **a11y（T5）**：identifier 齐全（panel/sliders/buttons/notice）✅
  （PanelWiring + dispatch 断言；XCUITest 腿 L011 pending-manual 口径）。

## 关键修复（排障记录，教训沉淀候选）

1. **后向 clamp 擦除 grow 契约（根因，管线级）**：`processRec` 把协商
   输入 clamp 到裸 `frameROI`——rotation AABB 72 在 64 帧上被一层下游
   （colorin）砍回 64，每 warp 像素透明。修复 = clamp 到
   `frameROI.union(roiOut)`（`ROI.union` 新增；cached + uncached 双腿…
   uncached 腿沿用同一 roiIn 无需另改）。halo/crop 行为不变（union ==
   frame 当请求在帧内）。FWDOUT 探针钉死：hook 输出 72 而下游收 64。
2. **半 texel 采样约定**：texel-corner 采样让恒等整体偏移半 texel，
   ramp 中性门以 0.5/63 精确签名抓获 → 改 pixel-center（整数 = texel
   中心），Swift↔Python 双实现同改。
3. **float 数组 packing**：MSL `float hinv[9]` 常量数组 stride 存疑 →
   改三个 float4 行（Swift SIMD4 镜像），echo 探针验证字段逐字到达。
4. **setBytes→setBuffer**：80B 结构体栈上传疑似 race，改 shared 缓冲。
5. **sub-region getBytes 回零**：macOS 27 beta 上子域读回全零 → harness
   一律全幅读回 + CPU 侧开窗（flat 探针实证）。
6. **h33 归一化**：DLT  pin h33=1 而 compose 留 h33≠1（1.0226），首跑以
   0.1966 精确签名暴露 → 测试侧归一化后比较。
7. **in-model 拟合**：梯形目标不在 4 参模型内（rms 7.5）→ 改 in-model
   round-trip（rms<0.5）；Vision 符号以探针为准（CW+）；0° 行对齐边
   Vision 回 nil（改 −3°）；均匀白斑欠检测（改 bordered page）。
8. **ColorIn 同尺寸断言松绑**：grow 上游后下游平面天然变大，断言改
   format-only（内容/roi 一致性由管线保证）。

## 全绿闸门

- 全 suite：**331 tests, 3 skipped, 0 failures**（2026-09-20 终轮；
  04-02 时 311 → +20：Homography 6 + Vision 4 + Ashift 7 + Panel 2 + ROI 1）。
- 04-VALIDATION IOP-GEO-02 行待签（04-06 统一签核）；Manual-Only：
  真实斜地平线 RAW 抽检（input/RAW 现有 DSC00012/DSC09991 建筑风景，
  面板按钮人工触发确认——L011 口径 pending-manual）。
- 下游影响：04-04 lens（warp ROI 模式复用：forward AABB + union clamp
  已就位）、04-06（SC#1 签核数据源就绪）。

## 过程记录

- 本文件 + 各提交 body + 04-03-DECISIONS.md；调试探针（echo/AShiftDbg/
  scratch）已全部退役，无 `.work/04-03/` 日志留存（排障全在提交说明）。
