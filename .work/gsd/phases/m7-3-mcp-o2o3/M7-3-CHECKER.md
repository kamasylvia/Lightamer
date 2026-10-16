# M7-3-01 CHECKER — 修订批独立复核（fixer+checker 合批的 checker 腿）

> **结论头：放行。** 放行门 1-5 全 PASS；零阻断残留；3 项 advisory
> 执行期注记见 §四.3（不阻门、不阻开工）。

- 复核基线：HEAD `e7d8151e`（fixer 修订批 commit，其后零产线文件）
- 输入：`M7-3-01-PLAN-REVIEW.md`（须修后放行：4 高 / 3 中 / 4 低；
  §四放行门 1-5）+ 修订后 `M7-3-01-PLAN.md` + `M7-3-CONTEXT.md`
- 复核方式：放行门逐条对修订后 plan 文本独立验证 + 代码面独立猎残
  （**非转抄 fixer 批注**——本腿全部 grep / file:line 亲跑：五钉坐标、
  裸构造计数、宿主调用点、renderedPlane 全仓调用面、controller 字段、
  pristine 键数、BUNDLE-MAP 归属、REQUIREMENTS 行号）。

---

## 一、放行门 1-5 逐条复核

### 门 1（H1——快照计数钉清单）— **PASS**

- **坐标亲跑**：全 MCP 测试面 `count, 2x` / `count == 2x` 扫描证实
  破坏性计数钉**恰五处**、与 plan 清单逐一吻合：
  `McpRegistrySnapshotTests:194` / `McpSearchStateToolsetTests:270` /
  `McpHostTests:243` / `McpHostTests:696`（:718 memory 臂
  `memoryTools == httpTools` 等值断言、无独立硬码——随行亲验）/ 
  `McpLauncherTests:200`。**无第六处**。
- **union 四计数**（:209/:246/:274/:421）+ 连带点（`all23` 属性
  :184-186 定义 + :207 引用、头注 :15/:22、:209 断言 message、
  `McpRegistrySnapshotTests:30` docstring）均在 plan T5 action 5/6
  显式改清单。
- **files_modified**：McpHostTests / McpLauncherTests 两行已增
  （22→24 件），各自注明计数钉点位与 message 同批。
- **红线矛盾消除**：T5 action 7 改写为「culling 层文件不改 +
  searchstate **工具面**零 diff（:270 计数负测显式改 20→21、负测语义
  保持）」——plan 内部自相矛盾消除。
- **grep 门**：T5 验收增「全仓 `count, 20` / `count == 20` / `all23`
  在 MCP 测试面零命中」。
- **清白旁证**（本腿独立排除）：McpCullingToolsetTests:273（projection
  列 25）/ :412（fixture 行数 12）/ McpEditingToolsetTests:507
  （list_iops 目录 19）/ McpSearchStateToolsetTests:920（错误码表 16）/
  McpLauncherSentinelTests:171/:175（buffer 2000）——均与工具计数无关，
  不受 T3/T4 影响。

### 门 2（H2——projectDirectory 锚退役）— **PASS**

- `McpServerController.swift:194` `projectURL.deletingLastPathComponent()`
  启动捕获亲验在位（makeHeadlessSearchState library closure）。
- plan T4 action 3 启动捕获退役范围 = liveState **+ :194 锚**
  （`box.url.deletingLastPathComponent()`）——`20997721` 同族第二实例
  引证在注。
- T4 验收 + T5 锁仲裁 fixture 各增 **A→B 运行时切换后
  `get_state.project.path` 与项目相对解析锚同指 B** 断言腿。

### 门 3（H3——no-project http 臂 + 生产调用点）— **PASS**

- 裸 `McpSearchStateContext()` 亲验**恰两处**（:256 stdio / :267 http）
  ——plan 双臂换形（:254-256 / :263-267）覆盖完备。
- 生产宿主调用点本腿独立 grep 核实**恰五处**：runHeadless :254/:263 +
  runHeadlessArbitrated :378/:390/:410——plan 全清单传 project provider；
  read-only 宿主 :410 面上工具在位、open/create 由 registry writer gate
  前置 serverReadOnly 拒——双宿主红线「tools never disappear」兑现且
  不弱化只读语义。
