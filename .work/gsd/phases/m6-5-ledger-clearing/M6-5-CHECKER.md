# M6-5 修订版 PLAN Checker（独立目标反向核，2026-10-16）

> Checker 身份：独立目标反向核（fixer 后另一只眼，零共享推理链）。
> 输入 = 修订版 `M6-5-01-PLAN.md`（commit `2f88907a`）+ `M6-5-CONTEXT.md`
> + `M6-5-01-PLAN-REVIEW.md` + 代码锚点 HEAD 亲验（写腿全集全仓再扫 /
> 字段面终对照 / 分诊门干跑实证）。
> 结论头：**放行 / 0 error + 0 minor open（1 批内补漏已闭环 + 2 观察项）**。
> 修订版 plan 可直接派执行批；三组核心修订自洽复验全绿，证据在案。

---

## 一、Goal-backward（phase 目标反向推演）

**Phase goal**（requirements 字段）= 「挂账单一清单逐项闭合或转 V2 挂账
留痕」+ 全套 `--all` 确认轮。40 项盘点（CONTEXT §1）→ 修订版 plan 逐项
映射复核：

| 分类 | 项数 | 落点 | 映射判定 |
|---|---|---|---|
| 清偿 | 8 项（A1+B2+C3 同条→T1 / C2→T2 / A13→T3 / D2→T4 / D4→T5 / F1→T6） | T1..T6 各带机检 AC | ✓ 无缺口 |
| Manual-Only | 11 项（A3 A4 A6 A8 A10 A14 A17 B1 D5 E2 E3）+ rider | T7 汇编（~17 行，逐行来源指针） | ✓ |
| 转V2 | 9 项（A11 A15 A18 B3 C1 D1 E1 E4 E5） | T8 登记节（触发条款对表基准 M-4 修订） | ✓ |
| 销账 | 7 项（A2 A5 A7 B4 C4 D3 + E6） | 零动作；评审 A-1 §1 证据链可复核 | ✓ |
| 留置 | 5 项（A9 A12 A16 A19 A20） | 零动作（归他站在案） | ✓ |

合计 8+11+9+7+5 = **40 逐项闭合，无孤儿项**。SC→任务映射：CONTEXT §3
六修复量级评估 ↔ T1..T6 一一对应；§4 确认轮口径 ↔ T9（算术已随 E-2 扩面
同步 +3→+5 / 3846→3848，对账式 3841+2+5 精确）；§6 ↔ T7；§5 ↔ T8。
**Goal-backward 成立——修订版 plan 执行完毕即 phase goal 达成。**

## 二、核心修订自洽复验（三组独立实证）

### 2.1 E-1：App bundle repo 写腿全集再扫（全仓，非复核评审旧账）

全 Tests 域引用 `Tests/Fixtures` 的 13 文件逐一过组合（load ×
写腿调度面 × temp 防护）：

- **唯一裸写腿文件 = `RasterEditFaceTests.swift`**（load×5 +
  recordDrtChange/flush/undo 面×6，tempguard 仅 1 = 现存防御
  removeItem）——restore 法（:187-190 直驱）+ undo 法（:205 repo 取用
  → :209/:213 双调度）两法恰为全集，与 E-1 修订版 T1 双法同改对表 ✓。
- `RasterRoundTripTests`：写腿已 tmp 化（:297 source = tempDirectory；
  :290 注记自证「repo directory never grows a .lra」）✓。
- `ProcessVersionCarrierTests`：全部 load 走 `makeImageURL()` =
  `temporaryDirectory + UUID`（:55-60）✓。
- `NLMeansDragDowngradeTests`：commitContinuousEdit×2 无 load（合成
  instances，无 sidecar URL）✓。
- `PanelWiringTests` / `CropOverlayTests` / `LayerE2ERoundTripTests` /
  `EDRViewportTests` / `DrtPanelModelTests`：全部 temp/合成 URL ✓。
- 其余 4 文件（Depth 族 / RasterDecodeLeg / RasterHdrViewport /
  RasterIccSemantics / RasterRouting / ImportTransport /
  LibraryThumbnailBridge）：零写腿组合 ✓。

**判定：T1 双法改后 repo 路径写腿全集真空——T9 复扫「零命中」可满足，
批内卡死风险消除。** undo 法断言全在 carrier 面（`drtRecord`/
`hasDrtRecord`，亲读 :216-222）换 tmp 副本零语义影响的修法依据成立。

### 2.2 E-2：12 字段清单 vs `LightamerSidecar` :250-377 全字段面终对照

文档字段面逐字段三分：①**结构性**（compose 恒新造）：schemaVersion /
appVersion / imageID / decoderVersionUsed / decodeParamsHash / instances
/ history / historyHash / **layerStack** ②**12 optional**（七 additive
:317-365 + 五元数据 :293-309）③**process**（:158-163 分支条件盖章，
T2 零触红线）。

