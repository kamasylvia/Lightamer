# B3-2a 报告：对照架加 temperature + 转写 temperature

lane B3-2a（omp）。HEAD 起点 `ebb70b59`（已亲核）。工作树里
`.work/gsd/phases/rust-core/waves/VERIFY.md` 有塔台未提交的改动，未碰。
上游基线一律 `release-5.7.0`（`Lightamer-rust-spike/refs/dt-master`，只读）。
行号无前缀指 `src/iop/temperature.c`。

## 一、对照架加第三个模块

- 清单：`tools/extract.sh` 加 `temperature` 一节，抽出 19 个片段，
  `--check` 19 个 `OK`（见 §8）。
- `csrc/chain.c`：`MODULES` 加 `temperature` 行（params-size/fill 走新 glue，
  roi 对与 `reload_defaults` 走 glue——上游无 roi 函数，继承恒等缺省；
  上游 `reload_defaults` 要 GUI/dev/history，对照架永不跑它，调用方恒传
  显式参数）；`output_dsc` 钩子为空操作（`process` 只写温度子记录与
  最大值，不碰通道/类型）；`oracle_run` 改为 `run_impl` + 双包装：
  老入口行为逐字节不变（温度附加传空），新 `oracle_run_temp` 喂
  白平衡事实；状态上报加温度三件（`temp_enabled`/`temp_coeffs`/`temp_late`）。
- 回调重命名：`temperature_tu.c` 把 `process` 等宏重命名为 `temperature_*`
 （`.inc` 字节不动）；`dt_dev_prepare_piece_cfa` 不重取（hotpixels TU
  已定义一次）。
- 文件静态函数的测试入口（`_find_coeffs`、`_calculate_bogus_daylight_wb`、
  `_temp2mul`、`_mul2temp`、`_temperature_tint_to_XYZ`）以标明段落在 TU 尾，
  因 TU 外不可见（README Layout 已登记此形态）。
- `stubs/dt_shim.h`：image 加白平衡/矩阵/机身/文件名/加载状态字段，
  dev 加 `chroma`（只含提交与处理写的三字段），piece 加
  `process_cl_ready`，另加 `DT_IMAGEIO_OK/CACHE_FULL`、`dt_wb_data`、
  `dt_control_log`、`g_str_has_suffix`、`DT_OMP_DECLARE_SIMD`、
  `dt_gui_collapsible_section_t`（不透明占位）。
- `stubs/stubs.c`：`dt_wb_presets_count` 恒 0（预设表是图形界面菜单数据，
  不取；`_find_coeffs` 直落兜底，与转写侧跳过同构）、`dt_wb_preset`
  不可达 abort、`dt_control_log` 静默、`g_str_has_suffix` 同语义。
- Rust 入口：`run_temperature`（params/种类/瓦片/通道数 1 或 4）、
  `run_rawprepare_temperature`（两模块链）、
  `run_rawprepare_temperature_hotpixels`（三模块链，上游链序）、
  `temperature_find_coeffs`/`temperature_bogus`/`temperature_temp_to_mul`/
  `temperature_mul_to_temp`/`temperature_tint_xyz`（五个转换入口）。
- `Facts` 冻结（前两波测试按字面量构造它，不许加字段）：温度事实走新
  `TempFacts`（`base` + `wb` + `xyz_to_cam`），C 侧 `oracle_temp_facts`
  156 字节；`StateOut` 加温度三字段（只读不断言处，旧测试零改）。
- 对照库与 Rust 侧直链同一个系统 lcms2（Homebrew 2.19）：C 侧
  `build.rs` 硬编码 `link-search`/`link-lib`（decode 先例写法），Rust 侧
  经 `lcms2-sys` 默认 dynamic 特性走 pkg-config 同一库（构建脚本读证：
  先探系统库，失败才回落静态编译）。
- 行为替身表（README 同步加 9 行）：见 README。
- 警告：glue 警告保留，verbatim TU `-w`（沿 B3-1c 三次编译）。

