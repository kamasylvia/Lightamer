# B3-1b 报告：模块级对照架 + 转写 rawprepare

lane B3-1b（omp）。HEAD 起点 `cfbc3fba`（已亲核）。工作树里
`waves/VERIFY.md` 有塔台未提交的改动，未碰。上游基线一律
`release-5.7.0`（`Lightamer-rust-spike/refs/dt-master`，只读；
rawspeed 另见 §2）；行号无前缀指 `src/iop/rawprepare.c`。

## 一、对照架 `lightamer-oracle`（新 crate，Testkit）

结构：`upstream/*.inc`（15 个逐字片段，见 §2）+ `stubs/dt_shim.h`
（最小 dt 接口：用到的类型/宏/声明；布局是架内自定的，枚举**值**
抄上游并逐个注出处）+ `stubs/stubs.c`（纯接口替身，零上游逻辑）
+ `csrc/chain.c`（小管线：模块表 + 建链 `init`/`reload_defaults`/
`commit` 读快照 + `modify_roi_out` 前推 + 按链序逐个 `process`，
`pipe->dsc` 沿链演进；`output_dsc` 钩子记每模块留下的通道/类型）
+ `csrc/*_tu.c(pp)`（shim + 片段按依赖序拼成的翻译单元）
+ `csrc/rawprepare_glue.c`（参数标量 fill/read，Rust 不镜像 C 布局）
+ `src/lib.rs`（唯一 `unsafe` 边界：`#[repr(C)]` 镜像三结构体，
两边静态断言 100/20/68 字节；长度全检后调用；`OracleError` 手写）。
`build.rs` 用 `cc`（C11 + C++17，`-O2 -ffp-contract=off -fno-fast-math`）。

Rust 入口：`run_rawprepare`（事实/参数/瓦片/`rin`/`rout` → 输出瓦片 +
`StateOut{enabled,filters,xtrans,processed_maximum,p_width,p_height}`，
输入分 `U16`/`F32` 两腿）、`rawprepare_roi_out/in`、`rawprepare_defaults`。

验证：`tools/extract.sh rawprepare [--check]`（`LIGHTAMER_DT_REF` 传参考
克隆；缺席则 SKIP 退出 0；先对 blob 哈希防标签漂移，再 `sed` 行范围
重抽逐字节比）。加第二个模块六步见 crate `README.md`。

行为替身表（同 README）：cache get/release（落到工作图上，DB 写无读者）、
`DT_CONTROL_SIGNAL_RAISE`（无信号总线）、`dt_print`/trouble（静默）、
scharr（`abort`，链钉 `want_detail_mask=0`）、gtk（`abort`，widget 恒 NULL）、
glib list（同语义含 NULL）、`MIN/MAX/CLAMP`（调用点无副作用，等价）、
`DT_OMP`（串行 = 无 OpenMP 上游）、`dng_gain_maps=NULL`（ARW 无，平坦场恒关）。
跨调用的唯一指针线程局部（并行测试曾竞态 SEGV，修后连跑 5× 稳）；
自带 `shiftDcrawFilter` 弱定义（与 decode 的同 pin rawspeed 强符号并存）。

## 二、原样取了哪些行（`tools/extract.sh` 内 manifest 即清单）

`src/iop/rawprepare.c`（blob `b344b027`）：40-55 平坦场枚举 + 参数结构、
65-82 提交数据结构、195-201 `_compute_proper_crop`、253-286 roi 对、
301-320 `_adjust_xtrans_filters`+`_BL`、322-448 `process`（CPU 路）、
569-580 `_image_is_normalized`、582-622 `_image_set_rawcrops`、
624-678 `_check_gain_maps`、680-740 `commit_params`、742-751 pipe 对、
753-777 `reload_defaults`。`src/common/image.c`（`05605921`）：170-173
`dt_image_is_raw`、180-184 `dt_image_is_mono_sraw`、259-262
`dt_image_is_rawprepare_supported`。`src/imageio/imageio_rawspeed.cc`
（`7f7dabe7`）：119-127 `dt_rawspeed_crop_dcraw_filters`（C linkage，
头文件 `G_BEGIN_DECLS` 亲核）。`src/common/dng_opcode.h`（`a57d2c85`）：
26-44 增益图结构（`_check_gain_maps` 编译用，从未取数据）。
`external/rawspeed @ 0c16fee7` 的 `ColorFilterArray.cpp`（blob `f349c81a`）：
143-170 `shiftDcrawFilter`（dt 侧是子模块 gitlink，内容不在参考克隆内；
取本仓钉住的 rawspeed，与 B2-a 同 pin）。

