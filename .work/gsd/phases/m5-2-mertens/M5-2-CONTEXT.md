# M5-2 CONTEXT — IOP-HDR-06 Mertens 曝光融合 research（discuss/research 起草批，2026-10-09）

> Phase = M5-2（ROADMAP §Milestone 5 M5-2 行：免 CRF 估计的快速 HDR 合并第二
> 模式 + 多档 deghosting；与 Robertson02（IOP-HDR-01）互为合并选项；输出 32f
> 进 IOP-HDR-04 既有管线；参考 `lumen/merge.py` MIT 模式借鉴）。本文 = 研究定
> 稿载体 + **C 档第 1 停裁决面**（OQ-M5-2-1..7 交用户；全带推荐，用户可随时推
> 翻）。读解正本 = 同目录 `RESEARCH-NOTES.md`（§ 引用见各条）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。

## Phase Goal（ROADMAP 原文锚定）

Mertens 曝光融合第二 HDR 合并模式：无 CRF/无 EV 元数据依赖、内容驱动权重
（对比度/饱和度/曝光拟合）+ 拉普拉斯金字塔多频段融合；多档 deghosting；与
Robertson02（IOP-HDR-01）互为合并选项（用户按素材择用）；复用 Phase 8
StackMergeService 骨架 / MTB 对齐 / 行带流式 / provenance 面。验收形态 =
golden 对照（Mertens 权重域）+ 与 Robertson02 选项共存不回归 + 走查。

## 决议（D-M5-2-N，均带推荐；最终裁定 = 对应 OQ）

### D-M5-2-1 算法本体与借鉴边界（RESEARCH §1/§0）

- 推荐**自实现 Mertens 2007**（纯 Swift 纯函数，论文公开算法 + OpenCV 行为锚
  `createMergeMertens(1.,1.,1.)` 常数缺省）；**OpenCV 零入仓**（零新 SPM 红线）。
- Lumen 借鉴限：deghost 三档表 + 分位亮度映射 + 融合前参考置换语义
  （**MIT，成段移植带归属注记**——与 GPL 参考仓不同级）；对齐不借鉴（MTB
  已覆盖 bracket 场景，SIFT/ECC 属 M5-3 PANO 面）。**最终裁定 = OQ-M5-2-1。**

### D-M5-2-2 输出域形态（RESEARCH §3.4）

- 推荐**形态 A：产物 = display-referred [0,1] 的 32f TIFF（无 ICC）**，下游
  走 M4-1 已交付 raster ingest 链（无 ICC float32 → sRGB 判定 → 逆变换 →
  sceneLinear）——零新机制；provenance kind = 域判别器。
- 被否形态：伪辐射重映射（融合已压缩 range，逆映射 = 半假 HDR）；双产物
  （磁盘/UI 双倍负担）。**最终裁定 = OQ-M5-2-2。**

### D-M5-2-3 deghosting 档位面（RESEARCH §2.2/§3.5）

- 推荐**四态：off / low / medium / high，默认 medium**（Lumen 三档表
  `low(.20,2) / medium(.12,5) / high(.065,9)` 移植 + off = Robertson02
  `deGhost:false` 对偶）；机制 = 分位亮度映射残差 + 可用门（裁切帧非运动
  证据）+ 膨胀羽化 + 融合前参考置换。
- v1 UI 不弹档位面板（默认 medium 起步，Lumen 同形），选择器挂 advanced
  面账。**最终裁定 = OQ-M5-2-3。**

### D-M5-2-4 与 Robertson02 的 UI 关系（RESEARCH §3.5）

- 推荐**互为合并选项**（ROADMAP 已裁语义）：HDR 合并入口扩两菜单项——
  「HDR 合并（Robertson02）」= 现行为原样默认、「HDR 合并（Mertens 快速）」
  = `.hdrMertens` enqueue；tag 分账（`_hdr` / `_mertens`）；不做自动择优
  （素材元数据质量判定面无可靠信号）。**最终裁定 = OQ-M5-2-4。**

### D-M5-2-5 预检语义（RESEARCH §3.2）

- 推荐**Mertens 腿免 EXIF EV**：extent 一致 + N≥2 硬门；aperture/ISO 差异 =
  warning 不拒绝（与 Robertson02 严格预检的分叉点——免预检正是本模式价值）；
  EV 有则记 provenance 不消费（08-3 stack 族 flat-zero 先例同形）；曝光比
  运行时自检豁免（`exposureRatioVerified` 全 true 占位）。**最终裁定 =
  OQ-M5-2-5。**

### D-M5-2-6 融合工作域与金字塔/内存形（RESEARCH §1/§3.3/§4）

- 推荐**工作域 = sRGB piecewise display 编码**（M3-1 `LutEncodingCatalog`
  曲线族现成，Mertens 权重语义即 display 域定义）；金字塔层数 = 分辨率自适应
  （最小边 ≥ 32px 封顶，focus-stack `defaultPyramidLevels=5` 起步锚）；
  band-outer + halo 流式（`defaultHaloRows=32` 先例，halo 随层数缩放回归钉）；
  staged 磁盘 N×16B/px，预算走 ru_maxrss 机检 8G 门（不移植 Lumen 全帧式）。
  **最终裁定 = OQ-M5-2-6。**

### D-M5-2-7 golden 门定义（RESEARCH §5）

- 推荐**六门**：G1 双跑 bit-identity / G2 Float32 vs Float64 孪生 parity
  （实测收窄钉门）/ G3 合成语义靶四件（双帧恒等 / 鬼影构造 / 权重零化 /
  halo 不渗）/ G4 Lumen 跨实现结构对照（非逐位，仓外一次性，不作门值）/
  G5 Phase 8 共存零回归（既有路径逐字节不动）/ G6 走查 Manual-Only。
  **最终裁定 = OQ-M5-2-7。**

