# Requirements: Lightamer

**Defined:** 2026-08-03
**Core Value:** 在 macOS 上用 Metal 加速提供 100MP+ 大图下零延迟的 RAW 调整体验，并让 Capture One Session 工作流与 Darktable 级调整深度在同一原生 app 中共存。

> ⚠️ **2026-09-27 项目重定义（用户指令）**：产品目标改为 **macOS 独占、RAW 9 解码、UI 完全模仿 Alcedo Studio 的 Alcedo 克隆**；dt 独有已交付代码保留但默认不启用；图片管理改 Alcedo 方式（Sessions/Catalogs 剥离）；导出格式保留原矩阵、可选项按 Alcedo；水印相框保留 yiyin；蒙版 = Alcedo + Nitro Photo（不用 dt 方案）；以上全部属 **V1**。**下方既存 v1 Requirements 为里程碑 1 历史账（已交付面照旧有效，交付面被剥离者标 disabled）**；新 V1 需求家族待 `ALCEDO-FEATURE-MAP.md` 测绘落盘后统一登记（ROADMAP M2-0），本文件暂不重写历史节。V2 节 ALCE-01/04/05/06/07 随重定义**提级 V1**；ALCE-02（OpenEXR）/ALCE-03（Ultra HDR JPEG）维持 V2（用户：导出格式保留原方案）。〔2026-10-16 M6 立项批更新：ALCE-03 随 LightCraft 裁决②**解冻 → M6-3**（ImageIO auxiliary 原生路先试）；ALCE-02 维持 V2 原位挂账〕

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
- [x] **M2NODE-03**: 节点内有序调整列表（顺序=用户数据编译器不得重排）+ 18 项目录所有权校验（Clarity/Sharpen/Halation/FilmGrain 属 DRT/Post，Grade 内插入 = typed error）（**M2-4 终态注记**：所有权框架三层 + addModuleToLayer typed 缝 + **宽限执行**已交付 `52cf75e`（D-M2-4-CONTEXT-8）；严格面激活（18 目录收窄）归 M2-5——M2-4-1 验收裁决维持不勾，`M2-4-3-ACCEPTANCE.md` 复核维持）【2026-10-07 M2 closeout 终态（Delivered）：节点内有序列表 + 所有权框架三层 + addModuleToLayer typed 缝 + 宽限执行（`52cf75e`）+ 严格面激活（18 目录收窄）= M2-5 批交付——指针 = `TODO.md` M2-5 批「add 面严格化」+ `phases/m2-5-color-grade/M2-5-3-ACCEPTANCE.md`（checker E2 判「翻勾逾期带指针件」；INPUT §4.5 显式呈报晨审可推翻）】
- [x] **M2NODE-04**: 蒙版 Grade-owned 绑定（每 Grade 多蒙版独立 enabled/opacity/invert；首 Grade 删除锁） **Delivered 数据/绑定面**（M2-4-2 三任务两提交：语义激活 = `MaskCombiner.drawnGroupPlane` 装配前 enabled 恒等元过滤（一行 `continue`，kernel/五式公式零 diff；空 enabled 集 = 既有 dt no-form fill-1 leg 恒 1 passthrough——禁用蒙版=约束解除≠禁用 grade）+ `MaskSpec` 访问面 `maskItems`/`setItemEnabled`/`setItemDisplayName`（值语义，无第二存储，displayName 派生消费 Core 单源 nextLayerName）+ `LayerEditingState` deletionProtected **clear+fill 双腿**拦截（checker E3，toast+零 history item；全仓 mask 写入点 8 触点审计表 DECISIONS 在案）+ `PipelineDocument.maskGroups` 投影（组序=grade 序=层序，M2-7 数据正本；reorder 跟随纯派生证明）+ `node(for:)`/`displayTitle(for:)` 选中映射 + EditorNodeHeaderView 动态名（未选中 = KEY 恒等逐字节不变——zh catalog `editor_node_name`=「调色」实测，D-M2-4-2-2 勘误）；测试 14 新增（MaskItemSemanticsTests 9【APP】+ PipelineLinkageTests 5【LAYERS】，全套 2217/14/0）；锚 `42e2f95`/`9a3e906`，验收 `phases/m2-4-node-model/M2-4-2-ACCEPTANCE.md`；挂账注记：① stroke 腿 `MaskSpec(drawn:)` 重建丢 sibling payload 复核归 M2-7/M2MASK-04（D-M2-4-2-5 登记在案）② feather/应用序=feather→invert→opacity→clamp 归 M2MASK-04 ③ M2-7 Mask Groups 面板 UI 消费面归 M2-7 ④ 新 4 UI 键 + toast 键 zh 滞后挂 P3 收口对账（D-M2-4-CONTEXT-11）→ **已闭环**（M2-4-3 T4：zh-audit exit 0，29 键 zh/en 落盘含本注记所列键族））
- [x] **M2NODE-05**: 持久化——sidecar/项目文件 schema 扩展承载节点图（沿 one-way 格式锁惯例升版本） **Delivered sidecar 腿**（M2-4-1 T4：`.lra` v4→v5 一原子 additive 事务——`MaskGroupItem.enabled/displayName` + `MaskSpec.deletionProtected`（全 Optional，synthesized encodeIfPresent nil 保持 canonical JSON 字节 = stableHash 零漂移逐字节钉）+ `rawOverrides`（encodeIfPresent 缺键；hash-isolated 双向机检：与 overrides 有无无关 historyHash/driftDetected 同值，蒙版字段则 set-fields-move）+ 读者容忍（旧档全 nil、`>5` degrade 不拒载）+ 写者恒发 5；`.lalb` 四表零触碰（项目文件腿归 M2-8 mini-git 激活）；SidecarV5Tests 10【APP】；锚 `b7d7acd`/`48e2b7d`，验收 `phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md`；口径注记：`deletionProtected` 落 runtime/snapshot 拼写，`.lra` 文件载体随 M2MASK-04 补（D-M2-4-1-3，测试断言显式钉缺口））
- [x] **M2NODE-06**: 节点面板 UI——图视图（Develop/DRT 端点节点+Grade 节点+连线+增删改名重连+Fit）SwiftUI/Metal 自绘 **Delivered**（M2-4-3 四任务三提交：`App/Sources/Lightamer/UI/Shell/Nodes/` 三件 = NodeCanvasGeometry 纯函数几何正本【纵向单列 layout/edges/insertionIndex/fitScale，零手写坐标】+ NodesPanelModel【投影订阅 + 选中写 selectedLayerID 仲裁点 + 命令薄路由 + mix live/commit 腿】+ EditorNodesPanelView【ZStack = Canvas 连线层仅画线 allowsHitTesting(false) + 真 SwiftUI 卡片层原生命中，零手写 hit-test；三类卡 + 上下文菜单四项 availableActions 穷举 + 拖卡重连【6pt 阈值 + scrollDisabled 双保险 + 指示线 + insertionIndex 纯函数，自槽 no-op】+ 恒定 Fit + `.nodeLocked(_:hint:)` 泛化三件套 modifier【M2-7 首组锁消费接口，语义冻结 DECISIONS D-M2-4-3-6】】+ EditorToolRailView `.nodes` 空态替换【history/versions 面 diff 零】；AC3 渲染几何机检 = NodeCardFramesKey preference 读回（真面板 NSHostingView 实测帧 = Layout）；测试 NodeCanvasGeometryTests 9 + NodesPanelModelTests 14【APP】，30 节点 layout BENCH 0.0081ms/round 观察行；锚 `b4ea439`/`e245b46`/`34de49a`，收口 `phases/m2-4-node-model/M2-4-3-SUMMARY.md` + `M2-4-ACCEPTANCE.md`（phase 级汇总）；挂账：自由平移/缩放 = CONTEXT Deferred；拖动流畅度/滑杆手感 = Manual-Only 走查观察项（D-M2-4-CONTEXT-10，非门）；zh 对账 exit 0（29 键 T4 落盘）；签核 VALIDATION 归 verify-work；验收 PASS `phases/m2-4-node-model/M2-4-3-ACCEPTANCE.md`（2026-09-30 独立验收：AC 11/11 + 复跑 App 332/0/0、Layers 174/2/0 + zh-audit 双检亲跑 + BUNDLE-MAP 求和 2240 精确；PASS / 0 error + 1 minor 已修 + 2 observation））

### Color Grade 控件 (GRADE)
- [x] **M2GRADE-01**: 18 项封闭目录参数对齐（CAT02 WB 默认 5999.99K identity 2000-15000K+Tint；exposure ±16；contrast 中灰邻域保色相语义新图 +15；White/Black/Shadows/Highlights ±100；curve 单位方形点列；HLS 8-bin+h/l/s_range 45/0.1/0.1+target_hls；saturation 0-4；vibrance ±100；LMT CUBE path；tint ±100——Feature-map §2.1 全表）**Delivered**（M2-5-1 八任务八提交：GradeCatalog 18 目录五元组注册表【catalogID/opName 常量/owner/identityJSON/panelExposures，`NodeOwnershipCatalog.swift` 同文件扩展，owner(of:) 签名零变 = M2-4-1 校验缝零改动】+ defaultLook 三 entry 单源（+1.5EV/+15/1.3，KD-9）+ 新 iop 七件八 op（CAT02 WB【Planck 积分 xy + CAT02 适应阵，identity (5999.9934, 9.7112783) 双断言】/Contrast【OkLab S 曲线，Alcedo ApplyOkLabContrast 逐式忠实】/White·Black【gain=1+max(v,0)·0.005 / offset=v·0.001】/Saturation【luma-pivot+peak 限幅】/Tint【±100，像素语义签注 DECISIONS §八】/colorWheels【LGG 幂式+IsIdentity 照抄】/HLS【Gaussian 窗+YIQ 旋转+applyTargetEdit 终式】——kernel 数学对 Alcedo 源码逐式验算忠实（验收报告重点①表）；golden = Swift Float64 参考 + linear 域比较 + p99.9≤1e-5 分级容差；ACEScc 域包夹 = 每层子 run 头尾 envelope 对（driver 缝，≥1 目录 op 才包）+ V50Order 十行 add-only（acesccIn 20.5/acesccOut 69.9）；测试 +47（GradeCatalogTests 14/ACESccEnvelopeTests 5/GradeKernelGoldenTests 18/GradeParamsCodingTests 10）+ 全套 2287/14/0；面板暴露清单消费/严格面收窄/mint 接线 = M2-5-2 已交付（面板半边终注 2026-10-01：Tone 主面六行 + Look 四组 18 行 + 八 provider 注册 + add 面 12 唯一 op 严格化 + Develop 作用域收窄——验收 PASS `phases/m2-5-color-grade/M2-5-2-ACCEPTANCE.md`）；对齐五件 identityJSON no-op 断言 + shadhi 面板默认两值分立在册；锚 `ba70717`..`fd13a46`，验收 PASS `phases/m2-5-color-grade/M2-5-1-ACCEPTANCE.md`（2026-09-30：AC 12/12 + 三域复跑逐值一致 + 0 error + 2 minor 已修 + 1 observation））
- [x] **M2GRADE-02**: LGG 三向色轮（每轮 disc Vec2+strength+color_offset+luma_offset；gamma/gain identity=(1,1,1)；trackball UI+Reset wheels）**Delivered**（M2-5-1：params 逐字段照抄 `color_wheel_model.hpp` + ColorWheels.metal kernel【behavior 11 幂式，disc/strength 不进装配/gain.luma 装配不消费均照抄】+ IsIdentity 判定式照抄 + identity 三轮容差 0 + golden；M2-5-2 T4 `ec8a237`：ColorWheelsPanelView 三 trackball【Canvas 圆盘+DragGesture → `discFrom`/`pointFrom` 纯函数（IOP 落 `ColorWheelsModule`，KD-2 钦定位点）+ 拖拽派生 colorOffset = Alcedo UpdateDerived 终式逐式验算（HueToUnitRgb+DiscToCdlDelta；lift 0/gamma·gain 1、gamma 反号、绝对位置非增量；strength 0…0.1/luminance ±1 滑杆；**strength 上限 clamp 对齐 Alcedo UpdateDerived——payload pristine 1.0 首拖 10× 偏差 = 验收修复**】+ 单轮双击 reset（`resetting(wheel:)` payload identity）+ Reset wheels 总按钮（identityJSON 解码单 discrete commit））；CatalogAddFaceTests 4 法【disc round-trip/clamp、cdlDelta 方向+量程+clamp、单轮 reset、真 EditorState 会话 reset 链上字节 == identityJSON】；锚 `d584835`..`36f082b`，验收 PASS `phases/m2-5-color-grade/M2-5-2-ACCEPTANCE.md`（2026-10-01：AC 12/12 + 三 bundle 复跑逐值一致 + 1 minor 已修）
- [x] **M2GRADE-03**: 产品默认 look（+1.5 EV/contrast +15/saturation 1.3）仅作用于新导入；用户新建 grade 与 reset 恒 identity **Delivered**（M2-5-2 T7 `95d396b`：`.lalb` v1→v2 首迁【additive 列 `default_look_pending` + 幂等 ALTER（table_info 探针）+ pre-migrate sqlite3_backup 快照钩子首消费 + user_version 2】+ insertImage 恒写 1（无开关 OQ-8 A）+ `defaultLookPending`/`clearDefaultLookPending` API + 开图入口注入（KD-5 fallback `EditorWorkspaceShellView.loadCurrentImage`，开图即清幂等）+ EditorState mint（checker E5 形态：真 load 链 pipe load 定局后 `.lra` 文件级复核缺席才铸——单 AdjustmentLayer 内存构造 chain 三实例 + 恰一条 history item 经 `schedulePersist:false` 跳 persist 通道 + 渲染腿照跑）；DefaultLookTests 5 法【双断言：强制 flushNow 磁盘无 `.lra` + undo 一步 pristine；mint 四态 + v1→v2 迁移端到端】；用户新建 grade = 空 chain、reset 恒 identityJSON 单源；pristine 不变量「`.lra` 缺席未编辑零 sidecar 落盘」构造上成立）
- [x] **M2GRADE-04**: ACEScc 调色域（D4：Grade 内部 AP1/ACEScc 色适应往返，CAT02 创意白平衡语义；相机 WB 留在 RAW Decode/CIRAW 层）**Delivered**（M2-5-1 T2 `1853026`：ACEScc 域 envelope = 每层子 run 头尾包夹对【ACESccMath.metal 单点常数源：Rec2020→AP1 CAT02 适应阵 + S-2014-003 log 编解码；`LayerCompositeSeam` 持有器（Core 不可 import IOP → public 持有器 + IOP populate 注入）；effective chain 含 ≥1 目录 op 才包（checker E2 收窄，ExportPipeTests 盘点表在案）】+ ACESccEnvelopeTests 5 法【往返 ≤1e-5 p99.9（linear 域）/空链·非目录链跳过/E1 排序 pieces 首末/retouch·base·terminal 零包夹字节证/键稳定 HIT】；CAT02 创意 WB = cat02WhiteBalance iop（M2-5-1 T3，identity 双断言）；相机 WB 留 RAW 层 = RAWTechnicalOverrides 既有缝（M2-3-3）未动；验收 PASS `phases/m2-5-color-grade/M2-5-1-ACCEPTANCE.md`（2026-09-30）——勾选随 M2-5-3 验收批 2026-10-01）
- [x] **M2GRADE-05**: LUT 库递归扫描 + 子目录分组显示【2026-09-27 用户指令，改进超 Alcedo——其 LutCatalog 只平铺单层目录（`ListCubeLutsInDir` 无递归）】：根目录下任意深度子目录的 `.cube` 全部收录，LUT 面板按子目录树分组/折叠显示；文件增删/目录变更后的刷新与缓存失效语义明确（现状锚点 = `LutLibraryStore` 单层 `contentsOfDirectory`，`Lut3d/LutLibraryStore.swift:105`）**Delivered**（M2-5-3 T2 `6facf60` + T3 `851a1cc`：registry 键升根相对 POSIX 路径一处承载递归/同名消歧/可配根【旧行 optional `relativePath`/`subdirectory` additive decode + init 迁移幂等落盘；旧档裸名引用唯一尾段 fallback、歧义 nil degrade、旧档字节零改写；自愈三段式/blit identity/toast 语义零改动】+ `enumerator(at:)`+`skipsHiddenFiles` 递归收录 + `LutLibraryTreeView`（root 行 + DisclosureGroup 子目录组、BuiltIn 组首、手动刷新 + onAppear rescan、撞车前缀、selection 写 key、`displayKey` 高亮旧引用不改字节）+ 500 文件 5s 软上限 + 万文件探针 0.77s；LutLibraryRecursionTests 16 法【IOPP】；刷新语义 = 面板打开 + 手动按钮（FSEvents = v2 预声明）；锚 `a31ac15`..`1044641`，验收 PASS `phases/m2-5-color-grade/M2-5-3-ACCEPTANCE.md`（2026-10-01：AC 12/12 + IOPP 342/3/0、App 369/0/0 复跑逐值一致 + 0 error + 2 minor 已修）；树目测走查 = Manual-Only 挂 GUI 验收轮）
- [x] **M2GRADE-06**: LUT 根目录用户可配置【同上用户指令】——设置页选择根目录并持久化，不锁死默认位置（默认仍 `~/Library/Application Support/Lightamer/LUTs/`）；切换根目录后重建索引；跨子目录同名冲突的消歧规则与既有查重/自愈（12-5 D-6 能力）整合；被引用 LUT 缺失时 degrade 语义（节点保留、渲染 typed 降级）**Delivered**（M2-5-3 T4 `93ad30f`：`lut.library.root` UserDefaults 键【拼写单源 = `LutLibraryStore.libraryRootKey`，IOP init 直读 `.standard`；AppPreferences 登记/reset 面；空/缺 = 默认根】+ Settings Cache 页「LUT Library」节【当前根显示/NSOpenPanel 选择/重置/结果行/坏根橙错行】+ `validateRoot`（isDirectory + 写探针）前置——探针失败不持久化保持现根（L009：不建 bookmark，v1）+ 切根 = 重造 store → `replaceShared` 原子换（static var + NSLock holder，checker m6）+ `SharedForwardingResolver` 保 module box 活解析 + registry.json 每根自洽 = 切根独立重建；同名消歧 = relativePath 键空间天然唯一（KD-1 一体）；缺引用 degrade = blit identity + toast 语义零改动 + 跨根缺名 typed 缺席测试钉；SettingsPagesTests +1 + LutLibraryRecursionTests KD-3 四法；锚同上，验收 PASS 同报告（默认根行为零变化 = LutLibraryStoreTests 10 法零改动全绿证））
- [x] **M2GRADE-07**: 内置 LUT 库 = Alcedo 同款胶片 LUT 集【2026-09-28 用户指令「把内置的 LUT 换成和 Alcedo 一致」；2026-09-29 用户勘误】——**目标集 = CMake 打包 glob 的 `Agfa_*/Fuji_*/Kodak_*.cube`（Alcedo 真内置集）；安装目录里实测的 Hasselblad 两张 33³ 与「色彩逆向」子目录为用户自放，非内置，不入目标**。**许可门（第一任务）**：从上游 GitHub `JanLohse/spectral_film_lut` clone 原生获取 + 核实其许可（本地无 fork，已查；禁从 GPL-3.0 的 AlcedoStudio 仓拷数据文件——公开仓 config/LUTs 亦不存在）；随包 LICENSE/NOTICE 署名；M2-5 落地 **Delivered**（M2-5-3 T1 `a31ac15` + T5 `7d73d1d`：**许可门结论 = 宽松（MIT，Copyright (c) 2026 Jan Lohse）→ 资产分支**【上游 tag v0.18.2 SHA `42f4f3f…`，验收批 GitHub API 独立重查一致；上游仓 = LUT 生成器（Python，无 .cube），Alcedo 打包集本就是该工具产物（安装目录 TITLE 头 `D:\Projects\spectral_film_lut\…` 逐字取证）】→ vendored 集 = **上游 v0.18.2 无头重生成 40 张 65³**（39/41 精确对应 + Kodak_Ultramax_400 收编 + 5219_3200 不造；offscreen GUI 应用默认参数 + 两偏差：65³、BW 配 Kodak 2302 print）——**零字节来自 GPL 仓**（vendored TITLE 裸名形态 vs Alcedo Windows 路径形态，验收批抽样复核）；44→41→40 勘误链自洽（glob 真值 41 非 44；evidence §四 41 行对照表）；`Resources/LUTs/` = 40 .cube + **LICENSE（MIT 全文）+ NOTICE**（provenance/版本/偏差/零 GPL 声明）folderReference 入包（42 项测试钉）+ seeder 首启拷默认根 `BuiltIn/`（count+size 哨兵幂等，可配根不种子）；BuiltInLutSetTests 4 法【APP】+ KD-4 两法；锚 `a31ac15`/`7d73d1d`/`1044641`，验收 PASS 同报告）

