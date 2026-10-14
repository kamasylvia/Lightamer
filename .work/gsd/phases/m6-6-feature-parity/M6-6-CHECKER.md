---
phase: m6-6
plan: "M6-6-01"
kind: plan-checker（修订版反向核，fixer 同批独立眼；2026-10-16）
target: M6-6-01-PLAN.md + M6-6-CONTEXT.md @ fefa53c6（review 同批修订版）
verdict: "PASS / 0 error + 2 minor（非阻塞）→ 放行"
---

# M6-6-01 修订版 CHECKER（独立反向核）

> 核对基座：修订版 plan/CONTEXT 全文亲读（fefa53c6）；review 正本
> `M6-6-01-PLAN-REVIEW.md` 九项逐条对表；树面独立复测 = xcstrings
> 1926 keys 实数 + zh-audit --check 实跑（PASS，`30 interp keys all
> variant-PRESENT`）+ 三调用点 `App/Sources/Lightamer/UI/
> McpLauncherPanelView.swift:225/:242/:246` 亲证 + M6-5-VALIDATION
> :124/:270 两层移交语言亲读 + ci.yml `on:`（含 `tags: ['v*']`）亲读
> + STATE :117 亲读 + `OQ-V2-5`（`phases/v2-station/OQ.md:31`）在案
> + 工具链实跑（`rg` / `/usr/bin/ruby -ryaml` 实载 ci.yml OK）+
> survey 头部形态亲读（标题 + blockquote，无 front-matter）。全部
> 2026-10-16 工作树实测。

## 结论

**PASS / 0 error + 2 minor（非阻塞）→ 放行。** 修订版达成 phase goal
（parity 门落地 + M6 收口）无缺口；F1 须修三处口径统一且判据全部可
观测；F2-F5 落位自洽；F6-F9 注记逐条在位。残留 = 2 minor 文档镜像
未同步 + 2 nit 注记（见 §四），均不阻塞执行。

## 一、Goal-backward（修订版 → phase goal 反推）

- **parity 门落地链**：T1 checklist（ID 化正本落公开树）→ T2 门脚本
  （六断言 + self-test 红绿 + `--tree-root` 注入缝）+ CI parity job
  （additive）→ T3 首轮对账（`--write` + gaps ≥10 一次性 AC）。链路
  闭合，D1-D5 裁定逐条有载体。
- **M6 收口链**：T4 VALIDATION 兼 milestone_closeout（六 phase 终态
  汇编 + 六裁决兑现表 + 编排偏差 + 提前清偿偏差 + 铭谢/边界 + 全套
  `--all` ΔN=0 确认轮）→ T5 五正本翻账 + AGENTS 节。D6/D8/D9 有载体。
- **SC→任务映射**：SC1←T2/T3；SC2←T2；SC3←T3；SC4←T2；SC5←T4；
  SC6←T2——零孤儿 SC；T1/T5 由自有机检 AC 承载，无任务缺验收面。
  requirements 三条（M6INT-04 / ROADMAP §M6-6 / M6-5 挂账清单）全部
  被任务消费。
- **前置依赖**：红线族（零 Swift / 零 .metal / Project.swift 零 diff /
  xcstrings 例外申报）与任务面无交集，机检形保留完整。

## 二、F1 修订自洽（须修项复核）

- **三处口径统一** ✓：front-matter `estimated_tests`（:9）/ T2 AC /
  red_lines 三处均为「`zh-audit --check` 前后 **PASS 恒定** + catalog
  keys **1926→1929** + grep 三 `%lld` 变体键在册（尾块纯插入）」；
  「断言 5 ABSENT→PRESENT」与「27 键全 PRESENT」错算零残留（机检命中
  仅存于修订注记对删除项的描述，非活口径）。
- **判据可观测性** ✓：基态实跑亲证——`--check` PASS 行自带
  「1926 catalog keys」计数，rider 后同位读 1929（1926+3 算术自洽）；
  三变体键 grep `mcp_launcher_(status_running|done_writes|exit_code)
  %lld` 于 xcstrings 可机检；调用点零 diff 由 red_lines 两条承载
  （Swift 全域零 diff + McpLauncherPanelView 调用点零触碰显式点名）。
- **ΔN=0 与 rider 零测试面自洽** ✓：`estimated_tests "+0"` 保留、
  `expected_all` 3848/24/0 不动——rider 纯 xcstrings，新判据全部为
  非测试面观测，无隐含测试增量。「键集 30→30」scoped 到断言 5 正确
  （三新键走 `INTERP_PREFIX_RE` → 断言 2 rule c，不入断言 5 计数；
  zh-audit 输出行 `30 interp keys` 为该口径的可观测载体）。

## 三、F5 注入缝可测性 + 词表终态唯一性