**有无第十三字段？——无。** 唯一疑点 layerStack 已归位：`PasteSemantics
.paste` 自有（`LightamerCore/Sources/Pipe/History/PasteSemantics.swift`
——OVERWRITE 臂 :165 取 payload layerStack / MERGE 臂 :186
`targetLayerStackRecord(history:)` 从 targetHistory 重建，而 batch
applier 恰把 decode 出的 targetHistory 传入 paste）——layerStack 是
paste 语义的所有物，非「被丢弃的携带缺口」。process 经 processStamp
携带。构造点 12 参全部在位（init :422-429 亲验）。**T2 修法 = 全
optional 面闭合，E-2 半修风险不存在。**

### 2.3 E-3：分诊门可机检性（干跑实证，非纸面推演）

- **干跑**：目录副本 + 三键（`settings_displays_overridden %@` /
  `edr_headroom_label %@` / `softproof_active_label %@`，en+zh）→
  `python3 Scripts/zh-audit.py --check --catalog <副本>` **exit 0 PASS
  （1926 键）**——断言 1-4 无破坏（新格式变体键经 `covered_by_family`
  的 `prefix + " "` 形被 interp 族覆盖，不落 orphan；zh 完整性由新键
  自带值满足）。清偿路线（键落目录）与 zh-audit 现行四断言兼容实证 ✓。
- **断言 5（V16 新增）机制可判定**：提取（同行 regex + PENDING 续行
  延拓）→ 集合判定 `any(ck.startswith(K + " "))`——纯集合运算无歧义；
  `run_selftest` 的 `check()` golden 结构天然容纳红/绿两用例（BAD
  fixture 增无变体键 = 红；`selftest_family` 补变体 = 绿）。**门 =
  可机检 ✓。**
- 预扫定格数（30 调用点/30 键 = 24+3 单行 + 3 续行，3 ABSENT）由
  fixer 双脚本独立跑出（grep 单行面 + PENDING 状态机续行面互证），
  V16 首跑 transcript 为最终对表基准——plan 已按「transcript 记实际」
  措辞，无脆弱等式 AC ✓。

## 三、独立猎残

| # | 发现 | 处置 |
|---|---|---|
| R-1 | 修订版 T6 验收标准初稿漏「AGENTS 登记行落盘」机检项（action 4 有、AC 无） | **批内补漏已闭环**——fixer commit amend（`2f88907a`）补入 AC |
| R-2 | CONTEXT §2 分类汇总表计数妆饰性滑差：留置行标「6 项」实列 5 项（A9 A12 A16 A19 A20）；销账行「6 项（+E6）」实 7 项 | **观察项，不阻塞**——逐项 §1 表为正本且正确（合计恰 40）；分类裁定不重开，晨审知悉即可 |
| R-3 | V16 断言 5 提取与 KEY_SHAPE 同源（`[a-z][a-z0-9_]+` 小写偏置）——含大写/数字的插值字面量键逃逸断言 5 | **范围注记**（与 V15 既有形态同盲区，本批非缺陷）；plan T6 已申报 spec 深检留人工，同口径 |
| R-4 | plan 内一致性回扫（LIB / 3846 / 24+1 / 大写 bundle token 残留） | 零残留（仅纪律节/修订记录节的刻意提及）✓ |
| R-5 | T2 补记落点形态：M6-2-VALIDATION 挂账节 = 编号列表（:99-125），非表格 | 「#2 行后追加带日期补记行（不改写原行）」与列表形态兼容 ✓ |
| R-6 | T2 新测试写盘域：SessionBatchApplierTests 全程 tempDirectory（:23 L009 注记 + :35） | 无 repo fixture 写面 ✓ |
| R-7 | T8 对表基准双正本核验：M6-2-VALIDATION :104（「首个真实 iop 语义分叉/bump 批触发时四件同批」）+ DECISIONS §6 :68-76（四件套含②完整形 `RenderProcess.resolving(piece.renderProcess)`） | plan AC 两处引证逐字吻合 ✓ |
| R-8 | 工作树现存孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（untracked） | T1 步 5 前置清扫覆盖；red_lines「无残留」唯一允许态 ✓ |
| R-9 | 三清偿键 zh 文案为执行期产物（干跑用占位值） | plan 已约束「措辞对齐既有相邻键族」✓ |

## 四、结论

**放行 / 0 error + 0 minor open。** 修订版 `M6-5-01-PLAN.md`
（`2f88907a`）七 finding 全数落入且三组核心修订经独立实证自洽
（写腿真空 / 字段面闭合 / 分诊门干跑 PASS）；goal-backward 40 项
逐项映射无缺口；独立猎残仅妆饰性观察两条（R-2/R-3），均不阻塞派发。
执行批可按修订版 T1→T9 序推进；批内 ΔN 记账预期 +5（T2 +4 / T4 +1），
T9 对账 3848/24/0。