### 显示渲染变换 (DRT)
- [x] **M2DRT-01**: DRT 节点+面板——Method 分段卡（ACES 2.0/OpenDRT）恒展开；默认 OpenDRT【2026-10-01 M2-6-3 Delivered（面板）：DrtPanelView 挂 displayTransform 页（占位特面退休——枚举保留槽标记、渲染臂换真面板，M2-6-3-DECISIONS D1）+ Method 分段卡恒展开置顶 + Color & Encoding 折叠组默认展开 + aces20 限色组/opendrt 预设三件套随 method 显隐 + Vignette 行原地保留（E1 勘误边界不动）；**「默认 OpenDRT」对标偏离已登记**（AGENTS.md M2-6 增量节）：面板概念 DRT 恒在（默认 method=OpenDRT），渲染面 pristine 档 = `.sdrGamma` 直通（性能/视觉双保护 + 非 DRT 零差红线，用户显式动面板才进 DRT 渲染；晨审可推翻 = KD-1 传点一行，DECISIONS D5）；验收 PASS（`phases/m2-6-drt/M2-6-3-ACCEPTANCE.md`）】
- [x] **M2DRT-02**: OpenDRT 预设三件套——Look 7（standard/arriba/sylvan/colorful/aery/dystopic/umbra+custom）+ Tonescale 15 + Creative White 6；45 个 detailed 参数 editor-owned 整体序列化（预设=具名快照）【2026-10-01 M2-6-1 Delivered（OpenDRT 核）：Tonescale 实枚举 14（USE LOOK PRESET + 13，m3 勘误——原文 15 系多计）；detailed 参数实数 53（hpp 实态，CONTEXT 事实基线②）；53 参数整体序列化 + 预设快照 + NOTICE（M2-6-1-SUMMARY/DECISIONS §D6/§D7）；验收 PASS（M2-6-1-ACCEPTANCE：预设表 vs Alcedo expected bins standard/arriba 复算 53/53 逐位一致）】【2026-10-01 M2-6-3 终态补注（验收）：预设三件套面板暴露落地（Look 7+custom / Tonescale / Creative White pickers，opendrt 方法组内显隐；技术专名 zh=英文原文 OQ-12-A）；custom 派生判定（快照匹配→具名/不匹配→custom）+ 预设单 discrete commit undo 一步回测试钉】
- [x] **M2DRT-03**: ACES 2.0——Limiting Space 七选 + ACES reference gamut compression 前置【2026-10-01 M2-6-2 Delivered（ACES 2.0 子集）：Limiting Space 七选数据表（rec709/rec2020/p3d65/p3d60/p3dci/proPhoto/adobeRGB，规格原色逐行署名 + 白映射锚）+ ACES 1.3 reference gamut compression 内置前置段（v1.3 tag BSD 转录，kernel 常量默认 on，OpenDRT 路径不经过——活体校验钉死）+ CAM16 JMh 核（往返 ≤1e-6）+ ODT Float64 参考（灰锚 18%→10.0 nits）+ drt_aces2 Metal kernel（golden worst p99.9=2.28e-6）+ aces20 方法臂；上游 v2.0 main Apache-2.0 许可更正亲核成立，NOTICE/Apache 文本/头注三处署名；验收 PASS（M2-6-2-ACCEPTANCE：aces-core 上游源码抽 5+ 函数亲核转录忠实 + 三域复跑 999 executed/6 skip/0 fail 与声明逐值一致）】【2026-10-01 M2-6-3 终态补注（验收）：Limiting Space 七选面板组落地（method==aces20 时显示）；method 切换单 discrete commit + 幂等连点测试钉】
- [x] **M2DRT-04**: Color & Encoding——Encoding Space 六选（Rec.709/P3-D65/P3-D60/P3-DCI/XYZ/Rec.2020）+ EOTF 随空间联动 + Peak Luminance 100-1000 nits；HDR 判定 = EOTF∈{ST2084,HLG}，驱动 EDR 预览与导出链【2026-10-01 M2-6-1 部分交付（验收注记）：legalEOTFs Core 单源 + isHdrEncoding 纯函数 + EOTF 编码核七函数（Float64+Metal 双落笔，st2084 decode 升带 5e-5 签注经 numpy 仿算独立复核）+ EDR 预览联动渲染腿 = drtTail（T7）已交付；EOTF 面板/视口 colorSpace 切换与导出链接线归 P3（M2-6-3）/M2-9，勾选留该批】【2026-10-01 M2-6-3 Delivered（面板+视口腿）：EOTF 面板（六空间 picker / EOTF 合法子集联动吸附=同空间首合法同 commit 原子 undo ~60 组合机检 / Peak 100-1000 slider D-H1 三件式；legalEOTFs Core 单源消费 UI 零第二实现）+ HDR→EDR 视口（isHdrEncoding 单源 → 四态 surface：DRT-SDR = bgra8+编码空间 calibrated colorSpace；DRT-HDR = 16F+EDR content+itur_2100_PQ/HLG（P3 编码走 displayP3_PQ/HLG——SDK 无 extendedITUR_2100 变体，DECISIONS D2 plan 字母修正）；D-COL2 follow gate 扩展 `!edrActive && !drtTailActive`（E3，encoding-space 挂载连续帧存活测试钉）+ 手动 EDR 互斥双层面【coordinator guard + 控件置灰】）；非 DRT 路径逐字节不变红线测试钉；**导出链接线 = M2-9**（EOTF 编码核/判定/DrtTailParams 复用面已备，writer/ICC/队列按 ROADMAP M2-9 行接线）；验收 PASS（`phases/m2-6-drt/M2-6-3-ACCEPTANCE.md`）】
- [x] **M2DRT-05**: DRT/Post 四件套（Clarity ±100/Sharpen amount-radius-threshold/Halation 0-1/FilmGrain 0-1）在 display transform 后对全图应用一次（预览=成品）【2026-10-01 M2-6-3 Delivered（Post 迁移）：drt 尾段激活时四件主链 skip + TailOrderedBox 槽位重放（74.1+ 槽序 = DRT 74.0 → post 四件 → EOTF 75.0 → borders/watermark 76/77，原 box 转发零新 kernel）+ 尾平面键折叠增 post 集（E5：空集零折叠 P1 种子位等；四件参数变更 → 尾平面 MISS、method plane+主链全 HIT——键局部性测试钉 4 miss 断言）+ 尾平面格式修正（EOTF 前恒 working float32；P1 主链顶面 8-bit 量化缺陷退休 = DECISIONS D9）+ display-referred 锚表（DECISIONS D4：sharpen/equalizer/bloom/grain 中心 BGRA [149,149,149,255]/grain [145,146,146,255]，kernel 字节零改；display 域视觉强度 = 走查观察项）+ Look 页 `panel_note_pre_drt` 摘除（TAB-MATRIX 勘误行同步）；非 drt 档四件主链原位零回归测试钉；验收 PASS（`phases/m2-6-drt/M2-6-3-ACCEPTANCE.md`）】
- [x] **M2DRT-06**: 独有 DRT 扩展位（filmic/sigmoid/agx 按 D1 v1 禁用；架构预留 DRT method 注册口）【2026-10-01 M2-6-1 交付注记（验收留后续）：DrtMethod 枚举注册口（aces_2_0/open_drt，cpp ToJson 终式）+ 穷举 switch 无 default 纪律 + aces20 显式 stub（isRenderImplemented 翻面 = P2 替换面）+ filmic/sigmoid/agx 零注册（Registry grep 零新增）；注册口本体已落地，终验勾选留 P2 aces20 渲染臂翻面后一并核】【2026-10-01 M2-6-2 补注（验收）：P2 臂填充交付——aces20 活臂（DrtMethodBox 双分派函数 switch 穷举 + isRenderImplemented 翻面 + 两 stub-pin 断言翻活臂断言，E4 族申报口径核过）；注册口两 case 全可达 + 零注册保持；**终验勾选留 P3**（面板分段卡/导出链接线批，M2-6-3）】【2026-10-01 M2-6-3 终验 Delivered（method 收口）：面板暴露 `[aces20, opendrt]`（DrtMethod 枚举即注册面；预留 case 不入枚举——新 method 加 case 即编译期断穷举 switch）；`defaultFaceDisabledOpNames`/Registry/NodeOwnershipCatalog M2-6 全程零 diff（git 机检亲核）；D1 v1 promise 兑现；「parity 后评估回归」挂账 = AGENTS.md M2-6 增量节注记（非代码）；zh 对账 audit PASS（1282 源键/1495 目录键，技术专名不译 OQ-12-A）；验收 PASS（`phases/m2-6-drt/M2-6-3-ACCEPTANCE.md`）】【2026-10-07 M2 closeout 终态（Delivered）：记账件翻勾——M2-6-3 终验 Delivered（method 收口）+ 验收 PASS 在案，证据 = `phases/m2-6-drt/M2-6-3-ACCEPTANCE.md`（checker E2）】

### 蒙版 (MASK2)
- [x] **M2MASK-01**: Radial（center 0.5/0.5、major/minor 0.5、rotation、inner/outer feather，归一化参考空间） **Delivered 数据/内核**（M2-7-1 T1：`EllipseForm` additive `innerFeather/outerFeather: Float?` 双羽化——MSL Alcedo 线性带腿（`grade_mask_coverage.cpp:150-153` 逐式：rho=sqrt(q)/inner=max(0,1−iF)/outer=1+max(0,oF)/value=1−clamp((rho−inner)/max(outer−inner,ε))，验收方亲核数学等价）+ uniform form2 槽尾追加（modeFlag 分流：双 nil→旧二次腿逐字节=06-03 goldens 零改动复跑即证；任一非 nil→Alcedo 腿，腿内 nil→0 补缺，**双 0 显式=硬边不回落**（checker E7 测试格））+ facade mode-aware 单源 `resolvedOuterFeather = outerFeather ?? (innerFeather != nil ? 0 : border)`；MaskFeatherAlignTests 9【LAYERS】双腿 float64 parity ≤1e-6 + 三采样锚点 + 回落矩阵；锚 `d6de037`）
- [x] **M2MASK-02**: LinearGradient（origin/normal/transition 0.2/start 1→end 0） **Delivered 换算钉**（M2-7-1 T2：零 schema 改动映射——换算式 plan 期钉死 `compression = transition_distance/(2√2)`（τ=0.2→c≈0.0707107，方形窗推导；方向 `rotation = atan2(nx, ny)`，plan 草稿「−90」示例文字被 golden 否决裁 +90——偏差-1 有据）+ `MaskGradientDefaults.compressionDefault` Core 常量单源（P2 面板消费点）+ golden 两档（0.2/1.0）逐点 ≤1e-6 + 方向/起止锚；非方窗 aspect 各向异性注记归 P2 DECISIONS；锚 `3ab8aad`）
- [x] **M2MASK-03**: Brush（复用 Phase 6 资产对齐 Alcedo 笔划/revision/乐观并发模型） **Delivered revision/并发面**（M2-7-1 T5（D-M2-7-CONTEXT-2 收敛口径：Phase 6 stamping 数据正本不动，对齐落点 = revision/乐观并发 + mask 级属性）——见 M2MASK-07；stamping 0.744ms/千枚 golden 零回归）
- [x] **M2MASK-04**: mask 级属性与语义——display_name/enabled/opacity/invert/feather/deletion_protected；应用序 = feather→invert→opacity→clamp **Delivered**（M2-7-1 T3/T4：`MaskGroupItem.feather: Float?` + `drawnGroupPlane` 条目级 Deriche blur 腿（reduce 前、>0.1 门 dt blend.c:306 同款；enabled 过滤/五式/reduce 装配零 diff）+ 应用序 feather→invert→opacity→clamp 非空转探针钉死（原「feather/invert 调换」机制线性算子下数学不可达，重设计双条目非线性 combine 构造——偏差-8 有据）+ facade 三 setter（setItemFeather/Inverted/Opacity，miss 静默 no-op）+ `mutateTopLevelItem` 深度优先递归 walk（嵌套 child 寻址，首中语义头注化）+ sidecar 载体 `deletionProtected`/`contentRevision` capture/restore 各一行（D-M2-4-1-3 挂账兑现，SidecarV5Tests `:204` 缺口钉翻面双向真断言、`:111/:119/:164` 零漂移族零 touch）；MaskItemSemanticsTests +5；锚 `1a038a5`/`7231c14`）【2026-10-01 M2-7-2 载体兑现注记（验收）：五 mask 级属性全部获得面板消费面——enabled/invert/opacity/feather/displayName 编辑走 EditorState `commitMaskEdit` 统一缝（`history_mask_item_*` 键族恰 1 item + 写点⑤ bump 在缝内；live 预览走 applyLiveMaskEdit 零 bump）；deletion_protected 锁删面板行级沿用双腿 toast 零 history（测试钉）；display_name 缺省派生消费 Core `nextLayerName` 单源】
- [x] **M2MASK-05**: Nitro 扩展——Follow Edges 边缘感知笔刷（IOP-MASK-06 提级 V1）+ Luminance/Color Range（内核复用 Phase 6，UI 按 Nitro 呈现，D5）+ AI Subject 入口（subject+invert sugar） 【2026-10-01 M2-7-1 部分交付注记（验收）：Follow Edges **内核已交付**——`mask_edge_map` Sobel luma kernel（单 PSO 零 function constant）+ PipeCacheKey additive（`edgeMapPosition=-4`（-3 实占 retouch，checker E2 勘误）+ `edgeMapKey` 静态键（imageID⊕pipeType⊕upstreamHash⊕算法版本⊕roi，below 前缀跨 grade 共享）+ `layerTier` 一行 `-4→.maskPlane` 分支 + edgeMapNamespaceID）+ CPU 切向流线 walker（lookahead 侧翼采样/动量混合/阈值停门/半像素去重/纯函数确定性/L014 fence 读回 ≤512）+ `.streamline`/`.snap` 熔断双 case 预埋（switch 穷举零 default）+ 失败降级空链语义；FollowEdgesTests 8【LAYERS】三景 golden+降级+纯函数性；**接线（stamp 调用面/UI 入口）归 P2（M2-7-2）**；Luminance/Color Range 与 AI Subject 未动；锚 `066423f`】【2026-10-01 M2-7-2 Delivered（验收）：三件全清——①Follow Edges **接线**：`MaskTool.followEdges` case（CaseIterable radio 自动纳入 + 六工具 AX pin 更新）+ coordinator READ seam（`followEdgesSurface` = 截断栈复合经既有 `processComposite`、preview 后子运行缓存暖、零 driver/pipe diff + prefixHash Hasher 折叠（imageID⊕base⊕下层 id+chain records，进程内不持久）+ `edgeMapField` 缓存 8 条 dict（键 prefixHash，失效语义等价 P1 键函数——Core internal 键类型 App 不可名，DECISIONS 偏差 4）+ L014 fence 读回）+ 交互腿（press=seed→seam→edge map→walker→BrushStroke→appendForm live 腿；drag 重走 mutate 臂 newest-wins generation guard；空链 = 零 append + 状态条降级）+ 触点穷举零 default（Grab 三既有 default 收紧为显式 case 表）；合成边缘场贴边 stroke 测试 = 真 kernel+真 fenced readback 仅注入 surface（stub-seam 形态），点链距边缘 ≤2px + 恰 1 bump；②Luminance/Color Range：`LuminanceColorRangePanelView`（luma 梯形 + Cz/hz 带 + 吸管走 pickColor 线性管 seam → IOP `JzCzhz.fromRGB` 单源——Core 不落换算函数（Core 不能 import IOP），Core 只落纯 UI 域映射 `luminanceTrapezoid`/`colorRangeEntries`，「禁第二 Jz 实现」红线优先于 plan「换算落 Core」原文，偏差 D-3 有据）+ boost 既有 −6.64385619 ×100 UI 约定 + 提交走 commitMaskEdit（`history_mask_range_*` 键族恰 1 item）；③AI Subject sugar：「主体以外」入口 subject 流复用 + invert 走 `RasterMaskRef.invert` 既有位（KD-7 raster-first），多主体 picker pendingInvert 穿插，**AIMaskEditing/AIMaskService 零 diff 红线兑现**（git 机检亲核）；RangePanelMappingTests 4【LAYERS】+ MaskRevisionTests +5 + MaskGroupsPanelTests +1（sugar round-trip + 覆盖重烤）；锚 `f9601c2`/`35ea75c`/`b95f033`，验收 `phases/m2-7-masks/M2-7-2-ACCEPTANCE.md`】【2026-10-01 M2-7-3 熔断行使注记（P3 走查裁决，OQ-4-C）：**Delivered（snap 态，streamline 挂 V2）**——真实样张走查（DSC00012.ARW 60.2MP，真 kernel + FollowEdges.swift 原文进程内探针，GUI pointer 通道环境受限如实披露）实测判据②成立：streamline 8 景盒 × 2 阈值链长 ≤3 点 + 100-seed 网格 82/100 空 + 场分辨率/步长扫频 0/3 功能链（排除降采样假说）；snap 12px 触达内确定性贴边；判据① 冷 6.3ms 中位远内 200ms；判据③ n/a（seam 只跑 preview 桶）。行使 = `LayerEditingState` 默认翻 `.snap`（`60582c3` 一行），walker/`.streamline` 分支保留模式选择器可选，完整流线 V2 复活零重写；证据 `evidence/m2-7-3/`（probe.log + ev_*.png），移交 `phases/m2-7-masks/M2-7-3-ACCEPTANCE-INPUT.md` §二（验收方有权以证据推翻）；验收 `phases/m2-7-masks/M2-7-3-ACCEPTANCE.md`（**裁决独立复现亲证**：probe 源码逐字节重建复跑——82/100 空/24 景链型/DIAG 0/3 逐值复现 + 6 张证据图 md5 逐字节一致；账面 6.1/80.3 混引已勘误为在案 log 真值 6.3/73.7）】
- [x] **M2MASK-06**: 蒙版编辑 UI——图上绘制+手柄 overlay、Mask Groups 面板（组序=grade 序拖动、蒙版缩略图 GPU 管线、锁删提示、Locate unfinished node 提示）、Default Behavior 三选 （P2 = M2-7-2 地盘；M2-7-1 只落 P2 消费的 Core facade/内核语义，UI 零触碰）【2026-10-01 M2-7-2 Delivered（验收）：①缩略 GPU 管线 = `MaskThumbnailRenderer`（assembleUnmasked 单入口复用 + RGBA 横 ramp 输入（parametric 腿在 ramp 上求值即窗口可视化，内核单源）+ LRU 键 = stableHash⊕size 档⊕窗口 dims（aspect 折入，checker M4）+ L014 fence 读回 8-bit gray + 空载荷 nil 占位降级 + 零 queue/device 创建（AC9 grep 零命中））；②Mask Groups 面板 = `PipelineDocument.maskGroups` grade 序投影纯消费（PipelineDocument 零 diff；走查抓出 LazyVStack 观察域读取缺陷当场修 `db8a211`——投影读取提 body 作用域）+ `MaskCommand` 增 `addMaskItem`/`removeMaskItem` payload-free（checker M5 选 A：删除目标 itemID 走执行缝参数 + 层菜单 `panelMenuCases` 白名单五项防 CaseIterable 泄漏）+ remove 连带孤儿 form 清扫 + 锁删双腿拦截零 history + Locate = 层选中 + pendingTabRoute 页签联动 + EditorState 统一缝（applyLiveMaskEdit 零 bump / commitMaskEdit 恰 1 item、写点⑤ bump 在缝内）；③双羽化手柄 = rim 内/外带双 grips（16px 命中 + legacy border 折 outer 转换）+ 导引线三 token；④Default Behavior = **完成时**消费 M2-3 既有面（枚举/键/设置页零新造，SettingsPages 仅 hint 一行；checker E1 勘误——M2-3 页面三处文字见证对表，arm 时作废入 DECISIONS）+ 三分流（currentNode 零动作 / newLayer `migrateMaskToNewLayer` 恰 1 结构 item 源层无残留 / ask 一次性 sheet 不持久）+ resolver 注入式（body 零 UserDefaults，grep 零命中）；⑤乐观并发接线 = expectedRevision 快照钉 press 段写毕后 + 先校验后 bump（append 重放 dedup / mutate 拒绝 toast 分派；正常笔画相等路径恰 +1 不走重放）；MaskGroupsPanelTests 9 + MaskDefaultBehaviorTests 5 + MaskThumbnailRendererTests 9【Project.swift + BUNDLE-MAP 双登记闭环】；锚 `4e8299c`/`6badfc2`/`1bdfb60`/`b7412a8`/`db8a211`，验收 `phases/m2-7-masks/M2-7-2-ACCEPTANCE.md`】
- [x] **M2MASK-07**: 蒙版内容单调 revision（MaskContentRevision）+ 笔划追加乐观并发校验 **Delivered**（M2-7-1 T5：`MaskSpec.contentRevision: Int?`（nil=0）+ `bumpContentRevision()` 单一助手 + `matchesExpected` 校验原语 Core 单源（`contentRevision ?? 0` grep 全仓仅 MaskSpec.swift 3 处，AC6 机检亲核）+ **写点终表五处 bump 载体**（overlay `endInteraction` 提交腿恰一次 dirty 门/live tick 零 bump——appendForm/mutateForm 亲验无 bump 调用/AI install 提交前 gate+bump/`fill` 前向携带 +1/`duplicateAndInvert` +1；duplicate/resetEdits/clear 零 bump 载体裁决有据（内容搬运/chain 回退/无生产目标））+ AI 失配拒装 typed error（gate 读 post-await live spec，bake 窗口穿插写必命中）+ undo 穿越写被拒 + D-M2-4-2-5 同批兑现（`MaskOverlayRecord` 抽取 sibling 保真构造 `spec = layer.mask ?? MaskSpec(); spec.drawn = drawn`——parametric/raster/deletionProtected/contentRevision 四 sibling 存活揭穿测试钉）+ overlay 腿 expectedRevision 参数面留 P2 接线；MaskRevisionTests 6【APP】；锚 `768d5e3`，验收 `phases/m2-7-masks/M2-7-1-ACCEPTANCE.md`）

