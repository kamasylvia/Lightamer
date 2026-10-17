# M7-6 CONTEXT — M7 站收官 phase（SKILLS-01 + UQ-A1/UQ-L1 + 三缺陷 + 站级 VALIDATION；OQ 裁决落定批，2026-10-17）

> **裁决正本**：OQ-M7-6-1..10 **全部按 `RESEARCH.md` §7 推荐落定**（M7 站
> charter 授权站内 auto-advance + OQ 全按推荐；先例 M6-3/M6-4、
> M7-2/M7-3/M7-4/M7-5 同款）。**晨审可推翻**——推翻 = 用户晨审修订本文件
> 对应 D 条，下游 plan 受影响任务面重开（已执行部分按「晨审推翻先例」惯例
> 处理）。读解正本 = 同目录 `RESEARCH.md`（§0 输入清单 / §1 SKILLS-01 形态
> / §2 UQ-A1 / §3 UQ-L1 / §4 三缺陷 / §5 VALIDATION / §6 plan 切分 / §7
> OQ 表 / §8 证据索引；file:line 经 planner 2026-10-17 HEAD `07927ab2`
> 逐点亲核复核吻合——个别 ±2 行内微差随本批勘正：acquire 异 holder busy
> 入口检查实测 :215-217〔RESEARCH 记 :217〕、obs-3 复检锚 revoked throw
> 实测 :228-231〔RESEARCH 记 :229 拼写，语义同点〕、`makeUnionRegistry`
> 实测为 `private func` :277〔见下「快照改动权」行使注记〕）。
> **评审 round 1 勘误两条（2026-10-17，正本 = `M7-6-01-PLAN-REVIEW.md`
> e61185b0）随行内标注**：D-M7-6-5（yiyin Slider「零命中」为 grep 假阴
> 性，实测 3 处在册）与 D-M7-6-7（setControlAdmit 装配构成实为三宿主，
> embedded 委托 startHTTPHost 无独立安装点）——上游 RESEARCH 同句以本
> 文勘误为准，晨审可翻。
>
> **夜间全自动授权在案**（先例 D-07-3-T5-1；晨审可推翻）：本 phase 执行批
> （双 zcode subagent 执行 + 独立验收 + 全套 `--all` 轮〔本 plan 期
> orchestrator 已预批〕）可夜间全自动推进；**C 档第 3 停（站级 VALIDATION
> 签核给用户过目）不受站内授权覆盖**——T6 落盘后用户晨审过目为准。
>
> **C 档门控行使记录**：RESEARCH 批续接点 C 档第 1 停（OQ 裁决前不进
> plan）——该停由站 charter 授权链行使（OQ 全按推荐落定即裁决，本文即落
> 定载体）；第 2 停等待面由 auto-advance 覆盖（闭环汇报照发）。
>
> **快照改动权（本波持权——M7-5 移交）**：union 32 基线 + 五钉 23 维持，
> **本波预期 union 内容零 diff**（三缺陷/UQ 两件/SKILLS-01 均不增删工具；
> 快照断言面零触碰）。唯一预期 diff = `McpFinalSnapshotTests.swift` 的
> `makeUnionRegistry` 可见性提升 `private`→`internal` **恰一行 additive**
>（T4 SKILLS-01 机检新文件 `SkillsReferenceTests` 复用活注册表——同测试
> target internal 可见即够，实测 :277 为 private）。**持权窗口内禁并行派
> 发**（orchestrator 编排保证；若误并行派发 = 立即停手上报，禁抢先合并快
> 照表）；窗口用讫归还 M8（T6 VALIDATION §挂账清算面登记移交注记）。

## Phase Goal（ROADMAP §M7-6 行锚定）

六项收官（scope 定案正本 = `.work/GOAL-STATE.md` 续接点 2026-10-17 条 +
`phases/m7-5-turn-taking/M7-5-SUMMARY.md` §M7-6 Scope）：①SKILLS-01
skills 文档仓（自家 MCP 的 agent 使用文档——仓内 `skills/lightamer-mcp/`
单 skill 多 reference，SKILL.md 人写 + references 机检，en 单语，零 taste
零 Alcedo 文案）②UQ-A1 预览层 ICC 双曲线失配修复（legal SDR 对预览层改
挂导出同款 ICC v4 + 解码等值测试）③UQ-L1 滑杆横扫 scrub（LightamerSlider
单组件 readout DragGesture，D-H1 三段回调复用）④M7-5 major-1
setControlAdmit 生产接线（宿主透传参案）⑤minor-1 裸 stdio/http 臂
agentControl 两行 + obs-3 acquire 复检硬化（快照+条件复检三行，review B1） ⑥M7 站 VALIDATION 收口
（单站级文档，含 M7-5 签核 + 制度偏离登记 + SC 翻账）。对应 REQUIREMENTS
SKILLS-01（:452）+ UQ-A1/UQ-L1（:458/:460）+ M7-5-SUMMARY §Leftovers
1/2/3/6。验收形态（ROADMAP 定式）：skill 仓机检 reference 生成 ✓ / UQ-A1
解码等值测试 ✓ / UQ-L1 交互走查 ✓ / SC 数字门 = 站终验全套轮判定式兑现。

