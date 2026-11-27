# RESEARCH — Whole-Chain Streaming in Row Bands（整链按行带流式处理调研）

日期 2026-11-27；只读 lane；方法 = 读源码原文，每条事实带 `文件:行号`。
基线：B1 闭环（550 测试），上限公式 `(预算 − 2×单块下限) ÷ 2`，Full/Export 上限 77,510,737 像素
（`waves/B1-b2-REPORT.md:77-82`）。上游引用皆指 `Lightamer-rust-spike/refs/dt-master @ 679d594f5d`。
本仓路径为仓库相对路径。外部引用省略机器公共前缀 `/Volumes/UNITEK/Documents/Development/`；
短路径锚点：dt 文件（`tiling.c`/`pixelpipe_hb.c` 等）∈ `Lightamer-rust-spike/refs/dt-master/src/develop/`；
LC 文件全写 `lightcraft/crates/` 起；`lumen/*.py` ∈ `lumen-raw/lumen/`；
`renderer/`/`edit/`/`io/`/`image/`/`decoders/` ∈ `AlcedoStudio/alcedo_studio/src/`；
`lutools/`/`Shared/` ∈ `RawLab/`；shim/rawspeed 文件 ∈ `Lightamer-rawspeed-spike/`。

## 1. Reference findings（参考项目怎样处理大图）

### 1.1 darktable：只有按模块分块，每模块输入输出两帧整图常驻——核实成立

- 主循环按模块串行，每模块输出申请整帧：`…/refs/dt-master/src/develop/pixelpipe_hb.c:2373-2378`
  （`bufsize = bpp * roi_out->width * roi_out->height`，亲验），输出占一条缓存行
  （同文件 `:2641-2646` `dt_dev_pixelpipe_cache_get(pipe, hash, bufsize, …)`，亲验）。
- 分块决策只在单模块内：放得下（`dt_tiling_piece_fits_host_memory`，同文件 `:1857-1859`）
  则整图 `process`，放不下且允许则 `process_tiling`（`:1876-1891`，亲验读 `:1855-1900`）；
  还放不下就整图硬算并打警告 `"processed without tiling even if memory requirements are not met"`
  （同文件 `:1906-1919`，亲验）。
- **两帧整图常驻是注释原文**：`…/src/develop/tiling.c:610-616`
  `/* correct for size of ivoid and ovoid which are needed on top of tiling */`，
  `available` 先减去输入整帧 + 输出整帧 + overhead（亲验）。tile 输入从整帧 `ivoid`
  逐行拷出（同文件 `:743-755`，`ioffs` 注释 `offsets of tile into ivoid and ovoid`，亲验读 `:689-763`）。
- 默认分块请求：`tiling.c:1903-1921`（亲验），`factor = 1 + ioratio`（`:1912`），
  `TILING_FULL_ROI` 模块 `overlap = 4`（`:1920`）；ptp/roi 分流按区域逐位相等
  （`:1176`，grep 亲验；定义 `imageop.h:94`，12 个几何模块置位，grep 亲验）。
- **缩略图/预览/导出同样整帧**：五种管线只差缓存行数与预分配，共用同一递归主循环。
  `pixelpipe_hb.c:219-272`（亲验）：export/thumbnail 预分配整帧
  （`sizeof(float)*4*width*height`，`:225-226`/`:237-238`），preview 12 行（`:255-256`）、
  preview2 5 行（`:263-264`）、full 64 行（`:271-272`）；缓存"行"= 整帧 float buffer
  （`pixelpipe_cache.h:60-63,72`，亲验；
  `entries==2` 的管线只在 0/1 行交替，`pixelpipe_cache.c:241,250`，grep 亲验）。
- **整链行带：没有。** 双证据：① 关键词 grep 扫 `pixelpipe_hb.c` + `tiling.c` + `pixelpipe_cache.c`：
  亲跑 pattern（`strip|scanline|band[^a-z]|stream.*pipe|pipe.*stream`）仅 1 命中——`:3956`
  filmstrip（胶片条 UI）注释；复审以更宽 pattern（含裸 `stream`）复跑，另得 4 处 `downstream`
  （`:772,813,878,961`，缓存失效语义）——两轮零像素流语义。`develop.c` 同理：亲跑 4 命中
  （`:1175,1195,2581,3361`，UI/DB 注释）+ 复审补 `:3044`（upstream），零像素语义。
  ② `src/develop/` 全列无 strip/band/stream 相关文件
  （`ls` 亲列：tiling/pixelpipe/develop/imageop/blend/masks 等）。最接近的只是单模块内的
  OpenCL 行带切分（`tiling.c:1786-1800` 的 `tile_height/valid_rows/num_tiles` 行带高度数学，亲验），
  仍落在单模块分块文件内，不贯穿链。
- **上限**：无像素硬上限——分块尺寸纯由当时可用内存算出（`tiling.c:610-623`，亲验），
  吻合检查对可用内存（`:1923-1934`，亲验）。超限行为 = 分块 → 还不够 → 整图硬算 + 警告
  （无拒绝路径；与我方 `FrameTooLarge` 前置拒绝不同，见 §2.5）。

### 1.2 LightCraft（Rust）：整帧管线，无整链流；超限靠分级与拒绝

- 输入输出全是整帧 `Vec`：`lightcraft/crates/raster/src/lib.rs:52-65`
  （`Image { width, height, data: Vec<T> }` + `vec![…; w*h]` 一次分配，亲验）；
  渲染三入口全是整帧引用：`lightcraft/crates/pipeline/src/lib.rs:708` `render(&Rgb32f)`、
  同文件 `:714` `render_cached(&Arc<Rgb32f>)`（亲验 `:706-716`）、`:478` `plan(&Rgb32f)`（亲验）。
