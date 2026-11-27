# B1-c REPORT — Render jobs on the engine: injectable sources, generations, latest-wins, demo

结论头：B1-c 渲染作业接线完成——双注入口、`render.request`/`render.cancel` 两命令、（照片，实例）代号 latest-wins、同实例互斥、渲染记录、七步演示全部落盘；全工作区测试由 525 涨到 553（+28），另有三份默认不跑的计时测试；三演示脚本与 `Scripts/rust-ci-lite.sh` 全绿，复审 `PASS / 0 error + 3 minor`（三处全修，见 §9）。

## 0. 起点与 HEAD

- 起始 HEAD（亲核）：`ceb878bff2818810cb0b63222888636d0f7eccf2`（B1-c 任务书提交；B1-b2 代码提交 `cfca6531` 为其父）。
- 起点状态（逐条核过）：管线有同步 `Pipe::render`（节点、模块来源、输入画面、输入标识、处理版本号、输出区域、取消检查）；引擎有 4 线程作业池（`Task`/`JobCtx`/作业消息）、事件（作业开始/进度/结束、照片/剪贴板变更）、快照、`collect`；备份/恢复/扫描已是「命令登记、作业去做」；无解码、无真实模块；引擎不依赖管线的 crate（`cargo xtask layers` 29 包无违规）。
- 基线：`cargo test --workspace --locked --offline -j6` 全绿，`--list` 计 525 个（522 跑 + 3 ignored），与 VERIFY B1-b2 一致（268.5s）。
- 构建前守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=63% swap=?M disk=?GB)`。
- 全程并行度 `-j6`，无 `caffeinate`，无 Swift 构建，无图形程序。

## 1. 注入口（`crates/lightamer-engine/src/render.rs`，新文件约 940 行）

两个 trait，由嵌入引擎的一方注入，引擎自己不去找，默认都没有：

- `InputSource::fetch(photo) -> Result<RenderInput, InputError>`：给照片标识，交出画面（`Frame`）、图像信息（`ImageInfo`）、输入标识（`input_id: u64`），或分了类型的 `InputError`。只在作业线程里调用（为将来的解码留的：可能很慢）。没有它时 `render.request` 报 `CommandError::NoInputSource`（新增变体，一句人话），不起作业。
- `ModuleSource::lookup(id) -> Option<SharedModule>`：按标识找模块（`Arc<dyn IopModule>`）。闭包与 `HashMap` 都是来源（与管线 `ModuleLookup` 同款 blanket 实现）。没有它时链是空的，输出等于输入；单个标识找不到时跳过并记进本次记录（`skipped: unknown-module`），永不报错。
- 核心里没有模块标识的中心名单：执行序按注册表的非 raw 默认链（`jpg_chain`）排，注册表里没有的标识排在后面、按（标识，多实例下标）排序。B1 没有解码、没有照片的 raw 信号，所以先全走非 raw 链；B2 按照片的 raw 与否分流（写在 `execution_order` 文档里）。
- 管线实例由引擎自己建：`Engine::new` 建四种各一台（`Pipe::new`，预算按活物理内存；读不到时按 8 GiB 保守值 `FALLBACK_PHYS_BYTES` 推导，构造永不失败）。

## 2. 两条命令与代号、取代的规则

经 `execute` 登记（`render::SPECS` 并进 `command_specs`，注册表 22→24 条），参数都是 `photo`（Text）+ `kind`（Text，四词 `full`/`export`/`preview`/`thumbnail` 之一；`kind` 用 Text 而非 Enum——Enum 无取值器先例，错词报 `BadParam` 并列出四词，同样分类型）：

- `render.request { photo, kind }`：校验（照片存在→`NoPhoto`；输入来源存在→`NoInputSource`）→ 快照请求那一刻的当前设置（`photo_settings`：草稿读内存，真实会话走库的读穿面；渲染不写库）→ 该（照片，实例）代号加一 → 在飞的那一代置取消标志（作业表里那行的 flag——就是传给管线的取消检查）→ 起作业 → **立即返回** `{"generation", "job"}`。登记之后无等待：快照是内存读（真实会话是一次读穿），spawn 入队即返；「命令先返回」有测试钉死（慢模块 500ms，返回时作业非 terminal）。
- `render.cancel { photo, kind }`：取消在飞的那一代（置同一 flag，清在飞标记），不起新的；没有在飞时成功返回 `{"cancelled": false}`。**幂等是定死的语义**：取消与完成撞车不报错（与 `job.cancel` 对已完成作业 no-op 同款）。只停未完成的工作：已完成但未 `collect` 的投递仍会落地（M2 窗口，有测试钉死）。
- 取代只发生在同一个（照片，实例）内：新请求只碰自己那一槽的在飞作业；不同照片、不同实例互不影响（有隔离测试）。

## 3. 作业怎样跑、结果怎样回来、同种实例怎样互斥

- 作业线程（`run_render_job`，只用快照 + 注入源 + 管线锁 + 发送通道，不碰引擎状态）：排序跳过（禁用的记 `disabled`，找不到的记 `unknown-module`；参数 `SettingValue`→管线 JSON 是全函数 `setting_cell`，与 serde 派生形状六种逐值对过，无序列化失败路）→ 查取消 → 取输入（**锁外**：慢解码不挡管线）→ 抱住该实例的锁（`Arc<Mutex<Pipe>>`，每种一台）→ 锁内先查取消 → 调 `Pipe::render`（输入标识、处理版本号 `settings.process.0`、终点区域 = 输入整帧）→ 把像素拷出预算（`RenderedImage`，不占管线预算）→ 经无界通道发回，**发前先放锁**（发送永不阻塞锁）。
- 引擎线程（`collect`→`finish_restores` 之后接 `finish_renders`，与恢复作业同款待收表）：只有代号等于该槽当前代号的投递才落地——存画面、存记录、发事件；旧代号的投递整份丢弃（无画面、无记录、无事件）；取消的投递（被取代或被取消）不发渲染事件（作业通用的开始/进度/结束照常）；作业起跑前被跳过（无投递）时清在飞标记，worker 侧失败则合成一条失败事件。投递先于完成消息发出（同恢复作业的论证），`collect` 先排空作业消息再收投递，不丢不重。
- 事件：`RenderReady { photo, kind, generation }` 只为最新一代发；最新一代失败（模块错、输入错、管线错）发 `RenderFailed { photo, kind, generation, reason }`；取消不是失败，不发。
- 互斥：一把锁一种实例（四台管线各包一 `Mutex`，`render_pipe` 按 kind 解构取，无下标、无嵌套、无死锁）。被取代的作业在下一次取消检查处让出：管线在入口、每节点前、每块前查取消——最坏多占锁一个 `process` 调用的时长；输入获取在锁外，不占。
- 会话关闭清掉全部槽位（画面、记录、代号）与待收表；在飞作业的迟到投递因无槽可落而丢弃。

## 4. 每次渲染的记录（管线侧只加这一项）

`crates/lightamer-pipeline/src/render.rs` 的增量（该 crate 别处零改；`git diff ceb878bf HEAD -- crates/lightamer-pipeline` 只有本节 5 处 + 5 个测试）：

1. `NodeReport { id, multi, hit, process_calls, millis }` + 私有构造 helper（命中：零调用零毫秒；未命中：调用数 = 1（整帧）或块数（分块），毫秒实测）。
2. `Pipe` 加 `last_trace: Vec<NodeReport>` 字段 + 只读 `last_trace()`（`with_budget_and_floor` 初始化；`RenderRequest` 签名零动，既有构造点零触碰）。
3. `render()` 在入口清、命中/未命中各推一条（含 `Instant` 计时）；取消或失败留已完成的前缀（没算完的节点一条不留），空链留空。
4. `run_tiled`（私有）返回值加实际执行的块数（`Ok((out, calls))`，空网格 0）。
5. `lib.rs` 导出 `NodeReport`；5 个新测试（miss→hit 两轮与探针计数对齐、改参部分重算、9 块数与探针一致、失败留前缀、空链留空）。

引擎侧 `RenderRecord { generation, job, nodes, skipped }` 随投递回来，按槽存 `last_record`，只读方法 `last_render_record` 给演示和测试。

## 5. 命令行演示与脚本

- `lightamer-cli render-demo [--size N]`（默认 256，限 8..=1024）：合成渐变输入 + 私有 `demo_gain` 模块（乘增益 + 可选 `sleep_ms`，定义在本文件——testkit 只作开发依赖），真实会话（`bench_setup` 复用，3 张空占位）在自建临时目录里走七步，每步打印，任一步期望不符即非零退出：
  1. 建会话、3 张占位、首图链上 5 个增益；2. 渲染（preview）+ 节点表；3. 改中段增益再渲染（node 1 命中、node 2-4 重算，node 0 因 4 槽位挤出而重算——见 §7）；4. 连发三代只收最新就绪 + 三代作业结局；5. 慢渲染取消后无事件；6. 次图空转计时（全 miss）；7. 关会话、清临时目录。
- `Scripts/rust-render-demo.sh`：守卫 → 发行版构建 → 跑子命令 → 断言 `ALL GREEN` 与关键行 → 查无残留临时目录（排除脚本自身）→ 退出 0。只用自己的临时目录与合成画面。

## 6. 演示的输出

`Scripts/rust-render-demo.sh`（发行版构建 30.7s，`render-demo --size 256`，退出 0；改脚本卫生检查后二次跑 8.2s 退出 0）：

```text
step 1: plant a session with three empty photos (256x256)
  five demo_gain instances sit on the first photo's chain
