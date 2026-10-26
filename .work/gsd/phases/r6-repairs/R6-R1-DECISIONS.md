# R6-R1 修复批 — DECISIONS（2026-10-27）

基线 HEAD = `fb32ef92`（全套 4292/35/0）。输入 = omp FAIL 回注（B-1 第二病灶
+ m-1 诊断），正本 = `R6-ACCEPTANCE-OMP.md` §二/§三。批内容 = T1 诊断 + T2
B-1 真修（issue #8）+ T3 机制回归 + T4 m-1 DRT 面板诊断与修复（issue #9）+
T5 收口。

## 一、T1 诊断 — B-1 第二病灶机制（插桩实证）

### 1.1 方法论

理论穷举先行：R6 invalidate 后所有 main-actor 交错序（flushTerminal 先/后于
resume）在逻辑层全部收敛成功——丢失必然在 SwiftUI 渲染/观察层，纯读码无法
裁决。转插桩实证：`[import-obs]` DEBUG stderr 三点插桩（modifier init/
body-read/onChange fire + coalescer deliver + run tail nil 写后行），24+ 轮
`-la_editor_probe` fresh 进程轮（16 文件 fixture，/tmp 即弃项目），失败轮
（2/10 + 4/14，与 omp 28% 同量级）活体 trace 对账。

### 1.2 机制（铁证 trace，round3/8 + 修复前批）

失败轮完整序列：

```
deliver completed 16/16            ← flushTerminal 交付终态（R6 序：先于 resume）
body-read completed adapter=alive  ← modifier body 重估，读到 .completed
fire#2 -> completed adapter=alive  ← onChange 触发（.importing→.completed）
                                     ← adapter.apply(.completed) = omp「导入完成」+val=1 证据源
tail nil written                   ← run tail invalidate+nil 写完成（同 main turn）
body-read nil adapter=alive        ← modifier body 再次重估，读到 nil、@State 完好
（5× host body pass，modifier struct 重建）
<<< 无 fire#3 — onChange 对 (.completed→nil) 永不触发 >>>
FAIL: grid rows never arrived
```

**病灶 = SwiftUI `onChange(of:)` 值输入重估丢失**：nil 写到达 modifier body
（读到 nil），但 onChange 节点未消费该转换。nil 是 run 的**最后一个写**——
再无后续写强制重同步，一次丢失即永久丢失（~28%/轮，概率 = 属性图把该值输入
重估排进 post-nil 事务的调度成功率）。

**三假说实证排除**：
- 复活（R6 病灶一残余）：全写点枚举（:418 deliver / :438 importing / :465
  nil）+ invalidate 三面锁闭合，且失败轮 body-read 读到 nil（若被复活应读到
  .completed）；
- 重挂载/身份复位：mountID 全程同值、adapter=alive；
- else 臂早退（adapter nil）：丢失时点 adapter 恒 alive。

对照 pass 轮：同序多一行 `fire#3 -> nil adapter=nil`（onChange 正常消费）。
R6 归因（复活竞态）确为病灶之一（已修），本病灶独立存在——与 omp「缝外第二
病灶」判定吻合，精化为「到达 modifier body 但 onChange 节点未消费」。

### 1.3 对 omp §二 的两点精化

- omp 证据「nil 已写」由 watchdog 行+AI 行推断——插桩证实 nil 写确实完成且
  稳定（body-read nil）；
- omp 候选修法①（terminal 交付时同步核 nil 补触发）前提错误（实测终态交付
  在 nil 写**之前**，fire#2 时 importProgress=.completed 非 nil）——弃。

## 二、T2 修法 — run tail 直接事件通道（任务书候选③换源）