- 无整链流，双证据：① `lightcraft/crates/pipeline/src/`、`lightcraft/crates/raster/src/` 全列
  无 stream/strip/scanline/tiling 模块（scout 全列 + 我亲验 `ls crates/` 29 个 crate 与
  `grep -i tiling|band` 零渲染语义命中，仅"频带/色带"他物）。
  ② 签名全是 `&Rgb32f → Rgb32f/Rgba8` 整帧进出（上条行号）。
- 最接近的三处局部（都不贯穿链）：① **窗口渲染**——`RenderRequest.window: PixelWindow`
  （`lightcraft/crates/pipeline/src/lib.rs:159-161`），`plan()` 对 dehaze 空气光用 384px 代理
  估计全帧（`AIRLIGHT_PROXY_EDGE`，同文件 `:474`，亲验），源仍是整帧，省的是输出端计算；
  ② **GPU 行带 dispatch**——`lightcraft/crates/gpu/src/render.rs:150` `BAND_PIXELS = 4<<20`，
  同文件 `:833-834` 按行带切 dispatch（亲验），只是单个 kernel 防看门狗的提交切分，
  输入输出 buffer 仍整帧；③ **AI 去噪 overlapping-tile**
  （`lightcraft/crates/denoise-core/src/run.rs`，scout 读）与去噪产物按 `STRIP_ROWS=128` 分条存
  （`lightcraft/crates/denoise-core/src/product.rs:26`，亲验 `:20-30`），都是模块/产物内部行为。
- 上限数字（亲验原文）：渲染输出 `MAX_OUTPUT_SIDE=65_535`、`MAX_OUTPUT_PIXELS=1<<30`
  （`lightcraft/crates/pipeline/src/lib.rs:190-192`），超限 `check_output_size` 直接拒绝
  （同文件 `:196-199`）；内存预算 RAM/4 钳 [256MB, 1.5GB]
  （`lightcraft/crates/engine/src/memory.rs:25-31`），缓存 1/2、解码门 1/4、GPU 池 1/8、
  导出门 2×预算（同文件 `:14-24,95,182-195`）；导出放大预检 `too_big_for_memory`
  （`lightcraft/crates/engine/src/export/prepare.rs:184-193`，亲验），工作集公式 = 源 12B/px +
  输出 36B/px（同文件 `:199-208`，注释称 24MP 导出峰值约 1.2GB，亲验）；
  AI 去噪单图 110M 像素（`lightcraft/crates/denoise-core/src/run.rs:17`，grep 亲验）；
  导出作业持导出门并发（`lightcraft/crates/engine/src/export/batch.rs:100-103`，grep 亲验）。
  超限行为 = 拒绝渲染/解码（`TooLarge` 变体，`lightcraft/crates/codecs/src/lib.rs:65`，grep 亲验），
  或排队等待（`WorkGate::acquire` 按字节等，`lightcraft/crates/engine/src/memory.rs:137-145`，
  scout 读），GPU 失败回 CPU（`lightcraft/crates/gpu/src/lib.rs:12-17` 文档 + `BROKEN` 进程级
  sticky，亲验）——**没有"放不下就流式的路径"**。

### 1.3 lumen-raw（Python）：整链可流，是本调研最完整的先例（甲+丙+代理统计全有）

- **分流总闸** `lumen/large_image.py:177-226`（亲验全文 226 行）：无空间操作 →
  按 64 行 strip 把 `engine.process` 流过整链（`:224`）；有空间操作但放不下 →
  按 `side=block_size(margin)` 分块调 `engine.process_region`（`:215` 双循环）；
  放得下 → 整帧（`:191-192`）。
- strip 生成器 `:38-39`（`STRIP_ROWS=64`，`:10`，亲验）；内存判据 `FRAME_BYTES=100`
  （61MP 实测峰值 55–76 B/px 取整，`:134-136`，亲验），`fits_in_memory`
  （`h*w*100 ≤ 可用×0.85`，`:138-141`，亲验）；块边长钳 [512, 8192]
  （`:143-148`，亲验）。
- **margin 块精确性**：`engine.py:1342-1350` `process_region` docstring 原文
  "the block matches the whole-frame render"（亲验），margin 由 `spatial_margin`
  按 denoise/clarity/texture/sharpness 逐项累加（`:910-923`，亲验）。
- **代理统计（全局模块不断流的先例）**：dehaze 统计取自 3000px 缩略图
  （`large_image.py:206-210`，亲验），local tone mapping 上下文取自低分辨率整帧
  （`:196-200`，亲验）；主入口判据 `source.nbytes > MAP_BYTES(256MB)` 且缓存装不下则转流式
  （`engine.py:1222-1237`，亲验）。
- **磁盘后备（乙的先例）**：`allocate()` 超 256MB 用 `memmap` 落 `LumenRAW-cache/`
  （`:23-36`，亲验）；TIFF 导出按 strip 流式写
  （`engine.py:1745-1746` `rowsperstrip=STRIP_ROWS`，grep 亲验）；GPU 两条后端按
  `STRIP_BYTES=48MB` 切行 dispatch（`cuda.py:30,377`、`metal.py:36,499`，grep 亲验）。
- **上限**：硬上限 4 亿像素，超了直接抛错（`:8,12-15`，亲验）——流式不是无限大图的解，
  只是把上限推高一个量级。

### 1.4 AlcedoStudio（C++）：无整链流；分块只在去马赛克 NN 装配与 ROI 预览

- 导出恒整帧解码：`renderer/pipeline_scheduler.cpp:218-222`
  `FULL_RES_EXPORT = DecodeRes::FULL, require_host_output=true`（亲验 `:150-224`）；
  执行器整帧进整帧出：`edit/pipeline/pipeline_executor.cpp:108-128`
  （`Apply/Render: shared_ptr<ImageBuffer> → …`，亲验）。