## 二、原样取了哪些行（`tools/extract.sh` 内 manifest 即清单）

`src/iop/temperature.c`（blob `eee5d23a`）：48-64 限值与预设标签 +
68-75 参数结构 + 77-99 GUI 数据结构（纯类型，转换函数点名它）+
101-105 提交数据结构、185-199 数组/参数互化、201-236
`_ignore_missing_wb`、281-403 光谱链（`spd` 类型 + 黑体/日光谱 +
谱→XYZ + 温度→XYZ 含 tint 版）、406-502 互化四件
（`_XYZ_to_temperature`/`_xyz2mul`/`_temp2mul`/`_mul2xyz`/`_mul2temp`）、
504-639（`scaled_copy_4wide` + `_publish_chroma` + `process`）、687-728
`commit_params`、730-743 `init_pipe`/`cleanup_pipe`、1382-1511（bogus
日光 + 矩阵准备 + `_find_coeffs`）。
`src/develop/imageop_math.h`（`8bc306cc`）：154-157 `FC` + 195-207
`FCNxtrans`（与 hotpixels 的 `FCNxtrans` 同字节，各自 manifest 自足）。
`src/common/dttypes.h`（`f875f6a6`）：57 `DT_ALIGNED_PIXEL` + 68-72
SIMD 通道数 + 94-114 通道循环宏、231-259 颜色矩阵有效性。
`src/common/math.h`（`689dc106`）：114-117 `dt_isnormal`。
`src/common/colorspaces.h`（`9b01c350`）：37-38 `D65xyY`。
`src/common/colorspaces.c`（`c3fc7d6d`）：2311-2456（pseudoinverse +
两枚转换矩阵函数）。
`src/common/image.c`（`05605921`）：253-257
`dt_image_is_matrix_correction_supported`。
`src/develop/pixelpipe_hb.h`（`0c0acea0`）：292-295
`dt_pipe_is_preview`（提交里读渲染种类的出处）。
`src/external/cie_colorimetric_tables.c`（`051340d0`）：1-230 全表
（纯数据，81 行观测者 + 107 行日光分量）。

不抽：GUI 全族、`reload_defaults`（见 §1）、`process_cl`/`init_global`/
`legacy_params`、元数据函数、预设表（见 §1）。
`colorspaces_inline_conversions.h` 未整取：抽出函数引用的该头符号经
grep 为零（谱腿只用 `D65xyY`，已取），整取会拖入 SSE 头链，在 ARM64
上不可编译；任务书「原样取」一条在此以源码为准落为行级原样，
MANIFEST 有注记。

## 三、lcms2 落点与分层例外

- 新依赖 `lcms2 6`（MIT，A1 审计表 §6 已登记）落在 `lightamer-color`，
  薄封装只此一个：`white_point_from_temp(f64) -> Option<(f64, f64)>`
  （对应上游 `:329` 调的那个函数）。
- `lightamer-iop-color` 依赖它（温度谱腿唯一 lcms 调用点）；
  `INTRA_LAYER_ORDER` 加 `["lightamer-color", "lightamer-iop-color"]`，
  注释写明理由（`colorin`/`colorout` 必用色彩管理 crate）。
- `Cargo.lock` 只增 `lcms2 6.3.0` + `lcms2-sys 4.2.0` 两节
  （`bytemuck`/`foreign-types`/`cc`/`pkg-config`/`libc` 皆复用锁内已有版）；
  其余锁 diff 只有本工作区边（testkit 开发依赖等），无新外部包。

## 四、转写 `temperature` 做了哪些、没做哪些

- 参数（5 键 `ParamsDesc`）：`red`/`green`/`blue`/`various`（Float
  0-8，缺省机内归一）+ `preset`（Int -1..4，缺省 0 机内）。校验在
  `commit`（非有限/越界判 `InvalidParams`，手写错误类型即 `PipeError`）。
