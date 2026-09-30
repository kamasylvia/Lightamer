# Requirements: Lightamer

**Defined:** 2026-08-03
**Core Value:** 在 macOS 上用 Metal 加速提供 100MP+ 大图下零延迟的 RAW 调整体验，并让 Capture One Session 工作流与 Darktable 级调整深度在同一原生 app 中共存。

> ⚠️ **2026-09-27 项目重定义（用户指令）**：产品目标改为 **macOS 独占、RAW 9 解码、UI 完全模仿 Alcedo Studio 的 Alcedo 克隆**；dt 独有已交付代码保留但默认不启用；图片管理改 Alcedo 方式（Sessions/Catalogs 剥离）；导出格式保留原矩阵、可选项按 Alcedo；水印相框保留 yiyin；蒙版 = Alcedo + Nitro Photo（不用 dt 方案）；以上全部属 **V1**。**下方既存 v1 Requirements 为里程碑 1 历史账（已交付面照旧有效，交付面被剥离者标 disabled）**；新 V1 需求家族待 `ALCEDO-FEATURE-MAP.md` 测绘落盘后统一登记（ROADMAP M2-0），本文件暂不重写历史节。V2 节 ALCE-01/04/05/06/07 随重定义**提级 V1**；ALCE-02（OpenEXR）/ALCE-03（Ultra HDR JPEG）维持 V2（用户：导出格式保留原方案）。

## V1 Requirements — Milestone 2: Alcedo V1（2026-09-27 重定义；✅ D1-D6 已签核全按推荐，M2-1 起可执行）

> 规格锚点 = `research/ALCEDO-FEATURE-MAP.md`（章节号见各条）。粒度 = family 级，phase discuss 时再拆 task。M1 历史需求族（下方既存各节）作为已交付资产账本继续有效；本节为唯一活跃 V1 面。

### dt 禁用矩阵 (DIS)
- [x] **M2DIS-01**: 39 个 dt 派生 iop 逐一审计 → 启用/禁用矩阵落盘（D1 filmic/sigmoid/agx、D2 降噪三件、Alcedo 无对应项默认禁用；独有增强项按 D6 收纳保留）**Delivered**（M2-1：`phases/m2-1-dt-disable/M2-1-MATRIX.md` 禁用 6/启用 33/灰区保留 14，T4 复核签注逐行一致 + 验收全集比对一致；`c663709`/`902d942`）
- [x] **M2DIS-02**: ModuleRegistry feature-flag 门控（默认面收窄；禁用模块代码+测试保持全绿，可显式开启）**Delivered**（M2-1：`defaultFaceDisabledOpNames` 6 项 + `populate/seed(defaultFace:)` 收窄缝 + `LIGHTAMER_FULL_IOP_FACE=1` opt-in 口（KD-3）；既有测试零改动全绿（KD-2）；`f5bcfa2`/`561ca59`）
- [x] **M2DIS-03**: UI 七页签收敛——禁用项不出现在任何面板/预设浏览器/批量 apply 面（**Delivered 半边 = M2-1**：面板行/层 add-module/预设 apply 种子/批量 apply 种子/MCP schema 五面收窄钉死，`561ca59`；**七页签 IA 收纳留 M2-3**）；**Delivered 终注（2026-09-29，M2-3-3）**：七页签 IA 收纳兑现——`EditorTabRoutingTable` 单一正本（动态 populated-provider 集 − {TextOverlay} 恰一次归页 = 33，恰一次断言 + 禁用 6 名 grep 零命中机检，AgX 失挂 = E1 勘误执行；TAB-MATRIX md 与表逐行对账测试钉），验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`；**P4 走查一致（七页签序与归页 20 屏对照——MANIFEST 同上）**
- [x] **M2DIS-04**: 降噪由 RAW 9 解码层承担（CIRAW NR 参数族在 RAW Decode 页签暴露，D2） **Delivered**（M2-3-3 T4：`RawDecodePanelView` NR amount/luminance/chroma/sharpness 四滑杆 + decoder version（default/v8/v9，`resolveDecoderVersion` 纯函数 typed 降级）+ boost + identity Reset——`RAWTechnicalOverrides` 缝先写 filter 后 readback，cache key 自然漂移；膨胀字段 Optional `sharpnessAmount`/`boost` encodeIfPresent nil 零漂移（`RawDecodeOverridesTests` 5 断言钉）；会话级载体，持久化挂账 M2-4 节点 schema；Neural Engine demosaic+denoise 校准归 M2-5+；锚 `921a98f`，验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`）**终注（2026-09-30，M2-4-1 验收）：持久化挂账销账**——sidecar v5 `rawOverrides` 字段（decodeIfPresent/encodeIfPresent，nil 档缺键；hash-isolated：decode 域由 decodeParamsHash 代表，不进 HistoryHash/driftDetected）+ 写腿（`setRawDecodeOverrides` 透传钩 → 2s throttle 落盘，`RawDecodePanelView` 零 diff）+ 恢复腿（E1 方案① re-decode；pristine 档单 decode 零回注；等价判定防 switch-back 双 decode），AC7 真链 3 测试钉（`SidecarV5Tests`，真 EditorState+PipeCoordinator+WorkspaceModel 装配）；锚 `48e2b7d`，验收 `phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md`
- [x] **M2DIS-05**: 预设/MCP 默认工具面同步收窄（禁用模块不入默认 schema）**Delivered**（M2-1：apply_params 禁用 op = typed unknownOp、list_iops 默认面 18→15、工具注册面 19 不变（不删工具）；`f2a3618`）

> M2-1 验收：`phases/m2-1-dt-disable/M2-1-ACCEPTANCE.md`（独立复跑 1889/11skip/0fail）。