### 版本与历史 (VER)
- [x] **M2VER-01**: EditCommit 不可变 commit 图（hash 主键、双亲=分支/合并、created_at_ns、kind、edit_payload JSON）**Delivered（v1 收窄态，sidecar v7 + .lalb version_ref 双载体）**（M2-8-1：commit 图面经 D-M2-8-CONTEXT-2-A 晨审追认①收窄为**独立线性事务链**——无 hash DAG，`edit_commit/pipeline_root` 列名维持预留（reduced DDL 签注，将来翻 DAG 世界线可 additive 加回）；版本身份数据面双载体交付——①sidecar v7 additive 双可选键 `versions:[SidecarVersionRecord]?`（id/name/createdAt/updatedAt + 非活跃链复用 FROZEN `{items,position}` 拼写）+ `activeVersionID`，`schemaVersionCurrent` 6→7，nil 双键 v6 逐字节零漂移（SidecarV7Tests 三字节面钉）+ items 不双写 + historyHash 零折叠负测；②`.lalb` `version_ref` 投影表 v2→v3 迁移激活（reduced 5 列 DDL，head_commit_hash 不激活；`replaceVersionRefs` 单事务整表 reconcile 幂等投影 + FK CASCADE + 注入式 sink）；锚 `2afeb3a`/`69a30ec`，验收 `phases/m2-8-versions/M2-8-1-ACCEPTANCE.md`）
- [x] **M2VER-02**: VersionRef 命名版本——从导入原始态新建 + branch from current commit + fork from root + rename/remove；版本切换即时、自动保存（**命令面 Delivered（M2-8-1）**：`VersionCoordinator` 三命令 createFromScratch/branchFromCurrent/switchTo + rename/remove + materialize-on-first-create + dangling typed degrade——`fork from root` 经 D-M2-8-CONTEXT-3-A 晨审追认②并入新建（无 DAG 同型）；切换即时 = 链 swap 零 await 单快照 + `rebuildLayerStack` param 重放（同图零重解码，DRT carrier 重同步）；自动保存 = 版本动作 `scheduleSidecarWrite` 走既有 2s debounce；真链 VersionSwapTests 11 法钉死含 E4 跨图污染。**面板 Delivered（M2-8-2 验收 2026-10-01 PASS）**：VersionsPanelView （name/updated_at/active 徽标 + 新建/Branch + 行菜单 inline rename/Remove 确认对话框 + 单击切换 + 空态引导；`editor.versions.placeholder` marker 退役）+ KD-1 默认名归 UI （coordinator 三命令 name 参数化）——VersionsPanelTests 5 法真链钉死，全字面达成）
- [x] **M2VER-03**: ImageEditState 材质化缓存（active_version/materialized_head/transaction_chain；仅加速恢复非用户概念）**Delivered (in-memory: OQ-5-A——ImageEditState 不落库，param 重放兑现)**（内存态兑现（M2-8-1，D-M2-8-CONTEXT-5-A）：active 链常驻内存 + param 重放 = 切换即时语义的需求侧兑现；`image_edit_state` 表维持预留**不落库**；切换即时性观察数字落账 = M2-8-3 DECISIONS §2.1（500 链切换 avg 0.562ms / max 1.073ms，debug 口径，与单次编辑 commit 同数量级——不超带不立项）；M2VER-03 完整落库面随需求重开时另立案）
- [x] **M2VER-04**: 历史=版本内线性事务流——每行操作名+参数 delta+时间；永久 undo/redo（跳回后 redo 尾巴保留、再编辑丢弃尾巴）；崩溃恢复条（**部分交付（M2-8-1）**：版本内线性事务流本体 = v7 `history` 键语义升级「active 版本链」（拼写冻结零改，v6 读者降级可读）；链 swap/branch 快照时点（redo 尾留源版本，jump 点保留）/remove 两边界语义交付并测钉。**历史行 UI + 崩溃恢复条 Delivered（M2-8-2 验收 2026-10-01 PASS）**：行可点跳 （原始索引换算在视图层）+ 类型图标（闭集 HistoryRowKind enum 映射后穷举 switch）+ position 高亮纯派生；undo 四条验收固化（跳回保尾/再编辑丢尾/双入口同源/500 链 .lra 重载逐字节 + 全程 undo 到 −1，HistoryRowJumpTests 7 法）；「每行参数 delta」半边经 D-M2-8-CONTEXT-8-A 裁决 Deferred（per-op 摘要设施挂账，不阻翻账）；崩溃恢复条 = OQ-9-A 哨兵 toast 最小面（`app.cleanTerminate` 双向哨兵 + 一次性 toast；附带修复 02-06 起 applicationWillTerminate 形参类型错误致回调从未触发的潜伏缺陷，LESSONS L052）——CleanTerminateSentinelTests 3 法 + kill 走查五格程序化在案。**M2-8-3 走查追记（2026-10-02，error 级登记另案）→ 已修闭环（2026-10-02 验收批 `4e7fc58`）**：哨兵 toast 的**屏上渲染点在默认 shell 缺席**（D-26 toast 通道 `StatusBar` 只挂 `legacyBody`，默认 `WorkspaceHostView` 面 grep 零 toast 面；真机 9 帧连拍帧帧无 toast——前证 `gui-acceptance/m2-8/m2-8-14` + M2-8-3 DECISIONS §3.3）——验收批修复：`ToastBarView` 零 chrome 面挂 `WorkspaceHostView` 底部 safeAreaInset（nil toast 零高度不添常驻条、有 toast 22pt StatusBar 语言面携 `status_toast` 标识；legacyBody 零触碰），ToastFaceTests 3 法钉死（零 chrome 契约 + 真 WorkspaceHostView 挂载 AX 树 wiring 可见性）；**修复后真机复验：哨兵 toast 于默认面底条清晰渲染 + 4s auto-clear 消退**（`m2-8-12/13`，`M2-8-3-ACCEPTANCE.md` §五）——屏上面缺席消解）
- [x] **M2VER-05**: Copy Adjustments——三层面板（Version→Node→Item 勾选）Paste 生成新 Version；不复制 RAW decode/lens/crop-rotation（**Delivered（M2-8-2 验收 2026-10-01 PASS）**：三 pane 对话框 + 源选择段（当前图/外部 .lra v7 多版本二级选择·v6 单链·损坏源 typed 错误）+ pasteChain 落新版本（OVERWRITE-paste epoch 复用零新投影语义 + DRT 第二 item + 蒙版 contentRevision 置 nil + 隐式目标 materialize）；不复制面 = isAdjustmentTransferable 单谓词（owner==.grade + terminal trio 显式排除；develop 15 + drtPost 4 全表穷举断言）——AdjustmentTransferTests 8 法钉死；库内图像选择器 Deferred（M2-8-2 DECISIONS §1.3 晨审追认点，调整复制主用例经外部 .lra 入口功能完整）。**M2-8-3 走查追记（2026-10-02，error 级登记另案）→ 已修闭环（2026-10-02 验收批 `e9c03af`）**：对话框**用户可达入口确定性崩溃**——Edit 菜单「复制调整…」开 sheet 即 EXC_BREAKPOINT（执行方 2/2 + 验收批 1/1 = 3/3 复现；机制落实：app-root sheet 闭包挂链在 `.environment(...)` 写入**之外**，sheet 内容环境快照缺 `VersionCoordinator`/`EditorState` 两 Observable——`m2-8-15` 崩溃报告 + M2-8-3 DECISIONS §3.2）——验收批修复：`AdjustmentTransferSheetContent` sheet 内容面显式重注入两 Observable（preset-manager Window / init 参数注入惯例线），`SheetEnvironmentInjectionTests` 以**真 `.sheet` 呈现**挂载生产 face 钉死（专防「非 sheet 层级测绿」盲区；负腿实测：掏空注入 = 测试宿主同一 fatal 签名硬失败）；**修复后真机复验：对话框 4 次开启全渲染零崩**（三 pane + 来源段 + 排除/枚举/禁用守卫面活体正确，`m2-8-09/10/11`，`M2-8-3-ACCEPTANCE.md` §五）——用户可达崩溃消解）

### 导出选项 (EXP2)
- [x] **M2EXP-01**: 尺寸四模式——Original/Long Edge/Bounds W×H/Print（in-cm-mm+DPI）+ allow_upscale + maximum_edge_pixels **模型+数学半边 Delivered（M2-9-01，验收 2026-10-02 PASS / 0e+1m，`M2-9-01-ACCEPTANCE.md`）**：`OutputMode` 四模式（+`bounds(w:h:)`/`physical(width:height:unit:dpi:)` + `ExportPhysicalUnit`）+ `allowUpscale`/`maximumEdgePixels` 字段 + 手写容错 decode（旧 payload 字面锚测试）+ `resolveExportResolution` 单源数学（Alcedo cpp:31-80/287-325 同构自写：fit-inside / upscale 钳 / cap 尾段全模式 + DPI 宽度比修正 golden 300×2/3=200 / physical DPI≤0 typed 失败）；消费面 **renderer DPI 接线半边 Delivered（M2-9-03 T1，验收 2026-10-03，`M2-9-03-ACCEPTANCE.md`）**——renderStage sizing 腿直切 `resolveExportResolution` + `StageOutput.dpi = result.dpi`（cap 宽度比修正 DPI 达产物元数据，golden 300×2/3=200 实测；legacy 三模式逐值零漂移论证），面板 UI 归 M2-9-04；**Delivered 终注（2026-10-03，M2-9-04 验收 `phases/m2-9-export/M2-9-04-ACCEPTANCE.md`）：面板 UI 半边兑现**——检查器 Export 页 SDR 节四模式字段按模式显隐（original 无字段 / longEdge 单框 / bounds W×H / physical 双维+单位+DPI）+ 高级折叠区两控件（allowUpscale=false / maximumEdgePixels=0，OQ-12 A）+ 模型域越界禁入（`sizingViolation` 按模型常量 1...100000 px / 1...2400 DPI / physical 0.01...100000 → `canRun` 禁用，UI 不静默钳）+ `makeSizing` 四模式映射测试钉（`ExportMemoryKeysTests`，QML:27-46 首用默认对表）
- [x] **M2EXP-02**: 元数据策略档位——默认剥离 location/设备序列号/编辑历史；EXIF 写入本 app 版本号 **模型半边 Delivered（M2-9-01，验收同上）**：`ExportMetadataPolicy` mode{standard,none}+6 bool（STANDARD = exif/xmp/iptc 真 + location/serials/editingHistory 固定剥离假；CONTEXT「7 bool」口语计数 = mode+6，Alcedo hpp 字段清单为准）落 `ExportVariant.metadataPolicy` 载体（默认 .standard）+ `embedICC` 载体；**消费半边 Delivered（M2-9-03 T2，验收 2026-10-03，`M2-9-03-ACCEPTANCE.md`）**——`ImageIOEncodeCore.mountMetadata` 单点装配腿（五 encoder 换调用点，编码核心面零 hunk = E1 案 A）+ OQ-6 剥离消费（BodySerialNumber + Exif-dict GPS 前缀 + {GPS} 构造性缺席；NONE 短路）+ EXIF Software（{TIFF} dict 座位——D-5 原文 Exif 座位全容器被弃，探针链 DECISIONS §1；JPEG readback 不回显走 byte-scan）+ `mountXMP` policy gate（.skippedByPolicy；默认档 packet 不嵌 = OQ-6 有意行为变更，XMPExportMatrixTests 显式传参改造锚定）；App 侧 `Lightamer <version>` 传值载体（exifSoftware）归 M2-9-04（queue 路径暂无载体，SUMMARY 交接）；**Delivered 终注（2026-10-03，M2-9-04 验收 `phases/m2-9-export/M2-9-04-ACCEPTANCE.md`）：App 侧传值载体兑现**——`exifSoftwareString(version:)` 纯函数 + `currentExifSoftware`（CFBundleShortVersionString）经 `enqueueExportM2` → enqueue `exifSoftware` 批参 → `$jobExifSoftware` TaskLocal（03 钦定递缝，引擎体零 hunk）→ `encodeStage`/`mountMetadata` {TIFF} Software 座位（03 座位正本次序不变）；真链捕获断言 encode 腿逐 job 载体值（`ExportAssemblyTests`）
- [x] **M2EXP-03**: 文件名模板——12 字段（stem/capture_date/camera/lens/iso/aperture/shutter/focal/rating/sequence 补零+literal）+ 冲突 FAIL/REPLACE + 子文件夹 **引擎+模型半边 Delivered（M2-9-01，验收同上）**：`ExportFileNameTemplate` 11 token+literal（12 面）parse/render 分离 + `{{}}`/`}}` 转义 + typed 五错误 + sequence 零计数位宽 + shutter `1-500` 形态 + sanitize 200 帽 + fallback "image"；`ExportNamer.ExportCollisionPolicy` 三档（increment 默认 = 既有 -1/-2 行为逐字节，重载对形态）；`NamingTemplateStore` 三内置（QML:35-52 拼写）+ CRUD + 损坏降级；**renderer 接线半边 Delivered（M2-9-03 T1，验收 2026-10-03，`M2-9-03-ACCEPTANCE.md`）**——step 9 逐 job 模板求值（decoded.capture 8 字段 + 盘上 rating〔override 模式同读〕+ sequence；空渲染 fallback；tag 拼接面不变）+ 冲突三档消费（FAIL=typed 拒绝零写盘/REPLACE/Increment；queue 占用枚举 landingDirectory 单源 join）+ 子文件夹消费（渲染前 typed 创建）+ `$jobNamingCarrier` TaskLocal 队列递缝（sequence 入队盖章批内序）；面板 UI/模板选择器归 M2-9-04；**Delivered 终注（2026-10-03，M2-9-04 验收 `phases/m2-9-export/M2-9-04-ACCEPTANCE.md`）：面板 UI/模板选择器半边兑现**——`ExportNamingEditor`（预设下拉 3 内置+用户+Custom 尾项 / 11 token 尾追插入〔DECISIONS §7 简化裁决〕/ typed parse 反馈红字+raw message / live 预览〔样本=队列首行名或当前图 stem，sequence=1，空 capture 字段缺省渲染〕/ 存 sheet+改名 inline+删〔内置不可删〕；手改 pattern→Custom 掉锚）+ 无效模板→`canRun` 禁用（add/run 同一门）+ queue 盖章批序真链断言（`ExportAssemblyTests` sequence 1/2 FIFO）
- [x] **M2EXP-04**: 输出 ICC 与本图 DRT 编码强制联动（space/EOTF/peak nits 入队前已解析）；格式矩阵保留原 6 格式（EXR/UltraHDR = V2 ALCE-02/03）**渲染链半边 Delivered（M2-9-02，验收 2026-10-03 PASS / 0e+1m，`M2-9-02-ACCEPTANCE.md`）**：`DrtOutputColorSpace` 输出 ICC 解析器（space×eotf 穷举无 default、accept-set==legalEOTFs==Alcedo cpp 三方逐行镜像、typed 拒绝；macOS 27 CalibratedRGB 平台缺陷 → SDR 幂臂自建 ICC v4 字节，锚值与 Alcedo .icc 资产逐位一致；HDR 三臂系统名）+ `exportDrtChain`（records verbatim + E7 哑值/`drtEncoding` 载体）+ `Request.drtTail`/`jobDrtTail` TaskLocal 队列递缝 + `enqueue(drtTails:)` + `tailFormatFloatOverride` 四处缝（导出尾平面恒 float32，quantizer 拥有钳位与位深 = OQ-8-A；display 面零漂移）+ yiyin×DRT E2E（印框 EOTF 后红线导出腿实证）；**元数据腿/OMIT 剥离半边 Delivered（M2-9-03 T3，验收 2026-10-03，`M2-9-03-ACCEPTANCE.md`）**——`ExportICCStrip` post-encode 剥离（JPEG APP2/PNG iCCP/TIFF tag 34675 原位压缩+孤儿清零；HEIC/AVIF/WebP typed 不可达档）+ `embedICC` encodeStage/render/queue 全消费 + `ExportVariant.validate` drtOutput peak 闸门（finite 正数 typed 拒绝；nil 不触发 = E3 additive）；面板装配（`drtOutput` 非 nil = 联动开关注入）归 M2-9-04；**Delivered 终注（2026-10-03，M2-9-04 验收 `phases/m2-9-export/M2-9-04-ACCEPTANCE.md`）：面板装配半边兑现**——`enqueueExportM2` OQ-7 强制联动（`assembled.drtOutput = drtRecord`〔当前图 `effectiveDrtRecord() ?? DrtRecord()`〕+ 每图 `DrtTailParams(record:postOpNames: NodeOwnershipCatalog.drtPostOpNames)`〔PipeCoordinator :660 同法 verbatim〕）；装配级 peak 闸门兜底断言（bad peak → validate typed 拒绝含 "peak"；nil drtOutput 不触发 = legacy 面）
- [x] **M2EXP-05**: 导出队列 UI（检查器内+Queued/Exporting/Done/Failed 四态+质量跨会话记忆）；yiyin 印框/水印终步保留适配 **队列 UI 半边 Delivered（2026-10-03，M2-9-04，验收 `phases/m2-9-export/M2-9-04-ACCEPTANCE.md`）**：检查器 Export 页（OQ-1 A：`exportPageActive` 会话开关挂 Inspector 列，legacy sheet 冻结）+ `ExportQueueFaceView` 四态映射（pending→Queued / rendering+encoding→Exporting / done→Done / failed+cancelled→Failed 取消归败档，plan 已定裁决）+ 36 行帽+`…(N more)` 汇总 + done/total 进度 + 失败红字摘要 + per-job retry/cancel + 质量四键跨会话记忆（OQ-10 A：typed 读、run+离页写回、0.0 真记忆、异型降解）；yiyin 终步适配 = 队列注入器保留（`makeYiyinInjector` 随 rebuild 构造）+ topbar yiyin sheet 入口不变（M2 页无 yiyin 节——Alcedo 对标面无此项）；**Delivered 终注（2026-10-03，M2-9-05 走查批 `phases/m2-9-export/M2-9-05-DECISIONS.md` §5，证据 `.work/gui-acceptance/m2-9/`）**：真机走查兑现观感半边——五节观感（AX 树+截图双证）+ 尺寸四模式/折叠区默认屏上逐值 + 模板 3 内置/typed 红错/live 预览 + 单图 DRT 联动出片（Software="Lightamer 0.1.0" byte-scan + ICC=BT.1886 幂臂 + 无 GPS）+ 批量 sequence 0001..0003 落「导出」子目录（OQ-11 默认文案屏上证）+ 队列 46 jobs→36 行+「…（还有 10 项）」精确帽 + Failed 红字/retry（AXPress 翻完成）+ PQ 臂（Rec.2020 吸附 ST 2084 + 出片 ICC=系统 BT.2100 PQ CICP 9/16）+ legacy 回切双向（旧面/`export.page.*` 零命中）；挂账随注记：FAIL 冲突档 UI 未暴露（enqueueExportM2 固定 .increment——档位选择器缺口，随 F-2 通道或另案）+ yiyin M2 出片恒 false（04 裁决面，E2E 单测承载语义）+ legacy sheet 会话内实开（待人工可选余项）

