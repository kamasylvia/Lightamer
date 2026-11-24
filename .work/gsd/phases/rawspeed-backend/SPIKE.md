# rawspeed backend — spike report (issue #24)

执行日期 2026-11-24（独立复跑 2026-11-25） · spike 提交 = `8873c77c`（本文件） · 复跑记录 = `evidence/RERUN.md`（提交见 `git log -1 -- .work/gsd/phases/rawspeed-backend/omp-spike-rerun-summary.md`） · lane = omp spike（技术验证，不做实现）
工作区：`/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/`（仓外，构建/样张/DNG）；仓内只留文本证据。

## Environment

| 项 | 值 |
|---|---|
| 机型 | Apple M4（16 GB） |
| OS | macOS 27.3 |
| Xcode | Xcode 27.0（27A266a），Swift 6.4 |
| rawspeed | `718eae230df9ebb1750755b775e52185f2342a46`（main，2026-11-22） |
| 第三方 | pugixml 1.15 / libjpeg-turbo 3.2.0 / libomp 22.1.7（Homebrew），zlib（SDK） |
| 样张 | CC0 `7RM5-LosslessCompressedLarge.ARW`（Sony ILCE-7RM5，85,950,464 B） |
| 基准期 | 全机无其它重活（`pgrep -fl "xcodebuild\|test-direct\|swift-build\|cmake\|ninja"` = none），`caffeinate -i`，内存空闲 61–67% |

---

## §0 结论头

- **Q1 形态：形态 A（Swift 6 直接吃 rawspeed C++ 头）不可行——能驱动、读不到、错即崩。** 解码调用链（`Buffer` → `RawParser` → `getDecoder` → `checkSupport` → `decodeRaw`）在 Swift 侧全部可用，但结果面全被封死：`RawImage::get()` 被 C++ interop 判为“可能返回 interior pointer”而**不导出**，`operator->` 与 `operator*`/`.pointee` 都不导入（后者复跑 typecheck 补证：`evidence/rerun-t2-extra-routes.log`），像素访问器（`RawImageData::getU16DataAsCroppedArray2DRef()`，普通成员函数）又只能经那个被封死的指针到达，`RawImageData::data` 是 protected。且 rawspeed 函数被导入为**非 throwing**——坏文件实测 `SIGABRT`（`EXIT=134`，`C++ exception handling detected but the Swift runtime was compiled with exceptions disabled`）。→ **必须 C ABI 薄封装（形态 B，darktable 同款）**。置信：**高**（编译错误原文 + 运行时 abort 可复现）。
- **Q2 体验速度（用户动作 → 位图就绪，冷启动 = 每测量独立进程，10 次中位）：现状 P0（CIRAW v8）适配屏 2560 档 **968 ms**、全分辨率 **1048 ms**（冷启动，每测量独立进程，10 次中位）；P1 首开（rawspeed → 内存 DNG → CIRAW v8DNG）同档 **447 ms / 556 ms**（快 2.2× / 1.9×）；P1 已缓存 DNG（盘上 122 MB）**374 ms / 482 ms**（快 2.6× / 2.2×；独立复跑 P0 868/939、P1a 401/461、P1b 337/391 ms，比值仍 ~2.0–2.2×，§4.9）；马赛克先降档：ds1（1/4 面积）**351 / 239 ms**，ds2（1/16）**302 / 202 ms**。编辑等待（每次新曝光值）：归档 harness 的 P0 适配档 738 ms / P1 13 ms **不是产品形态**——产品 `CIContextPool` 的 render-once memo 冻结首次输入平面（`PixelPipe.renderInputPlane` 的 `dedupeKey`），编辑只重跑管线；补测产品形态（冻结 2560 平面后做同一曝光乘法）P0 **1.69 ms**、P1 **1.76 ms**（n=10，§4.9）。→ **编辑等待不构成 CIRAW 的淘汰理由**；CIRAW 的代价集中在首开。100% ROI 两者都 ~2 ms。**RAW 9 经 DNG 可用**（`v9DNG` 在 `supportedDecoderVersions` 里，输出与 v8DNG 不同），但每次 **3.10–3.18 s**（冷进程；稳态 e2e ~2.8 s、渲染 ~2.7 s，v9 渲染段为 v8DNG 的 ~15×，§4.9）——预览档不可用，导出档可选。置信：**高**（同一二进制、同一渲染腿；哈希已在计时窗外）。
- **Q3 取舍：抄策略，不抄自写解码器。** 最快且体验最好的组合 = **rawspeed（解码段）+ 小档解码（HALF/QUARTER/EIGHTH）+ 目标尺寸直渲 + 100% 只渲可见 ROI + 分块缓存**；这套策略在 lumen-raw（1600 px 预览 + 512 px 分块 ROI）、Alcedo（`DecodeRes` 四档解码时降采样 + 2560 快速预览 / 8192 全分辨率双档）、darktable（mipmap 金字塔：内嵌 JPEG → mip-from-mip → rawspeed+pipe）里都是同构的。**自写解码器不值**：lightcraft 的纯 Rust 自研解码器是完整的多格式 unpack + DNG + demosaic 工程；我们缺的只是「新机型支持 + 解码速度」两点，rawspeed 的解码段 34–57 ms（解码段口径，非体验口径；同文件 LibRaw unpack 634–652 ms，16×）已经解决，剩下的边界是 C++ 一层（形态 B 已证可行）。置信：**中高**（策略证据来自源码 file:line；「自写」代价是量级判断，非实测）。

---

## §1 T1 rawspeed 构建配方

**命令行（可复现，已用 `cmake` 重跑验证 `ninja: no work to do`）**

```bash
cmake -S rawspeed -B build/rawspeed -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 \
  -DBUILD_TESTING=OFF -DBUILD_TOOLS=ON -DBUILD_BENCHMARKING=OFF -DBUILD_FUZZERS=OFF -DBUILD_DOCS=OFF \
  -DWITH_OPENMP=ON -DCMAKE_CXX_FLAGS="-I/opt/homebrew/opt/libomp/include"
cmake --build build/rawspeed -j 4
```

| 事实 | 值（来源） |
|---|---|
| C++ 标准 | `-std=c++20`（`build.ninja`） |
| 异常 / RTTI | **均开启**（编译行无 `-fno-exceptions` / `-fno-rtti`；rawspeed 自身以 `RawspeedException` 族报错） |
| 优化 | `-O3 -DNDEBUG -stdlib=libc++ -Werror`（`CMAKE_CXX_FLAGS_RELEASE`） |
| 依赖来源 | pugixml 1.15 Homebrew 动态库；libjpeg-turbo 3.2.0 Homebrew（`libjpeg.dylib`）；zlib 取自 Xcode SDK（`libz.tbd`）；libomp 22.1.7 Homebrew |
| `cameras.xml` | **运行时资源**，不编进二进制：`RS_CAMERAS_XML_PATH="/usr/local/share/rawspeed/cameras.xml"` 只是编译期默认路径，`CameraMetaData(const char*)` 每次进程解析；App 必须自带一份并显式传路径（darktable 用 `datadir/rawspeed/cameras.xml`） |
| OpenMP | `WITH_OPENMP=ON`，`-Xclang -fopenmp` + `libomp.dylib`（黑电平/去坏点等并行段用它） |
| 产物 | `librawspeed.a` **1,892,544 B**；整个 build 目录 6.1 MB；另含 `rs-identify` 工具 |
| 耗时 | configure **26.5 s**（含编译器探测），build **17.6 s real / 45.3 s user**（93 个目标；日志实测） |
| 链接形态 | 静态库 + 4 个动态依赖（pugixml/libjpeg/libomp/zlib）——见 §3 的 XCFramework 配方 |

**T1 验收（`bin/rsprobe`，`evidence/t1-a7r5-meta.txt`）**

```
decoder_class: rawspeed::ArwDecoder          make: SONY   model: ILCE-7RM5
canonical: Sony / ILCE-7RM5                  dim_uncropped 9728x6656  dim_cropped 9568x6376
crop_offset 0,0   crop_right_bottom 160,280  pitch_bytes 19456  cpp 1  bpp 2  UINT16
is_cfa 1   cfa_dcraw_filter 0x94949494   cfa_pattern_2x2 0112 (RGGB)
black_level 512 (2x2 512 512 512 512)   white_point 15360
wb_coeffs 2536 / 1024 / 1778            color_matrix 3x3 (XYZ→camera, 见 §4 的 DNG 约定)
mosaic_fnv1a64_cropped 0xbd81df79e1a15f93
pass_read_ms 7.3–8.1 (warm) / 100–992 (cold page cache)   pass_decode_ms 38.6–57.6
（`evidence/t1-a7r5-meta.txt` 是 bench.sh 每轮覆盖的探针输出：归档轮 992.1 / 40.4 ms、复跑轮 438.1 / 36.1 ms，差异是外部卷 page cache 冷读；warm 7.3–7.6 / 38.6–57.6 ms 出自 `evidence/t1-build-facts.log` 的两次连续读）
```

