# B1-a REPORT — Pipeline foundation: regions, frames, module trait, geometry, tiling

结论头：B1-a 地基完成——区域/画面/预算/模块接口/几何链/格式协商/分块决策/四实例配额全部落盘，
全工作区测试由 398 涨到 460（+62），`Scripts/rust-ci-lite.sh` 全绿，复审 `PASS / 0 error + 3 minor`
（三处已修订，见 §12）。dt 取整与分块公式逐条对着上游 `master 679d594f5d` 移植，出处行号三处一致。

## 0. 起点与 HEAD

- 起始 HEAD（亲核）：`26950d71bd3ee036c3b52121f65bfa1d8caee5c9`
- 起点状态（逐条核过）：`lightamer-geom`/`lightamer-raster`/`lightamer-sysmem`/
  `lightamer-pipeline` 四空壳（各 1 个 metadata 测试）；`lightamer-iop-traits` 只有
  `ModuleDesc` 系描述（2 测试）；`lightamer-history` 只读未动（本波结束 `git diff`
  验证零改动）；全工作区基线 398 passed（命令见 §9）。
- 构建前守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=73% swap=?M disk=?GB)`。
- 续做 lane B1-a-r（复审三处 minor 收尾）：沿用 `tiling.rs` 未提交的 `SHRINK_BRANCH` 改动；
  本 lane 构建前守卫重跑 → `GUARD PASS (heavy=0 free=70% swap=?M disk=?GB)`。
- 全程并行度 `-j6`，无 `caffeinate`，无 Swift 构建，无图形程序。

## 1. 模块接口（`lightamer-iop-traits`，+13 测试）

`IopModule: Send + Sync`，对象安全：只有 `&self` 方法，无泛型、无关联类型，
`Vec<Arc<dyn IopModule>>` 装得下各种模块（测试
`two_different_modules_share_one_dyn_table` 把两个不同类型的本地模块放进同一张表，
逐个 commit/roi/tiling/process 全调一遍）。

为什么和 CORE-DESIGN §1 草图不同：草图用 `Params`/`Piece` 关联类型——每个模块
自己的类型进签名，trait 就做不成 `dyn`，自动发现要的那张「动态表」无从谈起。
本波改走两条无关联类型的路：参数是历史模型存的 JSON 对象
（`&Map<String, Value>`，`{"type": "float", "value": 0.5}` 单元）；
提交结果是 `CommitData = Arc<dyn Any + Send + Sync>`（不透明、线程共享，
模块自己 downcast 转回，拿错别人的报 `Backend`）。

- 描述未填的默认值：`flags()` → 空；`colorspaces()` → `(Rgb, Rgb)`
  （本管线工作空间是线性 RGB、缓冲是 RGBA；darktable 那边
  `input/output_colorspace` 默认回落到各模块自己的 `default_colorspace`，
  `src/develop/format.c:81-93`，REQUIRED 无全局默认——我们的全局默认是
  自立的，文档里写明了）。
- `roi_out`/`roi_in` 默认恒等（`src/develop/imageop.c:108-125`）；
  `tiling` 默认调 `TilingReq::default_for`（`src/develop/tiling.c:1903-1921`）。
- `process` 签名：`(data, input: &Plane, output: &mut PlaneMut, rin, rout)`。
- 错误四种：`InvalidParams`/`RoiMismatch`/`UnsupportedFormat`/`Backend`，
  各带一句人话（`Display` + `std::error::Error`）。
- 五 helper：`get_float`/`get_int`/`get_bool`/`get_text`/`get_floats`，
  缺名/错 tag/错载荷一律 `InvalidParams`（各一测验）。
- 回调↔上游映射表见 trait 文档（`iop_api.h:97-110` 色彩、`:119-124` tiling、
  `:199` commit、`:213-243` roi 对）。

## 2. 区域（`lightamer-geom`，+10 测试）

`Roi { x, y, width, height: i32, scale: f32 }`，镜像 `dt_iop_roi_t`
（`src/develop/pixelpipe.h:36-39`）。构造器裁决（测试钉死）：
负宽高是错；零宽高是合法的空；零/负/非有限缩放是错。
运算：`intersect`/`union`（同缩放按位相等才做，否则错）、
`translate`、`to_scale`、`is_empty`、`contains`/`contains_point`、
`sub`（相对坐标，越界是错）。整数一律 checked/i64 中间量，
溢出是 `RoiError::Overflow`。

## 3. 取整规则（对 darktable 源码逐条）

| # | 规则 | 我方落点 | 上游出处（已打开核过） | 上游原文 |
|---|---|---|---|---|
| R1 | 原点向零截断 | `to_scale` 的 x/y | `src/iop/finalscale.c:103-104` | `roi_in->x /= roi_out->scale;`（`int /= float`，C 截断） |
| R2 | 范围 `ceil` | `to_scale` 的 w/h | `src/iop/finalscale.c:124-127` | `MAX(16, MIN(ceilf(roi_out->width / roi_out->scale), piece->buf_in.width))` |
| R3 | 递归入口同 R1 | 同 R1 | `src/develop/pixelpipe_hb.c:2480-2481` | `roi_in.x /= roi_out->scale;` |
| R4 | 裁剪偏移截断+钳 | 文档（本波无 crop 模块，FakeCrop 只仿形状） | `src/iop/crop.c:587-594` | `roi_in->x += iw * d->cx;` 后 `CLAMP(..., 0, (int)floorf(iw))` |
| R5 | 默认 roi 对恒等 | trait 默认方法 | `src/develop/imageop.c:108-125` | `_iop_modify_roi_in/out` 都是 `*dst = *src` |
| R6 | 分块远边保护 | 分块决策（非 `to_scale`） | `src/iop/finalscale.c:133-141` | `x_end = ceilf((roi_out->x + roi_out->width) / roi_out->scale)` |
| R7 | 收缩 `floor` | `settle_tile_size` | `src/develop/tiling.c:629-646` | `width = floorf(width * scale)` 三分支 |
| R8 | 宽高向下贴对齐 | 同上 | `src/develop/tiling.c:670-671` | `width = (width / align) * align`（仅真切分） |
| R9 | 重叠向上贴对齐 | 同上 | `src/develop/tiling.c:674-675` | `overlap % align != 0 ? (overlap / align + 1) * align : overlap` |
| R10 | 块数 `ceil` | `decide` | `src/develop/tiling.c:682-683` | `ceilf(roi_in->width / (float)tile_wd)` |

## 4. 画面与预算（`lightamer-raster` +8，`lightamer-sysmem` +4）

- `Frame` = `Vec<f32>` + `FrameExtent`（整数矩形，无缩放——缓冲位置不需要）
  + `PixelFormat`。`alloc` 只接受 `RgbaF32Premul`（16 B/px）；`RgbaU8`/`RgbaU16`
  有名无实（`is_allocatable() == false`，分配报 `UnsupportedFormat`）。
- 尺寸在 u64 里算，`width * height * 4` 上溢或超 `isize::MAX` 报 `TooLarge`
  （`u32::MAX²` 画面实测报 `TooLarge`，无 abort）。
- `rows_mut(y0, y1)` 返回连续区间，测试用 `split_at_mut` 切成两半各写各的，
  逐行断言互不影响；`view`/`view_mut` 越界报 `OutOfBounds`
  （`row(8)`/`view` 探出帧各一测验）；`copy_from` 形状/格式不对报
  `ShapeMismatch`。全经 `.get()`，零下标。
- `Budget::acquire` 超限报 `BudgetError`（含已用/剩余/上限三数），
  `Grant` 是借用式 RAII（drop 归还，`saturating_sub` 防欠流），
  `used`/`remaining` 经 `Mutex` 可问；8 线程 × 50 次抢 10 字节测试收尾为零。
- 配对住管线层（`budgeted::alloc_frame`）：先扣款后分配，分配失败 grant
  已 drop，字节回去（`RgbaU8` 分配失败后 `used == 0` 钉死）。
  画面与预算分处两个 L0 crate、同层无链，这是唯一合法的配对位置。

## 5. 分块（`lightamer-pipeline::tiling`，8 测试，手算在注释里）

`TilingReq` 镜像 `dt_develop_tiling_t`（`src/develop/tiling.h:25-41`），
`factor_cl`/`maxbuf_cl` 填了不用。`default_for` 照
`default_tiling_callback`（`:1903-1921`）：`factor = 1 + 输出面积/输入面积`。
两处写明的偏离：空输入给 2（上游除零得 inf）；`TILING_FULL_ROI` 的
overlap-4 分支暂无对应（标志词汇无此位）。

`decide` 照 `_default_process_tiling_ptp`（`:571-822`）移植，
八步与报告 `docs/PIPELINE.md` 同文：吻合检查（`:1923-1933`）→
无增益门 factor<2.2（`:599-610`）→ 可用=预算−两整帧−开销（`:613-615`）→
收缩（`:629-646`）→ 方形（`:652-658`，ptp 不贴对齐）→ 对齐（`:670-675`）→
步长/块数（`:678-683`）→ 超 10000 块放弃（`:81-84` 默认档）→
逐块钳帧/跳窄末块（`:733`）/好块只裁前侧（`:780-790`）。
分发按位相等（`:1176`，含缩放位）；形状对不上答 `NoTiling`
（roi 变体路 `:527-567`+`:496-525` 随 B1-b）；
`singlebuffer` 不取 `dt_get_singlebuffer_mem()` 下限（B1-a 无全局配置，
零预算退化成放弃一路，测试钉死）。
收缩比跑在 f64（上游 float），同公式、更宽浮点——手算例全取二进制精确值，
两边一致（0.5/0.25/0.0625/0.75 未用；0.4/0.6 系因二进制不精确弃用，
以 0.5/0.25/0.0625 重组）。收缩分支阈值取上游字面量 `0.333f`（`:634,638`），
我方 `SHRINK_BRANCH = 0.333f32 as f64` 逐位拓宽——不是 `1.0 / 3.0`
（M1 修订；测试 `shrink_branch_matches_upstream_literal` 钉死）。

四例验收（块数/尺寸/重叠全手算，算式在测试注释里）：
不分块（吻合 + 无增益门各一断言）；1000x100 切 2 块（factor 5，
预算 7.2M，`scale=0.5`，500+500）；1000x1000 切 2x2（预算 52M，
`scale=0.25`，sqrt 双缩）；对齐 16 落格（500→496，3 块 496/496/8，
原点 0/496/992 全 ≡0 mod 16）。另三例：重叠 8 的好块裁剪
（输入 500/500/32，好块 500/492/24）；窄末块跳过（12x12 位置计 100 块，
10/11 行列跳过）；极小预算放弃。

## 6. 几何链（`lightamer-pipeline::chain`，10 测试）

调用方给执行序 `PipeNode`（标识/多实例下标/JSON 参数）+ `ModuleLookup`
（闭包与 `HashMap` 皆可）；`build_chain` 逐个 commit（未知标识/
提交拒绝/坏区域/往返四种 `ChainError` 全带模块名）。
`forward` 从终点输出逆序推（`pixelpipe_hb.c:2575` 形），
每例 `assert_chained` 取三样：`forward` 的几何、手算的每节点应得输入、
调用方要的终点输出——逐节点断言相等 + 双向包含（两端独立推导，
非自包含），相邻恒 `geos[i].output == geos[i+1].input`，
末端输出恒等于终点；空期望只用相等 + `is_empty`
（M3 修订后形态；原「相等 + 包含」半句恒真，已按此重写）。
`backward_check` 从首个输入顺推核对（`:4026` 形），首个不合报
`Roundtrip`（expected/got 双列）。线形↔几何形在 `from_wire` 校验，
坏区域点名模块。

八例验收：恒等链（testkit 真 Identity + 1:1 假）；放大（2/1，
100→50 输入）；缩小（1/2，100→200）；裁剪(+10/+6/+20/+12)→放大→缩小
往返归位（首输入 (10,6,120,112)，反推全合）；非整数倍（3/2：
出腿 100→150 上取整，进腿 100→66 截断，反推报 `Roundtrip` 并断言报了——
有损缩放不往返是诚实行为）；空区域（终点空 + sink 报空输入各一，
sink 反推失败是预期的）；64 节点长链（32 对上下，首输入按位等于终点，
零累积）；混合链（shift/scale/shift 三段，反推全合）。
另：未知模块/提交拒绝/坏区域/长度错各一错；`multi` 透传 + 闭包 lookup 一例。

## 7. 格式协商与四实例（+3/+1 测试）

`negotiate` 顺链比对相邻首尾，异则记 `ColorStep { after, from, to }`；
全同零笔（空链/单节点亦零）；单边界有且仅有一笔；双边界两笔 from/to 全对。
`PipeKind::{Full, Export, Preview, Thumbnail}` + `quota()`：
Full/Export 4GiB/256MiB（槽 8/4），Preview 1GiB/64MiB（槽 4），
Thumbnail 512MiB/16MiB（槽 2）。**初值，B1-b 实测后再调**。

## 8. 模块发现与分层

- 核心零中央名单：`IopModule` 对象安全 + `ModuleLookup`，本波测试只用
  `mod_*`/`test_*` 假名；`cargo xtask check-no-iop-names` 全仓 97 名零命中。
- 分层：`cargo xtask layers` 通过。geom/raster/sysmem/iop-traits 四个 L0
  零工作区依赖（raster/iop-traits 各有自有的数据形状，管线在边界转换，
  见 §1/§4）；pipeline 依赖 L0 四件 + `serde_json`；testkit 依赖
  iop-traits + `serde_json`（`IdentityModule` 的 trait 实现在非测试代码里）。
- 教训：iop-traits 曾 dev-依赖 testkit 做对象安全测试，dev 环导致 cargo
  编出两份 `lightamer_iop_traits`、trait 类型分裂（E0277）——
  dev 环里传 trait 对象必死。改走两个本地模块，跨 crate 的 `dyn` 证明
  留在 pipeline 测试（Identity + fakes 同表）。
- `ImageInfo` 住 iop-traits（§1 已述理由：trait 签名要 + L0 无依赖）。

## 9. 验收（命令与输出）

基线（开工前）：`cargo test --workspace --locked -j6` → `passed total=398`
（与任务书 398 一致；守卫 `GUARD PASS (heavy=0 free=73% swap=?M disk=?GB)`）。

- 六 crate（`cargo test -p <name> --locked --offline -j6`，逐个绿）：
  `lightamer-geom` 11，`lightamer-raster` 9，`lightamer-sysmem` 5，
  `lightamer-iop-traits` 15，`lightamer-pipeline` 26，`lightamer-testkit` 6，
  另 testkit 1 个文档测试；0 failed。
- 全工作区：`cargo test --workspace --locked -j6` →
  83 个测试二进制全 `ok`，`passed=460 failed=0`（398 + 本波 62：
  geom +10、raster +8、sysmem +4、iop-traits +13、pipeline +25、testkit +2），
  1 个 ignored（`bench_paste_10k_reports_phases_for_both_sync_modes`，
  万张计时，默认不跑）。
- `cargo xtask layers` → `OK: 29 crates, no layering violations`
  （L0 四件零工作区依赖；pipeline → geom/iop-traits/raster/sysmem +
  testkit(dev)；testkit → iop-traits）。
- `cargo xtask check-no-iop-names` → `OK (97 names, 4 roots clean)`。
- `cargo xtask check-order-sync` → `OK (97 modules, fixture .../dt-order-679d594f5d.json)`。
- `cargo xtask check-i18n` → 无 `i18n` 目录（B17 才启用），无事可比。
- `cargo xtask check-apple-boundary` → `OK: 29 crates, 214 rust files,
  no Apple-boundary violations`。
- 六条 lint 全工作区：
  `cargo clippy --workspace --all-targets --locked -j6 -- -D warnings
  -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used
  -D clippy::panic -D clippy::todo -D clippy::unimplemented` → 退出 0。
- `cargo fmt --all --check` → 退出 0。
- 文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`
  → 退出 0（中途修过 pipeline lib.rs 三处冗余/歧义内链）。
