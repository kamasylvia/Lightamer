# V2-PROPOSAL — V2/Maintenance 站立项草案（规划起草 subagent，2026-10-08）

> **定位**：M2 收官（15 phases / 145 plans / 2961 tests 零 fail，VALIDATION `3f91221` + 终审 `80f778f`）后的下一站排期草案。本文只做**候选分档排序 + M3 组合方案**，立项/排期终裁在用户（C 档第 1 停）。
> **预裁注记**：`M2-11-VALIDATION-INPUT.md` §4.5 用户回批「④V2 站排期：按推荐——草案定稿后按推荐方案与 OQ 推荐项直接进入 planner，不再停等」。本文 OQ 均带推荐，orchestrator 可按推荐流转；用户可随时推翻。
> **输入**：REQUIREMENTS V2 各节 / `M2-11-VALIDATION-INPUT.md` §4.4 挂账单一清单 / SPEKTRALAB-NOTES / LUMEN-RAW-NOTES / ALCEDO-FEATURE-MAP 增量测绘 / M2-11-05-SUMMARY 终态段。
> **边界**：M4（ToneEqual 悬垂 retain）+ M5（L057 取消腿家族）已裁决走修复批（在飞，§4.5②），**不入本站**。ALCE-01/04/05/06/07 已随 2026-09-27 重定义提级 V1 并在 M2-5/6/8/10 交付（色轮/DRT/命名版本/CLIP 搜索/AI 评片），**不重复立项**。

---

## 一、候选池分档总览

排序维度 = **用户可见价值 × 复用 M2 资产度 × 风险（反向）**。规模：S（≤1 plan）/ M（1-2 plans）/ L（2-4 plans 或需 research 环）。

| 档 | 项 | 规模 | 推荐批次 | 一句话 |
|---|---|---|---|---|
| **T1 主打档** | M2GRADE-08 LUT 作者编码建模 | M | M3-W1（前置） | 修「胶片 LUT 作于 log 域而我方按 working space 直套」系统性偏差；FSIM-01 前置基建 |
| **T1 主打档** | FSIM-01 两段式胶片模拟语义 | L | M3-W2..W3（主打） | 场景置位→胶片→配光→相纸阶段模型；配光自动求解 = UX 亮点；差异化卖点（Alcedo 无此面） |
| **T1 主打档** | FSIM-02 宽容度面板 | S/M | M3-W3（随 FSIM-01） | 场景直方图+胶片容纳范围双虚线+占比读数；教导交互 |
| **T2 搭车档** | YIYIN-09 预览面板拖拽调整 | S | M3-W1（mini-plan 搭车） | yiyin sheet 预览面 UX 小件；fork 已同步参考 `f8de57a` |
| **T2 搭车档** | 小件族（V14/V15 zh 清算 + 冲突档选择器 + peak-ICC 标注） | S | M3-W1（同批） | M2-9/M2-11 挂账尾款；冲突档选择器晨审判「必须暴露」 |
| **T3 备选主打档** | RASTER-IN-01 非 RAW 栅格开发链 | L | 方案 B 主打 / M4-W1 | Alcedo parity 最大缺口；DRT 逆链（ACES 2.0 inverse）进 develop 图 |
| **T3 备选主打档** | IOP-MASK-06 Follow Edges V2 | M | 方案 B 内含 / M4 | 脊线预提取/亚像素质心/自适应步长；snap 熔断态复活（M2 栏 M3 同物） |
| **T3 备选主打档** | IOP-MASK-07 Depth via MiDaS | M | 方案 B 内含 / M4 | MiDaS ONNX→CoreML 解锁桌面 RAW 深度蒙版；复用 M2AI-10 worker 隔离 |
| **T4 缓办档** | ALCE-02 OpenEXR 导出 | S/M | M4（随 RASTER-IN research 同批裁） | 与 RASTER-IN 的 EXR 读对偶；写侧无原生 → 依赖问题（OQ-5） |
| **T4 缓办档** | ALCE-03 Ultra HDR JPEG 导出 | S/M | M4 | gain map 嵌 JPEG 腿；与 ALCE-02 合并为「导出格式扩容批」一次 research |
| **T4 缓办档** | IOP-HDR-06 Mertens 曝光融合 | M | M4-W2 | 第二 HDR 合并模式（免 CRF + 三档 deghosting）；复用 Phase 8 管线 |
| **T4 缓办档** | TRACK-01..05 追色族 | L | M4/M5 | colormatch iop + 多参考 + 交互；MCP-09-C `match_color` 依赖本族 |
| **T4 缓办档** | IOP-PANO-01 全景合成 | L | M5 | SIFT+球面投影+分块羽化；独立大件不与主打混波 |
| **T4 缓办档** | FSIM-03 印相域影调蒙版注记 | S | 并入 FSIM phase research | 研究注记非功能，不独立立项 |
| **触发条件档** | M1 100MP 级增强行带流式 | L | 待触发 | `c573087` 已闭 12MP 档；100MP HDR/堆栈真实场景出现再立项 |
| **触发条件档** | M2-denoise 拖动降档预览语义 | S/M | 可搭 M3 任一波 | 拖动降档预览（松手全质量）；kernel 重写 C 案挂后 |
| **触发条件档** | M6 O-2 显示腿瞬态峰杠杆 | M | 待触发 | 6.3-8.6GB；16GB 机 swap 压力出现再处置 |
| **触发条件档** | M7 O-1 RAF 双峰 spike | S | 可搭 M3 research 环 | 14↔42ms 双态跳变定位；低成本 spike 候选 |

