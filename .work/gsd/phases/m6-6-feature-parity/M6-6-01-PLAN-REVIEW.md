---
phase: m6-6
plan: "M6-6-01"
kind: plan-review（独立评审路，替代 omp 复审；2026-10-16）
reviewer: zcode 独立 plan 评审（零共享上下文）
verdict: 须修后放行（1 须修 + 4 建议修 + 4 注记；零结构性驳回项）
---

# M6-6-01 PLAN 评审（独立路）

> 亲验基座：plan/CONTEXT 全文亲读；`ci.yml`（113 行）、`Scripts/zh-audit.py`
> （671 行，regex 与断言供给点亲读）、`ALCEDO-FEATURE-MAP.md`（330 行 +
> 节标题全列）、`.gitignore`/remotes/`git status`/`git ls-files`、
> `M6-5-VALIDATION.md` §挂账单一清单、STATE/ROADMAP/REQUIREMENTS/TODO
> M6 面、xcstrings 三裸键值、两处消费 catalog 的测试、LightCraft 本地仓
> `docs/parity-checklist.md` + `xtask/src/parity.rs`、`test-direct.sh`
> bundle 注册表、`zh-audit --check` 实跑。全部 2026-10-16 工作树实测。

## 一、findings

### F1【须修】N-1 rider 验收机制错配——「断言 5 三键 ABSENT → PRESENT」不可观测

- **位点**：plan front-matter `estimated_tests`（:9「断言 5 三键 ABSENT →
  PRESENT 转绿」）+ T2 验收标准（:171 同文）+ red_lines（:269「V16 断言 5
  ABSENT 零命中——N-1 三键转绿后 **27 键全 PRESENT**」）。
- **实测**：`uv run python3 Scripts/zh-audit.py --check` 当前 **PASS**，
  输出「30 interp keys **all variant-PRESENT**」。三键是 `Text("K \(x)")`
  插值形态——V16 断言 5 只供给自 `LOCATED_INTERP_RE`（`String(localized:`
  同行）与 `LEAD_INTERP_RE`（form-1c 续行）两 regex（zh-audit.py:140-141、
  :262-265），**不扫 Text 族**——这正是 M6-5 N-2 的在册限定（VALIDATION
  :133-136「Text 族…不设防，3 处真 ABSENT 活体」）。rider 前后断言 5 的
  键集合与计数均不变（30→30）；「27 键」的拆分不存在，「ABSENT 前态」
  无从观察。执行方按 AC 字面找前态 ABSENT 会落空 → 假验收/困惑。