step 2: render once (preview)
  generation 1 job 2: 5 nodes, 0 skipped
  node | id | hit | process calls | ms
  0 | demo_gain multi=0 | miss | 1 | 0.131
  1 | demo_gain multi=1 | miss | 1 | 0.125
  2 | demo_gain multi=2 | miss | 1 | 0.233
  3 | demo_gain multi=3 | miss | 1 | 0.186
  4 | demo_gain multi=4 | miss | 1 | 0.188
step 3: change the middle gain, render again
  generation 2 job 3: 5 nodes, 0 skipped
  node | id | hit | process calls | ms
  0 | demo_gain multi=0 | miss | 1 | 0.134
  1 | demo_gain multi=1 | hit  | 0 | 0.000
  2 | demo_gain multi=2 | miss | 1 | 0.072
  3 | demo_gain multi=3 | miss | 1 | 0.071
  4 | demo_gain multi=4 | miss | 1 | 0.095
  node 1 hits (upstream keys unchanged), nodes 2-4 recompute: ok
  note: node 0 recomputes only because the 4-slot preview cache
  holds 4 of the 5 planes; its key is unchanged (node 1 hits on it)
step 4: fire three generations without waiting (only the latest reports)
  render events: [RenderReady { photo: "32235cee-…", kind: "preview", generation: 5 }]
  job 4 generation 3: Finished { cancelled: true }
  job 5 generation 4: Finished { cancelled: true }
  job 6 generation 5: Finished { cancelled: false }
