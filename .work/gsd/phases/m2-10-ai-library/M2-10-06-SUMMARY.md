# M2-10-06 SUMMARY — AI 出片可编辑副本（分块推理 + sidecar v8 + 副本落盘 + 对话框）

> 执行 worker 收口（2026-10-04 夜）。三个功能提交 + 本收口提交；
> 裁决与偏离正本 = `M2-10-06-DECISIONS.md`（§1..13）。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `dba72ce` | sidecar v8 additive（`SidecarAIProvenanceRecord` 六字段 D-3 snake_case + `aiProvenance` 双向 optional + schemaVersionCurrent 7→8 + v8 头注释）+ `TileInference.swift` 纯面（axisSpans 对齐末 tile / 线性 ramp 权重 / feedEdge / 400MP typed / 进度曲线）+ SidecarV8Tests 5 + TileInferenceTests 13 |
| T2 | `b4d13d6` | `EnhanceCopyWriter`（O_EXCL 命名递增 / 容器规则 / EXIF 继承 orientation 烘焙 / 失败清占位）+ `ImportService.importFile` 单文件孪生（复用 insertRow 内部 + album + .lra mint 带 provenance）+ EnhanceCopyTests 8 |
| T3 | `7786ff8` | 协议 additive（`AITileParameters` height/width/amount + `AIWorkerResult` tileEdges/scale）+ worker 增强 leg（`EnhancementSession` IO 发现/tile run + AIWorkerMain open/run/stop 分支）+ `AIWorkerClient.openEnhancement/enhanceTile` + `EnhanceEngine`（编排/blend/取消/进度/内存 pin）+ `EnhanceDialogModel` + `EnhanceDialog` + EnhanceDialogTests 10 |
| T4 | 本提交 | AC 机检 + 全套对账 + SUMMARY/DECISIONS/GOAL-STATE/LESSONS + BUNDLE-MAP 三行 |

## 测试数字（基线 2890/16/0）

- **终账：`TOTAL|2926/16/0|988s`** = 2890 + **36 精确对账**
  （TileInferenceTests 13 [LIB] + SidecarV8Tests 5 + EnhanceCopyTests 8 +
  EnhanceDialogTests 10，App 578→601、Library 568→581）。
- 七 bundle 逐值（本轮实测）：IOP 467/1/0（peakRSS 7090MB）、IOPParity
  362/3/0（5985MB）、Layers 298/3/0（1058MB）、Library 581/4/0（599MB）、
  Sessions 279/4/0（1607MB）、Export 338/1/0（5377MB，红线门零漂移）、
  **App 601/0/0**（2831MB）；peakRSS 最大 IOP 7090MB < 8192 门，零 MEMFAIL；
  skip 16 = 基线**零新增**（真模型 golden 在场环境非 skip）。
- 定向轮：SidecarV8Tests 5/0/0 + TileInferenceTests 13/0/0 +
  EnhanceCopyTests 8/0/0 + AIWorkerProtocolTests 10/0/0 +
  AIWorkerClientTests 9/0/0（05 零 diff 证明）+ import 三类
  10+2+7/0/0（孪生抽取零漂移证明）+ EnhanceDialogTests 10/0/0。

## 真模型 golden 实测（资源门激活态）

- **链路**：真 worker 子进程（`--ai-worker` 分叉臂）→ open 增强 leg（IO 名 +
  supported edges + scale 从模型描述**发现**：`[256]` / `4` 断言）→ engine
  规划 → 64² 合成梯度 pad-to-fit 单 tile → 路径通道 TIFF16 进出 →
  **256² 输出**（64×4）。
- **确定性**：两轮逐元素差 ≤ 1/255（实测显著更紧——同 CoreML 会话确定性前向）。
- **耗时**：端到端 2.748s（spawn + open + 两轮 engine + stop；编译缓存热；
  2.4MB mlpackage 冷编译亚秒）。tile 推理量级正本 = M2-10-01 转换基准
  20.55ms/tile（256²）。
- **100MP 端到端时数**：未实测（无 100MP fixture；测试域小图）。内存形态 =
  DECISIONS §12（fp32 输出整帧驻留 ≈ 6.4GB @100MP×4，贴 8G 门）；流水线化
  直写 = E3 后手挂账。

## 交付面形态（KD 对照）

- **T1（KD-1）**：sidecar v8 三字节面（v7 round-trip 逐字节 / 全 nil = v7 形
  仅版本号位差 / 带 provenance round-trip 逐字节）+ hash 隔离 tamper 负测 +
  operation 冻结值空间负测；tile 纯面 = exact-shape 网格（末 tile 对齐轴尾，
  零截断余数）、线性 ramp（归一化和恒 1 锚）、feedEdge（最小 supported ≥ span）、
  400MP typed、进度 15+78·done/total 单调。
- **T2（KD-3/KD-4）**：O_EXCL 并发占位唯一（8 并发去重断言）+ Lumen 命名形
  （首份无序号）；容器规则矩阵（DECISIONS §1）；16-bit 深度盘上断言；占位
  清扫；EXIF/orientation/GPS 三继承腿；真链 round-trip（Media/ 终名 → images
  行 + `.lra` provenance 回读 + 相册落位 + 原图零触碰）。