### 图库与项目模型 (LIB)
- [x] **M2LIB-01**: 单项目文件包（SQLite：`<stem>` 库 + manifest；相册结构与全部编辑历史在一个文件内，可整体移动/备份；schema 版本化）**Delivered**（M2-2-1：`.lalb` 单 SQLite + `project_meta` manifest + `user_version` 三分 dispatch（absent→fresh=1 / 1→ok / >1 typed REFUSE，迁移前自动快照缝）+ WAL/synchronous=NORMAL + KD-6 节流 TRUNCATE checkpoint（≥2s∨≥64 批，close 后 `-wal`==0 实测）+ `sqlite3_backup` 在线拷（唯一钦定备份路径，M2-3 不暴露裸拷）+ 包目录常量（`Media/` + `.<stem>.lathumbs/`，KD-1）；编辑历史面 = `has_edits`/`params_hash` 投影列，mini-git 四表 M2-8 经 migrate 缝激活；`4491c7b`/`a50f67f`；验收补 `withWriteBatch` BEGIN IMMEDIATE 事务包裹——KD-4 同事务语义修复，`phases/m2-2-library-project/M2-2-1-ACCEPTANCE.md` F-1）
- [x] **M2LIB-02**: 相册骨架——文件夹/相册/智能相册（Filter JSON 谓词）+ Element 引用计数模型（Feature-map §6.2 Sleeve/FolderContent/Filter 语义）**Delivered**（M2-2-1：`albums` 单表三型 `type` 判别（album/folder/filter，SleeveRoot/ComboFolder 合并）+ parent 树（级联 + 环拒绝）+ `filter_data` = `FilterPredicateGroup` Codable JSON（sortedKeys，`validating()` 前置，零新格式）+ `images.ref_count` 物化列同事务联动（add 幂等/逐成员递减封底/删相册子树级联/归零不删行，KD-4）；真身红线守住——`.lra` 恒编辑态真相，Library 域零 sidecar 路径；`5bf0eeb`）
- [x] **M2LIB-03**: 导入——文件夹批量导入（入库方式三选见 M2LIB-07）+ RAW-only 扩展名过滤可配 + 进度反馈。**过滤加固 AC（2026-09-27 用户实测 Alcedo 0.3.0 上游缺陷反向教训：其 changelog 宣称 RAW-only 但导入链零过滤——`CollectFolderFiles` 递归全收、`is_supported_file` 孤儿无调用、loader 处调用被注释 → `.ARW.xmp` 当图片导入数量翻倍）**：①按最后一个后缀精确匹配白名单（case-insensitive）；②显式排除附属/sidecar 文件（`.xmp`/`.lra`/`.lightamer-preset`/`.pp3`/`.opc` 等）与点开隐藏文件；③验收 fixture 必须用真实 C1 Session 目录（含 `.ARW` + `.ARW.xmp` 对，如 `/Volumes/UNITEK/.../Capture/RAW`），断言导入数 = RAW 数而非文件数 **Delivered**（M2-2-2：`ImportFilter.select` 单一纯函数门，判定序 ①隐藏（`.` 前缀 + Finder `isHidden` flag）→ ②硬编码排除表（五类，先于白名单且**永不读配置**——白名单含 `xmp` 仍拒，机检）→ ③白名单最后后缀精确 case-insensitive（`photo.ARW.xmp` 落 ② 拒；`raw.xmp.arw` 双后缀伪装按最后后缀语义收，测试钉文档）；AC③ fixture 经用户裁决落**合成 C1 Session 形态**（盘面 16 文件 → 恰 7 RAW 入库、rejected 分类 6 sidecar/2 白名单外/1 隐藏精确、6 `.xmp` 随迁零翻倍——覆盖 Alcedo 缺陷形态；真实 C1 目录复跑 = Manual-Only 观察项入 SUMMARY）；可配宿主 `ImportDefaults`（UserDefaults `library.import.rawExtensions` 全量替换语义 + 归一化 + reset，OQ-12）；进度面 `ImportProgress` 快照 + `ImportProgressView`。锚 `b77c677`/`c6eee61`，验收 `phases/m2-2-library-project/M2-2-2-ACCEPTANCE.md`）
- [x] **M2LIB-04**: Image 物化搜索列（file_stem/capture_at/camera/lens/iso/focal/aperture/rating + 词边界折叠检索文本）+ EXIF 词法搜索（`iso800`/`f/2.8`/`35mm`/日期多格式 AND 组合；性能对标 ~20ms@2 万张）**Delivered 索引层**（M2-2-1：images 28 列冻结序含 EXIF 八列（SessionIndexSchema v2 同名同型）+ `file_stem/file_ext/exif_search_text/exif_search_words` 物化四列 + `ExifFold` 双向折叠词表正本（`f2.8`+`f 2 8`/`iso800`+`iso 800`/`35mm`+`35 mm`/日期五变体/曝光倒数族；`iso800` 前缀串不误伤 FTS 实库钉）+ `images_fts` FTS5 external-content（列同名钉 `exif_search_words`，unicode61 零定制）三触发器同步 + `ExifSearchIndexer`（ImageIO PROPERTIES-only 物化填充 + rebuild 幂等）；**查询面（AND 组合解析）与 ~20ms@2 万张性能验收归 M2-2-3 LibraryQueries**；`c1e8a90`）；**Delivered 查询面终注**（M2-2-3：`ExifSearchParser` 三段 typed 计划（iso 三拼写 eq + 范围五约束族 / aperture 四拼写 ±0.05 容差带 4 位规整 / 35mm 双拼写 / 日期六拼写 round-trip 拒非法 / disjoint+unrecognized typed 降级）+ `LibraryQueries` 混查单语句三腿 AND（FilterSQL.library 结构化腿 ∩ FTS MATCH 折叠变体 OR 组词法腿 ∩ keyset 行值 seek + NULL 尾段，五键白名单 scanEpoch typed 拒绝）+ KD-6 `iso800`⊄`iso8000` 双腿负例；**OQ-9 硬门 PASS = Release 热 p95 最差 15.66ms @ 2 万张**（72/72 形状 × 3 轮 Debug+Release 对账，验收独立复跑 15.15ms 同格复现；`perf.md` §A）；`dfb4746`/`b9792ea`/`811122f`，验收 `phases/m2-2-library-project/M2-2-3-ACCEPTANCE.md`）
- [x] **M2LIB-05**: Album Inspector——总数卡 + 四分组（日期/相机/标签/镜头）+ Activity view（按日数量图点击过滤）+ 搜索过滤态显示 **Delivered 数据面+壳面（合龙终态 2026-09-29）**（数据面 M2-2-3，OQ-11 切分线：Inspector 面板/网格/搜索对话框壳与视觉验收归 M2-3——本条数据与查询 API 面先行交付：`LibraryQueries` overviewCount 总数 / groupCounts 四键（captureDate 日桶 / camera mk+md Unknown 归一（NULL+'' 双源）/ labels 星档 / lens，typed 点击载荷）/ activitySeries 按日计数序列 + dayFilter UTC 整秒投影回 FilterPredicateGroup / currentFilterDescription typed 渲染源 / searchPage+searchNullTail keyset 分页（五键白名单）/ SmartAlbumStore.evaluate(.library) 智能相册成员集缝闭环；20 测试真 `.lalb` 机检；锚 `b9792ea`，验收 `phases/m2-2-library-project/M2-2-3-ACCEPTANCE.md`）；**壳面 Delivered**（M2-3-2：LibraryGridView keyset 无限滚动网格（LazyVGrid + 尾窗信号胶水 + isExhausted 封底 + 双击 openEditor 真缝）+ LibraryInspectorView（Alcedo AlbumInspectorPanel IA 逐件——LIBRARY OVERVIEW 总数卡随 filter 联动 / 四分组点击 typed 臂折叠-反选-面包屑逐臂退（Unrated inert D3）/ ACTIVITY 柱点击=日期腿 / SEARCH FILTER currentFilterDescription verbatim / SMART ALBUMS evaluate(.library) 成员闭环+相册谓词折叠 D4 + missingStore 空态）+ GlobalSearchDialog 三合一（EXIF 腿真接 `ExifSearchParser.parse` 四族形状分类行内呈现 + 空串恒真清词法腿 + CLIP/全文 M2-10 诚实空态 + ⌘F 呈现态 m6 方法面）+ 批量 relink sheet（持久化腿 gate 注记见 M2LIB-07）；27 新测试真 `.lalb`，终轮 2130/14skip/0fail，验收独立复跑同值；锚 `fe068a2`/`530c971`/`48e906f`，验收 `phases/m2-3-ui-shell/M2-3-2-ACCEPTANCE.md`；P4 Alcedo 对照视觉走查 Delivered（2026-09-30，M2-3-4 T2——20 屏差异清单，`.work/gui-acceptance/m2-3/MANIFEST.md`））
- [x] **M2LIB-06**: Sessions/Catalogs 剥离——UI 不暴露、入口禁用（代码保留可回切） **Delivered**（M2-2-4：`LibraryLegacyGate.isLegacyLibraryRequested(environment:)` 唯一 env 读点（纯函数可注入，KD-1）；默认 false = Sidebar Sessions/Catalogs 双区 + 模式切换器（单 `if legacyLibraryEnabled` 包裹，节内容零改动）+ Settings Catalogs 双节全隐，启动面 = 项目工作区最小容器（`ProjectWorkspaceFace`；无项目 → P2 Welcome sheet，OQ-1）；**回切口 = `LIGHTAMER_LEGACY_LIBRARY=1`**（QA/回归通道；回切形态 = 既有树 verbatim 迁 `legacyBody`——验收 diff 机检 old body vs legacyBody 仅差声明行——+ 冻结 `Set<String>` 快照对偶断言，env=1 面逐字节同构）；**Settings 页无新开关**（OQ-8 双库心智）；**代码零删除**——Session/Catalog 模型与三族既有测试零 diff 全绿，`LightamerCore/` 零改动；File 菜单 Session 项未门控（OQ-8 字面外 inert 死路由，菜单 IA 收纳归 M2-3）。终轮 **2049/13skip/0fail**（基线 2038 +11 = LibraryLegacyGateTests；验收独立复跑 2049/13/0 763.8s 同值）；偏差 6 条 + Manual-Only 3 项（env=1 真进程冒烟/默认启动面目视/真实 C1 目录）见 `phases/m2-2-library-project/M2-2-4-SUMMARY.md`；锚 `207bd25`/`c09d258`，验收 `phases/m2-2-library-project/M2-2-4-ACCEPTANCE.md`）
- [x] **M2LIB-07**: 导入方式询问【2026-09-27 用户指令】——选择导入文件夹时弹询对话框：「**移动 / 复制 / 软链接（快捷方式）**」三选，决定 RAW 从源文件夹入库的方式。实现约束：①移动 = 同卷 rename 优先、跨卷自动回退 copy+校验+删源（**校验通过前永不删源**）；②复制 = 进度反馈 + 逐文件校验（字节/哈希）+ 重复检测跳过；③软链接 = 相对/绝对链接策略随卷型定（USB/网络卷路径可变性，对照 L009 卷型标注教训），stale link 检测与修复入口；④对话框默认值与「记住我的选择」留 M2-2 规划裁决；⑤三模式下 `.lra`/附属 sidecar 的随迁语义一致（移动/复制随行、软链接指向原位 sidecar） **Delivered**（M2-2-2：三方式 `ImportService` actor（KD-2 scan→plan→per-file executor，DB 行只在落位成功后写——无幽灵行）——①移动同卷 rename 优先、跨卷 copy→verify（尺寸 + FNV-1a `StableHash`）→删源，**红线结构化**：remove 仅在 verify 通过腿内，注入 verify 失败 = 源文件字节原样 + 零行红钉机检（import 与 moveProject 双钉）；②复制逐文件 verify + 等价字节重复跳过（`StepResult` 计数面）+ 同名异内容 `<stem>-1` 递增避让；③软链接 `ImageLinker` kind1 卷相对 + volumeUUID（statfs 挂载点 + `volumeIdentifierKey`，挂载点改名免疫；firmlink 双拼写候选）／跨卷 kind2 绝对 typed 降级，stale 两形态（`pathMissing`/`volumeAbsent`）+ `relinkRecord` 数据面（Inspector 批量 relink UI 归 M2-3）；④对话框 OQ-4 默认复制 + 「记住我的选择」`ImportDefaults` mode/rememberMode 两键（单次覆盖不落盘机检；设置页 UI 归 M2-3/M2UIW-05）；⑤sidecar 随迁一致——move/copy `.lra`/`.xmp` 随行且失败整体回滚已拷字节、link 留原位。进度 + per-file 取消（无幽灵行）+ EXIF 物化走 M2-2-1 Indexer 缝。锚 `b2da780`/`c6eee61`/`b30d8e5`，验收 `phases/m2-2-library-project/M2-2-2-ACCEPTANCE.md`）；**relink UI 壳注记（2026-09-29，M2-3-2）**：Inspector 批量 relink sheet 交付（stale 两形态 typed 分类 + 换源选择 + App 层批量编排 + BackgroundTaskHosting 第二腿 + relived/stillStale/cancelled 三分类计数；真持久化经 @testable 注入真写 + 查询面复核），生产持久化因 `ProjectFileStore.withWriteBatch` Core-internal + Core 冻结红线为注入缝——sheet run 按钮 gate + 诚实文案（`relink_persistence_pending`），待 Core-face 小 plan（`LibraryStore.relinkImage` 族）落地面后摘 gate 即全功能（M2-3-2 DECISIONS D2 + LESSONS L042 + `phases/m2-3-ui-shell/M2-3-2-ACCEPTANCE.md` D2 架构注记）；**Import Defaults 设置页注记（2026-09-29，M2-3-3）**：④腿设置页交付——Settings Import Defaults 页消费 `ImportDefaults` 三键（三选 transport + remember 单写契约 + RAW 白名单全量替换 + reset，`SettingsPagesTests` 写读 reset 断言钉），见 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`

### UI 壳 (UIW)
- [x] **M2UIW-01**: 双工作区路由（Library/Editor）+ 顶栏 + 暗色玻璃主题 tokens（Feature-map §1.1/1.2/1.3 布局语义；SwiftUI 实现非 QML 复刻像素级） **Delivered（双面合龙终态 2026-09-29）**（路由+顶栏+tokens = M2-3-1，验收 `M2-3-1-ACCEPTANCE.md`；图库面 = M2-3-2（缩略图网格 + Album Inspector + 全局搜索三合一 + relink sheet，验收 `M2-3-2-ACCEPTANCE.md`）；编辑器面 = M2-3-3（三段布局 + 七页签 33 面板归页 + 示波器 GPU + RAW Decode 面板，验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`）——双工作区面齐，整条合龙；锚 `46e13fb`/`29553ba`/`05317d1`/`921a98f`/`8d556c7`）；**P4 视觉对照走查 Delivered（2026-09-30，M2-3-4 T2）**：20 屏三件套 Alcedo 真机差异清单（15 基线 + 5 增补 = 七页签全覆盖），判定分布 一致 11 / 偏差-接受 8 / 设计差异 1（左竖胶片条 = 用户裁决标识差异），偏差-修 2 条闭环（`a3bf5bf`），真缺陷 2 项转专项（导入完成态不发布 / 编辑器加载失败——`.work/gui-acceptance/m2-3/MANIFEST.md` + `phases/m2-3-ui-shell/M2-3-4-SUMMARY.md`）
- [x] **M2UIW-02**: 编辑器三段布局——左工具轨（History/Versions/Nodes 图标列+展开推挤）、中视口（FIT/百分比读出/裁剪角度徽标/双级 busy/手势缩放平移）+ **左侧竖向滚动胶片条【2026-09-29 用户裁定，偏离 Alcedo 底部布局】**（与图库同集合过滤）、右示波器 + 调整栈 **Delivered**（M2-3-3 T1：`EditorToolRailView` History 真挂 M1 history stack（undo/redo 头部）/Versions+Nodes 诚实空态（M2-8/M2-4 家族）+ 展开推视口不推胶片条；中视口 = 既有 `EditorAreaView` 零 diff 包装（KD-1 前置快照核对在 DECISIONS，手势/overlay/双级 busy/FIT/ZoomHUD 面零迁移）；左竖胶片条 = M2-3-1 FilmstripView 直挂（同集合过滤，M2-3-1 部分注记并账）；右栏 = ScopePanelView + 七页签栈纵向（Alcedo 同方位）；锚 `46e13fb`，验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`）；**P4 视觉对照走查 Delivered（2026-09-30，M2-3-4 T2）**：20 屏三件套 Alcedo 真机差异清单（15 基线 + 5 增补 = 七页签全覆盖），判定分布 一致 11 / 偏差-接受 8 / 设计差异 1（左竖胶片条 = 用户裁决标识差异），偏差-修 2 条闭环（`a3bf5bf`），真缺陷 2 项转专项（导入完成态不发布 / 编辑器加载失败——`.work/gui-acceptance/m2-3/MANIFEST.md` + `phases/m2-3-ui-shell/M2-3-4-SUMMARY.md`）
- [x] **M2UIW-03**: 七页签调整栈（Tone/Look/LUT/Display Transform/Geometry/RAW Decode/Mask）+ 节点头（名称+焦距/光圈/快门/ISO） **Delivered**（M2-3-3 T2：`EditorTabRoute` Alcedo 页序 + `EditorTabRoutingTable` 单一正本 33 面板恰一次归页（动态集断言 + 禁用 6 零命中 + TAB-MATRIX 对账，M2DIS-03 终注同）+ DT 页 Vignette + DRT 占位节（E1 勘误，AgX 失挂）+ Mask 页 layers 预归位 + yiyin 顶栏 sheet/MCP 现状/Preset 头部全局三特例入口；`EditorNodeHeaderView` Color Grade 常量 + EXIF 焦距/光圈/快门/ISO 四腿（nil→"—"）；锚 `29553ba`，验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`）；**P4 视觉对照走查 Delivered（2026-09-30，M2-3-4 T2）**：20 屏三件套 Alcedo 真机差异清单（15 基线 + 5 增补 = 七页签全覆盖），判定分布 一致 11 / 偏差-接受 8 / 设计差异 1（左竖胶片条 = 用户裁决标识差异），偏差-修 2 条闭环（`a3bf5bf`），真缺陷 2 项转专项（导入完成态不发布 / 编辑器加载失败——`.work/gui-acceptance/m2-3/MANIFEST.md` + `phases/m2-3-ui-shell/M2-3-4-SUMMARY.md`）
- [x] **M2UIW-04**: 示波器（直方图/波形二选一，GPU 渲染） **Delivered**（M2-3-3 T3：`ScopeReduceKernels.metal` 256-bin×4 通道（R/G/B/Rec.709 luma）atomic 计数直方图 + 逐列下采样波形（r16Uint 小纹理）GPU compute 双 pass + `ScopeReduce` 宿主（L031 唯一队列路由 + L014 fence 读回）+ PREVIEW 完成回调 additive tap（不可见零 tap）+ `ScopeThrottle` ≤15Hz/idle 250ms 补算状态机；`ScopeReduceTests` 7（三 case 逐 bin parity + 像素总数 + 波形 parity + 确定性 + 1x1 退化）；v1 波形呈现 = 小纹理 CPU 读（DECISIONS D6 登记项，P4 观察清单接账）；锚 `05317d1`，验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`）；**P4 视觉对照走查 Delivered（2026-09-30，M2-3-4 T2）**：20 屏三件套 Alcedo 真机差异清单（15 基线 + 5 增补 = 七页签全覆盖），判定分布 一致 11 / 偏差-接受 8 / 设计差异 1（左竖胶片条 = 用户裁决标识差异），偏差-修 2 条闭环（`a3bf5bf`），真缺陷 2 项转专项（导入完成态不发布 / 编辑器加载失败——`.work/gui-acceptance/m2-3/MANIFEST.md` + `phases/m2-3-ui-shell/M2-3-4-SUMMARY.md`）
- [x] **M2UIW-05**: 设置页族——语言/主题、Default Behavior（蒙版绘制三选）、缓存、Local Content Recognition、Advanced Content Analysis、键盘自定义（冲突显示+恢复默认）、关于 **Delivered**（M2-3-3 T5：`SettingsPage` 十入口导航（navigationPages 精确十项 + Acceleration/Updates 负例断言 + Catalogs 门控页两态）+ Displays/MCP/Catalogs 语句级 verbatim 迁移 + `AppPreferences`（mask 三选 `mask.behavior.default` 存储面交付、接线归 M2-7；Keyboard keymap 镜像 + 纯冲突检测器 + override 存储——v1 展示/检测/恢复三面不活绑）+ LCR/ACA「arrives with M2-10」诚实空态零假开关 + Import Defaults 三选消费 `ImportDefaults`（M2LIB-07④ 设置页腿）+ About 版本/MIT；锚 `8d556c7`，验收 `phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`；zh 文案补录 Delivered（P4 T1 对账批 +223 键，`Scripts/zh-audit.py --check` 机检 exit 0））；**P4 视觉对照走查 Delivered（2026-09-30，M2-3-4 T2）**：20 屏三件套 Alcedo 真机差异清单（15 基线 + 5 增补 = 七页签全覆盖），判定分布 一致 11 / 偏差-接受 8 / 设计差异 1（左竖胶片条 = 用户裁决标识差异），偏差-修 2 条闭环（`a3bf5bf`），真缺陷 2 项转专项（导入完成态不发布 / 编辑器加载失败——`.work/gui-acceptance/m2-3/MANIFEST.md` + `phases/m2-3-ui-shell/M2-3-4-SUMMARY.md`）
- [x] **M2UIW-06**: 后台任务系统 UI（对话框+底部栏+取消，AI/导入/导出共用）**Delivered 协议+导入腿**（M2-3-1：`BackgroundTaskHosting` 三腿协议一次成型（`@MainActor` handle + `BackgroundTaskSnapshot` 0…1/indeterminate/阶段文案 + cancel；零 leg 专属字段——导出腿 M2-9 / AI 腿 M2-10 届时消费，禁提前设计）+ `BackgroundTaskRegistry` register/update/finish/cancel/cancelAll（插入序稳定 + 重复注册拒绝）+ 底部栏/对话框**双呈现同源**（`BackgroundTaskProjection.descriptors` 单函数，`tasks.bar`/`tasks.dialog` marker）；导入腿 = `ImportTaskAdapter` **只读订阅** `LibraryProjectController.importProgress` + `cancelImport()` 透传（checker E3：controller/ImportModeDialog/ImportProgressView 零 diff）+ 单调钳制快照；9 测试（四态生命周期/插入序穿中间完成/单调跨相不回退/cancel spy/双呈现同行集）。锚 `56e582e`，验收 `phases/m2-3-ui-shell/M2-3-1-ACCEPTANCE.md`）；**P4 视觉对照走查 Delivered（2026-09-30，M2-3-4 T2）**：20 屏三件套 Alcedo 真机差异清单（15 基线 + 5 增补 = 七页签全覆盖），判定分布 一致 11 / 偏差-接受 8 / 设计差异 1（左竖胶片条 = 用户裁决标识差异），偏差-修 2 条闭环（`a3bf5bf`），真缺陷 2 项转专项（导入完成态不发布 / 编辑器加载失败——`.work/gui-acceptance/m2-3/MANIFEST.md` + `phases/m2-3-ui-shell/M2-3-4-SUMMARY.md`）

### 节点模型 (NODE)
- [x] **M2NODE-01**: PipelineDocument 线性链语义（Develop→Color Grade×N→DRT；Develop=RAW→scene-referred；DRT=显示终点非 scene 端口） **Delivered**（M2-4-1 T1：`Graph/PipelineDocument.swift` 纯派生只读门面——零存储字段、`init(_ stack:)` 唯一构造面（漂移结构性不可能，纯函数性测试钉）；develop = baseLayer 投影、grades = `compositeLayers` narrowing（retouch 结构性排除）、DRT = 固定常量 UUID 灰态占位端点（真 DRT 归 M2-6）；mix = opacity 投影零新字段（OQ-6-A）；端点 deletionLocked + mix 恒 1（OQ-7-A）；D-M2-4-CONTEXT-1/6/7 全按推荐 A；PipelineDocumentTests 5 断言组（投影 parity 逐项/retouch 排除/空栈三段/纯函数性）【LAYERS】；锚 `22e3b32`，验收 `phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md`）
- [x] **M2NODE-02**: 图命令集——AddClean(插 identity grade)/Remove+Bridge/Reconnect/Rename/SetEnabled/SetMix(0-1)/InsertFromJson（undo/redo 可复原保 NodeId） **Delivered**（M2-4-1 T2：`Graph/NodeGraphCommand.swift` 7 命令纯数据 `apply(to:)`（「图语义↔层操作」映射表单文件承载；switch 穷举零 default 机检零命中）+ `EditorState.apply` 唯一执行入口（GUI-19 重赋 + 恰一条 structure commit `history_graph_*` 七键族；lockedNode 静默拦截、其余 typed toast——D-M2-4-1-6 非 throwing 裁定）；undo/redo 走既有 `rebuildLayerStack` 快照单路径，UUID 保持由 canonical JSON 逐字节 round-trip 钉死；InsertFromJson 载荷 = SidecarLayerRecord JSON 字节复原（id/paramsData/mask verbatim，retouch 载荷 badPayload 拒绝）；SetMix 钳 0...1 + **SetMix(0) ≡ bypass 像素级断言容差 0**（E4，LayerCompositeDriver CPU 对照 + 防空转 sanity）；`LayerStack.insert(_:at:)` additive + nextLayerName 下沉 Core 单源（M4，EditorState 私有副本删除）；NodeGraphCommandTests 17【APP】；锚 `02a2835`，验收 `phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md`）
- [ ] **M2NODE-03**: 节点内有序调整列表（顺序=用户数据编译器不得重排）+ 18 项目录所有权校验（Clarity/Sharpen/Halation/FilmGrain 属 DRT/Post，Grade 内插入 = typed error）
- [x] **M2NODE-04**: 蒙版 Grade-owned 绑定（每 Grade 多蒙版独立 enabled/opacity/invert；首 Grade 删除锁） **Delivered 数据/绑定面**（M2-4-2 三任务两提交：语义激活 = `MaskCombiner.drawnGroupPlane` 装配前 enabled 恒等元过滤（一行 `continue`，kernel/五式公式零 diff；空 enabled 集 = 既有 dt no-form fill-1 leg 恒 1 passthrough——禁用蒙版=约束解除≠禁用 grade）+ `MaskSpec` 访问面 `maskItems`/`setItemEnabled`/`setItemDisplayName`（值语义，无第二存储，displayName 派生消费 Core 单源 nextLayerName）+ `LayerEditingState` deletionProtected **clear+fill 双腿**拦截（checker E3，toast+零 history item；全仓 mask 写入点 8 触点审计表 DECISIONS 在案）+ `PipelineDocument.maskGroups` 投影（组序=grade 序=层序，M2-7 数据正本；reorder 跟随纯派生证明）+ `node(for:)`/`displayTitle(for:)` 选中映射 + EditorNodeHeaderView 动态名（未选中 = KEY 恒等逐字节不变——zh catalog `editor_node_name`=「调色」实测，D-M2-4-2-2 勘误）；测试 14 新增（MaskItemSemanticsTests 9【APP】+ PipelineLinkageTests 5【LAYERS】，全套 2217/14/0）；锚 `42e2f95`/`9a3e906`，验收 `phases/m2-4-node-model/M2-4-2-ACCEPTANCE.md`；挂账注记：① stroke 腿 `MaskSpec(drawn:)` 重建丢 sibling payload 复核归 M2-7/M2MASK-04（D-M2-4-2-5 登记在案）② feather/应用序=feather→invert→opacity→clamp 归 M2MASK-04 ③ M2-7 Mask Groups 面板 UI 消费面归 M2-7 ④ 新 4 UI 键 + toast 键 zh 滞后挂 P3 收口对账（D-M2-4-CONTEXT-11）→ **已闭环**（M2-4-3 T4：zh-audit exit 0，29 键 zh/en 落盘含本注记所列键族））
- [x] **M2NODE-05**: 持久化——sidecar/项目文件 schema 扩展承载节点图（沿 one-way 格式锁惯例升版本） **Delivered sidecar 腿**（M2-4-1 T4：`.lra` v4→v5 一原子 additive 事务——`MaskGroupItem.enabled/displayName` + `MaskSpec.deletionProtected`（全 Optional，synthesized encodeIfPresent nil 保持 canonical JSON 字节 = stableHash 零漂移逐字节钉）+ `rawOverrides`（encodeIfPresent 缺键；hash-isolated 双向机检：与 overrides 有无无关 historyHash/driftDetected 同值，蒙版字段则 set-fields-move）+ 读者容忍（旧档全 nil、`>5` degrade 不拒载）+ 写者恒发 5；`.lalb` 四表零触碰（项目文件腿归 M2-8 mini-git 激活）；SidecarV5Tests 10【APP】；锚 `b7d7acd`/`48e2b7d`，验收 `phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md`；口径注记：`deletionProtected` 落 runtime/snapshot 拼写，`.lra` 文件载体随 M2MASK-04 补（D-M2-4-1-3，测试断言显式钉缺口））
- [x] **M2NODE-06**: 节点面板 UI——图视图（Develop/DRT 端点节点+Grade 节点+连线+增删改名重连+Fit）SwiftUI/Metal 自绘 **Delivered**（M2-4-3 四任务三提交：`App/Sources/Lightamer/UI/Shell/Nodes/` 三件 = NodeCanvasGeometry 纯函数几何正本【纵向单列 layout/edges/insertionIndex/fitScale，零手写坐标】+ NodesPanelModel【投影订阅 + 选中写 selectedLayerID 仲裁点 + 命令薄路由 + mix live/commit 腿】+ EditorNodesPanelView【ZStack = Canvas 连线层仅画线 allowsHitTesting(false) + 真 SwiftUI 卡片层原生命中，零手写 hit-test；三类卡 + 上下文菜单四项 availableActions 穷举 + 拖卡重连【6pt 阈值 + scrollDisabled 双保险 + 指示线 + insertionIndex 纯函数，自槽 no-op】+ 恒定 Fit + `.nodeLocked(_:hint:)` 泛化三件套 modifier【M2-7 首组锁消费接口，语义冻结 DECISIONS D-M2-4-3-6】】+ EditorToolRailView `.nodes` 空态替换【history/versions 面 diff 零】；AC3 渲染几何机检 = NodeCardFramesKey preference 读回（真面板 NSHostingView 实测帧 = Layout）；测试 NodeCanvasGeometryTests 9 + NodesPanelModelTests 14【APP】，30 节点 layout BENCH 0.0081ms/round 观察行；锚 `b4ea439`/`e245b46`/`34de49a`，收口 `phases/m2-4-node-model/M2-4-3-SUMMARY.md` + `M2-4-ACCEPTANCE.md`（phase 级汇总）；挂账：自由平移/缩放 = CONTEXT Deferred；拖动流畅度/滑杆手感 = Manual-Only 走查观察项（D-M2-4-CONTEXT-10，非门）；zh 对账 exit 0（29 键 T4 落盘）；签核 VALIDATION 归 verify-work）

### Color Grade 控件 (GRADE)
- [ ] **M2GRADE-01**: 18 项封闭目录参数对齐（CAT02 WB 默认 5999.99K identity 2000-15000K+Tint；exposure ±16；contrast 中灰邻域保色相语义新图 +15；White/Black/Shadows/Highlights ±100；curve 单位方形点列；HLS 8-bin+h/l/s_range 45/0.1/0.1+target_hls；saturation 0-4；vibrance ±100；LMT CUBE path；tint ±100——Feature-map §2.1 全表）
- [ ] **M2GRADE-02**: LGG 三向色轮（每轮 disc Vec2+strength+color_offset+luma_offset；gamma/gain identity=(1,1,1)；trackball UI+Reset wheels）
- [ ] **M2GRADE-03**: 产品默认 look（+1.5 EV/contrast +15/saturation 1.3）仅作用于新导入；用户新建 grade 与 reset 恒 identity
- [ ] **M2GRADE-04**: ACEScc 调色域（D4：Grade 内部 AP1/ACEScc 色适应往返，CAT02 创意白平衡语义；相机 WB 留在 RAW Decode/CIRAW 层）
- [ ] **M2GRADE-05**: LUT 库递归扫描 + 子目录分组显示【2026-09-27 用户指令，改进超 Alcedo——其 LutCatalog 只平铺单层目录（`ListCubeLutsInDir` 无递归）】：根目录下任意深度子目录的 `.cube` 全部收录，LUT 面板按子目录树分组/折叠显示；文件增删/目录变更后的刷新与缓存失效语义明确（现状锚点 = `LutLibraryStore` 单层 `contentsOfDirectory`，`Lut3d/LutLibraryStore.swift:105`）
- [ ] **M2GRADE-06**: LUT 根目录用户可配置【同上用户指令】——设置页选择根目录并持久化，不锁死默认位置（默认仍 `~/Library/Application Support/Lightamer/LUTs/`）；切换根目录后重建索引；跨子目录同名冲突的消歧规则与既有查重/自愈（12-5 D-6 能力）整合；被引用 LUT 缺失时 degrade 语义（节点保留、渲染 typed 降级）
- [ ] **M2GRADE-07**: 内置 LUT 库 = Alcedo 同款胶片 LUT 集【2026-09-28 用户指令「把内置的 LUT 换成和 Alcedo 一致」；2026-09-29 用户勘误】——**目标集 = CMake 打包 glob 的 `Agfa_*/Fuji_*/Kodak_*.cube`（Alcedo 真内置集）；安装目录里实测的 Hasselblad 两张 33³ 与「色彩逆向」子目录为用户自放，非内置，不入目标**。**许可门（第一任务）**：从上游 GitHub `JanLohse/spectral_film_lut` clone 原生获取 + 核实其许可（本地无 fork，已查；禁从 GPL-3.0 的 AlcedoStudio 仓拷数据文件——公开仓 config/LUTs 亦不存在）；随包 LICENSE/NOTICE 署名；M2-5 落地

### 显示渲染变换 (DRT)
- [ ] **M2DRT-01**: DRT 节点+面板——Method 分段卡（ACES 2.0/OpenDRT）恒展开；默认 OpenDRT
- [ ] **M2DRT-02**: OpenDRT 预设三件套——Look 7（standard/arriba/sylvan/colorful/aery/dystopic/umbra+custom）+ Tonescale 15 + Creative White 6；45 个 detailed 参数 editor-owned 整体序列化（预设=具名快照）
- [ ] **M2DRT-03**: ACES 2.0——Limiting Space 七选 + ACES reference gamut compression 前置
- [ ] **M2DRT-04**: Color & Encoding——Encoding Space 六选（Rec.709/P3-D65/P3-D60/P3-DCI/XYZ/Rec.2020）+ EOTF 随空间联动 + Peak Luminance 100-1000 nits；HDR 判定 = EOTF∈{ST2084,HLG}，驱动 EDR 预览与导出链
- [ ] **M2DRT-05**: DRT/Post 四件套（Clarity ±100/Sharpen amount-radius-threshold/Halation 0-1/FilmGrain 0-1）在 display transform 后对全图应用一次（预览=成品）
- [ ] **M2DRT-06**: 独有 DRT 扩展位（filmic/sigmoid/agx 按 D1 v1 禁用；架构预留 DRT method 注册口）

### 蒙版 (MASK2)
- [ ] **M2MASK-01**: Radial（center 0.5/0.5、major/minor 0.5、rotation、inner/outer feather，归一化参考空间）
- [ ] **M2MASK-02**: LinearGradient（origin/normal/transition 0.2/start 1→end 0）
- [ ] **M2MASK-03**: Brush（复用 Phase 6 资产对齐 Alcedo 笔划/revision/乐观并发模型）
- [ ] **M2MASK-04**: mask 级属性与语义——display_name/enabled/opacity/invert/feather/deletion_protected；应用序 = feather→invert→opacity→clamp
- [ ] **M2MASK-05**: Nitro 扩展——Follow Edges 边缘感知笔刷（IOP-MASK-06 提级 V1）+ Luminance/Color Range（内核复用 Phase 6，UI 按 Nitro 呈现，D5）+ AI Subject 入口（subject+invert sugar）
- [ ] **M2MASK-06**: 蒙版编辑 UI——图上绘制+手柄 overlay、Mask Groups 面板（组序=grade 序拖动、蒙版缩略图 GPU 管线、锁删提示、Locate unfinished node 提示）、Default Behavior 三选
- [ ] **M2MASK-07**: 蒙版内容单调 revision（MaskContentRevision）+ 笔划追加乐观并发校验

### 版本与历史 (VER)
- [ ] **M2VER-01**: EditCommit 不可变 commit 图（hash 主键、双亲=分支/合并、created_at_ns、kind、edit_payload JSON）
- [ ] **M2VER-02**: VersionRef 命名版本——从导入原始态新建 + branch from current commit + fork from root + rename/remove；版本切换即时、自动保存
- [ ] **M2VER-03**: ImageEditState 材质化缓存（active_version/materialized_head/transaction_chain；仅加速恢复非用户概念）
- [ ] **M2VER-04**: 历史=版本内线性事务流——每行操作名+参数 delta+时间；永久 undo/redo（跳回后 redo 尾巴保留、再编辑丢弃尾巴）；崩溃恢复条
- [ ] **M2VER-05**: Copy Adjustments——三层面板（Version→Node→Item 勾选）Paste 生成新 Version；不复制 RAW decode/lens/crop-rotation

### 导出选项 (EXP2)
- [ ] **M2EXP-01**: 尺寸四模式——Original/Long Edge/Bounds W×H/Print（in-cm-mm+DPI）+ allow_upscale + maximum_edge_pixels
- [ ] **M2EXP-02**: 元数据策略档位——默认剥离 location/设备序列号/编辑历史；EXIF 写入本 app 版本号
- [ ] **M2EXP-03**: 文件名模板——12 字段（stem/capture_date/camera/lens/iso/aperture/shutter/focal/rating/sequence 补零+literal）+ 冲突 FAIL/REPLACE + 子文件夹
- [ ] **M2EXP-04**: 输出 ICC 与本图 DRT 编码强制联动（space/EOTF/peak nits 入队前已解析）；格式矩阵保留原 6 格式（EXR/UltraHDR = V2 ALCE-02/03）
- [ ] **M2EXP-05**: 导出队列 UI（检查器内+Queued/Exporting/Done/Failed 四态+质量跨会话记忆）；yiyin 印框/水印终步保留适配

### AI 图库 (AI2)
- [ ] **M2AI-01**: 本地 CLIP 嵌入——CoreML 档模型可选（MobileCLIP2-512/SigLIP2/Jina-768 级），本地运行不上云。**模型获取 = 混合策略（✅ 2026-09-27 用户批准「就按这个方案」：五件套 = CLIP 搜索/自动打标/AI 评片/AI 描述/本地不上云承诺，每件带改进——默认模型内置免下载、MCP server 外部 agent 入口、编辑侧 AI 既有优势；默认模型须中文文本塔可用，具体档位 M2-10 research 实测后定）**：①默认语义模型**内置 app 包**（MobileCLIP2-S2 int8 CoreML ≈40-80MB）——零下载零网络依赖，反向消除 Alcedo 实测的「应用内下载 AI 离线包全报错」痛点（其默认端点已是 hf-mirror.com 但仍失败，疑 `model_assets.rs:496` `_hf_endpoint` 参数未接线）；②SigLIP2/Jina 大档走**本仓 GitHub Release 资产**可选下载（版本锁死），HF/hf-mirror 兜底；③权重许可（MobileCLIP MIT/CoreNet Apache-2.0 待核）与 int8 量化管线入 M2-10 research
- [ ] **M2AI-02**: 嵌入存储+ANN 检索（SQLite 向量方案执行时定，对标 HNSW 近邻）+ 自然语言搜索入全局搜索三合一
- [ ] **M2AI-03**: 自动打标——出厂中英 label query 原型嵌入余弦（score/second_label/margin/confident）+ 导入后询问 Remember-my-choice
- [ ] **M2AI-04**: AI 评片——OpenAI/Anthropic 兼容 endpoint、1-5 星+理由（clamp；rating=0 reasons-only 哨兵）、星级写库、严格度+输出语言设置
- [ ] **M2AI-05**: AI 描述——caption+tags+scene+confidence + 全文检索文档（描述/标签进全局搜索）
- [ ] **M2AI-06**: 凭据与安全——Keychain 存 key（zeroize）+ 强制 HTTPS（localhost dev 例外）+ prompt profile 护栏（rubric 变更可检）
- [ ] **M2AI-07**: 后台执行——任务注册表+取消，分析期间可继续工作
- [ ] **M2AI-08**: MCP server 保留互补（Phase 14 资产；launcher 与外部 client 双入口照旧）

### 性能与收口 (M2PERF)
- [ ] **M2PERF-01**: 原 PERF-01..07 按新架构重校——60fps@100MP 决战/零卡顿 hitch=0/RAW9 解码 500ms 可交互/懒加载万张 60fps/批量 apply 万张≤5s/内存 3GB/Instruments profile 落账
- [ ] **M2PERF-02**: M2 全族 SC 终验 + VALIDATION + verify-work 签核

## v1 Requirements（里程碑 1 历史账，2026-08-03 定义）

Requirements for initial release. Each maps to roadmap phases.
v1 = 完整工作流闭环 + 蒙版系统 + HDR/堆栈 + 印框/水印 + 全量 iop（按 Fine 粒度分阶段交付，不设上限）。

### Platform & Foundation (FOUND)

- [ ] **FOUND-01**: 应用基于 Swift 6 + SwiftUI + Metal 3 + Core Image（CIRAW，macOS 27 起原生 RAW 9）+ ImageIO 构建，macOS 27 为最低版本
- [ ] **FOUND-02**: 工作色彩空间锁定为 linear Rec2020 scene-referred，pixelpipe 内部数据类型为 float32 RGBA（与 Darktable modern pipeline 对齐，便于移植算法）
- [ ] **FOUND-03**: iop 模块系统采用 Swift `protocol IOPModule { associatedtype Params: Codable, Hashable }`，模块顺序采用 Darktable `v50_order` 位置方案（rawprepare→demosaic→colorin→creative iops→colorout→gamma）
- [ ] **FOUND-04**: pixelpipe 多分辨率架构（FULL/PREVIEW/THUMBNAIL/EXPORT 至少四条管线），每模块带 per-module per-ROI 缓存（hash 命中跳过上游），参数拖动时只重算受影响模块
- [ ] **FOUND-05**: 主编辑视图用 MTKView/MTLTexture 直接渲染 Metal 输出，通过 NSViewRepresentable 与 SwiftUI 桥接，参数拖动 60fps（100MP+ 下不卡顿）
- [ ] **FOUND-06**: Metal compute shader 调度框架（build-time 编译 kernel、function-constants、PSO 缓存），支持 tile-based 处理以避免 100MP 全量入内存
- **FOUND-07**: macOS 27 起原生 CIRAW 9（Core ML demosaic+denoise on Neural Engine）通过 `#available` opt-in；未来 macOS 升级时无需改架构即可获益