### AI 图库 (AI2)
- [x] **M2AI-01**: 本地 CLIP 嵌入——CoreML 档模型可选（MobileCLIP2-512/SigLIP2/Jina-768 级），本地运行不上云。**模型获取 = 混合策略（✅ 2026-09-27 用户批准「就按这个方案」：五件套 = CLIP 搜索/自动打标/AI 评片/AI 描述/本地不上云承诺，每件带改进——默认模型内置免下载、MCP server 外部 agent 入口、编辑侧 AI 既有优势；默认模型须中文文本塔可用，具体档位 M2-10 research 实测后定。**✅ 2026-10-02 用户 OQ-1 裁决「采用偏质量」：默认内置档 = Chinese-CLIP ViT-B/16 质量档（int8 ≈190MB；MobileCLIP2 出局 = apple-amlr 研究许可 + 纯英文文本塔双伤，M2-10 research 核实）**）**：①默认语义模型**内置 app 包**（MobileCLIP2-S2 int8 CoreML ≈40-80MB）——零下载零网络依赖，反向消除 Alcedo 实测的「应用内下载 AI 离线包全报错」痛点（其默认端点已是 hf-mirror.com 但仍失败，疑 `model_assets.rs:496` `_hf_endpoint` 参数未接线）；②SigLIP2/Jina 大档走**本仓 GitHub Release 资产**可选下载（版本锁死），HF/hf-mirror 兜底；③权重许可（MobileCLIP MIT/CoreNet Apache-2.0 待核）与 int8 量化管线入 M2-10 research。**〔模型资产半边 Delivered——M2-10-01 验收 2026-10-03 PASS（`M2-10-01-ACCEPTANCE.md`）：五档位编译期清单定型 = bundled Chinese-CLIP ViT-B/16 int8（OQ-1-B；primary 92,558,991B + txt/vocab aux ≈192MB，Apache-2.0，zh+en 塔，E4 实证 inputSize 224²〔config.json+preprocessor 双证〕，digest 非 nil 且与盘上字节三方互验〔shasum 手搓独立复核〕）+ realesr-general-x4v3 fp16（2,494,268B，BSD-3-Clause）；release 三档 = jina-clip-v2 int8（Apache-2.0）/ real-esrgan-x4plus fp16（BSD-3-Clause）/ drunet-color fp16（MIT）digest nil = fail-closed 拒下载（上架后回填解除，M2-10-01-DECISIONS §6 维护者清单）。下载器 = GitHub Release 版本锁死 + hf-mirror/HF 兜底 + 流式 SHA-256 + 同目录 tmp 原子晋升。打包格式裁决 = mlprogram（A/B 平级 62.83/62.35ms，#2545 未复现）。**嵌入存储+检索+CLIP 搜索消费半边已 Delivered（M2AI-02 翻勾注记，M2-10-02 验收 2026-10-03）；打标/评片/描述/凭据消费半边已 Delivered（M2AI-03/04/05/06/07 翻勾，M2-10-03/04 验收；嵌入/打标本地面自 M2-10-05 起经 `--ai-worker` 子进程承载）；AI 出片增强半边已 Delivered（M2AI-09 翻勾注记，M2-10-06 验收 2026-10-04）；**设置 UI 半边 Delivered（M2-10-07 执行批 `9daf709`/`47e46c4`，2026-10-04）：LCR 页五档位清单（状态/许可/体积/内置-下载徽标/待发布禁点）+ 下载/移除/换激活（确认→registry recomputeAll 入队）+ AI 就绪探针 + 数据政策本地声明；全套 2955/16/0 对账（M2-10-07-SUMMARY）。全族闭环，本条翻勾**〕
- [x] **M2AI-02**: 嵌入存储+ANN 检索（SQLite 向量方案执行时定，对标 HNSW 近邻）+ 自然语言搜索入全局搜索三合一 **〔Delivered——M2-10-02 验收 2026-10-03 PASS（`M2-10-02-ACCEPTANCE.md`）：①嵌入存储 = LibrarySchema v4 additive 七表（user_version 3→4，v1/v2/v3 三出生形态单 dispatch 全链迁移测试 + OQ-9-A 单激活 partial unique DB 级强制 + fp16 BLOB native-endian + 四域 CASCADE）+ SemanticStore 四域 actor 原语；②检索 = D-1 裁决兑现（vDSP 暴力精确全扫为基线——「SQLite 向量方案执行时定」按 M2-10-CONTEXT D-1 用户裁决闭合，ANN/sqlite-vec 为 ≥20 万行或 p95>50ms 后手；实测 200k×512 median 32.05ms/31.56ms 两轮 ≤50ms 硬门 PASS，100k 档验收轮逐位重合 15.98ms）；③自然语言搜索 = GlobalSearchDialog CLIP tab 真腿（EXIF 腿同型集合过滤/typed `.modelUnavailable` 诚实空态/zero-hit 保开提示；真模型 zh「蓝天白云」+en「a clear blue sky」端到端 sanity 激活态绿）。嵌入生产写面 embedAndStore 同 plan 交付并真模型验证，导入管线接线归 M2AI-03 波（M2-10-03），若 03 波发现缺口回退本翻账（注记在案）〕**
- [x] **M2AI-03**: 自动打标——出厂中英 label query 原型嵌入余弦（score/second_label/margin/confident）+ 导入后询问 Remember-my-choice **〔Delivered——M2-10-03 验收 2026-10-03 PASS（`M2-10-03-ACCEPTANCE.md`）：①出厂集 = LabelQueries 173 标签 × zh/en 单源（Swift 源即唯一真相源，生成器正则解析零复制；幂等 seed 入 `label_query` 可查可审计，真 .lalb 双 seed 测试钉）；②原型余弦 = pinned-revision 文本塔原型 173×512 fp16（盘上 177,152B + revision 与 Catalog pin 逐字对 + gitignore 零跟踪亲验）+ LabelEngine 归一化点积分类全字段（margin≥0.05 inclusive nextUp 双侧机检/top8 裁度主行独占 top_scores JSON/revision-corrupt typed 拒绝族）；③导入询问 = LabelingAskDialog（Alcedo SemanticGenerationDialog 形态）+ `library.ai.labelingMode` ask/always/never 三态 + Remember 写回 + 真 ImportService 链测试 ×3。全套独立复跑 2797/16/0 单轮干净绿。命中质量走查（threshold 0.05/单句原型上限）挂 M2-10-07 走查——质量观察项非交付缺口；**labelingMode 三态 UI Delivered（M2-10-07 `47e46c4`）：LCR 页自动打标节（ask/always/never + 重置）；命中质量走查挂 M2-10-VALIDATION-INPUT 观察清单**〕**
- [x] **M2AI-04**: AI 评片——OpenAI/Anthropic 兼容 endpoint、1-5 星+理由（clamp；rating=0 reasons-only 哨兵）、星级写库、严格度+输出语言设置 **〔Delivered——M2-10-04 验收 2026-10-04 PASS（`M2-10-04-ACCEPTANCE.md`）：①双协议 endpoint = AIProviderClient 手写 Codable（openAI chat completions / anthropic messages，URL join golden + vision base64 载荷 + typed 错误族 + 零重试自动机费用护栏〔429/5xx typed 上抛用户手跑，DECISIONS §1〕）；②clamp（越界入 [1,5]）+ rating=0/缺席+reasons 哨兵行 + 无理由 typed malformed；③星级写库 = applyStars 确认门唯一写面（OQ-11-A：present 不落列负测钉三层 + 批 200 硬顶 + `library.ai.ratingConfirm` 不再询问偏好）；④严格度×语言 = rubric 五档×双语定稿（DECISIONS §3 文本即 profile 身份）——持久化设置 UI 与批量评片触发 UI 归 M2-10-07 ACA 页/Inspector 分析区（KD-2 明文承载）；**UI 半边 Delivered（M2-10-07 `9daf709`/`9586c1b`）：ACA 页 = 连接表单（准入前置行内拒绝）+ key Keychain 录入/清除 + 严格度/语言 + 不再询问开关 + 连接测试；Inspector 分析区 = 「AI 评片…」→ 顺序扫描（任务栏进度可取消）→ 确认门呈现（key 缺席 = 引导打开 ACA 页）**〕**
- [x] **M2AI-05**: AI 描述——caption+tags+scene+confidence + 全文检索文档（描述/标签进全局搜索） **〔Delivered——M2-10-04 验收 2026-10-04 PASS（`M2-10-04-ACCEPTANCE.md`）：①描述契约四字段（caption 必填/tags 默认/confidence clamp 0...1）→ `ai_understanding` reconcile（02 replaceUnderstanding 显式 DELETE+INSERT，L059 服务路径镜像回归 + rendition_kind edited 默认/original 显式）；②全文检索真腿 = `ai_understanding_fts` MATCH → **JOIN active=1**【E5：demote 行 raw MATCH 证索引在 + join 空集证陈旧行不命中，双钉】→ GlobalSearchDialog fulltext tab 真输入（CLIP/EXIF 分支零触碰 + 空态诚实 mode 分叉 + 族互斥测试），WorkspaceHostView 装配缝 +6 行（§9 申报追认）；**触发 UI 半边 Delivered（M2-10-07 `9586c1b`）：Inspector「AI 描述」命令 = 顺序扫描直写 `ai_understanding`（无确认门——派生数据语义，DECISIONS 签注）+ rendition_kind 按行 has_edits 分叉 + FTS 可检索零改**〕**
- [x] **M2AI-06**: 凭据与安全——Keychain 存 key（zeroize）+ 强制 HTTPS（localhost dev 例外）+ prompt profile 护栏（rubric 变更可检） **〔Delivered——M2-10-04 验收 2026-10-04 PASS（`M2-10-04-ACCEPTANCE.md`）：①AICredentialStore kSecClassGenericPassword 零状态面（service=bundle id，account=rating-provider 单连接 OQ-7-A；真宿主 keychain 测试激活态 7/0/0 非 skip）+ zeroize 字节级契约（`resetBytes(in: 0..<count)` 全 range + allSatisfy 断言〔L062 空 range 陷阱〕+ 调用方所有权/CoW 模型 DECISIONS §5）；②AIEndpointPolicy https 强制 + loopback 三 host（双 IPv6 拼写折叠）例外**无开关**（DECISIONS §2）+ 配置面/传输面双道门（client 发送前 guard 零流量负测）；③prompt_profile_id = StableHash FNV-1a **decimal String**（L013）over rubric|protocol|model——稳定 + 变更敏感测试钉；key 三面零泄漏（header-only/body 净/错误文案净）在案〕**
- [x] **M2AI-07**: 后台执行——任务注册表+取消，分析期间可继续工作 **〔Delivered——M2-10-03 验收 2026-10-03 PASS（`M2-10-03-ACCEPTANCE.md`）：①任务注册表 = AIAnalysisRegistry 三任务型（embedding/labeling/recomputeAll）conformer 挂既有 BackgroundTaskRegistry 聚合面（BackgroundTaskHosting 协议零 diff 亲证，栏/对话框零新增呈现面）；②取消 = per-task NSLock token + 每张检查点 + 增量终态（已完成行保留，重跑幂等 reconcile）+ exactly-once fire（drain 双 fire 回归测试揭穿力亲证）；③分析期间可继续工作 = 串行 utility QoS 单飞（maxInFlight==1 机检）+ 每张 Task.yield + 解码/IO 离主线程；四缺席路径 typed + lastFailureCopy 可观测（禁假开关）；recomputeAll = OQ-9-A 单批翻 active + 旧 key 行保留（取消保 partial + 翻档维持，测试双钉）。M2-10-02 嵌入接线回退条款不触发（runImport 成功尾自动嵌入腿真链 ×3 过，M2AI-02 翻账维持）〕**
- [x] **M2AI-08**: MCP server 保留互补（Phase 14 资产；launcher 与外部 client 双入口照旧）**〔Delivered——M2-10-07 收口核验 2026-10-04（`M2-10-07-DECISIONS.md` §D-OQ12）：M2AI-08 按字面「零新增」核验 = 本 plan 全批（`c573087..9586c1b`）`git diff --name-only App/Sources/Lightamer/MCP/ LightamerCore/Sources/MCP/` **零命中**（Export/Version 红线域同检零命中）+ MCP 既有测试全绿（App bundle）；`semantic_search` 工具 **defer 签认**（OQ-12-A 用户裁决 2026-10-02 采纳推荐 A——语义工具等外部需求立项，工具 schema/文档/安全走查都是新增验收面）；launcher 与外部 client 双入口照旧零触碰**〕**
- [x] **M2AI-09**: AI 出片入工作流——超分/降噪增强在独立预览对话框执行（模型档位 M2-10 research 定），结果作为**新可编辑副本**插入项目（版本链/胶片条可见、可继续调整），原图零触碰（Lumen RAW「editable copy」UX 模式，2026-10-01 用户裁决采纳；副本格式按 Lightamer 惯例随原格式 + sidecar，不强制 DNG）**〔Delivered——M2-10-06 验收 2026-10-04 PASS（`M2-10-06-ACCEPTANCE.md`）：①sidecar v8 additive `aiProvenance` 六字段（D-3 snake_case 冻结 + hash 隔离，v7 三字节形 pin + tamper 负测）；②TileInference 纯面（exact-shape 网格末 tile 对齐轴尾 / 线性 ramp 归一 / 400MP 输出像素域 typed / 15+78 进度曲线）+ EnhanceEngine 编排（blend 行距 = tile 实宽 / 取消 checkpoint + tmp 清扫）；③副本落盘 = EnhanceCopyWriter（POSIX O_EXCL 命名递增 Lumen 形 / 16-bit 容器规则——16-bit PNG 同格式、其余 TIFF 16〔DECISIONS §1 有意收窄「随原格式」，晨审可推翻〕/ EXIF 继承 + orientation 烘焙 + GPS 保留 / 失败清占位）+ `ImportService.importFile` 单文件孪生（复用 insertRow 零复制粘贴 + pristine `.lra` mint 带 provenance + 原图字节/无 sidecar 零触碰断言——D-3 version_ref 语义按 checker M4 消歧执行）；④EnhanceDialog（中央 192² 预览同引擎同模型单 tile / 下载行四态 / close-after 取消语义）。**真模型 golden 激活态**：64²→256² 经真 worker 子进程（capability discovery 断言 tileEdges `[256]`/scale 4），两轮 ≤1/255，3.352s 非 skip 亲点；全套 2926/16/0 精确对账（App 首轮 SidecarV5 在案 ANE flake → 隔离 11/0/0 + 全量 601/0/0 复绿）。**注记**：对话框双入口接线（网格/编辑器入口 + 生产 seams 注入）+ release 档上架后下载行走 ModelAssetStore → M2-10-07；100MP×2 级大图 fp32 双缓冲峰值贴 8G 门（实测口径 > DECISIONS §12 申报值）→ tile 直写流水线化挂 Maintenance（E3 后手）；**双入口接线 Delivered（M2-10-07 `9586c1b`）：图库右键两命令 + 编辑器 Image 菜单两命令 → EnhanceDialog 生产缝（frameProvider = 原文件解码 D-3 新源像素语义 / worker 通道 / import twin）；顺序单张批量 v1 + typed 内存闸（c573087）前置**〕**
- [x] **M2AI-10**: AI 推理进程隔离 crash-safe——神经模型推理跑独立 worker 进程：推理崩溃编辑器不死、任务可重试/降级（设备不可用换 ANE↔GPU↔CPU）、记住失败设备组合；M2AI 本地推理面（01..05/09）共用此范式（Lumen RAW crash-safe 模式，2026-10-01 用户裁决采纳）**〔Delivered——M2-10-05 验收 2026-10-04 PASS（`M2-10-05-ACCEPTANCE.md`）：①`--ai-worker` 同 binary 子进程（OQ-5-A，无 InProcess 兜底——装配面零回退构造亲证）+ UInt32 BE 长度前缀 JSON 帧协议（8MB 构造期分界 + 坏帧容忍；OQ-10-C 混合通道定稿——IPC spike 真子进程实测 ping 0.025ms/小图字节通道亚毫秒/50MP TIFF 路径通道 15.5-19.4ms）；②crash-safe 链 = DEBUG+env 双门钩子真 exit(9)（Lumen LUMEN_TEST_WORKER_CRASH 范式 + `@units` 扩展形）→ generation 重启 → `.all→.cpuAndGPU→.cpuOnly` 增量剔除降级链（MAX_RETRIES=4/open 900s/run 600s，超时 SIGKILL+收尸/管道断裂折叠 typed）→ `.workerExhausted/.workerUnavailable` 诚实呈现；③CompatRecord = ai-compat.json per 机型+OS build per 模型 per units 记账（两模型同 units 崩全禁/CPU 崩恒不记/同目录 tmp 原子写/坏 JSON 容忍/resetAll API——按钮面归 M2-10-07）；④装配单点换 AIWorkerClient（02/03 消费面零 diff，AnalysisRegistryTests 13/0/0 + SemanticSearchTests 10/0/0 零涟漪）。全套 2890/16/0 精确对账；E1 真链测试 + 验收独立 python 探针双证（HOOK-EXIT: 9/坏帧存活/stop exit 0）。M2AI-09 增强推理腿 = 路径通道帧形状已就绪、推理落 M2-10-06；**「重置 AI 兼容性记录」按钮 Delivered（M2-10-07 `47e46c4`）：LCR 页诊断节 = 确认对话框 → `CompatRecord.resetAll()`（文件删除终态测试钉）+ `.workerUnavailable/.workerExhausted` 的就绪探针可见面**〕**

