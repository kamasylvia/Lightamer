# B3-1c 报告：对照架加 hotpixels + 转写 hotpixels

lane B3-1c（omp）。HEAD 起点 `d4b93c23`（已亲核）。工作树里
`.work/gsd/phases/rust-core/waves/VERIFY.md` 有塔台未提交的改动，未碰。
上游基线一律 `release-5.7.0`（`Lightamer-rust-spike/refs/dt-master`，只读）。
行号无前缀指 `src/iop/hotpixels.c`。

## 一、对照架加第二个模块

- 清单：`tools/extract.sh` 加 `hotpixels` 一节（12 行），抽出 12 个片段，
  `--check` 12 个 `OK`（见 §8）。
- `csrc/chain.c`：`MODULES` 加 `hotpixels` 行（params-size/fill 走新 glue，
  roi 对走 glue 恒等——上游 `hotpixels.c` 没有 roi 函数，继承
  `imageop.c` 的 `_iop_modify_roi_out/in` 恒等缺省，亲核 `imageop.c:85-100`）；
  `output_dsc` 钩子为空操作（`process` 从不写 `dsc`，亲核全文件无
  `dsc` 写）；`oracle_run` 尾部加 `pipe_type` 参数，建链时按调用方种类设
  `pipe->type`；处理期每个启用的 stage 在 `process` 之前调原样的
  `dt_dev_prepare_piece_cfa(&piece, &rin)`（位置同上游
  `pixelpipe_hb.c:1391`，传 `roi_in`）。
- 上游回调名跨模块冲突（每个 iop 都有 `process`）：`hotpixels_tu.c` 在逐字
  include 之前用宏重命名为 `hotpixels_process` 等（`.inc` 字节不动）。
- `stubs/dt_shim.h`：pipe 加 `type`，piece 加 `module`/`filters`/`xtrans`，
  dev 加 `gui_attached`（恒 `FALSE`），module 加 `gui_data`（恒 `NULL`）与
  `input/default_colorspace` 函数指针（chain 统一接返回 `IOP_CS_RAW` 的胶水；
  hotpixels 上游两回调恒答 RAW，rawprepare 的片段无一处读 piece CFA，
  故统一接法对 rawprepare 不可观察）；另加 `DT_IMAGE_MONOCHROME_BAYER`
  枚举值、`IOP_CS_RAW`（`colorspaces.h:45`）、`GtkToggleButton`/`GtkLabel`
  空类型（GUI 结构体编译用）、`dt_iop_image_copy_by_size` 声明（`memcpy`
  实现，见替身表）。
- `stubs/stubs.c`：`dt_iop_image_copy_by_size` = 串行 `memcpy`（上游是
  文档性拷贝 + 大缓冲并行，字节恒等）。
- Rust 入口：`run_hotpixels`（facts/params/种类/瓦片；单色 sRAW 按
  `pure_monochrome` 读 4 宽）、`run_rawprepare_hotpixels`（两模块链入口，
  几何走 `rawprepare_roi_out`，hotpixels 恒等）；`run_rawprepare` 签名不动，
  经抽出的公共 `run_chain` 跑 `PipeType::Full`（rawprepare 不读管线种类，
  行为逐字节不变）。种类在 oracle 侧自立 `PipeType`（与管线侧同名类型经
  调用点 4 臂映射；oracle 若依赖 traits 会改 `Cargo.lock`，故不依赖）。
- 行为替身表（README 同步加 3 行）：image_copy（串行 memcpy）、roi 恒等胶水、
  colorspace 全 RAW 胶水。「加第二个模块」六步按本次实战更新（重命名、
  `VERBATIM_TUS`、`PipeType`），标题改为「加另一个模块」。
- 警告清零：`build.rs` 拆三次编译——glue（chain/两份 glue/stubs）保留警告，
  verbatim TU（两模块 TU + predicates）与 `crop_tu.cpp` 加 `-w`。
  cargo 构建警告 28 → 0（基线亲测：全量重编 `grep -c warning` 0；
  机制亲证：手工编两份 TU，无 `-w` 各 8/6 警告，有 `-w` 0，4 份 glue 0）。

## 二、原样取了哪些行（`tools/extract.sh` 内 manifest 即清单）