---

## 二、逐项档案

### T1 主打档

**M2GRADE-08 — LUT 作者编码建模**（REQUIREMENTS :388；上游 Alcedo c740f7b 形态）
- **价值**：高——修系统性色偏（log 域胶片 LUT 直套 working space）；上游 parity 面。
- **依赖**：无硬前置；是 FSIM-01 的软前置（传递曲线/色域目录基建直接复用）。
- **规模**：M——面板 input/output encoding 选择器 + 编码随 LMT 生效 + 库内逐 LUT 记忆 + 传递曲线/色域目录。
- **复用 M2 资产**：M2-5 `LutLibraryStore`（key 升级/shared holder/可配根全在）+ `Lut3dModule` + M2-6 LMT 面。
- **风险**：中低——编码烘焙进 LMT 触碰 lutf 缝；上游 `lut_catalog.cpp`→LUT library service 形态可对照。
- **备注**：原文即注「可插队 M2 后期 UI 打磨轮」——M2 已收官，插队窗口 = 现在。

**FSIM-01 — 两段式胶片模拟语义**（REQUIREMENTS :379；SPEKTRALAB-NOTES 可借鉴#1）
- **价值**：高——从「贴一段 LUT」升维为「物理流程」（场景置位→胶片记录光→配光→相纸呈现）；配光自动求解（软件测光算印相滤色组合 + Y/M 手动偏移）= UX 亮点对齐物；Alcedo 无此面 = 差异化卖点。
- **依赖**：M2GRADE-08（编码目录）；M2-5 Grade 件族 + ACEScc envelope。
- **规模**：L——阶段模型动 M2-4 节点图语义（Develop→Color Grade×N→Display Transform 链上新增胶片段），需 research 环（SpektraLab `rfc/` + 指南）。
- **复用 M2 资产**：M2-5 GradeCatalog 七件 + envelope 缝 + M2-6 DRT 尾段策略 + LUT 库。
- **风险**：中高——语义级升维；**红线注记**（SPEKTRALAB-NOTES）：81 波长光谱引擎架构性不可达（CIRAW 后 RGB 域起步），只能做染料近似——FSIM-01 的可行核 = 阶段分离语义 + 配光求解，不是光谱重放；预期管理入 research。
- **许可**：SpektraLab 代码 GPL-3.0 只读零复制；其胶片/相纸配置 = CC BY-SA 4.0 独立资产，如引入须独立归属（与 M2GRADE-07 spectral_film_lut MIT 不混用）。

**FSIM-02 — 宽容度面板**（REQUIREMENTS :380）
- **价值**：中高——场景直方图 + 胶片容纳范围双虚线 + 低于/内/高于占比；「场景置位与显影后曝光严格分离」教导交互。
- **依赖**：FSIM-01（场景置位概念随阶段模型而来）。
- **规模**：S/M。
- **复用**：直方图基建 + M2-5 面。
- **风险**：低。

### T2 搭车档

**YIYIN-09 — 预览面板拖拽调整**（REQUIREMENTS :278）
- S 规模 mini-plan；yiyin sheet 预览区拖拽分割线；对齐上游 PR #126（fork `f8de57a` 已同步）；参考 `web/main/components/actions/`。原文即注「M2-11 收官后 mini-plan」。

