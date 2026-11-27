# B1-b REPORT — Pipeline execution: render, cache, row parallelism, tiling runs

结论头：B1-b 执行完成——同步渲染入口、链式缓存、按行并行、分块执行、单块下限、物理内存配额全部落盘，
全工作区测试由 460 涨到 511（+51），另有第二份默认不跑的计时测试；61MP 空转未命中中位数 27.5ms（门 200ms），
`Scripts/rust-ci-lite.sh` 全绿，复审 `PASS / 2 error + 4 minor`（六处全修，见 §12）。

## 0. 起点与 HEAD

- 起始 HEAD（亲核）：`553aff5204aabf38a180d84e0eac93fce0231c03`（B1-b 任务书提交；B1-a 代码提交 `7ff98662` 为其父）。
- 起点状态（逐条核过）：地基八件在位、无执行（无渲染函数、无缓存、分块只有决策、`to_scale` 只有测试用）；
  配额四常量（Full/Export 4GiB、Preview 1GiB、Thumbnail 512MiB）；分块决策无单块下限。
- 基线：`cargo test --workspace --locked -j6` → `passed=460`（83 二进制全 ok，与 VERIFY 一致；127.7s）。
- 构建前守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=70% swap=?M disk=?GB)`。
- 全程并行度 `-j6`，无 `caffeinate`，无 Swift 构建，无图形程序。

## 1. 渲染入口（`render.rs`，+30 测试：29 跑＋1 计时）

`Pipe` 是一种实例一台：`{ kind, budget: Arc<Budget>, floor, cache: PlaneCache }`。
`Pipe::new(kind)` 从活物理内存推导预算/槽位/下限；`with_budget_and_floor` 给测试显式数字。
`RenderRequest` 一次给齐八样：执行序节点、模块来源、图像信息、输入画面、输入标识（u64）、
处理版本号（u32 明文，不依赖历史模型类型）、终点区域、取消检查（`&dyn Fn() -> bool`）。
还回 `OutputFrame`（`Arc<SharedFrame>` 新瓶）或 `RenderError`（七种，全带人话）。

次序（`render()`）：入口取消检查 → `build_chain` → 空链短路（拷贝，要求输入已在终点区域）
→ `forward` → `backward_check` → `negotiate`（首个变换步骤即 `ColorGap`，点名起止空间；
变换本身 B5）→ 逐节点：取消检查 → 缓存 peek（命中且 extent 相符：复用，无 `process`、
无重分配；键撞但几何不符：按未命中重算——与上游 `_get_by_hash` 的尺寸失配失效同款，
`pixelpipe_cache.c`）→ 未命中：`tiling()` 取请求 → `decide` → 不分块调一次 `process`，
分块逐块调 → 成功才提交（命中触达 + 待写条目）；取消/任一错误直接返回，临时的画面随栈帧放掉。

七种错误与触发测试：`Chain`（UnknownModule/Commit/BadRoi/Roundtrip/LengthMismatch 全沿用）、
`ColorGap{after,from,to}`、`Node{id,tile,source}`、`OutOfBudget{detail}`（预算数字全列）、
`Frame{detail}`（帧/平面构造故障）、`InputMismatch{detail}`（首节点输入须与调用方画面逐位一致，
x/y/w/h）、`Cancelled`。每种一例，断言类型 + 人话 + 预算归零 + 缓存空。

偏离记录：`decide` 吃的是预算上限（非上游 `granted - cachemem` 的剩余额度）——上限是常量，
冷热两趟网格相同（任务书「同一台机器两次相同」）；剩余额度随缓存态漂，网格会变。B1-c 若要
上游行为，传 `remaining()` 是一行。

## 2. 缓存（`cache.rs`，+8 测试）

键（`chain_keys`）：FNV-1a 链式折叠——域名标签 `lightamer.pipe.cache.v1` ＋ 实例种类 ＋
输入标识 ＋ 处理版本号 ＋ 逐节点（链位置 u64、标识长度＋字节、多实例下标、参数规范 JSON
长度＋字节、输入/输出区域 x/y/w/h＋缩放位）。形状照上游 `_dev_pixelpipe_cache_basichash`
加区域折叠（`pixelpipe_cache.c:99-184`：图像 id、管线类型、逐 piece `piece->hash`；
`piece->hash` = 操作名＋实例＋参数，`imageop.c:2562-2595`）。

算法与历史模型 `hash64` 同为 FNV-1a，但**在这个 crate 里另算一份**（`fnv1a`/`mix` 十行，
标准向量空串与 `foobar = 0x85944171f73967e8` 钉死，后者与独立 Python 实现对过）——
L2 同层虽允许管线依赖历史模型，为一个哈希函数添一条边不值当。

参数规范 JSON 是递归手写（`push_value`/`push_object`，逐级按键排序）：工作区把
`serde_json` 的 `preserve_order` 特性合了进来（经 schemars 系传递依赖），`Map` 是插入序，
裸 `to_string` 在全工作区构建下首轮即错（`params_key_ignores_insertion_order` 单 crate 绿、
全工作区红——本波亲历的特性合一陷阱；修法即递归排序，另加嵌套序测试）。

行为（`PlaneCache`）：按字节＋槽位双重准入（字节上限 = 预算的一半，给下一趟工作集留地方；
槽位沿用 B1-a 表），淘汰最久没用；超上限的平面拒绝（`false`），渲染照常成功。
命中实现零拷贝（`Arc` 克隆）；`peek`（读不碰新近度）＋成功提交时 `touch`＋`insert`，
取消/出错缓存逐字节不动。逆序提交：下游先定夺，上游条目最新近（下游改参数复用上游，
反之不成立）。
验收对应：同请求第二次零 `process`（`second_identical_render_calls_no_process`）；
改中段参数只重算它及下游（`param_change_recomputes_node_and_downstream_only`，三探针计数
1/2/2）；上游命中不重分配（`upstream_hit_reuses_plane_without_realloc`，`Arc::ptr_eq`）；
跨实例/跨版本号/换输入标识三负测；预算紧张跳缓存
（`tight_budget_skips_cache_renders_ok_and_returns_bytes`，1024 字节预算渲
1024 字节单节点：成功、缓存空、握输出 1024 在账、放手归零、第二趟重算）；渲染级 LRU
（4096 预算五连 gain，缓存留二，逐出命中计数钉死）。

## 3. 预算跟着画面走（`sysmem` +2，`budgeted` +1）

`sysmem` 新增 `SharedGrant`（`Arc<Budget>` 授权，`acquire_shared`，借用式 `Grant` 原样保留，
记账共用一个 `charge` 上锁点）；`budgeted` 新增 `SharedFrame`（画面＋owned 授权）与
`alloc_shared`（先扣款后分配，失败 grant 已 drop）。渲染的中间画面、缓存条目、返回输出
`shared_frame_returns_bytes_when_last_holder_drops` 与渲染级三测试钉死（§2 末）。

## 4. 分块执行（`render.rs` 内，+2 测试）

`run_tiled` 照 `_default_process_tiling_ptp`（`tiling.c:690-806`）：最大块尺寸的一对可复用
输入/输出暂存（充电到预算上）；逐块从上游整画面拷含重叠的输入；`iroi`/`oroi` 绝对坐标
（`:740-741`）；每块调一次 `process`；好块（只裁前侧重叠）拷回（`:780-790`）。
帧边截掉的重叠由网格 builder 钳掉，执行侧 `view` containment 拷贝。
块间串行（块级并行未做）；暂存分配失败是分类型预算错误（上游回落不分块加日志，
我方确定性优先——已写进报告与注释）。

两例验收：FakeMem（factor 8，overlap 0）64x64 在 20 万预算下切 3x3＝9 块
（手算：可用 68,928 → 单块 8,616 → scale 0.131 → sqrt 缩 23x23 → ceil(64/23)=3，
末列钳 18），每块一次 `process`，与 4GiB 不分块逐位相同；
FakePosition（factor 8，overlap 4，自带值只与绝对坐标有关）100x100 在 40 万预算下
切 6x6＝36 块（25x25，步长 17，末列钳 15），逐块 `rin` 含重叠（25 宽/17 步长/85 起点
三断言），与不分块逐位相同——好块拼装对了逐位才合得上。

## 5. 按行并行（`iop-traits::parallel`，+4 测试；`testkit` 恒等改用）

`par_map_rows(src, dst, rows, src_stride, dst_stride, row_len, f)`：校验（行宽入 stride、
两缓冲装得下，checked `usize`，错即 `RoiMismatch`）→ 按 `4×线程数` 切块 → `rayon::scope`
逐块派发（`split_at_checked`/`split_at_mut_checked`，无一处下标）。行对之间不交叠，
并行与串行逐位相同，与线程数无关。`Plane`/`PlaneMut` 新增整片访问器（`as_slice`/
`as_mut_slice`）。恒等模块改走它（行拷贝闭包）； shapes 检查保留，行为测试全绿。

测试：137x61 并行拷贝与串行逐位同；stride 间隙不被碰（9 行 padding 断言——首轮曾抓到
跨块间隙 bug：顺序切分忘跳块间 `stride - row_len`，已修）；单行/零行（零行闭包零运行）；
短缓冲/宽行四错全分类型。渲染级 `one_thread_and_many_threads_agree_bitwise`（1 线程池
vs 8 线程池同渲逐位同）。

## 6. 单块下限（`tiling::decide` +1 参数，+3 测试）

`decide(..., singlebuffer_floor: u64)`：`singlebuffer = max(available / factor, floor)`，
即 `tiling.c:613-620` 的 `fmaxf(available / factor, dt_get_singlebuffer_mem())`。
B1-a 的 11 处调用逐处加 `0`（零下限＝旧行为，期望逐位不动）：
`fitting_frame_and_default_request_stay_untiled` 两处（1_000_000/200_000 预算）、
`wide_frame_splits_into_two_x_tiles`、`square_frame_splits_both_ways`、
`aligned_tiles_land_on_the_grid`、`overlap_widens_input_and_trims_leading_good_part`、
`narrow_end_tiles_are_skipped`、`tiny_budget_gives_up_to_untiled`、
`mismatched_or_empty_regions_stay_untiled` 三处（异形/换缩放/空）。
新测三例（1000x100 旧算例复用：商 800,000）：下限 700,000 不动（仍 2 块）；
下限 1,200,000 长大（scale 0.75 → 750 宽 → 2 块，末块钳 250）；下限 1,600,000 整帧一瓦。

## 7. 配额公式（`kinds.rs`，+4 测试）

`quota_for(kind, total)`：分成 Full/Export 各 16%、Preview 5%、Thumbnail 3%（合计 40%），
钳进[下限，上限]（下限 512/512/256/128 MiB，上限＝B1-a 常量表）；钳完超 40% 池则按比例
压回（下限让路，池不让）。`u128` 精确算，无溢出。`max_tile_bytes`/`cache_slots` 沿用 B1-a。
`singlebuffer_floor`：Full/Export `max(2MiB, total/128)`（与上游 `default` 档逐字相同），
Preview ÷256、Thumbnail ÷512（帧小逐级减半）。`system_physical_memory()` 经 libc
`sysconf` 读物理内存（crate 唯一 `unsafe`，两处调用点各带 SAFETY 说明；失败返回
`io::Error`，调用方回落常量）。

16 GiB 值（测试钉死）：Full/Export 2,748,779,069（2.56 GiB）、Preview 858,993,459、
Thumbnail 515,396,075，合计 6,871,947,672（6.4 GiB）＜ 9 GiB 线；下限 128/128/64/32 MiB。
边界：1 TiB 全钳上限；512 MiB 小机器按比例压进 40% 池（Full＝Export＞Preview＞Thumb 全正）。

分成出处：上游 `default` 资源档（`darktable.c:2334-2339` 的 512/1024，
`darktableconfig.xml.in` 的 `resourcelevel` 默认 `default`），收紧到 40%；
Thumbnail 整管 `/3`（`pixelpipe_hb.c:359-376`）折成 3% 股。

## 8. 空转计时（默认不跑，发行版）

命令：`cargo test --release -p lightamer-pipeline --locked -- --ignored idle_61mp --nocapture`。
输入 9504x6336 float32 RGBA（240,844,800 浮点 ≈0.98GB，调用方建好，不计时），单恒等节点。
负载口径照 `rust-budget.sh:load_busy`（uptime 首数/ncpu＞1 或守卫不过 → 报 UNRELIABLE 跳门），
峰值常驻走 `getrusage` 自报＋`/usr/bin/time -l` 旁证。

- 未命中中位数（5 轮，冷 pipe）：**27.5ms**，门 200ms，**过，余量约七倍**。
- 命中中位数（5 轮，暖 pipe）：**0.002ms**（Arc 克隆）。
- 峰值常驻：自报 1840MB，`time -l` 1,929,953,280B（1840.8MB），4GB 停手线下约一半。
- 负载行：`load1=2.94 ncpu=10 guard_ok=true`（0.29/核，安静）。

## 9. 验收（命令与输出）

- 起点基线：`cargo test --workspace --locked -j6` → `passed=460`（83 二进制，见 §0）。
- 六 crate（`--locked --offline -j6`，逐个绿）：geom 11、raster 9、sysmem 7（+2）、
  iop-traits 19（+4）、pipeline 71（+45，另 1 ignored 计时）、testkit 6＋1 文档测试。
- 全工作区：`cargo test --workspace --locked --offline -j6` → `passed=511 failed=0`、
  83 二进制全 ok（460＋51：pipeline 45、iop-traits 4、sysmem 2）。
- 卡片验收：第三条（改参只重算下游）＝ `param_change...`＋`upstream_hit...`；
  第四条（双跑逐位）＝ `repeated_renders...`＋`one_thread...`；
  第五条（空转）＝ §8 发行版数；第七条（键含 process 维）＝ `cache_isolated_across_process_versions`
  ＋ `every_key_dimension_flips_the_key`。
- `cargo xtask layers` → `OK: 29 crates, no layering violations`。
- `cargo xtask check-no-iop-names` → `OK (97 names, 4 roots clean)`。
- `Scripts/rust-apple-boundary.sh` → `ALL GREEN`（7/7，含 Linux 目标编 `lightamer-apple`）。
- `Scripts/check-licenses.sh` → `allow=852 exception=1 fail=0 total=853`，退出 0
  （与 B1-a 逐字同：rayon 1.12.0/libc 0.2.191 早在锁与审计表，无新增第三方 crate，
  `docs/LICENSE-AUDIT.md` 无需加行——`Cargo.lock` 只添依赖边，版本号不动）。
- 六条 lint：`cargo clippy --workspace --all-targets --locked --offline -j6 -- -D warnings
  -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic
  -D clippy::todo -D clippy::unimplemented` → 退出 0（0 error）。
- `cargo fmt --all --check` → 退出 0。
- 文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked --offline` → 退出 0。
- 封存面：`git diff --stat 553aff52 HEAD -- crates/lightamer-history crates/lightamer-registry
  crates/lightamer-engine apps crates/lightamer-apple 'crates/lightamer-iop-*/src/modules'` → 无输出。