`src/iop/hotpixels.c`（blob `ca687dd1`）：35-41 参数结构 + 43-50 GUI
数据结构（纯类型，`process:330` 点名它；逻辑零取）+ 52-61 提交数据结构、
105-158 `_process_bayer`、161-216 `_process_monochrome`、219-325
`_process_xtrans`、327-356 `process`、358-366 `reload_defaults`、368-385
`commit_params`、387-398 `init_pipe`/`cleanup_pipe`。
`src/develop/imageop_math.h`（`8bc306cc`）：195-207 `FCNxtrans`。
`src/develop/pixelpipe_hb.c`（`d6f1d1bb`）：1289-1304
`dt_dev_prepare_piece_cfa`（逐字节，未改一行）。
`src/develop/pixelpipe_hb.h`（`0c0acea0`）：272-283
`dt_pipe_is_full/thumb/export`（判渲染种类的出处；`dt_pipe_is_preview*`
等其余判定同文件 268-300，本波只用三枚）。
`src/develop/pixelpipe.h`（`e0dce537`）：41-57 `dt_dev_pixelpipe_type_t`
（EXPORT=1/FULL=2/PREVIEW=4/THUMBNAIL=8）。

不抽：GUI 全族（`gui_init`/`gui_update`/`draw`）、`name`/`description`/
`default_group`/`flags`/`default_colorspace`（元数据非像素）。

## 三、CFA 按区域派生怎么对上的

- 上游链：处理期每个 stage 先 `dt_dev_prepare_piece_cfa(piece, roi_in)`：
  `piece->xtrans[j][i] = dsc.xtrans[(j+roi.y)%6][(i+ox)%6]`，再 `process`。
  对照架同位调用（chain.c 处理循环，`&st->rin`）。
- 转写侧：bayer/单色两条腿根本不读 CFA（邻居固定 ±2/±1，上游亦然）；
  只有 X-Trans 腿读表。转写按 B3-1a 约定，以 tile 原点 `(ox,oy)` 查
  `PipeState` 的图案：`cells[((r+oy)%6)*6+((c+ox)%6)]`，经 36 元移位表 +
  同序 20 步搜索建偏移表，再逐像素读——与上游「预派生表 + tile 内
  `(r%6,c%6)` 读」逐像素同一映射（`piece[(r%6)][(c%6)] =
  dsc[((r+oy)%6)][((c+ox)%6)]`）。
- hotpixels 无 roi 函数，`rin == rout` 恒成立，故两侧都用同一原点；
  两模块链中 rawprepare 把原点归零（上下游同式），hotpixels 段两侧同为
  `(0,0)`。分块边界：邻居读取不出 `roi_out`（上游 tile 内寻址同样不出
  块，见 `_process_*` 的 `2..width-2`/`1..width-1` 界），两侧一致，不改。
- 证据：X-Trans 在原点 `(0,0)` 与 `(1,3)` 各一块逐位相等（§4）；`(1,3)`
  是强项（零位移证明不了偏移对齐）。

## 四、转写 `hotpixels` 做了哪些、没做哪些

- 参数（4 键 `ParamsDesc`）：`strength`/`threshold`（Float 0-1，缺省
  0.25/0.05）、`markfixed`/`permissive`（Bool，缺省关）。校验在 `commit`
 （非有限/越界判 `InvalidParams`，手写错误类型；沿 rawprepare 严格先例）。
- `commit` 多一个参数：渲染种类。新类型 `PipeKind` 下沉到
  `lightamer-iop-traits`（新文件 `kind.rs`；pipeline 原定义改为重导出，
  内外路径零变化；engine 仅测试桩与签名跟进，生产逻辑零改动）；
  `IopModule::commit` 尾加 `kind`,
  `build_chain` 尾加 `kind`，`Pipe::render`/`render_stream_from` 传
  `self.kind`（后者经既有 `kind()` 方法，字段跨模块私有）；全部实现与
  调用点机械跟上（fakes 20、pipeline render/stream 测试桩各 1、engine
  源码桩 3 + 集成测试桩 3、cli 桩 2、traits 桩 3 + testkit 桩 1、
  build_chain 测试调用 33、rawprepare 本体 1 + 单测调用 9 + 对照调用 2
  ——行为零改，见 §8）。
- `commit`：四值照 `:368-385` 同序算（乘数 = 强度/2，f32 除 2 精确，等同
  上游经 double 落回 float 的正确舍入值）；`markfixed` 在缩略图/导出为假；
  单色两腿按 `monochrome_bayer` / `s_raw+monochrome` 定；CFA 取建链时刻
  `PipeState` 快照（= 上游 `d->filters`，两边都是只写不读，
  `expect(dead_code)` + 单测读值）；不支持或强度 0 → `applies=false`，
  输出抄输入、不碰状态（沿 rawprepare 约定）。