**正确性交叉验证**（`bin/xcheck`，rawspeed 马赛克 vs LibRaw `raw_image`，同文件、同区域 512×512、对齐搜索 ±2 px）：

```
region 512x512 at libraw (4528,2932) best_offset 0,0
max_abs_diff 0   mean_abs_diff 0.0000   mismatch_fraction 0.000000
```

→ **两个解码器在传感器域逐像素完全相同**（强证据：不是自检）。注意这是 cropped 区中心窗口（crop offset = 0,0，所以整幅同构）。

**偏差申报 1（根因已定位）**：v2 遗留的 T1 证据里 `mosaic_fnv1a64_cropped = 0xbcc106ae7a111119`。本次重建探针得 `0xbd81df79e1a15f93`，并用独立 Python TIFF 读取器对 DNG 像素数据复算得同值。根因查明：v2 探针的 FNV-1a 偏移基写成了 `1469598103934665603`（正确值 `0xcbf29ce484222325` = 14695981039346656037，少一位）；本次 §3 的 shim 一开始沿用了同一笔误，复现出**完全相同**的旧值 `0xbcc1…`，改正常量后立即变为 `0xbd81…`（`mosaic_first8` 两种实现逐元素一致：522 551 539 562 532 561 524 564）。→ **像素数据从未不同，只是哈希常量错了；旧值作废，新值三路（rsprobe / shim / DNG 字节 Python 复算）一致**。

---

## §2 形态 A：Swift 6 直接 C++ interop（结论：不可行）

包形态：`swift-tools-version:6.0`，C++ target 以 `publicHeadersPath` 发布 `RawSpeed-API.h`（自动 modulemap），可执行 target 挂 `.interoperabilityMode(.Cxx)`，`cxxLanguageStandard: .cxx20`，include 路径经 `cxxSettings.unsafeFlags` / `-Xcc` 双份。

| 轮次 | 结果 |
|---|---|
| 1 | **C++ 模块导入成功**（`import CRawSpeed` 通过），编译 360 s（首次 clang 模块 typecheck；增量后 1.2–1.7 s） |
| 2 | Swift 侧语法修正（`var parser`、`unique_ptr` 非 Optional） |
| 3 | `CameraMetaData.getNumCameras` 不存在；`RawImage.dim` 不存在 → 探查类型 |
| 4 | 类型探针：`RawImage::get()` 被禁用；`operator->` 不导入 |

决定性错误原文（≤20 行；完整归档 = `evidence/t2-compile-errors.log`，含探针源码与命令）：

```
error: cannot use mutating member on immutable value: 'parser' is a 'let' constant
error: value of type 'rawspeed.CameraMetaData' has no member 'getCamera'
  note: C++ method 'get' that returns a pointer of type 'Optional' is unavailable
  note: C++ method 'get' may return an interior pointer
  note: annotate method 'get' with SWIFT_RETURNS_INDEPENDENT_VALUE in C++ to make it available in Swift
error: value of type 'rawspeed.RawImage' has no member 'operator'
```

运行时（`evidence/t2-form-a.log`）：

```
$ RawSpeedInterop cameras.xml 7RM5-...ARW
meta_loaded: true
decode_returned: true
mRaw_handle_is_live: true (no accessor exists in Swift)
PASS_DRIVE_ONLY                                   # EXIT=0

$ RawSpeedInterop cameras.xml bogus.raw
C++ exception handling detected but the Swift runtime was compiled with exceptions disabled
meta_loaded: true
                                                  # EXIT=134 (SIGABRT)
```

逐条判定：

| 能力 | 形态 A 可行性 | 依据 |
|---|---|---|
| 解析文件、选解码器、checkSupport、decodeRaw | ✅ 可驱动 | 运行时 `decode_returned: true` |
| 读 `RawImageData`（dims/cpp/CFA/black/white/WB/matrix） | ❌ | 唯一入口 `RawImage::get()` 被 interior-pointer 规则禁用；`operator->`、`operator*`/`.pointee` 均不导入（后两者复跑 typecheck 补证：`evidence/rerun-t2-extra-routes.log`） |
| 读像素平面 | ❌ | 访问器 `RawImageData::getU16DataAsCroppedArray2DRef()` 本身是普通成员函数，但拿 `RawImageData*` 的唯一入口 `get()`/`operator->` 被封死；`data` 成员 protected |
| 摄像头元数据查询 | ❌ | `CameraMetaData::getCamera` 同样不导出（返回内部指针） |
| C++ 异常 → Swift 错误 | ❌ | 函数被导入为 **非 throwing**（编译器提示 “no calls to throwing functions occur within 'try'”），异常穿帧 = `std::terminate`（实测 134） |

→ **形态 A = 部分可行但不可用**：要把它变成可用，得改 rawspeed 头（加 `SWIFT_RETURNS_INDEPENDENT_VALUE`）并为每个访问器写 Swift 友好的重载——这等于自己维护上游补丁，比写一个 165 行的 C shim 更贵。**必须走形态 B。**

代价面：首次编译 360 s / 增量 1.2 s；`.Cxx` 只需挂在**直接 import rawspeed 的 target**（一个），不扩散到 app 其余部分。

---

## §3 形态 B：C ABI 薄封装（可行）

`shim/Sources/CRawSpeedShim/{rawspeed_shim.h, rawspeed_shim.cpp}`（165 行 C++ + 68 行头；DNG 写入器在 `bin/dngwriter.h`，317 行，二者共用），Swift target 纯 C 头 `import CRawSpeedShim`（**不开 `.Cxx`**）。

要点：

- **不透明句柄** `typedef struct rs_image rs_image;` 持有 `RawImage`（shared_ptr，像素平面的真正所有者）+ `RawImageData*`；另存 `unique_ptr<RawDecoder>` 仅为保活。**风险注记（复跑核对）**：rawspeed 的 `RawDecoder` 契约要求 file `Buffer` 在 decoder 存活期间有效，而 shim 在 `rs_open` 返回时释放 `FileReader` storage；本 spike 在 open 后不再调用任何 decoder 方法、像素平面由 `RawImage` 独立持有（`rs_fill_info`/`rs_mosaic_hash` 在 storage 释放后仍正确），故实测无故障，但生产化必须去掉 decoder 或保留 file mapping。
- **错误面**：`rs_error { int32_t code; char message[512]; }`，`rs_open` 内部 `catch (RawspeedException) / std::exception / ...` 全捕获，**异常零穿出**。
- **异常/内存面（复跑核对）**：`rs_open`/`rs_fill_info`/`rs_build_dng` 全捕获；像素访问器 `getU16DataAsCroppedArray2DRef()` 是 `noexcept`（`RawImage.h:304`），`rs_mosaic` 另有 UINT16 类型门——异常不会穿出。DNG 字节用 `malloc`/`rs_free_bytes`、句柄用 `new`/`delete`，归属闭合。`rs_mosaic_hash` 已补 UINT16 类型门（复跑修改）；`dngwriter` 仍未做（本样张恒 UINT16；float DNG 属未覆盖输入）。
- **字段面**：dims/crop/cpp/bpp/pitch_elems/is_cfa/is_xtrans/cfa filter+2x2/black_level(+2x2)/white_level/wb 三系数/color matrix 9 元素/make/model；
- `rs_mosaic` 返回 cropped 平面基址（**行距 = `pitch_elems`，不是 width**——rawspeed 保留 uncropped pitch，这是与 v2 草稿的一处修正）；`rs_mosaic_hash` 便于跨实现对齐。
- Swift 侧：`rs_image*` 作为 `UnsafeMutablePointer<rs_image>?` 传值；`Sendable` 处理 = 用 `final class RSHandle: @unchecked Sendable` 持有指针并在 `deinit` 调 `rs_free`，解码调用放 actor/后台队列（rawspeed 每 handle 独立，无共享可变态；本 spike 每次 `rs_open` 各解析一份 `CameraMetaData`——线程安全但有重复解析成本；生产化建议 `std::call_once` 共享一份只读 meta（darktable 同款），共享后只读并发安全）。
- 实测（`evidence/t3-shim.log`，Swift 6 语言模式 + 严格并发编译通过）：

```
=== A7R5 ARW ===
make=SONY  model=ILCE-7RM5
dim=9568x6376 uncropped=9728x6656   crop=0,0,160,280 cpp=1 pitch_elems=9728 cfa=1 xtrans=0
cfa_filter=0x94949494 pattern=(0, 1, 1, 2)
black=512 sep=(512, 512, 512, 512) white=15360
wb=(2536.0, 1024.0, 1778.0) has_wb=1
matrix=(0.82, -0.2976, -0.0719, -0.4296, 1.2053, 0.2532, -0.0429, 0.1282, 0.5774) has_matrix=1
hash=bd81df79e1a15f93                                  # == T1 / DNG 字节（三路一致）
EXIT=0

=== corrupt input (error path) ===
open_failed code=2 msg=virtual std::unique_ptr<RawDecoder> rawspeed::RawParser::getDecoder(...), line 47: File too small
EXIT=0                                                # 形态 A 同输入 = SIGABRT(134)
```