### RAW Decoding & Input (RAW)

- [ ] **RAW-01**: 通过 CIRAWFilter 读取主流相机 RAW：佳能 CR3、尼康 NEF、索尼 ARW、富士 RAF、松下 RW2、奥林巴斯 ORF、适马 X3F、宾得 PEF、徕卡 DNG、Phase One IIQ 等
- [ ] **RAW-02**: 读取 Adobe DNG（含嵌入原始 DNG 与转换 DNG）
- [ ] **RAW-03**: 读取 32-bit float TIFF/EXR/HIF 作为 HDR/堆栈源文件
- [ ] **RAW-04**: 读取非 RAW 格式作为输入并支持调色：JPEG、HEIC、PNG、WebP、TIFF、PSD（扁平）
- [ ] **RAW-05**: macOS 27 起原生 CIRAW 9（Neural Engine demosaic+denoise）；macOS 27 以下场景若必须降级，需明确支持的相机子集与回退策略
- [ ] **RAW-06**: EXIF/IPTC/XMP 元数据读取（相机型号、镜头、焦距、光圈、快门、ISO、GPS、拍摄时间）

### Capture One Session Management (SESS)

- [x] **SESS-01**: "文件夹即会话"模型——选择一个文件夹作为 Session 根，所有操作围绕该文件夹，不做中央库
- [x] **SESS-02**: Session 内自动维护 Capture（原片）/ Crop（调整副本）/ Output（导出）三级子目录结构（沿用 Capture One 习惯）
- [x] **SESS-03**: sidecar 调整文件随原片存放于 Capture 子目录，格式为 Lightamer 自有格式（不与 Darktable 二进制兼容，最大化参数调节能力）
- [x] **SESS-04**: 多 Session 切换 + 最近会话列表（最近打开、快速切换）
- [x] **SESS-05**: FSEvents 文件夹监视——外部新增/移动/删除文件时自动同步到 Session 视图（含 edge case：用户在 Finder 中移走文件后的孤儿 sidecar 处理）
- [x] **SESS-06**: Session 内浏览模式：网格视图（thumbnail grid）、单图大图、culling 对比视图（多图并排筛选）
- [x] **SESS-07**: 会话级索引 DB（可重建派生缓存，C1 `.cosessiondb` 同构）——sidecar 索引（params hash/评分/图层栈摘要）+ 缩略图索引；**真身恒为 sidecar**，DB 删除无损可重建；批量 apply = 索引单事务 + sidecar 批量写队列（懒渲染基座，PERF-07 万张 ≤5s）
  **Delivered**（Phase 9，SESS-01..07）：五步编排 + 三级目录幂等（SESS-02 = REQUIREMENTS 字面三级，Trash/Selects 不建、Crop/ v1 空目录维护——D-09-CONTEXT-3）+ `.lra` 同目录自有格式（L003/L013）+ recent 去重/上限 + FSEvents hint-only 四缺陷对策与四时点 reconcile（SESS-05 孤儿处置 = 移除带确认/忽略持久化两动作，永不硬失败）+ 浏览三态（SESS-06 culling v1 = 2 图 cap，D-09-CONTEXT-6）+ 索引 DB schema v1 冻结 25 列（Phase 12 预留列在表）+ 删库重建逐列 parity。证据：09-VALIDATION SC#1-6 三列对照 + Session 族 100+ 测试 + FINDINGS 09-3/09-4 真机走查。