不抽：GUI 全族、OpenCL 路（`process_cl` + global 对）、`legacy_params`
（v1 迁移；本管线起步即 v2 语义）、`distort_*`（本波无 Rust 对应）、
`output_format`（其 `dsc.rawprepare` 写在 RAW 头无读者）、
`init_presets`/`description`/`name`/`operation_tags`/`flags`/
`default_colorspace`（元数据非像素）。

## 三、转写 `rawprepare`（`crates/lightamer-iop-raw/src/modules/rawprepare/`）

- 参数（10 键 `ParamsDesc`）：`left/top/right/bottom`、`black_0..3`、
  `white`（Int）、`flat_field`（Bool）。数组取最简形：具名标量——
  `ParamType` 无列表种（`Floats`↔`Curve` 是曲线载荷专用），且
  `lightamer-iop-traits` 本波冻结。
- 缺省：缺键从 `image.raw` 取（黑/白/左/上裁切）；右/下裁切无事实
  （`RawFacts` 只带已裁框的原点，且马赛克到手已裁），缺省 0 = 不再裁；
  平坦场缺省关（无增益图事实）。无 raw 事实时全缺省中性。
- `commit`：`applies = raw.is_some() && !normalized`（`normalized` =
  HDR 且白点为 1/`0x3F800000`，`:575` 原样；非 HDR 浮点存 buffer 那半
  在 commit 不可见，见 §5）；马赛克判 `state.cfa`（= `dsc.filters`
  位），两式与 `:693-716` 同序；黑均值 `:718-724` 同序 f32 累加；
  `flat_field=true && applies` 判 `InvalidParams`（增益图未转写）。
  不适用时黑白键一律不读，存良性常量（上游算完即弃，观感同）。
  rawcrops 腿的 `p_width`/`p_height` 重写无通道（`ImageInfo` 在 commit
  不可变、`PipeState` 无该字段），对照跳过该两项（读者 crop/lens/demosaic
  皆未转写，现无可观察面）。
- `process`：f32 马赛克腿（u16 腿由精确提升覆盖，见 §4）；
  `(in-sub[id])/div[id]` 逐值同序（无 FMA、无换序），id 即 `_BL`
  （i64 算奇偶，低位与 C 同）；`csx/csy` 即 `_compute_proper_crop`
  （`iscale≡1`，本管线缓冲全分辨率）；rayon 按行并行（`par_map_rows`
  无行号，此处自写同纪律的索引版：预检 + `par_chunks_exact` 拉链；
  短尾平面判错：分块寻址需整行，见复审 M4）。
  写状态：四路最大值 1.0、CFA 按裁切移位（Bayer 四情形枚举、
  X-Trans 与 `_adjust_xtrans_filters` 同下标）。
- 不适用（`!applies`）= 输出抄输入、不碰状态（= 上游跳过禁片；
  管线内查无既有模块级约定，此即本波约定）。roi 在 `!applies` 时恒等
  （= 上游禁片不改几何）。多通道输入判 `UnsupportedFormat`（未转写腿
  永不静默走偏）；有 applies 无 CFA 同判（管线内不可达）。
- roi 对：与 `:253-286` 同式（`x=y=0`、`round((l+r)*scale)`、
  `iscale≡1`）；过裁用饱和收敛到空（上游走负宽到下游报错，
  仅垃圾输入可观察）。
- DESC 全填：flags `TILING|DISTORT`、色彩 `(Raw,Raw)`、分组 Base、
  history（`ONE_INSTANCE` → 单实例）。`output_format`/tiling/stats 全默认。
- 不做（逐条）：多通道预降采样腿（无此输入）、DNG 增益图、OpenCL、
  细节蒙版、图形界面、v1 参数迁移。

## 四、门限与最大绝对差（全逐位相等）

门：平均绝对差 < 1/65535、容差内占比 > 0.9999（`lightamer-testkit`
`compare_planes`，常量 `MEAN_ABS_GATE`/`TOLERANCE`/`IN_TOLERANCE_GATE`）。
下表 `max_abs` 全 0（`--nocapture` 实测；线性纯运算 +
`-ffp-contract=off` 两边同序，符合预期）：