step 5: start a slow render, cancel it (no ready event)
  generation 6 cancelled, no render event: ok
step 6: idle timing on the second photo (preview, all miss)
  generation 1 job 8: 5 nodes, 0 skipped
  node | id | hit | process calls | ms
  0 | demo_gain multi=0 | miss | 1 | 0.109
  1 | demo_gain multi=1 | miss | 1 | 0.104
  2 | demo_gain multi=2 | miss | 1 | 0.105
  3 | demo_gain multi=3 | miss | 1 | 0.112
  4 | demo_gain multi=4 | miss | 1 | 0.104
step 7: close the session, remove the temp dir
demo: ALL GREEN
```

（job 1 是 `session.open` 的失联扫描作业；照片 UUID 中段省略。256px 合成帧单节点约 0.1ms。）

## 7. 与任务书的偏差

- 演示第 3 步的期望是 `[evicted, hit, miss, miss, miss]`，不是任务书写的"前两位命中"：预览缓存只有 4 个槽位（B1-a 表：Full 8 / Export 4 / Preview 4 / Thumbnail 2），5 节点链的第 5 次插入必然挤掉第 1 个平面——node 0 的键没变（node 1 的键折叠了 node 0 的贡献而 node 1 命中了，这是逻辑证明），重算只是容量挤出。任务书字面在 preview+5 节点下数学不可达；「改参只重算下游」的干净形状由引擎测试 `record_matches_module_side_process_counts`（3 节点 `[hit, miss, miss]`、探针总数 5）钉死。演示打印了这行解释，断言按诚实值。
- 其余：`kind` 用 Text（见 §2）；取消无在飞时成功报 `{"cancelled": false}`（见 §2，幂等）；保留画面拷出预算（见 §3）；失败也带记录（`nodes` 为已完成前缀）。

## 8. 验收（命令与输出）

- `cargo test -p lightamer-engine --locked --offline -j6` → 10 个二进制全 ok：183 通过 0 失败（lib 66 含 5 个 render 单元测试；render_jobs 17；其余 7 个文件 100）。「测试」一节映射：latest-wins→`latest_wins_three_slow_generations_keep_only_third`（卡片第六条）+ `real_session_supersede_keeps_only_latest`；取消→`cancel_leaves_no_ready_event_and_next_request_runs` + `cancel_without_in_flight_reports_false_and_spawns_nothing` + `cancel_after_finish_before_collect_still_lands_ready`（M2 窗口）；隔离→`supersede_isolated_across_kinds_and_photos`；失败→`module_commit_failure_reports_failed_with_reason_and_returns_budget` + `input_failure_reports_failed_with_reason_and_returns_budget`；命令先返回→`request_returns_before_slow_job_finishes`；坏参数→`request_rejects_unknown_missing_and_bad_kind_without_spawning` + `request_without_input_source_is_typed_and_spawns_nothing`；空模块源→`empty_module_source_renders_identity_and_records_skips`；快照→`render_uses_request_time_settings_snapshot`；排序与跳过→`chain_order_and_skips_match_registry_and_switches`；记录→`record_matches_module_side_process_counts`；分发口→`registry_grows_by_two_with_unique_params`；真实会话→`real_session_renders_and_leaves_store_untouched`（库转储前后逐字节等）+ `real_session_supersede_keeps_only_latest`。全部在临时目录跑，不碰用户照片库与真实应用支持目录。
- `cargo test -p lightamer-pipeline --locked --offline -j6` → 87 通过 0 失败 2 ignored（82+5 记录测试）。
- `cargo test -p lightamer-cli --locked --offline -j6` → lib 44 通过（含 `demo_runs_small_and_reports_green`）+ 集成 5 通过，0 失败。
- `cargo test --workspace --locked --offline -j6` → 全绿（修订前跑通 552；修订后 `render_jobs` +1，`--list` 计 553 个 = 550 跑 + 3 ignored = 基线 525 + 新增 28：引擎 5 单元 + 17 集成 + 管线 5 + CLI 1）。
- `cargo xtask layers` → `OK: 29 crates, no layering violations`（管线不依赖引擎；引擎→管线/栅格/几何三条新边均为 L4→L2/L0，合法）。
- `cargo xtask check-no-iop-names` → `OK (97 names, 4 roots clean)`（引擎测试只用 `mod_gain*` 假名）。
- `Scripts/rust-apple-boundary.sh` → `ALL GREEN`（7/7）；`Scripts/check-licenses.sh` → `allow=852 exception=1 fail=0 total=853`（与基线逐字同，无新增第三方 crate，`docs/LICENSE-AUDIT.md` 无需加行）。
- 六条 lint 全工作区退出 0（修订后重跑）；`cargo fmt --all --check` 干净；`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked --offline` 退出 0。
- `rg -n 'std::fs|create_dir|read_dir|std::fs::copy|fs::copy' crates/lightamer-engine/src` 无输出。
- `git diff --stat ceb878bf HEAD -- crates/lightamer-history crates/lightamer-registry crates/lightamer-catalog 'crates/lightamer-iop-*/src/modules' crates/lightamer-apple` 无输出。
- 三演示脚本各退出 0：render（上见）、session（`demo: ALL GREEN`）、history（`demo: ALL GREEN`，一万张中位数 147.3ms PASS）。
- `Scripts/rust-ci-lite.sh` → `rust-ci-lite: ALL GREEN`，退出 0（197.6s；修订前跑通，测试 549 通过；修订为注释 + 1 测试，修订后分包复验：引擎 183、CLI 49、lint、`fmt` 全绿；界面重建 2s≤180s，发行版 17786416B≤80MB，单 crate 检查 0s≤40s，`target/` 17571MB≤20GB；冷构建两项 SKIP）。
- 跑完之后：`git status --porcelain` 无测试/脚本残留（仅本波路径改动 + 他人 `.work/` 未跟踪文件 + 早已存在的 `evidence/gui/paste-tiers.csv`，均不动）；系统临时目录无本波残留（顺手清掉一批 PID 已死的他轮 `lightamer-engine-test-*` 空壳，塔台 B13′-c 先例）；无残留进程（命中的一条 `omp -p` 即本 lane 自身）。
- `git show --name-only HEAD` 24 路径全在允许清单内，含 `B1-c-REPORT.md` 与 `B1-c-review.log`。
- Commit：首提 `669d05f71f`（`refs #32`，零 push）；复审修订 + 本报告终稿 + 复审日志 amend 并入，最终提交与首提仅差这三处，哈希见 `git log --oneline -1`。