### History & Non-Destructive Editing (HIST)

- [ ] **HIST-01**: 非破坏性编辑——所有调整存为参数序列（history stack），原文件永不被修改
- [ ] **HIST-02**: 完整 history stack——支持任意时刻的撤销/重做、跳转到任意历史点、压缩/展开历史步骤
- [ ] **HIST-03**: history stack 持久化到 sidecar（含模块顺序、multi_priority、multi_name、blendop 参数）
- [ ] **HIST-04**: history hash 用于漂移检测（参数变化时正确失效缓存，避免蒙版失效类损坏）
- [x] **HIST-05**: 调整同步/复制粘贴——复制一张图的全部或部分调整参数到其他图（多选批量应用）
- [x] **HIST-06**: before/after 对比预览（分屏对比、快照点对比、按住键临时查看原图）
  **Delivered**（Phase 9）：三式粘贴（overwrite/merge/partial）+ skip 集（decode 域 `< ashift 15.0`，D-09-04-D1——plan 公式修正，dt 正本 flag 制）+ 单提交 pasteSet additive 机制（⌘Z 恰 1 + 旧档兼容）+ 三段式批量管线（索引单事务 + 串行写队列 + 崩溃自愈；pristine 目标铸造自洽 doc）；before/after 三形态（split 双平面 / peek 逐字节==重放 / hold 零渲染）。注记：**跨图 undo 组（批级撤销）defer v2**（per-image commit 可退）。证据：PasteSemanticsTests 16 + SessionBatchApplierTests 12 + BeforeAfterTests 5 + FINDINGS 09-4 真会话全链。

