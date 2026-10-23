# LUMEN-B DECISIONS — 裁定与偏差记录（执行批 2026-10-24）

> 正本计划 = 同目录 LUMEN-B-PLAN.md；OQ 裁决正本 = CONTEXT.md（D-LU-1/3/6 +
> X6/X7 + 红线 17 条 + 修复轮修订）。本文件只记执行期偏差与新钉；计划内已定值不重抄。

## §1 消费方四门接线：实际清单申报（review m-7 触点申报 + gate ① 结构性偏离）

- **gate ①（PipeCoordinator 载入腿预览档平面）申报未接线**——结构性原因：
  本仓管线在载入腿只解码一次（lazy CIImage 全分辨率 = 编辑工作平面本体），
  不存在独立的「预览档解码」；把载入腿平面读经缓存 = 量化编辑工作平面，
  直触 H-LU3 第二臂（编辑平面被量化 = 逐位语义漂移）= 红线禁手。处置 =
  PipeCoordinator.swift / EditorState.swift 全程零 diff（t3-grep.log 负测
  在案），重开/预览档位由 gate ②③④ 承载（图库档 B 渲染腿 / 选片回落腿 /
  MCP decodeImage）。计划风险节「触点若超预期 = 停手申报最小触点清单」的
  行使；如需编辑器重开加速 = 后批立项（须 PixelPipe 层设计，非包装层可达）。
- **gate ②**：`WorkspaceHostView` 桥装配点接线 `LibraryThumbnailBridge
  .RenderLeg`（原 nil——hasEdits 行全占位）。**v1 腿形态 = pristine 解码**
  （sidecar develop 物化 = 计划注记的「P2 develop 腿」域，本批不实现）；
  占位→pristine 的观感折衷在此申报（列语义不变，行渲染从 miss 变为
  无编辑观感图）。
- **gate ③**：`CullViewLoader.defaultDecodeLeg` = T3 缓存路由（store 共享
  load → SmartPreviewRender.cgImage）。
- **gate ④**：`CullingToolset.defaultDecodeImage` **内部**换路由（seam
  签名/构造点零改；McpServerController 全批零 diff——git 逐 commit 可核）。
- 消费点正本 = `evidence/lumenb/t3-grep.log`（App 侧恰两点 + Core 一文件；
  编辑腿零命中）。

## §2 缓存平面档位 = 2560（我方新钉，Lumen 无此维）

缓存平面长边 = **2560** = `PreviewBucket.cap`（编辑器自有预览档）与 LU3
显示档对齐。内存 LRU 6 张 float32 ≈ 105MB（Lumen 6×20MB 面的换档重标）。
4096 臂弃：4096²×16B ≈ 270MB/张 × 6 = 1.6GB，破 GUI 3G 触发线余量。
X8 蒙版 guide ≤4096 档属 Plan C 域，与本档无关。

## §3 zlib「level 1」意图的系统等价物

Apple Compression framework 无级别旋钮；`COMPRESSION_ZLIB` 为速度定向
deflate——「禁高级别（Lumen level 1 读 ~40ms 口径）」的结构性满足（无 level
参数可设）。计划红线未破（高级别不可达），在此申报等价形。

## §4 形态钉（review m-9/m-10 落实）

- **shared holder 单例形**：`SmartPreviewStore.shared` = `private static
  var sharedInstance`（`nonisolated(unsafe)`）+ NSLock getter + `replace
  Shared(_:)`（M2-5 LutLibraryStore 体例 / ColormatchResolverBox 同形逐行
  镜像）。四门消费方共享同一 index DB 句柄/内存 LRU/in-flight 表；并发
  测试挂单例假设（T2 merge 测试经 `replaceShared` + 恢复生产实例）。
- **mtime 钉 ns**：键 mtime 维 = `stat()` 的 `st_mtimespec`（tv_sec×1e9 +
  tv_nsec），同秒连拍不共键；path 维 = `resolvingSymlinksInPath`（一文件
  多路径同键；stat 跟随 symlink 与 resolved path 一致）。
- **弃层申报（m-10）**：Lumen 三层缓存只移植 float16 解码面层（kind 'd'）——
  ①2560 JPEG 相机视图层弃（`CullViewLoader` 每次 ImageIO 直读内嵌预览，
  M2-2 实测 10.6ms/张 口径可接受）；②320 thumbs 层弃（`.lathumbs` 既有
  派生物承担）。index 表保留 `kind` 列（Lumen entries 表形直译），仅写 'd'。
- **损坏语义**：损坏 index = schema exec 失败臂删 db/-wal/-shm 重建；损坏
  平面文件 = `forget` + 重解码重写（T2 双测试钉死）。

## §5 量化一致性的边界钉（H-LU3 执行形）

- `enabled`（limit>0）未命中路径**恒过 quantize**——写失败（盘满/目录敌意）
  仍返回量化平面（Lumen 语义：quantize 挂 miss 路径与写成功无关）；命中/
  未命中逐位一致（T3 消费级 golden 钉：冷店 disk hit == miss == quantize
  (decodePlane)）。
