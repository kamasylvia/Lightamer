# RawLab 调研（2026-10-20，用户令「dancancer/RawLab 更新了，查新版本有什么功能我们不具备」）

- 仓库：`github.com/dancancer/RawLab`，**最新 0.8.2（2026-10-20 发布）**；跨四平台（macOS/Windows/Android/iOS）共享 C++17 核 + 各平台原生编辑器；自养 RAW 解码（LibRaw + 固定版 Adobe DNG SDK + JXL）。
- **许可证 = GPL-3.0**（+ 阿里云 RUM SDK 链接例外）→ 与 darktable/Alcedo 同类。**勘误（2026-10-20 晚，用户裁「我们也切到 GPL」）：本项目已切 GPL-3.0，RawLab 从「只读零复制」升级为「同许可合规复制可用」（保留原版权声明 + 许可证文本 + 标注修改）——UQ-R1..R6 落地时可直接参照/复用其实现。**
- 开发形态：`codex/*` 分支丛林 = AI 辅助高频迭代（0.5→0.8.2 十天五个版本）；0.8.1 起**使用统计默认开启**（RUM SDK，数据存境内）——我们不采。

## 0.5→0.8.2 功能弧（changelog 正本）

| 版本 | 新增 |
|---|---|
| 0.8.2（10-20） | **DCP 色彩 profile 直接导入**（四平台）；Nikon HE/HE* NEF、Sony ARW6/压缩 RAW2、**Sigma X3F**、JPEG 压缩 DNG 解码；新机型识别；几何视口级预览 + 全分辨率终导 |
| 0.8.0（10-17） | 桌面 Agent/CLI JSON 编辑完整化（能力发现/预览/FINAL 导出）；**裁切/旋转/摆正/翻转/透视校正**；JPEG/PNG/TIFF/HEIF 栅格输入；+29 创意 look |
| 0.7.0（10-14） | JXL 压缩 DNG 解码；**渲染 float32 DNG 导出**；六语言；**Lensfun profile 镜头校正 + 手动选型 + 自动裁切** |
| 0.6.0（10-12） | **14 主配方**（替换 6 调整 + 24 HSL，0-200% 强度同缩 LUT，风格图）；**八通道 HSL 混合器**；**一键自动曝光 + 嵌入预览曝光匹配默认**；iPad 布局 |
| README 常驻 | 线性光小波降噪（亮度/色度/粗色度三控）；暗角；确定性颗粒；**逐图编辑记忆 + 可续传批量导出**（冻结设置/取消/失败重试）；信息叠层；缩放平移 |

## 对照 Lightamer（parity-checklist 136 行 + 已知能力）

### 真缺口（架构兼容，可立项——六件）
1. **渲染 DNG 导出**（0.7.0）——我们导出矿阵六格式（JPEG/PNG/TIFF/HEIF/WebP/AVIF）**无 DNG**。可行路 = TIFF/EP 标签自写或 DNG SDK（许可待查）；用户价值 = 下游 LR/C1 可继续编辑的 baked 中间格式。
2. **透视校正（keystone）**（0.8.0）——我们有 crop/rotate/straighten/flip，**无透视**（parity 零条目）。Metal warp 自实现（dt `ashift` 算法参考）。
3. **Lensfun profile 镜头校正 + 自动裁切**（0.7.0）——我们 FEAT-DEV-07 **Partial**（仅嵌入 opcodes）；v1 立场「Lensfun 数据只读路线」至今未落。
4. **一键自动曝光 + 嵌入预览曝光匹配默认**（0.6.0）——parity 零条目；小件，UX 价值高（新片打开即近相机 JPEG 观感）。
5. **可续传批量导出**（冻结设置 + 跨重启恢复 + 失败重试）——我们导出队列有 retry（M2-9），**无跨重启续传**。
6. **主配方系统**（多调整 + HSL 打包预设 + 0-200% 强度缩放 + 风格图）（0.6.0）——我们预设面 = LUT 库/导出预设/复制粘贴，**缺「调整包 + 强度缩放」形态**（Alcedo 亦无此面）。

### 架构不可达 / 不适用（CIRAW 路线下 N/A，不计缺口）
- **DCP 外部 profile 导入**（0.8.2）——CIRAW 不接受外部 DCP（FEAT-DEV-04 既定 out-of-scope，与 Alcedo 同）；要做须自建色彩管线 = 弃 CIRAW 地基。
- Nikon HE/HE* NEF、Sony ARW6、Sigma X3F、JXL-DNG 解码——解码覆盖由 Apple 决定（他们自养解码器才有此自由度）。
- 跨平台四端——我们 macOS 独占（项目定义）。
- 使用统计 RUM——不采。