**契约对照（shim 字段 ↔ `LightamerCore/Sources/Decode` 现状）**

| shim 字段 | 产品现有类型 | 缺口 |
|---|---|---|
| `black_level` / `black_level_separate` | `RAWTechnicalParams.blackLevel`（**单值 Double**，来自 DNG 字典） | 逐通道 black 是**新字段**；且今天 `rawTech` 只做日志（`EditorState` 打印），**没有任何 IOP 消费它** |
| `white_level` | `RAWTechnicalParams.whiteLevel`（同，DNG 字典） | 语义一致，来源改为 rawspeed |
| `wb_coeffs[3]` | `RAWTechnicalParams.neutralChromaticity`（CIVector xy） | **不同表示**：需要 xy↔RGB 增益换算，或新增字段 |
| `color_matrix[9]` | **无** | 全新（camera→XYZ / XYZ→camera 的约定见 §4） |
| `cfa_pattern` / `is_xtrans` / `crop` / `pitch` / `cpp` | **无** | 全新（今天马赛克不进管线，CIRAW 内部完成 demosaic） |
| `make` / `model` | `CaptureMetadata.cameraMake/cameraModel`（ImageIO EXIF） | 已有；rawspeed 的 canonical 值可作为补充/校正 |
| 像素平面 | **无**（`DecodedImage.ciImage` 是 CIRAW 已显影的 RGB） | 全新：`DecodedImage` 需要增加「马赛克平面 + 元数据」形态，或新增 `DecodedMosaic` 类型 |

→ **架构后果（最重要的一条）**：今天 `RAWTechnicalParams` 是 readback/日志面，管线起点是**已显影 CIImage**。接 rawspeed 意味着引入一个真正的 rawprepare 段（black/white/WB/matrix/CFA 消费）+ 一条「马赛克 → RGB」的显影腿（DNG→CIRAW 或自有 Metal demosaic）。这不是「换个解码器」，是**管线起点前移**。

**XCFramework 最小可行配方（未构建，仅评估）**

1. 两个 slice：`cmake -DCMAKE_OSX_ARCHITECTURES=arm64` 与 `x86_64`（Release 静态库）；
2. 依赖可静态化：`libomp.a` / `libpugixml.a` / `libjpeg.a` 均存在（Homebrew 已带）→ 把四个 `.a` 合并（`libtool -static`）或分别链接；
3. `xcodebuild -create-xcframework -library librawspeed_fat.a -headers include/ -output rawspeed.xcframework`；
4. SPM `.binaryTarget(name: "RawSpeed", path: "rawspeed.xcframework")` + 现有 shim target 依赖它。
   **代价**：必须先选定依赖静态化策略（license 上 LGPL-2.1 的 rawspeed 静态链接需提供 relink 能力或改用动态库——这是**法务面决策**，不在本 lane 结论内）。

---

## §4 Q2 体验速度

口径（本轮按自审意见修订過一次，diff 见 §6.11）：

- 指标 = 用户动作 → **位图就绪**（`CIContext.render(toBitmap:)` 返回、CPU 可读的 sRGB RGBA8）。
- **校验哈希不在计时窗内**：渲染完成立即打点，FNV 校验在窗后单独计时；冷启动值 = 父进程墙钟 − 本次 `hash_ms`（进程启动 / Metal 设备 / `CIContext` 初始化仍在窗内）。
- **冷**：每测量一个新进程（含进程启动），3 次热身弃、10 次计时取中位，报 min / p90（**n=10 时 p90 取到末位 ≈ max**）。
- P1a（`benchlive`）与 P0/P1b（`bench`）都输出 `hash_ms`，冷值一律按「父墙钟 − `hash_ms`」；`benchlive` 的进程内 e2e 也在哈希之前打点。
- **热（M1）**：同进程重开，**每个 rep 都** `clearCaches()`，设备与上下文保留。
- **M2**：每个 rep 换一个**新**曝光值（+0.5 EV 起、每 rep +2%）——同一编辑重复渲染会被 CI 缓存变成假测量；缓存按自然设计保留（不清）。
- P0 与 P1 共用同一个 `render()` 函数（同一个缩放/ROI 渲染腿）。
- **P2 没有渲染腿**：LibRaw 出全幅/半幅 sRGB（`dcraw_process`），2560 目标尺寸渲染与 `make_mem_image` 都不含在内 → 只作「解码 + 去马赛克」的**下界**。
- P1 三个变体：**P1a 首开**（rawspeed 解码 + 内存 DNG + CIRAW，同一进程一次完成，无盘上 DNG）、**P1b 已缓存 DNG**（122 MB 在盘，计时含读盘 + `CIRAWFilter(imageURL:)`）、P1a-ds1/ds2（马赛克先降档再封 DNG）。

### 4.1 M1 打开等待（冷启动，每测量独立进程，n=10；括号 = min / p90）

| 路径 | 适配屏 2560 | 全分辨率 |
|---|---|---|
| **P0 CIRAW v8（现状）** | **968 ms**（956 / 1577） | **1048 ms**（1038 / 1063） |
| **P1a 首开（rawspeed→内存 DNG→CIRAW v8DNG）** | **447 ms**（434 / 456） | **556 ms**（548 / 572） |
| P1a，马赛克先降 1/4 面积（ds1） | 351 ms（349 / 366） | — |
| P1a，马赛克先降 1/16 面积（ds2） | 302 ms（301 / 318） | — |
| P1a + **RAW 9**（v9DNG，n=5） | **3177 ms**（3140 / 3208） | — |
| P1b 已缓存 DNG（122 MB 在盘） | 374 ms（365 / 386） | 482 ms（462 / 538） |

### 4.2 M1 热（同进程重开 + clearCaches，n=10）

| 路径 | 适配屏 2560 | 全分辨率 |
|---|---|---|
| P0 CIRAW v8 | 759 ms | 835 ms |
| P1b 已缓存 DNG ds0 | 244 ms | 276 ms |
| P1b 已缓存 DNG ds1 | 57 ms | — |

### 4.3 M2 编辑等待（每次一个**新**曝光值 → 位图更新；缓存按自然设计保留）

| 路径 | 适配屏 2560 | 100% ROI 1024×768 |
|---|---|---|
| P0 CIRAW | 738 ms（378 / 748） | 2 ms（2 / 3） |
| P1b 已缓存 DNG | 13 ms（12 / 14） | 2 ms（1 / 2） |

> **口径警告（2026-11-25 复跑修订）**：本表是 harness 上界（未冻结输入平面），**不代表产品编辑等待**。归档轮 P0 fit 738 ms 在复跑同口径为 329 ms（−55%），本身不稳定；产品形态对照见 §4.9（P0 1.69 ms / P1 1.76 ms）。

### 4.4 规模阶梯（P0 vs P1a/P1b）

| 输出/解码规模 | P0 冷 | P1 冷 |
|---|---|---|
| 长边 2560 | 968 ms | P1a 447 / P1b 374 ms |
| 长边 1280 | 993 ms | —（ds2 2392 长边 ≈ 此档）|
| 长边 640 | 1001 ms | — |
| 马赛克 ds1（4784 长边） | — | P1a 351 / P1b 239 ms |
| 马赛克 ds2（2392 长边） | — | P1a 302 / P1b 202 ms |

### 4.7 P2 替身（LibRaw 解码 + CPU 去马赛克；**无渲染腿**，n=10）

| 配置 | 冷 e2e（解码+去马赛克） | 其中 open+unpack | 其中 process |
|---|---|---|---|
| LibRaw full linear | **1080 ms** | 638.08 ms | 451.27 ms |
| LibRaw full AMaZE | **1514 ms** | 635.47 ms | 877.26 ms |
| LibRaw half linear | **698 ms** | 634.85 ms | 54.66 ms |
| LibRaw half AMaZE | **689 ms** | 631.36 ms | 54.48 ms |

（`bench.csv` 与 `bench-run.log` 由同一次 `bench.sh` 覆盖写入；跑一轮就把归档换成该轮 —— 这是本 lane 的「单一数据源」约定，报告 §4 表由 `tables.py` 从 CSV 生成。）

**关键读数**