- `Scripts/check-licenses.sh`（不带参数）→
  `allow=852 exception=1 fail=0 total=853`，退出 0
  （`serde_json` 已在锁与审计表，无新增第三方 crate，
  `docs/LICENSE-AUDIT.md` 无需加行）。
- 封存面：`git diff --stat 26950d71 HEAD -- crates/lightamer-history
  crates/lightamer-registry crates/lightamer-engine apps crates/lightamer-apple
  'crates/lightamer-iop-*/src/modules'` → 无输出。
- 取整/分块出处：§3 表 R1–R10，代码注释 + `docs/PIPELINE.md` + 本报告
  三处一致；上游片段逐条打开核过（行号以 `sed -n` 实读为准）。
- 对象安全：`iop-traits::module::tests::two_different_modules_share_one_dyn_table`
  （`Vec<Arc<dyn IopModule>>` 装 Doubler + Zeroer，commit/roi/tiling/process
  全调一遍，各自输出 3.0/0.0）。
- `docs/PIPELINE.md` 八节齐（区域/取整单列/画面与预算/模块接口/几何链/
  格式协商/分块/四实例/测试模块）；`crates/README.md` 六行已改。
- `Scripts/rust-session-demo.sh` → `demo: ALL GREEN`，退出 0（22.6s）。
- `Scripts/rust-history-demo.sh` → `demo: ALL GREEN`，退出 0
  （万张粘贴中位数 143.2ms，门 1000ms）。