## 9. 复审的结论头与修订记录

复审实例独立重跑验收（`B1-c-review.log`，只读未改代码）：`PASS / 0 error + 3 minor`——分包测试数（复审时引擎 182 / CLI 49 / 管线 87+2ignored；修订后引擎 183、全工作区 552→553）、治理四件（许可证 `852/1/0/853`）、六条 lint、`fmt`、文档零警告、三演示脚本、`rust-ci-lite.sh`（`passed=549`）、提交面 23 路径全对上；代码六条逐项核（命令先返回的 spawn 后无等待、取代三规则、作业线程零引擎引用、渲染零 catalog 引用 + 转储比对、演示 step5 代号链、管线 diff 逐 hunk）+ 四项挑刺核（不可达分支、4 槽位形状诚实、跨通道时序成立、cancel 幂等）。三处 minor 全修：

- M1（`final_roi_for` 的 `Roi::new(...).map_err` 臂不可达）：已加注释点名（w/h 源自 u32 恒非负、scale 恒 1.0，防御性保留）。
- M2（finish-then-collect 窗口：作业已完成但未 `collect` 时 cancel 报 `cancelled:true`，随后投递仍落地并发就绪）：行为自洽，补两处——`run_cancel` 注释写明"只停未完成的工作" + 新增确定性测试 `cancel_after_finish_before_collect_still_lands_ready`（毫秒渲染 + 500ms 裕量）钉住该窗口。
- M3（演示 step3 注释欠半句淘汰序机制）：已补（点名 B1-b 上游 MRU 逆序 touch + 最老先逐跳过本轮命中）。