**小件族**
- **V14 标记菜单裸键 + V15 zh-audit 提取器硬化**：Phase 15 zh 清算批（M2-11 FINDING-G 族）。
- **冲突档选择器 UI**：`enqueueExportM2` 固定 `.increment`，引擎三档已交付钉死（M2-9-VALIDATION 挂账#4 + 走查#59 行）——晨审判「选择器必须暴露 → fix(m2-9) 通道或另案小修」，S。
- **peak-ICC 标注**：HDR 导出 peak 元数据说明面，S。

### T3 备选主打档（方案 B 主打）

**RASTER-IN-01 — 非 RAW 栅格开发链**（REQUIREMENTS :387；ALCEDO-FEATURE-MAP 增量 delta 1，#265-270）
- **价值**：高——Alcedo parity 最大缺口；JPEG/PNG/TIFF/OpenEXR 导入即开发 = 非 RAW 用户入口级能力。
- **规模**：L——源 color description（ICC）解析 + HDR 旗标 → display-referred 输入经 DRT 逆链（ACES 2.0 inverse，上游 DisplayToAp1/OCIO 可对照）+ Metal staging + 文件夹导入文件类型选择器（#264 形态）。需 research 环。
- **复用 M2 资产**：M2-6 DRT 段（逆变换路径）+ `DrtOutputColorSpace`（正向解析器反向利用）+ M2-2 ImportFilter/ImportService + M2-9 ICC 纪律。
- **风险**：中——「栅格 = display-referred 经 DRT 逆链」色彩语义需形式化（我方编辑器可开非 RAW 但未形式化此语义）；EXR 读无 ImageIO 原生 → 依赖问题与 ALCE-02 同批裁（OQ-5）。

**IOP-MASK-06 — Follow Edges V2**（REQUIREMENTS :365 + M2 栏 M3；M2-7-3 熔断态复活）
- **价值**：中高——Nitro 独门能力补完；walkers 对真实照片脊型失稳已实测（`phases/m2-7-masks/evidence/m2-7-3/probe/probe.log`：8 景盒 × 2 阈值 ≤3 点链、82/100 空）。
- **规模**：M——脊线预提取/亚像素质心/自适应步长。
- **复用**：M2-7 全套在册（`mask_edge_map` kernel + CPU walker + `.snap/.streamline` 双 case + 进程内探针方法论）——V2 修复方向在案，复活零重写。
- **风险**：中——算法修复曾有失稳史；熔断态（默认 `.snap`）兜底，失败不伤产线。

**IOP-MASK-07 — Depth via MiDaS**（REQUIREMENTS :366；LUMEN-RAW-NOTES 候选 1，2026-10-01 采纳）
- **价值**：中高——AI Background/Depth 蒙版解锁（桌面 RAW 深度源稀缺的现成解法）。
- **规模**：M——MiDaS 级单目深度 ONNX→CoreML 转换 + 蒙版数据面接入；参考 `lumen/auto_masks.py` + `lumen/ai_worker.py`。
- **复用**：**M2AI-10 推理 worker 进程隔离 crash-safe（已交付）= 直接底座** + M2-7 蒙版源架构 + M2-10 模型管线（内置 AI 模型已 ≈193MB by-design，MiDaS small 级增量可控）。
- **风险**：中——模型转换与资产体积；relative-depth 仅相对深度（前景选择够用）。

### T4 缓办档（M4/M5 候选）

- **ALCE-02 OpenEXR 导出**（S/M）：编码器矩阵加一格式；ImageIO 不写 EXR → 需第三方 binding 或自写 minimal 子集（OQ-5）；与 RASTER-IN 的 EXR 读对偶，一次 research。
- **ALCE-03 Ultra HDR JPEG**（S/M）：ISO 21496-1 gain map 嵌现有 JPEG 腿，EDR 渲染值映射增益层；gain map 构造需 research（Apple Adaptive HDR API 面）。
- **IOP-HDR-06 Mertens**（M）：免 CRF 快速 HDR + 三档 deghosting；参考 `lumen/merge.py`；输出 32f 进 IOP-HDR-04 既有管线；与 Robertson02（IOP-HDR-01）互为合并选项。
- **TRACK-01..05 追色族**（L）：Reinhard/CDF/OT 择一 → 3D LUT + `colormatch` iop + 多参考聚合 + 拖入交互 + golden parity 门；计算核 native 不可外包（2026-09-26 再确认）；MCP-09 研究项 C `match_color` 工具位依赖本族——**若用户高频走 agent 编排修图可提前**（OQ-6）。
- **IOP-PANO-01 全景合成**（L）：SIFT 对齐 + 相机优化 + 球面投影 + 分块羽化，100MP+ 输出；参考 `lumen/merge.py`；独立大件。
- **FSIM-03**（S）：研究注记，并入 FSIM phase research，不独立立项。

