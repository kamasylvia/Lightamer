# M2-11-01 ACCEPTANCE — flaky 清算批独立验收

> **PASS / 0 error + 0 minor（附 2 观察项，均非缺陷级，处置 = 记录在案不修码）**
> 验收方 = 独立 subagent（零共享上下文，2026-10-07 夜间授权在案）。全部结论实测核验，
> 不轻信执行申报。验收基线 commit = `a88c9dd`（HEAD）。

## 结论头

| 域 | 结果 |
|---|---|
| selftest 12 断言 | ✅ 全绿 EXIT=0（独立亲跑） |
| 第四形态鲁棒性 probe ×4 | ✅ 全部符合预期（验收方自造） |
| 等价性抽查（真日志旧/新判定） | ✅ 7/7 EQUIV 逐字节一致（独立复现） |
| commit 边界 | ✅ 3c26336..HEAD = 9 文件 == front-matter 申报集 |
| 产线零触碰 | ✅ `App/` `LightamerCore/` 空 diff；Tests 域唯一 diff = LibraryThumbnailBridgeTests.swift |
| OQ-3-A 红线（环境件零改码） | ✅ SidecarV5/LayerE2E 测试文件零 diff（边界审计背书） |
| 台账转录 | ✅ 14 行数据行机检确认；a88c9dd 对 GOAL-STATE = 24 插入/0 删（append-only 机械证明）；抽查 3 行全对上源记录 |
| 数字对账 | ✅ 定向 ×3 = 10/0/0 ×3 + Library 全量 581/4/0（验收方亲跑）；2955/16/0 基线 = 七 bundle EQUIV 值加总精确 |
| 未跑全套 `--all` | ✅ 符合 AGENTS.md 批准制（未申请）；plan AC 面只需 Library 域轮——不构成缺口 |

## 一、selftest 独立证据

### 1.1 亲跑（12 断言全绿，EXIT=0）

```
ok   crash counts zeroed (AC1)          ok   crash verdict (AC1)
ok   crash no ANE note                  ok   crash stderr diagnostic present
ok   singular counts (AC3)              ok   singular verdict (AC3)
ok   normal full five-field line (AC4)  ok   ANE note + verdict ok (AC5)
ok   filtered truncation exempt (KD-2)  ok   filtered truncation verdict
ok   unfiltered truncation FAILs (AC2)  ok   unfiltered truncation verdict
SELFTEST OK (test-direct.sh parse_bundle_log — 3 fixtures + 2 constructed)
```

与 M2-11-01-SUMMARY 申报逐行一致。fixture 保真核验（`cat -et`）：三 fixture 的 TAB+空格
前缀、`Test Suite '…'` 引号形态、`time: command terminated abnormally` 尾、
`maximum resident set size` ru_maxrss 行齐备——L055 现场形态复刻属实。

### 1.2 验收方自造 probe ×4（plan 之外的超集鲁棒性面）

| probe | 构造 | 期望 | 实测 |
|---|---|---|---|
| P1 混合形态（验收指令点名的「单数+崩溃截断混合」） | 末条 Executed = 类 suite `Executed 1 test`（单数）+ `terminated abnormally` 尾 | verdict=crash（D1 优先级 crash > no-total-line）、计数置零 | ✅ `0/0/0|verdict=crash` |
| P2 第二崩溃签名 | `Restarting after unexpected exit` 行 | crash | ✅ `0/0/0|verdict=crash` |
| P3 单数截断双臂 | `Executed 1 test` 无 All tests 总计行 | 无过滤 → no-total-line；带过滤 → ok 1/0/0 | ✅ 两臂均正确 |
| P4 crash ⊕ MEMFAIL 并存 | 崩溃签名 + ru_maxrss=9536MB | crash 压过 MEMFAIL（D1 链序） | ✅ `verdict=crash`（peak 9536MB 解析正确） |

### 1.3 LA_SELFTEST 守卫双形态

- 被执行路径：`LA_SELFTEST=1 ./Scripts/test-direct.sh` → EXIT=0，bundle 主体零执行。✅
- source 路径：source 后 functions 表仅暴露 `parse_bundle_log`。✅
- 不设 env 的正常路径：7 真日志 EQUIV（下节）+ 真跑 Library 轮 BUNDLE 行正常 = 语义零变化实证。

## 二、等价性抽查（独立复现）

验收方自写对照脚本（`/tmp/m2-11-01-acceptance-equiv.zsh`）：旧记账逻辑自
`git show 6031e1e^:Scripts/test-direct.sh` 记账段逐字抽取包成函数，对新 parse 对七份
存活真日志（`/tmp/la-direct-tests-*.log`）逐 bundle 比对：