### 我们领先面（反向，供定位）
MCP 32 工具 + turn-taking（其 Agent JSON 0.8.0 才完整，无 MCP）；AI 图库全家桶（CLIP 语义检索/打标/评片——其 0.8.0 明示「AI 不在本版」）；HDR/全景合并；DRT/ACES 显示变换 + EDR；WebP/AVIF/UltraHDR 导出；版本/stacks/culling；100MP 性能目标。

## 处置建议（待用户裁）
- **GPL-3.0 可加入参考项目**（第七个；只读纪律同 darktable/Alcedo）：价值点 = 透视校正/Lensfun 数据路线/DNG 导出/配方系统四件的**实现形态参照**（C++ 核 + 四端一致性设计有可读性）。
- 六真缺口入 `research/UPSTREAM-QUEUE.md`（编号 UQ-R1..R6）待下一特性批裁；推荐优先级 = ①DNG 导出 ②透视校正 ③自动曝光（小件高感知）④Lensfun 数据路线 ⑤续传导出 ⑥配方系统。
- 本地克隆：`/tmp/rawlab-inspect`（shallow，即弃）；若采纳则正式克隆到 `/Volumes/UNITEK/Documents/Development/RawLab`。

---

## 增量节（2026-10-25 M9 charter 输入批；main +203 release/CI churn + development 0.9 真货）

> main 增量 = 0.8.0..0.8.2 发布批（四平台 CI runner 自建、iOS/Android 导入缓存与
> 批处理日志、ARW6 重建溢出拒绝、Windows Lensfun 前缀化）——平台工程 churn，与我方无关。
> **真货在 `origin/development`**（0.9 在飞，2026-10-23..26）。正本判定 =
> `M9-CHARTER-INPUT.md` §0.3/§4。

### development 分支 0.9 面（逐项判定）

- **clarity + dehaze**（`33d4a9bd`）：AdjustmentKind 加 `.clarity`/`.dehaze` 两标量 +
  AtmosphereSettings → 闭源 sony2fuji 引擎 `sony2fuji_session_set_atmosphere` API。
  **判定：排除**——我方已有 DehazeModule（dark-channel-prior，Registry.swift:448，
  Plan 08-5-T1）+ Clarity（Equalizer EIGF，Plan 04-05-T2）；上游算法体不可读（闭源
  native 引擎），无移植面。
- **AI 降噪 = DualDn Big/Restormer**（`b9e5de06` + `docs/architecture/dualdn-inline-denoise.md`）：
  RAW 四相位张量（RGGB packed 384/halo 128）+ RGB 分支（512/64）双网络；噪声参数
  k/b 传感器标定（Sony ILCE-7CM2 ISO 100-12800，范围外不外推）；GPU-only 无 CPU 回退；
  RGB 修正量桥接协议 v2（保护图 8px 膨胀 + smoothstep 权重）。**判定：排除（双壁垒）**
  ——①许可：DualDn = CC BY-NC 4.0、Restormer = Academic Public License（`77dce309`
  AGENTS 明示），均禁商用，开源再分发违约风险；②架构：需解包 Bayer 原始 + 黑白位 +
  CFA，CIRAWFilter 不暴露（我方「不写 RAW 解码器」约束）；我方 RAW 9 NE 融合降噪 +
  DenoiseProfile（dt 移植）已覆盖。**噪声标定方法论（k/b per-ISO 传感器实测 + 不外推
  纪律）注记为质量参考**——DenoiseProfile 后续增强可借鉴。
- **selective adjustments**（`405ceff3` 等 6 commits 跨平台 + 会话 history + transfer
  transactions）：全局参数蒙版化局部应用。**判定：排除**——我方 layers + masks + AI
  mask 五源体系（Phase 6 + M2/M4/M6-4/lumen 批）能力超集。
- **compare 视图**：单图 before/after split（EditorView.swift:198 中性显影）。
  **判定：已有**——我方 09-04 T7 compare point + CullingView 双窗。
- **JPEG XL DNG（0.7）/ DCP import 跨端（0.8）/ 跨相机 preset roadmap**：自养解码器
  与 DCP 路线，与 CIRAW 冲突，排除；注记 DCP 路线若我方未来需要输入 profile 面再评估。
- **三区色彩分级（colorGrading）**：我方 ColorBalanceRGB + colorWheels + Hls 超集，排除。

### 可取小点（注记）

- 「Auto 直方化前 cold AI preparation」（`155439c3`）= 冷启动模型预备的测试面形态，
  我方 AIAssetStatus 同域，质量参考。
- ARW6 重建溢出/空低带拒绝（`aa9fbb15`）：CIRAW 路线无此面，注记。