## 决议（D-M7-6-1..10，生效值，硬约束，执行中不重开）

### D-M7-6-1 skills 仓形态 = 仓内 `skills/` 顶层目录（OQ-M7-6-1）

- **裁决 = RESEARCH 推荐（①仓内）**：`skills/lightamer-mcp/` 单 skill 多
  reference——`SKILL.md`（人写）+ `references/tools.md`（机检生成 32 工具
  表）+ `references/errors.md`（19 错误码表）。理由一句：我方无 CLI/终端
  用户分发面，Alcedo 独立仓的动机（CLI reference 面向用户发布）不存在，
  机检测试同仓最简，未来独立仓 = 目录平移零重写。
- 证据：RESEARCH §1.1-§1.2（survey :303 两形态候选 + gap #27 :273「缺，
  低成本高价值」；我方机检正本 = McpFinalSnapshotTests all32 :270）；§7.1。
- 被否备选：独立 `lightamer-skills` 仓（分发需求不存在——挂账至需求出现）。

### D-M7-6-2 skill 语言 = en 单语（OQ-M7-6-2）

- **裁决 = RESEARCH 推荐（①en 单语）**：理由一句——消费者是外部 LLM
  agent（英文最稳），Alcedo 同款英文，双语双倍维护无收益。
- 证据：RESEARCH §1.2（「skill 文件不进 xcstrings / 不进 zh-audit 面，
  DECISIONS 申报豁免」）；§7.2。
- 被否备选：zh/en 双语（零消费面）。

### D-M7-6-3 reference 机检形态 = 测试即门（OQ-M7-6-3）

- **裁决 = RESEARCH 推荐（①测试即门）**：新测试文件
  `SkillsReferenceTests.swift` 从活注册表渲染 markdown 与仓内
  `references/tools.md` 逐字节比对——注册表演进漂移随全套即红，零脚本维
  护面（对齐上游 `generate_cli_reference.py` 思路的 golden-test 化）；机
  检源 = `makeUnionRegistry().descriptors()`（32 工具五域全集）。
- 证据：RESEARCH §1.2 机检形态段 + §7.3。
- 被否备选：独立生成脚本（留 v2 若 reference 需独立发布）。

### D-M7-6-4 UQ-A1 域外对处置 = legal 对换 ICC v4、域外对 calibrated 回落（OQ-M7-6-4）

- **裁决 = RESEARCH 推荐（①legal 对换 + 域外回落两段式）**：
  `drtLayerColorSpace` SDR 幂臂改两段式——legal 对先试
  `DrtOutputColorSpace.drtOutputColorSpace(space:eotf:)`（Core public
  `try?` → 导出同款 ICC v4，含 srgbPiecewise 真分段表；Core 侧 per-pair
  永久缓存 = 零每帧开销），typed throw 的域外对（gamma18 等）回落现行
  calibrated 构造（预览显示义务：全部 space×SDR-eotf 组合仍须上屏；不扩
  导出 legal 表——那是 export 语义面）。HDR/linear 臂零改。
- 证据：RESEARCH §2.1-§2.2（预览面 EditorMTKView :732-800、srgbPiecewise
  2.2 幂近似 :755-760〔M4-1-01 KD-8 登记偏离——本修复后该偏离消解，
  DECISIONS 收口申报〕；导出面 DrtOutputColorSpace :53-141 legal 表
  :59-137；消费链单链 drtLayerColorSpace → drtSurfaceSpec :804-811 →
  PipeCoordinator.drtViewportSurface :646-653）；§7.4。
- 被否备选：扩导出 legal 表全量换 ICC（越 UQ-A1 scope——改 export 语义面）。

### D-M7-6-5 UQ-L1 scrub 范围 = 只落 LightamerSlider（OQ-M7-6-5）

- **裁决 = RESEARCH 推荐（①单组件）**：scrub 手势落 LightamerSlider
  readout Text（`DragGesture(minimumDistance: 3)`，177 调用点全量受益）；
  MonochromePanelView 自有 row 不获 scrub，登记观察项不顺手改。
