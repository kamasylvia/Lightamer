# B1d-a Report — Whole-Chain Row-Band Streaming, Pipeline Side

## 结论头

- 整链行带流式（管线这一侧）已交付：`render_stream` 新入口、条带/方块双模式规划与执行、输出落盘、`StatsNeeds` 声明，28 个新测试 + 1 个默认不跑计时，全绿。
- 全工作区 clippy（含六条不崩溃 lint + perf）、rustdoc、xtask、边界脚本、许可证检查全绿；`render` 函数体零改动。
- 200MP 计时门内一次通过（条带 66MB / 方块 1006MB，复审独立复现一致）；ci-lite 全绿（644 通过）；
  三个演示全绿（history 首跑 load 12.25 测不准，重跑 load 8.90 通过）。复审 PASS，见下。

## 起点

- 起始 HEAD `1535a9e2`（亲核：`git rev-parse HEAD`）。
- 守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=55% swap=?M disk=?GB)`，构建前跑过。
- 基线：HYG-1 收口 616 测试（`VERIFY.md`），另 3 个默认不跑的计时测试。

## 续做：盘上的半成品哪些完整、哪些半截、你补了什么

上一实例（2026-11-28 02:47 被代理 TLS 握手失败打断，第 32 分钟）留下未提交改动，
一次没编译过。我逐文件核过：

完整（对的接着用，只修门）：

- `crates/lightamer-iop-traits/src/stats.rs`（258 行）：`StatsNeeds` 三态 +
  `check_overlap_covers` + 4 测试；`module.rs` 的 `stats()` 默认方法。一次过。
- `crates/lightamer-pipeline/src/stream.rs`（1750 行）：`plan_stream` 纯规划器、
  `render_stream` 执行器、缓冲复用、取消语义 + 17 测试。逻辑完整，一次过。
- `crates/lightamer-pipeline/src/spill.rs`（520 行）：`StreamSink` 拼装 + 内存映射
  落盘 + 6 测试。一次过。
- `fakes.rs` +353 行：`FakeBlur`/`FakeSpin`/`FakeWhole`/`FakeProxy`/`FakeGrow`
  五个假模块。一次过。
- `render.rs`：`StreamRefused`/`Spill` 两种新错误 + `stream_alloc`/`set_last_trace` +
  三处可见性放开；`render` 函数体零改动（diff 无删行，逐 hunk 核过）。

半截（缺的补上）：

- 200MP 默认不跑的计时测试：完全没有。我补了
  `stream_200mp_reports_strip_and_block_peaks`（条带+方块串行一轮，见下）。
- 取消+落盘组合测试：没有。我补了 `cancelled_run_leaves_no_spill_residue`。
- `docs/PIPELINE.md`「行带流式」节、`NOTICE` 的 Lumen 登记：都没写。我补了，
  另加 `crates/README.md` 两行。
- clippy 门：上一实例没跑过，留 9 处（`run_stream_piece` 超 100 行 1 处 +
  测试里浮点 `==`/`as` 转换 8 处，其中 1 处是我新测试抄的）。我拆出
  `emit_stream_piece`、测试改 `to_bits`/`try_from`/`#[expect]`，全绿。
- `FakeBlur` 文档一句「200MP 测试照此求和顺序解析复现」是空话（常量源下模糊恒精确，
  无需复现顺序）：改写成实际语义。

## 两种模式：规划与执行

- **条带**：链上每个模块 `overlap` 全零且不改几何 → 整宽带，每带 64 行
  （`STRIP_ROWS`，Lumen `lumen/large_image.py:10`），最后一条取余数。
- **方块**：任一 `overlap > 0` → 方块。边长
  `sqrt(预算 × 0.25 ÷ 每像素字节数) − 2 × 余量`，钳 512 到 8192
  （Lumen `block_size`，`lumen/large_image.py:143-148`，逐字核过）。
- 规划器 `plan_stream` 是纯函数：输入几何链/各模块影响范围/预算/帧尺寸/每像素字节数，
  输出模式 + 带/块列表 + 每块要读的输入区（输出区经 `forward` 反推 → 与输出区取并 →
  按余量放大 → 钳到帧内）。惰性迭代，不为大帧建表。
- 执行 `render_stream`：与 `render` 同样的 `RenderRequest` + 接收者（每块的位置/大小/画面）。
  次序：提交 → 前推几何 → 反推核对 → 格式协商（有变换步骤即 `ColorGap`）→
  准入与规划（拒绝在任何分配前）→ 逐块：查取消 → 取输入 → 整链跑过一对复用缓冲 →
  裁好块交接收者。无整帧足迹预检（来流式就是因为整帧放不下）；每步分配照旧走预算。
- 空链逐带拷贝；单节点与头节点无输入（空平面喂首节点）都有测试钉住。

## 余量怎样累加