```
EQUIV IOP       : 467/1/0|peakRSS=5737MB|sampling=time|verdict=ok
EQUIV IOPParity : 362/3/0|peakRSS=5992MB|sampling=time|verdict=ok
EQUIV Layers    : 298/3/0|peakRSS=1057MB|sampling=time|verdict=ok
EQUIV Library   : 581/4/0|peakRSS=598MB|sampling=time|verdict=ok
EQUIV Sessions  : 279/4/0|peakRSS=1615MB|sampling=time|verdict=ok
EQUIV Export    : 338/1/0|peakRSS=5483MB|sampling=time|verdict=ok
EQUIV App       : 630/0/0|peakRSS=2831MB|sampling=time|verdict=ok
```

worker 的 7/7 EQUIV 可独立复现 ✅；七值与 M2-10-07-SUMMARY 测试对账表逐值一致（三方互证）。
注：Library.log 现为 worker 03:14 硬化验证轮覆写件（581/4/0 与续班终轮同值），其余六份
= 00:xx 续班终轮原日志——等价性结论不受覆写影响。

## 三、边界审计（逐 commit vs front-matter）

| commit | 内容 | 文件面 |
|---|---|---|
| `6031e1e` | T1 fix(scripts) | test-direct.sh + selftest + 三 fixture = 5 文件 ✅ |
| `f9284ca` | T2 test(library) | LibraryThumbnailBridgeTests.swift 单文件 ✅ |
| `a88c9dd` | T3/T4 docs | GOAL-STATE + SUMMARY + DECISIONS = 3 文件 ✅ |

- `git diff --stat 3c26336..HEAD` = **9 文件，恰等于 front-matter `files_modified` 申报集**
  （LESSONS.md 为「如踩坑」条件件，worker 申报零新教训 → 缺席自洽）。✅
- 产线域亲证：`git diff --stat 3c26336..HEAD -- App/ LightamerCore/` = 空。✅
- Tests 域亲证：唯一 diff = LibraryThumbnailBridgeTests.swift；SidecarV5Tests /
  LayerE2ERoundTripTests 等环境件零触碰（OQ-3-A 红线亲验）。✅
- T2 语义亲读：OneShotGate（NSLock + CheckedContinuation，@unchecked Sendable）+ A 腿
  `if stem == "1" { await aGate.awaitOpen() }` 钉槽 + `prioritize([3])` 后**无条件**
  `aGate.open()`（D5 失败路径防死锁裁定兑现）+ 腿内 `defer { box?.exit() }`。产线逻辑
  零触碰属实（diff 全在 Tests 单文件）。✅
- D7（`598MBMB` 拼接 bug 修复）实证：验收亲跑 Library 轮 BUNDLE 行 =
  `peakRSS=597MB` 单单位（组装缝 `%MB` 剥回数字生效）。✅
- 提交时序：03:09 → 03:14 → 03:22 顺序合理，无夹带。

## 四、OQ-3-A 红线 + 台账转录抽查

### 4.1 红线
#1 ANE / #2 LayerE2E 两环境案零改码零改测试——由第三节边界审计机械证明（Tests 域
唯一 diff = 缩略图测试）。处置 = 台账观测收口 + ANE 机检注记（`6031e1e` 起），符合裁决。

### 4.2 台账（GOAL-STATE「Flaky 清算台账」节）
- 数据行机检 = **14 行**（LayerE2E 3 + ANE 五波 6 + 缩略图 4 + 本轮硬化行 1），与申报一致。✅
- append-only 机械证明：a88c9dd 对 GOAL-STATE numstat = **24 插入 / 0 删除**——历史行
  无改写可能。✅
- 抽查 3 行（对照源记录）：
  1. LayerE2E 2026-09-28 行（SIGTRAP host exit 133 + 第 2 轮 3 断言 fail + 隔离 ×2 绿 +
     第 3 轮全套 0 fail）← `M2-2-2-SUMMARY.md` flake 归因节 **verbatim 一致** ✅
  2. ANE 2026-10-07 终态行（13.338s passed + ~68h 重启复绿 + 两红三绿结论照录）←
     `M2-10-07-SUMMARY.md:104-106` **一致**（含「不重新计数」纪律）✅
  3. 缩略图两连击行（2026-10-03/04 两击 + 隔离类 10/0/0 + Library 全量 568/4/0 补跑 +
     「环境型归因趋弱」引文）← `M2-10-05-ACCEPTANCE.md` O-1 + 测试对账表 **一致** ✅
