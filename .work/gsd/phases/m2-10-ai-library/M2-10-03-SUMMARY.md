# M2-10-03 SUMMARY — 自动打标 + 后台任务注册表 + 导入询问接线

> 执行 worker 收口（2026-10-03 夜）。两个功能提交 + 本收口提交；
> 裁决与偏离正本 = `M2-10-03-DECISIONS.md`（§1..13）。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `f15bb96` | LabelQueries（出厂 173 标签 × zh/en，脚本解析型单源）+ LabelEngine（余弦分类/margin-confident/top8 裁度/top_scores JSON）+ LabelPrototypeSet（fp16 LE bundle 加载 + revision typed 拒绝）+ `generate_label_prototypes.py`（新，申报）+ `build_default_bundle.sh --with-label-prototypes`（E3 opt-in 追加）+ LabelEngineTests 12 |
| T2 | `6a756bd` | AnalysisTaskTypes（Core 值类型 + 取消令牌 + id 查询族）+ AIAnalysisRegistry（三任务型串行 utility 队列 + AI leg conformer + 取消增量 + typed 失败面）+ 导入接线（runImport 成功尾单点：自动嵌入腿 + labeling 三态）+ LabelingAskDialog + LabelingPromptController + `library.ai.labelingMode` 键族 + AnalysisRegistryTests 13 + LabelingDefaultsTests 13 |
| T3 | 本提交 | AC 机检 + 全套终跑对账 + SUMMARY/DECISIONS/GOAL-STATE + BUNDLE-MAP 三行 |

## 测试数字（基线 2759/16/0）

- **全套 --all 终跑：`TOTAL|2797/16/0|975s`** ——执行数 = 2759 + **38 精确
  对账**（LabelEngineTests 12 全落 Library；AnalysisRegistryTests 13 +
  LabelingDefaultsTests 13 全落 App），**单轮干净绿零 flake**。
- 七 bundle 逐值：IOP 467/1/0、IOPParity 362/3/0、Layers 298/3/0、
  **Library 503→515/4/0**（+12）、Sessions 279/4/0、**Export 338/1/0 红线门
  零漂移**、**App 512→538/0/0**（+26）；skip 16 = 基线**零新增**。
- peakRSS 最大 IOP 7857MB < 8192 门，零 MEMFAIL。
- 资源门注记：本机激活态——`testRealPrototypesClassifyRealEmbedding`
  **真跑非 skip**（真原型 173 × 真嵌入链端到端）；无模型环境该测试 XCTSkip
  可审计（AC#7 双读口径）。

## LabelEngine 形态（KD-2 兑现 + DECISIONS 签注位）

- 分类 = 归一化点积（与 02 归一化姿态同构，零隐式 norm——非单位输入使分值
  翻倍由测试钉死）；全表有序输出，tie-break 字母序确定性。
- `confident = margin ≥ 0.05`（inclusive，`nextUp` 双侧机检）；tail 行
  （无 runner-up）confidence 恒真。
- 入库 = top 8 行 + 主行独占 `top_scores` JSON（§5 签注）；行级 runner-up
  取全表序（裁行不裁链）。
- `LabelPrototypeSet.load` typed 家族：revision mismatch / index corrupt
  （JSON 坏/count 不齐/重复 label/payload 尺寸）/ 目录缺席。

## 原型资产实况（D-M2-10-CONTEXT-7 兑现）

- **真原型已生成落盘**：`Resources/AIModels/chinese-clip-vitb16-int8/
  label-prototypes/{prototypes.json,bin}`——173 原型 × 512 维 fp16 LE =
  177,152 bytes；revision = Catalog pin `36e679e6…`；gitignore 覆盖机检过
  （`git check-ignore` 命中，零跟踪字节）。
- 生成链 = `generate_label_prototypes.py` 解析 `LabelQueries.swift`（唯一
  真相源）→ pinned-revision 文本塔逐条嵌 en query → L2 → fp16。
- `build_default_bundle.sh`：`--with-label-prototypes` opt-in 阶段（E3），
  无 flag 时 01 链字节等价；flag 链完成后移除 01 的 `prototypes/` README
  占位（本机尚未跑全 flag 链，占位暂留——DECISIONS §4）。

## AIAnalysisRegistry 形态（M2AI-07 兑现）

- **串行 utility 队列**：FIFO 单飞（`maxInFlight==1` 机检）；每张之间
  `Task.yield()`；文件 IO/解码/嵌入全部离主线程（engine actor + ImageIO
  背景腿）——「分析期间可继续工作」。
- **取消 = 增量终态**：token 逐张检查点；已完成行保留（重跑幂等
  reconcile）；终态 exactly-once（DECISIONS §11，首轮测试抓到修复）。
- **typed 失败面**：store/engine/model/prototypes 四缺席路径 → handle
  snapshot 错误文案 + `lastFailureCopy` 可观测——不崩不静默（AC#4 面）。