- **disabled（limit=0 或 stat 失败）= 原始解码直通（零量化）**——默认中性
  面：与批前行为逐字节一致（T2 disabled 测试 + T3 中性 golden 钉）。

## §6 测试向量与源替代申报

- **实拍导出平面缺位**：CI 无实拍样张 → round-trip golden 双源 = 种子化
  LCG 噪声平面 + 照片样合成平面（梯度 + 平滑 shading + 细粒噪声——重排
  压缩率的平滑域动机成立）。逐位一致 + <0.05% 误差断言为数学面，源无关。
- **上游向量缺失**（m-3 同口径）：Lumen preview_cache 无测试向量 → 自织
  向量 + 直译语义对拍（T2 各族 = preview_cache.py 行为逐条镜像面）。
- **full_size 判定**：真 RAW 的 sensor px 不可 CI 依赖 → `properties`
  注入缝 + 合成 properties 表驱动（≥50% 真 / <50% 假 / 缺席 = 假——诚实
  回落臂）；verdict 随提取落定（Lumen embedded_view 同形）。

## §7 评级写腿与键位申报

- **写腿 = `LibraryStore.setMetadataMarks`（计划钉死 :455 投影批写）**：
  投影列即时可见（胶片条/表头读本地 projection——`applyWrittenMarks`）；
  **`.lra` sidecar 真相不在本腿**——投影与 sidecar 的真相回填 = 下一次
  编辑器侧 mark 写（LibraryMetadataWriter.apply）时按投影列存活值落盘。
  此折衷申报：选片面评级 = 库域即时判定面，非编辑文档真相写入。
- **flag 语义**：0 = none / 1 = pick / 2 = reject（LightamerSidecar:303
  既有 trio——P/X/U → 1/2/0，测试钉死）。
- **Z 键 = X7 之外的可加键**（偏差申报）：X7 最小集无缩放键；Z/双击 100%
  沿 Lumen 词汇（Z/Space 直译取 Z，Space 让位滚动语义）。G/D 钉死对不动。
- **评级后前进 = 同步推进**（键即刻走位），写腿 fire-and-forget——Lumen
  rate() 的 go(advance) 同序直译。

## §8 缩放面 v1 形态

共享 zoom 状态（模型单值，双 Pane 结构性同步——Lumen sync_zoom 的逐 pane
拷贝被单源替代）；100% 腿 = 全尺寸平面按像素尺寸滚动（retina 下 1pt=2px
≈ 200% 观感的**近似申报**）；点击对焦/拖拽平移 = 走查轮细化项（挂 validate
道）。全尺寸平面 = 内嵌合格件或 T3 缓存档（2560 平面上限 = 回落保真申报：
内嵌不合格源的 100% = 缓存档保真，非传感器原生）。

## §9 ΔN 越带申报（+41 vs 计划带 +14..18）

实账 = IOP +18（8+7+3）/ App +22（8+6+8）/ Library +1（分区纯函数，寄生
既有 LIB 文件零新增登记）= **+41**。越带 +23 理由：
- 沿 LUMEN-A 批「每条 SC 子句一测」纪律（A 批同款越带 +16..19 先例）——
  本 plan 每 SC 子句均有机检方法；
- T4 loader 高状态面（显示档/LRU 逐出序/预读产出/full_size 三案表/回落
  腿切换/全尺寸 cap/生产门 cap/路由状态机）每族需独立确定性方法（并发
  与逐出序不可合并断言）；
- T6 对比状态机五面 + 组跳边界三案 + 提示条映射含空面 + 插队窗双钳——
  均为 SC 显式子句；
- T2 键失效三例并入一方法、损坏/降级/禁用三面各一（合并后仍 7 法）。
全套 `--all` 终值对账归 C 收口轮（计划预期带按 +41 修正为 4165..4168 邻域，
以运行期为准）。

## §10 环境与执行注记

- **磁盘压力处置**：执行中 Data 卷多轮触 G4 门（25GB）——清理对象全部为
  可再生缓存（Xcode ModuleCache/SDK 预编译缓存、ms-playwright 浏览器缓存、
  @zcodedesktop-updater / quark 更新包缓存、GeoServices/Homebrew 缓存、
  本批测试临时目录）+ 本批测试 fixture 目录清扫；零用户数据触碰。
  Build/Products 与 DerivedData 主体未清（增量构建保留）。
- **tuist generate 登记一次**（T7 注册批末位）；批内 T4/T5 期临时注册
  按惯例即用即撤（A 批同款）。
- **重开命中探针 = skip 族申报**：`LIGHTAMER_PERF_PROBE` 专用探针测试未
  落（需新 IOP 文件 + 真实样张面）；≤100ms 级口径的代证 = T2/T3 golden
  路径（unpack 面即命中路径本体）+ Lumen 40ms/7MB 口径引用。专用探针挂
  C 收口轮（与 GUI 走查同道——实机样张）。