- T4 grep 机检「裸 `McpSearchStateContext()` 在 controller 内零命中」
  在位；**http 无 EOF 腿偏离句**（kernel 地板、checkpoint 优雅面仅
  stdio）入 T4 action 3 + T6 DECISIONS 申报族。

### 门 4（H4——GUI 判别缝谓词 + held 预检）— **PASS**

- 差分谓词三 clause 在位：调用后 `pendingConflict != nil ∧ 调用前 ==
  nil ∧ projectStore 未变化` → typed `projectReadOnly(holderSummary)`
  （plan T4 action 4 + 风险节两处一致）。
- **held 目标 probeLockAvailable 无持有预检**在 openProject **之前**
  （既有 `SingleWriterLock.probeLockAvailable` 面，LightamerApp :1310/
  :1324 同款先例亲验）；controller 零 diff 保持（`projectStore` :52
  `private(set)` / `pendingConflict` :73 `var` 外露可读亲验——预检与
  差分全部 provider 装配侧，零新 controller 面）。
- T5 仲裁 fixture 两腿在位：已持 A + open held B → typed
  projectReadOnly 且 `get_state.project` 仍指 A；stale pendingConflict
  挂起 + open 成功目标 → 成功应答。

### 门 5（M1/M2/M3/L1-L4）— **PASS**

- **M1**：mode 捕获（provider 在 `runHeadless(mode:)` /
  `runHeadlessArbitrated(mode:)` mode 可见作用域内构造）+ arm 内部
  `mode == .stdio` 自守卫（双保险——启动 :353 if 门亲验在位）+ T5
  http mode watcher-absence 腿。
- **M2**：region 规格三处一致（T2 action 3 / T5 action 4 / 风险节）——
  round + 平面 bounds clamp、交后 w/h ≤ 0 → invalidParams 携归一化值、
  两边界 golden 强制（x+w==1.0 精确 / 亚像素 w）；风险节原「round vs
  floor 待钉」收敛为 round+clamp 单式；detailCrop :1096-1097
  renderFailed 亲验在位（只作兜底非规格的论据成立）。
- **M3**：共享 helper 形钉死（`(image, libraryProvider,
  sessionPairProvider)` 签名）——`resolveImageURL` :951 `private static`
  第二参吃 `McpSearchStateContext` 亲验（直调不可达、复制禁令论据成立）；
  files_modified SearchStateToolset 挂 T1+T4 双 hunk 注记 + T6
  DECISIONS「寻址单源抽取」申报 + match_color provider 禁顺手动
  （M7-4 路由）注记在位。
- **L1**：pristine payload 亲点 = **12 键**（image/position/itemCount/
  items/versions/activeVersionID/note/keywords/rating/flag/colorLabel/
  author）——plan 四处（SC / T1 read_first / T1 action 3 /
  files_modified）已改「十二键→十三键」；CONTEXT 修订注记声明
  M7-2-VALIDATION 历史文档不回改、以注记为准。
- **L2**：9 调用点 / 5 文件清单本腿独立 grep 全仓核实（QL pane
  :123/:171 / parity :221/:262/:543 / matchcolor :158 /
  QLRendererTests :206/:227 / MCP body :835）——红线 / T2 验收 /
  SC ③ / Checker 关注点 5 / title 五处口径统一；IOPP 归属
  （BUNDLE-MAP :107）与 T6 注记维持正确。
- **L3**：`ProjectOpenOutcome.name = url.deletingPathExtension()
  .lastPathComponent` 在位；`ProjectFileStore` 公开面无 name 读点亲验
  （禁新 Core face 论据成立）。
- **L4**：list_luts golden **seeded 内容正断言**腿（已知 name/hash/
  size +1 条）在位——恒等式外的可见性腿闭环。

---

## 二、Goal-backward

- ROADMAP §M7-3 行（:107）三验收形态 ↔ 任务面全映射：
  1. **compare/region golden** ✓ → T5 action 4（含 M2 两边界腿）+
     T2/T3 schema/裁剪面；
  2. **project 工具与单写者锁仲裁 fixture** ✓ → T4 工具面 + T5
     action 2（修订后腿族更完备：H4 两腿 + M1 门控腿 + H2 锚腿）；
  3. **快照族零意外 diff** ✓ → T5 action 5-7（union 全点位 + editing
     层两层同批 + H1 五钉显式改 + 零残漏 grep + DECISIONS 申报）。