### Image Operation Modules (iop) — Tone (IOP-TONE)

按 Darktable 全量对标，Fine 粒度 roadmap 分阶段交付。v1 起逐步覆盖以下模块：

- [x] **IOP-TONE-01**: exposure（曝光）
- [x] **IOP-TONE-02**: temperature / white balance（白平衡：色温/色调，含吸管取色）
- [x] **IOP-TONE-03**: tonecurve（色调曲线，可作用于 RGB/各通道）
- [x] **IOP-TONE-04**: shadow & highlight（阴影/高光恢复）
- [x] **IOP-TONE-05**: contrast（对比度）
- [x] **IOP-TONE-06**: levels（色阶）
- [x] **IOP-TONE-07**: tone equalizer（色调均衡器，Darktable 高价值模块）

### Image Operation Modules (iop) — Filmic / Scene-Referred (IOP-FILM)

- [x] **IOP-FILM-01**: filmicrgb（Darktable 标志性 scene-referred tone mapping，最复杂的移植之一，需早期 spike）
- [x] **IOP-FILM-02**: sigmoid（替代 tone mapping）
- [x] **IOP-FILM-03**: hatchless / other filmic variants

### Image Operation Modules (iop) — Color (IOP-COLOR)

- [x] **IOP-COLOR-01**: colorbalancergb（色彩平衡 RGB，高级色彩调整）
- [x] **IOP-COLOR-02**: color calibration（色彩校准，channel mixer 升级版）
- [x] **IOP-COLOR-03**: vibrance / saturation（自然饱和度/饱和度）
- [x] **IOP-COLOR-04**: channel mixer（通道混合器）
- [x] **IOP-COLOR-05**: color zones（色相/饱和度/亮度的分区域调整）
- [x] **IOP-COLOR-06**: monochrome / black & white（黑白转换，含色彩滤镜模拟）
- [x] **IOP-COLOR-07**: velvia（鲜艳度）
- [x] **IOP-COLOR-08**: LUT (.cube) 作为 iop 模块——导入并应用 1D/3D .cube LUT（含 DOMAIN_MIN/MAX、tetrahedral 插值，参考 Darktable lut3d） —— **Delivered（Phase 12）**
- [x] **IOP-COLOR-09**: color contrast / color correction curves — **已交付=colorcontrast（56.0）**；rgbcurve/rgblevels 划出 Phase 5（D-05-CONTEXT-1），Phase 6+ stretch 补齐（CurveTools 全复用机械增量）

### Image Operation Modules (iop) — Detail & Sharpen (IOP-DETAIL)

- [x] **IOP-DETAIL-01**: sharpen（锐化，含 USM 与高斯/拉普拉斯变体）
- [x] **IOP-DETAIL-02**: local contrast（局部对比度，等效 clarity）
- [x] **IOP-DETAIL-03**: highpass / soften
- [x] **IOP-DETAIL-04**: equilizer / detail enhancement

### Image Operation Modules (iop) — Denoise (IOP-DENOISE)

- [x] **IOP-DENOISE-01**: raw denoise（profiled denoise，基于相机噪声 profile，Darktable denoise (profiled) 的 Metal 移植，最复杂移植之一）
- [x] **IOP-DENOISE-02**: non-local means denoise（非局部均值）
- [x] **IOP-DENOISE-03**: bilateral / surface blur — 已交付：直连档（rad≤6）+ 稠密 5D 网格档（dt lattice 同族近似，D-05-08-T2-2）
- [x] **IOP-DENOISE-04**: hot pixels / dark frame / chromatic noise — chromatic noise 已交付（05-06 chroma 参数 + 05-07 Y0U0V0 模式）；**hotpixels/dark-frame 正式 defer**（hotpixels.c:94 IOP_CS_RAW Bayer 域 + CIRAW 无 despeckle 键——需求解释权裁决，非缺口；重启 = v2 自研 RAW 解码），cacorrect 复议维持 defer（D-05-08-T4-1，与 Phase 6 无关）

### Image Operation Modules (iop) — Geometry & Lens (IOP-GEO)

- [x] **IOP-GEO-01**: crop（裁剪，含比例锁定、旋转微调）
- [x] **IOP-GEO-02**: rotate / perspective（旋转/透视校正，含自动检测）
- [x] **IOP-GEO-03**: lens correction（镜头校正：几何畸变、横向色差、渐晕——CIRAW 不足部分用 Metal 补，含 lensfun-style 数据库或自有 profile）
- [x] **IOP-GEO-04**: flip / orientation（翻转/方向）
- [x] **IOP-GEO-05**: liquify（液化，肖像修饰，复杂模块）——**已交付（06-06）**：base 链 18.0 warp 模块（bezier 路径 + 扭曲场 + lanczos/bicubic kernel）；扭曲场解析 ≤2.4e-7、warp parity 0.0、蒙版内容锚定经 GeometryPointMapper liquify 段
- [x] **IOP-GEO-06**: retouch（修复画笔/克隆，依赖蒙版框架）——**已交付（06-07，独立图层 kind，D-06-CONTEXT-4）**：四算法 clone/heal/blur/fill（heal 基准 median ~10ms 预算内，降级条款未触发）；stroke 形状即蒙版（NO_MASKS）；v1 圈定：视口圆形绘制（path 数据腿就绪）、blur gaussian、fill 纯色

### Layers System (LAYER) — Capture One 风格调整图层

Lightamer 采用 Capture One 风格的 adjustment layers 作为局部调整的核心组织机制。每个图层是一个独立的调整容器，携带自己的 iop 参数 + 蒙版 + 混合方式。这是与 Darktable（全局 pixelpipe + per-iop 蒙版）的根本架构差异，必须在 pixelpipe 设计时就纳入考虑（roadmapper 会规划具体架构）。

- [x] **LAYER-01**: 背景层（base layer）+ 多个可命名调整图层（adjustment layers）的图层栈模型——**已交付（06-01 层核 + 06-07 retouch kind 扩展）**：`any Layer` 双 kind 栈（adjustment + retouch）
- [x] **LAYER-02**: 每层独立 iop 参数——**已交付（06-01，层 K 增量账本 + 24 面板零改动路由 06-05）**
- [x] **LAYER-03**: 每层蒙版——**已交付（06-03 drawn + 06-04 parametric/raster + 三类 ⊗ 装配单平面；内容锚定经 GeometryPointMapper，D-06-CONTEXT-7）**
- [x] **LAYER-04**: 层管理——**已交付（06-05 UI + 06-01 data face）**；注记：合并 = mergeDown v1 交付；**编组（层文件夹）= v2**（D-06-CONTEXT-6——纯 UX 组织，蒙版组由 MaskGroup 内嵌套承载）
- [x] **LAYER-05**: 混合模式——**已交付（06-01 定案 + 06-02 引擎）**：值不重编 + dt MODERN 公式（D-06-CONTEXT-2）+ REVERSE 位 + PS dodge/burn 新值增补；dt 三证据 54/54
- [x] **LAYER-06**: 图层与全局 iop 的协作——**已交付（混合模型 (c)，06-RESEARCH §1）**：base 链全局 iop + 1+N+1 合成（层子链 + blend 三元组），walk/缓存/ROI 零改动；轨 B 恒等层逐字节实证
- [x] **LAYER-07**: 图层状态持久化到 sidecar——**已交付（06-01 sidecar v2 + 06-03/04 mask payload + 06-07 retouch strokes）**：真 RAW E2E 渲染逐字节（06-05）；history 双轨全粒度；ONE-WAY 拼写锁

### Image Operation Modules (iop) — Masking / Local (IOP-MASK)

蒙版系统服务于 LAYER（每层一个蒙版）。蒙版形态：

- [x] **IOP-MASK-01**: drawn mask——**已交付（06-03）**：五形态 GPU 光栅化（解析 ≤1e-6）+ combine 组壳 + maskVersion 缓存键
- [x] **IOP-MASK-02**: parametric mask——**已交付（06-04）**：luma+JzCzhz 单 kernel（D-06-CONTEXT-3）；注记：dt 双域 UI（Lab+RGB）defer——可逆扩展位
- [x] **IOP-MASK-03**: raster mask——**已交付（06-04）**：旁挂 16-bit PNG + StableHash 校验 + 三失败腿降级；Phase 7 AI mask 经此通道消费
- [x] **IOP-MASK-04**: mask combining operations——**已交付（06-04）**：五式逐行 + 嵌套组 + 解析面积 golden
- [x] **IOP-MASK-05**: 蒙版可应用于任意调整图层——**已交付（06-04 T5 驱动器接线）**；retouch 层除外（NO_MASKS，D-06-CONTEXT-4）

### Image Operation Modules (iop) — HDR & Stacking (IOP-HDR)

- [x] **IOP-HDR-01**: HDR merge（多张不同曝光的 HDR 合并，含对齐、鬼影去除）
- [x] **IOP-HDR-02**: focus stacking（焦点堆栈合并）
- [x] **IOP-HDR-03**: average/median stacking（平均值/中位数堆栈降噪）
- [x] **IOP-HDR-04**: 32-bit float HDR pipeline 支持（合并后可继续在 linear Rec2020 中调整）
- [x] **IOP-HDR-05**: HDR/EDR 显示输出（在支持 EDR 的显示器上呈现真实高动态范围）

### Image Operation Modules (iop) — Effects (IOP-FX)

- [x] **IOP-FX-01**: vignette（渐晕）
- [x] **IOP-FX-02**: grain（胶片颗粒）
- [x] **IOP-FX-03**: bloom / glow（光晕）
- [x] **IOP-FX-04**: dehaze（除雾）
- [x] **IOP-FX-05**: watermark/text overlay（作为 iop 层，独立于 yiyin 面板的最终出图水印）

### AI Modules (AI) — 基于 Apple Vision / Core Image 原生框架（v1 仅含原生可实现项）

**划分原则**：v1 仅纳入 Apple 原生框架（Vision / Core Image / Core ML 系统提供）可直接实现、无需自定义训练模型的 AI 能力。需自定义 Core ML 模型的进 v2。研究阶段已确认能力边界（见 `.planning/research/SUMMARY.md` 与 STACK.md）。

**v1 AI（全部基于公开 Vision/Core Image API，零自定义模型、Neural Engine 加速、本地运行无联网；例外：tap-to-segment 层 B `GenerateIterativeSegmentationRequest` 首次使用需一次性模型下载——层 A 与磨皮定位请求全程离线，D-07-CONTEXT-1）：**

- [x] **AI-01**: 主体检测蒙版（subject isolation）——基于 `VNGenerateForegroundInstanceMaskRequest`（macOS 14+，WWDC26 增强 iterative tap/scribble/lasso），自动识别人/动物/食物/物体（class-agnostic），适用于任意 demosaic 后的 RAW 图像
  **Delivered**（Phase 7）：层 A 一键离线 + 层 B tap/box 精修（D-07-CONTEXT-1 双层共存，assetStatus 三态门控）；scribble/lasso 手势 = v1 后（D-07-CONTEXT-4，种子枚举升级缝预留）；多主体 instance 勾选浮层。证据：07-1 确定性/语义门 + 07-3 MaskToolbar AI 组/SegmentEditingOverlayHost + FINDINGS 07-3 真机走查。
  - 注记（2026-09-26 登记）：**AI Background 类型入口** = subject 蒙版 + invert 组合的 UI sugar（combine inverted 已交付），对标 Nitro Photo AI Background；任意 UI 轮捎带，不立新需求。
- [x] **AI-05**: AI 磨皮——基于 `VNFaceLandmarks2D` + `VNGeneratePersonSegmentationRequest` 定位皮肤区域，Core Image 高斯模糊/高通滤波实现频率分离（frequency separation），保细节平滑、肤色自然不塑料感；无需自定义模型
  **Delivered**（Phase 7）：skinSmooth iop @ V50Order 66.5（两频高斯 + raised-cosine 阈值衰减防塑料感，D-07-CONTEXT-6；多频/bilateral 变体 = v2 位预留）+ SkinRegionLocator（hull−保护区⊗personSeg，yaw 门）+ 面板第 25 席（「定位皮肤」接线）。证据：float64 parity 6×6 <1e-5 + 恒等三元组逐字节 + PanelWiringTests 60/60；pore-level 目检 = Manual-Only 挂账（待含人脸样张）。