### 触发条件档（Maintenance 处置建议）

- **M1 行带流式**：`c573087` 两阶段 engine 已闭 12MP 档；触发 = 100MP HDR/堆栈真实场景内存压力实测出现。**不随 RASTER-IN 捆绑**（OQ-4）。
- **M2-denoise**：拖动降档预览 UX 语义 = S/M 可搭车；kernel 重写/时域复用 C 案 = L 挂后。
- **M6 O-2**：触发 = 16GB 机 swap 压力实测出现；未现不立项。
- **M7 O-1**：S 规模 spike，可搭 M3 research 环顺带跑（perf.md 计量基建全在）。

---

## 三、M3 组合方案（方案级推荐）

### 方案 A「胶片暗房」——M2GRADE-08 + FSIM-01 + FSIM-02 + 搭车族 【**推荐**】

- **构成**：W1 = M2GRADE-08 + YIYIN-09 + 小件族（zh 清算/冲突档选择器/peak-ICC）；W2..W3 = FSIM-01（含 research 环）；W3 尾 = FSIM-02 + FSIM-03 注记 + M7 spike（顺带）。
- **规模**：约 5-7 plans。
- **理由**：
  1. **资产复用最厚**：M2-5 Grade 件族/GradeCatalog/LUT 库 + M2-6 DRT 尾段 + M2-11 计量基建全在期，FSIM 升维直接踩在 M2GRADE-08 编码目录上——两件同站做避免 LUT 面二次返工。
  2. **差异化价值最高**：Alcedo 无胶片模拟面，做出来即超集卖点；配光自动求解是 UX 亮点。
  3. **前置时序顺**：M2GRADE-08 原文注「可插队 M2 后期」，插队窗口就是现在。
- **风险**：FSIM-01 语义级升维（节点模型加阶段）——research 环先行 + 光谱引擎不可达预期管理。

### 方案 B「栅格链 + 蒙版修复」——RASTER-IN-01 + ALCE-02 + IOP-MASK-06 V2 + IOP-MASK-07 + 搭车族

- **构成**：W1 = 搭车族 + RASTER-IN research；W2..W3 = RASTER-IN-01（DRT 逆链 + 选择器 + EXR 读）+ ALCE-02（EXR 写，与读同批裁依赖）；W3 尾 = MASK-06 V2 或 MASK-07（二选一，另一件滚 M4）。
- **规模**：约 5-7 plans。
- **理由**：parity 优先立场——补齐「完全模仿 Alcedo」的最大输入缺口；EXR 读写一次闭环；蒙版族两项内聚（M2-7 + M2AI-10 基建直接复用）。
- **风险**：RASTER-IN 色彩语义形式化 + EXR 依赖裁决；蒙版算法修复有失稳史。

### 方案级推荐

**推荐方案 A**。三票：①复用 M2 资产度最高（排期维度第二权重）；②M2GRADE-08 的插队窗口语义（原文自证）；③差异化用户价值（排期维度第一权重）——方案 B 的 RASTER-IN 是 parity 补课，晚一站做不产生沉没成本（非 RAW 输入现状可用只是未形式化），而 FSIM 的前置时序红利过期不作。方案 B 整体滚存为 M4 主打（届时 EXR 依赖、DRT 逆链语义随 M3 的 FSIM research 反哺）。

> 若用户选 B：M2GRADE-08 仍建议随 B 的 W1 搭车先行（S/M 规模、独立无前置、避免与 FSIM 绑死）。

---

## 四、逐项推荐排序（与方案选择解耦）

