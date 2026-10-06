# M2-11-01 SUMMARY — flaky 清算批（wave 1：脚本两件修 + 缩略图硬化 + 两环境案观测收口）

> 执行 worker（ZCode subagent，2026-10-07 夜间授权在案「开跑，不要停」）。
> 规格锚点 = 本目录 `M2-11-01-PLAN.md` + `RESEARCH-NOTES.md` §D + LESSONS L055/L028。
> 裁决正本 = `M2-11-01-DECISIONS.md`（KD-1..5 签注 + 执行期裁定 D1..D6）。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `6031e1e` | `fix(scripts): detect host crash and singular test count in test-direct`——Scripts/test-direct.sh（parse_bundle_log 抽取 + 崩溃签名 FAIL + 总计行校验 + 单数 regex 两处 + ANE-DEGRADED 注记 + LA_SELFTEST 守卫 + 头注释）+ Scripts/test-direct-selftest.sh 新建 + Scripts/test-direct-fixtures/{crash,singular,normal}.log 新建 |
| T2 | `f9284ca` | `test(library): harden thumbnail production reorder assertion`——LibraryThumbnailBridgeTests.swift 单文件（A-slot one-shot gate 序注入 + 失败路径放行 + defer exit） |
| T3/T4 | 本批 | GOAL-STATE flaky 台账段立表 + 续接点 + 本 SUMMARY/DECISIONS |

产线零触碰亲证：`git diff --stat 3c26336..HEAD -- App/ LightamerCore/` = 空（见文末对账）；Tests/ 唯一改动 = LibraryThumbnailBridgeTests.swift。

## T1 交付细节

### parse_bundle_log 抽取（KD-1）

- 判定逻辑全在 parse 内（m4 注）：executed/skipped/failed 计数、summary_fail 合并、
  crash / no-total-line / MEMFAIL / executed-0 / fail 判定、ru_maxrss 与 ps-poll peak 解析、
  ANE-DEGRADED 签名扫描；BUNDLE 行组装留 run_bundle（执行 + RSS 采样不动）。
- stdout 契约 = 五字段一行：`<E>/<S>/<F>|peakRSS=<MB>MB|sampling=<time|ps-poll>|verdict=<v>[ ANE-DEGRADED]`；
  stderr = ↳ 诊断行（仅非 ok）；**恒返回 0**（结果全在行内编码，run_bundle 据 verdict 置 ANY_FAIL——
  command substitution 下 set -e 不误杀）。
- LA_SELFTEST 守卫（m7 形态）：`return 0 2>/dev/null || exit 0`——source 消费（selftest）只暴露
  parse 函数；被执行消费干净退出。守卫位置 = parse 定义之后、bundle 注册表之前；`RSS_LIMIT_MB=8192`
  连同 SPIKE 注记上提到守卫前（set -u 下 source 路径 parse 判定需在册，D3）。
- 头注释同步：输出行格式（` MEMFAIL` / ` ANE-DEGRADED` 尾注记）、verdict 全集与计数置零语义、
  单数 regex 说明、LA_SELFTEST 用法。

### 两修语义（KD-2）

1. 崩溃签名：`terminated abnormally` 或 `Restarting after unexpected exit` → verdict=crash。
2. 总计行身份：无过滤轮末条 `Executed N tests?` 行向前找最近 `Test Suite '` 行，非
   `'All tests'` → verdict=no-total-line；过滤轮豁免（-XCTest 轮末条 = 'Selected tests' 类 suite）。
   两者计数置零报 `0/0/0`（AC1「末条类 suite 行不再被当 bundle 计数」的字面兑现，D2）。
3. 单数：`Executed [0-9]+ tests?` 施于 executed 判据与 summary_fail 外层两处（m1 注：两处同修；
   内层 `with [0-9]+ failures?` 本就兼容零触碰）。注：:165 外层 `^Executed` 锚在直启日志
   （Executed 行带 TAB 缩进）实践中恒不命中，本次不改锚语义只改单数——行为面零变化。

### ANE 注记（KD-3）

