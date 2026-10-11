# fix(film-leg) — M3-3 Film leg 引用计数竞态修复 + M4-1 挂账 #6 收口

> 修复批正本（2026-10-12/13 夜间，ZCode subagent worker；夜间全自动授权在案）。
> 派发对象 = `M5-1-03-ACCEPTANCE.md` §7 新登记 P1（非 M5-1/M4 引入，M3-3 时代即存在）
> + 挂账移交 ④「M4-1 #6 孤儿预防」。任务令四件：根因读码 / 修复 / 回归 / #6 收口。

## 结论

**PASS——竞态结构性根除（读码 + A/B 压力双实证）；M4-1 挂账 #6 闭环。**
修复后全 App bundle 测试轮的阻断解除（TODO M5-1 行「修复后补全套 `--all`
全绿轮」= 后续轮事项，本批按派发令不跑全套）。

---

## 1. 根因（读码确认）

**槽**：`FilmMethodBox.runContext` = `nonisolated(unsafe) static var:
FilmGPUPayloads?`（修复前 `FilmTailPolicy.swift:305`）——进程级单槽。

**写序**（修复前 `PixelPipe.swift` `runFilmLeg` :1183-1184）：

```
defer { FilmMethodBox.runContext = nil }   // ① 登记 clear
FilmMethodBox.runContext = assembled.payloads   // ② set
...
try await filmPipe.runSub(...)   // ③ await = 悬挂点：走链递归
                                 //    （processRec）+ cache actor 往返
                                 //    全在此窗口内；box.process 读槽
```

**竞态机制（两面）**：

1. **内存安全面（= .ips 崩溃签名）**：非原子全局槽的 load-retain（box
   `process` 读槽）与 store-release（另一腿的 ② set / ① defer clear）并发
   交错 → 旧 payloads 过度释放 → 提前 dealloc；持同一对象的另一腿局部
   `assembled` 元组在作用域尾 destroy 时打在已释放内存上 =
   `_swift_release_dealloc → outlined destroy of (method: Params, payloads:
   FilmGPUPayloads?, …) @ runFilmLeg`——与 `.ips ×3` 同签名
   （`evidence/m5-1-03-acceptance/ips-1/3/4`）逐点吻合。
2. **正确性面（静默，无崩溃）**：A 腿 await 窗内 B 腿 set 覆盖槽 → A 的 box
   读到 **B 的 payloads**（错 payload 渲染）；或 A 的 defer clear 先落 →
   B 的 box 读到 nil → identity blit（静默恒等渲染）。

**触发条件**：两条 film leg 并发——GUI coordinator 渲染无跨腿互斥
（ACCEPTANCE §7 在案：滑杆 live 窗连续渲染 / 会话缩略图渲染等可交叠）。
M3-3 源码注释「one writer, synchronous window, no cross-run leakage」的
**串行假设在并发下不成立**（「single writer」实为「每个 run 都写同一全局」）。

**非本批引入（与 ACCEPTANCE §7 一致，本批复核）**：PixelPipe 末触 `1b2b520`
（M4 批），Film 域四提交零触碰；机制自 M3-3-02 引入静态槽起即潜伏。

---

## 2. 修复方案与理由

**选定：显式传参（payloads 随 box 实例走）；task-local 落选。**

| 改动 | 文件 |
|---|---|
| `FilmMethodBox` 增存储属性 `runPayloads: FilmGPUPayloads?` + `init(record:method:payloads:)`（payloads 默认 nil = 既有构造点零漂移） | `FilmTailPolicy.swift` |
| `FilmMethodBox.process` 读 `runPayloads ?? assemblyContextForTesting`（降级面逐字节不变） | 同上 |
| `FilmTailAssembly.instances(method:payloads:)` 构造时携带（唯一产线调用点 = `runFilmLeg`；测试零调用，签名直改） | 同上 |
| `runFilmLeg` 删静态 set/defer-clear，改传参（`assembled.payloads` → instances） | `PixelPipe.swift` |
| `FilmDescriptorProbe.probe` 同构（构造即携带，删 set/clear） | `FilmDescriptorProbe.swift` |
| **静态槽 `runContext` 整体删除**——编译期证明无残留读者（`grep runContext` 全仓仅剩历史注记） | 同上 |
| `assemblyContextForTesting` 保留（测试注入面，产线零写入 → 无竞态面） | 同上 |

**为何不选 task-local**：

1. 实例状态**零并发模型假设**：payloads 寿命 = box 寿命 = 腿 pipe 的 pieces
   持有期（`runSub` 期间恰好存活，既不提前释放也无静态滞留）；task-local
   则依赖「同任务传播穿透 `PipeCache` actor miss 闭包」的传播规则——对
   `@Sendable` 闭包的执行位置敏感，是第二处需要论证的微妙面。