| 瓦片 | mean_abs | max_abs | in_tol |
|---|---|---|---|
| 真瓦片 top-left/center/brightest/darkest（256×256，缺省参数） | 0 | 0 | 1.0 ×4 |
| 黑位/白点/超白点/四路异黑 | 0 | 0 | 1.0 ×4 |
| u16 腿（oracle 词 vs 我方浮点） | 0 | 0 | 1.0 |
| 裁切 1x0/0x1/1x1/2x3/3x2/4x4 | 0 | 0 | 1.0 ×6 |
| 用户裁切 2/4/6/8 | 0 | 0 | 1.0 |
| X-Trans + 裁切 1x2 | 0 | 0 | 1.0 |
| 改黑位/改白点 | 0 | 0 | 1.0 ×2 |

链上状态同测：四路最大值两边皆 1.0、CFA 图案经 oracle
`filters`/`xtrans` 解码后相等（含奇偶裁切移位与 X-Trans 表）、
真瓦片 oracle `enabled`（缺省即启用）。样张事实（`decode --dump`
实测）：黑 512×4、白 15360、RGGB `0x94949494`、已裁 9568×6376、
loader 左/上裁切 0（故缺省裁切全 0）。

## 五、与任务书读法不一致处（以源码为准，共 5 处）

1. `dt_rawspeed_crop_dcraw_filters` 本体是 rawspeed C++（`ColorFilterArray::shiftDcrawFilter`），
   不在 `refs/dt-master` 树内（子模块 gitlink）：连带原样取本仓 rawspeed 同 pin。
2. 非 HDR 浮点存 buffer 的归一化半（sRAW 类）：commit 见不到存类型，
   未转写（范围外；ARW 存 u16 不触发）。
3. 非归一化 HDR（白点为它值浮点位）：校验判错（上游静默截断 u16 取低位；
   范围外， loud 优先）。
4. 过裁收敛：饱和到空 roi（上游负宽；仅垃圾输入可观察）。
5. DESC 色彩静态 `(Raw,Raw)`，上游 `default_colorspace` 非 raw 回 RGB
   （`:115-120`）：现无可观察面（色彩协商尚无管线内调用者；待接线时
   非 raw 图会多一段 Raw→Rgb，届时再对）。

## 六、不稳定测试 `whole_path_counts_probe_once_decode_once`

根因：`cameras.xml` 解析是进程单例一次初始化，落在“本二进制谁先碰解码”
头上；`SERIAL` 只串行不排序，本测试首跑时 `probe()` 触发首解析，
`meta_parse_count` 增量为 1 判红（B3-1a 已见一次）。修法（仅本测试内）：
读数前先 `RawImage::ensure_metadata()` 热单例（幂等 `call_once`），再量
增量。连跑三遍全绿（见 §8）。

## 七、新增测试清单（26 个）

oracle 自测 3（合成瓦片值/u16=f32 腿/缺省）；转写单测 9（缺省解析、
显式与校验、适用判定、roi 对、像素手算、Bayer 移位、描述元数据、
短尾判错、非零原点 id）；testkit 比较 4（恒等/离群/长度错/空）；
对照集成 10（发现表 + 真瓦片四区 + 黑白点 + 超白点 + 异黑位 +
奇偶裁切 + 用户裁切 + X-Trans + 改参 + 三禁片直通/拒收）。
旧测试一个不改（`implemented_modules_resolve…` 两处因新行自动覆盖，
无断言改动）。

registry 缺口：`lightamer-registry` 全自动拼表（`MODULES` 链 +
`lookup_implemented` 链；`check-no-iop-names` 反而禁其具名），其泛型测试
`implemented_modules_resolve_and_stay_described` 已把 rawprepare 纳入；
运行该包测试为证（见 §8），零改动。
## 八、验收清单（命令与输出）

- 机器守卫：`Scripts/machine-guard.sh` → 起工 `GUARD PASS (heavy=0 free=67% …)`；
  全套前 `GUARD PASS (heavy=0 free=59% …)`。
- 全套：`cargo test --workspace --locked --no-fail-fast -j6` → exit 0，
  `passed=775 failed=0 ignored=5`（749 + 新增 26，见 §7；旧断言一行未改）。