- REQUIREMENTS MCP2-04..07（:434-437 亲验）↔ 四工具一一对应
  （render_preview=MCP2-04 / list_luts=MCP2-05 / project_open+create=
  MCP2-06 / list_versions=MCP2-07），无孤儿项。
- M7-2 遗留路由一致性：F-AC-1/F-AC-2/N2-1..N2-4/⑥/F-AC-4 本波收口、
  FIX2③ 与 match_color 锚病维持 M7-4、CLIP 贴线待实测——plan 与
  M7-2-VALIDATION 挂账清单逐条吻合（评审维度 6 结论维持）。

## 三、修订自洽专项

1. **H4 顺序语义**（任务书点名专项）：预检（probe held → typed 拒，
   不触 openProject——用户正开项目不可被掀）→ 通过后快照
   `pendingConflict`（调用前）→ `openProject` → 差分评估。三 case
   推演全对：**held 目标**（预检拦截，A 不动、零对话框）/
   **正常成功**（projectStore 变化 → 「未变化」clause false → 非
   conflict 臂 → 成功）/ **stale conflict**（调用前非 nil → 「调用前
   == nil」clause false → 差分不触发 → 成功应答）。谓词逻辑完备，
   两洞（已持误报成功 / stale 反向误报）均消。
2. **H1 清单 grep 零残漏**：三 pattern（`count, 20` / `count == 20` /
   `all23`）入 T5 验收；破坏性钉恰五处（§一 门 1）；grep 不覆盖的
   「20-tool」注释形态见 §四.3 advisory（不阻门）。
3. **H3 双宿主 uniformity**：五调用点全传 provider 后，四宿主函数 +
   EmbeddedState 第五缝的 project 工具在场性成立；no-project 双臂
   open 前行为逐字节负测 + with-project 臂盒读同源——closed face
   identical across hosts 兑现。
4. **files_modified / ΔN 一致性**：22→24 件；SearchStateToolset
   T1+T4 双 hunk 注记齐；estimated_tests +12..20 带维持（评审维度 5
   已核准含 H4③/M1/M2 增腿在上沿内——修订未超评审处方腿集）。

## 四、独立猎残（本腿新增产出）

1. **破坏性计数钉完备性**：H1 清单穷尽（无第六处）——见 §一 门 1。
2. **ambiguous 计数清白**：:412（fixture 行数）/ :507（list_iops 19）/
   :920（错误码 16）/ :273（列 25）——零交集。
3. **advisory：过时「20-tool」doc 注释点**（非阻断——断言与 grep 门
   均不涉及，行为面为零）：
   - **已在 files_modified 内**（T5 同批顺路清扫，零新文件、零申报
     负担）：`McpHostTests` :216/:466/:668；`McpSearchStateToolsetTests`
     :15/:262；`McpRegistrySnapshotTests` :16/:178；`McpFinalSnapshotTests`
     :196（makeUnionRegistry :190-201 段内——该段本波显式改，注释
     随段更新）。
   - **清单外两件——本波不触**（维持零 diff / 不在清单现状）：
     `McpRenderParityTests:564`（IOPP——T2 全消费方零 diff 红线约束）；
     `McpProjectReadOnlyErrorTests:18`（APP，不在 files_modified）。
     注释级陈旧无行为面，留 M7-4/后续批次随批申报处理。
4. 其余扫描（`20-tool`/`is 20`/`all 20` 消息串）均已被 H1 显式改
   清单覆盖或属 §四.3 advisory。

## 五、结论

**放行。** 修订批 `e7d8151e` 对评审放行门 1-5 全部兑现；修订自洽三专项
（H4 差分+预检顺序语义 / H1 零残漏 / H3 双宿主 uniformity）全过；
Goal-backward 无缺口；独立猎残零阻断残留。advisory §四.3 在清单文件内的
注释清扫点随 T5 批顺路处理（零成本）；清单外两件维持不触。执行可按修订
后 plan 直接开跑（T1 起，App bundle 快照红窗自 T2 起的既有申报不变）。