**裁定**：终局事件不依赖值观察通道。`LibraryProjectController.onImportRunEnded`
（`(@MainActor () -> Void)?` 公开监听面，verifyStrategy/uuidProbe 先例形态）；
run tail 在 nil 写 + coalescer=nil 之后、AI tail 之前，clear-first 同步触发。
`ImportProgressModifier` 在注册 adapter 时挂臂，闭包体 = onChange else 臂逐行
镜像（finish(id:) + importAdapter=nil + reload Task；@State 经 struct 拷贝写
同一存储盒，mount 期有效）。

**幂等性**：双通道（tail 事件 + onChange else 臂）谁先跑谁 nil 掉 @State
adapter，另一通道结构性 no-op（else 臂要求 adapter 非 nil；tail 闭包 guard
`importAdapter != nil`）。tail 恒先（同 main turn，先于任何 SwiftUI 事务）。
onChange else 臂保留价值 = 挂载前在飞 run 的边缘（此时无 adapter 无挂臂，
onChange 从非 nil 初值起的 nil 转换仍可达）。

**红线核验**：invalidate 语义零 diff（病灶一不复活）；FIX2-01 完成态发布面
零 diff（coalescer 本体未触）；17 封存面零 diff（本批产品面 = 3 App 文件，
Core/IOP 零触碰，WorkspaceModel 未触）。

**修法验证**（修复构建，20+15 轮）：0/35 零行（未修复基线 28%/轮，20 连绿
概率 ≈0.2%、15 连绿 ≈1.7%）；trace 形态两型 = ①onChange 丢失仍发生但 tail
通道补偿（fire#2→tail→无 fire#3，行到达）②双通道序贯幂等（fire#3 ->
adapter=nil，else 臂跳过）。

## 三、T3 回归 — 机制面确定性测试（+3 法）

R6 教训落实：生产缝概率性腿不承判别，机制腿确定性复现丢失形态。本批形态 =
**「onChange 结构性缺席的世界」**（单测进程无 SwiftUI 图 = 失败轮丢失形态
的确定性同构）：

1. `testRunEndEventFiresAfterNilTerminalAndClears` — 排序契约：事件在 nil 写
   后同 turn 触发（闭包内读到 nil）、恰一次、自清（幂等）；
2. `testRunEndEventDrivesFinishAndReloadWhenObservationAbsent` — 丢失形态
   正主：真 runImport + 生产挂臂镜像（registry+adapter 注册+终态 apply）+
   无任何 SwiftUI 消费者 → finish+reload 仍必达（旧代码此世界唯一通道
   = onChange，结构缺席 = 永丢）；
3. `testRunEndEventUnarmedTailIsNoOp` — 无挂臂尾零动作。

既有维持绿：ImportProgressCoalescingTests 5/0/0（R6 两 invalidation 法在
内）、ImportCompletionRegressionTests 6/0/0（含 R6 终态稳定法）。

## 四、T4 m-1 — DRT 面板缺席（确诊 + 修复，issue #9）

### 4.1 黑盒复现（实机）

`-la_editor_probe -la_probe_stay` stay-alive 实例（float32-gradient.tif）+
swift AX 走查：tab 轨 = 位置聚类七连（y≈490 横排，omp obs-1 索引漂移实证——
本批两实例 rail 索引 12-18 → 23-29 漂移，位置聚类法免疫）。压第 4 钮
（displayTransform）：**vignette 行渲染在、DRT 控件零**——omp6-09 表型复现。

### 4.2 机制（插桩 A/B 实证）

`[drt-obs]` 三点插桩（body/onAppear/model）：

- EmptyView-else 构建：`body model=nil` 一次，**onAppear 零触发** → 鸡生蛋
  死锁：model nil → EmptyView → 无渲染内容 → appear 事件无附着体 → 不构建；
- Color.clear-else 构建：`body model=nil → onAppear fired → body model=built`，
  全控件渲染（方法 radio 组 / 编码空间 Rec.2020 / EOTF ST 2084 / 峰值
  100 nits / 限色空间）。

