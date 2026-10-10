# M5-1 CONTEXT — TRACK 追色族 research（discuss/research 起草批，2026-10-11）

> Phase = M5-1（ROADMAP §Milestone 5 M5-1 行：TRACK 追色族 research + 执行，
> TRACK-01..05 + MCP-09 研究项 C `match_color` 工具位）。本文 = 研究定稿载体 +
> **C 档第 1 停裁决面**（OQ-M5-1-1..8 交用户；全带推荐，用户可随时推翻）。
> 读解正本 = 同目录 `RESEARCH-NOTES.md`（§ 引用见各条）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。

## Phase Goal（ROADMAP 原文锚定）

TRACK-01 追色统计算法（参考图色彩分布特征提取 + 变换求解——Reinhard / CDF /
最优传输族择型，输出 3D LUT 或等效参数组）+ TRACK-02 多参考统计聚合 + TRACK-03
非破坏落位（`colormatch` iop）+ TRACK-04 交互 + TRACK-05 质量门 + MCP-09 研究
项 C `match_color` 编排工具位兑现。验收形态 = OQ 清零 + golden parity 门 +
确定性门 + GUI 走查 + MCP 端到端 parity。

## 决议（D-M5-1-N，均带推荐；最终裁定 = 对应 OQ）

### D-M5-1-1 求解族框架（RESEARCH §3.2）

- 推荐**三档统一统计框架**：S1 Gaussian OT 闭式线性映射（主打——Bures-Wasserstein
  闭式，`3×3+offset` 极小参数面，线性域全定义域）+ S2 per-channel CDF 匹配
  （256-entry 曲线，LUT/1D ramp 应用）+ S3 Reinhard 对角（= S1 关协方差特例，
  TRACK-01 原文点名项，实现成本 ≈0）。**非参数 Sinkhorn/离散 OT 不做**（照片
  场景收益边际 + 确定性维护负担；v2 另议）。
- strength = 解与恒等的线性插值（0 = identity），三档共用。
- 被否形态：单选一族（TRACK-01 原文「择一」按「择型交付」解释——三档共享统计
  提取与落位框架，边际成本小、语义档位齐）；agent-vision 迭代路线（TRACK-02/05
  结构性排除，2026-09-26 再确认在案）。**最终裁定 = OQ-M5-1-1。**

### D-M5-1-2 统计/应用色彩空间（RESEARCH §3.1）

- 推荐**统计域 = Oklab**（线性 Rec2020 解析直换、零外部依赖、色相线性优于
  Lab）；**应用域 = working linear Rec2020 恒等直出**（不引入应用编码转换——
  LUT 若需编码语义，M3-1 `LutEncodingCatalog` 缝现成；线性臂无 LUT 无此问题）。
- 被否形态：CIELab（dt 对齐但需 cms/自写 Lab，色相线性弱）；ACEScc（矩阵在库
  但锥响应感知均匀性弱于 Oklab，调色域语义与 Grade 族混淆）。**最终裁定 =
  OQ-M5-1-2。**

### D-M5-1-3 colormatch op 形态与 LUT 载体（RESEARCH §3.3）

- 推荐**新独立 op `colormatch`**（iopOrder 36.x 邻 lut3d；supportsBlending +
  allowTiling 同 lut3d 旗标）；**线性臂（S1/S3）参数直入 params**（矩阵+offset
  12 floats + strength + 哈希——sidecar 零负担、可手调、零 schema 升级）；
  **LUT 臂（S2）烘焙 65³ float32 走 `.cube` 派生资产位**（`.lra` 同目录派生物
  惯例参照 `.lra.masks/`；params 存 `{assetRef, stableHash}`，资产丢失 = typed
  degrade + 按哈希重解）——**不进 paramsData**（≈4.4MB base64 会让 sidecar
  膨胀失禁）。
- 被否形态：塞进 `lut3d`（lutName 语义 = 用户库文件引用，与求解器产物实例身份
  /缓存/持久化语义不同，混体面在 lut3d 密封面上开洞）；LUT 内嵌 base64
  （R5）。**最终裁定 = OQ-M5-1-3。**