- `Scripts/rust-ci-lite.sh` → `rust-ci-lite: ALL GREEN`，退出 0
  （守卫/许可证/分层/文档/边界/构建/测试 460 通过/预算全 PASS：
  界面重建 32s≤180s，发行版 17.8MB≤80MB，单 crate 检查 7s≤40s，
  `target/` 12.8GB≤20GB；冷构建两项 SKIP）。
- `git show --name-only HEAD` → 31 文件：六 crate 目录 26 + `Cargo.lock` +
  `docs/PIPELINE.md` + `crates/README.md` + `B1-a-REPORT.md` + `B1-a-review.log`，
  全在纪律允许路径（`git show --stat` 反向 grep 零命中）。
- 残留：测试后 `git status --porcelain` 无测试临时文件；
  `/tmp/b1a-workspace-test.log`（上一实例遗留）与本 lane 的
  `/tmp/b1a-r-workspace-test.log` 均已删；系统临时目录无本波目录；
  无残留进程（`B1-a-review.log` 的复审实例只读，未留进程）。

## 10. 给用户看的汇报

做成了什么：管线地基八件——区域（含 dt 取整移植）、画面（含预算配对）、
模块接口（对象安全，可动态注册）、几何链（前推/反推八例全绿）、
格式协商（只出计划）、分块决策（与 dt ptp 路同公式，手算四例全合）、
四实例配额（初值）、恒等测试模块。
还没做：B1-b（缓存键/失效/行并行/分块执行/四实例跑通/双跑逐位/61MP 空转计时）、
B1-c（渲染作业接引擎 + 演示）。roi 变体分块、色彩变换执行、GPU 字段消费
都在后面。