2. 最小改动面：5 文件 81+/30-（含测试）；`init`/`instances` 增参均有默认值
   或唯一调用点，零签名破坏。
3. **DrtMethodBox 先例同构**：tail box 本就是 driver-constructed、per-run
   数据自带（params 内嵌）；GPU payloads 非 Codable 不得入 Params，实例
   属性是该先例的自然延伸。

---

## 3. 回归证据

**复现载体**（ACCEPTANCE §7 钦定 = `FilmPanelTests`，指令
`Scripts/test-direct.sh --bundle App FilmPanelTests`）：

| 轮 | 树 | 结果 |
|---|---|---|
| 修复后 ×3 | 本批 | **6/0/0 全绿**（65s/63s/57s）——验收批同指令 3/3 SIGSEGV |
| 终轮（提交树） | 本批 | **6/0/0**（46s） |

**A/B 压力探针**（临时测试 `testProbeConcurrentFilmLegsDoNotStompPayloads`
——真链 film leg：portra 对**真 payloads**（真 buffer/table 装配），每轮换
strength 重建 payloads，TaskGroup 4 并发腿 × 40 轮 = 160 腿次高密度交叠；
**探针已撤，不入 commit**，`FilmLegTests.swift` 回落零 diff）：

| 腿 | 树 | 结果 |
|---|---|---|
| A（修复后） | 本批 | **10/0/0 全绿**（47s） |
| B（`git stash` 修复，pre-fix Core 重建） | 修复前 | **宿主 SIGSEGV**（exit 139，`terminated abnormally`），探针开跑后即崩（`/tmp/la-direct-tests-Layers.log`）——pre-fix 一击复现 |

A/B decisive：同探针、同宿主、同轮次，修复前崩 / 修复后绿。stash pop 恢复
后终轮复归全绿。

**域回归（本批定向四轮，全绿零 MEMFAIL）**：

| bundle | 指令 | 结果 |
|---|---|---|
| Layers | `--bundle Layers FilmLegTests` | **9/0/0**（终轮 10s；3×2 矩阵 + fused kernel 全过） |
| IOPParity | `--bundle IOPParity FilmGoldenTests` | **16/0/0**（136s；含 `FilmDescriptorProbe` 面 = probe 改动点直测） |
| Export | `--bundle Export`（全量） | **350/1/0**（205s；1 skip 存量） |

---

## 4. M4-1 挂账 #6 收口（孤儿 `srgb-matrix-8.tif.lra`）

处方 = `M4-2-03-PLAN.md` T5 + `M4-1-02-ACCEPTANCE-OMP.md` §一.3
（写腿 tmp 域 + 双前清 + 读方前清）：

1. **写方治本** `RasterRoundTripTests.testEditReplaySurvivesFlushAndReload`
   （Export bundle）：fixture 先拷入测试 **tmp 域**（UUID 目录，tearDown
   整体清扫）后编辑副本——sidecar 写腿随行落 tmp，仓内
   `Tests/Fixtures/` **永不再生成 `.lra`**（App bundle 的
   `testRestoreWinsOverDerive` 读同路径假设起始干净的跨 bundle 轮间污染
   根除）。**双前清**：测试入口对 repo 侧车路径防御性 `removeItem`（防旧
   孤儿毒轮）+ 出口双清（tmp sidecar 显式清 + repo 路径防御扫）。
2. **读方前清** `RasterEditFaceTests.testRestoreWinsOverDerive`（App
   bundle）：入口一行 `removeItem(sidecarURL)`——「起始无 sidecar」假设
   确定性成立（写-behind 迟到孤儿不再 satisfy restore 腿）。
3. **孤儿清查**：`find Tests/Fixtures -name "*.lra"` 零命中（现存孤儿已由
   前批验收清除，本批复核在盘为零）；Export bundle 全量轮（205s 窗口）后
   复扫仍零命中——生成源已闭。
4. TODO.md M5-1 行同步勾翻（本文件为正本指针）。

---

## 5. 边界与移交

- **未跑全套 `--all`**（派发令明确）；「修复后补全套 `--all` 全绿轮
  （M5-1 对账 3477 亲证闭环）」留后续轮（TODO M5-1 行已注）。
- commit 未 push（派发令）；`fix(film-leg)` 单提交 = 3 Core + 2 测试 +
  本报告 + TODO 行。
- 工作区预存改动（`M5-1-02-ACCEPTANCE-OMP.md` modified、
  `M5-1-01-ACCEPTANCE-OMP.md` / `dt-clone-archive/` untracked）**非本批
  产物，未纳入 commit**。
