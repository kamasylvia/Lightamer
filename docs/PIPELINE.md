# PIPELINE — 管线地基（B1-a）

B1-a 落的是管线内核的地基：画面与区域的数据类型、模块接口、几何链、
格式协商、分块决策。执行（缓存、并行、分块执行、渲染作业）是 B1-b；
渲染作业接引擎是 B1-c。

darktable 源码引用皆指 `refs/dt-master @ 679d594f5d`（只读上游）。
规则是读源码移植的，代码没有抄一行 C。

## 区域（Roi）

`lightamer-geom::Roi` 镜像 `dt_iop_roi_t`
（`src/develop/pixelpipe.h:36-39`）：整数 `x`/`y`/`width`/`height` 加浮点
`scale`。`scale == 1.0` 是全分辨率；宽或高为零是合法的空区域（模块说
「我不需要输入」就长这样）；负的宽高是错误；零、负数、非有限的缩放
是错误（定在构造器里，见 `Roi::new`）。

运算：相交、合并（最小包围）、平移、换缩放（`to_scale`）、判空、
判包含（含点）、取子区域（相对坐标，越界是错误）。
两个运算量缩放必须按位相等，否则相交/合并报 `ScaleMismatch`，
包含直接报 `false`。整数运算全部 checked，溢出是 `RoiError::Overflow`。

## 取整规则（单列）

换缩放的取整照 darktable 的模块写法移植：

| 规则 | 取整 | 出处 |
|---|---|---|
| 原点（x/y） | 向零截断（C 浮点转整数） | `src/iop/finalscale.c:103-104`（`roi_in->x /= roi_out->scale`）、`src/develop/pixelpipe_hb.c:2480-2481` |
| 范围（w/h） | `ceil`（不丢被盖住的像素） | `src/iop/finalscale.c:124-127` |
| 裁剪偏移 | 浮点加法后截断，再 `floor` 钳 | `src/iop/crop.c:587-594` |

`to_scale` 用的是非分块规则。分块时 darktable 另有一道远边保护
（把宽扩到 `ceil((x + w) / s)`，`finalscale.c:133-141`），那一道归分块
决策，不在这里。

默认 roi 对（恒等）照 `src/develop/imageop.c:108-125`；
前推的形状照 `_dev_pixelpipe_process_rec` 从链尾调 `modify_roi_in`
（`src/develop/pixelpipe_hb.c:2575`），反推的形状照
`dt_dev_pixelpipe_get_dimensions` 顺调 `modify_roi_out`（同文件 `:4026`）。

## 画面（Frame）与预算（Budget）

`lightamer-raster::Frame` = 像素缓冲（`Vec<f32>`）+ 所在区域
（`FrameExtent`，整数矩形，不带缩放——缓冲的位置不需要缩放）+
像素格式。工作格式是 32 位浮点四通道预乘 Alpha
（`PixelFormat::RgbaF32Premul`，整条管线唯一可分配的格式）；
`RgbaU8`/`RgbaU16` 只是枚举里的名字，给显示用，B1 分配不了。

访问方式：按行（`row`/`rows`/`rows_mut`，返回连续行区间，
调用方用 `split_at_mut` 切开，各写各的，互不别名）；
按子区域（`view`/`view_mut`，读/写视图，逐行借）；
整体拷贝（`copy_from`，形状或格式不对是错误）。
越界一律运行时错误（`RasterError::OutOfBounds`），编译期挡不住——
测试里 `row(8)` 对 8 行画面报 `OutOfBounds` 就是证明。
字节大小和行列数在 64 位里算，溢出或超过可寻址内存是
`RasterError::TooLarge`。

`lightamer-sysmem::Budget` 是带硬上限的预算：`acquire` 超限是
`BudgetError` 不是崩溃；`Grant` 是 RAII，drop 即归还；
`used`/`remaining` 随时可问，`Mutex` 包着，可跨线程共享。

L0 的四个 crate 互相不依赖，所以缓冲和预算的配对住在管线层：
`lightamer_pipeline::budgeted::alloc_frame` 先扣预算再分配，
分配失败时 grant 已 drop，字节自动回去。