1. **P0 对输出尺寸不敏感**：2560 / 1280 / 640 三档分别在 968 / 993 / 1001 ms —— CIRAW 的成本在「解文件 + demosaic」，不在输出尺寸。⇒ **降采样必须发生在解码/去马赛克之前**（改马赛克或改解码器），在 CI 层缩输出没有用。
2. **P1 的成本随马赛克规模下降**：P1a 447 → 351（ds1）→ 302（ds2）；P1b 374 → 239 → 202 ms。
3. **归档表的 738 vs 13 不能读成产品编辑差**：它测的是「解码平面是否被冻结」——不是解码器差异。产品对 ARW/DNG 都冻结输入平面（`CIContextPool` render-once memo），补测产品形态 P0 **1.69 ms** / P1 **1.76 ms**（§4.9）。harness 的 738 是未冻结时的上界，且复跑同口径只有 329 ms（CI 有时能缓存住 100MP 平面），本身不稳定。
4. **RAW 9 经 DNG 可用但不可作预览**：冷进程 3.10–3.18 s/次；其中稳态渲染段 ~2.70 s（v8DNG 的 ~15×），首次模型准备 ~2.1 s（一次性，系统缓存后新进程不再付）。§4.9。
5. **内存 DNG vs 盘上 DNG**：同口径（都扣掉校验哈希）全分辨率 P1a 556 ms vs P1b 482 ms——两者**同量级**（差 ~74 ms；上一轮 550 vs 493，差 <60 ms）；早前「内存版慢 288 ms」是把含哈希的 684 与不含哈希的 396 相减得出的**错误对比**。→ 选择落盘缓存（P1b）的理由是**内存占用与跨会话复用**，不是速度。

### 4.5 P1 关键实验结果（RAW 9 与色彩）

1. **A7R5 原片的 `supportedDecoderVersions` = `v7, v8, v9`** —— 本机 macOS 27.3 / Xcode 27 SDK 上 **A7R5 已支持 RAW 9**。类级名单进一步定位旧结论的偏差来源：`supportedCameraModels(with: .version9)` 共 **69** 台，其中含 **"Sony Alpha ILCE-7R V"**（不含字符串 "ILCE-7RM5"）；`version8` 名单共 **465** 台，含两者。→ AGENTS 里「A7R5 不在 CIRAW9 名单」是按型号字符串 "ILCE-7RM5" 匹配得出的**假否定**（证据：`evidence/camera-list.txt`）。RAW 9 的真实约束不是名单而是**速度**（下条）与 **V9 的绿偏缺陷**（§6.3）。
2. **rawspeed 马赛克 DNG 的 `supportedDecoderVersions` = `v6DNG, v7DNG, v8DNG, v9DNG`** → **RAW 9 经 DNG 对非 Apple 名单来源也可用**，输出与 v8DNG **不同**（hash 与像素都不同），即真的走了 RAW 9 的 CoreML demosaic+denoise。
3. **代价**：v9DNG 冷进程 e2e **3.10–3.18 s**（归档四轮 3026 / 3083 / 3147 / 3177；复跑冷 3100 ms），其中 **稳态渲染 ~2.70 s**（v8DNG 渲染段 ~0.18 s 的 **~15×**）、rawspeed 解码 48–72 ms、DNG 构建 22–66 ms、CI init ~17 ms；**首次模型准备 ~2.1 s 是一次性**（首进程 rep0 的 ci_init = 2107 ms；系统缓存后新进程 ci_init ~129 ms，不再付），首发 6.1 s 是更冷状态的一次性观测。→ **RAW 9 只能用于导出档/后台档，不能进预览档**。
4. **色彩差异**：P1 与 P0 的同图 2560 位图，`mean_abs_diff = 22.8/255`（`evidence/p0-vs-p1-cmp.txt`），均值 RGB 116/144/67 vs 111/128/52（P1 偏青、绿少）。**P1 的色彩管理还没对齐**，速度结论不受影响，但「P1 输出直接上屏」还差一轮色彩标定。
5. **DNG 封装约定（重要且反直觉）**：`ColorMatrix1` 必须写 **rawspeed 的 `metadata.colorMatrix` 原值**（rawspeed 文档称其为 XYZ→camera）。写成它的逆矩阵（按 DNG 规范字面理解 camera→XYZ + 按 D65 归一）时，CIRAW 渲染 **过曝约 2.5–3 档并全图截白**，且 `filter.neutralChromaticity` 变成 `(-0.002, 0.755)` 的垃圾值；写原值时渲染正常、`neutralChromaticity ≈ (0.335, 0.356)`，与原片 CIRAW 的 `(0.345, 0.363)` 一致（`evidence/dng-props.txt`）。→ **方向已独立证明（复跑 2026-11-25）**：rawspeed 的 9 元素与 LibRaw `cam_xyz` 逐元素完全相同（max diff 0.000000），而 LibRaw 的 `cam_xyz` 按 `cam_xyz @ rgb2xyz`（RGB→camera）归一化求逆后与它自己的 `rgb_cam` 吻合到 1e-7——即 `cam_xyz` 确为 XYZ→camera；DNG `ColorMatrix1` 也是 XYZ→camera，故**写原值正确，不是两边抵消**（`evidence/rerun-lrmat.log`）。仍需色卡/受控光源做的是**色彩标定**（`mean_abs_diff 22.8` 的偏色），不是方向。
6. **DNG 体积与首建成本**：ds0 = 122 MB，ds1 = 30.5 MB，ds2 = 7.6 MB。两个口径（不要混用）：**seam 内构建**（`benchlive`，不含 FNV 交叉校验）≈ 33 / 47 / 52 ms（ds0/ds1/ds2）；**`rs2dng --time` 探针**（含 FNV）≈ 137 / 74 / 41 ms。rawspeed 解码 34–57 ms 另计。注意：初版 binning 是逐样本双精度累加，ds1 实测 **855 ms**（未归档旧二进制，只能作为观测记录）——改成分块整型累加到 74 ms，像素哈希不变（`0x040b32e098206fb7`）。**降档腿必须在 GPU/Metal 或紧密循环里做，否则数百 ms 级的 CPU 开销会吃掉降档收益。**

### 4.6 解码段拆分（解释列，不进结论）

| 段 | 值 |
|---|---|
| rawspeed 文件读取 | 7.3–8.1 ms（warm）/ 100–992 ms（冷 page cache；归档 992 / 复跑 438） |
| rawspeed 解码（85 MB 无损压缩 ARW） | **34–43 ms**（冷进程首解可到 57 ms） |
| 马赛克 → DNG 字节（ds0 / ds1 / ds2，内存内） | **25–30 / 68 / 38 ms**（不含落盘） |
| LibRaw `open_file + unpack`（同文件） | **618–638 ms** |
| LibRaw `dcraw_process` 线性 / AMaZE | **428 / 813 ms** |
| LibRaw half_size 的 `process` | 51 ms（且 **qual 无效**：linear/AMaZE 输出同 hash） |
| CIRAW `CIRAWFilter(imageURL:)` init（ARW / DNG） | ≈130 ms / ≈90 ms（含首次模块加载成分，冷进程中共 1 次） |

### 4.8 复跑

`evidence/bench.sh`（单命令）：机器守卫 → 缺产物先构建（rawspeed 静态库 / rsprobe / rs2dng / lrbench / xcheck / bench / benchlive）→ T1 探针 → xcheck → 形态 B 探针（含坏输入错误腿）→ DNG 三档 → P0-vs-P1 粗差 → 全矩阵 → 写 `evidence/bench.csv`（`BENCH_OUT=<path>` 可改落点；`--quick` 在归档存在时自动改写 `bench-quick-<HHMM>.csv`，不覆盖归档）。`--quick` = 5 次。复跑对照见 §4.9。

### 4.9 独立复跑对账（2026-11-25）

环境：Apple M4（16 GB）/ macOS 27.3 / Swift 6.4；`Scripts/machine-guard.sh` PASS（heavy=0，内存空闲 71%）；`pgrep -fl "xcodebuild|test-direct|swift-build|cmake|ninja|darktable|Lightamer"` = none；`caffeinate -i`。复跑用**未改一行的 `bench.sh`/`benchrun.py` 副本**（md5 相同），输出落 `evidence/rerun-bench.csv` / `rerun-bench.log`；归档 `bench.csv` 未被覆盖。

独立复跑 `evidence/rerun-bench.csv`（26 行中 5 行偏离归档 > ±15%，全部更快）：