### 性能与收口 (M2PERF)
- [x] **M2PERF-01**: 原 PERF-01..07 按新架构重校——60fps@100MP 决战/零卡顿 hitch=0/RAW9 解码 500ms 可交互/懒加载万张 60fps/批量 apply 万张≤5s/内存 3GB/Instruments profile 落账 **〔重述批 2026-10-07（M2-11-04 D-3；checkbox 翻勾归 M2-11-05 closeout；原 PERF 族 :613-620 历史行零触碰；数字正本 = `phases/m2-11-performance/perf.md`）：①**PERF-01 链面重述（OQ-5-A M2 默认面）** = Develop + 1 Grade（defaultLook +1.5EV/+15/1.3）+ DRT SDR，preview-2560 真样张；静态 warm 复测 ARW 60.2MP = 13.4 Debug / 13.2 Release ms（达标）、RAF 100MP = 14-42 带 / 37.2 ms（双峰噪声 O-1 未稳态达标，移交 M2-11-05 GUI 轮顺带观察）；拖动门两档终值——color 七件 ARW 8.6/8.6/8.9（Debug）与 8.7/8.2/8.1（Release）双构建达标（RAF 8.1-21 带，best-round 9.7-11.9 达标）、denoise 单件 ~65(RAF)/~57.5(ARW) ms 未达 16.6ms（OQ-7-A bounded 降载三档 57→~37→~29 趟全不达 + 引擎级单腿 26.5ms@29 趟独自超门 = decimate 杠杆数学不可达，revert 零产线 diff，V2 备选语义「denoise 拖动降档预览」挂账）。②**PERF-05 重述（OQ-6-A；门对象 = PREVIEW 缩略桶 512）** = open→512 缩略桶首帧 ≤500ms（warm）——实测 0.172s(RAF 100MP)/0.194s(ARW 60.2MP) **达标**（余量 ~2.6-2.9×）；fit（2560）桶 = 记录档（首帧 2.806/5.061s，warm 中位 2.07/1.94s，在案 13 perf :18 ≈2.08s）显式归类观察项；RAW9 CoreML 编译冷 2.62s 单列（首编译态，本轮磁盘缓存命中态不可复现，不入门）；渐进显示 = 观察项不强制。③**PERF-02 重述（OQ-1-A 内存三分法）**——①GUI 编辑器交互稳态工作集 ≤3GB：实机三轮 footprint 中位 **1975MB ≈1.93GB PASS**（余量 ~1.55×，`/usr/bin/footprint` phys_footprint 口径，perf.md §PERF-02）②FULL 管线瞬态 = TilingPlan 窗口有界断言维持（不设绝对数；MemoryBudgetTests bilateral FULL 门 + testFullToneEqualMemoryBudget 零触碰）③测试宿主 8G = 运行门（MEMFAIL 机检）非内存 SC 门（M2-4-0 SPIKE `70e09e5` 证伪 <3G 宿主门）。④**PERF-03/04/06 终值指针**：Instruments trace ×2 盘上归档（编辑会话 33MB + hitch 432MB，`phases/m2-11-performance/profile/`）+ MainActor ≥250ms hang = 0 + hitch >50ms（拖动场景）= 0（缩放/平移/万张滚动 Manual-Only → M2-11-05 GUI 轮）；懒加载档 A Release 9.7ms/张 ✓、档 B Release 2.70s/张（预算上沿外 ~35%，量级一致，吞吐由档 A 承担；09 perf.md §浏览模式）。⑤**PERF-07 Delivered 维持**：万张 apply 0.490s（门 ≤5s 余量 ~10×）——终验轮带内复核义务指向 M2-11-05。⑥**SpektraLab 对标两硬门（OQ-2-A）双 PASS**：FULL 桶全链 warm <1s——Release 60.2MP 168.2ms（余量 ~5.9×）/ 100MP 300.6ms（余量 ~3.3×）；尾平面命中重渲 ≤10ms——同参全命中腿 0.021ms / 单参 tick 尾段重放腿 5.009ms（Debug 同绿）；preview 全链 warm 85ms = 记录档（LUT 重贴 vs 全链渲染语义差异注记，不与 0.01s 对标）；单二进制 32MB 不对标（内置 AI 模型 ≈193MB by-design）。〕**【2026-10-07 M2 closeout 终态（Delivered）：逐门三列判定 = `phases/m2-11-performance/M2-11-VALIDATION-INPUT.md` §4.1——两硬门（SpektraLab ①②）PASS + 三分法/PERF-05 512 门/PERF-07（0.543s 带内）/PERF-03/04（缩放平移本轮补测 >50ms=0）达标；挂账面 = denoise 拖动（V2 语义）+ RAF O-1 观察项 + 万张滚动 Manual-Only；终验净轮 TOTAL|2961/16/0|1081s】
- [x] **M2PERF-02**: M2 全族 SC 终验 + VALIDATION + verify-work 签核 **〔口径注记（2026-10-07 M2-11-04）：终验基线 = 2955/16/0（M2-10 终值）+ M2-11 增量——02 波 +2、03 波 +3、04 波 +1 → 终验预期 2961/16/0；skip 16 按 test func 计零新增（M2-11 新测并入既有 func 或 fixture 在场即跑形态；若执行期新增 env 门控 func 则如实 16+Δs 记账，禁凑数）；全套 `--all` 终轮 + PERF-07 带内复核 + 翻账批 = M2-11-05。〕**【2026-10-07 M2 closeout 终态（Delivered）：VALIDATION 兼 M2 收口签核（OQ-8-A 单文档）——`M2-11-VALIDATION.md` status=validated + 终验 `TOTAL|2961/16/0|1081s` 干净绿（恢复协议后净轮）+ 红线域零 diff + L055 七日志核读 + 零 MEMFAIL；error 级 FINDING 两枚（ToneEqual 悬垂 retain / L057 家族 LUT 点位）已登记带 .ips 证据，归属晨审裁】

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
- [x] **YIYIN-09**: 预览面板拖拽调整——yiyin sheet 预览区支持拖拽垂直/水平分割线调整大小（对齐上游 ggchivalrous/yiyin PR #126 `a7ab9f8`，2026-10-07 fork 已同步 `f8de57a`；参考 `web/main/components/actions/`；Lightamer 侧 = yiyin sheet 预览面 UX 小件，M2-11 收官后 mini-plan）—— **→ M3-W1**（2026-10-08 V2 立项裁决，OQ-V2-7：与小件族同批搭车）
  - [x] **Delivered（M3-1-02，2026-10-08）**：**方案 A①映射（OQ-V2-7/OQ-M3-1-5 生效值）**——sheet 自身双方向拖拽调尺寸，上游 PR #126 五语义逐条移植（DECISIONS D7 形态对表 = 语义移植非像素移植：无图像列表/无 in-sheet 预览，分割线 = sheet 右/下缘 8pt invisible hit 条）：①双重钳制（px 界 120-720/160-560 原值移植 ∩ 比例域 0.15-0.75/0.35-0.92，上游扣除集不移植——D1 两域交仍有界）②松手才落盘（quantize3 三位小数，defaults 三段探针 + 注入式 defaults 机检双证）③拖动中零 history 零 pipe 零落盘（模型零引用结构断言 + GUI 探针）④容器缩放按 ratio 重排（mount 段 onGeometryChange 测 host 域递入——.sheet 内容面无法自测挂载域，D4）⑤实时读数 verbatim `w × h`。首用键缺席 = 现状 420×560 逐位零观感变化（上游持久化默认不采，D3）；**height 帽 560 = 默认高「只能缩不能增」= checker M7 有意裁定**（控制面板无高度增量语义，走查 GUI 直证「拖不动增高」且松手终端 ratio 照常落盘；D2）。持久化键 `yiyin.sheet.widthRatio/heightRatio` 注入式 defaults（AGENTS.md 键登记段已录）。走查正本 = `.work/gui-acceptance/m3-1/`（MANIFEST 七项全过 + 双方向终端四点 AX frame 逐位 + 跨会话持久 + 容器跟随实测）。测试新增 14（YiyinSheetSizingTests，APP 域；App 635→649/0/0 终绿）；执行期修复 = DragGesture `.global` 锚定（sheet 自运动耦合，D6/MANIFEST O-1 残余手感观察挂账）。**F-1 扩围登记（非本批面）**：New Project 面板取消即崩（L057 家族新实例，.ips 在证据目录，归 M2-9-05 修复另案批）。

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

- **IOP-MASK-06**: Follow Edges 边缘感知笔刷——brush 沿图像轮廓单侧跟随涂抹（edge-aware/contour-following），Metal 边缘导向实现；Nitro 独门能力，算法级新需求。**待定（parked）——2026-10-10 用户裁决：V1 熔断 + V2 门 2/8 未达，功能代码删除；重启条件 = 出现可靠开源参考实现（边缘跟随笔刷类）**。〔历程：M2-7-1/2 内核+接线 Delivered → M2-7-3 熔断行使（`.snap` 默认，streamline 挂 V2）→ M4-2-01 V2 换锚（RidgeExtract 六段 + ridge-graph walker + App carrier；合成 golden 九景全绿，真图门 FAIL 0/8）→ M4-2-02 升域 512→1024（真图门 FAIL 2/8 <6/8，预算第一档）→ 三选一上报后用户终裁删除挂待定——V2 代码面全撤（逆 M4-2-01/02），代码回落 M2-7 熔断基线；重启时以参考实现为锚重立项，`phases/m4-2-follow-edges/` 全套（RESEARCH-NOTES/01·02 正本/03-CONTEXT 终裁）保留为重启输入〕
- **IOP-MASK-07**: Depth 深度蒙版——读取图像内嵌深度数据（AVDepthData / ProRAW embedded matte，iPhone 人像类源）作为蒙版源；桌面 RAW 深度源稀缺，依赖数据面非算法面。**（2026-10-01 用户裁决：采纳 Lumen RAW 候选——以 MiDaS 级单目深度模型〔ONNX→CoreML，relative-depth 前景选择〕作桌面 RAW 数据面解法，本项解锁）**。**Delivered 终态（2026-10-11，M4-3 VALIDATION signed——`phases/m4-3-depth/M4-3-VALIDATION.md`，兼 M4 milestone 收口）**：最终形态 = 单目深度模型生成（非内嵌数据读取——桌面 RAW 深度源稀缺的裁决兑现）。链路 = Depth Anything V2 Small Apple 官方 CoreML F16 件直采（Apache-2.0 全链 LICENSE/NOTICE/manifest；HF revision `cfef6f6f2a` 锁定；零转换）→ GitHub Release `ai-models-v1` 分发不入仓（digest SHA-256 `3824a48c…` / 45,759,882 B 三源互证 + 确定性打包两次构建逐字节 + fail-closed：`.digestUnpublished` 拒下载 + 真网下载端到端走查 SHA 逐位）→ M2AI-10 worker 第三推理腿（family 三腿分派 + crash-safe 隔离 + isfinite typed 守卫；AIWorkerProtocol 零 diff）→ 四段 Lumen 同参纯函数管线（percentile 10/95 + 0.48/0.22 窗 + smoothstep；守卫 (b) = NaN backstop 数学事实 + coverageFloor 缝）→ 单「深度」入口四态 UI + `RasterMaskRef.invert` 近/远糖（Phase 6 通道零改动）；golden 三件套（abs-rel 实测 0.0023-0.0036 ≤ 0.01 + 同 units 双跑逐字节 + 语义靶）+ perf forward all 45.0ms / 端到端 231.3ms 落 ANE 带；执行批 `d2e234a..0355e65` 十提交 + 验收批 `57596d3`；双重验收双路 PASS / 0 error；定向终值三 bundle 1748/11/0 双路亲证。挂账 = enhancement 族 resolver 顺延 / guided filter 观察项挂 V2 / o-2 容差口径注记（VALIDATION 挂账总汇编）

### Photo Merging Extensions (v2) — Lumen RAW 借鉴（2026-10-01 用户裁决登记）

来源 = `.work/gsd/research/LUMEN-RAW-NOTES.md`（MIT 项目，只借鉴模式不搬代码）；DNG 导出候选经用户裁决**不采纳**。

- **IOP-HDR-06**: Mertens 曝光融合——无 CRF 估计的快速 HDR 合并第二模式（含多档 deghosting），与已交付 Robertson02（IOP-HDR-01）互为合并选项；输出 32f HDR 进 IOP-HDR-04 管线 —— **✅ Delivered（2026-10-15 M5-2 VALIDATION signed，`phases/m5-2-mertens/M5-2-VALIDATION.md`；双验收双波全 PASS，IOP-HDR-06 三列对账锚 = 七 Mertens 测试文件 47 法；终态 = 定向七 bundle 拼表 `TOTAL 3538/22/0`〔分割重跑，修复后基线 3539/22/0〕；交付面 = MertensFusion 纯函数族〔三因子权重 + 分位映射 + deghost 四态默认 medium + Float64 孪生〕+ `mertensVerdicts` 免 EV 预检零拒绝面 + `hdrMertens` 生产腿流式〔MTB 对齐复用 + band-outer halo 流式 + 共享 union 掩码单通道 + 129 点置换 LUT in-pass〕+ sRGB-tagged 32f 经 M4-1 raster ingest〔两域判别钉〕+ UI 两菜单项并存 + `_mertens` 分账 + provenance `hdr-merge-mertens`；预算 = ru_maxrss 6248MB<8G 门 + 融合核 172.24s@100MP×5 预算内零 GPU 化触发；六门 G1-G5 全绿 + G6 行 2/5 omp 实机回填〔余行挂账 M5-4〕；E-1 生产腿 LUT 兜底缺口随验收批 `358abd8` 单源化修复闭环）**（2026-10-11 M5 立项）
- **IOP-PANO-01**: 全景合成——特征匹配对齐 + 相机参数优化 + 球面投影 + 分块羽化融合，输出 100MP+ 大图入正常编辑管线；v1 合成族（HDR/焦点堆栈/降噪堆栈）之外的新合成模式 —— **✅ Delivered（2026-10-13 M5-3 VALIDATION signed 兼 M5 milestone 收口，`phases/m5-3-pano/M5-3-VALIDATION.md`〔milestone_closeout: M5〕；双验收三波双路全 PASS〔02 波 omp FAIL→fix `60aad61`→OMP-REVERDICT PASS；03 波零实质分歧〕；IOP-PANO-01 三列对账锚 = Pano*Tests 九文件 + PanoMergeKindTests + PanoMergeUITests 合计 90 法；终态 = 全套 `--all` 批准轮 `TOTAL 3631/24/0` exit 0〔收口轮 + zcode 验收复跑双轮互证，对账链 3539+43+44+5 精确〕；交付面 = 自实现特征链〔DoG 多尺度 + 128 维定向描述子 + knn Lowe 0.3 + RANSAC + BFS 连通门，PanoRNG LCG 种子 121 单流确定性，OpenCV 零入仓，Lumen MIT 语义移植注记〕+ 单焦 f + N×R LM BA〔3N+1〕+ 横向 wave correct + 球面投影 + 分块羽化融合〔512 tile 流式 + 恒 inner_crop 直方图栈〕+ FloatTIFFWriter sRGB-tagged 32f → M4-1 raster ingest + 200MP 画布帽 + 2..32 张 + 8G ru_maxrss 机检〔探针 5033-5653MB、全套轮零 MEMFAIL〕+ `_pano` 分账 + provenance details + typed 三态 zh + Session 菜单第三项 + 简形 sheet 零控件；v1 全 CPU 零 `.metal`；G6 行 1 前段/行 4 log 面 omp 实机回填，余行挂账）**（2026-10-11 M5 立项）

### Film Simulation Extensions (v2) — SpektraLab 借鉴（2026-10-02 用户指令吸纳）

来源 = `.work/gsd/research/SPEKTRALAB-NOTES.md`（GPL-3.0 代码只读；CC BY-SA 4.0 资产如引入须独立归属）；参考源码 = `/Volumes/UNITEK/Documents/Development/SpektraLab`（指南 + `rfc/`）。

- **FSIM-01**: 两段式胶片模拟语义——「场景置位（胶片前）→ 胶片记录光 → 配光（测光自动算印相滤色组合 + Yellow/Magenta 手动偏移）→ 相纸呈现」阶段模型，升维现行 M2GRADE 单段 LUT；配光自动求解为其 UX 亮点对齐物 —— **→ M3 主打**（2026-10-08 V2 站立项方案 A：M3-3 实现，前置 M2GRADE-08 = M3-1；research 环 = M3-2）。M3 细化需求草案（**M3-2 research 细化**，转正或修正随 research 定稿）：
  - **FSIM-01a**（草案）：节点图胶片段语义——Develop→Color Grade×N→Display Transform 链上新增胶片阶段（场景置位输入→胶片记录→配光→相纸四子阶段映射），与 M2-4 命令集/history/sidecar schema 兼容
  - **FSIM-01b**（草案）：配光自动求解——软件测光（场景统计）自动求解印相滤色组合（Y/M/C 密度）+ Yellow/Magenta 手动偏移覆盖；确定性门 = 同输入同解
  - **FSIM-01c**（草案）：染料近似域基线——RGB 域胶片响应近似（81 波长光谱引擎架构性不可达声明随 research 落档）；golden 参考基线构造方式 plan 期定
  - **FSIM-01d**（草案）：胶片/相纸资产面——自建配置起步 vs 引入 SpektraLab 28 款实测配置 + 8 放大 LUT（CC BY-SA 4.0，独立归属义务，不与 MIT spectral_film_lut 混用），OQ-V2-10 三态对比 research 裁
  - [x] **Delivered（FSIM-01a，M3-3 三波，2026-10-09）**：阶段承载 = FilmRecord + sidecar v9 + HistoryItem.filmRecord/Hash 折叠（v1 零档字节零漂移负测钉死）+ film sub-run 缝（3×2 降出矩阵六格断言，DRT 数源替换签名零改）+ fused kernel 单 pass（65³ texture3d 印相表）+ filmPlacement 19 行 grade op + Film 面板/只读卡（NodeKind 零新增）。正本 = `phases/m3-3-fsim/M3-3-0{1,2,3}-SUMMARY.md` + §七状态表
  - [x] **Delivered（FSIM-01b，M3-3 三波 + M3-4-01 精确锚收口，2026-10-10）**：配光自动求解 = bake 期中性包求解器（bit-identical 门 + 错误向量判别）→ 运行期 AUTO-core solve cache + FilmStatsSeam + 整数秩 → 确定性门五件（键折叠小端 FNV 精确值 / 跨 ROI 同解重叠字节相等 / 整数秩手算 / 平面 hash 哨兵 14_365_179_805_968_017_957）→ **exact 收口**（t = a∓N 精确落点 + RFC-023 §6.4 四行 8 值公开向量 ±5e-4 三实现独立复算全命中 + F'(K*) 六值逐位 + 排序/交叉拒绝/域守卫门 + Params v2 resolved knees）；Y/M 手动偏移恒在（面板 Y·M 滑杆）。正本 = `phases/m3-4-latitude/M3-4-01-ACCEPTANCE.md` §二/§三 + `M3-4-01-ACCEPTANCE-OMP.md`（FAIL→`d8d72d9`→复验 PASS，双验记录）
  - [x] **Delivered（FSIM-01c，M3-3-03 + M3-4-01，2026-10-09/10）**：染料近似域 golden 主门 = kernel 两级门（同表采样 8.7e-5/钉 1e-4 + 理想连续模型凸性门 + 平面元 6.2e-3）+ bake 体素 ≤1e-5 + 中性闭合 1.4e-3（M3-4-01 精确锚重钉 12→16 法）；**81 波长光谱引擎架构性不可达声明落档**（M3-2 RESEARCH §2 + AGENTS「M3-3 架构增量」注记节）
  - [x] **Delivered（FSIM-01d，M3-3-01，2026-10-08）**：资产三态裁决 = c 混合（OQ-V2-10）——CC BY-SA 五件套 29 文件字节原样（MANIFEST 30 行全量对账测试 + LICENSE = 上游 SPEKTRAFILM_LICENSE.txt 逐字节 + 仓根 NOTICE 署名；M3-3-03 验收 shasum 30/30 复核；与 MIT spectral_film_lut 分账零混用）