- **F5** ✓：`--tree-root PATH` 载体明确、消费点两处点名（A4 的
  `.work/` 存在性判定 + A5 被扫文件根），fixture 换根即可打「公开树
  分支」确定性形态——消除了「本仓 `.work/` 恒在 → 分支不可达」的
  不可测根因；SC2 / R3 / 修订注记三处同步。先例亲证：zh-audit.py
  `--root`（:74 docstring + :636 argparse）同型在位。
- **词表终态唯一性** ✓：EXR 全部 V2 口径、零 OOS 残留——plan T1 V2
  锚（ALCE-02 原位注记 + OQ-V2-5，OQ-V2-5 亲证在案）/ CONTEXT D2
  勘误句 / §3 EXP 行 / §1 边界 / §4 / 头注「维持 V2」六处一致。OOS
  集终态 = Updates 页 + Nikon HE（D2 示例）+ demosaic 算法菜单（plan
  T1 锚，STACK.md 结构性不可达——与 D2「结构性不可达」定义相容，
  D2 括号为示例非穷尽，无矛盾）。大小写统一句保留，A3 精确匹配可落。

## 四、独立猎残（checker 自有发现，均非 review 九项范围）

1. **[minor·文档镜像] CONTEXT §5 SC2 镜像行未随 plan 同步**——:302
   仍为「…缺失 src 路径各 ≥1 红例 + 1 净例」，缺「公开树分支 +
   `--tree-root` 注入」字样。该分歧修订前已存在（原 plan SC2 有公开
   树分支、§5 无），本轮 plan 侧加注后差幅微增；§5 自称「plan
   front-matter 镜像」。S 级——执行以 plan 为准，可随执行批顺带或
   晨审处置。
2. **[minor·文档镜像] CONTEXT §6 R4 未含 ruby fallback**——:322-324
   仍为「pyyaml 时以缩进目检 + CI 首跑兜底」，plan R4 已落
   `ruby -ryaml`（本机实测可载 ci.yml）。同类 S 级镜像滞后。
3. **[nit] 修订注记粒度**：注记写「CONTEXT 同批改 D2/D4/D7②/§1.6」，
   实际另动头注输入正本引文（:25-26 汇总句消歧）——注记未列，不改
   不阻塞（头注改动属 D7② 消歧的组成部分）。
4. **[nit] 登记落点措辞双锚**：CONTEXT D7② 写「T4 VALIDATION 挂账表
   引原文并显式登记」，plan T4 把登记落点写在「编排偏差登记落收口
   段」——两锚 compatible（收口段登记一次、挂账区可引用），任一落法
   均满足「显式登记 + 引原文」语义；执行方无需双写。

## 五、review 九项落位对表（checker 独立复核，非 fixer 自报）

| 项 | 位点（修订版） | 复核 |
|---|---|---|
| F1 须修 | plan :9 / T2 AC / red_lines 三处 + 修订注记 | ✓ 口径统一、判据可观测（§二） |
| F2 | CONTEXT D2 勘误句 + plan T1 V2 锚；OOS 换 Updates/Nikon HE | ✓ 六处 V2 一致（§三） |
| F3 | CONTEXT D7② + §1.6 改引 :124 + plan T4 收口段偏差登记 + 头注消歧 | ✓ 原文两层（:124 项级 / :270 汇总）亲读 |
| F4 | plan T1 AC `{3,5}` | ✓ SHELL 5 字母覆盖 |
| F5 | plan T2 `--tree-root` + SC2 + R3 | ✓ 可测性成立（§三） |
| F6 | plan T1 §2.6 并 DRT 域 + 上游增量节对表指令 | ✓ 在位（DRT 域 M2-6 惯例锚） |
| F7 | plan T1 头注 `:line` 低波动纪律 + DECISIONS 申报 | ✓ 在位 |
| F8 | plan T1 头注 `doc:` 公开树知情申报 | ✓ 在位（内容不公开/路径公开两层写明） |
| F9.1 | plan T1 action 2「标题与头部 blockquote 之后」 | ✓ survey 无 front-matter 亲证 |
| F9.2 | plan T1 AC `rg -n '[\x{4e00}-\x{9FFF}]'` | ✓ 本机 rg 在位 |
| F9.3 | CONTEXT D4 tags 注记 | ✓ ci.yml `tags: ['v*']` 亲证 |
| F9.4 | plan T5 STATE :117 勘误指令 | ✓ :117 原文亲证在案 |
| F9.5 | plan R4 ruby fallback | ✓ 本机 ruby+yaml 实载 OK |

## 六、残留与放行条件

- 放行。残留 1/2 为 S 级文档镜像滞后，建议执行批 T4/T5 顺带同步
  （或晨审一并处置）；残留 3/4 为 nit，无需动作。
- 执行面零新增前置；夜间授权链与 C 档停形态不受本修订影响。
