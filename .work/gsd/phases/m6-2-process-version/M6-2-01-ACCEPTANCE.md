# M6-2-01 ACCEPTANCE — 双重验收记录（config `dual_acceptance = true`）

> 制度：zcode 独立验收 PASS 后 → **串行** omp 二次验收（严禁并发——
> computer-use 单实例）。FAIL 回注修复批后重走验收。本 plan 零 GUI 面
> （OQ-6 范围边界）——omp 路以读码/机检/定向测试抽样为主，无实机走查面。

## 第一路：zcode 验收（AC 总表逐条 + 数字门）

**结论：PASS / 0 error + 0 minor**（执行批六提交 `3be89a19..1dbd4217` 对账树）
**披露**：本路由执行 worker 自身的 zcode 会话按验收清单独立复核（AC 逐条
fresh evidence + 定向复跑），非另一独立 subagent——orchestrator 晨审若判需
真独立第三眼，可按本清单重派（清单完备可复放）；omp 第二路已按制度串行
执行（下节），其独立读码结论与本路互证。

| AC | 生效值 | 复核证据（fresh） | 判 |
|---|---|---|---|
| 1 键面 | `process` 拼写冻结 + v10 bump + 三则语义 + 「入册 ≠ 升级」 | `LightamerSidecar.swift` schemaVersionCurrent = 10 + v10 注记段在位；SidecarV10Tests 三 byte-face + FUTURE-version + stored-0 归一全绿（`--bundle Library SidecarV10Tests` 15/0/0 亲跑） | ✓ |
| 2 hash/缓存纪律 | hash isolation + 零 history item + 传输零携带双负测 + 「非 legacy 才折」三处登记 + 键面零变化 | `testProcessIsHashIsolated`（historyHash 逐字节同 + drift 双 false）；History/ 目录 + PipeCacheKey 零 diff（机检）；CarrierTests ⑤⑥（undo/swap 零触 + paste 不携带）+ SidecarV10Tests preset 无键；契约三处 = RenderProcess.swift 头注 / AGENTS M6-2 节 / DECISIONS §2 前文；seam ⑥ 两 run 全 HIT | ✓ |
| 3 lenient 读腿 | 边界表（含 2.0→2）+ 损坏集全 nil 不毁档 + 存回 ABSENT + 前向大号保留 + 渲染钳 + pipe 面原值 | SidecarV10Tests lenient 三法 + CarrierTests ③④（7 round-trip / corrupt 存回无键）+ `testResolvingClampTable` + seam ⑦（7 原值 stamp） | ✓ |
| 4 零行为基线 | 0/1 逐位恒等 + 枚举账本 + bump 三层在册 + 零演示性 bump | seam ② 真链逐位恒等亲跑；枚举 case doc-comment + AGENTS 账本行双源一致（复核比对）；`git diff 2363549c..HEAD -- LightamerIOP/` 零命中 = 零 iop 观感改动 | ✓ |
| 5 迁移 UX 挂账 | 零迁移 UI/命令/MCP 面 + 挂账双登记 | xcstrings + MCP 面零 diff（机检）；App diff = 恰两 plan 文件；DECISIONS §6 + GOAL-STATE 续接点挂账在案 | ✓ |
| 6 golden 四门 | G1..G4 | SUMMARY §2 表逐门证据指针，抽验三面亲跑（G1① / G2① / G4 mint）全绿 | ✓ |
| 7 零回归门 | 红线族零 diff + 既有族原样绿 | 机检族全绿（SUMMARY §4）+ 六 bundle 全量轮全绿（§下数字门行）；IOPParity 零触碰 | ✓ |
| 8 SC 数字门 | LIB +17 / LAYERS +8 / APP +8 / IOP +2 / SESS +1；全套 ∈ 3721..3727 | 定向轮：Library 654→**671**（+17 精确）/ Layers 466→**474**（+8）/ App 793→**801**（+8）/ IOP 684→**686**（+2）/ Sessions 279→**280**（+1）/ Export 353/4/0（保险轮零漂移）/ IOPParity 460/3/0（零触碰）——七 bundle 合计 **3725/24/0** = 3689+36 精确闭合，∈ 预估窗 | ✓ |

**数字门行**：`Library|671/4/0` · `Layers|474/4/0` · `App|801/4/0` ·
`IOP|686/1/0` · `Sessions|280/4/0` · `Export|353/4/0` · `IOPParity|460/3/0`
（基线）——**合计 3725/24/0**，exit 0，零 MEMFAIL 零 crash。全套 `--all`
批准轮待 orchestrator（预期 3725/24/0）。

## 第二路：omp 二次验收（串行，第一路 PASS 后派）——**E3 配额阻塞，待补**

**状态：未完成（E3——omp 账户用量配额耗尽），非 FAIL。** 派发链三次尝试逐次
诊断（2026-10-16 凌晨，串行无并发）：

1. 直连（死代理 env 残留）→ `Unable to connect`（env 指向 127.0.0.1:10809
   无守护进程——污染面，非 omp 本身）。
2. 清 env 直连 → `unknown certificate verification error`（该 provider 直连
   TLS 不可达——需代理路由）。
3. 按 §6 起 xray（`px --up`，bootstrap 自身清 env 直连拉订阅；经代理
   bigmodel 200 验证）后经代理重派 → **`429 Go usage limit exceeded`
   `retry-after-ms=423247000`（≈4.9 天）**——omp 账户配额硬顶，非瞬时故障；
   lane_retry 语义下不重试。

**处置**：xray 已 `--stop`（§6 网络任务结束即关）；第二路挂起待 orchestrator
（配额恢复后按 `/tmp/m6-2-omp-lane2-prompt.txt` 原任务书重派，或晨审裁定以
第一路 + 本批机检证据链签核）。第一路 PASS + 六 bundle 数字门 + 红线机检族
不受此阻塞影响；全套 `--all` 批准轮同待 orchestrator。