- B1-a 测试零删除：11 处 `decide` 调用加 `0` 参数（见 §6），期望不动；其余全部原样绿。
- `Scripts/rust-session-demo.sh` → `demo: ALL GREEN`，退出 0（13.5s）。
- `Scripts/rust-history-demo.sh` → `demo: ALL GREEN`，退出 0（28.8s；万张粘贴 143.7ms）。
- `Scripts/rust-ci-lite.sh` → `rust-ci-lite: ALL GREEN`，退出 0（65s；测试 511 通过，
  界面重建 6s≤180s，发行版 17.8MB≤80MB，单 crate 检查 1s≤40s，`target/` 14.4GB≤20GB；
  冷构建两项 SKIP；复审修订前另有一轮 229s 全绿，数见 git 历史）。
- `docs/PIPELINE.md` 补「执行」一节＋配额/下限/分块三节同步；`crates/README.md` 四行已改
  （pipeline/iop-traits/sysmem/testkit；geom/raster 零改动行不动）。
- 提交面：20 文件全在允许路径（六 crate 内 15＋`Cargo.lock`＋`docs/PIPELINE.md`＋
  `crates/README.md`＋本报告＋复审日志；amend 后亲核 `git show --name-only`）。

## 10. 给用户看的汇报

做成了什么：管线能把一串节点真跑一遍了——同步渲染入口（给节点、模块、画面、标识、
版本号、区域、取消，拿输出画面）；缓存（同请求第二遍一次 `process` 不调，
改一个参数只重算它及下游，跨实例/跨版本/换输入全隔离）；分块执行（大内存模块自动切块，
块结果与不分块逐位相同）；预算跟着画面走（放手即还）；取消与七种分类型错误；
配额按物理内存推导（16GB 机上四管共 6.4GB，看门狗线下）；61MP 空转 27.5ms（门 200ms）。
还没做：B1-c（渲染作业接引擎作业池＋取消＋latest-wins＋演示）；roi 变体分块（非 ptp 形状
仍走不分块）；色彩变换执行（B5，当前是带起止空间名的分类型错误）；块级并行（块间串行，
行内并行已做）。