- 导出读整块 `CV_32FC4`，只敢省一次 clone：
  `io/image/image_writer.cpp:664-675`（亲验），注释原文 "FULL_RES_EXPORT buffers can be
  multi-hundred MB; cloning before downscale doubles peak memory"——反证持有整帧。
- "无整链流"三证据：① `src/` 一级 20+ 目录、`renderer/` 仅 1 文件（`ls` 亲列），
  无 stream/tile/strip/band 模块；② `decoders/;io/;image/;renderer/` 精搜
  `strip|rowsperstrip|tile` 零图像流语义命中（scout 精搜 + 我亲跑 `io/` 仅 EXIF 常量命中）；
  ③ 上两条整帧正向反证。分块只出现在 Neural demosaic 的 GPU tile 装配
  （`neural_tile_jobs.hpp`，亲验头 60 行：纯去马赛克几何）与 AI denoise tile 循环
  （落整块平面，`ai_denoise_model_session.cpp:160` `AssembleDenoisedPlane`，grep 亲验）；
  demosaic tile 逐 job `copyTo` 拼回整帧输出（`cuda_sensor_demosaic.cpp:254`，grep 亲验）。
- 上限数字：**没找到**像素上限（精搜零命中 + 导出整帧反证）。

### 1.5 RawLab（C++ 核心 + 各端）：只有 HDR 导出链是整链流，主链整帧

- **HDR 流式导出链**（行源 → 256 行 strip → 128 行 tiled 落盘 → 128 行 band 渲染/编码，
  亲验）：`lutools/src/core/hdr_stream.cpp:22-23`
  （`decodeRows=256, tileEdge=128, cachedTiles=32`）；`stageSource` 按 256 行解码 strip、
  逐 strip `editHDRPixels`、按 128 行 tiled 带落盘（`:502-544`，亲验 `:504-560`，
  内存准入按带算 `:504,543`）；`renderStreamFiles` 按 `bandFirst += tileEdge` 逐带渲染
  追加写盘（`:615-643`，亲验 `:606-647`）；入口 `exportTiledStream`
  （`hdr_pipeline.cpp:1109`，grep 亲验）。
- **上限**：HDR 流拒 128MP 以上（`streamScratchBytes`，`hdr_stream.cpp:649-657`，
  `:651` `width*height > 128000000 throw`，亲验）。
- 主链整帧，三证据（①③亲验，② scout）：① `Shared/` + `lutools/src/` 目录亲列 +
  我亲跑精搜（`tiling|tile|strip` 在 `RawLabNative*` 零图像语义命中，仅 `ViewportTileCache`
  显示缓存）；② scout 精搜 `lutools/src` 主 render 路零 strip-chain 命中；
  ③ `photo_effects.h:20-28` 原文 "A strip uses the full output dimensions"
  （亲验）——此处的 strip 仍是全幅宽语义。Rendered DNG 按 64 行 strip 写盘
  （scout 读 `rendered_dng.h:17-18`）只是**写盘格式**分 strip，上游仍需整幅或行回调供数。
  小波去噪 tile 循环注释 "避免保留跨越整图宽度的原始行带"（`wavelet_denoise.cpp:542`，
  grep 亲验）反证常态持有整图宽行带。预览是金字塔 tile（边长默认 1024，
  `lutools/src/core/viewport_pyramid.h:49`，grep 亲验）+ 112MB/36 块 LRU
  （`Shared/RawLabKit/ViewportTileCache.swift:13`，亲验头 60 行），只管显示。

### 1.6 横向对比

| 项目 | 整链流？ | 机制 | 上限（源码原值） | 超限行为 |
|---|---|---|---|---|
| darktable | ❌ 无 | 单模块 tiling，两帧整图常驻 | 无像素上限（可用内存定） | tiling → 硬算+警告 |
| LightCraft | ❌ 无 | 整帧 + 窗口渲染 + GPU dispatch 切带 | 输出 1Gpx / 边 65535；预算 RAM/4 | 拒绝 / 排队 / 回 CPU |
| lumen-raw | ✅ 整链可流 | 64 行 strip / margin-block / memmap / 代理统计 | **4 亿像素硬上限** | 抛错（裁切或降倍率） |
| AlcedoStudio | ❌ 无 | demosaic-NN tile 装配（拼回整帧） | 没找到 | 整帧持有 |
| RawLab | ⚠️ 仅 HDR 导出链 | 行源→256 行 strip→128 行 band 落盘/渲染 | HDR 流 128MP | throw |
| 我方 B1 现状 | ❌ 无 | 单模块 ptp 分块 + 前置拒绝 | Full/Export 7751 万像素 | `FrameTooLarge` 拒绝 |

## 2. Our full-frame assumptions（我们的管线哪里假设了整帧）

按渲染数据流逐处列出；改动量级：小 = 一函数内， 中 = 跨 2–3 文件，
大 = 新执行器/新语义。好消息（零改动可复用的）列在 §2.8–2.9。

### 2.1 调用方输入是整帧（`RenderRequest.input: &Frame`）

`lightamer-pipeline/src/render.rs:98-115`：`input: &'a Frame`（调用方整帧画面，`:106`），
`final_out: GeomRoi`（`:112`）。`forward()` 从整帧终点区域反推整链几何
（`render.rs:364` 调 `chain::forward`）。**改动（中）**：流式入口需要"按需区域输入"
（§5），`forward` 本身可复用（它只算区域，不碰像素）。

### 2.2 每个节点的输出是整帧分配