| row | kind | 归档 ms | 复跑 ms | 偏差 | ±15% |
|---|---|---|---|---|---|
| P0 CIRAW v8 A7R5 fit | cold | 968.1 | 868.0 | -10.3% |  |
| P0 CIRAW v8 A7R5 full | cold | 1048.3 | 939.1 | -10.4% |  |
| P1a live ds0 fit (decode+DNG+CI) | cold | 446.8 | 400.8 | -10.3% |  |
| P1a live ds0 full | cold | 555.5 | 460.8 | -17.0% | **OUT** |
| P1a live ds1 fit | cold | 350.8 | 306.4 | -12.7% |  |
| P1a live ds2 fit | cold | 302.2 | 273.1 | -9.6% |  |
| P1b cached-DNG ds0 fit | cold | 373.8 | 336.7 | -9.9% |  |
| P1b cached-DNG ds0 full | cold | 481.5 | 391.3 | -18.7% | **OUT** |
| P1b cached-DNG ds1 fit | cold | 239.3 | 206.0 | -13.9% |  |
| P1b cached-DNG ds2 fit | cold | 202.2 | 172.1 | -14.9% |  |
| P0 CIRAW v8 1280 long edge | cold | 992.7 | 900.1 | -9.3% |  |
| P0 CIRAW v8 640 long edge | cold | 1001.1 | 901.7 | -9.9% |  |
| P1a live ds0 v9DNG fit (RAW9) | cold | 3177.3 | 3099.8 | -2.4% |  |
| P0 CIRAW v8 A7R5 fit | hot | 759.4 | 699.4 | -7.9% |  |
| P0 CIRAW v8 A7R5 full | hot | 835.1 | 735.3 | -12.0% |  |
| P1b cached-DNG ds0 fit | hot | 243.7 | 221.6 | -9.1% |  |
| P1b cached-DNG ds0 full | hot | 275.9 | 226.1 | -18.1% | **OUT** |
| P1b cached-DNG ds1 fit | hot | 57.0 | 51.6 | -9.5% |  |
| P0 CIRAW v8 fit | hot | 738.3 | 329.3 | -55.4% | **OUT** |
| P0 CIRAW v8 100% ROI | hot | 1.8 | 1.9 | +5.6% |  |
| P1 cached-DNG ds0 fit | hot | 13.3 | 10.0 | -24.8% | **OUT** |
| P1 cached-DNG ds0 100% ROI | hot | 1.5 | 1.7 | +13.3% |  |
| P2 LibRaw full linear | cold | 1080.5 | 1044.6 | -3.3% |  |
| P2 LibRaw full AMaZE | cold | 1514.0 | 1424.1 | -5.9% |  |
| P2 LibRaw half linear | cold | 698.3 | 679.1 | -2.7% |  |
| P2 LibRaw half AMaZE | cold | 689.2 | 672.8 | -2.4% |  |

产品形态 M2（冻结输入平面后做下游曝光乘法；n=10，编辑→位图）：

| 输入 | 冻结（首次输入平面渲染） | 产品形态编辑 中位（min / p90） | 同探针未冻结对照 |
|---|---|---|---|
| P0 CIRAW v8 ARW | 679 ms | **1.69 ms**（1.59 / 4.07） | 192.3 ms |
| P1b cached DNG ds0 | 192 ms | **1.76 ms**（1.60 / 2.77） | 12.1 ms |

RAW 9（v9DNG）冷/热拆分（`evidence/rerun-v9-breakdown.log`）：

| 场景 | e2e ms | 其中 CIRAWFilter init | 其中 render |
|---|---|---|---|
| 首进程 rep0（含模型准备） | 4938 ms | 2107 ms | 2735 ms |
| 同进程稳态 rep1–9（中位） | 2812 ms | 18 ms | 2703 ms |
| 独立冷进程（3 次，中位） | 2952 ms | 129 ms | 2748 ms |

**口径差异（P0/P1 与产品）**：decoder version 一致（产品 automatic = v8，bench `--decoder v8`）；渲染腿不同——bench 用 `CIContext(mtlDevice:)` 默认 working space + `cacheIntermediates: true`，输出 sRGB RGBA8 CPU bitmap；产品 `CIContextPool` 用 linear Rec2020 / `workingFormat: RGBAh` / `cacheIntermediates: false`，渲染到 rgba32Float texture（无 CPU 回读）。解码+demosaic 段占 P0 的 ~700 ms，色彩空间/位深只影响其后的渲染段；P0 的 968/868 ms 是「CIRAW 解码 + 2560 渲染 + 回读」的同形近似，不是产品 GUI 的逐字节真值。**M2 是受口径影响最大的一项**（见上表），产品形态必须冻结输入平面才是可比的。哈希在计时窗外（`bench`/`benchlive` 的 `hash_ms` 单列并从冷墙钟扣除）；P1a 的 DNG 字节拷贝与 `CIRAWFilter(imageData:)` 在窗内（属 seam 本身），P1b 的读盘在窗内。

**结论**：M1 的相对结论（P1 约为 P0 的 1/2）在复跑中保持；绝对值的跨轮漂移：M1/P2 −3%…−19%，M2 两行 −25%/−55%（5/26 行超 ±15%，全部更快），与 §6.5 申报的双向漂移一致。M2 的 57× 不成立，改以本表产品形态为准。RAW 9 的冷/热拆分见上表。

## §5 Q3 参考 UX 策略与横向

### 5.1 各项目预览策略（源码证据）

| 项目 | 首屏显示什么 | 何时算全分辨率 | 100% 是否只算 ROI | 缓存 | demosaic 在哪 | 线程 |
|---|---|---|---|---|---|---|
| **darktamer**（darktable 分叉） | 内嵌 JPEG（够大时直接用）→ 不够则 mip-from-mip → 再不够才 rawspeed+pixelpipe 从零生成（`src/common/mipmap_cache.c:1600-1690`） | 用户进暗房后 pixelpipe 按 `DT_DEV_PIXELPIPE_PREVIEW / FULL` 档跑；mip 金字塔 `DT_MIPMAP_0..10 + F/FULL`（`mipmap_cache.h:30-49`） | 是：pixelpipe 以「当前窗口缩放 + ROI」调度（`develop/pixelpipe.h:44-51`），不是每帧全幅 | mipmap 内存 + 磁盘 cache；嵌入式缩略图等级选择 `dtgtk/thumbtable.c:1898-1925` | rawspeed 只出马赛克（`imageio/imageio_rawspeed.cc:189-232`），demosaic 在 pipeline（CPU/OpenCL） | 后台线程 + OpenMP（黑电平缩放段 `imageio_rawspeed.cc:568-622`） |
| **Alcedo Studio** | 缩略图 = 内嵌 JPEG 的 reduced decode（`decoders/thumbnail_service.cpp` 用 `DecodeRes::EIGHTH/QUARTER/HALF` 映射，`app/thumbnail_service.cpp:43-56`）；编辑器 = 2560 快速预览 | `FAST_PREVIEW`=2560 长边 / `FULL_RES_PREVIEW`=8192 / `DETAIL_ROI_PREVIEW`=视口 ROI（`renderer/pipeline_scheduler.cpp:26-27,146-190`） | 是：`DETAIL_ROI_PREVIEW` 只渲 `viewport_region`（同上 :176-186） | 缩略图磁盘缓存带 schema 版本（`app/thumbnail_service.cpp:59`）；解码结果按 `source_key` | **解码时降采样**（`DecodeResToDownsamplePasses`，`edit/input/raw_input_loader.cpp:544-548,726-728`）+ **GPU/NN demosaic**（`decoders/processor/nn/demosaicnet*`，CUDA/OpenCL） | 解码线程池（`thumbnail_service.cpp:61-65` 注释：解码是 CPU 活，不放渲染执行器） |
| **lumen-raw** | 1600 px 半尺寸预览（`engine.py:126,168` `preview_limit=1600` + `half_size=bool(preview_limit)`） | 缩放超过 1600 后 → 后台按「屏幕像素够用的最粗级（1, 1/2, 1/4…）」渲可见块（`viewport.py:1-16`） | 是：512 px tile，只渲可见 tile，平移只补新暴露的 tile（`viewport.py:33-37`） | tile LRU 256 MB + 「编辑后不复用旧状态 tile」（`viewport.py:34`）；详情 220 ms debounce（`resolution.py:46`） | LibRaw（`rawpy`）CPU；GPU 用于编辑图 | GUI 线程只画已完成的 tile（`viewport.py:10-14`） |
| **RawLab** | 按窗口算预览长边（`Adjustments.swift:353-364`：`fit*mag*displayScale`，按 64 px 取整避免窗口微调反复重渲） | 交互中降档、松手 forceExact（`EditorModel+Rendering.swift:22-49`：`setInteracting(true/false)` + 0.2 s debounce） | 部分（geometry draft 复用 transformed canvas，`Rendering.swift:10-18`） | 预览图 + geometry draft 缓存 | LibRaw（`PRODUCT.md:9`）CPU | Swift 调度器 + 后台队列 |
| **SpektraLab** | 「live tier」= `io.preview_long_edge`（800–8192 可调，`core/params.cpp:144`） | `tier_long_edge()`：`full` 档 = 0 表示帧自身分辨率（`pipeline/engine.cpp:101-116`） | 是（tier 机制，视口按 live/full 档切换） | 参数变化使相应 tier 失效（`engine.cpp:1652`） | 引擎内（C++，多后端） | 引擎线程 + 前端异步 |
| **lightcraft** | 预览缓存 crate：内容哈希 + 内存 LRU + 磁盘缩略图 + 优先级 job pool（`crates/preview/src/{hash,lru,disk,pool}.rs`） | 由 job 优先级决定（预览先于全图） | 未见显式 ROI 分块（`crates/preview` 是缓存/调度层） | 三层：hash/LRU/disk | **自研 Rust 解码器 + demosaic**（`crates/raw/src/demosaic/{bilinear,ppg,ahd,xtrans}.rs`） | rayon 并行 |