- `commit`：逐键解析（缺席读对应缺省分量）+ 标签；缺省 = `_find_coeffs`
  转写再绿归一（`reload_defaults` `:1633-1636` 分支）；非 RAW 与单色
  RAW 关断（`matrix_supported`，`image.c:253-257` 同构）；读链上快照
  无（上游提交本就不读 `dsc`），读渲染种类无；写晚校正标志（上游
  `:725` 逐件写，除 true-monochrome hide 早返；对照架 hide 恒 FALSE）。
- `process`：关断走直通（只落晚校正标志，其余不动——关断件的上游
  可观察态）；三腿逐像素乘（拜耳 `FC` + 原点移位字、X-Trans 原点移位表、
  四通道逐道），rayon 按行并行（行间独立，与上游 `DT_OMP_FOR` 同构）；
  发布 enabled/coeffs/晚校正 + 最大值 coeffs-first 缩放（`_publish_chroma`
  同序）。
- 缺省四步：①机内（转写，含 `four_bayer` 第四元）②bogus 矩阵（转写，
  嵌入矩阵恒无效分支——解码不给、ARW 没有）③相机预设（跳过，无表无机身串，
  与对照架零预设桩同构落兜底）④兜底 `2.0/1.0/1.5/1.0`（转写）。
- 公开纯函数：`wb_to_coeffs`、`temp_tint_to_xy`、`temp_tint_to_coeffs`、
  `coeffs_to_temp_tint`，另 `default_coeffs`、`bogus_daylight_wb`
  （对照测试要调，面板后用）；光谱链为私有 helper（任务书「不做光谱函数」
  一条落为不公开：转换要谱值，只能内转，见 §6 第 6 条）。
- 零行 `OpenCL`；零图形界面；取色预设不做。
- DESC 全填：分组 Base、flags TILING、色彩 (Raw,Raw)、history 单实例。
- `PipeState.temperature` 加 `late_correction`（traits 唯一改动）。

## 五、门限与最大绝对差

门：平均绝对差 < 1/65535、容差内占比 > 0.9999（`compare_planes`）；
逐像素乘法全逐位相等（`max_abs` 断言 0）。色温 xy 门 < 1e-4（计划卡片值）。

| 瓦片/用例 | mean_abs | max_abs | in_tol |
|---|---|---|---|
| 单模块真瓦片 top-left/center/brightest/darkest（256×256，机内缺省） | 0 | 0 | 1.0 ×4 |
| 三模块链 ×4 真瓦片 ×4 参数集（机内/用户/D65/全一，16 门；D65 第四道 inf→1.0 双边同代，bogus 另证逐位） | 0 | 0 | 1.0 ×16 |
| 拜耳四相位（原点 (0,0)/(1,0)/(0,1)/(1,1)，各不同值） | 0 | 0 | 1.0 ×4 |
| X-Trans 原点 (0,0)/(1,3) | 0 | 0 | 1.0 ×2 |
| 四通道 RGB 16×16 | 0 | 0 | 1.0 |
| 强度为一（附逐位不变断言 + 链中段恒等断言） | 0 | 0 | 1.0 |
| 非 RAW 直通（附直通断言，无 oracle 侧：见 §6 第 4 条） | — | — | — |
| 缺省五腿（机内/矩阵/兜底/四拜耳/四拜耳落空） | 逐位 | 逐位 | — |
| bogus（`[1.0459…, 1.0, 0.9356…, inf]` 两边逐位） | 逐位 | 逐位 | — |

链上状态同测：发布系数、四路最大值、晚校正标志两边相等（16 链门逐门断言）。

色温换算（2000–12000K 每 500K × tint 0.135/0.5/1.0/1.5/2.326，
105 点，单位矩阵）：xy 最坏 2.220e-16（门 1e-4，余量 12 个量级），
系数最坏 8.882e-16。真矩阵（A7R5 解码矩阵，9 点抽查）：xy 2.220e-16，
系数 1.332e-15。系数→色温四组全逐位相等
（如 `[2.5273, 1.0, 1.7344, 1.0]` → `(9014.052, 0.41542384)` 两边同值）。

