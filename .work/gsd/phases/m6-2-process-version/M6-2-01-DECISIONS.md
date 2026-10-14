# M6-2-01 DECISIONS — per-photo process version 执行批决策与登记

> 六项 KD（KD-1..KD-7）执行期**零重开、零偏离**——本文件登记：checker 回注项的
> 落地形态（E1/M1/M4）、plan 预登记面的兑现申报、诚实申报项（钳制形式正确性/
> resolving 零消费点/挂账件）、与执行期两处测试面微修（SUMMARY §6 同文）。

## 1. E1 双登记（checker error 回注的落地与范围申报）

1. **pre-M6-2 数据保真缺口（明确不修，出范围）**：`SessionBatchApplier`
   既有档 batch apply 臂今日（含本批后）从 decode 出的 document 仅提升
   **5 字段 + process stamp**（history/instances/decodeParamsHash/imageID/
   decoderVersionUsed + processStamp），随后与 pristine 臂共汇
   `LightamerSidecar(` 构造点重建**全新档**——文档级 additive 字段
   `provenance` / `rawOverrides` / `displayTransform` / `versions` /
   `activeVersionID` / `aiProvenance` / `filmRecord` 在既有档 batch apply 时
   **被静默丢弃**。这是 pre-M6-2 的数据保真缺陷（非本批引入），M6-2 按 plan
   范围纪律**不修**；挂观察项待未来 fix batch（与 M6-5 挂账清算批的汇编面
   同类）。process 在本臂不修即会随其余字段一同被丢——这正是显式携带的动机。
2. **process 在本臂的携带 = M6-2 显式新增面（非「自动保全」）**：落地形 =
   `processStamp: RenderProcessVersion?` per-arm 提升（既有档臂 =
   `document.process` 原值含前向大号照搬；pristine 臂 = `.current`），构造点
   传 `process: processStamp`。**跨臂共享 `document.process ?? .current` 形
   禁用**（nil 撞 `?? .current` = 给 legacy 既有档 mint，违反 OQ-1）——禁令
   注记已写死在两处代码位（提升点 + 构造点）。测试 = SessionBatchApplierTests
   `testBatchApplyStampsProcessBranchConditionally`（pristine = 1 + 既有档
   三态一法：legacy 保 ABSENT / 1 保全 / 前向 7 保全）。

## 2. M1 双门分离注记（值类型域门 vs sidecar 存储门）

`RenderProcessVersion.init?(rawValue:)` 值类型域门 = **`0...0xFFFF_FFFF`**
（含 0 = legacy 哨兵——内存载体的合法域）；sidecar **存储值** decode 域门 =
**`1...0xFFFF_FFFF`**（stored-0 / null / 损坏 → nil 归一 ABSENT——0 ≡ 缺键 ≡
legacy 是同一语义，LightCraft `skip_serializing_if = "ProcessVersion::is_legacy"`
同构）。OQ-3 散文表「合法域 = 0..2^32−1」的读法以本注记为准：**stored-0 不保留
为 0**（KD-2 的 stored-0 归一化钉死面优先）。两门已各自测试钉死：
`testVersionTypeDomainGateAndConstants`（值门含 0）/ `testStoredZeroNormalizesToAbsentKey`
（存储门 0 → ABSENT）。三处代码注记在位（RenderProcess.swift 值门 doc /
LightamerSidecar.swift decode 段 / AGENTS M6-2 节）。

## 3. M4 ProcessProbeModule 可行性确认（checker 无行动项的兑现记录）

T2 落地亲证 checker 判读：`IOPModule.process(... piece: inout IOPiece ...)`
签名 + `IOPiece` public struct + `RenderProcessVersion` 落 `LightamerCore/
Sources/Pipe/`（与 IOPiece 同模块）——测试替身 `ProcessProbeModule` 读
`piece.renderProcess` 可见性无碍；TestGainModule test-local 先例形
（IOPieceIscaleTests.IscaleProbe 同力学：ModuleBox 直构造 + actor recorder +
blit 直通臂）。零阻碍兑现，无偏差。

## 4. 出生点盖章字节面影响申报（KD-7 预登记面的兑现）

Session 两 writer 的 mint 臂产物新增 `"process": 1` 键（新档非既有档漂移）；
ImportService AI 副本 / StackMergeService 两 writer 同批。**既有测试零浮出**
（Sessions 280 / Library 671 / IOP 686 全绿——KD-7「若既有测试钉其全字节 →
定向修」未触发）。合并产物 birth sidecar 的真实生产腿证据 =
StackMergeServiceTests `testHDRLegBirthSidecarStampsCurrentProcess` /
`testMertensLegBirthSidecarStampsCurrentProcess`（合成 decodeLeg + 真 merge
leg——MertensLegTests 同位力学，StackMergeServiceTests 原文件全程 stub 腿
不触生产 writer，故 +2 法按真腿形落地于该文件）。

## 5. 钳制形式正确性注记（诚实申报）

M6-2 时点 `RenderProcess.resolving` 的钳制（前向大号 → current；≤0 → 最老
case）**目标 = v1 ≡ legacy 行为**——渲染逐位恒等（G3），无观感差异可观察。
钳制测试（`testResolvingClampTable` + `testForwardLargeNumberStampsVerbatim`）
证的是**形式正确性**（表映射 + 原值贯通 + 钳制在消费点不在 stamp），非观感
差异。首个真实分叉落地时该注记由新 golden 取代。

## 6. resolving 无生产消费点申报（KD-5 挂账同文）

M6-2 交付面 = 缝 armed + 零行为：`PixelPipe.renderProcess` 属性、IOPiece
stamp、六处派生 pipe 继承全部在位，但 **coordinator → pipe 的生产传值不接线**
（装配点调用不传 = 缺省 `.legacy` = 与今日逐字节同——零消费即零行为，传值是
无消费者的死接线）。**首个真实分叉批的接线件挂账**：①PipeCoordinator 各
render 调用点读 processVersion 载体传 `renderProcess:` ②分叉 iop 在
`process` 内消费 `RenderProcess.resolving(piece.renderProcess)` + 穷举
switch ③该 stage 缓存键按「非 legacy 才折」折值 ④「Update to Current
Process」迁移 UX 同批裁形（OQ-5 挂账）。文档值 → pipe 的贯通已由 G2③
（sidecar decode → 载体 → RenderPipeline.process(renderProcess:) → piece）
显式证明，非断言。

## 7. 执行期测试面微修登记（零产线改动，SUMMARY §6 同文）

- resolving 负数构造崩 → 域门设计正确，测试改单式（T1）。
- CarrierTests flush 竞态 → 内容谓词轮询 `flushUntil`（T3）；decodeParamsHash
  断言修正 = writer 面活原子重盖章（既有惯例）。
- SeamTests G2①/② 合一法 → 拆两法合 plan「8 法」（T2）。

## 8. 与 LightCraft 的有意偏离（登记）

- **版本槽不承载 process**：LightCraft per-settings 快照使版本恢复带回「它
  当时的 process」；我方 process 是文档级键、跨 versions 槽共享（版本 swap =
  history 链换装不触 process）——RESEARCH §3.2 的显式偏离，CarrierTests ⑤
  钉死（undo 到顶 + swap 后仍 1）。
- **legacy 记 0 非 V1=1**：我方概念引入前的渲染记 0（更诚实——无「命名过的
  历史渲染」可指认）；枚举账本首 case = v1（mint 本代）。RESEARCH §3.1 同文。

## 9. 待供件清单

无。全部面有源可查；无「待核/待定/待补」标注。