**公开资料（文献级，未实测）**：Lightroom Classic 的 Develop 以「smart preview / 1:1 预览缓存 + 后台标准预览生成」为核心（Adobe 官方 help「Preview generation」）；Capture One 以「Preview size（如 1920/2560/5120）+ 打开即生成 + 缩放只重算视口」为宣称；Pixelmator Pro 与 RAW Power 走 Apple RAW/Core Image 栈，预览策略与本文 P0 同源，差异在缓存与分块。**均未在本机安装或实测**（`/Applications` 现装：`Darktamer.app`、`digiKam.org`、`Imaging Edge`、`壹印.app`；无 LR/C1/Pixelmator/RAW Power）。

### 5.2 横向表

| 解码器 | ILCE-7RM5 支持 | 本机实测速度（同文件） | 许可证 | 接 Swift 的形态与代价 | 活跃度 |
|---|---|---|---|---|---|
| CIRAW RAW 8 | ✅（`supported=v7,v8,v9`） | 冷开 968 ms（2560）/ 1048 ms（全幅）；编辑 738 ms（harness 上界；产品形态 ~2 ms，§4.9） | 系统框架 | 原生（现状） | Apple |
| CIRAW **RAW 9** | ✅ 原片支持；经 DNG 也支持（v9DNG） | **3177 ms**（2560；四轮 3026–3177） | 系统框架 + 模型资源 | 原生；需模型资源准备（首发 6.1 s） | Apple |
| **rawspeed** + DNG→CIRAW | ✅（ArwDecoder，逐像素 = LibRaw） | 解码段 **34–57 ms**；P1 首开 447 / 556 ms，缓存 DNG 374 / 482 ms | LGPL-2.1 | **C ABI shim（形态 B）**，165 行 + 头 68 行；静态链接需处理 LGPL relink | 活跃（2026-11-22 commit） |
| LibRaw | ✅ | unpack **618–638 ms** + demosaic 428/813 ms → 1081/1514 ms | LGPL-2.1 / CDDL | C API 直连（简单） | 活跃（0.22） |
| rawler（Rust `raw` crate） | 未测（lightcraft 未用它） | 未测 | LGPL-2.1 | Rust→C/Swift 桥（额外 FFI） | 活跃 |
| lightcraft 自研解码器 | 未测 | 未测 | MIT/Apache-2.0 | Rust 重写整条链 | 活跃（自有项目） |

### 5.3 判断

- **最快且体验最好的一套 = rawspeed 解码 + 「小档解码 + 目标尺寸直渲 + 100% ROI 分块」策略**。它同时满足三件事：解码段 34–57 ms（比 LibRaw 的 unpack 快 16×）、可把降采样放在 demosaic 之前（P1a 302–447 ms 首开）、以及首开比 CIRAW 快 ~2×（447/374 vs 968）。编辑等待**不是**它的差异化收益：产品形态下两者都 ~2 ms（§4.9）。
- **我们该抄什么**：① lumen-raw 的「预览档固定小尺寸 + 100% 分块 + 编辑后 tile 失效」；② Alcedo 的「2560 快速预览 / 8192 全分辨率 / ROI 三档渲染类型 + `DecodeRes` 在解码路径里降采样」；③ darktable 的「内嵌 JPEG 先上屏 → 后台补真预览」这一层（Lightamer 今天缺首屏 JPEG 快通道，`SmartPreviewStore` 只缓解码**结果**）。④ 从本次实测新增：**已解码平面的冻结是编辑等待的前提，而 CIRAW 现状已有这套 memo**（`CIContextPool` render-once；P0/P1 产品形态都 ~2 ms，§4.9）——rawspeed 的收益在首开，不在编辑。
- **rawspeed 的 C++ 边界不是「不可行」**：形态 B 已跑通（shim 165 行 + 头 68 行）、零异常穿出、字段与 T1 逐项一致。
- **映射到 Lightamer 的落点（仓库已有件，只读核对）**：
  - 渲染腿：`LightamerCore/Sources/Metal/CIContextPool.swift:228` `renderToTexture(longEdge:)`（已在用的「按目标长边直渲」，注释已记录「绝不渲 100MP 再缩」的内存理由）+ `:286` `renderRegion`（ROI 腿已存在）——本文 P0/P1 用的正是同一形态，**这两条腿不需要新写**。
  - 预览缓存：`LightamerCore/Sources/Decode/SmartPreviewStore.swift`（解码出口包 + LRU 上限 `previews.cacheMB`）→ DNG/小档预览落盘缓存可直接复用其形态（含 2560 cap 与盘路径约定）。
  - 缩略图腿：`App/Sources/Lightamer/State/SessionThumbnailRenderer.swift`（App 侧装配）+ 导入期缩略图——「内嵌 JPEG 先上屏」的快通道应挂在这一层。
  - 管线缓存与失效：`LightamerCore/Sources/Pipe/PipeCache.swift`（`enforceBudget` 预算/驱逐 + `PipeCacheKey` 键纪律）——马赛克档与预览档的缓存键须沿用同一纪律。
  - 交互降档先例：`EditorState.previewDenoiseBypass`（M3-1：拖动期临时降档、commit 自愈、旁路不进 history）——「拖动时用小档、松手出全档」可直接套这套三防线。
- **自写解码器的范围与代价**：如果要覆盖 raw-speed 的能力面，需要「容器解析（CR3/ARW/NEF/RAF/RW2/ORF/DNG/IIQ/3FR）+ 各压缩族（无损 JPEG / Sony ARW 有损 / Nikon HE / Canon CR3 / Fuji X-Trans）+ 逐机型 CFA/black/white/WB/matrix 元数据 + demosaic」。lightcraft 用一个 crates/raw 覆盖了其中一部分（tiff+dng+四个 demosaic）。**结论：不值**——rawspeed 已覆盖全部格式且比 LibRaw 快 16×，缺口只剩「C++ 边界」和「demosaic 归属」，后者用 DNG→CIRAW（P1b fit 374 ms）或自有 Metal demosaic 都能填。

---

## §6 风险与未验项

1. **P1 色彩未标定**：`mean_abs_diff 22.8/255`；`ColorMatrix1` 方向已独立证明为 XYZ→camera（rawspeed 矩阵 = LibRaw `cam_xyz`，逐元素 max diff 0；§4.5-5），写原值正确。#24 实现前仍需用 ColorChecker（仓内已登记缺件，`phases/evidence-legacy/plans/02-04/colorchecker-acquisition.md`）或受控光源做**色彩标定**（不是方向复核）。
2. **RAW 9 速度/资源**：冷进程 3.10–3.18 s/次（稳态渲染段 ~2.70 s = v8DNG 渲染段的 ~15×；四轮 3026–3177 ms）；首次模型准备 ~2.1 s 是一次性（系统缓存后新进程不再付），6.1 s 是更冷状态的首发观测；v9 名单仅 69 台（v8 为 465 台）——覆盖窄，不能作为格式覆盖方案。未测「模型资源是否需联网下载」（`CIRAWFilter.downloadResources(timeout:completionHandler:)` 存在）；离线场景必须假定不可用。
3. **V9 的既有缺陷未复核**：`RAWDecoder.swift` 注释记载 v9 输出经 color-managed CIContext 转换后绿通道偏移（G/R≈3.9×）。本次 P1 的 v9DNG 位图未做同口径颜色检查（只看了 hash 与速度）→ 若 #24 打算用 v9DNG 出片，必须重跑该探针。
4. **热测口径**：`clearCaches()` 只能清 CI 层缓存，RawCamera/Apple 内部解码缓存的清空不可控；热数字（P0 见 §4.2）可能仍含残留，仅作趋势参考。另：热行的进程内 e2e 从 `openFilter` **之后**起算（`open_ms` 单列：P0 ~52–57 ms、P1b ~14–15 ms），读「重开」时应把 `open_ms` 加回。
5. **p90 尾部噪声 + 轮间漂移**：个别冷行 p90 出现 2.2–7.2 s（系统级停顿，page cache/Spotlight 类）；结论一律用中位 + min。**跨轮系统性漂移**实测存在、且**双向**：另一 lane 的 `ApplicationsStorageExtension`（~30% CPU）在场时整轮冷行慢 8–12%（个别行 +21%）；归档轮之后又观测到整体快 7–27%（同一二进制、同一机器，原因未取证，标 [推断] 为连续多轮全量矩阵后的缓存/温度尾部）。本机另一 lane 的 `omp` argv 还会污染 `pgrep -fl` 的 heavy 检测（`bench-run.log` 的环境头里有该 argv，不含媒体/个人数据；`benchrun.py` 已改为 `pgrep -l`，只取 comm）。表内数字 = 提交进仓的 `bench.csv` 那一轮；相对结论（P1/P0 首开比值；编辑差已被 §4.9 推翻）比绝对值稳。四轮全量的 P0 基线分别是 894 / 909 / 968 / 992 ms（差 ±5%），P1a fit 427 / 447 / 458 / 468 ms。**独立复跑（2026-11-25）**：5/26 行超 ±15%，全部更快（P1 full −17%/−19%，M2 P0 fit −55%、M2 P1 −25%）；M1 的 P1/P0 比值保持 ~2.0–2.2×。
6. **未跑产品现状真值**：仓库有 `Tests/LightamerTests/QuickLookPerfProbeTests.swift`（`LA_QL_PERF=1`，2 样张 × 3 长边 × 冷/热）——需产品测试构建（重活，且会与基准互斥），且其口径走导出链、与本文 P0 的编辑路径不同。**决定：不跑，归 #26 或 orchestrator 排期**；本文 P0 用与产品同形的 `CIRAWFilter` + 缩放渲染调用，已能代表现状。
7. **M2 冷启动变体未单测**（M2 的冷值 ≈ M1 冷 + M2 热，属算术）。
8. **XCFramework 未构建**（配方见 §3），且 LGPL-2.1 静态链接的合规处置（relink 能力/动态库）需用户/法务决策。
9. **未做 Metal demosaic 原型**（可选 ≤30 min 项）→ GPU 路只有 Alcedo 的量级参考，无本机数字。
10. **用户实拍库未使用**：CC0 集已覆盖所需压缩类型（无损压缩 ARW），故全程未取用户文件（隐私红线零接触）。