## 11. 复审的结论头

复审实例独立重跑 §9（`B1-a-review.log`，只读未改代码）：
`PASS / 0 error + 3 minor`——六 crate 测试数、`passed=459`（复审时）、
五项 xtask、六条 lint、`fmt`、文档零警告、许可证 `852/1/0/853`、
两 demo 全对上；上游八条逐行对（超四条下限）全命中；
几何链八例数值断言全实、分块六例手算全合、对象安全真 `dyn` 表、
提交面 30 文件全在允许路径、封存面零输出。Findings M1/M2/M3 见 §12。

## 12. 修订记录

- M1（收缩阈值取上游字面量）：`tiling.rs` 两处比较由 `1.0 / 3.0` 改走
  `SHRINK_BRANCH = 0.333f32 as f64`（上游 `tiling.c:634,638` 的 `0.333f`
  逐位拓宽；`[0.3330000, 0.3333333)` 内两值走不同分支）。
  `sed -n '625,650p'` 亲核 634/638 两行；新增测试
  `shrink_branch_matches_upstream_literal`（`const` 断言低于 `1.0/3.0` +
  逐位相等）钉死；三处测试注释与 `docs/PIPELINE.md` 分块 §4 同改字面量。
- M2（注释行号）：`tiling.rs:build_grid` 注释 `tiling.c:729` →
  `tiling.c:727`（宽钳）/`:730`（高钳）；`sed -n '720,735p'` 亲核
  727/730 两钳位行，729 只是内层循环 `{`。报告与 PIPELINE.md 未引 729，
  不受牵连。