- 余量 = 链上各模块分块请求 `overlap` 的和（`u32` 逐个 `saturating_add`）。
- Lumen 另加的富余：**有**，`spatial_margin` 在非零余量上 `+ 4`
  （`lumen/engine.py:922`，亲核）。**我们不带**：上游的余量是每个工具的手估公式，
  +4 盖估计误差；我们的余量是模块声明的精确值，且有 `check_overlap_covers` 看着，
  自加富余只会把块切小。任务书处方本就是纯累加。
- 余量再大也不拒绝：放大饱和后钳到帧（巨余量测试钉住：边长落 512，输入区钳成整帧）。

## 逐位相同是怎样保证和证明的

- 保证：每带/每块把输入区按余量放大后跑完整条链，只交出属于自己的内层部分
  （Lumen `process_region`，`lumen/engine.py:1342`）。`process` 是纯函数，同输入同输出。
- 证明（三例整帧对流式逐字节比）：条带（恒等+增益，200×150）、方块（含重叠 8 的
  真模糊，640×640 切 2×2 块）、混合五节点链（256×256）。另有双跑逐位、
  绝对坐标假模块（`FakePosition`，证块在终坐标系渲染非草稿坐标）、200MP 常量断言。
- 撒谎的影响范围两档拦：声明自相矛盾（增长 8 声称 0）被 `check_overlap_covers` 拒；
  声明自洽但 `process` 偷读块外（真读 8 声称 0）被逐位测试拦（条带边界出缝，
  `assert_ne` 钉住）。测试注释写明了两种撒谎的形状。

## 落盘和它的上限

- `StreamSink`（可选助手）：跑之前备好。输出 ≤ 内存阈值进内存；超了落匿名内存映射
  临时文件（Lumen `allocate`，`lumen/large_image.py:23-36`），drop 即删，
  完成/取消/出错都不留。目录调用方可指定，不指定走系统临时目录。
- 字节上限调用方传：超了在跑之前就分类型拒绝（`Spill`）。零长输出恒进内存
  （零长映射在部分平台直接拒绝）。
- 测试：内存拼装（乱序到达）、落盘拼装（四象限读回逐值对）、字节上限拒、
  未完成拒（目录空）、块越界错、流式进落盘对整帧逐字节等、取消即删。

## 拒绝的几种情形

`StreamRefused`，都在任何分配之前，预算/缓存原样、trace 留空（入口先清空 trace，拒绝后未写；测试逐项断言）：

- 会改几何的模块：两档中心探针（16/32 方块，输入增长随区域变即拒）+ 整帧几何核对
  （输入盖不住输出、或整帧增长与探针不一致即拒）。转置/放大/缩小三例钉住。
- `StatsNeeds::WholeImage`：必须看整图，本波只立声明，拒。
- `StatsNeeds::Proxy { max_long_edge }`：代理统计随第一个要它的模块做，本波拒。
- `OverlapMismatch`：`overlap` 与自己 `roi_in` 自相矛盾，拒。

## 每像素字节数的初值和理由

- 初值 100（`STREAM_BYTES_PER_PIXEL`）。Lumen `FRAME_BYTES` 在 61MP 上实测 55–76
  取整 100（`lumen/large_image.py:134-136`）；我们的一块是两块工作画面加一块接收画面，
  约 48 字节每输入像素，100 偏保守。B1d-b 在真模块上实测后再调。

## 两亿像素的两个内存数

- 形状：20000×10000 合成（200,000,000 像素），五节点，16GB 机 Full 预算
  2,748,779,069 B + 下限 128 MiB。输入从不在内存：无源头节点逐块懒生成常量 3.0；
  接收者逐像素断言期望常量后丢弃（3.2GB 输出不拼装，否则盖过被量的门）。
- 条带（157 带）：峰值常驻 66MB（门 1GB 内）。
- 方块（32 块，边 2605）：峰值常驻 1006MB（止损线 4GB 内；另报的数）。
- 命令：`cargo test --release -p lightamer-pipeline --locked -- --ignored stream_200mp --nocapture`，
  单测内串行（并跑常驻叠加失真，B1-b2 量法坑）。跑前 load 5.21/10 核 + 守卫 PASS，
  门内一次通过，18.26 秒。

## 验收清单（命令与输出）

- `cargo test -p lightamer-pipeline --locked`：111 通过 / 3 ignored（新增 25：stream 18 含 1 默认不跑 + spill 7）。
- `cargo test -p lightamer-iop-traits --locked`：23 通过（含新增 4）。
- `cargo test -p lightamer-raster/lightamer-sysmem/lightamer-testkit --locked`：9 / 7 / 6+1，通过。
- `cargo test --workspace --locked`：644 通过（616 + 28），4 ignored（3 旧 + 200MP 新），零失败（ci-lite 内数）。
- B1 测试零删：diff 全是加行（删行仅三处可见性 `fn`→`pub(crate) fn`）；接口声明有默认方法，
  既有模块零改。