### 6.11 自审修订记录（第一轮 + 第二轮）

> 本节是**修订史**：表里的数字是各轮当时的值（用于说明改了什么），**不是**当前结论值；当前值见 §0/§4。

第一轮独立自审（`evidence/SELFREVIEW.md`）= **4 error + 13 minor**。全部 error 已修并重跑：

| # | 问题 | 处置 | 影响 |
|---|---|---|---|
| E1 | P1 的 M1 从「已生成好的 122 MB DNG」起算，与 P0 不是同一用户动作 | 新增 **P1a 首开**（`benchlive`：shim 解码 → 内存 DNG → CIRAW，一次进程内完成，n=10）；原行为 **P1b 已缓存 DNG** 并标注含读盘 | P1 首开 427 / 684 ms（原报 358/617 是缓存命中值） |
| E2 | 自证 FNV 哈希跑在计时窗内（全幅 +240 ms、ROI 占一半） | 渲染完成立即打点，哈希窗后计时并单列 `hash_ms`；冷值 = 父墙钟 − `hash_ms` | 全幅 P0 1171 → 966 ms；ROI 11.1 → 1.9 ms；P1 编辑 236 → 11 ms（该轮值） |
| E3 | P2 没有渲染腿，与「同一条 render()」口径矛盾 | §4 口径明确写「P2 无渲染腿 = 解码+demosaic 下界」，§4.7 行名去掉「fit」，注明不含 `make_mem_image` | 无数字变化，口径已诚实 |
| E4 | P1 ds0 fit 归档 CSV 与报告差 31.7% | 修正后三轮全量复跑，报告数字改为与最终 `bench.csv` 同一轮；残差记入 §6.5 | 已对齐 |
| m6 | M2 的 min/p90 回退成 median；p90 实为 max | `bench` 输出真实 min/p90（n=10 的 p90 本质≈max，已在 §4 说明）；v9 行热身改 2 次；热测每 rep 都清缓存 | M2 数字改为真实分布 |
| m6' | **M2 每次都在渲染同一个编辑**（第一次后全被 CI 缓存命中，0.2 ms 的假数） | 每个 rep 换一个新曝光值（+0.5 EV 起、每 rep +2%），自证断言位图必须变 | 得到 P0 371 ms vs P1 11 ms 的真实分布（该轮值） |
| m8 | 色彩矩阵方向在三处注释里不一致（写反会过曝 3 档） | `dngwriter.h` 顶部写清方向与反例；`rawspeed_shim.h` 字段注释改为「rawspeed 原值」；`--invert-matrix` 标注为反例探针 | 防实现者踩坑 |
| m9 | shim 行数前后不一（135/150） | 统一为实测：`rawspeed_shim.cpp` 165 行 + 头 68 行；DNG 写入器 `dngwriter.h` 317 行单列 | — |
| m1 | 「像素访问器是模板」是事实错误 | 改为「访问器是普通成员函数，但到达它的唯一入口 `get()`/`operator->` 被封死」；另归档编译错误 `evidence/t2-compile-errors.log` | Q1 结论不变 |
| m10 | P0-vs-P1 粗差不在 bench.sh 里 | `bench.sh` 增加 `bench cmp` → `evidence/p0-vs-p1-cmp.txt` | 可复现 |
| m3/m4/m5/m12 | 日志覆盖/缺失、configure 无归档、warm 读数无出处 | T3 日志含好坏两腿；`bench-run.log` 重建；新增 `t1-build-facts.log`（warm read/decode + configure 输出）；`camera-list.txt` 含取数脚本 | — |
| m2 | 形态 A 的编译错误无归档 | `evidence/t2-compile-errors.log`（探针源码 + 命令 + 原文诊断，可 5 s 复现） | — |
| m11 | 解码段数字与体验数字并置 | §0 Q3、§5.3、§8 均加「解码段口径，非体验口径」 | — |
| m7 | §5/§6/§7 混用旧轮数字 | 全部改为本轮 CSV 值（894/966、427/684、341/396、1082/1516） | — |
| m13 | 报告头 HEAD 过期、evidence 未入仓 | HEAD 改为提交时的实际值；evidence 入仓政策见附录（`.gitignore:80` 排除，源码与脚本进 `spike-src/`） | — |

**第二轮自审**（`evidence/SELFREVIEW-2.md`）= 3 error + 11 minor。处置：N1 `benchlive` 补 `hash_ms`（P1a 冷值不再含校验哈希）；N2 §8 草稿按 §4 重写；N3 全量再跑一轮并与报告机械同源（`evidence/tables.py` 直接从 `bench.csv` 生成 §4 表）；m1–m11 逐条改（热行 `open_ms` 单列说明、`bench.sh` 的 `REPO` 路径修正使机器守卫真正生效、p90≈max 说明、DNG 双口径、`tables-4.md` 删除、`bench-run.log` 由脚本自身 tee、HEAD 换成实际提交 SHA）。

### 6.12 独立复跑修订（2026-11-25）

`evidence/RERUN.md` = 独立复跑 lane（HEAD `144a76b9`）的七项核对。error 与处置：

| # | 问题 | 处置 |
|---|---|---|
| R1 | **P0 M2 738 ms 不是产品形态**：harness 未冻结输入平面；产品 `CIContextPool` 有 render-once memo。归档的 738 vs 13（57×）是「未冻结 vs CI 命中」的错位对比 | §0 Q2 / §4.3 警告 / §4 关键读数 3 / §5.3 / §7.5 / §8 全部改写；新增 §4.9 产品形态对照（P0 1.69 ms / P1 1.76 ms） |
| R2 | **P0 M2 自身不可复现**：归档 738 ms，复跑同口径 329 ms（−55%）；CI 能否缓存 100MP 平面受内存压力影响 | 同 R1；§6.5 补记 |
| R3 | **RAW 9 的「新进程、进程内重复都一样」不成立**：首进程 rep0 4.94 s（ci_init 2.11 s），稳态 2.78–2.95 s；冷新进程 2.92–2.98 s | §4.5-3 / §6.2 改为冷/稳态拆分 |
| R4 | **T1 引用数字与归档文件不符**（写 100.8/43.1，文件 992.1/40.4） | §1 改为归档 992.1/40.4、复跑 438.1/36.1，并注明 page-cache |
| R5 | **ColorMatrix1 方向缺独立证明** | §4.5-5 加 LibRaw `cam_xyz`/`rgb_cam` 证明（max diff 0 / 1e-7） |
| m1 | 报告头 `2bdc4022` 不存在 | 改为 `8873c77c` |
| m6 | T1 引文不符 | 同 R4 |
| m7 | `bench.sh` 无条件覆写归档 | `BENCH_OUT` + `--quick` 不覆盖归档 |
| m8 | `heavy_procs` 抄入另一 lane 的 argv | `pgrep -l`（只取 comm） |
| m9 | v9 「~9–10×」无参照 | 改为「渲染段 ~15× / 相对 P1b 总时长 9.2×」 |
| m2/m3/m4/m10 | 已在当前版修复 | 复核通过，无改动 |

复跑还补了两条 Q1/Q3 证据：`operator*`/`.pointee` 也不导入（`evidence/rerun-t2-extra-routes.log`）；shim 的 decoder 保活与 rawspeed file-Buffer 契约存在潜在冲突（open 后不再调用 decoder，实测无害，生产化须去掉或保留 mapping）。

---

## §7 推荐实现路径（#24 草案，不展开成计划）