- 不分块：`run_untiled` 按 `geo.output` 整区分配输出（`render.rs:623-677`，分配在 `:632`），
  调一次 `process`（`:663-671`）。
- 分块：`run_tiled` 同样先分配**整帧输出**（`:687-735`，分配在 `:698`），另加一对按最大块的
  暂存（`:715-717`）。**改动（大）**：band 执行器逐输出带分配/复用小平面，
  `run_untiled`/`run_tiled` 需 band 变体或被新执行路径替代。

### 2.3 缓存里是整帧

`cache::PlaneCache` 存 `Arc<SharedFrame>` 整帧平面（`cache.rs:167-174`），
字节上限 = 预算一半（`render.rs:275-280`），准入/淘汰按整帧字节（`cache.rs:249-271`）。
键是整链整帧键（`chain_keys`，`cache.rs:122-157`，无带维度）。
**改动（中）**：选项有三——① 流式轮不写缓存（小，命中率归零但正确）；
② band 键（整帧键 + 带序号，小平面天然适配字节/槽位 caps，中）；
③ 只缓存代理统计与几何（小）。推荐 ① 起步（§3.7）。

### 2.4 分块是在整帧输出里按块填

- 决策扣掉两帧整帧：`tiling::decide` 的 `resident = 2×frame + overhead`
  （`tiling.rs:113-116`，`:115`），`singlebuffer = max(可用/factor, 下限)`（`:119`）；
  只做 ptp（逐位相等才分块，`:91-98`），roi 变体答 `NoTiling`（`docs/PIPELINE.md:169-171`）。
- 执行从**整帧上游平面**拷含重叠的块输入（`fill_tile_input`，`render.rs:775-824`，
  注释原文 "out of the full upstream plane"，`:775-776`），好块拷回整帧输出
  （`copy_good_part`，`:914-922`）。**改动（中）**：band 规划可复用 `decide` 的收缩/对齐数学，
  但"整帧输出 + 整帧上游"的前提要换成"带输出 + 带输入链"；且几何节点带要走 roi 变体——
  那是 B1 遗留缺口（PIPELINE.md 写明 ptp-only），流式波必须顺手补或绕行（§3.5）。

### 2.5 渲染开始前的占用核对是整帧足迹

`check_footprints`（`render.rs:541-565`）：节点 0 需 输出 + 2×下限，
其余需 输入 + 输出 + 2×下限（`:549-555`），超了 `FrameTooLarge`（`:556-562`）；
`max_frame_bytes = (预算 − 2×下限) ÷ 2`（`:318-336`）。空链不过此门
（`render_empty` 直接分配，`:469-498`，超预算走 `OutOfBudget`）。
**改动（小）**：加 band 足迹分支（带高 × 宽 × 16B × 在飞带数 ≤ 预算），
`FrameTooLarge` 保留作"连一带都跑不了"的拒绝。

### 2.6 引擎保留的结果是整帧拷贝

`run_render_job` 成功后 `frame.as_slice().to_vec()` 整帧拷贝出预算
（`lightamer-engine/src/render.rs:725-732`），存 `RenderedImage { pixels }`
（同文件 `:231-243`），每（照片，实例）留最新一代，无字节上限
（`waves/VERIFY.md:351-352` 塔台已登记此缺口，缩略图波之前必须加）。
**改动（中）**：流式渲染的交付面要换——Full 预览仍需整帧（内存装得下才流式？
  不，§3.8：Full/Export 才需要流式；交付改为分片回调/直接写文件，
  不经过 `RenderedImage` 整帧拷贝）。

### 2.7 引擎的输入来源是整帧

`InputSource::fetch(photo) -> RenderInput { frame: Frame, … }`
（`lightamer-engine/src/render.rs:126-133,166-176`），作业线程整帧取回
（`:666`），`final_roi_for` 按整帧 extent 定终点区域（`:530-550`，`:681`）。
**改动（小–中）**：加 `fetch_region(photo, roi)`（§5；默认实现 = 整帧取回后裁，
  B2/B4 的整幅马赛克走默认实现即可）。

### 2.8 好消息一：`process` 的平面视图与帧大小无关（零改动）

`IopModule::process(data, &Plane, &mut PlaneMut, rin, rout)`
（`lightamer-iop-traits/src/module.rs:103-117`）：借来的行视图 + 区域，
band 就是小一号的 tile——分块执行已经证明模块不关心平面是不是整帧
（`process_tile`，`render.rs:828-880`）。**点运算与 halo 模块零改动即可被 band 调用。**

### 2.9 好消息二：几何链已支持任意区域（零改动）

`chain::forward` 从任意 `final_out` 反推每节点输入区（`chain.rs:195-215`，
`geos[i].output == geos[i+1].input`）；`backward_check` 顺推核对
（`:228-256`）；`roi_in/roi_out` 默认恒等（`module.rs:84-94`）。
**输出带的输入带可直接算出，无需新几何代码。**

## 3. Design options（设计选项）

### 3.0 公共前提与术语

- 像素格式恒 16B（RGBA f32），`plane_bytes`（`render.rs:513-527`）。
- **空间支持（support）** = 输出一带需要读入的输入增量，已有两个现成表达：
  ① `roi_in(data, rout)` 逐模块精确回答（`module.rs:91-94`）；
  ② `tiling().overlap` 像素 halo 声明（`lightamer-iop-traits/src/tiling.rs:24`），
  dt 先例：管线按此 halo 提供输入（`blurs.c:605-612` 注释原文，亲验）。
