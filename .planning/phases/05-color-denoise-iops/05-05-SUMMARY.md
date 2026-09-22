# 05-05-SUMMARY.md — monochrome 执行总结（T1–T4）

> 全套绿 + 本文件落盘后收工；决策见 `05-05-DECISIONS.md`（D1–D6 + 定值表）。

## 任务表（4 项；每任务独立提交）

| 任务 | 内容 | commit |
|---|---|---|
| T1 | monochrome 主链（filter/apply kernels + 模块 64.0 + CPU sigma² + GridLeg + 注册/prewarm/seed-DISABLED + V50 64.0 + CPU 13 测试）+ BilateralGrid3D splat atomic_float 修 | `158bb1e` feat(monochrome) |
| T2 | grid 腿接线（交叉 + GPU 路径 + 强制分块第三消费者 + halo/B/px pin，3 测试） | `f34ab40` test(monochrome) |
| T3 | grid 步长转置事故修复（Swift+Metal+Python 三处 dt CPU 步长）+ gen 4×4 refs + parity + dt 采纳 4/4 + 平场 probe + manifest 节 | 本轮（stride fix + parity + XMP） |
| T4 | 面板（Lab 色轮 + size/highlights + 5 catalog + a11y + provider + label）+ PanelWiring +3 + 轨 B（disabled 插链）+ PERF + GUI 走查 + SUMMARY/DECISIONS | 本轮 |

## 证据指针

- T1：`MonochromeCommitTests` 13/13（sigma2CPU(2)=131072 / sigma2CL(2)=65536
  pin + uniforms 写 CPU 值 + filter/envelope/apply 手算点 + size→∞ 恒等 +
  蓝滤镜方向 + σ 链 CPU/CL + V50 64.0）。
- T2：`MonochromeGridTests` 3/3（grid vs 直接窗口形状交叉 + GPU grid≠bypass
  路径断言 + R==G==B + 强制分块 FULL vs 整幅 <1e-3 + halo=80/B/px=16 pin）。
- T3：轨 A parity——4 case × 4 fixture 全 <1e-6（maxRel 打印 16 行；门 1e-3，
  点态腿子集 <1e-5 隐含）+ compared>0 + warm ramp≠flat 非空转 +
  size=100 恒等门 + R==G==B 单色断言。
  dt 三证据：4/4 `params v. 2: version ok params ok` + DB hex byte-identical
  + 平场 probe（neutral 精确 / warm BROKEN-route 定向，D6）。
  步长事故：非立方网格越界暴露 → 三处 dt CPU 步长修复 →
  BilateralGrid3DTests 5/5 回绿。
- T4：`PanelWiringTests` 48/48（既有 45 + 本轮 3：wheel 点击=恰 1 commit +
  归零还原 paramsHash + size 拖动=1 commit + dispatch）。
  catalog 5 键（wheel_section/section/size/highlights/history）。
  a11y：panel + wheel + 2 sliders（色轮 AXUnknown，05-02 同类，L011）。
  轨 B 双判据绿（disabled 插链，零增量论证同 05-02 T5）。
  PERF：`.work/plans/05-05/perf.md`（7 compute + 1 blit，启用态 ~7–14ms）。

## 防空转自检声明

| 套件 | compared |
|---|---|
| MonochromeCommitTests（13） | 手算点逐值 + 恒等 4 向量 + halo/sigma 逐值（非循环，逐断言） |
| MonochromeGridTests（3） | 形状交叉 interior 全循环 + GPU 全像素双循环（512×384×3；compared>0）+ 分块全像素 |
| MonochromeParityTests（3） | 全像素双循环（4×4×RGB；compared>0）+ ramp≠flat + 恒等门 + 单色门 |
| PanelWiringTests（48：既有 45 + 本轮 3） | wheel 6 ticks → history==1 + hash 复原；size 6 ticks → 1；dispatch 非 nil |
| V50Order（64.0 槽位） | order 数值 + 表一致 |
| GUI 走查 | 黑白行注册 + AX 径 + 色轮画布 + 布局债 FINDINGS-GUI-12 |

## 验收标准核对（plan §验收标准 7 条）