## 交付切分建议（RESEARCH §6；OQ 裁决后 plan 期细化）

估 2 plans：01 = MertensFusion 纯函数族 + MergeKind/Params/provenance
additive + runMertensLeg + G1/G2/G3/G5 → 02 = UI 两入口 + zh 键族 + 域判别
回归钉 + G6 走查 + perf 探针。执行分工照 Phase 执行模型（omp 执行 + subagent
验收；config `dual_acceptance = true` 双重验收）。

## Open Questions（OQ-M5-2-1..7，每条带推荐）

### OQ-M5-2-1 算法实现边界
- **推荐**：自实现 Mertens 2007（OpenCV 零入仓）；Lumen MIT 语义移植带归属
  注记；对齐复用 MTB 不借鉴 SIFT/ECC。
- 备选 A：引 OpenCV/第三方 Swift binding——违背零新 SPM 红线（不推荐）。
- 备选 B：只读论文重写、零 Lumen 段移植——常数表/置换语义重造轮，MIT 下无
  必要（deghost 表与置换式是 Lumen 实测调优值）。

### OQ-M5-2-2 输出域形态
- **推荐**：形态 A display-referred [0,1] 32f TIFF，M4-1 raster ingest 链
  衔接（零新机制；kind = 域判别器）。
- 备选 A：伪辐射重映射进 scene-referred——半假 HDR + DRT 双重压缩风险
  （不推荐）。
- 备选 B：双产物落盘——负担无场景（不推荐）。

### OQ-M5-2-3 deghosting 档位与默认值
- **推荐**：off/low/medium/high 四态，默认 medium；v1 无档位面板（advanced
  挂账）。
- 备选 A：默认 off（更「所见即所得」但真 bracket 场景鬼影裸奔——Lumen 缺省
  medium 为实测锚）。
- 备选 B：两态 off/on——档位表是 IOP-HDR-06「多档」原文承诺（不推荐）。

### OQ-M5-2-4 与 Robertson02 的 UI 关系
- **推荐**：互为选项（两菜单项，Robertson02 保持默认一键位；tag `_mertens`
  分账）。
- 备选 A：单一入口 + 对话框选算法（多一步交互；现有一键路径被扰动）。
- 备选 B：Mertens 替换 Robertson02 默认位—— Robertson02 是真 HDR 输出唯一
  路，不可退位（不推荐）。

### OQ-M5-2-5 预检语义（免 EV 面）
- **推荐**：免 EV——extent+N 硬门，aperture/ISO 差异 warning 不拒，EV 仅
  provenance 记录。
- 备选 A：沿用 Robertson02 严格预检——与「免 CRF 快速」定位自相矛盾（拒绝
  无 EXIF 素材 = 模式价值归零，不推荐）。

### OQ-M5-2-6 融合工作域与金字塔/内存形态
- **推荐**：sRGB piecewise 编码域 + 层数自适应（≥32px 锚）+ band-outer halo
  流式 + ru_maxrss 8G 机检门。
- 备选 A：gamma 2.2 简编码——曲线族里现成 sRGB 不用而另写（无收益）。
- 备选 B：log 域融合（arri_logc4 现成）——权重语义（0.5 中心曝光拟合）在
  log 域失义（不推荐）。

### OQ-M5-2-7 golden / 确定性门定义
- **推荐**：六门（G1 bit-identity / G2 孪生 parity / G3 合成靶四件 / G4
  Lumen 结构对照非门值 / G5 共存零回归 / G6 走查）。
- 备选 A：G4 升格为数值门——OpenCV 内部常数未冻结，逐位不可达，强作门 =
  假门（不推荐）。
- 备选 B：砍 G3 鬼影构造件——deghost 是本模式主卖点，无靶不可验收
  （不推荐）。

## 验收形态（ROADMAP M5-2 行兑现路径）

- OQ 清零 → 用户裁决回批（C 档第 1 停兑现处）→ plan round（M5-2-01.. 起）。
- SC 数字门 = plan 期定；全套 `--all` 轮照批准制 + 8G 运行门（AGENTS 资源
  监控节）；合成族测试落域照 BUNDLE-MAP 规则 + `tuist generate` 恒末位（L041）。
- 红线自证惯例：零新 SPM / 密封面零 diff 清单（Lut3d/Film/Sidecar schema/
  History 等）/ V50Order 零触（本 phase 不入 iop 链——合并服务面非 op 面）/
  全 `.metal` 新增面申报（预期零——纯 CPU，与 Mertens 数学复杂度匹配；GPU 化
  仅当 perf 探针证伪 CPU 预算时 plan 期再议）。

## 裁决记录

（待用户回批后回填：OQ-M5-2-1..7 各项生效值 + 日期 + 回批载体。）

## 裁决记录（用户回批 2026-10-11）

**OQ-1..7 全部按推荐采纳（全 A）**：①自实现 + Lumen MIT 语义移植注记（零新 SPM）②display-referred [0,1] 32f + M4-1 raster ingest 链衔接 ③deghost off/low/medium/high 默认 medium，v1 无面板 ④互为选项两菜单项 + `_mertens` 分账 ⑤免 EV（aperture/ISO 差异降 warning）⑥sRGB piecewise 编码 + 层数自适应 + halo 流式 + ru_maxrss 8G 机检 ⑦golden 六门（bit-identity/Float64 孪生 parity/合成靶四件/Lumen 结构对照非门值/共存零回归/走查）。