- **T3（KD-2/KD-5）**：capability discovery（DECISIONS §4——静态资产的实测
  消解）；engine 多 tile identity 锚（4 tile 网格 identity 桩逐像素还原）；
  取消 = checkpoint 贯穿 + 半成品 tmp 清扫 + close-after（Lumen :177-185 同
  型）；进度单调端点钉死；模型缺席 typed 面（digestUnpublished 诚实「待发
  布」）；对话框 = before/after 中央 192² + 模型档 + 下载行 + 进度 + 取消语义。
- **双入口接线归 M2-10-07**（本 plan 对话框可presentable，seams 全注入）。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | v8 三字节形断言 + provenance 不进 historyHash | ✅ SidecarV8Tests 5/0/0（逐字节 round-trip / 位差 / tamper 负测 / 冻结枚举负测） |
| 2 | reserve_copy 并发唯一 + N 递增 + 容器矩阵 + orientation 烘焙 + EXIF 键值 | ✅ EnhanceCopyTests（8 并发去重 + 矩阵 6 腿 + 盘上 depth=16 + 占位清扫 + EXIF/GPS/orientation） |
| 3 | 导入链 round-trip（Media/ + 新 images 行 + `.lra` provenance 回读 + 相册落位） | ✅ EnhanceCopyTests 真链（真 .lalb + 真 ImportService + 真 SidecarStore 文件链） |
| 4 | version_ref 零触碰（M4 消歧口径） | ✅ 原图字节 + sidecar 面断言 + `git diff` 零 version/VersionCoordinator 文件（DECISIONS §11） |
| 5 | 分块：切分/权重和一/余数族内/进度单调 + 取消删半成品 + close-after | ✅ TileInferenceTests 13 + EnhanceDialogTests（engine 取消清扫 + close-after 终态） |
| 6 | 真模型 golden：64²→256² + tile 一致性 1/255（资源门 skip） | ✅ 真子进程实测（在场非 skip；缺席环境 XCTSkip——0 fail 硬 AC 保持） |
| 7 | 导出管线/MCP 零 diff；既有 importFolder/sidecar 测试零改动 | ✅ 机检（Export/MCP/version 文件零命中；既有测试文件零改动全绿） |
| 8 | 资源门 + 登记闭环 + diff 边界 == 申报集 | ✅ `--all` 双读 2926/16/0；四测试文件 Project.swift × BUNDLE-MAP 双命中；diff 边界 = front-matter + DECISIONS §9 申报四件（含账本） |

## 偏差与申报（全量清单）

- front-matter 外源码文件 **4 个**（AIWorkerProtocol / AIWorkerClient /
  AIWorkerMain / AIWorkerEnhancement 新建）——计划正文授权 vs 清单漏列的起草
  缺口，全量论证 = DECISIONS §9。
- 计划文本外执行裁决 12 项全录 DECISIONS（§1 容器规则签注 / §4 tile 族终值 +
  capability discovery / §5 400MP 算术修正 / §6 强度语义 / §7 mint 形态 /
  §8 孪生落位 / §10 金样 / §11 M4 落点 / §12 内存形态，晨审可推翻）。
- 项目树零越界：Export/MCP/version 域文件零 diff（机检在案）。

## 首轮测试抓出的真缺陷（防线自证）

- **blend 行距错位**：blend 以 valid rect 宽（192）为 tile 缓冲行距，pad-to-fit
  时缓冲实宽 = feed（256）——行错位读成乱值。多 tile identity 测（exact tile）
  全绿掩蔽、pad 路径（preview 192²）当场抓红。修 = 行距用 tile 实宽。
- **裸 `await taskHandle` 不 join**（L065）：`await runTask` 零等待返回，测试
  断言落在中间态。independent swiftc 探针证（join 返回 0.0s）。修 =
  `await runTask.value`。
- **输出名假设**：worker 假设 `output_tile`（转换只命名 input）→
  prediction 后取不到 feature。修 = IO 名动态发现（input 优先 `input_tile`
  否则首个；output 取首个），金样测试当场抓红后修复通过。

## 交接（下游 plan）

- **M2-10-07（LCR/ACA 设置页 + 入口收口）**：①增强对话框双入口接线 = 把
  `EnhanceDialogModel` 的 seams（frameProvider / modelFacts / tileExecutor /
  EnhanceContext）接到 PipeCoordinator 渲染面 + AIWorkerClient + 当前项目/相
  册；②「重置 AI 兼容性记录」按钮 = `CompatRecord.resetAll()`（05 交接既
  述）；③release 档上架后，对话框下载行走 `ModelAssetStore.download`（现成
  UI 已接 `.notInstalled/.downloading/.corrupt/.digestUnpublished` 四态）；
  ④走查观察项：副本在网格的「衍生自」徽标 = OQ-4-C 后手（provenance 的
  source_image_id 即 join 键）。
- **Maintenance 挂账**：100MP×4 fp32 输出整帧贴 8G 门 → tile 直写 TIFF 流水
  线化（DECISIONS §12，E3 触发即转正式）。

## 阻塞节

无 E3 阻塞。环境注记：①首轮 EnhanceDialogTests 一次宿主 mid-run abnormal
（环境型归因，三轮复现全绿，DECISIONS §13）；②Library 缩略图时序 flake
（05 申报的同族）本轮 --all 未复现。