- `process`：先整块拷贝，再三腿。bayer/mono 逐行转写（`mid`、`TESTONE`
  四邻居同序、`count>=min`、`maxin` 初值 0.0 + 严格大于）；`markfixed`
  的有符号游标改无符号同序写法（bayer 步 2 起 2，mono 步 1 起 1，xtrans
  步 1 起 2 + 同色检查），边界与上游逐项同。rayon 按行并行（行间独立：
  检测只读输入，标记不出本行——与上游 `DT_OMP_FOR` 同构）。
- 与上游唯一算术偏离：mono `markfixed` 的 `out[4*i+c]`（`:207`、`:209`）。
  步 4 只在 4 宽腿正确；在 1 宽腿它是跨行错写（串行宽瓦片下在界内错行；
  窄瓦片首行写出缓冲，且跨 OpenMP 行数据竞争），生产构建中无从对等。
  转写读 `planes` 步（4 宽与上游逐字节同，由对照证明；1 宽在行内 sane
  标记，由单测锁定）。详见 §5 第 4 条。
- DESC 全填：分组 Correction、flags BLEND、色彩 (Raw,Raw)、history 单实例。
- 不做：图形界面；修了几像素的计数（接口无回传通道，归设置面板那一波，
  待办）；`reload_defaults` 的 `hide_enable_button`（GUI 面，无转写位）。

## 五、与任务书读法不一致处（以源码为准，共 6 处）

1. 上游 `process` 按**处理时刻** `pipe->dsc.filters == 9` 选 X-Trans 腿，
   不是按 `commit` 存的 `d->filters`（后者全文件只写不读）。转写：快照照
   存（任务书要求），分支读处理时刻 `state.cfa`（以源码为准）。
2. `d->filters` 快照既然后面没人读，转写侧以 `expect(dead_code)` 承载 +
   单测断言快照值，不虚构用途。
3. `process` 的 X-Trans 表读的是 `piece->xtrans`（按区域预派生），转写的
   原点偏移读 `rout`（`rin == rout` 恒成立，无 roi 函数所致）。
4. mono `markfixed` 步 4 在 1 宽腿是跨行错写（见 §4）：转写读 `planes` 步。
   4 宽腿与上游逐位相等（对照门过），1 宽标记行为由单测锁定、无上游对等
   （上游该处窄瓦片越界、OpenMP 下数据竞争）。
5. `CfaPattern::None` 的已启用输入走 bayer 腿（上游 `filters==0` 同样落进
   bayer 分支；管线内不可达，两侧一致）。
6. 空 tile（0 宽/高）跳过检测循环（上游 C 循环条件同为空），拷贝 0 行，
   状态不碰。

## 六、门限与最大绝对差（全逐位相等）

门：平均绝对差 < 1/65535、容差内占比 > 0.9999（`compare_planes`）。
`max_abs` 全 0（`--nocapture` 实测；比大小 + 取最大值 + 拷贝，无算术）。

| 瓦片 | mean_abs | max_abs | in_tol |
|---|---|---|---|
| 链真瓦片 top-left/center/brightest/darkest（256×256，缺省参数，每块 4 孤立 + 1 相邻对超白热点） | 0 | 0 | 1.0 ×4 |
| bayer 四相位各一热点 | 0 | 0 | 1.0 |
| 相邻对 strict/permissive | 0 | 0 | 1.0 ×2 |
| 无热点平场（附逐位不变断言） | 0 | 0 | 1.0 |
| X-Trans 原点 (0,0)/(1,3) | 0 | 0 | 1.0 ×2 |
| 单色拜耳（1 宽） | 0 | 0 | 1.0 |
| 纯单色（4 宽）plain/marked | 0 | 0 | 1.0 ×2 |
| 强度 0（附直通断言 + oracle 禁用断言） | 0 | 0 | 1.0 |
| markfixed 预览/导出（附预览有标记、导出等于无标记跑断言） | 0 | 0 | 1.0 ×2 |
| 非 RAW 直通（附直通断言 + oracle 禁用断言） | 0 | 0 | 1.0 |
| 改阈值 0.3（附 warm 像素保留 + 缺省修复断言） | 0 | 0 | 1.0 |
| 改强度 0.5（附亮场修复断言） | 0 | 0 | 1.0 |

链上状态同测：四路最大值两边皆 1.0、CFA 经 oracle 解码后相等、
真瓦片 oracle `enabled`。样张事实沿 B3-1b（黑 512×4、白 15360、
RGGB `0x94949494`）。

## 七、新增测试清单（26 个）

