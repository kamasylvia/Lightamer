# Plan 06-03 SUMMARY — drawn mask（四形态 GPU 光栅化 + 内容锚定映射器 + mask 平面缓存 + blend mask 腿 + overlay 显示腿）

**执行**：GSD executor subagent（2026-09-23/24 夜间）。**终轮全 suite：698 tests / 3 skip / 0 fail**（基线 670 → +28；touch Tests + `xcodebuild build-for-testing` 重编复跑）。无密码弹窗（单测全程 test-direct 直启）。无 push（本地 commit 即完成态）。

## 任务完成表

| T | 内容 | commit | 关键验证数字 |
|---|---|---|---|
| T1 | stamping spike 两方案原型 + 定稿 | `30c556a` | A render-pipeline additive：精度 6.56e-07（门 1e-5）、1000 stamps @2560×1707 = **0.744ms 中位**；B compute atomic 定点：3.7e-9 但 29.5ms → **选 A**（D-06-03-T1-1） |
| T2 | GeometryPointMapper + 四几何模块点映射 + liquify 恒等预留 | `41fe1e2` | roundtrip 全绿：crop/flip 精确 0.0、ashift 1.3e-12 px、lens 1.0e-12 px、复合链 1.9e-12 px、**lens 大畸变极端档 1.0e-12 px**（门 0.1px；D-06-CONTEXT-7 降级未触发）；GPU 3×3 复合 vs 分段 walk <1e-12 |
| T3 | MaskSpec drawn payload 冻结 + sidecar round-trip + maskVersionHash + maskKey | `d8fb81b` | sidecar 往返恒等 + canonical 字节稳定（ParamsCoding sortedKeys）；v1 文档兼容读；hash 翻转矩阵（点/参数/version）；mask key 隔离（mask 编辑 → 链 HIT + mask MISS，make-closure 证明） |
| T4 | analytic kernel（ellipse/path/gradient）+ 解析 golden | `6ef19d9` | 逐像素 vs float64：ellipse 0.0/0.0/**1.34e-6**（旋转羽化带 float32 地板，分层门 5e-6）、gradient ≤3.5e-7（A&S erf）、path 0.0/4.2e-7；tile 缝 bands=4 vs 整幅 **0.0**（门 1e-6，分块计数>1 断言） |
| T5 | brush stamps（按 T1 定稿）+ eraser | `6ef19d9` | hardness 0/0.5/1 径向剖面 ≤4.2e-7；N-stamp 加法累积 1.8e-7（13 stamps 解析和）；eraser 负 flow 有符号和逐点对照 |
| T6 | mask 腿接线 + maskVersion 独立折叠 | `a94fa97` | 蒙版编辑记账：**5 hits（含 B 链 HIT）/ 2 misses（B mask 平面 + B prefix）/ 1 blend pass**；参数编辑：5 hits（含 **B mask 平面 HIT**）/ 2 misses（B 链 + prefix）——maskVersion ⊥ chainHash 双向独立（METAL-8）；内容级：mask 外 == 无蒙版合成逐字节（normal + multiply@0） |
| T7 | overlay 显示腿 + GUI 复验 | 本轮 | 真机 RAW + `-la_mask_overlay_probe`：changed pixels **288,515**，changed 区域 ΔR +65.53 / ΔG +80.39 / ΔB −35.58（黄调显著）；OFF vs OFF2 **视口逐字节相同**（确定性基线）；FINDINGS.md 落账 |
| T8 | tile 缝 + 内容锚定端到端 + 回归收口 | 见上/本轮 | tile 缝与内容锚定并入 T4/T5 套件；全量 698/3/0 |

## 交付面

- **Core/Pipe**：`GeometryPointMapper`（`GeometrySegment` affine/homography/radial/liquifyIdentity + compose + forward/inverse 归一化契约 + GPU 侧 `projectiveInverseComposite`/`lensParams`）；`Mat3D` 上移 Core（IOP typealias 保 API）；`IOPModule.pointMapSegment`（**协议本体声明** + 扩展默认，泛型派发陷阱见 D-06-03-T2-2）；`ModuleBoxing.pointMapSegmentErased`。
- **Core/Layers/Masks**：`MaskSpec` drawn payload 冻结（BrushStroke/PathForm/EllipseForm/GradientForm + MaskGroup 壳）；`stableHash()` = sortedKeys canonical JSON ⊕ StableHash；`DrawnMaskRasterizer`（缓存 plane / 渲染 / 展平 / stamps / fold / overlay API）。
- **Core/Metal**：`MaskRasterKernels.metal` — `mask_raster_analytic`（含行带 uniform）+ `mask_stamp_*`（加法混合）+ `mask_fold` + `mask_overlay_display`。
- **IOP**：crop/flip/ashift/lens 四模块 `pointMapSegment` 增量 API（几何数学留在模块侧，Core 不 import IOP）。
- **Sidecar**：`SidecarMaskSpec.drawn` optional 追加（decodeIfPresent 非破坏）。
- **Driver**：`LayerCompositeDriver` mask 腿（hasMask + mask 纹理）+ blendTripleHash 折叠真实 maskVersionHash（placeholder 退役）。
- **App（DEBUG）**：`-la_mask_overlay_probe` 显示腿 probe（静态 UUID 蒙版层，不入用户状态）。

## 实测数字（详表）

- 映射器精度表：见 GeometryPointMapperTests 输出（`[06-03 T2]` 前缀，81 点网格/形）。
- 光栅化解析表：见 DrawnMaskRasterTests 输出（`[06-03 T4/T5]`/`[06-03 T8]` 前缀，compared 8192–19200/形）。
- GUI 量化：见 FINDINGS.md「Plan 06-03 T7」节。

## 决策与勘误（正本 06-03-DECISIONS.md）

- D-06-03-T1-1 stamping = render-pipeline additive（数字对比）。
- D-06-03-T2-1 mapper 落位 Core + 模块侧 hook；D-06-03-T2-2 协议扩展-only 成员泛型静态派发陷阱（协议本体声明修复）。
- D-06-03-T4-1 椭圆 q 域重形式（border→0 的 0/0 与 float32 相消规避）+ A&S erf + 旋转羽化带 5e-6 分层门；D-06-03-T4-2 **176B uniform setBytes 竞态复现**（ashift D2 同根）→ 全线 MTLBuffer。
- D-06-03-T5-1 brush/eraser 语义（加法累积 + 收尾 clamp；eraser = 负 flow）。
- D-06-03-T7-1 overlay = Core API + DEBUG probe（UI 6-5）。

## 验收标准对照

- [x] stamping spike 定稿落 DECISIONS（数字对比 + 选型）；正式实现按定稿方案
- [x] GeometryPointMapper：四几何模块 + 逆序复合 + roundtrip ~1e-12 px（门 0.1px）+ liquify 恒等预留；降级未触发
- [x] drawn 四形态 golden：ellipse/path/gradient 解析 ≤1e-6（旋转羽化带 1.34e-6，分层门 5e-6 有据）+ brush 三档剖面 + eraser 定稿
- [x] mask 平面缓存（maskVersionHash 折叠）+ 蒙版编辑链零重算记账 + sidecar round-trip
- [x] mask 腿接线：无 mask 常量路径 + 有 mask 三元组生效（LayerCache/LayerComposite 回归绿）
- [x] overlay 显示腿 GUI 复验量化（FINDINGS.md）；tile 缝 <1e-6（实测 0.0）；内容锚定端到端断言
- [x] 全 suite 绿（698/3skip/0fail）；每任务独立提交；SUMMARY + DECISIONS 落盘

## 遗留 / 风险

- **旋转羽化带 float32 地板**（1.34e-6，门 5e-6）：如未来需 <1e-6，需 double 仿真或 CPU 折叠——当前画质无感。
- **lens 大畸变极端档**单测以 k1=−0.35/k2=0.10 记录证据；更极端系数（非线性区）走 D-06-CONTEXT-7 降级评估流程（未触发）。
- **MaskGroup combine**（多形态并/交/差/异或）与 parametric/raster = 06-04；本 plan 光栅化首个 analytic 形态 + 全部 brush strokes 累加。
- **overlay UI 开关**（选中层「显示蒙版」）与 MaskToolbar 交互 = 06-05（Manual-Only register 挂账）；本 plan 渲染腿 + probe 就绪。
- 既有 GoldenColor flake（L018 类 CI 腿，0-2 浮动，单跑绿）沿用 06-01 挂账，本轮终轮未复现。
- 每任务独立提交 7 枚（30c556a / 41fe1e2 / d8fb81b / 6ef19d9 / a94fa97 + T7/T8 收尾）；勿 push（本地 commit 即完成态）。