1. **形态 B 落地**：`rawspeed_shim.{h,cpp}`（本 spike 版本已验证）+ SPM/XCFramework 接入；`CameraMetaData` 进程内 `std::call_once` 加载自带 `cameras.xml`；异常零穿出。
2. **管线起点前移**：新增 `DecodedMosaic`（平面 + black/white/WB/matrix/CFA/crop）与 `rawprepare` 段；`DecodedImage` 增加马赛克形态（或并行的 decode 结果类型）。
3. **预览腿（先做，收益最大）**：rawspeed → 按目标档降采样马赛克（ds1/ds2）→ 未压缩 DNG（内存）→ `CIRAWFilter(imageData:)` v8DNG → 目标尺寸直渲。预期首开 302–447 ms、缓存命中 202–374 ms（现状 968 ms）。
4. **缓存**：DNG 落盘缓存（122/30.5/7.6 MB 三档）复用 `SmartPreviewStore` 形态；首建 = 解码 34–57 + 构建 33–52 ms（+ 落盘）。选落盘而非内存常驻的理由是 **RSS 与跨会话复用**（速度同量级，见 §4.7-5）。
5. **编辑等待**：产品形态下 P0/P1 都 ~2 ms（§4.9）——「预览档产物可复用」CIRAW 现状已有（`CIContextPool` render-once），不是 rawspeed 的增量收益。rawspeed 的增量在首开 302–447 ms（现状 968）与机型覆盖。
6. **导出档**：可选 v9DNG（RAW 9，3.10–3.18 s/张，稳态渲染 ~2.7 s）——先做色彩标定再启用。
7. **中期**：自有 Metal demosaic（替换 DNG 桥），目标把预览档的 374 ms 再压到 ~150 ms 级；届时可去掉 DNG 构建与 CIRAW 依赖。注意 §4.5-6 的教训：降档 binning 必须 GPU 化，否则 855 ms 级别的 CPU 开销会吃掉全部收益。

---

## §8 issue #24 评论草稿

> **Spike 结论（rawspeed 后端，2026-11-24；独立复跑 2026-11-25）**
>
> - **形态**：Swift 6 直接吃 rawspeed C++ 头**不可行**。`import` 与 `decodeRaw` 都通，但 `RawImage::get()` 被 interop 的 interior-pointer 规则禁用、`operator->` 不导入、像素访问器只能经那个被封死的指针到达、`RawImageData::data` protected ⇒ 读不到任何字段或像素；且 rawspeed 函数被导入为非 throwing，坏文件实测 `SIGABRT (134)`（"C++ exception handling detected but the Swift runtime was compiled with exceptions disabled"）。→ **必须 C ABI shim**（同 darktable）：本 spike 的 shim 165 行 + 头 68 行已跑通，坏输入返回 `code=2` 且进程存活，Swift 6 严格并发编译通过，马赛克与 LibRaw 逐像素相同（max abs diff 0）。
>
> - **速度（A7R5 CC0 85.9 MB ARW；用户动作→位图；冷启动 = 每测量独立进程，10 次中位；校验哈希在计时窗外）**：
>   - 现状 CIRAW v8：适配屏 2560 = **968 ms**，全分辨率 = **1048 ms**（独立复跑 868/939）；100% ROI 1.8 ms。
>   - rawspeed→DNG→CIRAW v8DNG：**首开 447 / 556 ms**（复跑 401/461）；**缓存 DNG 命中 374 / 482 ms**（复跑 337/391）；马赛克先降 1/4 = 351/239 ms、1/16 = 302/202 ms。
>   - **编辑等待不构成差异**：归档 harness 的 P1 13 ms vs P0 738 ms 是「CI 命中 DNG 平面 vs 未冻结 ARW 平面」的错位；产品 `CIContextPool` 对两者都冻结首次输入平面，补测 P0 **1.69 ms** / P1 **1.76 ms**（§4.9）。rawspeed 的收益在首开 ~2×。
>   - CIRAW 对输出尺寸不敏感（2560/1280/640 = 968/993/1001 ms）⇒ 降采样必须在解码前；rawspeed 解码段 **34–57 ms**（解码段口径，非体验口径；同文件 LibRaw unpack 618–638 ms）。
>   - **RAW 9 经 DNG 可用**（v9DNG 在 supported 列表，输出确实不同），但冷进程 **3.10–3.18 s**（稳态渲染 ~2.7 s = v8DNG 渲染 ~15×）→ 只可作导出档。另：A7R5 原片 `supported=v7,v8,v9`，v9 名单（69 台）里有 "Sony Alpha ILCE-7R V"——旧结论「A7R5 不在 CIRAW9 名单」是按 "ILCE-7RM5" 字符串匹配的假否定。
>
> - **正确性**：rawspeed 与 LibRaw 的马赛克**逐像素相同**（512×512 区域 max diff 0）。P1 与 P0 的 2560 位图 `mean_abs_diff 22.8/255` ⇒ 色彩尚未标定（`ColorMatrix1` 方向已由 LibRaw `cam_xyz` 独立证明为 XYZ→camera；需色卡做色彩标定）。
>
> - **独立复跑**：26 格中 5 格超 ±15%（全部更快），M1 的 P1/P0 比值保持 ~2.0–2.2×；M2 的 57× 不成立（§4.9）。
>
> - **取舍**：抄策略不抄解码器。最优组合 = rawspeed + 「小档解码 + 目标尺寸直渲 + 100% ROI 分块 + 预览产物可复用」（lumen-raw / Alcedo / darktable 三方同构）。自写解码器不值（rawspeed 已覆盖格式，解码段比 LibRaw 快 16×）。
>
> 详细报告：`.work/gsd/phases/rawspeed-backend/SPIKE.md`；复跑：`evidence/bench.sh`（`BENCH_OUT` 可改落点；独立复跑对照见 §4.9；源码副本在 `spike-src/`）。

---

## 附录：证据清单

| 文件 | 内容 |
|---|---|
| `evidence/bench.csv` / `bench-run.log` | 全矩阵（冷/热/M2/P2）+ 环境头；两者由同一次 `bench.sh` 生成（脚本自身 tee） |
| `evidence/rerun-bench.csv` / `rerun-bench.log` | 独立复跑（2026-11-25）全矩阵原始输出；归档 `bench.csv` 未被覆盖 |
| `evidence/rerun-compare.md` / `rerun-tables-4.9.md` | 归档 vs 复跑逐格对账 / §4.9 表（`spike-src/rerun_compare.py`、`rerun_tables.py` 机械生成） |
| `evidence/rerun-m2-product-shape.log` | 产品形态 M2（冻结输入平面）对照 |
| `evidence/rerun-v9-breakdown.log` | RAW 9 冷/热逐 rep 拆分 |
| `evidence/rerun-lrmat.log` | ColorMatrix1 方向独立核对（LibRaw `cam_xyz`/`rgb_cam`） |
| `evidence/rerun-q1.log` / `rerun-t2-extra-routes.log` | Q1 形态 A/B 重放 + `operator*`/`.pointee` typecheck |
| `evidence/RERUN.md` | 独立复跑七项核对（结论头 + SELFREVIEW-3 余项判定） |
| `evidence/bench.sh` / `benchrun.py` | 单命令复跑 |
| `evidence/t1-a7r5-meta.txt` | T1 字段（rsprobe 重建版） |
| `evidence/t2-form-a.log` | 形态 A：驱动成功 + 异常 abort |
| `evidence/t3-shim.log` | 形态 B：Swift 调用输出 |
| `evidence/xcheck.txt` | rawspeed vs LibRaw 逐像素 |
| `evidence/p0-vs-p1-cmp.txt` | P1 vs P0 的 2560 位图粗差 |
| `evidence/camera-list.txt` | CIRAW 各 decoder 版本的机型名单计数 + A7R5 命中 |
| `evidence/t2-compile-errors.log` | 形态 A 的编译错误原文（探针源码 + 命令，可 5 s 复现） |
| `evidence/t1-build-facts.log` | T1 的 warm read/decode + configure 输出 |
| `evidence/tables.py` | 从 `bench.csv` 机械生成 §4 表格（报告与 CSV 同源） |
| `evidence/SELFREVIEW.md` / `SELFREVIEW-2.md` / `selfreview-attempt.md` | 两轮自审 + `omp -p` 子实例不可用的记录 |
| `evidence/dng-props.txt` | DNG 元数据回读（AsShotNeutral/Black/White/Matrix） |
| `spike-src/` | shim、Swift 探针、两个 `Package.swift`、DNG 写入器、基准工具源，以及 `bench.sh` / `benchrun.py` 的副本（可复跑）；复跑对照工具 `m2-product-shape.swift` / `v9-breakdown.swift` / `lrmat.cpp` / `rerun_compare.py` / `rerun_tables.py` |

> **提交口径说明**：`.gitignore` 第 80 行把 `.work/gsd/phases/*/evidence/` 排除在仓外（evidence bundle 走私有 `lightamer-evidence` 仓的政策）。故本 lane 的 commit 只含 `SPIKE.md` + `omp-spike-summary.md` + `spike-src/`（含全部源码与可复跑脚本）；`evidence/` 下的原始数据留在工作区，按政策由 orchestrator 打包时处理。复跑不依赖 evidence：`spike-src/bench.sh`（配合 `spike-src/benchrun.py`）即可重建全部表。