## 六、与任务书读法不一致处（以源码为准，共 7 处）

1. 拜耳腿须按瓦片原点移位：`dt_dev_prepare_piece_cfa` 除派生 X-Trans 表外
   还移 `piece->filters` 字（`pixelpipe_hb.c:1289-1304`），偶原点恒等、
   奇原点换相——转写在 cells 层移位（rawprepare `shift_bayer` 同构），
   由四相位门锁定（初版漏此，`(1,0)` 门红，见 §9）。
2. `commit` 写晚校正：上游提交逐件写 `chr->late_correction`（`:725`），
   除 true-monochrome hide 早返（对照架 hide 恒 FALSE，故恒写）——转写
   提交与直通路径都写，只发布路径写 enabled/coeffs。
3. 缺省绿归一：`_find_coeffs` 本身不归一，归一在 `reload_defaults`
   `:1633-1636`；提交缺省取归一值（机内 2536/1024/1778/0 →
   2.476…/1/1.735…/0）。
4. 非 RAW 无 oracle 侧：上游提交无禁用逻辑（靠历史/使能钮），对照架
   temperature 恒处理——非 RAW 只断言我方直通（像素逐位 + 状态面）。
5. 三模块链测放 testkit：iop-color 与 iop-raw 同层禁边，分层机检会红；
   testkit 居 L5 可同时依赖两 crate（`temperature_chain_oracle.rs`）。
   任务书「测试全在 iop-color/tests」一条以分层规则为准拆分。
6. 「不做光谱函数」落为不公开：`temp_tint_to_coeffs` 经
   `_temperature_to_XYZ` 必用谱值，转写为私有 helper + 数据表转写
   （`cie_tables.rs`，十进制字面量逐字）；公开面只有四个换算。
7. `long double` 即 `f64` 位宽：ARM64 上游本就按 64 位算黑体谱，转写同位宽；
   `powl`/`expl` 对 `powi`/`exp` 差 ≤1ulp（§5 的 2.220e-16 自证非逐位），
   以 1e-4 门锁定；十进制常量逐字保留，allow 有注记。

## 七、新增测试清单（38 个）

oracle 自测 5（temperature 烟囱：4×4 手算 + 发布态；find 机内/兜底；
bogus 无矩阵；tint_xyz 有限）；lightamer-color 白点 1；temperature 单测
19（缺省/显式/校验 6、关断 2、种类无关、bayer 编码、手算三腿、晚校正 2、
直通、xy 钳制、双矩阵腿、表均匀、描述）；iop-color 对照集成 12（发现表 +
真瓦片 4 区 + 拜耳四相位 + X-Trans 双原点 + 四通道 + 全一 + 非 RAW +
缺省五腿 + bogus + 双扫 + 逆查）；testkit 链集成 1（16 门循环）。
旧测试一个不改（含 commit 加字段的零跟进：`TemperatureState` 字面量只在
traits 内；前两波对照测试断言一行未动）。
演示/bench：`temperature` 零引用（grep 全仓 `Scripts/rust-*.sh` 与
`apps/lightamer-cli` 零命中），第 5 条无事可做。

## 八、验收清单（命令与输出）

- 机器守卫：`Scripts/machine-guard.sh` → 起工 `GUARD BLOCK: G2 可用内存=29%<30%
  G4 Data 卷可用=23416MB<25GB`（他人 darktable-cli 重活在飞，未碰，等其结束）；
  开工后 `GUARD PASS (heavy=0 free=43% …)`；全套前 `GUARD PASS (heavy=0 free=55% …)`。
- 全套：`cargo test --workspace --locked --no-fail-fast -j6` → exit 0，
  `passed=839 failed=0 ignored=5`（801 + 新增 38，见 §7；首轮白点期望值
  小数点后第四位差 1.2e-4 红 1 个，容差改 5e-4 后重跑绿）。