oracle 自测 4（hotpixels 烟囱 2：孤立修复手算 + markfixed 在 Full 画线、
在 Export 等于无标记跑；复审 M4 回归 2：双模块链拒 mono、4 宽禁用全直通）；
转写单测 10（缺省解析、显式与校验、种类门 markfixed、零强度与非 RAW
禁用+直通、CFA 快照、bayer 手算、相邻对 strict/permissive 行为、4 宽四通道
落点、1 宽标记不出行、描述元数据）；对照集成 12（发现表 + 真瓦片链四区 +
四相位 + 相邻对两档 + 平场 + X-Trans 双原点 + 单色拜耳 + 纯单色两档 +
零强度 + markfixed 两类 + 非 RAW + 双改参）。
旧测试一个不改（除 commit 加参的 11 处机械跟进：rawprepare 单测 9 +
对照 2，断言一行未动）。
演示/bench：`hotpixels` 无引用（grep 全仓 `Scripts/rust-*.sh` 与
`apps/lightamer-cli` 零命中），第 5 条无事可做。

## 八、验收清单（命令与输出）

- 机器守卫：`Scripts/machine-guard.sh` → 起工 `GUARD PASS (heavy=0
  free=58% …)`；全套前 `GUARD PASS (heavy=0 free=56% …)`。
- 全套：`cargo test --workspace --locked --no-fail-fast -j6` → exit 0，
  `passed=801 failed=0 ignored=5`（775 + 新增 26，见 §7；复审修后重跑）。
- 六 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked
  -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing
  -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic
  -D clippy::todo -D clippy::unimplemented` → exit 0（中途修掉 11 个：
  excessive_bools、map_or×2、collapsible_if×2、too_many_lines×2、
  explicit_iter_loop、similar_names、too_many_arguments×2）。
- 文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`
  → exit 0。格式：`cargo fmt --all --check` → 过。
- 分层/同步/命名：`cargo xtask layers`（30 crates 无违反）、
  `check-order-sync`（97 模块 OK）、`check-no-iop-names`（97 名，4 roots clean）。
- 许可：`Scripts/check-licenses.sh` → exit 0。
- 演示：五个 `Scripts/rust-*-demo.sh` 皆 exit 0（session/history/render/
  decode/stream，无测不准重试）。
- `tools/extract.sh hotpixels --check`（`LIGHTAMER_DT_REF` 指向参考克隆）
  → 12 个 `OK`；`rawprepare --check` → 15 个 `OK`。
- 真瓦片 4 块 + 合成 15 块全过门，`max_abs` 全 0（见 §6）。
- `lightamer-iop-raw::lookup_implemented("hotpixels")` 查得到（对照集成
  首测），描述表和 registry 里都有（同测断言 MODULES + IMPLEMENTED）。
- 范围：`git show --name-only HEAD`（squash 后）仅纪律路径（NOTICE、
  PIPELINE.md 两句、六 crate、report+review log）；外部包零新增，
  `Cargo.lock` 零 diff（已验）。

## 九、复审（`B3-1c-review.log`，`PASS / 0 error + 7 minor`）

只读自审（`omp -p`，钉提交逐字节 + `--check` 双跑 + 转写逐行对，未构建/
未测试；复审日志一个字未改）。7 条 minor 全修：

- M1："恒为 UB"过强 → 措辞改为"跨行错写，窄瓦片越界、OpenMP 下数据竞争"
  （转写注释 + §4 + §5.4 三处同改）。
- M2：§4 计数对不上 → 改为"engine 测试桩 6、cli 演示桩 2"，
  "engine 零改动"限定为"engine 生产逻辑零改动"。
- M3：`assert_gate` 不断言 `max_abs` → 加 `assert_eq!(max_abs, 0.0)`
  （本模块纯比较/拷贝/取最大值，逐位是应有之义）。
- M4：双模块链/禁用拷贝按 1 宽 → `oracle_run` 加 `planes` 参数（中间缓冲
  与禁用拷贝乘通道数），链入口拒 mono（`BadInput`），加 2 回归测试
  （§7 oracle 自测 2 → 4）。
- M5：`process` 恒等检查不验原点 → 加 x/y 相等要求（X-Trans 原点映射所依）。
- M6：上游行锚漂移 7 处 → 逐处订正（另带出 `:204/:207`→`:207/:209`、
  TESTONE `:131-141`、拷贝 `:335` 三处同类）。
- M7：`xtrans_offsets` 零初值未披露 → 注释加 `<4 命中` 说明（上游该处读
  未初始化内存，真表/合成表恒命中 4，不可达）。
