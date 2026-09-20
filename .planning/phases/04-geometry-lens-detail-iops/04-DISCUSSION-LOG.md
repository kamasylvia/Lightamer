# Phase 4: Geometry, Lens & Detail iops - Discussion Log

> **Audit trail only.**

**Date:** 2026-09-20
**Phase:** 4-Geometry, Lens & Detail iops
**Mode:** 保活巡检自动推进（YOLO 授权延续；与 Phase 2/3 同模式）

---

## 过程

- 巡检触发，用户离线未应答灰色地带 multiSelect（延续 Phase 2/3 模式）。
- 处置：自主定稿，重点拍板 ROADMAP 遗留 open decision（Lensfun C++ vs XML-data-only）。

## 决策摘要

| 域 | 决策 |
|---|---|
| 镜头校正 | 三层：CIRAW 内嵌直通 + 手动滑块 Metal warp + Lensfun XML 只读（数据不入 git，后置）|
| crop/rotate 语义 | 显示窗口变换（ROI 前向收缩），不实际裁内存；记入 history sidecar |
| local contrast | 复用 03-05 EIGF/guided filter（clarity 标准路径），不新写双边 |
| sharpen/highpass | USM 变体（GaussianBlur 复用）|
| equalizer | 复用 toneequal CorrectionLUT 模式 |
| ROI 协商 | crop 前向收缩 + detail 后向扩展——PipeCacheKey.roi 首次实际生效（架构验收核心）|
| 交互 | EditorMTKView overlay 手柄 + Vision framework 自动水平检测 |
| deferred | liquify/retouch → Phase 6；Lensfun C++ → 永不（依赖红线）|

## 04-01-T0 ROI 协议定稿（2026-09-20，executor 确认三件实施口径）

- **口径 1（D-G2 读法）**：按 04-01-PLAN T0 实施——ROI 协商收缩，下游平面按窗口尺寸原生分配（无全幅 buffer、无窗口拷贝浪费）。
- **口径 2（roiHint 形状）**：`RenderPipeline.process(roiHint: ROI? = nil)`，nil = 全幅；Phase 4 仅测试/探针面，UI zoom-ROI 另议。
- **口径 3（验收口径）**：SC#4 四断言为本 plan all-green 闸门 + `04-VALIDATION.md` Wave 1 行签核；04-02..04-05 以本 plan 全绿为开工条件。
- **dt 依据**：前向 `pixelpipe_hb.c:3368-3405`（get_dimensions，直通分支 `:3378-3384`）+ 后向 `pixelpipe_hb.c:2085-2096`（递归体 modify_roi_in + processed_roi_in/out 盖章）；crop 实例 `crop.c:517-531`（out 收缩）/`:576-592`（in 偏移回取）。
## 04-02-T0 crop 编辑 live 语义定稿（2026-09-20，executor 采纳 plan 推荐 (a)）

- **决策：(a) live disabled + 暗膜**——拖动中 `setLiveParams(crop enabled=false)` 全图渲染，overlay 画暗膜 + 矩形手柄；commit 才渲裁切窗口一次。
- **理由**：crop 拖动每 tick 改 roi → ≤crop 全链键变 → 全链 miss（04-RESEARCH §1 gotcha，dt 同样）；整幅平面全程缓存命中保 60fps，与 C1/Lr「编辑时全图」交互一致。
- **影响**：overlay 实现含暗膜态（T4）；`setLiveParams` 快照带 `enabled=false`，`commitContinuousEdit` 带 `enabled=true` 最终 rect。
- **回退**：用户改选 (b) 则 T4 改写 + 注记每 tick 全链重渲（PREVIEW 档可扛，与 PERF-5 叠加）。
## 04-03-T0 rotate/perspective 模块身份定稿（2026-09-20，executor 采纳 plan 推荐）

- **决策：(1) 单一 `ashift` op**——一个实例、面板两个区块（旋转/透视），内嵌裁切位默认全幅；v50 槽位 15.0（`iop_order.c:319` `{15.0} "ashift"` 实测确认：rotate 在 crop 24.5 之前 ✓）。
- **决策：(2) 透视交互 = (a) 参数面滑块 + Vision 自动检测填充**——4 角手柄 defer Phase 6（liquify 顶点交互基建复用）。
- **决策：(3) EXIF 方向分工**——90° 步进由 flip（04-02）承担；ashift 只管微调/透视。
- **理由**：与 dt 槽位 15.0 语义对齐；单应统一旋转/透视同一 kernel；sidecar 持久化身份一次性定稿（事后改 = 格式迁移）。
- **执行裁决（plan 未覆盖，见 04-03-DECISIONS.md D1–D9）**：mode 锁定 GENERIC；uniforms 走 setBytes per-run（单应依赖 bufIn 尺寸）；前向补 `dscOut` 盖章；bilinear 边框语义钉死；中性/病态→blit 恒等；种子带 ENABLED 中性 ashift；L020 帧约定注释三处钉死；Vision 经 public facade + coordinator 只读源图；符号约定以探针为准。
## 04-04-T0 Lensfun 集成口径定稿（2026-09-20，executor 采纳 plan 推荐 + 细化）