- **rider 本体无误**：三 `%lld` 变体补齐是真修（运行时查表键 = `K %lld`，
  目录只有裸键 = zh 回退活体，M6-5 N-1 实锤；裸键值 :7960/:7976/:8120 已
  含 `%lld`，「同文」复制 specifier 恰好正确）；新增键经
  `INTERP_PREFIX_RE`（:129，扫任意行含 Text( 行）进 `interp_prefixes` →
  断言 2 rule c 覆盖，`--check` 保持 PASS。
- **修法**：三处措辞改为可观测判据——「`--check` 前后 PASS 恒定 +
  catalog keys 1926→**1929** + grep 三 `%lld` 变体键在册（尾块纯插入）
  + 调用点零 diff」；red_lines 删「27 键全 PRESENT」错算。

### F2【建议修】EXR 状态词表内部矛盾（OOS vs V2）

- **位点**：CONTEXT D2（:130-135）把「EXR 导出〔ALCE-02 用户裁决 V2〕」
  列入 **OOS** 示例；CONTEXT §3 EXP 行（:265）同面写「EXR→**V2 行**」。
- **矛盾**：D2 自家语义 = OOS「永不做/结构性不可达」vs V2「等条件」；
  EXR 恰有重启条件（V2-PROPOSAL OQ-V2-5 依赖对比再裁）→ 按 D2 定义应归
  V2。plan T1（:92-94）沿用「EXR = ALCE-02 V2 裁决」作 OOS 锚，把矛盾带
  进执行面。
- **修法**：统一 **EXR → `V2` 行**（锚 = ALCE-02 原位注记 + V2-PROPOSAL
  OQ-V2-5），OOS 留给 Updates 渠道终裁与 Nikon HE CIRAW 不可达两项结构
  性不可达；或显式改 D2 申报「OOS 兼收用户裁决范围外」并同步 §3。二选
  一，DECISIONS 记一笔即可。

### F3【建议修】D7② 移交语言误引

- **位点**：CONTEXT D7②（:219）「M6-5 VALIDATION 移交语言**点名 M6-6
  收口批**」。
- **实测**：M6-5-VALIDATION §挂账② 原文（:124）=「→ **下一清算批候选**」，
  未点名 M6-6。
- **处置本身合理**（milestone 收口前清一枚已知 zh 活体，S 量级，T6 同款
  形），但引文失实 + 相对移交原案属**提前处置**——按本批「禁静默」纪律，
  T4 VALIDATION 挂账表应引 M6-5 原文并显式登记「提前清偿」偏差（晨审可
  翻），勿写「点名 M6-6」。

### F4【建议修】T1 临时唯一性自检 grep 漏 SHELL 域

- **位点**：plan T1 验收标准（:105-106）`grep -o 'FEAT-[A-Z]\{3,4\}-[0-9]\{2\}'`。
- **bug**：`SHELL` = 5 字母，`{3,4}` 不匹配——临时自检对 SHELL 域全盲
  （T1 先于 T2，A2 尚未在位的窗口内失明）。T2 A1 的显式 alternation
  正确，不受影响。
- **修法**：`[A-Z]\{3,5\}` 或域码显式枚举。

### F5【建议修】self-test「公开树分支例」缺注入缝

- **位点**：plan T2（:137）只给 `--checklist PATH` 覆盖；A4 的 `.work/`
  存在性判定与 A5 的账面文件（`.work/gsd/REQUIREMENTS.md` 等三件）探测
  都 keyed on repo 真身——本仓 `.work/` 恒在（git ls-files 965 文件），
  fixture 换 checklist 路径打不开「`.work/` 缺席」分支，SC2 的公开树
  红绿例写不出确定性形态。
- **修法**：脚本加 `--tree-root`（或 `--no-work-tree` flag），A4/A5 判定
  走参数——zh-audit 先例即 `--root`（:636），同型顺手。

### F6【注记】§2.6 与「上游增量测绘」节域归属缺口（孤儿风险）

- CONTEXT §3 域表 ADJ=§2 目录+CW+Look、DEV=§2.4、GEO=§2.5——**§2.6
  Detail 面板（Post 四件套 UI）无落点**（按 M2-6 惯例应归 DRT 域）；
  附录「上游增量测绘」（:318 起，栅格输入链/LUT IO 编码面/OCIO ACES 2.0）
  同样不在域表——多数已有我方对应件（M4-1 raster 链 / M3-1 LUT 编码 /
  aces20 DRT）。
- **修法**：T1 action 加一句指令——§2.6 并入 DRT 域；增量节逐条对表，
  已有对应件并入既有域行 Notes、无对应件 mint 行或显式注记，防盘点
  遗漏（survey 功能面零遗漏准绳）。

### F7【注记】`:line` 证据指针的漂移维护成本

- A4 `:line` ≤ 行数机检（LightCraft parity.rs :5-6/:167-169 同款）=
  未来任何移动被引行的 commit（含与 parity 无关的批）都会打红 CI parity
  job。LightCraft 用「同 commit 更新行」纪律消化，我方同款纪律在头注，
  但**跨 feature 的行漂移**无人认领。
- **建议**：头注明示「`:line` 仅用于低波动文件；高波动文件用路径级指针」
  （或 A4 对 `:line` 越界先 warning 后升级 = V2 候选）；接受噪音成本须
  DECISIONS 显式申报。

### F8【注记】doc: 指针把 `.work/` 内部路径字符串带进公开树

- checklist 是公开树文件；Evidence 列 `doc:.work/gsd/phases/...` 的路径
  字符串本身公开（内容不公开——13-4 过滤史排除 `.work/`，机制经 TODO
  :344 13-4 T1 战果①亲证，非 .gitignore）。phase slug 暴露属低敏，但
  需用户知情。
- **备选**：doc 锚用标签形（`doc:M6-1 VALIDATION`），本地机检经 `.work/`
  内映射表解析标签→路径。建议 T1 头注或 DECISIONS 显式申报取舍。

### F9【注记】杂项（执行面一句话级）

1. T1「front-matter 之后的引言区」——survey **无 YAML front-matter**（引言
   = 头部 blockquote），措辞落点改「标题与头部 blockquote 之后」。
2. T1 全英文 AC 的 `grep -P` macOS BSD grep 不支持——改
   `rg -n '[\x{4e00}-\x{9FFF}]'`（或 perl）。
3. CONTEXT D4「触发面 push main/PR/dispatch」漏 tags——实际 `on:` 含
   tags，parity job 在 tag push 也会跑（无害，注记即可）。
4. STATE Notes :117「GitHub repo not yet created」为陈旧注记（13-4 已建
   仓，GOAL-STATE :168 在案）——T5 翻账时顺带订正可选。
5. R4 的 pyyaml 本地确实双缺（system python3 与 uv env 亲证均无）——可
   改 `ruby -ryaml`（macOS 自带）做本地 YAML 校验兜底，CI 首跑兜底不变。

## 二、放行依据（亲验通过面）

1. **D4 门面**：ci.yml = build-and-test + release 两 job 均 macos-27，
   parity job（ubuntu-latest / checkout@v5 / timeout 5 / 裸 python3）
   纯 additive 零冲突，ubuntu runner python3 预装；「CI 已存在非降级」
   申报成立（D4 与实况一致）。裸 python3 vs 全局 §5 uv 红线：例外已显式
   申报（D4「本地守 uv 红线」+ SC4 裸 python3 限定为 CI 形态等价核验）。
   zh-audit 同型声明成立（--report/--check/--self-test 三模式 + docstring
   体例 + uv 运行例逐点对上；--write/--checklist 为合理扩展）。
2. **D1/D2 checklist 面**：survey 330 行亲数 ✓；.gitignore 无 docs 排除
   （grep 零命中）✓；docs/ 新建入树 ✓；公开树排除 `.work/` 前提成立
   （过滤史政策）；12 域划分覆盖 §1-§8+§10 主体（缺口见 F6）；120-140
   预估与 §3 域级概算（111-147）自洽，AC [100,160] 合理；id 稳定不重
   编号/「whoever lands…same commit」引用与 LightCraft 原文逐字对上
   （parity-checklist.md :13/:16）；OOS 六词表为新增显式申报（REQUIREMENTS
   「待定（parked）」用语相容），唯 EXR 归属须先解（F2）。
3. **T2 rider**：调用点 :225/:242/:246 ✓；三裸键在册、值已含 `%lld` ✓；
   两处消费 catalog 的测试（SoftProofUIWiringTests L025 /
   CatalogModeIsolationTests L025）均按前缀过滤（`softproof_` /
   `settings_catalogs_` / `organization_mode_` / `catalog_`），三新键
   不入集 → **ΔN=0 成立**；SC6 尾块纯插入形与 M6-5 T6 先例同型 ✓。
4. **D6 收口面**：`milestone_closeout` 兼承载与 M5-3 先例（STATE M5-4 行
   「milestone_closeout: M5 carried by m5-3-pano/M5-3-VALIDATION.md，
   m2-11/m4-3 先例」）对齐 ✓；六裁决兑现表①-⑥与 ROADMAP charter 行
   （:61 六裁决 + :72-76 各 phase 行）逐条对上、各带 VALIDATION 正本
   指针 ✓；六 phase 终态数字（3689/3725/3759/3841→3843 核销→3848）与
   STATE/ROADMAP 在案值一致 ✓。
5. **T4 全套轮**：预期 `TOTAL|3848/24/0|` 与 test-direct.sh 输出契约
   （TOTAL|sum/sum/sum|seconds，:31）吻合 ✓；基线 3848 = M6-5 三路实测
   在案 ✓；七 bundle 注册表实测 `(IOP IOPParity Layers Library Sessions
   Export App)`（:165）与 bundle token 纪律一致 ✓；build-for-testing
   前置硬性落 SC5 命令序（I-1 教训落位）✓；ΔN=0 论证成立（见放行 3）。
6. **任务边界/红线**：零 Swift 触碰 vs xcstrings 例外申报清晰（SC6 +
   red_lines「除 N-1 三键尾块纯插入外零 diff」）✓；三 untracked 兄弟件
   实名逐一核对无误（M3-1-ACCEPTANCE-PI.md / retro-dual/backfill-pi.zsh /
   research/dt-clone-archive/）✓；survey 正文 330 行零改写红线可 grep 审
   ✓；Project.swift/.metal/sidecar schema/Export 矩阵零触均与任务面无交集
   ✓；config.toml `[gsd]` auto=true/paused=false 实读 ✓（read_first 项有
   效）。
7. **D7 对表**：六项与 M6-5 VALIDATION §挂账单一清单逐项吻合——①勘误
   正本已落（:48/:112 在案）②rider ③V17 候选移交 ④Manual-Only 19 行
   → GUI 批 ⑤V2 九项 + 留置五项（V2-PROPOSAL §七 :177 在册）⑥M6-4
   3843 核销已落 ✓（唯②引语失实 = F3）。
8. **D9 铭谢**：LightCraft 本地仓三参考件亲在（docs/parity-checklist.md /
   docs/gaps.md / xtask/src/parity.rs）；「方法论借鉴零代码移植 → 无
   NOTICE 义务」与 charter（代码级移植才触发）一致 ✓。

## 三、总评

**须修后放行。** plan 骨架（T1-T5 分工、D1-D9 裁定、SC1-SC6、红线族、
风险预案）经树面逐项亲验全部站得住，无结构性驳回项。F1 必修——rider
验收判据按字面执行不可观测（断言 5 不扫 Text 族是 M6-5 N-2 的在册限定，
plan 却把 rider 记到断言 5 头上），属会导致执行困惑/假验收的 AC 缺陷；
F2-F5 为一行级措辞/参数修，建议同批带入；F6-F9 注记级，可由执行方在
DECISIONS 带过。修法均不影响任务结构与 commit 切分。