- [x] **AI-06**: AI 蒙版作为图层/参数蒙版输入——AI 生成的 mask 可烘焙为 raster mask 或直接作为 parametric mask 应用到任意调整图层；注记：**像素 mask 走 raster 烘焙（v1 唯一忠实通道）**，parametric 语义曲线预设（肤色 hz 曲线）留 v2（D-07-CONTEXT-3）
  **Delivered**（Phase 7，raster 口径）：AIMaskResample 双线性 + RasterMaskStore.bake 羽化增件 → `MaskSpec.raster` 写选中层 mask 槽（恰 1 stackSnapshot，⌘Z 可退）；层 B 下载例外 = D-07-CONTEXT-1（本节头注）。证据：RasterMaskRoundTrip 9/9 + LayerUIWiringTests + GUI 真机（FINDINGS 07-3：bake 落盘 + ⌘Z 恰 1 + overlay ΔR 量化）。
- [x] **AI-07**: AI 蒙版可编辑/精修——AI 生成的蒙版不是黑盒，可手动调整边缘、羽化、反向、与其他蒙版组合
  **Delivered**（Phase 7）：五条覆盖路径内容级 E2E（drawn 修补/parametric ⊓ 收紧/invert/羽化重 bake/refine 同 maskID 重生成——AIMaskEditPathsTests 6/6）+ sidecar schema 零升级（AI 参数不落盘逐字节断言）+ refine 精修 = 同 maskID 覆盖重 bake（D-07-CONTEXT-5，缓存链自动失效）。

**以下 AI 能力因 Apple 无公开原生 API（需自定义 Core ML 模型）→ 移至 v2（见 v2 章节 AIV2）：**
- 天空分离（通用 RAW）——`CIRAWFilter.semanticSegmentationSkyMatteImage` 仅能读取 iPhone ProRAW 嵌入的 matte，不能从任意 DSLR RAW 计算
- 人像部位分割（皮肤/头发/嘴唇/眼睛等独立 mask）——`AVSemanticSegmentationMatte` 仅 iPhone 捕获时数据；DSLR RAW 需自定义 face-parsing Core ML 模型
- 通用语义分割（植被/建筑/水体/雪地等）——无公开多类分割 API，需自定义 DeepLab/Mask2Former 模型

### Color Management (COLOR)

- [ ] **COLOR-01**: 色彩管理 pipeline——camera RGB → linear Rec2020 working → display (Display P3 / ICC profile) → output (sRGB / Display P3 / Adobe RGB / ProPhoto / Rec2020)
- [x] **COLOR-02**: 软打样（soft proofing）——模拟打印机/输出设备的色彩空间，含 out-of-gamut 警告 —— **Delivered**（13-2：显示腿 runtime override + colorout 上游 proof 段 + gamut check 黑裁剪；BPC 探针落档；wiring 单测 + GUI 菜单在案）
- [x] **COLOR-03**: 多显示器 ICC profile 自动切换 —— **Delivered**（13-2：通知驱动 re-resolve + window↔screen 追踪 + Settings 手动覆盖；terminal-segment 翻键单测钉；真双屏 live 观感遗留 Manual-Only）
- [ ] **COLOR-04**: camera profile 支持（CIRAW 内置 profile；未来扩展 DCP-style 自定义 profile）

### Border / Watermark (yiyin panel) (YIYIN)

将 yiyin（壹印）作为 Lightamer 内置一等公民面板，功能对齐 yiyin 现有能力：

- [x] **YIYIN-01**: 白边/印框生成（边距、比例、颜色、是否按原比例扩展、竖转横/横转竖布局）—— **Delivered**（08-1：BordersModule 76.0 + YiyinLayout 逐值 parity + 全腿渲染；08-3 T1 面板整合）
- [x] **YIYIN-02**: EXIF 信息叠加（拍摄参数：相机/镜头/焦距/光圈/快门/ISO/拍摄时间，可配置字段与格式）—— **Delivered**（08-2 格式化层 15 字段 + 08-3 T2 decoder walk 真实样张接通；品牌 Logo 明暗 auto 分派）
- [x] **YIYIN-03**: 日期文字（可配置字体/大小/颜色/位置/旋转）—— **Delivered**（v1 口径 = 行内语义 + 九宫格锚点，D-08-CONTEXT-2；rotation 参数位预留，完整旋转 defer v2）
- [x] **YIYIN-04**: Logo 水印（PNG/透明图，可配置位置/大小/透明度）—— **Delivered**（v1 口径 = 九宫格锚点 + 透明度滑杆，D-08-CONTEXT-2/5；内嵌 26 件品牌 PDF + 用户上传双通道）
- [x] **YIYIN-05**: 自定义字体管理（用户可上传 .ttf/.otf，仅本地存储不联网）—— **Delivered**（08-2 T5 YiyinFontStore：会话注册 + 启动重扫自愈 + typed 四错；零联网）
- [x] **YIYIN-06**: Make/Model 品牌名归一化（如 Sony ILCE→α、Nikon Z→ℤ，移植 yiyin 的 model-map）—— **Delivered**（08-2 T2 表驱动逐点；D-08-2-2 定性 model-map.ts 为死代码面——归一化走 exif-format 活跃路径，忠实 yiyin 实际行为）
- [x] **YIYIN-07**: 文字模板系统（预设模板 + 用户自定义模板字符串）—— **Delivered**（08-2 T3 引擎三门/交错/forceUse + 面板 CRUD 稳定 key 行）
- [x] **YIYIN-08**: 输出尺寸/分辨率配置（DPI、长边/短边像素、是否保留原尺寸）—— **Delivered**（08-3 T3 YiyinExportSettings 独立值类型 + 校验 + 纯 targetSize 数学 + 与水印参数正交；物理应用 resize/DPI 写入 = Phase 11 EXP-03、导出消费点 = EXP-05，D-08-CONTEXT-7 裁决）

### Metadata & Organization (META)

- [x] **META-01**: 星级评分（0-5 星） —— **Delivered（Phase 12）**
- [x] **META-02**: 颜色标签（C1 风格彩色标签） —— **Delivered（Phase 12）**
- [x] **META-03**: 关键字/标签（层级关键字、批量编辑） —— **Delivered（Phase 12）**
- [x] **META-04**: 标准 EXIF/IPTC/XMP 读写（与其他工具兼容，评级/标签/关键字随 sidecar 同步） —— **Delivered（Phase 12）**
- [x] **META-05**: 按评分/标签/关键字/相机/镜头/日期/ISO/焦距等过滤与排序 —— **Delivered（Phase 12）**
- [x] **META-06**: 智能相册/动态集合（基于规则的虚拟分组，不复制文件） —— **Delivered（Phase 12）**

### Presets & Styles (PRES)

- [x] **PRES-01**: 原生预设系统——保存完整调整堆栈为 Lightamer 预设（.lightamer-preset，JSON/Codable） —— **Delivered（Phase 12）**
- [x] **PRES-02**: 预设管理器（创建/编辑/删除/导入/导出/分类） —— **Delivered（Phase 12）**
- [x] **PRES-03**: .cube LUT 导入与应用（作为 IOP-COLOR-08 模块的能力，含 1D/3D、DOMAIN_MIN/MAX、tetrahedral 插值） —— **Delivered（Phase 12）**
- [x] **PRES-04**: 预设可应用于单图或批量多图 —— **Delivered（Phase 12）**

### Export (EXP)

- [x] **EXP-01**: 导出格式：JPEG（含质量参数）、PNG（含 8/16-bit）、TIFF（含 8/16/32-bit float、压缩选项）—— **Delivered**（11-02 六格式编码面 + golden 矩阵：PNG/TIFF 8|16 全压缩变体逐位、TIFF 32f 1-ULP（float 域 bitwise 不可达，1e-6 带）、JPEG quality 已知点；JPEG-in-TIFF 刻意缺席【有损域上线性歧义】；E2E 探针终判 `ExportPhaseE2ETests`）
- [x] **EXP-02**: 导出格式：HEIF/HEIC（含质量、10-bit）、WebP（依赖 libwebp SPM，含质量/有损无损）、AVIF（macOS 27 起原生，否则依赖 libavif SPM，含 8/10/12-bit）—— **Delivered**（macOS 27 地板下 AVIF = 原生 `public.avif` 单路径，libavif 不进 v1（D-11-CONTEXT-1，UTI 本机探针钉死）；libwebp = 全项目唯一新 SPM 依赖。**注记：AVIF 12-bit 请求落 10-bit**（宿主 `l12p` 封顶，文档化降级 R1 + golden depth==10 锚 + `AVIFEncoder` conformer 替换缝保留）；**WebP 元数据 v1 例外**（Swift-WebP 零 mux 面，OQ-11-5 + RIFF 结构锚，Phase 12/14 复审位））
- [x] **EXP-03**: 导出尺寸/分辨率/DPI 配置、长边/短边/百分比/原尺寸 —— **Delivered**（sizing 复用 `YiyinExportSettings`（OQ-11-6 正主）四模式 + 永不放大钳 + `scalePercent` 折算向量 + DPI 1..2400 写入（72/300 落盘实测）；E2E 尺寸向量 512×342/384×256/256×171/奇数 257×171 精确）
- [x] **EXP-04**: 输出色彩空间选择（sRGB / Display P3 / Adobe RGB / ProPhoto / Rec2020，含嵌入 ICC profile）—— **Delivered**（`ExportColorSpaceMapper` 五空间单表 + ColorSync 精确路径 + ICC 名逐格式 golden + display/linear 双 TRC 风味。**注记：32f 线性 ICC 变体宿主只供 sRGB/P3/Rec2020**——adobeRGB/proPhoto×32f typed throw（11-02 D2）；ProPhoto = 系统 ROMM 档案（D1））
- [x] **EXP-05**: 导出时应用 yiyin 印框/水印（导出流水线的最后一步，与编辑器内 yiyin 面板共享配置）—— **Delivered**（联合上下文注入 = 08-3 T3 生产接线义务闭环；`ExportYiyinInjector` Core 缝 + App 生产注入器（coordinator 语义镜像）；共享 `YiyinExportSettings`/模板/logo faces；yiyin 开启但缺注入器 = typed error（静默丢印框禁止）；11-03 yiyin E2E + 11-05 真队列有印框 round-trip）
- [x] **EXP-06**: 批量导出队列——后台执行多图导出，含进度、可取消、失败重试 —— **Delivered**（`ExportQueue` actor：generation cancel + cancel(jobID) 三 gate + pump FIFO + 并发 1（内存红线 D-11-CONTEXT-2）+ **低优先级 = Utility QoS 替代**（`MTLCommandQueue` 无公开 priority API，SDK 头实证 RESEARCH §4.4——checker M3）+ 两层进度快照 + retry 显式（仅 failed、队尾新 seq）+ `yieldsToEditor` 接口位（Phase 15）；v1 无 queue journal（D-11-CONTEXT-8，幂等重试 + tmp 原子晋升替代）；13 队列语义单测）
- [x] **EXP-07**: 多规格同导（同一原片一次性输出多种尺寸/格式/水印组合的导出配方 export recipe）—— **Delivered**（`enqueue` N images × M variants 单动作 + tag 派生不互覆（`<stem>_<tag>` + `-1` 递增 + 大小写不敏感占用）+ E2E 1 源×8 变体一次落盘逐文件对照 + 同目录二导 `-1` 递增原文件不动。**注记：recipe v1 不持久化**（session 生命周期，D-11-CONTEXT-3）——类型已 Codable 零哈希字段，Phase 12 PRES 直挂即升级）
- [x] **EXP-08**: 导出后执行动作（如运行 shell 脚本、打开文件夹）—— **Delivered**（脚本路径制（普通 bookmark + 可达性重验降级，D-11-CONTEXT-6 注入面收窄）+ `Process` 直 exec 不经 shell 解释（**注入面自查 PASS**：`$()`/反引号/分号路径逐字进 `$1`、哨兵未创建）+ Finder `activateFileViewerSelecting` + per-job completion hook（仅 `.done` 且当代触发，OQ-11-7））

### System Integration (SYS)

- [x] **SYS-01**: Quick Look 扩展——Finder 中按空格预览 RAW 文件（含调整后预览，不仅是原片缩略图）—— **Delivered**（13-1 appex + QuickLookRenderer 三查回退链；13-4 实机 QL 预览=编辑态渲染证实）
- [x] **SYS-02**: Spotlight 索引——通过 RAW 调整后状态检索（评级/标签/关键字/EXIF 元数据可被 Spotlight 检索）—— **Delivered**（13-1 importer + 34 列抽取源；lindex 行实测健康；mds 级绑定待 /Applications 安装复测——13-4 SUMMARY 遗留#2）
- [x] **SYS-03**: 触控板/鼠标手势（双指缩放、捏拉、旋转、双指拖动平移）—— **Delivered**（13-3 AppKit recognizer 面 + viewportTransform 单源 + overlay 互斥矩阵；HUD/100%/Z/F 入口 AX 在案；触控板手感 Manual-Only）
- [x] **SYS-04**: 拖放导入（从 Finder 拖入 Session 或直接拖入编辑）—— **Delivered**（13-3 ImportService 三落点 + 复制默认/Option=Move + 源零改动 golden；拖放观感 Manual-Only）
- [x] **SYS-05**: 多语言跟随系统（String Catalog，至少 zh/en，结构预留扩展）—— **Delivered**（13-1..13-3 新 UI 全键 zh 同批 + 键审计；13-4 走查抓修 delete-confirm 裸键回退）

### Distribution & Project (DIST)

