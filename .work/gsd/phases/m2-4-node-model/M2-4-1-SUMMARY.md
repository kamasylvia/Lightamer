# M2-4-1-SUMMARY — 模型核收口（plan M2-4-1，P1 六任务）

> 收口时间：2026-09-30（夜间授权执行批）。plan 正本 = 同目录 `M2-4-1-PLAN.md`
> （checker 修正版 `c94aa3c`）。配套 = `M2-4-1-DECISIONS.md`（KD 确认 +
> D-M2-4-1-1..8）。**未 push**（验收批同守）。

## 任务与提交

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `22e3b32` | `feat(core): pipeline document read-only facade` — PipelineDocument（Graph/ 新目录）+ PipelineDocumentTests 5（LightamerTestsLayers）+ Project.swift/BUNDLE-MAP 登记 + tuist generate |
| T2 | `02a2835` | `feat(core): node graph command set with identity-preserving undo` — 7 命令纯 apply + LayerStack.insert/nextLayerName 下沉（M4 单源）+ EditorState.apply + NodeGraphCommandTests 17（App，含 E4 像素级 bypass 断言） |
| T3 | `52cf75e` | `feat(iop): node ownership catalog with grade insert validation` — NodeOwnership（Core）+ NodeOwnershipCatalog（IOP，零字面量）+ addModuleToLayer 缝 + NodeOwnershipCatalogTests 6 |
| T4 | `b7d7acd` | `feat(core): sidecar schema v5 additive mask and raw override fields` — v5 additive 事务 + SidecarV5Tests 7 + 版本 pin 随动（D-M2-4-1-4）+ testgain/passthrough 改列（D-M2-4-1-5） |
| T5 | `48e2b7d` | `feat(app): persist raw decode overrides in sidecar v5` — E1 恢复腿 re-decode + 写腿透传钩 + attach 双向缝 + AC7 真链 3 tests（SidecarV5Tests 终值 10） |
| T6 | 本提交 | SUMMARY/DECISIONS + GOAL-STATE 续接点 + LESSONS L046 |

## 全套回归终值（批准后实跑）

**`Scripts/test-direct.sh --all` = TOTAL|2203/14/0|723s，EXIT=0**（2026-09-30
orchestrator 批准后实跑；对照基线 2165/14skip/0fail @ `d7f87fe`）：

- 计数对账：2165 基线 + **38 新增**（PipelineDocumentTests 5 + NodeGraphCommandTests
  17 + NodeOwnershipCatalogTests 6 + SidecarV5Tests 10 = 38）= **2203 精确**；
  skip 14 精确不变；0 fail；全程 723s（< 1135s 预算）。
- 逐 bundle：IOP 457/1/0 peakRSS=7367MB · IOPParity 308/2/0 5984MB · Layers
  169/2/0 945MB · Library 430/4/0 295MB · Sessions 279/4/0 1595MB · Export
  260/1/0 6121MB · App 300/0/0 1468MB。MEMFAIL（8G 口径）零触发；host RSS
  巡视 ~2 分钟间隔全程 <4G 峰值（IOP 段 3.9G），未动用 kill 回退条款。
- 在案 flaky（LayerE2E SIGTRAP 负载型）：本轮未触发（Layers 18s 全绿一遍过）。
- 运行期资源监控条件（每 ~2 分钟 host RSS + >8G 即杀）按批准条款执行，未触发。

## AC 表核验（11 条全绿）