### D-M5-1-4 LUT 分辨率与域端裁剪（RESEARCH §3.4）

- 推荐 LUT 臂 **65³ float32**（FilmPrintBake 先例：Float64 bake + LRU + 体素门；
  与 33³ 差异在平滑域色相保真）；域端 = **线性延拓/clamp 平台面 + 1%/99% 分位
  截尾定义统计支撑域**（M3-3 轴端平台面教训同族——本处为正向应用端，配合截尾
  实际覆盖率 ≥98%）；矩阵臂全定义域无此问题。HDR/广色域策略 = working float32
  直通 + 政策声明（TRACK-05「裁剪策略明确」= 本条 + 面板 readout）。**最终裁定
  = OQ-M5-1-4。**

### D-M5-1-5 多参考聚合语义（TRACK-02）（RESEARCH §3.5）

- 推荐**统计级加权池化**（μ/Σ 混合分布二阶矩；CDF 族 = 直方图加权合并）——
  单解、确定、权重 = 参考列表行滑杆；N=1 恒退化自然。备选逐参考 LUT/矩阵 α
  混合语义弱（混映射 ≠ 混分布），v1 不做。**最终裁定 = OQ-M5-1-5。**

### D-M5-1-6 match_color MCP 工具面范围（MCP-09 研究项 C）（RESEARCH §5）

- 推荐**最小面**：`match_color(reference, targets?, strength?, solver?, attach?)`
  ——reference = 库内 id/路径；targets 缺省当前图、数组 = 批量（逐目标独立
  求解，工具内 fan-out）；attach 默认 true = 自动落位 colormatch 实例并返回
  params 摘要 + 求解哈希。**事后微调走既有 `apply_params`，验收走既有
  `render_preview`，元数据走既有 `list_iops`**——零新增面。**最终裁定 =
  OQ-M5-1-6。**

### D-M5-1-7 蒙版 / region 支持范围（RESEARCH §2/§8-R6）

- 推荐 v1：**colormatch 走 grade 层 = 既有蒙版体系自动可用**（feather→invert→
  opacity→clamp 应用序 + combine 语义零新机制）；**参考侧统计域 = 全图**
  （参考 region 局部统计挂 V2——UI/统计双面增量，走查若有真实需求再立）。
  源图侧局部应用 = 蒙版即达（无需新功能）。**最终裁定 = OQ-M5-1-7。**

### D-M5-1-8 golden / 确定性门定义（TRACK-05）（RESEARCH §6）

- 推荐**五门**：G1 求解确定性（同输入统计 → bit-identical 矩阵/LUT；SVD 符号
  约定固定 + 整数秩统计 + 退化回落确定——FilmSolveCache 先例体例）/ G2 kernel
  parity（vs Float64 CPU 参考，p99.9 ≤1e-5 目标 + 实测带收窄钉门纪律）/
  G3 语义 golden（合成参考对恢复已知变换 ± 容差 + 自然样张目测）/ G4 MCP 端到端
  parity（Phase 14 SC#3 同型）/ G5 恒等回归（缺席/禁用/strength=0 逐字节直通，
  L031 惯例）。零新 SPM 红线复申（全站 M5）。**最终裁定 = OQ-M5-1-8。**

## 交付切分建议（RESEARCH §7；OQ 裁决后 plan 期细化）

估 2-4 plans：01 统计+S1/S3 求解器（Core 纯函数 + G1/G3）→ 02 colormatch iop
+ 线性臂 + 面板（G2/G5）→ 03 S2/LUT 臂 + 多参考 UI（若裁做）→ 04 match_color
MCP（G4；可并入 03）。执行分工照 Phase 执行模型（omp 执行 + subagent 验收）。

## Open Questions（OQ-M5-1-1..8，每条带推荐）

### OQ-M5-1-1 求解族选型与交付切分
- **推荐**：三档统一框架全交付（S1 Gaussian OT 主打 + S2 CDF + S3 Reinhard
  特例；Sinkhorn 不做）。理由：统计提取/落位/交互框架三档共享，边际成本 ≈
  各一个纯函数求解器；档位齐则 TRACK-01「择型」语义完整且用户可按素材择用
  （同 Robertson02/Mertens 互为选项的站内先例）。