- [x] **DIST-01**: GitHub 开源仓库（MIT 或类似宽松许可证）—— **Delivered**（13-4：github.com/kamasylvia/Lightamer public + MIT LICENSE + 敏感审计闸前置）
- ~~**DIST-02**: Developer ID 签名 + 公证~~ —— **Removed（2026-09-27 用户终裁：砍苹果分发渠道）**；非沙盒决策不变；如未来重启 Apple 渠道作 v2 候选（make-dmg.sh 的 ad-hoc 覆盖届时移除）
- [x] **DIST-03**: DMG / zip 分发 —— **Delivered**（13-4 make-dmg.sh：UDZO 拖装 DMG + zip + SHA256SUMS，unsigned；产物实机启动验证）
- [x] **DIST-04**: CI（GitHub Actions：构建、测试、发布）—— **Delivered（范围修订：签名/公证段随 Apple 渠道砍除）**（13-4 ci.yml：push/PR build+test 无签名；v* tag → artifacts + Draft Release 人工发布）

### Catalogs Mode (CATALOG)【2026-09-27 用户指令新立；同日用户终裁 v1 后端 = 本地 SQLite，pg 降为 v2 评估项】

对标 Capture One 的双模式组织：Sessions（默认、零依赖）与 Catalogs（Lightroom Collections/Categories 同类）。会话权威语义不变：sidecar 恒真身，目录库是可重建聚合视图层。

- [x] **CATALOG-01**（✅ Delivered 2026-09-27 Phase 16 签核）: 双模式架构——Sessions 与 Catalogs 模式共存互斥可切；Sessions 恒默认且零外部依赖；Catalogs 模式在设置中启用
- [x] **CATALOG-02**（✅ Delivered 2026-09-27 Phase 16 签核）: 目录库后端（v1 = **本地 SQLite**，复用 Phase 9 libsqlite3 面 + 12-2 FilterSQL 谓词层，零新依赖）——跨会话影像元数据镜像 + catalogs 组织树（C1 Categories 语义）+ 虚拟集合；同步方向 = 会话→目录单向投影（sidecar 真身不变，目录库可全量重建——mutable and untrusted 原则延续）；**标签物化表**（(image_id, tag) 拆行，层级展开可索引——百万级行数下的层级关键字查询面）
- [x] **CATALOG-03**（✅ Delivered 2026-09-27 Phase 16 签核）: catalogs 组织树编辑与归类（C1 Categories 语义）——树 CRUD/拖拽 + 图片归类（含批量，复用 Phase 12 批量面）
- [x] **CATALOG-04**（✅ Delivered 2026-09-27 Phase 16 签核）: 跨会话浏览——Catalogs 模式下浏览/过滤/智能相册求值（复用 12-2 谓词层，求值域扩全库）
- [x] **CATALOG-05**（✅ Delivered 2026-09-27 Phase 16 签核；解释面增强 = 两档重建：对账式（文件在、行漂移——id 保持组织数据存活）/ 破坏式（文件丢失/schemaFailed——元数据恢复组织数据丢，.lcat 单文件备份兜底））: 脱库降级——目录库数据丢失可由会话面全量重建；Sessions 模式零功能损失
- [ ] **CATALOG-06**: 【v2 预留】远程后端评估——现成 pg 实例（LAN 延迟 ~0.2-1ms/往返可接受，可用性绑 NAS 为代价）或远程 SQLite 镜像；是否值得跨机/多客户端访问由 v2 届时裁决；FilterSQL 方言适配为该轮工作量

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Tethering

- **TETH-01**: 相机联机拍摄（通过 PTP/USB 实时捕获，自动入库到 Session Capture 子目录）
- **TETH-02**: 联机参数控制（光圈/快门/ISO/白平衡远程调节）

### Map / GPS

- **MAP-01**: 地图视图（MapKit，按 GPS EXIF 在地图标点）
- **MAP-02**: 点击地图标点查看该位置的图集

### Printing

- **PRINT-01**: 打印模块（色彩管理打印、布局、contact sheet）

### Advanced AI (v2) — 需自定义 Core ML 模型或非原生 API

这些能力 Apple 原生框架（Vision/Core Image）无公开 API 直接实现，需自定义训练 Core ML 模型或外部依赖，故留 v2。

- **AIV2-01**: AI 追色（color match）——分析参考图/参考风格，自动调整当前图色彩向其靠拢；Apple 无 `CIColorTransfer`，需实现经典 Reinhard/直方图匹配或自定义 Core ML 色彩映射模型
- **AIV2-02**: AI 评分/筛图（culling assist）——基于构图/曝光/对焦/清晰度自动给候选图打分排序；Apple 无质量评分 API，需自定义（Laplacian 方差模糊度量 + 直方图分析 + 可能的审美评分 Core ML 模型）
- **AIV2-03**: 天空分离蒙版（通用 RAW）——从任意 DSLR/无反 RAW 计算天空 mask（非仅读 iPhone ProRAW 嵌入 matte）；需自定义 Core ML 天空分割模型
- **AIV2-04**: 人像部位分割蒙版——皮肤/头发/嘴唇/眼睛/眉毛/牙齿等独立 mask，用于任意 RAW（非仅 iPhone 捕获时数据）；需自定义 face-parsing Core ML 模型（如 BiSeNet 风格）
- **AIV2-05**: 通用语义分割蒙版——植被/建筑/水体/雪地/地面等多类语义分割（Lightroom Adaptive Presets 风格）；需自定义 DeepLab/Mask2Former Core ML 模型

### Masking Extensions (v2) — 对标 Nitro Photo 补齐（2026-09-26 登记）

对标 Gentlemen Coders Nitro Photo（macOS）蒙版面的缺口项；蒙版主体已在 v1 Phase 6/7 交付（IOP-MASK-01..05 + AI-01/05/06/07）。

- **IOP-MASK-06**: Follow Edges 边缘感知笔刷——brush 沿图像轮廓单侧跟随涂抹（edge-aware/contour-following），Metal 边缘导向实现；Nitro 独门能力，算法级新需求（可插队 v1 后期 UI 打磨轮）
- **IOP-MASK-07**: Depth 深度蒙版——读取图像内嵌深度数据（AVDepthData / ProRAW embedded matte，iPhone 人像类源）作为蒙版源；桌面 RAW 深度源稀缺，依赖数据面非算法面

### Editor Workflow Extensions

- **WORK-01**: 标签/收藏夹集合（虚拟文件夹跨 Session）
- **WORK-02**: 全局搜索（跨 Session 检索，需索引）

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| ~~Lightroom catalog 模式（中央库）~~ **→ 2026-09-27 用户指令修订：不再整族排除**——可选第二模式（Catalogs 模式，v1 后端 = 本地 SQLite；pg 降为 v2 评估项）已立为正式需求（见 CATALOG 族）；仍是**默认关闭**，Sessions 恒默认 |
| Mac App Store 分发 / 沙盒 | 沙盒限制文件访问与 Session 模式冲突；开源免费路线选独立签名公证 |
| iOS / iPadOS 版本 | 项目定位 macOS 专属；依赖 Metal / Core Image / SwiftUI 桌面版 |
| Windows / Linux 跨平台 | 依赖 Metal / Core Image / SwiftUI；跨平台会牺牲原生体验与性能 |
| 账号体系 / 云同步 / 订阅 | 开源免费；个人自用优先；无云依赖 |
| 与 Darktable sidecar 二进制兼容 | 研究确认 Darktable 用 base64 二进制 blob + modversion，跨实现兼容做不到；Lightamer 用自有格式最大化参数能力 |
| 与 Darktable/Lightroom 预设互通 | 与 sidecar 决策一致；不互通，自有预设格式 + 标准 .cube LUT 即可 |
| 移动端配套 app | macOS 专属定位；移动端不在范围 |
| AI 追色/AI 评分/AI 天空/人像部位/通用分割（v1） | v1 仅做 Apple 原生 API 可实现的 AI（主体检测 + 频率分离磨皮）；天空分离/人像部位/通用语义分割/追色/评分需自定义 Core ML 模型，留 v2 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation (2026-08-03).

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-02 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-03 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| FOUND-05 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-06 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-07 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-01 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-02 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-03 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| RAW-04 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-05 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-06 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| SESS-01 | Phase 9 — Capture One Session Management | Delivered |
| SESS-02 | Phase 9 — Capture One Session Management | Delivered |
| SESS-03 | Phase 9 — Capture One Session Management | Delivered |
| SESS-04 | Phase 9 — Capture One Session Management | Delivered |
| SESS-05 | Phase 9 — Capture One Session Management | Delivered |
| SESS-06 | Phase 9 — Capture One Session Management | Delivered |
| SESS-07 | Phase 9 — Capture One Session Management | Delivered |
| HIST-01 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-02 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-03 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-05 | Phase 9 — Capture One Session Management | Delivered |
| HIST-06 | Phase 9 — Capture One Session Management | Delivered |
| IOP-TONE-01 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-02 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-03 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-04 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-05 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-06 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-07 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-FILM-01 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-FILM-02 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-FILM-03 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-COLOR-01 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-02 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-03 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-04 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-05 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-06 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-07 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-08 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| IOP-COLOR-09 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DETAIL-01 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DETAIL-02 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DETAIL-03 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DETAIL-04 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DENOISE-01 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DENOISE-02 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DENOISE-03 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DENOISE-04 | Phase 5 — Color & Denoise iops | Resolved（chromatic 交付；hotpixels/dark-frame defer） |
| IOP-GEO-01 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-02 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-03 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-04 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-05 | Phase 6 — Layers & Masking System | Delivered |
| IOP-GEO-06 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-01 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-02 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-03 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-04 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-05 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-06 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-07 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-01 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-02 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-03 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-04 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-05 | Phase 6 — Layers & Masking System | Delivered |
| AI-01 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| AI-05 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| AI-06 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| AI-07 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| IOP-HDR-01 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-HDR-02 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-HDR-03 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-HDR-04 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-HDR-05 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-FX-01 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-FX-02 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-FX-03 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-FX-04 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| IOP-FX-05 | Phase 8 — HDR/Stacking & Effects iops | **Delivered** |
| COLOR-01 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| COLOR-02 | Phase 13 — System Integration & Distribution | **Delivered** |
| COLOR-03 | Phase 13 — System Integration & Distribution | **Delivered** |
| COLOR-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| YIYIN-01 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-02 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-03 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-04 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-05 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-06 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-07 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-08 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| META-01 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| META-02 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| META-03 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| META-04 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| META-05 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| META-06 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| PRES-01 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| PRES-02 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| PRES-03 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| PRES-04 | Phase 12 — Metadata, Rating, Presets & LUT | **Delivered** |
| EXP-01 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-02 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-03 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-04 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-05 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-06 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-07 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| EXP-08 | Phase 11 — Export Pipeline & Batch Queue | **Delivered** |
| SYS-01 | Phase 13 — System Integration & Distribution | **Delivered** |
| SYS-02 | Phase 13 — System Integration & Distribution | **Delivered** |
| SYS-03 | Phase 13 — System Integration & Distribution | **Delivered** |
| SYS-04 | Phase 13 — System Integration & Distribution | **Delivered** |
| SYS-05 | Phase 13 — System Integration & Distribution | **Delivered** |
| DIST-01 | Phase 13 — System Integration & Distribution | **Delivered** |
| DIST-02 | Phase 13 — System Integration & Distribution | **Removed**（2026-09-27 用户终裁砍 Apple 渠道） |
| DIST-03 | Phase 13 — System Integration & Distribution | **Delivered** |
| DIST-04 | Phase 13 — System Integration & Distribution | **Delivered**（范围修订：无签名/公证） |
| MCP-01 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-02 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-03 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-04 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-05 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-06 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-07 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-08 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-09 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| MCP-10 | Phase 14 — MCP Server | **Delivered**（2026-09-28） |
| CATALOG-01 | Phase 16 — Catalogs Mode | Delivered（2026-09-27） |
| CATALOG-02 | Phase 16 — Catalogs Mode | Delivered（2026-09-27） |
| CATALOG-03 | Phase 16 — Catalogs Mode | Delivered（2026-09-27） |
| CATALOG-04 | Phase 16 — Catalogs Mode | Delivered（2026-09-27） |
| CATALOG-05 | Phase 16 — Catalogs Mode | Delivered（2026-09-27） |
| CATALOG-06 | Phase 16 — Catalogs Mode | Pending |

**Coverage:**
- v1 requirements: 140 total (119 + 4 AI + 1 SESS-07 + 10 MCP + 6 CATALOG)
- Mapped to phases: 140 (100%)
- Unmapped: 0 ✓