- **全局模块** = 输出任一像素依赖整图统计（直方图自动曝光、双边/局部拉普拉斯大核、
  deflicker 类）。dt 处理方式：`process_tiling_ready = FALSE` 整图硬算——
  drago（"needs the maximum L-value of the whole image"，`globaltonemap.c:560-565`，亲验）、
  bilat 局部拉普拉斯（`bilat.c:304-308`，亲验）、highlights segments/opposed
  （`highlights.c:1074-1078`，亲验）、rawprepare detail-mask（`rawprepare.c:886-891`，亲验）、
  liquify 无 `ALLOW_TILING`（`liquify.c:305-311`，亲验；门控 `imageop.c:2540-2546`，
  `_piece_may_tile`，`pixelpipe_hb.c:1494-1500`，亲验）。
  dt 的"绕法" = 不绕：整图两帧能装下就硬算（见 §1.1 超限行为），装不下也硬算 + 警告。
  我方不能抄（我们有硬预算 + 前置拒绝），只能走 §3.6 的两条路。

### 3.1 甲：整链按带（推荐，见 §3.7 的起步收窄）

**做法**：对每个输出带（整宽 × H 行），从链尾 `roi_in` 逐级反推每节点输入带
（§2.9 现成），深度优先从链头算到链尾：节点 i 消费节点 i−1 的输出带（含 halo），
产出自己的带；用完即放，只保留正在被消费的带。每带独立走一遍链（`cancel` 每带查一次，
沿用每节点/每块检查的纪律，`render.rs:338-347`）。

- **内存峰值**：设输出带高 h（行），链长 N，全宽 W，链累计 halo 上游共 H 行
  （各节点 halo 经缩放链折算后求和）。在飞平面 = 每节点一带（输入带被消费时与输出带共存，
  故 ≈ N+1 个，高度从下游 h 向上游 h+H 递增）。峰值 ≈ `(N+1) × W × (h + H/2) × 16B`。
  例（3:2 画幅，200MP → W≈17320）：N=21，W=17320，h=64，H=200 →
  22×17320×164×16 = 999,848,960B ≈ **1.0GB**，相对整帧两帧 6.4GB 降约 6×。
  带高自适应：`h = clamp(预算×0.5 ÷ ((N+1)×W×16B) − H, 16, 256)`。
- **接缝**：重叠必须盖住每节点的空间支持——由 `roi_in` 反推天然保证（输入带 = 精确需要区，
  不是"输出带 + 固定 halo"近似）；好块只取输出带（dt 同款 good-part 语义，
  `docs/PIPELINE.md:274-277` 转引 `tiling.c:780-790` + 我方 `copy_good_part`，
  `render.rs:914-971`）。
  **逐位恒等**：ptp 零-halo 模块与整帧逐位同（`process` 纯函数，同输入同输出）；
  halo 模块在好块内逐位同（输入区逐位同 → 输出逐位同；dt 分块同款语义，
  B1-a 已登记接缝容差待定 `VERIFY.md:315`，band 波顺手定：好块内零容差）。
- **缩放/旋转/裁剪节点**：`roi_in` 逐带精确回答（§2.9），downscale 带变高（内存公式 H 项吸收）；
  **旋转 90°是病态**：输出一带 ↔ 输入一列（整高），band 退化为整帧。
  对策：几何节点处切 2D block（即丙，§3.3）或拒绝流式回 `FrameTooLarge`。
  注意 B1 分块只做了 ptp，roi 变体是遗留缺口（§2.4）——几何带与它是同一缺口，波内二选一。
- **全局模块**：打断流，见 §3.6。
- **缓存**：起步不写 band 缓存（§2.3 选项①）；band 键是可选增强。
- **需要它的实例**：Full 与 Export（§3.8）。

### 3.2 乙：按模块整帧、带式落盘（mmap 整帧 + 顺序触页）

**做法**：模块仍以整帧语义调用（`process` 的 `rin/rout` = 整帧），但 `Frame` 的存储换成
mmap 磁盘后备（lumen `allocate()` 先例，`large_image.py:23-36`，亲验）：
RSS 只留被触及的页，OS 把其余页换到临时文件。模块按行顺序读写 → 缺页按带流；
`FrameTooLarge` 的"预算"换成"磁盘配额 + RSS 工作集"双门。

- **内存峰值**：RSS ≈ 工作集（当前模块正在读写的行窗 + OS 预读），磁盘 = 在飞整帧平面
  （输入 + 输出 + 缓存命中帧，200MP 下 3.2GB/帧 × 2–3 帧 ≈ 6–10GB 临时文件）。
- **接缝**：零（语义就是整帧，模块看到的地址空间连续完整）。
- **代价与风险**：① 非顺序访问的模块会抖动——旋转/列访问每行触发整帧缺页，
  比甲慢 1–2 个量级且无上限；② 缓存整帧 mmap 化后"淘汰"语义变成"解映射"，
  `SharedGrant` 预算模型要重写（`budgeted.rs:83-128` 按字节计价的前提动摇）；
  ③ 磁盘配额、清理、加密盘/机械盘性能都是新运维面；④ `Frame` 改存储后端是 L0 级改动
  （`Vec<f32>` → 枚举 Vec/Mmap），`row/rows/view` 全要过一遍。
- **结论**：接缝最小，但把内存问题换成磁盘 + 抖动问题，且动 L0。只建议作甲的**回退腿**：
  甲在某节点退化（旋转/全局模块）时，该节点用 mmap 整帧跑一次，而非全链乙化。

### 3.3 丙：lumen 式混合（点运算 strip + 空间运算 margin-block + 代理统计）

**做法**：照抄 `large_image.py:process`（`:177-226`，亲验）的三路分流：
点运算链 → 甲（strip=64 行）；含空间运算 → 2D block（边长 `block_size(margin)`，
`:143-148`，块 + margin 占可用 1/4，边钳 [512, 8192]）；全局统计 → 低分辨率整帧代理
（tone context `:196-200`、dehaze 3000px `:206-210`）。输出帧磁盘后备（`allocate`，`:23-36`）。