## 11. 复审的结论头

复审实例独立重跑 §9（`B1-b-review.log`，只读未改代码）：
`PASS / 2 error + 4 minor`——六 crate 测试数、全工作区 509（复审时，修订后 511）、
治理四件、六条 lint、`fmt`、文档零警告、许可证 `852/1/0/853` 全对上；
上游三条逐行对（分块执行/缓存键/内存口径，行号全准）＋附带核（递归/ fractions / piece hash）；
调用计数真探针、缓存键九维折叠点、取消/错误预算归零、`decide` 11 处加参与生产调用点、
配额手算（含 total=0 与钳制方向）全亲核。复审自报 miss 28.0ms（我方 27.5ms，1.8% 波动）。
Findings E1/E2/M1–M4 见 §12（六处全修，修订后测试/lint/总检查全重跑）。

## 12. 修订记录

- E1（`Frame` 零触发测试）：新增 `error_frame_overflow_is_typed_and_returns_bytes`
  （恒等链终点 `i32::MAX²`，`plane_bytes` 的 `×16` 上溢先于一切分配触发 `Frame`，
  断言类型＋"overflows"＋`used==0`＋`cache_len==0`）。§1「七种每种一例」至此坐实。
- E2（文档错数）：`docs/PIPELINE.md` 配额表 Preview 下限 `64 MiB` → `256 MiB`
  （`floor_for` 与同节正文皆 256，表内系从单块上限列误抄）。