日志含 `ANECCompile` 且该行含 `FAILED` → BUNDLE 行尾追加 ` ANE-DEGRADED`（对齐 MEMFAIL 尾注记
形态），不判 FAIL。解析归 parse（m4），注记拼装归 run_bundle。

### fixture 设计（三 fixture + 两构造段）

- `crash.log`：L055 现场形态复刻——两个类 suite（DrtPanelTests 6 + GradeCatalogTests 15）的
  `\t Executed` 行 + `time: command terminated abnormally` 尾 + ru_maxrss 行（time 异常退出仍打
  usage 的真实形态）。行格式逐字符对齐真日志（TAB+空格前缀、时间戳形态）。
- `singular.log`：单测试轮 `Executed 1 test, with 0 failures`（单数）+ All tests 总计行在——钉
  单数 regex **且**钉总计行校验对单数形态不误伤。
- `normal.log`：正常 bundle 段（3 tests / 1 skip / All tests 总计行）——正向对照，五字段逐字节断言。
- 构造段（selftest 内建，不入 fixture 目录）：①normal.log + `ANECCompile() FAILED` 行 →
  ` ANE-DEGRADED` 注记且 verdict=ok；②crash.log 剥除崩溃行的截断形态 → 带过滤豁免（15/0/0 ok）
  / 无过滤 no-total-line（KD-2 过滤轮兼容负证，plan 风险节可选项兑现）。
- fixture 构造用 printf 保真 TAB 前缀；selftest 临时文件落 `$TMPDIR` 不污染 fixture 目录。

### 自证证据

`Scripts/test-direct-selftest.sh` 12 断言全绿（EXIT=0）：

```
ok   crash counts zeroed (AC1)
ok   crash verdict (AC1)
ok   crash no ANE note
ok   crash stderr diagnostic present
ok   singular counts (AC3)
ok   singular verdict (AC3)
ok   normal full five-field line (AC4)
ok   ANE note + verdict ok (AC5)
ok   filtered truncation exempt (KD-2)
ok   filtered truncation verdict
ok   unfiltered truncation FAILs (AC2)
ok   unfiltered truncation verdict
SELFTEST OK (test-direct.sh parse_bundle_log — 3 fixtures + 2 constructed)
```

### 等价性冒烟（T1 action 4）

旧记账逻辑（`git show HEAD:Scripts/test-direct.sh` run_bundle 记账段**逐字**抽取）vs 新
parse_bundle_log，对 2026-10-07 续班终轮存活的七份真实全套日志（/tmp/la-direct-tests-*.log）
逐 bundle 比对：**7/7 EQUIV 逐字段一致**——

```
EQUIV IOP       : 467/1/0|peakRSS=5737MB|sampling=time|verdict=ok
EQUIV IOPParity : 362/3/0|peakRSS=5992MB|sampling=time|verdict=ok
EQUIV Layers    : 298/3/0|peakRSS=1057MB|sampling=time|verdict=ok
EQUIV Library   : 581/4/0|peakRSS=598MB|sampling=time|verdict=ok
EQUIV Sessions  : 279/4/0|peakRSS=1615MB|sampling=time|verdict=ok
EQUIV Export    : 338/1/0|peakRSS=5483MB|sampling=time|verdict=ok
EQUIV App       : 630/0/0|peakRSS=2831MB|sampling=time|verdict=ok
```

（七值同时与 `M2-10-07-SUMMARY.md` 测试对账表逐值一致——三方互证。）真跑冒烟：
`--bundle Library LibraryThumbnailBridgeTests` = `10/0/0|peakRSS=194MB|9s|sampling=time` OK。

## T2 交付细节（硬化选型记录，KD-4）

- **选型 = 首选「确定性序注入」兑现**：注入点即既有 RenderLeg 测试缝（产线零触碰）——A 的
  production 挂 test-only one-shot gate（NSLock + CheckedContinuation，@unchecked Sendable），
  单槽被钉住 = 队列态冻结；测试轮询 B/C 入队（原 `queuedCountForTesting` 轮询保留）→
  `prioritize([3])` 落地 → **无条件 open gate** → A 完成 → 槽位移交 → C（已提位）→ B。
  期望序 [1, 3, 2] 由构造保证，无调度延迟可破。