- 证据：RESEARCH §3.1-§3.2（LightamerSlider :18-81，readout :65-69 零手
  势 = 缺口；Monochrome 自有 row :178 不组合 LightamerSlider；yiyin 面板
  grep Slider 零命中——**勘误（review M2，2026-10-17）：实测 3 处
  `LightamerSlider(` 调用在册（YiyinPanelView :160/:182/:203），原「零
  命中」为 RESEARCH §3.1 grep 假阴性，原句留痕、勘误随 DECISIONS 申报
  ——UQ 条目「yiyin 通用」实际范围 = iop + yiyin 面板族〔三处落在 177
  调用点内，scrub 自动受益〕））；§7.5。
- 被否备选：全部自有 row（Monochrome 登记观察项即可——顺手改 = 范围膨胀）。

### D-M7-6-6 track 双击 wrinkle = 登记不动（OQ-M7-6-6）

- **裁决 = RESEARCH 推荐（①登记不动）**：SwiftUI Slider track 点击跳值
  是框架行为（整行 `onTapGesture(count: 2)` 含 track 区——track 双击 =
  第一击跳值一次 commit + reset 第二步 history）；lightcraft 修法基于自
  绘 egui widget 不可平移；tooltip/文档注记即可。
- 证据：RESEARCH §3.1 已知 wrinkle 段（lightcraft `cb8b797c` 同款病灶）；
  §7.6。
- 被否备选：拦截修复（框架内部消费点击，成本高不可平移）。

### D-M7-6-7 major-1 修法 = 宿主透传参 +1 缺省 nil（OQ-M7-6-7）

- **裁决 = RESEARCH 推荐（(a) 透传参案）**：四宿主
  （startReadOnlyHTTPHost :722 / startHeadlessStdioHost :786 /
  startHTTPHost :1035 / startEmbeddedIfPreferenceEnabled :1137——
  EmbeddedState box 加 `admit` 字段承载）+ `startEmbeddedServer` :1165
  直通；`setControlAdmit` **生产调用恰 3 点** = 三宿主函数体
  `setWriterCheck` 之后（:737/:819/:1081 各 +1 `if let admit { await
  registry.setControlAdmit(admit) }`）——embedded 无自有 registry、整段
  委托 startHTTPHost（:1176），经 box→startHTTPHost **复用 :1081 单点
  装配，无独立安装点**（**勘误 review M1，2026-10-17**：RESEARCH §4.1
  「四宿主装配点」将无 registry 的 embedded 段并入宿主清单——行号全对、
  构成错；禁在 embedded 段经 handle 二次安装）；GUI 装配点（LightamerApp
  :1632-1651 段）喂 coordinator-backed admit 闭包（acquire provider
  plain-await hop 同款先例形）。无头臂 nil = 恒放行 = D-M7-5 正确语义，
  字节零 diff。理由一句：与 `writerCheck` 装配先例完全同构（:819/:1081
  两处即先例形态），additive 缺省 nil 零回归，无 toggle 时序缝。
- 证据：RESEARCH §4.1（事实链亲证：App/Sources 恰 1 定义 :367 + 0 生产
  调用、3 调用全在测试 fixture McpControlToolsetTests :194/:253/:473、
  admit 闭包从 App 到 registry 无通道）；§7.7。
- 被否备选：(b) box 暴露 registry 补接线（handle 不回传 + off→on
  toggle 时序缝两处新面）。

### D-M7-6-8 站级 VALIDATION 形态 = 单站级文档，m7-5 不补写（OQ-M7-6-8）

- **裁决 = RESEARCH 推荐（①单站级）**：`phases/m7-6-station-close/
  M7-VALIDATION.md`（对齐 `M7-1-VALIDATION.md` 体例，front-matter
  `phase: M7 站`）；含 M7-5 签核 = 站级文档 §M7-5 节给 signed 语义（前置
  条件 = major-1 修复后执法语义完整——M7-5-SUMMARY §Leftovers 6）。理由
  一句：m7-5 补写独立 VALIDATION = 事后追认失真（双 ACCEPTANCE + SUMMARY
  已是更重收口载体），载体偏差显式登记为制度事实。
- 证据：RESEARCH §5.1-§5.2（现状盘点表：M7-1..M7-4 各有 VALIDATION，
  M7-5 无）；§7.8。
- 被否备选：逐 phase 补 m7-5 VALIDATION（追认失真）。

### D-M7-6-9 plan 切分 = 单 plan M7-6-01（OQ-M7-6-9）