- M1（报告措辞）：§1 改「＋30 测试：29 跑＋1 计时」；§9 以 pipeline 71（＋45）为准。
- M2（报告措辞）：§9 提交面改「20 文件（六 crate 内 15＋lock＋PIPELINE＋README＋报告＋日志）」。
- M3（键 position 维无用例）：`every_key_dimension_flips_the_key` 加同构双胞胎
  （同标识/同参数/同几何两节点键不同，注释写明累积链亦分隔、位置折叠钉死）。
- M4（暖缓存取消无用例）：新增 `warm_cache_cancel_keeps_cache_untouched`
  （两节点先暖缓存在位，第二趟同请求节点一处取消：探针 (1,1)、`cache_len==2`、
  `used==2048`，提交点零触达）。
修订后重跑：pipeline 71＋1ignored、全工作区 511、六条 lint 0 error、`fmt` 干净、
  `rust-ci-lite.sh` 全绿（65s，见 §9）。

## 13. 未做 / 未验

- 未做：B1-c 范围（见 §10）；roi 变体分块（`tiling.c:527-567`＋`:496-525`，形状不对仍
  `NoTiling`）；色彩变换执行（B5）；块级并行（串行，见 §4）；`max_tile_bytes` 未接入决策
  （配额有名无实，B1-b 的网格只受预算与下限约束）；`TILING_FULL_ROI` 语义（标志词汇无此位，
  B1-a 遗留）；`docs/LICENSE-AUDIT.md` 无新增行（无新第三方 crate，见 §9）。
- 未验：非 macOS 编译（`system_physical_memory` 的 `sysconf` 在 Linux 同签名，但本机单目标
  纪律禁装，未亲编；其余全是无平台代码）；64 线程以上机器的 `par_map_rows` 切分（逻辑与线程数
  无关，8 线程已验逐位）；机械盘/高负载下的空转数（门内余量大，未加测）。
- Commit：`19bdf93e`（报告与复审日志落盘提交；本行哈希 amend 进最终提交，最终提交
  与之仅差本行，哈希见 `git log --oneline -1`）。