| # | AC | 结果 |
|---|---|---|
| 1 | PipelineDocument 投影 parity + retouch 排除 + 纯函数性 | ✅ PipelineDocumentTests 5/5（序/id/name/enabled/mix 逐项、空栈三段、同栈两次 init 相等） |
| 2 | 7 命令语义 + 锁/钳/载荷拒绝 + SetMix(0)≡bypass 像素级 + undo/redo 保 UUID + InsertFromJson 字节复原 | ✅ NodeGraphCommandTests 17/17；E4 = setGradeMix(0) composite vs enabled=false composite 逐字节相等（容差 0；-0/+0 经 8-bit display tail 同折 0x00）+ mix=1 可见性防空转 |
| 3 | 新枚举 switch 穷举零 default | ✅ `git grep -n "default:" NodeGraphCommand.swift PipelineDocument.swift` 零命中；EditorState.apply 两处消费者编译穷举 |
| 4 | 所有权完备性 + 四件 DRT/Post + validate 矩阵 + 表零字面量 | ✅ 6/6；`git grep '"' NodeOwnershipCatalog.swift` = 0 命中；默认 face 非 grade 集恰 13 钉死 |
| 5 | addModuleToLayer typed 拦截；加载/undo/复原零校验 | ✅ 拦截 + toast 单测绿；既有 suite 全绿（Library/Sessions/Layers 无回归） |
| 6 | sidecar v5：nil 零漂移 + v1..v5 矩阵 + 容忍 >5 + 写者恒发 5 | ✅ SidecarV5Tests 10/10（canonical bytes 无新键 + stableHash parity + driftDetected 同值 + future 解码 + encodeIfPresent 缺键） |
| 7 | RAW overrides 真 load 链 round-trip（含 pristine 单 decode + nil 档不带键 + RawDecodePanelView 零 diff） | ✅ 3 真链用例绿（真实 EditorState+PipeCoordinator+WorkspaceModel 装配 + input/RAW fixture；写腿落盘→重装配恢复腿→readback 带 overrides→回注；pristine 零 re-decode）；`git diff RawDecodePanelView.swift` 空 |
| 8 | 渲染红线零 diff | ✅ `git diff --name-only | grep LayerCompositeDriver/PixelPipe/PipeCacheKey` 空 |
| 9 | 全套回归 0 fail，计数 ≈ 2165+20..28 | ✅ 2203/14/0（+38，略超预估带因 SidecarV5Tests 终值 10 > 预估 7——T5 真链 3 例并入同文件；对账口径见上） |
| 10 | diff 边界 == 申报文件集 | ✅ 逐 commit 只 add 申报文件；全 plan 累计 = front-matter 集合 + SidecarMetadataV3Tests/NodeOwnershipCatalog 两处已备案随动（D-M2-4-1-4/5，DECISIONS 在册） |
| 11 | 新测试文件登记闭环 | ✅ 四测试文件逐一在 Project.swift 对应 bundle sources + BUNDLE-MAP 行（LAYERS 5 / APP 17 / APP 6 / APP 10）+ 同 commit tuist generate |

## KD 确认与两处 plan 期裁定复核签注

KD-1..5 全部按 plan 落地（逐条确认见 DECISIONS「KD 执行确认」）。两处签注：

1. **Clarity 位源 op = equalizer（维持）**：复核发现 localContrast（dt bilat，
   IOP-DETAIL-02 clarity 等效交付）为第二候选；研究正本 feature-map §2.1 映射行
   「highpass / equalizer → Clarity」支持 plan 裁定，localContrast 留 .grade。
   M2-5 若改判 = 表一行 + 测试两处 pin 一行（D-M2-4-1-1）。
2. **rawOverrides hash-isolation 理由**：decode 域载体已由 decodeParamsHash 代表，
   二次折叠 = 同一信息双记账；drift 重算以文件自身 decode stamp 为种子，
   overrides 变更随 decode stamp 传播。对照面：蒙版三字段进 mask 域
   （stableHash 自然折叠）。双向机器钉（D-M2-4-1-2）。

## v5 字段终表

| 字段 | 位置 | 缺省语义 | 落盘 | hash 域 |
|---|---|---|---|---|
| `enabled` | MaskGroupItem | nil = true | ✅（drawn payload verbatim） | mask（stableHash 折叠） |
| `displayName` | MaskGroupItem | nil = 派生显示名 | ✅（同上） | mask（同上） |
| `deletionProtected` | MaskSpec | nil = false | runtime/snapshot 拼写；sidecar 投影缺口径挂 M2MASK-04（D-M2-4-1-3） | mask（同上） |
| `rawOverrides` | LightamerSidecar | nil = pristine（单 decode） | ✅ encodeIfPresent 缺键 | **hash-isolated**（decode 域，decodeParamsHash 代表） |

写者恒发 schemaVersion 5；读者容忍矩阵 v1..v4 全 nil + `>5` 容忍在册。

## 偏差与登记

- 五处执行期裁定（D-M2-4-1-2/4/5/6/7/8，含两处「既有测试随动」）全部在
  DECISIONS 备案，均为机械随动或语义勘误，无行为越界；晨审可推翻（各条
  附翻转代价：一行表/一行测试）。
- 执行期观察两条（同图 re-decode 层栈投影丢失 = pre-existing M2-3-3 语义；
  re-decode 交叠窗 isDecoding 灯）入 DECISIONS「执行期观察」，不属本 plan
  diff 面，M2-4-2+ 可裁。
- LESSONS L046 新增（测试装配 tuple 弃元 = 弱引用网静默死亡，三轮调试归因）。
- REQUIREMENTS 翻账按派发指令留验收批。