- RESEARCH §D 五件对账：#3 → `f9284ca`、#4/#5 → `6031e1e`、#1/#2 → 台账观测——五件各有着落。✅

## 五、数字对账（验收方亲跑）

| 轮 | 申报 | 验收亲跑 | 判定 |
|---|---|---|---|
| 定向 `--bundle Library LibraryThumbnailBridgeTests` ×3 | 10/0/0 ×3 | **10/0/0 ×3**（7s/1s/1s，195MB） | ✅ |
| `--bundle Library` 全量 | 581/4/0 | **581/4/0**（27s，597MB）EXIT=0 | ✅ |
| 基线 2955/16/0 | 不受影响 | 七 bundle EQUIV 值加总 = 467+362+298+581+279+338+630 = **2955**；skip 1+3+3+4+4+1+0 = **16**；fail = **0** | ✅ 加总精确 |
| +0 测试 | estimated_tests: +0 | Library 计数 581 与 M2-10-07 基线同值；无新增测试文件 | ✅ |

**「未跑全套 `--all`」不构成缺口**：AGENTS.md 资源监控节全套轮批准制（须 orchestrator
批准 + 运行中保持监视），本 plan 未申请；plan AC #6 机检面 =「test-direct 三轮 +
`git diff --stat`」——定向 ×3 + Library 全量已覆盖。脚本新判据全量上线挂 M2-11 终验轮
（§F #11）批准面，GOAL-STATE 续接点已登记。

## 六、AC 总表复核（8/8）

| # | AC | 验收判定 | 证据 |
|---|---|---|---|
| 1 | crash 日志 → verdict=crash 不假绿 | ✅ | selftest 亲跑 + P1/P2 probe |
| 2 | 末条 Executed 非 All tests → FAIL | ✅ | selftest 截断双臂 + P3 probe |
| 3 | `Executed 1 test` → executed=1 | ✅ | selftest + P1/P3 probe |
| 4 | normal.log 五字段逐字段一致 | ✅ | selftest + 7/7 EQUIV 独立复现 |
| 5 | ANECCompile FAILED → ` ANE-DEGRADED` 不 FAIL | ✅ | selftest 构造段；run_bundle 组装缝代码亲读 + D7 修复真跑实证 |
| 6 | 定向 ×3 + Library 全量全绿；产线零触碰 | ✅ | 验收亲跑 + 边界审计 |
| 7 | 台账三案齐、只追加不改写 | ✅ | 14 行机检 + 24/0 numstat + 抽查 3 行 |
| 8 | diff == front-matter；产线零命中 | ✅ | 9 文件恰等；App/LightamerCore 空 |

## 七、观察项（非缺陷，记录在案）

1. **selftest 调用契约 = zsh**：`bash Scripts/test-direct-selftest.sh` 在 line 11
   `${0:A:h:h}`（zsh path modifier）报 `A: unbound variable` EXIT=1。非缺陷——脚本
   shebang = `#!/bin/zsh` 且 `chmod +x`（头注释用法 = 直接执行）；test-direct.sh 本身
   同为 zsh 专属语法（`typeset -A` / `${(j:/:)…}` / `print -r`）。bash 误跑**响亮失败
   不产生假绿**，无正确性风险；不做 bash 兼容改造（改造面 = 两脚本全量，收益为零）。
2. **「四提交」簿记口径**：派发申报「四提交」，实际 = **3 commit**（T3/T4 合一提交
   `a88c9dd`，SUMMARY 提交账表 T3/T4 合行 = 正本口径）。工作产物自洽，纯派发短语
   计数口径差。

## 八、执行期自愈两件复核（申报核实）

- D6（selftest 首跑抓 parse `grep -an` 漏 `-E`）：现码 line 99 行号定位 grep 确为
  `grep -anE`（-E 在位），单数 `tests?` 在 ERE 下正确命中——修复属实，且 selftest
  断言面（normal 五字段）恰能揭穿该 bug 类（正常日志全误伤 no-total-line → AC4 红）。✅
- D7（组装缝 `MBMB`）：现码 line 282 `peak_mb="${peak_mb%MB}"` 在位 + 真跑单单位实证
  （第三节）。✅

## 九、验收批动作

- 本报告落盘 + GOAL-STATE 续接点增量（验收 PASS 登记），commit `docs(m2-11)`；
  不 push。
- 修复批：零（0 error + 0 minor，无修码动作）。
- 下一步（orchestrator）：M2-11-02（PERF 计量批，plan 在册）。