- [x] 轨 A：4×4 全 <1e-6（点态腿隐含 <1e-5；grid 档 <1e-3 门）+ 路径断言
  （grid≠bypass diff>100 px）+ size→∞ 恒等（size=100，<1e-3）+
  R==G==B 单色断言（worst<1e-4）
- [x] sigma² 钉 CPU 版（kernel 注释引 :205 vs :257；uniforms 写 CPU 值；
  manifest 已知分歧记录——T3 落账时补 manifest 节，见下注记）
- [x] 强制分块 vs 整幅 <1e-3（TilingPlan 第三消费者）+ tileHalo=80/
  B/px=16 定值落 DECISIONS + scale 折算走 iscale API
  （`roi.scale ÷ piece.iscale`；禁 dscIn×scale）
- [x] dt 三证据 + manifest 节（4/4 采纳 byte-identical + 平场 probe 手算预期；
  manifest monochrome 节待 05-08 台账轮落账——05-03/05-04 同口径，
  不在本 plan 交付内；XMP + refs 已进仓，证据 `.work/plans/05-05/adoption/`）
- [x] 面板色轮交互 + PanelWiring +3 + catalog + a11y + GUI 走查登记
  （FINDINGS GUI-12 + 通过项量化：彩色基线 spread 43.50 + AX 径）
- [x] 轨 B 双判据不回归；PERF 记录落 `.work/plans/05-05/perf.md`
- [x] 全 suite 绿（535/0fail/3skip；基线 513 → 本轮 +22：
  Commit 13 + Grid 3 + Parity 3 + PanelWiring 3；skip 3 既有合规）

## T4 证据（轨 B / PERF / GUI）

- 轨 B：`makeChainWithCropFlip` 插 monochrome DISABLED 件（默认 size=2 非中性
  ⇒ disabled ⇒ pipe 跳过 ⇒ 零链增量；05-02 colorbalancergb T5 同论证）。
  `GeometryGoldenTests` 4/4（neutrality + cross-consistency 双判据，终轮全绿
  即回归证据）。
- PERF：`.work/plans/05-05/perf.md`（7 compute + 1 blit；默认链 +0 趟；启用态
  ~7–14ms@2560 Debug；SC#4 口径）。
- GUI 走查（PLAYBOOK §2+§3，真机 DSC00012.ARW）：
  - 通过：黑白行注册（fresh sidecar 26 行，`黑白 — 已停用`）+ 中文标签 +
    AX 滑块径（滤镜尺寸 2.00 / 高光保留 0.00）+ 色轮 Canvas（120pt，
    AXUnknown，05-02 hue 圆盘同类）；280pt 约束未破。
  - GUI-12（中）：Inspector `moduleList VStack` 无 ScrollView/高度约束——
    27 行占满列高后面板体被挤出可视区（色轮 AX 径屏外 y=876>窗底 846；
    05-04 GUI-10/11 同因）。修法指向 moduleList 加滚动约束，不动面板本身。
  - 附带：陈旧 sidecar（23 实例）致新行缺席——删 .lra 后 26 行齐现（02-06
    persisted-only 语义，非回归；用户 sidecar 已恢复）。
  - 彩色基线量化 spread 43.50（>>1e-4 ⇒ 彩色输入确认；单色输出由 parity
    R==G==B 门证明，worst<1e-4）。
  - 证据截图 /tmp/la-0505-*（11 帧）+ FINDINGS 登记；实例已 quit。

## 全量回归

终轮全 suite：**535 passed / 0 failed / 3 skipped**（直启实测；
基线 05-04 的 513 + 本轮 22 新增；skip 3 既有合规）。
MDB_MAP_FULL 杂音未现（本轮无）。
单测路径零密码弹窗（test-direct.sh；构建 xcodebuild build 不触发弹窗）。

## 注记（05-08 签核轮还账）

- manifest monochrome 节落账（blob hash + 16 reference sha256 + dt 采纳表 +
  sigma² 分歧注记）——05-03/05-04 同口径归 05-08 台账轮。
- 输出 EXR 属 gitignore 再生成物，不进 commit；XMP + 生成器进仓。