- **FSIM-02**: 宽容度面板——场景直方图 + 胶片容纳范围双虚线 + 低于/内/高于占比读数；「场景置位与显影后曝光严格分离」「EDR 不可找回输入端已丢高光」的交互教导对齐 —— **→ M3-W3 尾（M3-4，随 FSIM-01）**（2026-10-08 V2 站立项方案 A）
  - [x] **Delivered（FSIM-02，M3-4-01 + M3-4-02 VALIDATION，2026-10-10）**：宽容度面板 = EV 直方图原生轴窗 + 胶片容纳范围双黄虚线 + 低于/容纳/高于占比（整 bin 分类 ≤1 bin 容差）+ 教导两条 zh verbatim（「场景置位作用于胶片模拟之前，显影曝光作用于其后——两者不可互替。」「EDR 位于输出侧，无法找回输入端已损失的高光。」）+ 置位编辑面（动态最小值滑杆 / typed 拒绝红行点名+真相回弹 / Fit / 三 readouts 端点斜率发布值逐位）+ descriptor 运行时（真链 probe + scan seam + ISO 6846 E1 判据）。验收 = **双验收**（zcode PASS/0E+3obs + omp FAIL→`d8d72d9`→**OMP-REVERIFY: PASS**）+ 实机证据链十项（`.work/gui-acceptance/m3-4/` MANIFEST：占比三读数 verbatim「低于 5%/容纳 95%/高于 0%」+ typed 拒绝红行实机）。M3 终验 `TOTAL|3174/16/0|1470s`（`phases/m3-4-latitude/M3-4-02-VALIDATION.md`；milestone closure 带回溯验收门注记——OMP-RETRO-QUEUE 16 项全 PASS 方翻正）
- **FSIM-03**: 印相域影调蒙版阶段归属研究注记——影调蒙版属负片后、相纸前印放阶段，与场景置位/调整层蒙版非同一功能 —— **→ M3-2 research 并入**（2026-10-08 V2 站立项；研究注记不独立立项）

### Alcedo Upstream Parity Extensions (v2) — 2026-10-07 上游增量裁决（用户「按推荐走」）

来源 = `.work/gsd/research/ALCEDO-FEATURE-MAP.md`「上游增量测绘」节（34241d0→f1fae5d，188 commits，v0.3.1+）。

- **RASTER-IN-01**: 非 RAW 栅格开发链——JPEG/PNG/TIFF/OpenEXR 导入即开发：源 color description（ICC）解析 + HDR 旗标 → display-referred 输入经 DRT 逆链（ACES 2.0 逆变换路径）进编辑管线；含 OpenEXR（与 ALCE-02 OpenEXR 导出对偶）；文件夹导入文件类型选择器对齐上游 #264 形态 —— **→ M4**（2026-10-08 V2 站立项：方案 B 滚存 M4 主打，不入 M3）。**M4 立项 + 范围收窄 = TIFF only（用户 2026-10-08 裁决），EXR/JPEG/PNG 移出**——TIFF 读写经 ImageIO 原生 + 内嵌 ICC → ACES 工作流 + HDR TIFF；JPEG/PNG 维持图库可浏览现状不进开发链；EXR 连同 ALCE-02 推迟（依赖对比存档 V2-PROPOSAL OQ-V2-5）。charter 正本 = ROADMAP §Milestone 4（M4-1）
  - [x] **Delivered（M4-1 收窄版终态，M4-1-01/02 双 plan + M4-1-VALIDATION signed 2026-10-10）**：TIFF 开发链全链交付——①描述解析 = `RasterColorDescription` 解析序 ①ICC→①′linear-ICC-float32→sceneLinear（checker E1 半边）→②no-ICC-float32→③sRGB + usable 三检查 + IFD tag-34675 直读（平台事实：ImageIO 合成 colorspace 面失真）+ canonicalization 阶梯（PQ/HLG 2e-4 / sRGB·纯γ 1e-4）②21 fixture 幂等矩阵（`Tests/Fixtures/TiffRaster/`，生成器双跑同 shasum）③逆变换 = aces-core `outputTransform_inv` Float64 移植 + Metal kernel 镜像（上游 SHA `069b0bc3` 逐行对表；fwd-first display 恒等 4.4e-15；RGC 逆不移植 + raster RGC 恒关 render-side 政策）④decode() UTI 分流翻转（RAW→TIFF→raster；decodeRaster 退役保留 + 快照钉；JPEG/PNG/HEIC 零回退机检锚）+ PixelPipe `rasterColor` 分派 + windowedPayload（top-first + LE）⑤raster 默认 DRT record（Alcedo D2 同形 seed carrier-only + mint skip + `srgbPiecewise` additive EOTF kernelIndex 7 = Alcedo hpp:46 逐字）⑥HDR TIFF EDR（旗标 = PQ/HLG TRC ∨ float 探针 >1.0 → 16F + EDR + itur_2100 视口臂，零新渲染代码）⑦导入面 = ImportCategory 掩码（`library.import.categories`，与 rawExtensions 正交）+ 类型选择器 + excludedType 分账 + 三模式零特例。**SC 三列全 Delivered**（round-trip 真队列 / ICC golden + IOP·IOPParity 逐位 / HDR 视口五法）；终验 `TOTAL|3335/16/0|1604s`（对账链 3174+102+59）；双重验收 4 路 PASS / 0 error；正本 = `phases/m4-1-tiff-raster/M4-1-VALIDATION.md`；挂账六项随 VALIDATION 移交（深影中性化 / HDR LUT 臂面 / CMYK·16-bit gray UX / 16-bit gray 补腿 / RGC 恒关晨审可翻 / omp-minor-1 修复批）
- **M2GRADE-08**: LUT 作者编码建模——LUT input/output encoding（面板选择器 + 编码随 LMT 生效 + 库内逐 LUT 记忆 + 传递曲线/色域目录，对齐上游 c740f7b 形态）；解决「胶片 LUT 作于 log 域而我方按 working space 直套」的系统性偏差（V2 段，可插队 M2 后期 UI 打磨轮）—— **→ M3-W1 前置**（2026-10-08 V2 立项裁决；「插队 M2 后期」窗口随 M2 收官兑现，FSIM-01 软前置基建）
  - [x] **Delivered（M3-1-01，2026-10-08）**：编码目录 17 条表驱动（scene 11 = camera log 10 + linear working 1 + display 6，KD-1）+ 传递曲线 Float64 正逆函数族（`LutEncodingCatalog` / `LutTransferMath`，公开标准公式，golden = 各标准公开参考值；gamut 矩阵 Bradford 自算非手抄）+ Params additive 编码对（nil = working 直通逐字节保现状，旧档 paramsHash 零漂移专测）+ 宿主侧复合表重烘焙（零新 kernel，Alcedo `Compose` :273 同构方向，LRU 16 + bakeCount 可观测 + stateLock）+ 库内逐 LUT 记忆三层序 + 内置 40 张 seeder 补标 {arri_logc4_awg4, rec709_bt1886}（adoption 路径盖章）+ 面板双 Picker（scene/display 分组 + 记住 Toggle）。**交付注记：新选内置 LUT 的观感变化 = 偏差修正非回归**（补标前 = log 表按线性直套的系统性偏差本体；既有文档按三层序停在旧渲染）。**FSIM-01 软前置交付物 = 目录 + 曲线族即 M3-3 消费面**。测试新增 37（IOPP 31 + LIB 6 + APP 5，口径 = Lut3dEncodingTests.swift 两类 24 + FullChain 2 + LIB 6 + APP 5）+ 既有 LUT 族零 diff 全绿（IOP 471/1/0 逐位基线）。
- **EXPORT-PRESET-01**: 导出面板命名预设层——格式/质量/位深/sizing/元数据策略/ICC/命名模板整组存具名预设 + Export 页一键套用 + 内置默认与用户预设管理（对齐上游 `7052355` 全选项预设形态；EXIF/ICC/GPS 勾选随预设走）。我方逐项记忆键族（`export.*Quality`/`export.namingTemplates`/`export.lastDirectory`）为数据基座，只加预设层不撞键族 —— **→ V2 站裁量（M7+ 导出打磨批；2026-10-13 夜间维护批登记，评估正本 = `.work/gsd/research/ALCEDO-PARITY-2026-10.md`）**
- **注记（非需求，2026-10-13 夜间维护批续；**〔2026-10-16 M7 charter 批更新：其中「agent GUI turn-taking 明确不立项」一句被用户 M7 裁决②**反转**——块二 turn-taking 正式立项 = TURN 族 → M7-5，Alcedo AU14 语义移植，与 M6-1 已交付单写者锁面合并（底座复用非等待项）；本注记其余内容（CLI/MCP 同构追认、MCP-09-B versions 面、IopCatalog extend-additively）维持有效，块三独立 CLI 维持不立项并升级为显式挂账（触发条件 = 外部用户诉求 ∨ MCP launcher 实战受限）〕**：上游 v0.3.2+主干自动化面（CLI/MCP/共享会话，142 commits `9ce6a24..7052355`）整体 = 我方 Phase 14 + M6-1 已交付能力的同构追认——缺口仅 MCP versions 面（已挂 MCP-09-B，上游 `cd3b4e4` 验证需求 + `from_commit` 先验拒绝细节兑现时取用）与 IopCatalog 覆盖面（既有 extend-additively 纪律内）；agent GUI turn-taking 明确不立项（MCP 编排皮路线维持）。逐项判定与质量参考清单见评估正本。
- **注记（非需求，2026-10-07 首批）**：OCIO ACES 2.0 reference forward transform（上游 `8f8e712`）= M2-6 aces-core 移植的交叉验证测试资产机会，规划 parity 测试时取用；图库编辑时间分组（#276）/后台任务岛（#275）= UI parity 参照，不立项。

### M6 Interop & Library Hardening (M6INT) — LightCraft 六裁决点（2026-10-16 M6 立项批登记）

来源 = `.work/gsd/research/LIGHTCRAFT-NOTES.md` §六（用户回批 2026-10-11 全按推荐采纳）；家族正本 = ROADMAP §Milestone 6。许可面 = LightCraft **MIT OR Apache-2.0 双许可**——代码级移植合法（与 darktable GPL-3.0「只读参考不复制」红线不同级），成段移植仍须 NOTICE 归属同 commit 登记。MCP-09-A 与 ALCE-03 两件为原位注记（见 MCP-09 / ALCE-03 行），不重复立 ID。

- **M6INT-01**: per-photo process version——`.lra` additive 可选 `process` 键：改观感的 iop 语义变更必须开新 process 号 + 旧号冻结（老照片渲染零漂移直至显式迁移）+ legacy 缺键不序列化语义（HistoryHash/缓存键逐字节不变，LightCraft hash64 技巧同构）—— **→ M6-2**（2026-10-16；设计前瞻 = `phases/m6-1-interop/RESEARCH-NOTES.md` process version 节）
  - **兑现注记（2026-10-16 M6-2-01 执行批；2026-10-14 验收闭环批翻 validated）**：**Delivered（VALIDATION signed——`phases/m6-2-process-version/M6-2-VALIDATION.md`，晨审可推翻）**——sidecar v10 `process` 键（nil⇔ABSENT⇔legacy，lenient decode 双门）+ `RenderProcess` 账本/bump 纪律三层 + 管线读缝 armed 零行为 + 出生点五面 + golden 四门（G1 byte-face/G2 冻结/G3 零行为/G4 mint+传输）；全套终验 **3725/24/0** = 基线 3689+36 精确；验收 = 双路独立验收 PASS / 0 error + 0 minor open（第一路 zcode 0E+1minor 已修 `dec16b1f` + 第二路 zcode 第三独立眼 0E+0minor `f75c52fa`；omp 制度路 E3 配额阻塞由第三独立眼替代，偏离登记 VALIDATION 特殊事项 §2）；挂账三项 = VALIDATION 挂账总汇编（接线件 + 迁移 UX 至首个真实 bump 批等）
- **M6INT-02**: 图库 stacks + auto-stack——`.lalb` 手动堆叠（封面/展开/收起 + 网格堆叠徽章）+ 拍摄时间间隔聚类自动堆叠（burst/bracket）；schema 迁移 plan 期定 —— **→ M6-4**（2026-10-16；裁决⑤：smart albums 次之、挑片视图/watched folders 挂账不立项）
  - **兑现注记（2026-10-14/15 M6-4-01 执行批；2026-10-16 验收闭环批翻 validated）**：**Delivered（VALIDATION signed——`phases/m6-4-gallery-stacks/M6-4-VALIDATION.md`，晨审可推翻）**——schema v5 两新表（`stacks` + `stack_content` WITHOUT ROWID + UNIQUE 一图一栈 DB 级不变量；封面 = position 0 单真相；additive 幂等迁移 + 快照轮换）+ CRUD 全 op 族单事务 + auto-stack LightCraft 全套语义（gap 60s 缺省可调 + preview 零写 + runs≥2 + 双 skip + per-cluster re-check + 空池守卫）+ 分页×堆叠（收起态 flag-aware JOIN 谓词 keyset 零扰动 + `.flat` 字节恒等 + 展开态 forward-only fixup union golden）+ 导入缝 merge→stack 四步匹配（ESCAPE 三转义钉死 + 零半栈）+ Grid 徽章/contextMenu/AutoStackDialog/View 菜单 UI；双路独立验收 PASS / 0 error + 0 minor open（3815/24/0 两路亲跑同值；登记 minor 五处修批 `984e0256` 清偿——Library 729/4/0）；挂账 = 栈顶顶替/计数口径 V2 候选（VALIDATION 挂账 #1）
- **M6INT-03**: AI 分割蒙版原生 spike——对照 Phase 7 AI-01 已交付面（`VNGenerateForegroundInstanceMaskRequest` + tap/scribble/lasso 精修）审计 LightCraft SAM 3 能力集缺口（点击 Object 精修 / Describe 文本选择 / 延迟高分辨率 patch 精修 / Edge 羽化）；原生零模型成本路先试（Vision + M2-10 CLIP 基建），不达标再裁 SAM CoreML（大件，OQ 另裁）—— **→ M6-4 spike**（2026-10-16；裁决④「达标即收」）
  - **兑现注记（2026-10-14/15 M6-4-02 执行批；2026-10-16 验收闭环批翻 validated）**：**Delivered（VALIDATION signed——`phases/m6-4-gallery-stacks/M6-4-VALIDATION.md`，晨审可推翻；spike 五行判定 = 机检轨达标即收）**——hi-res patch 组装（Planner 三 skip 门 + Composer ramp/≤4 帽 + 0.6×/≤1px 双数值门 + `segmentPatch` 单委托 + commit 缝 1s debounce，零新 kernel）+ Edge 羽化 ±100 参数化（正腿 GPU 缝复用 + **负腿 logit-gain 换锚**〔D-01：草案式线性恒等证伪，LightCraft `masks.rs` 原文条款，双路独立数学 ACCEPT〕+ 双羽化防三臂）+ 人物实例入口（`.person` 源族 + 标签合成提取腿 CVReadOnlyPixelBuffer + AIInstanceCatalog 零新类型 + typed noSubject）+ scribble 缝保持不激活（OQ-6）+ livePlane 切层/切图身份比对释放（D-13）；**Describe 文本选择 = 原生不可达收口**（Vision swiftinterface 全扫零文本分割 API，两路独立复核；SAM CoreML 大件挂 V2——charter 裁决⑦，用户裁立项另开独立 phase）；双路独立验收 PASS / 0 error + 0 minor open（3841/24/0 两路亲跑同值；升格建议修批 `b49215bb` 实修——App 816/4/0 负验证）；GUI 轨 M-1..M-4 挂 Manual-Only（VALIDATION 挂账 #2/#3），`gui-acceptance/m6-4/MANIFEST.md` local-only
- [x] **M6INT-04**: ALCEDO-FEATURE-MAP 升维 ID 化 parity 清单 + CI 对账门（清单引用 id 必须存在 + id 唯一性 + 状态词表机检，`zh-audit --check` 同型）**Delivered**（M6-6：`docs/parity-checklist.md` 134 rows / 12 域 / 六状态词表 + `Scripts/parity-audit.py` 六断言门〔A1-A6 + `--tree-root` 公开树注入缝，`--check` exit 0 uv/裸 python3 双形态〕+ ci.yml `parity` job；首轮 gaps 17 行 ≥10 一次性 AC 过；commit `93a674c8`/`a515b3ff`/`3c7498bc`，验收 `phases/m6-6-feature-parity/M6-6-VALIDATION.md`）〔2026-10-16；裁决⑥；「M6 第一个 plan」编排偏差已按收口段正式登记 = VALIDATION §四.1，互操作先行编排，晨审/用户可随时追认或推翻〕

### M7 Shell Special Project (SHELL) — D-6 defect special project（2026-10-16 M7 立项批登记）

来源 = `phases/fix2-defects/FIX2-VALIDATION.md` §挂账①④⑤⑥（双路同判三选一之①「接受降级 + gate=false 壳减树/窗口内容拆分专项」，用户 2026-10-16 裁决①生效）；定性正本 = `phases/fix2-defects/FIX2-01-DECISIONS.md` D-FIX2-1（H2 = macOS 27 SwiftUI 菜单/焦点更新机制在特定树形〔重树 + `.inspector` 分栏宿主 + 三段内容〕下不收敛——功能态-with-churn，框架共犯无 app 写点）；证据族 = `gui-acceptance/v2m/fix2-probe/`（t1-*/acc*-*/B/C/E 系，local-only）；workaround 已落 README「Known issues」。家族正本 = ROADMAP §Milestone 7（M7-1）。**家族终局（2026-10-16 M7-1 定罪批 VALIDATION signed，正本 = `phases/m7-1-shell/M7-1-VALIDATION.md`）：FIX2 全部饿死证据证据级 dissolved（十轮 transcript 全落遮挡/发射静默窗伪象；E 系从未进编辑器面），终局行为模型 = 可见性门控开关 × 振幅随面重（遮 0% / 置前 ≤1s 点火无需点击 / 显期间自持；图库 ~30% / 编辑器 80-100% / legacy 0.1%）；缓解 = upstream-only 为主；workaround 语义勘正 = 置前即恢复 ≤1s 无需点击（替换「一次点击」测量伪象表述）**。