- **决策 1（数据分发，Open Q4 采纳 plan 推荐）**：首跑下载 lensfun-data master.zip → Application Support/Lensfun/version_1/*.xml（unzip 扁平解包）；UserDefaults lensfun.customPath 可覆盖；失败/缺席 → (c) 静默缺席、(b) 照常。数据不入 git；测试钉 3 个手摘最小子集。
- **决策 2（归一化半径约定，lensfun GitHub 源码钉死）**：Hugin 畸变/TCA r=1 于半高、vignetting r=1 于像角；换算因子 NS·HW（分辨率无关，preview/full 同参同貌）；结论进 kernel 头注释。Diverge-aside：镜头 `aspect-ratio`/`center`/`real-focal` v1 子集皆无 → 缺省 1.5/0/名义焦段（落账 D-04-04-T0-2）。
- **决策 3（插值语义，lens.cpp 逐式）**：distortion/TCA = 4 点 Hermite 样条（edge 退化）；vignetting = IDW p=3.5 + exact<1e-4 + mindist>1 缺席。plan 的"三维线性"被源码口径替代（落账 D-04-04-T0-3；偏差方向相反——线性反而是大偏差）。
- **执行裁决（plan 未覆盖，见 04-04-DECISIONS.md D1–D9）**：vignette 除法语义（D1，plan 乘法字面是错的——配 XML 负 k 会越校越暗）；统一 dc1..dc4 + TCA 全 6 项多项式精确直通（D2）；复合先 D 后 TCA（D3）；出界 clamp（D4）；中性/病态→blit 恒等（D5）；EXIF 快照进 Params + process 期 resolve（D6）；L020 帧约定三处钉死（D7）；测试 XML 内联 + 子集文件双轨（D8）；URLSession+unzip 下载（D9）。
## 04-05-T0 detail 四模块口径定稿（2026-09-21，executor 采纳 plan 推荐 + 细化）

- **决策 1（luma 域，Open Q2 采纳 plan 推荐）**：Lab L（LabMath.h 融合；soften 例外 RGB 线性域）。scene-referred 纯度分歧记 intentional divergence，进各模块头（04-05-DECISIONS.md D-04-05-T0-1）。
- **决策 2（local contrast golden 口径，Open Q3 采纳 plan 推荐）**：合成 float64 公式参考 + detail=0 精确恒等门 + 内容方向断言；dt-cli 参考不可用（D-G3 必然代价）。
- **决策 3（equalizer 高斯带，Open Q8 采纳 plan 推荐）**：v1 纯高斯带，不接 edge-aware 权重；偏差注记；EIGF 接入作 stretch（未做）。
- **执行裁决（plan 未覆盖/勘误，见 04-05-DECISIONS.md D1–D11）**：模块清单以 plan 文件为准（5 ops；任务书 parenthetical 的 cacorrect/cacorrectrgb 按 plan 不交付——Bayer 域不可移植 + lens TCA 已覆盖，defer）；sharpen σ = radius×scale（commit 2.5× 往返抵消）+ amount=0 默认（plan"默认 0 中性"实为 amount 快路径恒等；dt $DEFAULT 2.0/0.5/0.5 勘误）；highpass 两参无 center/radius（plan 三参字面勘误；CL mix 腿为准）；box-mean 模块的 blur 基座取 dt σ 相关式 + IIR 合成镜像（D4）；soften mix = amt·blurred+(1−amt)·in + dt-cli probe 免跑先验结论（D5）；EIGF 腿 no-mask 单迭代 + sigmaR→feathering 映射自定（D6）；ROI halo vs tileHalo 双常数分工（D7）；equalizer 只跑 L + 全零 blit 恒等（D8/D9）；XMP 范围（D10）；seeds（D11：sharpen/bilat/equalizer enabled 中性，highpass/soften disabled）。