- **与甲的关系**：丙 = 甲 + "几何/大 halo 节点自动降 block" + "全局模块自动降代理统计"。
  block 是 band 的 2D 推广：旋转不再病态（block 经旋转仍是 block，只是换位置/形状，
  `roi_in` 照算）；大 halo（diffuse overlap 可达 1024 行，`diffuse.c:790-812` 亲验，
  `MAX_NUM_SCALES=10`，`:48`）在 strip 下吃掉整带、在 block 下只吃边。
- **代价**：规划器比甲复杂（strip/block 双模式 + 模式切换点 + 代理统计管线），
  实现量约为甲的 1.5×；但**决策逻辑可全部自动化**（按 `overlap` 与 `roi_in` 形状选模式），
  用户无感。lumen 用 226 行 Python 落完中枢（含内存探测），Rust 实现估计 800–1200 行。
- **结论**：丙是甲的完整体。起步波做甲（点运算 + 小 halo 白名单），
  第二波升丙（自动 block + 代理统计）。估算按两波分开给（§6）。

### 3.4 选项对比表

| 维度 | 甲：整链按带 | 乙：mmap 整帧 | 丙：lumen 混合（甲超集） |
|---|---|---|---|
| 内存峰值（200MP, 21 节点） | ~1.0GB（公式 §3.1） | RSS ~0.1GB，磁盘 ~10GB | 同甲（strip 段）/~2GB（block 段，上限） |
| 接缝/恒等 | 好块内逐位同 | 完全逐位同 | 同甲；代理统计段非逐位（精度门） |
| 模块改动 | 零（白名单内） | 零 | 零 + 代理统计回调（新） |
| 管线改动 | 大（新执行器） | 大（L0 存储 + 预算模型） | 大+（规划器 1.5×） |
| 旋转/几何 | 病态（需切 block/拒绝） | 天然支持（抖动风险） | block 覆盖 |
| 全局模块 | 打断（§3.6） | 天然支持 | 代理统计覆盖 |
| 磁盘依赖 | 无 | 必需（~10GB） | 输出帧可选 mmap |
| 先例 | lumen strip 段 | lumen `allocate` | lumen 全套 |

### 3.5 几何节点的配合（甲/丙通用）

- `roi_in` 已精确支持 crop/scale（取整规则 `PIPELINE.md:26-38`，`to_scale` 非分块规则；
  分块远边保护归决策层）。band 经 downscale：输入带更高，公式 H 项吸收。
- 旋转/翻转（dt `TILING_FULL_ROI` 12 模块，`imageop.h:94` + tiling.c:1176 分流）：
  甲退化（带↔列），丙用 block。B1 roi-variant 分块未做（§2.4）——流式波必须先补
  roi 路的"块输入区 = roi_in(块输出区)"（与 band 输入区是同一公式，一次实现两处用）。
- 建议：起步白名单排除几何模块（B1 无真实几何模块，B8/B9 才来，时间站在我们这边）。

### 3.6 全局模块：退回整帧 vs 代理统计

- **dt 的绕法 = 不绕**：整图硬算（§3.0 五组 `process_tiling_ready=FALSE`），
  靠"物理内存够大"蒙混。我方硬预算下不可抄。
- **lumen 的绕法 = 代理统计**（§1.3）：dehaze 用 3000px 缩略图统计，tone context 用低分辨率整帧；
  LC 同款：`AIRLIGHT_PROXY_EDGE=384`（`lib.rs:474`，亲验）。**这是业界通行解。**
- **建议**：两档——① 帧 ≤ 上限：该节点退回整帧跑（band 执行器内 einzel 整帧调用，
  前后 band 暂停，内存峰值 = 整帧两帧，门控通过才进）；② 帧 > 上限：
  用代理整帧（长边 ≤2048，`fits_in_memory` 判据 lumen `:138-141`）算统计，
  再逐带用统计渲染。精度门：代理 vs 整帧统计的渲染差，mean < 0.5 LSB8（LC 等价门
  `MEAN_LSB=0.5`，`FRAMEWORK.md:131`，转述已有调研结论）——**门值待用户定（§7.4）**。
- P0 的 21 模块里：exposure deflicker（直方图，`exposure.c:107-110`）、
  highlights segments/opposed、demosaic-RCD 以外的（passthrough 非全局）是候选全局模块；
  bilat/diffuse/tonemap 不在 P0（21 模块清单 `CORE-DESIGN.md:72-74`），大 halo 风险后移。

### 3.7 缓存语义与恒等性（甲/丙）

- 起步：流式轮不写缓存（正确优先；`insert` 跳过，`peek` 仍可读整帧缓存——
  同一设置先整帧后流式时命中，键不变）。
- 增强（可选）：band 键 = 整帧键 + 带序号 + 带几何；`PlaneCache` 字节/槽位 caps 天然适配小平面
  （`cache.rs:249-271`）。但 band 缓存的命中场景只有"同设置重渲同一带"（导出重试），价值低，
  建议不做。
- 恒等性：§3.1（好块内逐位同）+ §3.6（代理统计段精度门）。双跑逐位（B1 验收④，
  `PLAN-B.md:202`）在 band 轮同样要求：同输入 → 同字节。

### 3.8 哪几种实例需要它

- **Full 与 Export 需要**：上限同为 7751 万像素（`B1-b2-REPORT:77-82`），
  用户 61MP 占 77.7%，接片/1 亿像素机身超限。Export 更需要（原分辨率出片，
  不能降采样糊弄）。
- **Preview/Thumbnail 不需要**：上限 2265 万/1401 万像素，但输入本就是缩小后画面
  （`VERIFY.md:336`：解码波保证预览管输入不超过上限，超了切 Full 管按区域渲染）。
  流式波不碰 Preview/Thumbnail 实例（`kinds.rs` 配额零改）。