1. **M2GRADE-08**（M3-W1，两案通用前置）——插队窗口 + FSIM 软前置 + 中期规模。
2. **YIYIN-09 + 小件族**（M3-W1 搭车）——原文钦定 mini-plan + 晨审已判小修 + S 规模零风险。
3. **FSIM-01/02/03**（M3 主打，方案 A）——价值 × 资产双高；FSIM-03 并入 research 不单列。
4. **RASTER-IN-01**（M4 主打 / 方案 B 主打）——parity 最大缺口，research 环先行。
5. **IOP-MASK-06 V2 / IOP-MASK-07**（M4，或方案 B 内）——蒙版族内聚；M2AI-10 底座现成。
6. **ALCE-02 + ALCE-03**（M4「导出格式扩容批」一次 research）——EXR 依赖与 gain map API 面同批裁。
7. **IOP-HDR-06 Mertens**（M4-W2）——轻于 pano，复用 Phase 8 管线。
8. **TRACK-01..05**（M4/M5，视 agent 编排使用频率可提前，OQ-6）。
9. **IOP-PANO-01**（M5）——独立大件。
10. **M2-denoise 拖动降档语义**（任一波搭车）+ **M7 spike**（research 环顺带）。
11. **M1 / M6**（触发条件在案，不主动立项）。

---

## 五、M3 波次草案（方案 A 展开例）

| 波 | plans（估） | 内容 | 验收锚 |
|---|---|---|---|
| M3-W1 | 3 | M2GRADE-08（编码选择器+LMT 烘焙+逐 LUT 记忆+目录）/ YIYIN-09 mini-plan / 小件族批（zh 清算+冲突档选择器+peak-ICC） | LUT log 域档直套偏差消除 golden 对照 + 上游 c740f7b 对表；fork PR #126 形态对表；M2-9-VALIDATION 挂账#4 关闭 |
| M3-W1.5 | 1 | FSIM research（SpektraLab `rfc/` + 指南；阶段模型+配光求解设计；光谱不可达边界声明；CC BY-SA 资产取舍裁决面） | OQ 清零 + 设计评审 |
| M3-W2..W3 | 2-3 | FSIM-01 实现（阶段模型进节点图 + 配光自动求解 + Y/M 偏移） | golden 对照（染料近似域）+ 配光求解确定性门 + 走查 |
| M3-W3 尾 | 1 | FSIM-02 宽容度面板 + FSIM-03 注记落档 + M7 spike（顺带） | 双虚线/占比读数走查；spike 结论入 perf.md |

方案 B 展开：W1 = 搭车族 + RASTER-IN research；W2 = RASTER-IN 实现（逆链/选择器/EXR 读）+ ALCE-02 EXR 写（依赖同批裁）；W3 = MASK-06 V2 与 MASK-07 择一（另件滚 M4）。

---

## 六、边界与纪律

- **C 档**：本草案定稿即本站规划动作终点；立项/排期终裁 = 用户（§4.5 预裁「按推荐」可作快速通道，用户可随时推翻）。
- **在飞修复批隔离**：FINDING-F（L057 家族）+ ToneEqual 根因排查已派遣在飞（§4.5②）——本站所有 waves 派遣前复核 `git log`/GOAL-STATE，不得与修复批 owned 文件（IOP ToneEqual 面 / LUT 导入面板面）并行触碰。
- **zh 清算批**（V14/V15）原锚 Phase 15——随 M3-W1 搭车属提前执行，非另立 phase；若用户愿维持 Phase 15 独立批则从 W1 剔除（不影响两案主体）。
- 依赖红线：新 SPM 依赖裁决权在用户（ALCE-02/RASTER-IN EXR 面为唯一已知候选，OQ-5）。

---

## 七、M6 清算批转 V2 挂账（2026-10-16 M6-5 批登记）

> 登记体例沿用本提案「触发条件档」节（规模 + 触发 + 一句话）。
> **登记 ≠ 立项，终裁在用户。** 来源正本 = `phases/m6-5-ledger-clearing/
> M6-5-CONTEXT.md` §1/§5（40 项盘点的转 V2 分类行）；各来源 VALIDATION
> 挂账节原文在案可 grep。

### 1. TRACK-MULTIREF（M5-1）

- **来源锚**：`phases/m5-1-track/M5-1-VALIDATION.md` 挂账 A11（OQ-6 v1 裁决字面）。
- **触发条件**：agent 编排高频多参考工作流出现（需求驱动）。
- **规模**：S（GUI 面板多参考已交付，本件纯 MCP 面）。
- **一句话**：MCP `match_color` 多参考聚合 + 求解结果 preset 化（存 LUT 库条目）。

### 2. RELEASE-DIRECT-INJECT（M5-2）

- **来源锚**：`phases/m5-2-mertens/M5-2-VALIDATION.md` 挂账 + `perf.md` §事故 4 正本。
- **触发条件**：Release 直启基准轮需求出现（工具链债，无需求不动）。
- **规模**：S。
- **一句话**：Release 直启 WebP 包 framework 动态链接不对称修复（Debug 静态/
  Release 动态且未 embed；根因 = framework 未产出，D-09-04-D9 配方不达）。