- M3（`assert_chained` 真验装得下）：`chain.rs` 测试 helper 改签收三样
  （`forward` 几何 + 手算每节点应得输入 + 终点输出），逐节点相等 +
  双向包含（两端独立推导，非自包含），相邻交接 + 末端终点全断言；
  空期望只用相等 + `is_empty`（`contains` 空集恒真，无信号）。
  几何链八例全改（恒等/放大/缩小/裁剪往返/非整数/空+ sink/64 长链/
  混合；长链 64 个期望由执行序手推偶喂终点、奇喂加倍），
  测试名不变；§6 措辞按改后事实重写。

## 13. 未做 / 未验

- 未做：B1-b/B1-c 范围（见 §10）；roi 变体分块（`:527-567`+`:496-525`）；
  色彩变换执行（B5）；`TILING_FULL_ROI` 语义（标志词汇无此位）；
  `singlebuffer` 全局下限（B1-a 无全局配置，配额 `max_tile_bytes` 可作下限，
  B1-b 定）；`docs/LICENSE-AUDIT.md` 无新增行（`serde_json` 已登记，
  无新第三方 crate）。
- 未验：非 macOS 编译（本机单目标，纪律禁装；全是无平台代码，
  `ImageInfo`/`Roi` 等零 `cfg`）；性能（本波无计时测试，按任务书不量）。
- 复审覆盖：复审实例跳过 `rust-history-demo.sh`（任务书允许只跑其一）
  与 `rust-ci-lite.sh`（子项已逐项单独重跑）；续做 lane 已把两项全补跑
  （§9），无遗留跳过。