- **三任务型**：embedding（逐张 embedAndStore，尺寸唯一源 =
  `manifest.inputSize` E4）/ labeling（缺者先补两遍扫 + 一次 scan-table
  装载分类）/ recomputeAll（OQ-9-A：单批翻 active → 全库新 key 重嵌 →
  旧 key 行保留，取消保 partial + 翻档维持）。

## 导入接线（OQ-6-A 兑现）

- 自动腿：`runImport` 成功尾（`imported>0 && !cancelled`）→ 新行集
  （导入前 MAX(id) 高水位捕获）→ `enqueue(.embedding)` 无弹窗。
- 弹询腿：`.ask`（默认）→ 进度收尾一拍后 sheet（「用 AI 分析图片内容？」
  + 全本地声明 + Remember my choice）；「分析」→ `.labeling` 入队；
  `.always` 跳问直入；`.never` 不跑不弹（嵌入腿独立于该偏好照跑）。
- remember 写回：是+remember → `.always`；否+remember → `.never`；单次
  应答零持久化（ImportDefaults storeChoice 同款）。
- 红线机检：ImportService / ImportFilter / BackgroundTaskHosting
  **零 diff**（321383b..HEAD）；LibraryProjectController 半径 = 注入点
  两个字段 + runImport 尾单块。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | 手算锚 + margin 双侧 + top8 裁度 + revision typed | ✅ LabelEngineTests 12/0/0（正交/同向/反向 + nextUp 双侧 + JSON 形 + corrupt 家族） |
| 2 | 出厂集落库幂等 + zh/en 对齐 | ✅ `testFactoryCatalogCompleteness` + `testFactorySeedIsIdempotentIntoRealProject`（真 .lalb 双 seed，173×2 行，逐 label zh+en）——落点改 LabelEngineTests（3b 并行波保护，DECISIONS §12） |
| 3 | registry 三任务型真链 | ✅ AnalysisRegistryTests 13/0/0（嵌入行落库/取消增量/翻档保旧维/进度单调采样/串行序） |
| 4 | 导入接线三态 | ✅ 真 ImportService 链 ×3（ask 弹/always 跳/never 仅嵌入） |
| 5 | remember 写回 + reset | ✅ LabelingDefaultsTests 13/0/0 |
| 6 | BackgroundTaskHosting 零 diff + 既有栏呈现 | ✅ `git diff` 0 文件；AI 任务经 `backgroundRegistry.register` 进既有 bar/dialog |
| 7 | 资源门 0 fail | ✅ 2797/16/0（激活态零新 skip；无模型环境 = sanity 测试 XCTSkip） |
| 8 | 登记闭环 + diff 边界 | ✅ 三测试文件 Project.swift × BUNDLE-MAP 双命中；diff 边界 = front-matter 全量 + DECISIONS §3/§9 申报三件 + 账本文件 |

## 偏差与申报（全量清单）

front-matter 外源码文件共三件，均功能性必需、commit body + DECISIONS 双
申报：①`generate_label_prototypes.py`（§3——独立脚本 mirror convert 先例）；
②`WorkspaceHostView.swift`（§9——AI leg 挂既有聚合面 + prompt sheet 宿主）；
③`AIInferenceService.swift`（§9——同一 memoized 引擎的 analysis typed 视图）。
计划文本自抬的两处执行裁决：AC#2 增补落点改 LabelEngineTests（§12）、
top_scores 主行独占（§5）——晨审可推翻，改动半径各一处函数。

## 打标准确面观察（挂 M2-10-07 走查）

- threshold 0.05 初值未动；真图命中质量 = LCR 页走查项（01 §9 真图相对序
  golden 同步补）。
- 原型 = 单句 en query（非多 query 均值）——命中质量上限已知，改进路线
  多 query 均值原型（v2，plan 风险节原注）。
- RAW 大图嵌入耗时未实测（mock 链测试 + 真链 sanity 均小图）；万张重算
  时长账留 M2-10-07 LCR 页实机（registry 可取消 + 增量，无进度硬门）。

## 交接（下游 plan）

- **M2-10-04（全文 + AI 描述/评片）**：零共享文件冲突（本波未触 02 产物与
  SemanticStoreTests）；WorkspaceHostView 本波新增 65 行（04 若同文件改动
  = 后提交方 rebase）。
- **M2-10-05（worker 进程）**：`AIAnalysisEngining` 协议缝（App 层，
  AIAnalysisRegistry.swift 内）+ `AIInferenceService.engine()` 装配单点——
  worker conformer 落地后 swap 处 = `engineProvider` 闭包一行。
- **M2-10-06（增强）**：`recomputeAll` 的 manifest 消费模式（embeddingDim
  nil 拒绝）已钉；增强模型 `embeddingDim == nil` 路径同型。
- **M2-10-07（LCR 设置页）**：`LabelingPreferences.reset()` 钥匙就绪；
  labelingMode 三态 UI + 「重置 AI 兼容性记录」同页；threshold/命中质量
  走查在本页做。

## 阻塞节

无 E3 阻塞。环境注记：CoreML 编译缓存热（02 预热），全套 975s 正常水位。