- **SHELL-01**: gate=false 壳减树——`.inspector` 分栏宿主拆解 + safeAreaInset 横幅族入子窗/覆盖层；feature-flag 门控（gate=false = 减树形态默认开，可回切对照验证判别力）—— **→ M7-1**（2026-10-16）→ **M7-1 终态：不行使 parked（价值证伪——减树饿死论 dissolved：C1/C2/E 形三独立复现减树形均活 28-36%；执行批 `shell.reducedTree` flag 全套撤回即终态，零代码）**（2026-10-16 M7-1 定罪批）
- **SHELL-02**: 编辑器面独立 NSWindow 路线评估——评估报告先行（与减树交互 / 多窗 state 播撒 / MTKView 迁移成本三面），落地与否 research 环裁决；FIX2 裁定「research 复审并入专项首步」在此兑现 —— **→ M7-1**（2026-10-16）→ **M7-1 终态：挂条件账（触发 = E 系硬化复测复活——半日级必做前置：同 C1 复涂法逐段摘 filmstrip/viewport/rightPane + probe 项目 + AX 腿 + frontmost + reveal 后 60s 观测 + 样本总量 + transcript `phase=editor` 机检断言；判读：任一形 reveal 后 0% 持续 ≥60s = 树形杠杆复活 → 窗拆重评〔scratch + 编辑器窗 CPU 硬门 <10% + RESEARCH §3 多窗生命周期走查，量级 L〕；全部 ≥80% = 窗拆饿死性终证死亡，只剩 IA 偏好收益〔偏离 Alcedo 单窗对标〕不入）**（2026-10-16 M7-1 定罪批）
- **SHELL-03**: 菜单环燃料面减频——`visibleMenuCommands` 门内 menu 重建频度收窄 + `prependValue` 无去重组合修整；仅减燃料不承诺根治（H2 框架共犯定性）—— **→ M7-1**（2026-10-16）→ **M7-1 终态：不行使 parked（价值论证依赖已证伪 threshold 理论 + FIX2 B1/B2 焦点写点全摘不饿死先例——纯风险面，零代码）**（2026-10-16 M7-1 定罪批）
- **SHELL-04**: 上游通道——Apple Feedback 提交（报告稿 = `research/APPLE-FB-D6-DRAFT.md`，环签名 sample `t1-menu-loop-sample.txt` / `acc2-d6-editor-sample*.txt` 可附；**提交动作用户手动**——Nitro LUT 先例）+ macOS 27.1 release notes 监测 + 系统更新验证；闭环判据 = FB 案号登记 + 监测节律入 GOAL-STATE 巡检 —— **→ M7-1**（2026-10-16；稿本批已备，提交/监测为持续性义务）→ **M7-1 终态：in-flight（唯一主路径）——FB 稿补强三点已落（遮挡门控确定性复现〔遮 0% ↔ 置前 ≤1s 复燃无需点击，两形三面〕/ C1+C2 三独立复现树形证伪 / 跨日稳定编辑器 spin 配方 78.7-100% 三路在案 + repro 脚本可提供）；提交动作 = 用户手动，**FB 案号待回填槽 = 本行**；macOS 27.1 release notes 监测关键字（menu/updateMainMenu/property graph/invalidation）入巡检；E 系证据无效一事不入 FB（内部分卷）**（2026-10-16 M7-1 定罪批）
- **SHELL-05**: 走查专项卷 + 复测波——双路七条观察（第一路三条：churn 可见性门控 / legacy 开菜单态点火 / 菜单环燃料面 + 第二路四条：遮挡断环不复燃 / 点击恢复 / 输入路径分歧 / 菜单点火适用域）+ H2 精确定性措辞 + 五读数全帧行集 + 点击表型 AXPress/cliclick 双通道对照〔FIX2 挂账④〕+ 探针缝 `exit(0)` 兜底〔挂账⑤〕+ **导入零行间歇〔grid 刷新迟到族〕专项修后复测再裁**〔挂账⑥〕+ 波 1 屏面四项（V2M-T1-02/D3-01/D4-01/D5-01）+ m6-closeout Blocked-Channel 余行复走〔V2M-VALIDATION 挂账②硬义务〕—— **→ M7-1**（2026-10-16；复验门判据 = FIX2 判别探针族：~60k 重估 / 菜单环符号 / CPU 硬门三判据）→ **M7-1 终态：改挂「功能态常驻」走查批（D-6 缓解 = workaround 常态化〔遮挡/⌘H〕后行集以 churn 在场判读口径复走——原「修后复走」转绿判读前提消灭；FIX2 挂账④⑤随该批；挂账⑥降级待研〔三轮全净 churn 在场态零再现 = 因果假说反向旁证〕随该批顺带复测）**（2026-10-16 M7-1 定罪批）

### M7 MCP Tool Surface Additions (MCP2) — Alcedo CLI+AI 块一四波（2026-10-16 M7 立项批登记）

来源 = `research/ALCEDO-CLI-AI-SURVEY.md` §5 块一（O1-O4 四波切分，用户裁决②「三块全要，块三缓」生效）；形态 = MCP 工具 **additive**——20 工具封闭集快照族显式改（D-14-CONTEXT-3 机制内），每波 tools/list 快照同批更新；全部复用自有单源（FilterSQL / SemanticEngine / adjustment_transfer_service / ExportRenderer / LutLibraryStore），Alcedo GPL 零复制（survey §6：命令语义克隆合法，MCP snake_case 与 Alcedo 点分 JSON-RPC 天然异构）。家族正本 = ROADMAP §Milestone 7（M7-2..M7-4）。

- **MCP2-01**: MCP `search_photos` 检索工具（O1）——EXIF/全文/CLIP 语义三路由对齐 GUI 三段搜索（复用 FilterSQL/SemanticEngine/AIDescriptionService 单源；2026-10-16 勘误：原文「LabelQueries」系笔误——LabelQueries 是导入期自动打标的查询目录，非搜索路由，标签可检索性由 CLIP 腿 + 全文腿〔AI tags 进 FTS〕承载）；agent 最大单点缺口（现状 = `list_photos` 逐页扫，无检索动词；Alcedo `search.query` 对表）—— **✅ Delivered（M7-2-01，2026-10-16：commit `5a89f07f` 三路由 + `32055308` parity golden 三臂全绿；mode 三枚举默认 exif / EXIF 两段 keyset cursor〔segment 字段〕+ 窄投影九字段 / CLIP 帽 256 全文帽 500 / `modelUnavailable` additive 15→16）**
- **MCP2-02**: MCP `get_history` 编辑历史只读工具（O1）——编辑序列自查面，含 note/author 读面（author = v1 前向占位恒 null，M7-4 MCP2-09 落地后填充；与 MCP2-09 归属缝配套；Alcedo `editor.history` 对表）—— **✅ Delivered（M7-2-01，2026-10-16：commit `028c6230` 双地址制投影 + 五臂 kind 判别 + versions meta + F-5 截断保留最新端；golden byte-equal）**
- **MCP2-03**: MCP `get_state` 统一状态快照工具（O1）——project/workspace/editor 状态 + control 状态 + 运行中任务一行快照（Alcedo `state.get` 语义同构；tasks 面 = M2 导出队列计数，merge/pano/AI-worker 不入 v1）—— **✅ Delivered（M7-2-01，2026-10-16：commit `028c6230` 六字段组一次性快照 + MainActor hop 机检双判据；无头臂 typed nulls 契约）**
- **MCP2-04**: `render_preview` 反馈回路扩展（O2）——`compare:"root"`（原图对比出图）+ `region`（ROI）参数，agent 自评调色的 before/after 闭环（Alcedo `render.preview` 语义对表；survey gap #18 判「高价值」）—— **✅ Delivered（M7-3-01，2026-10-17：region 归一化 0..1 round+clamp + compare enum none|root 默认 root 双臂〔30s 单窗/不共享 decode/无自动降档〕；`renderedPlane` additive 默认参 `pristineOnly` = Core 唯一新触点；golden = T5 四法；执行链 `cf49c046`+`3ef68910`+`286530d2`）**
- **MCP2-05**: MCP `list_luts` 工具（O2 小件）——LUT 库清单读面（库面已有 M2-5，工具壳薄；Alcedo `lut.list` 对表）—— **✅ Delivered（M7-3-01，2026-10-17：editing 域 6→7；readOnlyHint + McpTimeouts.list；key = lutName 新写入寻址键句入 description；seeded 内容正断言 golden；`3ef68910`+`286530d2`）**
- **MCP2-06**: MCP `project_open`/`project_create` 工具（O3）——agent 全流程第一步（Alcedo `project.open/create` 对表；与 M6-1 项目单写者锁面交互 plan 期定）—— **✅ Delivered（M7-3-01，2026-10-17：第四域 ProjectToolset；requiresWriter:true + 错误码零新增；双宿主同源路由 = 无头 Core 直开〔current-project 盒〕/ GUI controller hop〔held 预检 + 差分谓词〕；锁仲裁 fixture 17 法；`bb6026f1`+`286530d2`）**
- **MCP2-07**: MCP `list_versions` 版本只读工具（O3）——M2-8 版本面只读投影（变更类命令视单写者余量二期；Alcedo `versions.list` 对表）—— **✅ Delivered（M7-3-01，2026-10-17：sidecar readDocument 单源、version-reference 投影零消费；includeItems 复用 historyKind/historyItemCap 500 保新端逐版本；双地址制经共享寻址 helper；golden = byte-equal 三版本投影 + ACTIVE 链 ≡ get_history；`bb6026f1`+`286530d2`）**
- **MCP2-08**: MCP `copy_adjustments`/`paste_adjustments` 跨图批量（O4）——agent 批量统一调色核心动词（复用 M2-8 adjustment transfer service + isAdjustmentTransferable 排除面单源；若走后台任务补 `list_tasks`/`wait_task`——Alcedo tasks.wait 语义此时一并引入；Alcedo `adjustments.copy/paste` 对表）—— **✅ Delivered（M7-4-01，2026-10-17：无状态双动词〔无剪贴板/tasks 面 → UPSTREAM-QUEUE〕；AdjustmentTransferCatalog 单源抽取 GUI/MCP 双消费；copy readOnly 枚举预览双形态寻址〔resolveReference verbatim〕；paste 批量 overwrite + per-target 分账〔固定 reason token 集〕+ live 硬拒 + targets 1..1000 重复拒 + mask 纪元重置 + flush 写达后方返；`a78ea631`+`503f1ffc`）**
- **MCP2-09**: 写工具 `note` 字段 + commit attribution 第一步（O4 附带）——apply_params/paste 类工具加 `note` 参数 + 编辑历史记 agent 身份（M2-8 版本/历史面板已有人读面，缺 agent 身份标注缝；Alcedo `editor.set note` + history author 对表）—— **✅ Delivered（M7-4-01，2026-10-17：HistoryItem additive note/author + SidecarHistoryItemRecord 镜像全链 + schemaVersion 10→11〔SidecarV11Tests 五法 + V10 :327 法语义退化申报〕+ HistoryHash 零折负测钉死 + author="mcp" 盖章〔GUI 写腿恒 nil 零 diff〕+ get_history per-item 两键 + 顶层 author position 真位翻转〔红尾腿〕+ EditorToolRailView note 副标题/author 徽章；`a78ea631`+`503f1ffc`）**

### M7 GUI Agent Turn-Taking (TURN) — Alcedo AU14 块二（2026-10-16 M7 立项批登记）

来源 = `research/ALCEDO-CLI-AI-SURVEY.md` §5 块二（用户裁决②生效；survey 拟「与 M2-9-A 合并立项」——**MCP-09-A 已由 M6-1 兑现**〔Core `SingleWriterLock` 五态 + `.lalb.lock` + GUI 三选对话框/只读面/guard 家族 + connect 指引〕，合并不再是等待项而是底座复用，本批勘误登记）。家族正本 = ROADMAP §Milestone 7（M7-5）。

- **TURN-01**: control acquire/release/get 工具面——agent 持锁期间 GUI 禁编辑保留浏览（编辑面板/命令面只读化；Alcedo `-32003 control_not_held` / `-32004 control_revoked_by_user` 错误语义同构）—— **→ M7-5**（2026-10-16）—— **✅ Delivered（M7-5-01 T1/T2：`599601d7`+`89d8bbff`——ControlToolset 第五域三工具 + requiresControl 第三道门 13 工具集 + 错误码 16→19 + AgentControlCoordinator 单写点 + 禁编辑 11 实落点 + get_state control.agent；验收形态①判定见 M7-5-01-SUMMARY）**
- **TURN-02**: agent 活动 GUI 可见性——活动卡/task island 对应面（「Agent · <holder> · <命令>」形；落点 = Toast/任务面 + MCP server 面板扩展；Alcedo task island + Cancel = Take control 对表）—— **→ M7-5**（2026-10-16）—— **✅ Delivered（M7-5-01 T3：`4755941d`——BackgroundTaskBar agent 行 + AgentTaskHandle pinned + Stop 卡单入口；实机走查配方 = `.work/gui-acceptance/m7-5/MANIFEST.md`，归验收批）**
- **TURN-03**: Stop 语义 + 恢复——Stop = Take control + agent 任务钉住 + 逐命令 activity 记录 + Stop 后同 agent re-acquire 可恢复任务（Alcedo AU14 `7e0c9cb` 迭代对表）—— **→ M7-5**（2026-10-16）—— **✅ Delivered（M7-5-01 T2/T3：coordinator stop/resume 状态机 + activity 边界闭形 + F8 registry.cancel 绕行负测；验收形态③判定见 M7-5-01-SUMMARY）**
- **TURN-04**: 无头宿主 turn-taking 简化臂——headless/stdio 形态 agent 恒持有（Alcedo null owner → `held: true` 同构）；GUI 选区类工具 headless `not_ready` 语义对表 —— **→ M7-5**（2026-10-16；可与 TURN-01 同 plan）—— **✅ Delivered（M7-5-01 T4：`dea46168`——makeHeadlessControlContext 恒真面 + 七生产调用点 + read-only 宿主照常注册；GUI 选区类工具我方不存在 = 零新码申报；验收形态④判定见 M7-5-01-SUMMARY）**

### M7 Agent Skills Documentation (SKILLS)（2026-10-16 M7 立项批登记）

- **SKILLS-01**: agent 操作 skill 文档仓——对齐 alcedo-skills 形态（会话启动/stdio 配置模板/工具语义边界/错误码表/render_preview 预览语义〔编辑态无印框〕/UI 单位说明；reference 可从 tools/list 快照机检生成，对齐上游 generate_cli_reference.py 思路）；**零 taste 搬运**（Alcedo 同款排除——其文档文案 GPL 禁译禁改，全部自写；taste 留 launcher `{{PROMPT}}` 模板载体）—— **→ M7-6**（2026-10-16）—— **✅ Delivered（M7-6-01 T4：`4259cfd8`——仓内 `skills/lightamer-mcp/`〔OQ-M7-6-1 仓内形态〕SKILL.md 七节 en 单语〔OQ-M7-6-2〕+ references/errors.md 19 码表 + references/tools.md 机检生成〔SkillsReferenceTests 测试即门 OQ-M7-6-3：活注册表渲染逐字节 + 19 码名断言；union 文件持权 internal 一行〕+ README 一句链接 + N2-2 文档句收口；偏差 = tools.md description 列省略〔zh 活文案 vs en 单语门结构冲突裁定——DECISIONS §8，晨审可翻〕）**

### Upstream Queue Intake (UQ) — 2026-10-16 M7 charter 批四候选入队（正本 = `research/UPSTREAM-QUEUE.md`）

> 2026-10-16 M7 立项批：UPSTREAM-QUEUE 四候选全部入队立 ID（用户裁决③）；入队后候选区原位标注指向本族。UQ-L2 挂面不入波（软打样未立项）。

- **UQ-A1**: DRT-SDR 预览层 ICC 双曲线失配——预览层 colorspace 改挂导出同款 ICC v4 字节（`CGColorSpace(iccProfileData:)`，L053 自建字节直接复用）+ ColorSync 解码等值测试（上游 Alcedo `36db9a8` 同病同修——preview/文件双曲线解码失配）—— **→ M7-6**（2026-10-16；渲染相关波分插）—— **✅ Delivered（M7-6-01 T2：`32b592aa`——drtLayerColorSpace SDR 幂臂两段式〔OQ-M7-6-4：legal 8 对 = 导出同款缓存 ICC v4 实例 / 域外对 calibrated 回落，禁扩导出表〕+ EditorPreviewColorSpaceTests 3 法〔legal 8 对 === 同实例 + ICC bytes 逐字节同 + srgbPiecewise 真分段行为腿〔CGColor converted 真变换判别 2.2 幂〕+ 域外回落负腿〕+ M4-1-01 KD-8 显示侧偏离消解收口；HDR/linear 臂零 diff 亲证）**
- **UQ-A2**: 导出 FAIL 档终写原子不覆盖——tmp 编码 + `link()` EEXIST 拒晋升 + unlink tmp（ExportCollisionPolicy 快照-落盘 TOCTOU 语义补全；上游 Alcedo `6203791` 同纪律——renameatx_np/renameat2 的 Swift `link()` 排他等价）—— **✅ Delivered（M7-4-01，2026-10-17：encodeStage additive `exclusiveFinalWrite` + 同目录隐藏 tmp + link() EEXIST → BaseNameOccupiedError 复用〔错误表零新增〕+ encoder-error 清理腿改道〔exclusive 臂 destination 不可触〕+ `$jobNamingCarrier` encode 腿递缝〔leg 签名零 diff〕+ **render 步快照检查保留**〔与上游唯一分歧——成本门，DECISIONS 申报〕+ exFAT 类卷 EOPNOTSUPP → encodeFailed 兜底〔行为变化申报，降级可选项挂 UPSTREAM-QUEUE〕；五腿实测；`2af9b17d`）**
- **UQ-L1**: 滑杆双击重置 + 值横扫 scrub——SwiftUI Slider 无原生支持需自实现（yiyin 面板与 iop 面板通用 UX 小件；上游 LightCraft `cb8b797c`/`ab64e9a5`，MIT/Apache-2.0）—— **→ M7-6**（2026-10-16；UI 小件分插）—— **✅ Delivered（M7-6-01 T3：`bac0ff76`——LightamerSlider readout scrub〔OQ-M7-6-5 单组件：DragGesture ≥3pt + LightamerSliderScrubSession 纯函数 + Shift 1/10 速 + range clamp；D-H1 三回调复用零旁路 = 一次 scrub 一次连续 commit〕+ 3 机检法 + xcstrings 恰 +1 键；范围勘注（review R1 计数勘正）：LightamerSlider 全部调用点 177 处全量受益 = iop + yiyin 面板族〔yiyin 八处 `:160/:182/:203/:235/:268/:380/:393/:589` 实测在册——RESEARCH §3.1「yiyin 零命中」为 grep 假阴性，review M2 翻转〕；双击重置已在位〔03-02 交付〕不顺手改 Monochrome 自有 row；track 双击 wrinkle 登记不动〔OQ-M7-6-6〕；拖离取消语义让渡申报〔DECISIONS §7——MANIFEST A3 观察行〕；走查配方 = `.work/gui-acceptance/m7-6/MANIFEST.md` 归验收批〔SC 措辞降格登记 = M7-VALIDATION §5③〕）**
- **UQ-L2**: 软打样 1:1 zoom window + 「1:1 像素 == 导出」等值测试验收形态——**挂面不入波**（软打样未立项；立项时验收形态直接取用；上游 LightCraft `c78b457c`）（2026-10-16 登记，无 phase 指针）

### M8 FSIM Spectral Core (SPEC) — 光谱升维（2026-10-17 M8 预告批登记草案 → 2026-10-18 M8-0 charter 批正式条目化）

来源 = `phases/m8-fsim-spectral/RESEARCH-PRE.md`（dt spektrafilm 模块族读解 + Jakob-Hanika 2019 公开数学 + 我方 film sub-run 缝融合测绘 + M6-2 process 通道对表）。家族正本 = ROADMAP §Milestone 8（2026-10-18 正式 charter）。**与 M3 FSIM 既有条目的关系 = 升维非重写**——FSIM-01a..d / FSIM-02（M3 交付的密度域阶段模型与宽容度面板）原样保留：密度域管线在 M8 后降为 process ≤ 1 老档的**冻结 legacy 臂 + golden 对照臂**（LightCraft V1 冻结同构）；M3 基建四件（film sub-run 缝 / FilmSolveCache / 65³ bake 家族 / 宽容度面板）= 同机制换内核，删除面为零。许可面 = dt spektrafilm 模块族与 spektrafilm Python 参考仓 GPL-3.0 零复制只读；Jakob-Hanika 论文数学 + BSD 参考方法可用；hanatos2025 表本体 / dt pack 常数集不消费（tc 表自拟合）；**CC BY-SA 数据包许可红线独立归属**——profile verbatim 纪律延续（谱面消费 = 同文件携带，归属义务面不变；与 MIT spectral_film_lut 分账零混用，FSIM-01d 先例）。边界精度修正 = FSIM-01c「光谱引擎不可达」收窄为「场景真实 SPD 重放不可达；重建谱上逐波长材料链可达」（RESEARCH-PRE §2；FSIM-01c 原文不改——勘误正本 = RESEARCH-PRE §2 + 本节）。