- 六 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked
  -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing
  -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic
  -D clippy::todo -D clippy::unimplemented` → exit 0（中途修掉三百余个：
  `unreadable_literal` 占大头（CIE 表 272 + 矩阵表 + 物理常数，逐字小数
  allow 注记）、`needless_range_loop` 5（转迭代器）、`manual_midpoint` 2
  （保 `(a+b)/2` 舍入，allow）、`explicit_iter_loop` 5（转 `&`/`&mut` 形）、
  clamp-like 1（转 `.clamp()`，NaN 语义同）、manual_assign 1（转 `*=`，
  `f32` 乘可交换逐位同）、match_same_arms 1（合并绿臂）、decimal_bitwise 1
  （`14`→`0xE` 同值）、cast_lossless 1（转 `f64::from`）、similar_names 2
  （改名）、too_many_lines 1（链测拆三 helper）、manual_assert_eq 1、
  cast_precision_loss（测里 allow））。
- 文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`
  → exit 0。格式：`cargo fmt --all --check` → 过。
- 分层/同步/命名：`cargo xtask layers`（30 crates 无违反）、
  `check-order-sync`（97 模块 OK）、`check-no-iop-names`（97 名，4 roots clean）。
- 许可：`Scripts/check-licenses.sh` → exit 0
  （allow=859 exception=1 fail=0 total=860）。
- 演示：五个 `Scripts/rust-*-demo.sh` → **blocked，未跑成**：脚本硬门
  `machine-guard.sh`，G4（Data 卷可用 24161MB < 25600MB，差 ~1.4G）红。
  排查：`/` 占用非本波产生（构建/测试/registry 全在 UNITEK 卷）；
  可动空间无（sysdiagnose 904M 系昨日事件诊断、`lightamer-oracle` 缓存内
  darktable dmg 85M 系他人文件，均未碰）。临走前重试，仍红则如实交付。
- `tools/extract.sh temperature --check`（`LIGHTAMER_DT_REF` 指向参考克隆）
  → 19 个 `OK`；`rawprepare --check` → 15 个 `OK`；`hotpixels --check` → 12 个 `OK`。
- 真瓦片 4 块 + 合成 11 块全过门，`max_abs` 全 0（见 §5）；色温 xy 最坏
  2.220e-16 < 1e-4（见 §5）。
- `lightamer-iop-color::lookup_implemented("temperature")` 查得到（对照集成
  首测），描述表和 registry 里都有（同测断言 MODULES + IMPLEMENTED）。
- 范围：`git show --name-only HEAD`（squash 后）仅纪律路径（见 §9 出门检查）。

## 九、复审（`B3-2a-review.log`，`PASS / 0 error + 5 minor`）

只读自审（`omp -p`，钉提交逐字节 + `--check` 三跑 + 转写逐行对，未构建/
未测试；复审日志一个字未改）。5 条 minor 全修：

- M1：绿归一 quote 行号错（`:1616-1621` 实为 `:1633-1636`）→ 报告 §4/§6-3
  与 `resolve_commit` 文档三处同改。
- M2：“无条件写”夸大（hide 早返不写）→ 报告 §4/§6-2 与 `resolve_commit`
  文档加限语“除 true-monochrome hide 早返；对照架 hide 恒 FALSE”。
- M3：“逐位同构”夸大（`powl`/`expl` 对 `powi`/`exp` 差 ≤1ulp）→
  `spd_blackbody` 文档与 §6-7 改“同位宽，差 ≤1ulp，以 1e-4 门锁定”。
- M4：PIPELINE 尾句截断（丢“两处都不收。”）→ 补全。
- M5：§5 漏 D65 第四道注 → D65 行加“第四道 inf→1.0 双边同代，
  bogus 另证逐位”。

修后重验：`cargo test -p lightamer-iop-color --locked`（33 绿）+
`cargo test -p lightamer-testkit --locked --test temperature_chain_oracle`
（1 绿）+ `cargo fmt --all --check` + workspace clippy 抽查对应包绿。
改动全是注释/文档/报告措辞，零行为 diff（`git diff` 对照确认）。