修订后复验：引擎 183 绿、CLI 49 绿、六条 lint 0 error、`fmt` 干净、workspace `--list` 553（amend 前重跑，命令见 §8）。

## 10. 给用户看的汇报

B1（管线内核）四段全部做完，停在这里给用户看：

**做成了什么。** 照片的渲染管线从零跑通了：B1-a 立了地基（画面、区域、模块接口、几何链、格式协商、分块决策）；B1-b 让它真跑起来（同步渲染入口、链式缓存、分块执行、按物理内存的配额，6100 万像素空转 27ms）；B1-b2 修了内存峰值随链长涨的毛病（五节点 6100 万像素从报错变成功，142ms）；B1-c（本波）把渲染接到引擎的作业池上——点一次渲染，命令立刻返回，作业在后台渲，连点三次只留最后一次的结果，中途能取消，每次渲染每个节点命中还是重算、有据可查。

**现场看，一条命令：** `Scripts/rust-render-demo.sh`（约半分钟：发行版构建 + 七步演示）。会看到：首图 5 个增益渲染的节点表；改中间一个增益后上游命中、下游重算；连发三代只有最新一代的一条就绪事件；取消慢渲染后无事件；次图空转每节点约 0.1ms（256px 合成帧）。

**还没做的。** 没有解码（B2：输入画面现在是合成渐变，真片还进不来）；没有真实模块（B3 起：链上现在是演示用增益）；没有色彩变换执行（B5：遇到要转空间的链报分了类型的错）；预览缓存 4 槽位装 5 节点链会挤出首个平面（演示第 3 步如实展示；槽位数是 B1-a 定的，不在本波改）。

## 11. 未做 / 未验

- 未做：B2 范围（解码、输入标识的真实来源、预览管输入上限的路由保证）；真实模块（B3 起）；色彩变换执行（B5）；块级并行（仍串行）；`docs/LICENSE-AUDIT.md` 无新增行（无新第三方 crate）；`render.cancel` 不接 `job.cancel` 的反向联动（`job.cancel` 置同一 flag，投递照样丢弃——行为已对，无需联动）。
- 未验：非 macOS 编译（单目标纪律；在 Linux 目标上只跟随 `rust-apple-boundary.sh` 跑，不单独编引擎）；64 核以上机器的代际竞态（逻辑与线程数无关，4 线程池已验）；机械盘/高负载下的演示耗时（门内余量大，未加测）；修订后未重跑全套 `rust-ci-lite.sh`（修订为两处注释 + 1 测试，分包测试与 lint 已重跑）。
