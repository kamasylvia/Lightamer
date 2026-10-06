# M2-11-01 DECISIONS — 裁决与执行期裁定正本

> plan 期已定裁决（KD-1..KD-5，planner + checker 回注 2026-10-07）执行签注 + 执行期裁定
> D1..D6。晨审可推翻，推翻路径逐条给出。

## KD-1 parse_bundle_log 抽取 — 签注兑现

- 抽取缝 = run_bundle 记账解析 + 判定段（HEAD :160-199）；职责面按 checker m4 注执行：
  判定逻辑全在 parse（计数/合并/五 verdict/ru_maxrss 解析/ANE 签名），BUNDLE 行组装留
  run_bundle。stdout 五字段契约与 BUNDLE 行中段同构（`N/N/N|peakRSS=…MB|sampling=…`），
  selftest 按行断言。
- 守卫形态按 m7 注：`return 0 2>/dev/null || exit 0`；守卫位置在 parse 定义后——source
  消费面恰为 parse 一个函数。**生产行为等价证据**：七真日志 7/7 EQUIV（SUMMARY 冒烟节）
  + 真跑过滤轮 ok。
- `RSS_LIMIT_MB` 上提守卫前（D3）；`HAVE_TIME`/`PLUGINS`/注册表留守卫后（selftest 不需要）。

## KD-2 L055 两修 — 签注兑现 + D1/D2 裁定

- 崩溃签名（terminated abnormally / Restarting after unexpected exit）→ crash；总计行身份
  （无过滤轮末条 Executed 向前最近 `Test Suite '` 行必须 = 'All tests'）→ no-total-line；
  过滤轮豁免；单数 `tests?` 两处外层同修（m1）。
- **D1 verdict 优先级链**：crash > no-total-line > MEMFAIL > executed-0 > fail > ok。前两者
  置顶（终局事实压过资源门）；MEMFAIL > executed-0 > fail 保持旧脚本相对序（旧代码依次覆盖
  赋值等价）。推翻路径：若晨审认为 MEMFAIL 应压过 crash（资源优先视角），调整 if-elif 链序
  即可，fixture 不变。
- **D2 crash/no-total-line 计数置零**：两 verdict 下 BUNDLE 行报 0/0/0（非保留部分类 suite
  计数）——AC1「末条类 suite 行不再被当 bundle 计数」的字面兑现；部分计数是 L055 假绿的
  本体，保留即残留误导。TOTAL 行相应少计（诚实反映「该 bundle 无可信计数」）。诊断信息
  不丢：↳ stderr 行携日志路径，人工可查实际进度。
- **D4 crash.log fixture 形态**：按 LESSONS L055 记载的 `time: command terminated abnormally`
  尾 + 类 suite Executed 行复刻（2026-10-03 现场日志已被后续轮覆盖，以 LESSONS 引文为
  正本）；`/usr/bin/time` 异常退出仍打 ru_maxrss 的形态一并复刻（peak 解析路径覆盖）。

## KD-3 ANE 注记 — 签注兑现

签名扫描（`grep ANECCompile | grep FAILED`）归 parse，注记拼装归 run_bundle；verdict 不变、
不 FAIL；字段说明进头注释。五波台账两红三绿环境型归因维持（M2-10-VALIDATION 裁决不翻）。

## KD-4 缩略图硬化 — 选型记录（首选序注入兑现）

- **注入点 = 既有 RenderLeg 测试缝**（构造注入的 leg，产线零 diff）：A 挂 OneShotGate
  （NSLock + CheckedContinuation，@unchecked Sendable，与文件内 ObservationBox 同款并发
  形态）钉住单槽 → 队列态冻结 → 轮询（保留）→ prioritize → 无条件 open → 期望序构造保证。
- **选型理由**：轮询形态已是在码硬化（M2-3-1 D7），两连击仍复现——竞窗在「轮询成功」与
  「prioritize 生效」之间，轮询本身压不掉；序注入把 A 的完成时刻收归测试控制，窗消失。
- **D5 失败路径无悬挂裁定**：gate open 置于 prioritize 之后无条件执行（非 defer 到 scope
  尾）——deadline 失败路径若 defer 到尾，`await (resultA, resultB, resultC)` 会等 gate 而
  gate 等 scope 退出 = 死锁；无条件 open 保证任何断言失败后测试必终止。leg 内
  `defer { box?.exit() }`（await 进 body 后裸 exit 不可用，顺带修正观测器配对）。
- 复现律：硬化后定向 ×3 + Library 全量零复现；台账行入 GOAL-STATE。

## KD-5 台账 — 立表兑现

- 位置 = `.work/GOAL-STATE.md` 新节「Flaky 清算台账（M2-11-01 KD-5 立表）」（「## 环境备忘」
  前）；六列表格式照 plan；三案 14 行历史转录（LayerE2E 2026-09-26 起 3 行 + ANE 五波 6 行
  + 缩略图 4 行 + 本轮硬化行）+ 五件处置对账 + 本轮观测注记（App/Layers bundle 不在轮中，
  无复现机会即无新行；ANE 机检自 `6031e1e` 起随全套轮自动携带）。
- 转录纪律：历史行原样转录不改写（含 RESEARCH §D「M2-4-1 轮 SIGTRAP」锚点归属松弛的注记
  ——GOAL-STATE:65 实为 M2-3 缺陷修复专项批，转录行带双锚）；「两红三绿」按
  M2-10-07-SUMMARY 记载结论保留，不重新计数。
- RESEARCH §D 五件对账：#3 → `f9284ca`、#4/#5 → `6031e1e`（三修）；#1/#2 → 台账段观测
  收口（两观测）——五件各有着落（T3 AC 兑现）。

## 执行期裁定

- **D3 RSS_LIMIT_MB 上提**：LA_SELFTEST source 路径下 `set -u` 生效，parse 的 MEMFAIL 判定
  引用该常量——常量 + SPIKE 注记整体上提守卫前，注册表/参数解析留后。备选（parse 内
  `${RSS_LIMIT_MB:-8192}` 默认值）否决：双源漂移风险。
- **D6 selftest 首跑抓真 bug**：parse 行号定位 grep 首版漏 `-E`（`tests?` 在 BRE 下按字面
  `+`/`?` 解释 → 正常日志全误伤 no-total-line），selftest 首跑 10 断言红当场暴露即修——
  fixture 回放自证纪律（D-M2-11-CONTEXT-4）的价值实证；该坑不另立 LESSONS（L028/L055
  家族已覆盖 grep 判据形态面，过程记录于此）。同批修正 selftest 断言展开式两处
  （`${out##*|verdict=}` 贪婪剥到值、`${out#*|*|}` 残留尾段）——断言写法坑非脚本缺陷。
- **D7（记账）run_bundle 组装缝首版 `598MBMB` 拼接 bug**：parse 输出携 `MB` 单位、组装处
  再拼 `MB`——提交前走查抓出即修（`%MB` 剥回数字）。零外部影响（未提交过坏形态）。
- **D8 本 plan 未跑全套 `--all`**：AGENTS.md 资源监控节全套轮批准制，本 plan AC 面只需
  Library 域定向/全量轮；全套解析等价以七真日志 EQUIV 冒烟背书。后续 M2-11 终验轮
  （§F #11）自带全套批准面，脚本新判据届时全量上线。
