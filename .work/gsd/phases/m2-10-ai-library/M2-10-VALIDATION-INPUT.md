# M2-10 VALIDATION INPUT — phase 签核输入汇总（2026-10-04 执行批落盘）

> C 档门控第 3 停输入 = 本文件。verify-work 签核前用户过目：七 plan 交付索引
> + 测试对账终值 + 挂账/观察清单。状态：**执行+验收闭环（01..06 验收 PASS），
> 07 执行批闭环（续班 2026-10-07，T4 提交落库）待验收轮**；TOTAL 实测已补
> （下节终轮定案行）。

## Phase 交付索引（七 plan）

| plan | 交付 | SUMMARY | DECISIONS | ACCEPTANCE | 测试增量 |
|---|---|---|---|---|---|
| M2-10-01 | 模型资产五档位清单 + ModelAssetStore（下载三源/流式 SHA-256/原子晋升）+ digest fail-closed | `M2-10-01-SUMMARY.md` | §1..8（§6 = Release 上架维护者清单） | PASS 2026-10-03 | +141 |
| M2-10-02 | LibrarySchema v4 七表 + SemanticStore/vDSP 扫描 + GlobalSearchDialog CLIP tab 真腿 | `M2-10-02-SUMMARY.md` | §1.. | PASS 2026-10-03 | +41 |
| M2-10-03 | LabelQueries 173×zh/en + LabelEngine + AIAnalysisRegistry + 导入接线（ask/always/never） | `M2-10-03-SUMMARY.md` | §1.. | PASS 2026-10-03 | +38 |
| M2-10-04 | AIProviderClient 双协议 + AICredentialStore/EndpointPolicy + 评片/描述服务 + 确认门 + fulltext tab | `M2-10-04-SUMMARY.md` | §1..16 | PASS 2026-10-04 | +66 |
| M2-10-05 | `--ai-worker` 同 binary 子进程 + 帧协议 + crash-safe 降级链 + CompatRecord | `M2-10-05-SUMMARY.md` | §1..15 | PASS 2026-10-04 | +27 |
| M2-10-06 | sidecar v8 provenance + TileInference/EnhanceEngine + EnhanceCopyWriter + import 孪生 + EnhanceDialog | `M2-10-06-SUMMARY.md` | §1..14 | PASS 2026-10-04（M-1 由 `c573087` 闭环） | +36 |
| M2-10-07 | LCR/ACA 设置页 + 双入口 + Inspector AI 区 + zh 全量 + M2AI-08 核验 + 翻账收口 | `M2-10-07-SUMMARY.md` | §D1..D15 | 待验收轮 | +26 |

phase 测试合计（BUNDLE-MAP 增行口径）= **+375**；checker M9 估测区间 +202..254
只做预算（实际超出的主因 = 02/03/04 波的 Core 级表/store/服务面测试密度，
逐波验收均已精确对账）。`c573087`（06 验收 M-1 修复批）另有 +3。

## 测试对账终值（--all 终轮，执行方实测）

- 基线链：2577（M2-8-VALIDATION）→ +141+41+38+66+27+36 = 2885…（逐波验收
  实测 2759/2797/2863/2890/2926 精确对账在案）→ `c573087` +3 = **2929** →
  本 plan +26 = **2955 预期**。
- 终轮实测：`--all` 于 `9586c1b`+（T4 批构建）执行，结果 = 「TOTAL 实测」行
  （验收轮以 `/tmp` 日志 + 七 BUNDLE 行复核；L055 机检 = `terminated
  abnormally` 全零 + Executed 行逐值一致）。
- 终轮实测（2026-10-04 执行批首轮）：**`TOTAL|2955/16/1|1129s`**——唯一
  fail = **在案 ANE 环境型 flake** `SidecarV5Tests.testWriteLeg…`（第四波
  记账，`M2-10-07-SUMMARY.md` 专节；隔离 11/0/0 绿 + 本波域零接触机检在
  案；App 基线 604〔601 + c573087 +3〕+ 26 = 630 精确）。