> **M8 批交付（2026-10-26 三眼验收全 PASS）**：SPEC-01..06 全 Delivered——四 plan 执行链 `47b28be0..903d23fe`，ΔN +80 ∈ [+60,+82]，全套三轮 `4286/46/0` 同值；双路 zcode PASS（`45f88435` / `f5bbe17c`）+ omp 终审 PASS/0B+1M+0m+6obs（`7b53e95d`——M-1 = probe 缝新档迁移行可见/sidecar 缺 process 键，挂账 M8 修正批首项，自愈通道非阻断）。golden 哨兵四件 + 曝光语义四法 + 迁移 UX 四面证据正本 = `phases/m8-fsim-spectral/M8-VALIDATION.md`（VALIDATION 签核 = C 档第 3 停呈晨审后另批）。

- **SPEC-01**: 光谱上采样核——scene-linear Rec2020 → CAT 至胶片参考光源 → xy → tri2quad → tc 系数表（192×192 级，自拟合 clean-room）→ sigmoid 谱重建 × `log_sensitivity` 积分 = 曝光 → log → DIR coupler → CMY 密度 → dichroic 放大机 × 相纸感光 → 扫描 CMFs → working RGB + OkLCh gamut 压缩；全链逐波长积分预折进构建期 per-sim/per-pair 表（GPU 逐像素无 81 波长循环）。**验收形态**：tc 表构建 <100ms 级 + 中性配平数值 sanity 实测 ✓；逐像素 kernel golden = 构建期表 Float64 独立数学复算对照（M3-3-03 两级门形态平移）✓ —— **→ M8-1/M8-2**
- **SPEC-02**: CC BY-SA 数据包更新通道——上游 spektrafilm release profile 谱面（`log_sensitivity`/`channel_density`/`base_density` 81 点全消费）新鲜 verbatim 更新流程（NOTICE §1 纪律延续：fresh copy + CHANGELOG 新行 + MANIFEST 对账，永不原地改）。**验收形态**：NOTICE/CHANGELOG/MANIFEST 三件对账测试（M3-3-01 MANIFEST 30 行全量对账先例）✓ + 上游 release 升级演练（fresh verbatim copy 幂等零漂移）✓ —— **→ M8-2**
- **SPEC-03**: 现密度域核迁移（process version）——光谱核 = 新 `RenderProcess` current 臂（process 2），密度核冻结 legacy 臂；老档渲染零漂移；film sub-run seed 分叉点折模型 tag（M6-2 §3.3 惯例）；`filmRampPlaneHash` 哨兵重钉流程；不设 `FilmRecord.engine` 字段（process 单源，OQ-M8-1 生效值）。**验收形态**：process ≤ 1 老档渲染逐位零漂移负测 ✓ + seed 折叠序钉死（含非 legacy 才折新 tag 负测）✓ + 哨兵重钉登记 ✓ —— **→ M8-2**
- **SPEC-04**: perf 预算——100MP 全帧光谱腿 probe 级预算（估 2-4× 现行 film 腿、非 81×——build-time tc-table 折叠；DIR coupler 模糊场降采样 1/4 res 候选）；tc 表构建 <100ms 级；8G RSS 门机检；probe 批先行（M8-1）定真值。**验收形态**：probe 四件（tc 构建 / 逐像素 microbench / RSS 峰值门 / pristine·strength-0 与密度核逐位对照基线）全实测入库（`LIGHTAMER_PERF_PROBE=1` 门 + L014 fence 惯例）✓ —— **→ M8-1**
- **SPEC-05**: UI 对齐——现行 Film 面板平移（材料 picker / Y·M 滑杆 / Solve / 宽容度面板数学零改；descriptor 真链 probe 换臂）；Alcedo 无光谱面无新增对标项（「等其落地」= 无对齐对象；Alcedo 胶片模拟 = LUT 面，M3-2 §10 已核）；dt upsampling 表选择器 / 带宽自适应控件 v1 不引入（恒自拟合单表）。**验收形态**：宽容度面板数学零改逐位（直方图原生轴 / 双虚线 / 占比 / Fit / typed 拒绝三规则）✓ + descriptor 换臂读数 by-design 登记 ✓ + GUI 走查配方（Manual-Only 行归 MANIFEST）✓ —— **→ M8-3**
- **SPEC-06**: FSIM-01c 边界措辞精度修订——NOTICE 消费披露行 + README/help 用户可见措辞升格「光谱重建材质模拟（逐波长），非场景光谱重放」；历史文档原文保留（勘误行追加惯例）。**验收形态**：NOTICE/README/help 措辞落位 ✓ + 历史文档零回改机检 ✓ —— **→ M8-2/M8-3**

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
- [x] **MCP-09**: 筛选/修图扩充工具组（2026-09-26 登记）：list_presets / apply_preset / diff_presets（预设三件套，上游依赖 PRES-01..04）+ export_image（尺寸/质量/格式落盘，render_preview 不落盘之补位）+ set_keywords（关键词写面，上游依赖 META-04）。**研究项**（Phase 14 research 定案）：A = GUI 与无头 MCP 同会话并发 sidecar 双写对策（WAL 仅覆盖索引层；单写者锁/后开者只读/移交）；B = 多版本参数组/历史快照 MCP 语义（多版本交付需保存/切换/对比参数组工具面）；C = match_color MCP 工具位（agent 编排层：选参考/批量触发 colormatch/强度/事后 apply_params 微调；签名预留，依赖 V2 TRACK colormatch iop，与 Phase 12 .cube LUT 协同）**→ 兑现（M5-1-03 2026-10-12）**：`match_color(reference, targets?, strength?, solver?, attach?)` 五参最小面（OQ-M5-1-6 裁决生效值）——reference 库内 id/路径双形态解析（LibraryStore.image→ImageLinker.resolve / resolveMember）、targets 批量 fan-out 逐目标独立求解、strength/solver（gaussian-ot|reinhard|cdf）、attach 自动落位 + `{instanceId, params 摘要, solveHash}` 返回、微调/验收/元数据全走既有 apply_params/render_preview/list_iops 零新增面；19-tool 快照族 19→20；G4 parity byte-identical【`McpMatchColorToolsetTests` 21 法 + `McpMatchColorParityTests` 3 法】。**研究项 A 重开 → M6-1（2026-10-16 LightCraft 裁决①，用户回批全按推荐）**：14 关闭的是 **MCP 宿主级**单写者（flock 五态 + 只读降级 + GUI-live 判据）；未决残面 = **库/项目级**并发——无头实例与活 GUI 同开同一项目时的 `.lalb`/`.lra` 双写。M6-1 = LightCraft `catalog.lock` + `--connect` 范式的项目级兑现（项目打开权单写者 + 撞活实例拒写并转发指引 + GUI 只读回退面）。charter 正本 = ROADMAP §Milestone 6（M6-1）；research 正本 = `phases/m6-1-interop/`。**研究项 A 兑现（M6-1-01 2026-10-14 VALIDATION signed）**：项目级单写者锁全落账——Core `SingleWriterLock` 五态泛化件（flock 唯一仲裁 + payload v1 冻结拼写 + probe=try-flock 即释）+ `<stem>.lalb.lock` 项目锁（role 面/openReadOnly E2 三岔/withWriteBatch 断路/close 释放序/`.lalb` 零 schema 触碰）+ legacy `session.lock` ride-along（进程内 seat registry）+ GUI 三选对话框与最小只读面（三 seam + banner AX + guard 家族 13 + VersionCoordinator 六写命令门 + batch paste 门）+ 无头 `--project` 仲裁两臂 + connect 指引（HTTP=stdout/STDIO=stderr/降级/只读常驻）+ MCP 写面 typed `projectReadOnly`（live 先判 + 自持豁免 + 五调用点）+ create/move 生产路径锁贯穿 + o-2 ColormatchResolverBox NSLock 收窄；终验 3689/24/0（对账链 3631+53+4+1 精确）；正本 = `phases/m6-1-interop/M6-1-VALIDATION.md`
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

### Color Transfer / 追色 (TRACK)【V2；2026-09-22 用户指令维持 V2（当日曾短暂提级 Phase 7，已回撤）】—— **M5-1 phase closed（2026-10-13 VALIDATION signed——`phases/m5-1-track/M5-1-VALIDATION.md`：三 plan 双验收全 PASS〔02 波 omp FAIL→fix→复验闭环〕+ 五门全绿 + 终态 3477/21skip/0fail；OQ-M5-1-1..8 全按推荐 2026-10-11 用户回批；五门台账正本 = `phases/m5-1-track/M5-1-GATE-LEDGER.md`；TRACK-01..05 终态 Delivered 本 VALIDATION 盖验落签）；**M5 milestone closed 2026-10-13 追签（M5-3-VALIDATION 兼收口 `milestone_closeout: M5`——TRACK 族 Delivered 终态随 M5 收口盖验确认，正本 = `phases/m5-3-pano/M5-3-VALIDATION.md`；夜间授权链晨审可推翻）**（research 正本 = `phases/m5-1-track/`；charter 正本 = ROADMAP §Milestone 5）

> **定位再确认（2026-09-26）**：计算核 native 不可外包——追色是统计算法（Reinhard/CDF/OT → 3D LUT），TRACK-05 确定性门与 TRACK-02 多参考统计聚合排除 agent vision 迭代路线（LumaRescue 类方法论无色彩匹配算法）。MCP+agent 作**编排皮**：选参考/批量触发/强度/事后微调（MCP-09 研究项 C `match_color` 工具位，依赖本模块 colormatch iop）；与 AIV2-01「AI 追色」的语义由编排层承载。GUI 拖入交互（TRACK-04）与 agent 编排并存不冲突。

- [x] **TRACK-01**: 追色计算——参考图色彩分布特征提取 + 色彩变换求解（Reinhard Lab 对齐 / 直方图 CDF 匹配 / 最优传输族中选定算法），输出 3D LUT（或等效参数曲线组）**Delivered**（M5-1-01/02：三档全交付——S1 Gaussian OT 闭式三明治 + S3 Reinhard 对角【`ColorMatchSolverGoldenTests:testG3MomentExactRecoveryS1/testG3DiagonalRecoveryS3`，G1 双跑位型 `testG1DoubleRunBitIdentity`】+ S2 per-channel CDF 256 梯【`ColorMatchCDFSolverTests`】；统计域 Oklab + 65³ `.cube` 派生 LUT【`ColorMatchBakeGoldenTests:testVoxelGateAgainstIdealModel` 实测 7.6e-8】）
- [x] **TRACK-02**: 多参考图支持——N 张参考的统计聚合或逐参考混合，权重可调**Delivered**（M5-1-02：统计级加权矩池化（序规范化 + 直方图取整 + N=1 恒等 + support 并集）——`ColorMatchPoolingTests:testAnyPermutationGivesByteIdenticalPool/testScalarScaledWeightsGiveIdenticalPools`；GUI 参考列表权重滑杆）
- [x] **TRACK-03**: 非破坏落位——追色结果以 `colormatch` iop 模块实例落位（内嵌 LUT + tetrahedral 插值 kernel），sidecar 持久化、可继续手调、cache 语义正确**Delivered**（M5-1-01/02：独立 op 36.5 + Params 直存 + store 级投影缝 attach + solve-twice 幂等零新 item——`ColorMatchServiceTests:testSolveTwiceLandsByteIdenticalParams/testAttachLandsOneHistoryItemWithParams`。**裁决偏差注记（checker m7，防 VALIDATION 对表困惑）**：原文「内嵌 LUT」→ 生效值 = **`.cube` 派生资产**（`<图名>.lra.colormatch/` 旁挂 + params 存 `{assetRef, assetHash}` 引用，65³ Float32，LUT 字节不进 sidecar 的 <8KB 上界专测钉死）——OQ-M5-1-3 裁决 2026-10-11 用户回批；tetrahedral 插值 kernel 经共享 `lut3d_tetrahedral` 函数兑现（`Lut3dKernels.metal` 零 diff））
- [x] **TRACK-04**: 交互——拖入/选择参考图 → 自动计算并预览；强度/透明度可调；before/after 对比**Delivered**（M5-1-02：ColorMatch 面板（solver picker + 参考列表权重滑杆 + strength 拖拽 + readout 统计哈希/支撑域）+ LUT 页 add 行（E-omp1 修复 `3ae3daf`）+ D-H1 拖拽三件套；实机走查证据 = `gui-acceptance/m5-1/` MANIFEST 行 1-4 + m5fix-*，本批收口未重跑——Manual-Only 行留 VALIDATION 人工执行）
- [x] **TRACK-05**: 质量门——LUT apply 的 golden parity（kernel vs float64 参考）、HDR/广色域裁剪策略明确、确定性（同输入同 LUT）**Delivered**（五门全绿——**G1** bit-identity 双跑/缓存键字面/全链含持久资产逐位【SolverGolden/BakeGolden/ServiceTests】；**G2** kernel parity 双面门（良态 ≤1e-5 + 全网格交越界实测钉 2.95e-3/3.68e-2，cbrt 交越机制注记 P1 DECISIONS §2）【`ColormatchKernelParityTests:testKernelParityP999`】；**G3** 合成对恢复（矩精确 ~1e-7 / 采样 1.73e-2 带内）+ 自然样张目测 = gui-acceptance Manual-Only 行【`ColorMatchSolverGoldenTests:testG3*`】；**G4** MCP e2e byte-identical【`McpMatchColorParityTests` 3/0/0，M5-1-03】；**G5** 恒等直通三态 byte-exact【`ColormatchIdentityGoldenTests`】；裁剪策略 = 1%/99% 截尾支撑域 + 线性延拓平台面（OQ-M5-1-4）；台账正本 = `phases/m5-1-track/M5-1-GATE-LEDGER.md`）

### Alcedo Parity / Alcedo 对标缺口 (ALCE)【V2；2026-09-27 用户指令——功能对标基准由 Darktable 全量翻转为 Alcedo Studio 后，对已交付 39 iop + Phase 6-16 交付面盘点出的真实缺口】

> **基准**：Alcedo Studio（GPL-3.0，`/Volumes/UNITEK/Documents/Development/AlcedoStudio`）。已覆盖面不重复立需求（色调/曲线/可选颜色/细节/局部色调映射 = Phase 3/4/5 已交付；LUT/颗粒/光晕 ≈ Phase 12 + bloom/grain；图库/分组/EXIF 搜索 = Phase 9/16；蒙版 = Phase 6；HDR/EDR = Phase 8；导出命名模板 = Phase 11）。**CIRAW 边界排除项不入本族**：demosaic 算法菜单、raw 域 inpaint-opposed 高光重建——架构上不可达（STACK.md Decoder 策略对比节 2026-09-27），v2+ 若做须走 libraw 兜底解码路线。Lensfun 镜头数据库维持 STACK.md 原评估（数据只读 + Metal warp），不因翻转加码。

- [ ] **ALCE-01**: LGG 三向色轮（Lift/Gamma/Gain，grading 标准 3-way）——每 adjustment layer 一个色轮实例，蒙版可绑；与现有 colorbalancergb/colisa 并存。UI 色轮 + Metal kernel + golden-image 门
- [ ] **ALCE-02**: OpenEXR 导出（32-bit float，half/float 可选）——现导出矩阵 JPG/PNG/TIFF/HEIF/WebP/AVIF 无 EXR；HDR/堆栈工作流回传 3D 软件需要 —— **随 RASTER-IN 推迟，M4 不立项**（2026-10-08 用户裁决：M4 范围收窄 TIFF only；EXR 读写依赖对比存档 V2-PROPOSAL OQ-V2-5，届时独立裁决）
- [x] **ALCE-03**: Ultra HDR JPEG 导出（gain map，SDR base + HDR 增益层）——嵌入现有 JPEG 编码腿，EDR 渲染值映射 gain map。**解冻 → M6-3（2026-10-16 LightCraft 裁决②，用户回批全按推荐）**：spike 先行 = ImageIO 原生路（`CGImageDestinationAddAuxiliaryDataInfo` + `kCGImageAuxiliaryDataTypeISOGainMap`〔macOS 15+〕/ `kCGImageDestinationEncodeGenerateGainMapWithBaseImage`〔macOS 16+〕——两键均在 macOS 27 底线内，SDK 实测在案），对照臂 = LightCraft 纯 Rust metadata writer 的 Swift 移植（MIT/Apache-2.0 双许可，NOTICE 义务）；原生路容器字节达标即收。charter 正本 = ROADMAP §Milestone 6（M6-3）**Delivered（validated 2026-10-14——M6-3 closed，VALIDATION = `phases/m6-3-ultrahdr/M6-3-VALIDATION.md`，双路独立验收 PASS / 0 error + 0 minor open；终态全套 3759/24/0 = 3725+34 精确）**：落地面 = research 三臂实测证 ImageIO 两键死路后走 **CI `.hdrImage` 全服务路**（`writeJPEGRepresentation` 写出完整 ISO 21496-1 容器 MPF APP2 + ISO APP2 + 尾部副图 + HDRToneMap，charter「原生路容器字节达标即收」兑现）+ `ExportVariant.gainMapHDR` validate 六门（jpeg/drtOutput/peak≥203〔203 单源三消费点〕/embedICC=false〔ExportICCStrip×MPF 偏移雷〕/!isHdrEncoding〔D-M6-3-7〕/!yiyin）+ `linearGainCapture` 9-hunk 缝（DRT 尾 EOTF-box 前线性级 capture，E4 线性光约束）+ `ExportGainMapEncoder`（CopyImageSource rewrap〔AddImageFromSource 丢 MPF 雷规避〕+ hdrgm:Version + **v1 无 EXIF 降级**〔{TIFF} 座位被 CI 路拒——OQ-2② 预授权；EXIF 注入器 → v2 批挂账〕）+ M2 页五维门 checkbox + 复位三入口；六格式矩阵零改动红线维持（ExportFormatSpec 面零 diff）；LightCraft 移植臂降兜底封存（零代码零 NOTICE）；单通道 'L008' + 不加新 tag；挂账五项 = VALIDATION 挂账总汇编
- [ ] **ALCE-04**: DRT 扩容——ACES 2.0 输出变换 + OpenDRT（现有 filmicrgb/sigmoid/agx 三个 DRT 之外）；目标色彩空间/传递函数/峰值亮度可选，与 EDR 输出联动（参考 Alcedo display-transform 面板与 jedypod/open-display-transform、aces-aswf/aces-core 算法）
- [ ] **ALCE-05**: 每片命名版本（named versions）——同一原片多个命名编辑版本并存，可从 history stack 任意步分叉；sidecar schema 扩展 + 浏览器版本切换 UI
- [ ] **ALCE-06**: in-app 自然语言搜索 + 自动打标签——本地 CLIP 多语言模型（导入后后台索引），按自然语言查询图库；对标 Alcedo 图库搜索；与 Phase 14 MCP 外接 AI 通道互补（不依赖外部 MCP 客户端）
- [ ] **ALCE-07**: in-app AI 评片与描述——OpenAI/Anthropic 兼容 API（钥匙串存 key，后台批跑），输出 1-5 星 + 理由 + 描述文本；评分写入 rating 管线，与 culling/MCP-10 通道共享落地字段