## 4. Module interface（模块接口要加什么）

### 4.1 声明一：空间支持——已有，不加新回调

- `roi_in(data, rout)` 已精确回答"输出带要读多少输入"（`module.rs:91-94`），
  band 规划逐带调用即可；`tiling().overlap` 是 halo 的像素声明
  （`iop-traits/src/tiling.rs:24`），dt 语义 = 管线按此提供 halo 输入
  （`blurs.c:605-612`，亲验）。**建议：复用二者，加一条一致性测试**
  （`roi_in` 反推区 ⊇ `overlap` halo 区，否则模块实现自相矛盾，`debug_assert` + 测试钉死）。
- 唯一缺口：`overlap` 在 `tiling()` 里与 `rin/rout` 一起给，band 规划需要"与带位置无关的
  halo 上界"来定带高——调一次全帧 `tiling()` 取 `overlap` 即可（dt `bilat.c:272-289`
  的 `overlap = ceil(4σ)` 本就与位置无关，亲验）。零接口改动。

### 4.2 声明二：全局统计——加一个，默认本地

dt 用 `process_tiling_ready=FALSE` 一刀切（§3.0）；lumen/LC 用代理统计（§3.6）。
建议形状（additive，默认本地，现有模块零改动）：

```rust
/// What whole-image statistics a module needs (default: none).
fn stats(&self) -> StatsNeeds { StatsNeeds::Local }

pub enum StatsNeeds {
    /// Output pixel depends only on its support region (default).
    Local,
    /// Must see the full frame; streaming falls back to whole-frame for this node (§3.6①).
    WholeImage,
    /// Accepts statistics from a downscaled proxy (lumen/LC precedent, §3.6②).
    Proxy { max_long_edge: u32 },
}
```

- 统计的**计算与消费分离**：`commit` 拿整帧/代理帧算统计（已有 `ImageInfo` 入参，
  `module.rs:76-80`，需加可选的统计输入——形状待实现波定，建议 `commit_with_stats`，
  默认调 `commit`），`process` 逐带消费（签名零改，统计在 `CommitData` 里）。
- P0 只有 exposure-deflicker 等 1–2 个候选（§3.6），接口先立、消费后接。

## 5. Splice-in（接在哪里）

### 5.1 管线入口：新入口，不碰 `render`

- `Pipe::render`（`render.rs:352-465`）语义 = 同步交出整帧 `OutputFrame`（`:130-151`），
  B1-c 引擎已依赖（`engine/render.rs:717`）。**建议新入口**：
  `Pipe::render_stream(&mut self, req, sink)`，其中 `sink: &mut dyn FnMut(BandOut)`，
  `BandOut { y, height, plane: SharedFrame }`（小平面，预算内）。
  复用：`build_chain`/`forward`/`backward_check`（`chain.rs`）、`negotiate`、
  `chain_keys`（band 键 = 整帧键 + 带序号，可选）、`cancel` 纪律。
  `check_footprints` 加 band 分支（§2.5）：带足迹 = 在飞带平面 + 2×下限。
- 调用方（引擎导出/Full 预览）按带消费：导出直接编码写盘（RawLab `encodeStream`
  同模式：入口 `hdr_stream.cpp:659` + 逐带循环 `:792`，亲验 `:786-800`）；Full 预览的显示帧
  就是上限内的整帧（§3.8），真超限的 Full 预览走"按区域渲染"（`VERIFY.md:336` 已登记，
  即 LC 式窗口渲染）。

### 5.2 引擎：`InputSource` 加区域腿

- 现状整帧（§2.7）。**建议**：`fetch_region(&self, photo: &str, roi: FrameExtent) -> RenderInput`
  （默认实现 = `fetch` + 裁剪，保持 B1-c 行为；`ModuleSourceAdapter` 同款默认模式，
  `engine/render.rs:221-229`）。流式作业先 `forward` 算链头输入区 → `fetch_region` 取最小输入 →
  逐带跑。`final_roi_for`（`:530-550`）整帧语义保留，流式作业传输出带区。
- `RenderedImage` 整帧拷贝（`:725-732`）流式轮跳过：导出轮像素直接进编码器，
  不经槽位保留（§2.6；反正 VERIFY 已登记保留无上限缺口，流式轮正好不踩）。

### 5.3 解码（B2，rawspeed）：不能只解一个区域——但不需要，判断核实成立

- **rawspeed 无区域解码 API**：`RawDecoder::decodeRaw()` 整幅（`rawspeed/…/decoders/RawDecoder.h:56`，
  无区域参数，grep 亲验）；我方 shim 在 `rs_open` 内整帧解出（`shim/…/rawspeed_shim.cpp:47`
  `decoder->decodeRaw()`，grep 亲验）；B2 范围 = 马赛克 + 元数据整幅交付
  （`PLAN-B.md:209-220`，亲验）。
- **马赛克 2B/px 核实成立**：`rs_mosaic` 返回 `const uint16_t *` 行主序裁剪平面
  （`rawspeed_shim.h:59-62` 注释 + `rawspeed_shim.cpp:121-122` 类型检查，亲验）。
  61MP（A7R5 9568×6376，`CORE-DESIGN.md:89`）马赛克 = 61,005,568×2 ≈ **122MB**（+ pitch）；
  200MP 马赛克 ≈ 400MB。**都放得下**（Full 预算 2.56GiB）。