- **裁决 = RESEARCH 推荐（①单 plan）**：任务序 T1 三缺陷 → T2 UQ-A1 →
  T3 UQ-L1 → T4 SKILLS-01 → T5 全套对账 → T6 站级 VALIDATION + 台账翻
  账。理由三句：union 串行纪律 → 并行度结构性为零；六项总量小（三缺陷
  产线 ≤10 行 + UQ-A1 一函数臂 + UQ-L1 一组件增强 + 两项纯文档）；收官
  语义天然串行（VALIDATION 依赖其余五项全落）。
- 证据：RESEARCH §6（备选双 plan A→B 串行不推荐——B 依赖 A 收官且 A 的
  union 权同样阻断真并行）；§7.9。
- 被否备选：双 plan（编排开销 > 收益）。

### D-M7-6-10 obs-A C12 AX 旗标 = 零代码 + 站级注记一行（OQ-M7-6-10）

- **裁决 = RESEARCH 推荐（①零代码）**：走查批零代码动作 + 站级
  VALIDATION 制度注记一行（M7-5 SUMMARY 备选项二的最轻形态——行为门为
  准、AXEnabled 恒真为框架忠实度已知面，不产码）。
- 证据：RESEARCH §7.10 + M7-5-SUMMARY §Leftovers 4（真机 osascript 实测
  commands `.disabled(gate)` 行为门生效但 AXEnabled 恒读 true）。
- 被否备选：SwiftUI 注记代码（零收益产码）。

## 登记申报（非 OQ）

- **制度偏离两件（正式登记归 T6 VALIDATION §制度偏离）**：①omp→双 zcode
  验收路由（M7-2 VALIDATION :85 先例在案——站级汇总一句）；②m7-5 无独立
  VALIDATION 载体（承 D-M7-6-8——载体偏差显式登记）。
- **xcstrings 预期恰 +1 键**：`slider_scrub_hint`（T3 scrub 的 readout
  AX hint，尾块纯插入 + zh-audit 对账同批）；若执行裁定零提示 = 零键，
  DECISIONS 申报。skill 文档 en 单语不入 xcstrings（D-M7-6-2 豁免）。
- **UserDefaults 零新键预期**：scrub 无持久化面、skills 文档无偏好键；
  若执行中确需 = 同纪律登记申报。
- **union 持权行使形态**：预期唯一 diff = `makeUnionRegistry`
  private→internal 一行（头注）；若执行中确需改快照内容（不该发生——
  六项均不增删工具）= 停手上报禁自裁。
- **N2-2 挂账收口路径**：get_state project 字段不对称句如实写进 SKILL.md
  已知面节（RESEARCH §1.1 文档句挂账一件——GOAL-STATE M7-2 续接点路由
  兑现，T6 VALIDATION §挂账清算面翻账）。

## 键族 / 登记面摘要（正本移交 plan front-matter）

- xcstrings：`slider_scrub_hint` 一键尾块纯插入（T3；历史键零触碰）。
- UserDefaults：零新键预期。
- 测试登记：新测试文件预期三（EditorPreviewColorSpaceTests / 
  LightamerSliderScrubTests / SkillsReferenceTests——全 APP 域）→
  Project.swift 恰三行 + BUNDLE-MAP 恰三行 + `tuist generate` 恒为该批
  最后一个动作（L041）。

---

## 晨审推翻点索引（可推翻面速查）

- **D-M7-6-1**：仓内 `skills/` ↔ 独立 `lightamer-skills` 仓——翻案 =
  T4 落点平移 + 机检测试路径改（文件读点改仓外）。
- **D-M7-6-3**：测试即门 ↔ 独立生成脚本——翻案 = T4 机检腿改脚本 +
  CI 外对账（全套门失去该漂移捕捉点，不建议）。
- **D-M7-6-4**：legal 对换 + 域外回落 ↔ 全量换 ICC（扩导出 legal 表）——
  翻案 = UQ-A1 scope 扩至 export 语义面 + legal 表测试面重开。
- **D-M7-6-5**：只落 LightamerSlider ↔ 连 Monochrome 自有 row——翻案 =
  T3 增 MonochromePanelView row 手势 + 测试腿。
- **D-M7-6-7**：透传参案 (a) ↔ box 暴露 registry 案 (b)——翻案 = T1
  major-1 修法整体重开（签名批改 box 载体批 + toggle 时序缝测试面）。
- **D-M7-6-8**：单站级 ↔ 逐 phase 补 m7-5——翻案 = T6 增补写
  M7-5-VALIDATION.md（追认失真代价自担）。