## 模块接口（IopModule）

`lightamer-iop-traits::IopModule`，对象安全（只有 `&self` 方法，
无泛型、无关联类型），注册表可以拿 `Vec<Arc<dyn IopModule>>`
装各种各样的模块。CORE-DESIGN §1 的草图用了 `Params`/`Piece`
关联类型，那样的 trait 做不成 `dyn` 表——自动发现要的正是那张表，
所以参数改走历史模型存的 JSON 对象（`Map<String, Value>`），
提交结果改走不透明的 `CommitData = Arc<dyn Any + Send + Sync>`
（模块自己 downcast 转回）。

方法与 `src/iop/iop_api.h` 的对应：`desc` → `op`/`flags()`；
`colorspaces` → `default/input/output_colorspace`（`:97-110`，
未填的描述默认走 `(Rgb, Rgb)`——本管线的工作空间是线性 RGB，
缓冲是 RGBA；darktable 那边 `input/output` 默认回落到
`default_colorspace`，见 `src/develop/format.c:81-93`）；
`commit` → `commit_params`（`:199`）；`roi_out`/`roi_in` →
`modify_roi_out`/`modify_roi_in`（`:213-243`，默认恒等）；
`tiling` → `tiling_callback`（`:119-124`，默认见下）；
`process` → `process`。

错误分四种（`PipeError`），每种带一句人话：
`InvalidParams`（参数不对）、`RoiMismatch`（区域对不上）、
`UnsupportedFormat`（不支持的格式）、`Backend`（后端出错）。

给模块作者的五个小工具（`params` 模块）：`get_float`/`get_int`/
`get_bool`/`get_text`/`get_floats`，从 `{"type": ..., "value": ...}`
单元里取值，找不到或类型不对报 `InvalidParams`。

接口签名只用本 crate 的类型：roi 用线形（`Roi`，`lightamer-geom::Roi`
的同形镜像，管线在边界处逐字段转换并校验）；
`process` 用借来的像素视图（`Plane`/`PlaneMut`，行访问带界检查）；
提交的图像信息（`ImageInfo`：解码尺寸 + 相机输入色彩空间）也住这里——
L0 不许跨 crate 依赖，trait 要用的类型只能和 trait 住一起。

## 几何链

`lightamer-pipeline::chain`。调用方给一串按执行顺序排好的
`PipeNode`（标识、多实例下标、参数）加一个 `ModuleLookup`
（按标识找模块；闭包和 `HashMap` 都是 lookup）。
三件事：

1. **提交**（`build_chain`）：逐个调 `commit`，找不到模块是
   `UnknownModule`，提交拒绝是 `Commit`（带模块标识和源错误）。
2. **前推**（`forward`）：从最后想要的输出区域出发，逆执行顺序，
   每个节点的输入变成上一个节点的输出，一直推到需要解码的那块。
   相邻两项恒有 `geos[i].output == geos[i+1].input`。
3. **反推**（`backward_check`）：从最前面的输入顺推回去，
   逐节点核对与前推记录一致；第一个对不上的报 `Roundtrip`。

模块返回的线形在 `from_wire` 处校验（`lightamer-geom` 的构造器），
坏区域报 `BadRoi` 并点名模块。核心里没有写死的模块标识，
测试全用 `mod_a`/`mod_sink` 这类假名
（`check-no-iop-names` 会扫这个 crate）。

## 格式协商

`lightamer-pipeline::negotiate`。每个节点报自己的
（输入空间，输出空间）；`negotiate` 顺链走一遍，相邻两节点
首尾空间不一致就在它们之间记一笔 `ColorStep { after, from, to }`。
全链同空间时零笔。这一波只出计划（`ColorPlan`），变换本身在 B5。

## 分块