### 3. PANO-V2（M5-3，五件）

- **来源锚**：`phases/m5-3-pano/M5-3-VALIDATION.md` 挂账（OQ-M5-3 裁决 V2 字面）。
- **触发条件**：全景合成用户反馈/需求出现（OQ 裁决 V2 字面，无触发不立项）。
- **规模**：L（独立 research 环）。
- **一句话**：预览合成画布 / 参考帧手选 / use_edits / per-image 焦距（畸变/
  tilt）/ multiband 融合。

### 4. SESSION-LEGACY-READONLY（M6-1）

- **来源锚**：`phases/m6-1-interop/M6-1-VALIDATION.md` 挂账 B3（`SessionCoordinator.swift:489` 仍仅 `session_lock_held` toast）。
- **触发条件**：用户诉求出现再裁（legacy 面 env 门控 QA 通道 `LIGHTAMER_LEGACY_LIBRARY`，默认隐藏，可见面趋零——维持 M6-1 范围裁定）。
- **规模**：M。
- **一句话**：legacy Session 根只读回退 GUI 面（现仅 typed toast，无 GUI 只读回退）。

### 5. PROCESS-WIRING（M6-2，触发条件档）

- **来源锚**：`phases/m6-2-process-version/M6-2-VALIDATION.md` 挂账 #1 原文 +
  `M6-2-01-DECISIONS.md` §6 四件套正本。
- **触发条件**（与 M6-2 VALIDATION 挂账 #1 原文同文）：
  **首个真实 iop 语义分叉/bump 批触发时四件同批**：①PipeCoordinator 各 render 调用点读
  processVersion 载体传 `renderProcess:` ②分叉 iop 在 `process` 内消费
  `RenderProcess.resolving(piece.renderProcess)` + 穷举 switch ③该 stage
  缓存键按「非 legacy 才折」折值 ④「Update to Current Process」迁移 UX
  同批裁形（OQ-5 挂账；LightCraft `develop.updateProcess` 一步 undo 为
  参考底稿）。
- **规模**：M。
- **一句话**：coordinator 传值接线件 + 分叉消费件 + 迁移 UX 同批裁形
  （by-design 挂账非缺陷；生产零传值维持，M6-2 双路亲证）。

### 6. ULTRAHDR-EXIF（M6-3）

- **来源锚**：`phases/m6-3-ultrahdr/M6-3-VALIDATION.md` 挂账 D1。
- **触发条件**：用户/生态对 EXIF 元数据的硬需求出现（by-design 降级预授权；
  Software 存活座位 = xmp:CreatorTool）。
- **规模**：M。
- **一句话**：gain map 档 EXIF v2/EXIF APP1 注入器批（禁自建 APP1 注入器裁决
  在案——段级注入与 MPF 副图偏移互斥；届时与 LightCraft C 路〔封存零代码〕
  同批评估路线）。

### 7. STACKS-SEMANTICS（M6-4，D-06）

- **来源锚**：`phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` 挂账 E1（`§D-06` 同条）。
- **触发条件**：图库 stacks 用户反馈出现。
- **规模**：M。
- **一句话**：栈顶被滤「首可见成员顶替」语义腿（LightCraft arrange 式 App 侧
  实现，hit 集有限 id 表）+ `overviewCount`/`groupCounts` 收起态口径合一。

### 8. SAM-COREML（M6-4，charter 裁决⑦）

- **来源锚**：`phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` 挂账 E4。
- **触发条件**：用户裁立项 = 另开独立 phase（原生不可达收口在案）。
- **规模**：L（3.4GB Meta License 永不入仓 + 全族自转换；ModelAssetStore
  安装链 + AIWorkerProtocol 第四腿已备）。
- **一句话**：Describe 文本选择分割 → SAM CoreML 大件。

### 9. PATCH-LIVEPLANE（M6-4，D-13 残差）

- **来源锚**：`phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` 挂账 E5（D-13 申报两笔）。
- **触发条件**：V2 语义批一并裁（登记级零用户可见面；主修已闭环 `b49215bb`）。
- **规模**：S。
- **一句话**：livePlane eager 释放（EditorState→LayerEditingState 新横 wire）
  + patch pass 互斥锁（confirm 在飞切图竞态消解）。