- **为什么轮询不够**（选型依据）：两连击（M2-10-05 执行批 + 验收批）发生在**轮询形态在码**的
  前提下——竞窗 = 「轮询观察到 queued≥2」与「prioritize 生效」之间 A 的 250ms 睡眠耗尽、
  B 先起。gate 恰好消除该窗（A 完成时刻由测试控制）。
- **失败路径无悬挂**：gate open 放在 prioritize 之后**无条件执行**——deadline 失败路径
  （XCTFail + break）也放行 A，await 结果必返回（旧形态若把 open 挂 defer 到 scope 尾会死锁，
  D5）；leg 内 `defer { box?.exit() }`（await 进 body 后 exit 不能裸调）。
- 复现律：硬化后定向 ×3 = 10/0/0 ×3（1-2s/轮，旧形态 9s 冷轮）+ Library 全量 581/4/0
  （与 M2-10 基线逐值一致）；执行期间零复现。台账见 GOAL-STATE「Flaky 清算台账」段。

## 测试数字 vs 基线 2955/16/0

- **+0 测试**（断言硬化不改计数，front-matter `estimated_tests: +0` 兑现）。
- 本 plan 按 plan AC 面跑 **Library 域定向/全量轮**（AGENTS.md 资源监控节：定向单 bundle 轮可
  常跑；全套 `--all` 须 orchestrator 批准——本 plan 未申请全套轮，**未跑 --all**）。
- Library bundle：581/4/0（基线逐值零漂移，硬化前后各一轮亲跑 + 硬化后全量）；其余六 bundle
  基线 = 续班终轮记录值（等价冒烟已对七份存活日志验证解析等价，脚本改动对全套判定面零漂移）。
- **2955/16/0 基线不受本 plan 影响**：无新增/删除测试，无产线 diff。

## AC 对账（plan 验收标准总表）

| # | AC | 结果 |
|---|---|---|
| 1 | crash 日志 → verdict=crash 不再假绿 | ✅ selftest crash.log 断言（counts 置零 0/0/0 + verdict=crash） |
| 2 | 末条 Executed 非 All tests → FAIL | ✅ selftest crash.log 复合 + 截断形态隔离断言（no-total-line） |
| 3 | `Executed 1 test` → executed=1 | ✅ selftest singular.log（1/0/0 ok） |
| 4 | normal.log 五字段逐字段一致 | ✅ selftest + 七真日志 EQUIV |
| 5 | ANECCompile FAILED → ` ANE-DEGRADED` 不 FAIL | ✅ selftest 构造段 |
| 6 | 定向 ×3 + Library 全量全绿；产线零触碰 | ✅ 10/0/0 ×3 + 581/4/0；`git diff` 产线域空 |
| 7 | 台账三案齐、只追加不改写 | ✅ GOAL-STATE「Flaky 清算台账」段（14 行转录 + 本轮行 + 观测注记） |
| 8 | diff == front-matter 申报集 | ✅ 文末对账 |

## 执行期发现（详见 DECISIONS D1..D6）

- selftest 首跑即抓出 parse 内 `grep -an` 漏 `-E`（`tests?` 在 BRE 下不命中 → 总计行校验全误伤）
  ——fixture 回放自证的价值当场兑现（D6）；同轮修掉 selftest 断言展开式贪婪匹配误写两处。
- run_bundle 组装缝首版有 `peakRSS=598MBMB` 拼接 bug（parse 输出已携单位），提交前自检抓出即修。

## 偏差与边界

- 零偏差：diff 边界 == front-matter 申报集；LESSONS 未新增（grep -E 坑属 L028/L055 已覆盖面，
  过程记录在 DECISIONS D6 不另立条）。
- 环境两案（ANE / LayerE2E）本轮零改码零改测试（OQ-3-A 红线），处置 = 台账 + 脚本机检就位。
- 未跑全套 `--all`（批准制，未申请）；未 push。