### Per-phase coverage counts

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 — Foundation, App Skeleton & Capability Spikes | FOUND-01..03, FOUND-05..07, RAW-01, RAW-02, RAW-04..06 | 11 |
| 2 — Pixelpipe Core, Color Management & History Stack | FOUND-04, RAW-03, COLOR-01, COLOR-04, HIST-01..04 | 8 |
| 3 — Tone & Filmic iops | IOP-TONE-01..07, IOP-FILM-01..03 | 10 |
| 4 — Geometry, Lens & Detail iops | IOP-GEO-01..04, IOP-DETAIL-01..04 | 8 |
| 5 — Color & Denoise iops | IOP-COLOR-01..07, IOP-COLOR-09, IOP-DENOISE-01..04 | 12 |
| 6 — Layers & Masking System | LAYER-01..07, IOP-MASK-01..05, IOP-GEO-05, IOP-GEO-06 | 14 |
| 7 — AI Modules (Native Vision Masking & Retouching) | AI-01, AI-05..07 | 4 |
| 8 — HDR/Stacking & Effects iops | IOP-HDR-01..05, IOP-FX-01..05 | 10 |
| 9 — Capture One Session Management | SESS-01..07, HIST-05, HIST-06 | 9 |
| 10 — yiyin Border/Watermark Panel | YIYIN-01..08 | 8 |
| 11 — Export Pipeline & Batch Queue | EXP-01..08 | 8 |
| 12 — Metadata, Rating, Presets & LUT | META-01..06, PRES-01..04, IOP-COLOR-08 | 11 |
| 13 — System Integration & Distribution | SYS-01..05, DIST-01..04, COLOR-02, COLOR-03 | 11 |
| 14 — MCP Server (远程 AI 修图 + 自动筛选) | MCP-01..10 | 10 |
| 16 — Catalogs Mode | CATALOG-01..06 | 6 |
| **Total** | | **140** |

### Cross-phase placement rationale
- **IOP-GEO-05 (liquify) / IOP-GEO-06 (retouch) → Phase 6 (Layers/Masking):** both architecturally depend on the mask/distortion framework; they cannot ship before masking exists.
- **AI-01, AI-05..07 → Phase 7 (AI Modules):** the v1 AI features (subject masking + frequency-separation retouching + mask integration/editability) depend on the Phase 6 layer/mask system (AI-06 feeds masks into layers), so AI ships immediately after Layers/Masking. These are the only AI capabilities Apple's native Vision/Core Image frameworks implement without a custom Core ML model; sky/portrait-parts/semantic segmentation (AI-02/03/04 → AIV2-03/04/05) moved to v2.
- **IOP-COLOR-08 (.cube LUT) → Phase 12 (Presets/LUT):** it is the same feature as PRES-03; they ship together as the `.cube` LUT module + its preset entry point.
- **HIST-05 (copy/paste) / HIST-06 (before/after) → Phase 9 (Session):** workflow features layered on the Phase 2 history stack, best delivered alongside the session browse modes they operate within.
- **COLOR-02 (soft proof) / COLOR-03 (multi-display ICC) → Phase 13 (System):** complete the color pipeline alongside system integration (Quick Look/Spotlight), which is where multi-display behavior becomes observable.

---
*Requirements defined: 2026-08-03*
*Last updated: 2026-09-24 — Phase 7 sign-off: AI-01/05/06/07 → Delivered（AI-06 raster 口径 D-07-CONTEXT-3 / AI-01 scribble 后置 D-07-CONTEXT-4 / 层 B 下载例外 D-07-CONTEXT-1）*
*Last updated: 2026-09-26 — Phase 9 sign-off: SESS-01..07 + HIST-05/06 → Delivered（SESS-06 culling cap 2 = D-09-CONTEXT-6 / SESS-05 孤儿两动作 / HIST-05 跨图 undo defer + skip D1 / PERF-07 门 0.490s Release-SSD + PERF-06 留 Phase 15）；证据 = 09-VALIDATION + 09-DISCUSSION-LOG 终节*

### MCP Server (MCP)

- [x] **MCP-01**: MCP 工具集：load_image / apply_params / render_preview / iop 参数 schema 元数据，远程 client 可完成「载入 → 修图 → 取回预览图」闭环
- [x] **MCP-02**: 双入口：GUI 偏好开关（开即启动/关即停）与 CLI 无头拉起同一 server（无 GUI 进程）
- [x] **MCP-03**: 渲染一致性：MCP 返回的预览图与本地 GUI 渲染量化一致（同参数同输出）
- [x] **MCP-04**: 安全面：默认仅回环绑定；非回环暴露必须带鉴权 token
- [x] **MCP-05**: 筛选读面（2026-09-26 扩充）：list_photos（会话索引查询：EXIF 轻量列/rating/flag/has_edits）+ get_thumbnails（批量缩略图取回，档 A/B 缓存直读）+ get_contact_sheet（服务端拼图返回单图）+ get_detail_crop（原尺寸 ROI 局部裁剪）
- [x] **MCP-06**: 筛选写面（2026-09-26 扩充）：set_rating / set_flag / set_color_label / append_note——写回以 sidecar 为真，复用 Phase 9 批量管线（段1 内存变换 + 段2 索引单事务 + 段3 串行写队列）语义，GUI 缩略图 stale 再生联动可见
- [x] **MCP-07**: culling 辅助（2026-09-26 扩充）：burst/连拍分组查询（拍摄时间+机型聚类）+ 脸部区域定位（复用 Phase 7 Vision faceLandmarks 基建）支撑细节裁剪
- [x] **MCP-08**: 筛选写回安全边界（2026-09-26 扩充）：写回限元数据字段（rating/flag/color/note），禁止像素修改与文件删除/移动；传输安全同 MCP-04
- [x] **MCP-09**: 筛选/修图扩充工具组（2026-09-26 登记）：list_presets / apply_preset / diff_presets（预设三件套，上游依赖 PRES-01..04）+ export_image（尺寸/质量/格式落盘，render_preview 不落盘之补位）+ set_keywords（关键词写面，上游依赖 META-04）。**研究项**（Phase 14 research 定案）：A = GUI 与无头 MCP 同会话并发 sidecar 双写对策（WAL 仅覆盖索引层；单写者锁/后开者只读/移交）；B = 多版本参数组/历史快照 MCP 语义（多版本交付需保存/切换/对比参数组工具面）；C = match_color MCP 工具位（agent 编排层：选参考/批量触发 colormatch/强度/事后 apply_params 微调；签名预留，依赖 V2 TRACK colormatch iop，与 Phase 12 .cube LUT 协同）
- [x] **MCP-10**: GUI launcher（2026-09-26 用户裁决进 V1）：偏好存 agent CLI 启动命令模板（如 pi/omp）+ 可选任务 prompt 模板（筛图口径/修图审美方向）+「一键 AI 筛图/修图」动作——app 拉起 agent 进程挂自身 MCP server，写回由 server 完成（sidecar 真身），输出日志面板显示 agent 文字流；agent 的 provider 配置归 agent 自身体系，app 零 AI 代码；launcher 拉起路径 app 侧串行化（研究项 A）

> **Phase 14 交付（2026-09-28 签核）**：MCP-01..10 全 Delivered——19 工具封闭集冻结（终快照逐字 + 第 20 工具白名单负例）；研究项 A 关闭（flock 单写者五态 + 只读降级 + GUI-live 判据）、B 维持 v1 history append（版本面 defer v2）、C 零占用（负例钉死）。证据： `14-VALIDATION.md` SC#1-7 三列 + `14-4-SUMMARY.md` 安全走查五条；终轮 1881/11skip/0fail。

### Performance (PERF)

- [ ] **PERF-01**: PREVIEW 全链（满 iop 集 enabled）warm median ≤16.6ms（60fps@100MP 预算）
- [ ] **PERF-02**: 100MP FULL 单帧 + N 层图层栈内存足迹 ≤3GB（TilingPlan 窗口化）
- [ ] **PERF-03**: Instruments 系统级 profile 报告落账（GPU 趟数/热点/内存），杠杆兑现记录在案
- [ ] **PERF-04**: 交互零卡顿——滑块拖动/缩放/平移 hitch（>50ms 帧间隙）= 0，MainActor 长任务清零
- [ ] **PERF-05**: RAW 解码——100MP 首渲可交互时间 ≤500ms（后台解码 + 渐进显示），CIRAW 9/8 双档计量
- [ ] **PERF-06**: 懒加载——万张级 Session 滚动 60fps，缩略图按需解码 + LRU 内存预算（Phase 9 工作基线已落账 `.work/09/perf.md`：双档缩略图管线 + LRU + 10k reload 26ms；**60fps 门本体 Phase 15 清算**）
- [x] **PERF-07**: 批量修图（懒渲染）——apply = 纯元数据写入零像素操作，万张 ≤5s（dt sqlite 事务对标；sidecar 批量写策略）；缩略图 stale 后台再生；导出排除
  **Delivered**（Phase 9）：段1+段2 万张 = **0.490s（Release/内置 SSD，09-05 签核轮 clean 构建终值）**，门 ≤5s 余量 ~10×；三轮对账 0.419→0.435→0.490 稳定；段3 sidecar drain 与 UNITEK 对照只记录不设门（L009 卷型标注）；零渲染零解码常驻断言（writer=nil 磁盘字节不变）。证据：`Perf07MassApplyTests` + `.work/09/perf.md` PERF-07 终账节。

## V2 Requirements

### Color Transfer / 追色 (TRACK)【V2；2026-09-22 用户指令维持 V2（当日曾短暂提级 Phase 7，已回撤）】

> **定位再确认（2026-09-26）**：计算核 native 不可外包——追色是统计算法（Reinhard/CDF/OT → 3D LUT），TRACK-05 确定性门与 TRACK-02 多参考统计聚合排除 agent vision 迭代路线（LumaRescue 类方法论无色彩匹配算法）。MCP+agent 作**编排皮**：选参考/批量触发/强度/事后微调（MCP-09 研究项 C `match_color` 工具位，依赖本模块 colormatch iop）；与 AIV2-01「AI 追色」的语义由编排层承载。GUI 拖入交互（TRACK-04）与 agent 编排并存不冲突。

- [ ] **TRACK-01**: 追色计算——参考图色彩分布特征提取 + 色彩变换求解（Reinhard Lab 对齐 / 直方图 CDF 匹配 / 最优传输族中选定算法），输出 3D LUT（或等效参数曲线组）
- [ ] **TRACK-02**: 多参考图支持——N 张参考的统计聚合或逐参考混合，权重可调
- [ ] **TRACK-03**: 非破坏落位——追色结果以 `colormatch` iop 模块实例落位（内嵌 LUT + tetrahedral 插值 kernel），sidecar 持久化、可继续手调、cache 语义正确
- [ ] **TRACK-04**: 交互——拖入/选择参考图 → 自动计算并预览；强度/透明度可调；before/after 对比
- [ ] **TRACK-05**: 质量门——LUT apply 的 golden parity（kernel vs float64 参考）、HDR/广色域裁剪策略明确、确定性（同输入同 LUT）

### Alcedo Parity / Alcedo 对标缺口 (ALCE)【V2；2026-09-27 用户指令——功能对标基准由 Darktable 全量翻转为 Alcedo Studio 后，对已交付 39 iop + Phase 6-16 交付面盘点出的真实缺口】

> **基准**：Alcedo Studio（GPL-3.0，`/Volumes/UNITEK/Documents/Development/AlcedoStudio`）。已覆盖面不重复立需求（色调/曲线/可选颜色/细节/局部色调映射 = Phase 3/4/5 已交付；LUT/颗粒/光晕 ≈ Phase 12 + bloom/grain；图库/分组/EXIF 搜索 = Phase 9/16；蒙版 = Phase 6；HDR/EDR = Phase 8；导出命名模板 = Phase 11）。**CIRAW 边界排除项不入本族**：demosaic 算法菜单、raw 域 inpaint-opposed 高光重建——架构上不可达（STACK.md Decoder 策略对比节 2026-09-27），v2+ 若做须走 libraw 兜底解码路线。Lensfun 镜头数据库维持 STACK.md 原评估（数据只读 + Metal warp），不因翻转加码。

- [ ] **ALCE-01**: LGG 三向色轮（Lift/Gamma/Gain，grading 标准 3-way）——每 adjustment layer 一个色轮实例，蒙版可绑；与现有 colorbalancergb/colisa 并存。UI 色轮 + Metal kernel + golden-image 门
- [ ] **ALCE-02**: OpenEXR 导出（32-bit float，half/float 可选）——现导出矩阵 JPG/PNG/TIFF/HEIF/WebP/AVIF 无 EXR；HDR/堆栈工作流回传 3D 软件需要
- [ ] **ALCE-03**: Ultra HDR JPEG 导出（gain map，SDR base + HDR 增益层）——嵌入现有 JPEG 编码腿，EDR 渲染值映射 gain map
- [ ] **ALCE-04**: DRT 扩容——ACES 2.0 输出变换 + OpenDRT（现有 filmicrgb/sigmoid/agx 三个 DRT 之外）；目标色彩空间/传递函数/峰值亮度可选，与 EDR 输出联动（参考 Alcedo display-transform 面板与 jedypod/open-display-transform、aces-aswf/aces-core 算法）
- [ ] **ALCE-05**: 每片命名版本（named versions）——同一原片多个命名编辑版本并存，可从 history stack 任意步分叉；sidecar schema 扩展 + 浏览器版本切换 UI
- [ ] **ALCE-06**: in-app 自然语言搜索 + 自动打标签——本地 CLIP 多语言模型（导入后后台索引），按自然语言查询图库；对标 Alcedo 图库搜索；与 Phase 14 MCP 外接 AI 通道互补（不依赖外部 MCP 客户端）
- [ ] **ALCE-07**: in-app AI 评片与描述——OpenAI/Anthropic 兼容 API（钥匙串存 key，后台批跑），输出 1-5 星 + 理由 + 描述文本；评分写入 rating 管线，与 culling/MCP-10 通道共享落地字段