- **终轮定案（2026-10-07 续班，本行 = phase 终态判据）**：全套 `--all`
  重跑 **`TOTAL|2955/16/0|1019s` 单轮干净绿**——六 bundle 与基线零漂移
  （IOP 467/1/0 peak 5737MB、IOPParity 362/3/0、Layers 298/3/0、Library
  581/4/0、Sessions 279/4/0、Export 338/1/0）+ App **630/0/0**（SidecarV5
  13.338s passed 复绿，ANE flake 第五波收口两红三绿环境型归因维持）；
  skip 16 = 基线零新增；L055 机检七日志 abnormal 全零；peakRSS 最大
  5737MB 零 MEMFAIL。**2929 基线 + 26 = 2955 精确对账，0 fail 达成**。
- 真模型 golden 激活态：05/06 两波验收均非 skip 亲点（AIWorkerClientTests 真
  链 + EnhanceDialogTests 64²→256² ≤1/255）；本轮 `--all` 资源门在场环境激活。

## M2AI-01..10 终态（翻账正本 = `REQUIREMENTS.md`，此处索引）

M2AI-01 ✅（本波设置 UI 半边兑现，全族闭环）／02 ✅／03 ✅（labelingMode UI
本波兑现；命中质量走查挂下表）／04 ✅（ACA 页 + Inspector 评片 UI 本波兑现）／
05 ✅（描述触发 UI 本波兑现）／06 ✅／07 ✅／08 ✅（零新增核验 + defer 签认，
`M2-10-07-DECISIONS.md` §D14）／09 ✅（双入口本波兑现）／10 ✅（resetAll 按钮
本波兑现）。

## 挂账 / 观察清单（全部为观察项，非交付缺口）

1. **Release 上架维护者清单**（01 DECISIONS §6）：jina-clip-v2 int8 /
   real-esrgan-x4plus fp16 / drunet-color fp16 三资产 digest 回填 + GitHub
   Release `ai-models-v1` 上传——上架后 LCR 页/对话框下载行零 UI 改动解锁。
2. **命中质量走查**（03 挂账）：threshold 0.05 / 单句原型上限的实图观感
   （LCR 页自动打标打开后看标签质量）——headless 盲区，计算机检已绿。
3. **真批量增强队列**（06/07）：多选顺序单张循环已可用；并发/断点续跑队列
   = 需求出现再立项。
4. **「衍生自」徽标**（06 交接④ / OQ-4-C 后手）：join 键定案
   `source_image_id` = 库行 id 十进制（07 DECISIONS §D7）；网格徽标 UI 后手。
5. **设置页/对话框视觉走查**（07 plan 风险节）：headless 以 marker/AX 机检 +
   模型级测试为门；Alcedo 对照截图走查归验收轮（M2-3 computer-use 方法学）。
6. **SettingsDeepLink 已开窗口限制**（07 DECISIONS §D11）：Settings 窗口已开
   时 pendingPage 滞留至下次开启消费——v1 已知。
7. **100MP 级增强内存**（06 M-1 → `c573087` 两阶段 engine + typed
   memoryBudgetExceeded 门）：12MP@×2 实测 −38%；>6 GiB 预算工况 typed 拒绝
   + 诚实文案；行带流式（E3）为正解，挂 Maintenance。
8. **性能实测表**（phase perf.md）：嵌入扫描 200k×512 median 32.05ms（02 波
   两轮 ≤50ms 硬门 PASS）+ tile 基准 20.55ms/tile（01 波）+ IPC spike
   （05 波：ping 0.025ms / 50MP TIFF 路径通道 15.5-19.4ms）——在案，
   60fps@100MP 终验归 M2PERF-01。
9. **Manual-Only 四行 + flake 台账**：SidecarV5Tests ANE 环境型 flake
   （**五波两红三绿**记账终态：01 执行 / 06 验收 / 07 首轮红、07 补跑 /
   07 续班终轮绿——06 验收 O-1 建议另案硬化维持）；Library 缩略图队列
   flake（05 验收 O-1，06 未复现）——沿用既有台账。
10. **worker 编译缓存冷启动**（05 波 ~400s 首轮）：真机首启观感走查项。

## 签核路径

verify-work 输入 = 本文件 + 七 SUMMARY + 三 ACCEPTANCE（01/02 合并轮、05/06
单独轮）+ REQUIREMENTS M2AI 族终态 + `M2-10-07-DECISIONS.md`。签核后 phase
收口（GOAL-STATE 翻账 → M2-11 交接）。