请求（`lightamer-iop-traits::TilingReq`）镜像 `dt_develop_tiling_t`
（`src/develop/tiling.h:25-41`）：`factor`/`maxbuf`/`overhead`/
`overlap`/`align` 是处理器侧，`factor_cl`/`maxbuf_cl` 是图形处理器侧
（填了不用）。默认值照 `default_tiling_callback`
（`src/develop/tiling.c:1903-1921`）：`factor = 1 + 输出面积/输入面积`，
`maxbuf = 1`，零开销、零重叠、对齐 1。
两处写明的偏离：空输入给 `factor = 2`（上游是除零得 `inf`）；
`TILING_FULL_ROI` 的 overlap-4 分支暂无对应（我们的标志词汇没有这一位）。

决策（`lightamer-pipeline::tiling::decide`）是纯函数：
输入（请求，输入/输出区域，一块画面的字节数，预算），
输出 `NoTiling` 或 `Tiled(TileGrid)`（块数、每块位置大小、
每块含重叠的输入区域）。算法照 `_default_process_tiling_ptp`
（`src/develop/tiling.c:571-822`）移植：

1. 吻合检查：`factor * 画面 + overhead <= 预算` 则不分块
   （`dt_tiling_piece_fits_host_memory`，`:1923-1933`）。
2. 无增益门：`factor < 2.2` 且开销小则不分块（`:599-610`）。
3. 可用 = 预算 − 输入整帧 − 输出整帧 − 开销，下限零（`:613-615`）；
   单块 = 可用 / factor（上游还和 `dt_get_singlebuffer_mem()` 取大，
   B1-a 无全局配置，不取——零预算退化成下面的放弃一路）。
4. 收缩：超单块则按 `scale` 缩（宽小于高且 `scale >= 0.333` 缩高，
   高小于等于宽且 `scale >= 0.333` 缩宽，否则两边缩 `sqrt(scale)`，
   一律 `floor`，`:629-646`；阈值是上游字面量 `0.333f`（`:634,638`），
   我方以 `0.333f32 as f64` 逐位拓宽到 `f64`——不是 `1.0 / 3.0`，
   两者在 `[0.3330000, 0.3333333)` 内走不同分支）；重叠主导
   （`3 * overlap` 超过任一边）则改方形（`:652-658`，ptp 路不贴对齐）。
5. 对齐：真切分时宽高向下贴（`:670-671`），重叠向上贴（`:674-675`）。
6. 步长 = 块 − 2*重叠（下限 1，`:678-679`）；
   块数 = `ceil(全幅 / 步长)`（`:682-683`）。
7. 超过 10000 块则放弃不分块（`:81-84` 的默认档；
   上游的 `unrestricted` 档暂无对应）。
8. 逐块：末块钳到帧内；两端都窄过 2*重叠的末块跳过（`:733`）；
   好块只裁前侧重叠（后侧由下一块覆盖写，`:780-790`）。

分发照 `:1176`（roi 按位相等才走 ptp；`TILING_FULL_ROI` 那半暂无）。
形状对不上的回答 `NoTiling`：roi 变体路（迭代拟合 `:527-567` + 单纯形
`:496-525`）要模块回调进循环，随 B1-b 的执行一起落地。

## 四种管线实例

`lightamer-pipeline::kinds`。darktable 是五种同构管线
（`dt_dev_pixelpipe_type_t`，`src/develop/pixelpipe.h:42-63`），
B1 立四种（第二个预览管线暂无对应）：
`Full`（完整分辨率）、`Export`（导出）、`Preview`（预览）、
`Thumbnail`（缩略图）。`quota()` 给每种三份配额——
内存预算、单块上限、缓存槽位数。**初值，B1-b 实测后再调**：

| 实例 | 内存预算 | 单块上限 | 缓存槽位 |
|---|---|---|---|
| Full | 4 GiB | 256 MiB | 8 |
| Export | 4 GiB | 256 MiB | 4 |
| Preview | 1 GiB | 64 MiB | 4 |
| Thumbnail | 512 MiB | 16 MiB | 2 |

（darktable 那边 Full 缓存 64 行、Preview 12 行，计的是行不是面，
数字不可比，只借「同构不同配额」的形状。）

## 测试模块

`lightamer-testkit::IdentityModule`（id `test_identity`）：
默认 roi 对和默认分块，`process` 把输入逐行抄到输出。
只许作开发依赖（分层检查钉死）。B1-b/B1-c 继续用它。