- `cargo xtask layers`：`OK: 29 crates, no layering violations.`；
  `cargo xtask check-no-iop-names`：`OK (97 names, 4 roots clean)`；
  `Scripts/rust-apple-boundary.sh`：`STEP 7/7 PASS ... ALL GREEN`；
  `Scripts/check-licenses.sh`：退出 0（bytemuck/memmap2/tempfile 三表达式全在允许清单，
  版本与审计表逐字同：1.25.2 / 0.9.12 / 3.27.0，无需审计表新行）。
- 六条不崩溃 lint 命令行口径（+ perf，非增量）：退出 0。
  `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`：退出 0。
- 历史/注册表/会话库/引擎/命令行/模块桩/Apple 零改动：`git diff --stat 1535a9e2 HEAD`
  对这些路径无输出。
- `render` 函数体零改动：diff hunk 全在它之外（import/枚举/新方法在前，可见性在后）。
- `Scripts/rust-session-demo.sh`：退出 0，ALL GREEN。
  `Scripts/rust-render-demo.sh`：退出 0，ALL GREEN。
- `Scripts/rust-history-demo.sh`：退出 0，ALL GREEN。首跑退出 1 是 `bench paste: UNRELIABLE
  (load 12.25 on 10 cpus)`（用户重活在跑；脚本把「测不准」报成失败是 B2-b 已登记毛病⑥，
  不在本波路径内，未动）；load 回落到 8.90 重跑一次通过（10k 粘贴中位数 199.9ms ≤ 1000ms 门）。
  无残留临时目录。
- `Scripts/rust-ci-lite.sh`：退出 0，ALL GREEN（574 秒；target/ 8.7GB ≤ 20GB 门）。
- `docs/PIPELINE.md` 有「行带流式」节；`NOTICE` 有 Lumen RAW 派生条（B1d-a，MIT，
  逐文件出处 + 三处有意偏离）。
- 跑后无残留：`git status --porcelain` 除他 lane 的 `.work/` 未跟踪文件外无本波临时文件；
  系统临时目录无本波残留（本波 `/tmp/b1da-*` 已删；`lightamer-ipc-spike.json` 系他 lane 文件，未碰）。
  无残留进程（复审确认仅两个 omp 会话；本 lane 退出后剩用户自己的）。
- `git show --name-only HEAD` 只含允许路径（含 REPORT + review.log）：见最终提交（哈希下）。

## 复审的结论头

`PASS / 0 error + 3 minor`（`waves/B1da-review.log`，22 分钟独立复审，待审 HEAD `586fc42c`）。
复审重跑了验收清单全部（fmt/clippy/全工作区测试/xtask 四项/边界/许可证/rustdoc/三演示/ci-lite
245 秒全绿），逐项核对 Lumen 源码行号（条带/公式/钳制/余量+4/落盘/行主序），独立复现 200MP
两数一致（66MB/1006MB，18.32 秒），确认 `render` 零改动、B1 零删、14 文件全在允许清单。
最终提交哈希：`b4e2e52531b9e432f8c76e8037cd4f202adf2345`（填哈希后还有一次 amend 并入本行，
最终值以完工消息里的哈希为准）。

## 给用户看的汇报

超过单帧上限的图，现在能在完整分辨率下渲染了：管线多了一个流式入口，
内存里一次只留一条带（64 行）或一个方块，整条链逐块流过去，结果和整帧
逐字节相同。链上全是逐点运算走条带，有空间范围走方块（块大小按预算自动算，
512 到 8192）；输出放不下内存可落磁盘文件，用完即删。会改几何、要看整图的
模块现在会明确拒绝（等各自的波）；上限仍由资源定，没有写死的像素数。
下一段（B1d-b）把引擎接上：超限自动转流式、磁盘上限做成配置、演示、
实测这台机器能到多少。

## 未做 / 未验

- 未做：无。原任务书八条、测试一节（10 条行为测试 + 1 默认不跑计时）、文档署名全做完。
  预览/缩略图实例、代理统计、几何模块的流式，按裁决本就不做。
- 未验：无。验收清单 12 条全绿（含 history 演示重跑绿）；复审 3 minor 全处置（下）。

## 修订记录（复审回注）

- minor-1（`last_trace`「原样」措辞过实）：成立。入口先清空 trace，拒绝后只是未写——
  REPORT 拒绝节改「trace 留空」；PIPELINE 不提 trace，无需改。
- minor-2（混合链逐位例只跑出 1 块）：成立。帧 256→1024（1MP，仍是小画面），块数 1→4，
  块间缝真覆盖；pipeline 测试重绿（5.40 秒），fmt/clippy 零错。
- minor-3（history 演示未绿）：环境性。按修法在 load 8.90 重跑一次，退出 0 全绿，
  bench 中位数 199.9ms。首跑失败的脚本毛病（测不准报成失败）仍归动演示脚本的波。