- **结论**：流式从去马赛克**之后**开始——解码整幅马赛克（B2 现状零改），
  demosaic 是第一个 band 化节点（输入 = 整幅马赛克常驻 + band halo，
  RCD halo 小；dt 另有 4px 输出边框语义，`PLAN-B.md:240`，B4 落）。
  超限判断点 = demosaic 输出的 RGB f32 整帧（200MP × 16B = 3.2GB > 1.24GB 上限 → 流式）。
- 接片注记：接片输入不是单马赛克（多帧拼接，merge 范畴，P0 之外），
  本调研只覆盖"单帧超限"；接片链的流式是后话（§7 不列入，免超五件）。

## 6. Estimate and acceptance（估算与验收）

### 6.1 估算（类比 B1 实际：B1-a 68min，B1-b 88min，B1-b2 36min，B1-c 58min，`VERIFY.md:304-354`）

| Lane | 内容 | 估计 |
|---|---|---|
| S1 | 接口：`StatsNeeds` + 一致性测试（§4）+ band 规划器（`roi_in` 链式反推 + 带高自适应 + 白名单门） | 1 lane × 3h |
| S2 | 执行：`render_stream` + band 缓冲复用 + cancel/错误语义 + `FrameTooLarge`-band 分支 | 1 lane × 3h |
| S3 | 接线：`InputSource::fetch_region` + 导出作业按带消费 + Full 预览区域渲染（接 VERIFY:336 登记） | 1 lane × 2h |
| S4 | 验收测试（§6.3）+ 200MP 合成 + 文档（PIPELINE.md 章节 + 上限表更新） | 1 lane × 3h |
| S5 | 独立复审 + 回注修复（B1 每波惯例） | 1 lane × 1h |
| 合计（甲起步） | 白名单 = 点运算 + 小 halo（overlap ≤ 64）模块；几何/全局模块拒绝流式 | **5 lane ≈ 12h** |
| S6（升丙，可选后波） | block 模式 + 代理统计管线 + demosaic band 化（需 B4 落定 RCD halo） | +2 lane ≈ 6h |

风险：① halo 链式放大——diffuse 类 overlap 1024 行 × 深链可把带高吃光，
规划器必须"带高 < 16 行则拒绝流式"（退回 `FrameTooLarge`，确定性行为）；
② B1 roi-variant 分块缺口（§2.4）与几何带同根，S1 必须二选一（补 roi 路 / 白名单排除几何，
推荐后者，§3.5）；③ 代理统计精度门未定则 S6 开不了工（§7.4 先行）。

### 6.2 验收测试形状

1. **200MP 合成流式**：200,000,000 像素合成图（渐变 + 网格 + 噪声三区，便于定位接缝），
   5 节点链（恒等 + 增益 + 小模糊 overlap=8 + 对比 + 输出），Full 预算（16GB 机 2.56GiB）内
   `render_stream` 成功，峰值 RSS < 1GB（峰值常驻自报，REPORT 原文口径，B1-b2 计时测试同款，
   `B1-b2-REPORT:86-95`），`cancel` 中途可停。
2. **逐位恒等**：同设置 20MP 图（上限内）整帧 `render` vs `render_stream` 逐字节相等；
   含 halo 节点时好块内逐字节相等（接缝区定义 = 输出带边界 ±0 行，好块即全带）。
3. **halo 覆盖负测**：`overlap` 撒谎的模块（声称 0 实际读 halo）被一致性测试拦下
   （§4.1 `debug_assert` + 单测）。
4. **拒绝路径**：旋转 90° 模块 / 全局模块（`WholeImage`）/ 带高 < 16 行时，
   `render_stream` 返回分了类型的拒绝（非 panic），预算缓存原样（`check_footprints`
   同款"跑之前就拒"语义，`render.rs:541-565`）。
5. **双跑逐位**：band 轮双跑逐字节同（B1 验收④同款，`PLAN-B.md:202`）。

## 7. Open questions（待用户定的事，不超过五件）

1. **起步白名单范围**：a) 点运算 + 小 halo（overlap ≤ 64）先行，几何/全局模块拒绝流式；
   b) 全模块一次到位（含 roi-variant + 代理统计）。
   **推荐 a**（甲 5 lane/12h 可交付；b 把 S6 卷入，18h 且精度门未定）。
2. **超限默认行为**：a) Full/Export 自动转流式（用户无感）；b) 显式开关，默认仍 `FrameTooLarge` 拒绝。
   **推荐 a**（lumen 全自动先例 `engine.py:1231-1237`；拒绝路径对接片用户是死路）。
3. **磁盘后备许否**：a) 允许 mmap 输出帧（lumen `allocate` 先例），配额 8GB，可关；
   b) 纯内存，超了就拒。**推荐 a**（200MP 输出帧 3.2GB，内存拼帧仍可能爆；mmap 只作输出落盘，
   不作乙式全链后备）。
4. **代理统计精度门**：a) mean < 0.5 LSB8（LC 等价门转述）；b) 更严/更松的数；
   c) S6 波再定。**推荐 a 先行、S6 实测回填**（无门不开工，§6.1 风险③）。
5. **Preview/Thumbnail 是否跟进**：a) 不跟进（维持现状 + VERIFY:336 的区域渲染登记）；
   b) 跟进。**推荐 a**（输入本就小，§3.8；跟进零收益）。

## 8. 风险登记（实现波输入）

- R1 halo 链式放大 → 带高下限 16 行 + 确定性拒绝（§6.1①）。
- R2 roi-variant 缺口 → 白名单排除几何（§3.5）。
- R3 非顺序访问抖动 → 只做甲，不做乙式全链 mmap（§3.2④）。
- R4 代理统计无门 → §7.4 先行，S6 门后开工。
- R5 200MP 测试资源 → 合成图内存生成（不落地），串行跑（B1-b2 量法坑，
  `VERIFY.md:340`：并跑 RSS 叠加失真）。