- `raw_input` 连跑三遍：`cargo test -p lightamer-cli --test raw_input` ×3 →
  皆 `7 passed`（约 12s/遍）。
- 六 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked
  -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing
  -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic
  -D clippy::todo -D clippy::unimplemented` → exit 0（中途修掉 pedantic
  若干：`use` 提前、`usize::from` 奇偶、`&raw` 裸借用、截断/符号 expect、
  `vec!` 容量、常量断言、`dyn` 免导 trait、2 位表、位比较；见提交记录）。
- 文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`
  → exit 0。格式：`cargo fmt --all --check` → 过。
- 分层/同步/命名：`cargo xtask layers`（30 crates 无违反）、
  `check-order-sync`（97 模块 OK）、`check-no-iop-names`（97 名，4 roots clean）。
- 许可：`Scripts/check-licenses.sh` → exit 0。
- 演示：五个 `Scripts/rust-*-demo.sh` 皆 exit 0。其中 history 首跑红
  （`develop.merge` 拒 `rawprepare.p_gain`：描述表填实后的刻意严格；
  根因见 §10，修 demo 用真参数 `white` 后重跑绿）。
- `tools/extract.sh rawprepare --check`（`LIGHTAMER_DT_REF` 指向参考克隆）
  → 15 个 `OK`。
- 真瓦片 4 块 + 合成 15 块全过门，`max_abs` 全 0（见 §4）。
- `lightamer-oracle/README.md`（加模块六步、行为替身表、重抽核对）、
  `NOTICE` 与 `docs/LICENSE-AUDIT.md §16` 条目齐。
- `rawprepare` 缺席面：旧测试一个不改；`registry` 泛型测试自动覆盖新行。
- 范围：`git show --name-only HEAD`（squash 后）仅纪律路径 +
  `Scripts/rust-history-demo.sh` 一处越界（§10 说明，已获验收必需背书，
  无其它越界）。外部包零新增（`cc`/`rayon`/`serde_json` 皆锁内已有；
  `Cargo.lock` 共 11 个 `+` 行：oracle 一节 6 行 + iop-raw 依赖 5 行）。

## 九、复审（`B3-1b-review.log`，`PASS / 0 error + 8 minor`）

只读自审（`omp -p`，15 `.inc` 亲核逐字节 + `--check` 15 OK，未构建/测试；
复审日志一个字未改）。8 条 minor 全修：

- M1：`crates/README.md` 的 `lightamer-cli` 行被我误删 → 从 base 原样恢复，
  经 `diff` 逐字节一致。
- M2：`oracle_abi.h:3` 注释 `(100/20/64)` → 68（与两边静态断言一致）。
- M3：禁片腿漏列替身表 → `chain.c` 几何期禁片直通（与上游跳整片一致，
  亲核 `_skip_piece_on_tags` 语义）；表补行；集成测试加裁切禁片直通 +
  u16 禁片 `Chain(2)` 断言。
- M4：短尾 strided 平面静默丢末行 → `fits` 收紧到整行（判错不写零）+ 单测。
- M5：`rout` 非零原点零覆盖 → 加手算像素单测（`rout=(1,1,…)`）。
- M6：`p_width`/`p_height` 丢弃未披露 → §3 补句 + `StateOut` 文档软化。
- M7：DESC 色彩静态未披露 → §5 记第 5 项（无调用者，待接线再对）。
- M8：锁行数措辞 → §8 与审计 §16 改 11 个 `+` 行（oracle 6 + iop-raw 5）。

## 十、纪律外改动说明（`Scripts/rust-history-demo.sh`）

本波填实 `rawprepare` 的 `ParamsDesc.fields` 后，history 演示第 4 步红：
`develop.merge` 的选择检查（`develop.rs:447`，B13′-b2 刻意设计：已声明
字段的描述拒未知参数）不再接受 demo 沿用的假参数 `rawprepare.p_gain`。
引擎行为正确，demo 陈旧（写于无描述表时代）。根因修在 demo：
`p_gain`（float）→ 真参数 `white`（int），值 1.5/2.5/1.0/2.0/3.0/99.0 →
1/2/1/2/3/99，两处值断言跟随（`"value":3`、`"value":2`），选择项
`rawprepare.p_gain` → `rawprepare.white`。断言结构（步数/游标/标签）
零改动。`Scripts/` 不在任务书路径清单内，此处为修根因所必需的唯一越界，
列明备塔台核验。