- 备选 A：只做 S1+S3（最小面，S2 挂 V2）——plan 数 −1，但 TRACK-01 原文三族
  只交付两族，语义折扣。
- 备选 B：含 Sinkhorn 非参数档——不推荐（成本高、照片场景收益边际）。

### OQ-M5-1-2 统计/应用色彩空间
- **推荐**：Oklab 统计域 + working linear Rec2020 恒等直出。
- 备选 A：CIELab（dt 语义对齐；需 Lab 往返实现，色相线性弱）。
- 备选 B：ACEScc/AP1（矩阵在库；感知均匀性弱 + 与 Grade 调色域语义混淆）。

### OQ-M5-1-3 colormatch op 形态与 LUT 载体
- **推荐**：独立 op `colormatch`（36.x 邻 lut3d）；线性臂 params 直存；LUT 臂
  65³ `.cube` 派生资产（params 存引用+哈希，不进 paramsData）。
- 备选 A：复用 `lut3d` op（语义混体，密封面开洞——不推荐）。
- 备选 B：LUT 内嵌 paramsData base64（sidecar ≈+4.4MB/实例——不推荐）。

### OQ-M5-1-4 LUT 分辨率与域端裁剪策略
- **推荐**：65³ float32 + 分位截尾支撑域 + 线性延拓平台面；矩阵臂全定义域。
- 备选 A：33³（省内存 ~9×；平滑域色相保真降级——film bake 先例 65³ 语义一致性
  更好）。
- 备选 B：129³（过度——统计求解分辨率瓶颈不在格点密度）。

### OQ-M5-1-5 多参考聚合语义（TRACK-02）
- **推荐**：统计级加权池化（单解确定；权重滑杆）。
- 备选 A：逐参考求解 α 混合（实现简、语义弱）。
- 备选 B：v1 只支持单参考（TRACK-02 缺交——不推荐）。

### OQ-M5-1-6 match_color MCP 工具面范围（MCP-09 研究项 C）
- **推荐**：最小面（reference/targets 批量/strength/solver/attach + 返回摘要与
  求解哈希；微调/验收/元数据走既有三工具）。
- 备选 A：加 preset 化（把求解结果存为 LUT 库条目供跨图复用）——增量 UI 面，
  挂 V2（库写面是 LutLibraryStore 新能力）。
- 备选 B：暴露簇统计/高级参数——v1 全局统计语义下无此面。

### OQ-M5-1-7 蒙版 / region 支持范围
- **推荐**：v1 = grade 层蒙版自动可用 + 参考侧全图统计；源侧局部 = 蒙版即达；
  参考 region 挂 V2。
- 备选 A：参考侧 region 一并做（统计域掩码 + UI 增量一个 plan 边缘；走查前
  无真实需求证据）。

### OQ-M5-1-8 golden / 确定性门定义（TRACK-05）
- **推荐**：五门（G1 bit-identity / G2 kernel parity ≤1e-5 目标实测收窄 /
  G3 合成参考对恢复 + 目测 / G4 MCP 端到端 / G5 恒等直通）。
- 备选 A：G3 只做合成对（自然样张目测挂 gui-acceptance Manual-Only 行——
  事实上的默认形态，非独立备选）。

## 验收形态（ROADMAP M5-1 行兑现路径）

- OQ 清零 → 用户裁决回批（C 档第 1 停兑现处）→ plan round（M5-1-01.. 起）。
- SC 数字门 = 各 plan 期定；全套 `--all` 轮照批准制 + 8G 运行门（AGENTS 资源
  监控节）。
- 红线自证惯例：零新 SPM / 密封面零 diff 清单 / V50Order add-only（colormatch
  36.x 行新增）/ 全 `.metal` 新增面申报。

## 裁决记录

（待用户回批后回填：OQ-M5-1-1..8 各项生效值 + 日期 + 回批载体。）