**根因 = AR-01 m11（`17b95f2b`）lazy-build 化时 else 臂留 EmptyView**——该
挂载语境（pageContent 的 ScrollView/VStack switch 分支）不给无内容视图发
appear。FilmPanelView 同款 house form 存活因其 body 有常驻 header（if-let
之外恒渲染），DRT 无等价物。最后活证窗口（M2-11 10-07 / M6-3 10-14）与
AR-01（10-17）时间线吻合 omp 疑点。

### 4.3 修法 + 边界

else 臂渲染真零尺寸叶（`Color.clear.frame(height: 0)` + accessibilityHidden）
——appear 事件获得内容钩子，AR-01 m11 意图（祖先 body 不再每评估抛一个
model）保持。峰值滑杆 System Events 设 100→400 nits 实时回读成功（写通道
活）。**T3-DRT 存活链（设值→关→重进）GUI 腿本轮部分完成**：设值+回读✓、
关编辑器✓；重进腿受阻于图库网格 cell 无 AX 物化（本实例形态）+ CG 双击
盲打未中——持久化语义 = R6 `DrtPersistenceTests` 7/0/0 在案，GUI 重驱动
移交下一验收轮（面板可达性已恢复 = 该链唯一 blocker 已除）。

**测试面申报**：EmptyView-appear 语义无 headless 单测通道（需窗口服务的
hosting 测试，引入 GUI 依赖不值）；m-1 回归守卫 = 机制注释 + 本批探针配方
（axpress-dt 位置聚类法，/tmp/r6r1-drt/ 即弃留存脚本）+ 下轮 omp T3-DRT 链。

## 五、观察项（obs）

- **obs-1（teardown SIGTRAP flake）**：DrtPersistenceTests 过滤轮 1/3 次
  宿主 exit=133（SIGTRAP），crash 报告 = `ShadhiModule.deinit` MTLTexture
  释放叠 `PipeCoordinator.deinit` 链——Metal teardown 竞态族，与本批改动面
  无关（IOP 零 diff），两次复跑 7/0/0 绿。若全套复现则立项。
- **obs-2（tab 轨 AX 索引漂移再证）**：同机两实例 rail 按钮索引漂移 11 位
  ——走查驱动一律位置聚类（y 行簇 + x 排序），禁硬编码索引（omp obs-1 升级）。
- **obs-3（图库网格 cell 无 AX 物化）**：library face 仅 `library.grid.end`
  可见，cell 本体不出树——GUI 重进链需 omp 级行驱动（其流程 AXRow 可达）或
  cell 级 AX 标记补齐（独立小批候选）。

## 六、commit 列表

| commit | 内容 | issue |
|---|---|---|
| `80f8814f` | fix(r6r1): drive the import run-end through a direct tail event | #8 |
| `0507135b` | fix(r6r1): give the DRT lazy-build appear hook a real leaf | #9 |
| （收口） | docs(r6r1): ledger — summary + decisions | — |

## 七、卫生

- 插桩修剪：`[import-obs]` 保留 fire/deliver/tail 三类（~6 行/run，复发取证
  面）；`[drt-obs]` 与 mount-init/body-read 诊断噪声全撤（机制入注释）。
- GUI 实例（film probe 98109 / probe-stay 98306 / 98713 / 460）逐一 kill 清
  零复核（ps 0 实例）；`library.recentProjects` 探针污染整键删除（键不存在
  复核）；/tmp fixture（r6r1-fixture / r6r1-drt / r6r1-runs / r6r1-build*.log）
  即弃域留存下轮；未 checkout 参考仓；DerivedData 单容器使用（dzgs…，无
  worktree/独立 DD）。
- 代理：gh 建单期 px --up（死代理残留三件清后成功，SOP §6 形态）→ issues
  #8/#9 建 + push（29be5cba..0507135b，`fixes #N` 随默认分支推送自动关闭）
  → 全套起跑前 px --stop。
- guard：全套起跑前 PASS（heavy=0 free=57%）+ ps 内联清零验证；monitor
  `--monitor 21600` nohup 伴跑。
