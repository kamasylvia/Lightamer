# LUMEN-B SUMMARY — 缓存底座 + 选片视图（LU4+LU3）执行摘要

> 执行批 = LUMEN-B-PLAN.md（checker `75678937` + fixer `a0e43b44`；批起点
> = LUMEN-A 终态 `c7bc2b9b`）。执行窗 = 2026-10-24。逐任务 commit-per-task，
> 全英文 Conventional Commits（`lumenb` 前缀），零 issue ref（内部规划口径
> ——A 批同款备案：仓内 issues 未启用）。

## 逐任务记账

| 任务 | commit | 内容 | 测试 |
|---|---|---|---|
| T1 | `3b916721` | SmartPreviewFormat：LAPV1 形 pack/unpack（magic+头长+JSON 头+float16 量化+字节平面重排+zlib）+ 公开 quantize 一致性规则 + 五类 typed 容错 + MIT 文件头注记 | SmartPreviewStoreTests +8（IOP） |
| T2 | `b23d01a0` | SmartPreviewStore actor：键（path\|size\|mtime ns\|process version\|格式版 → sha1 hex）+ index SQLite WAL（entries 表形）+ 平面文件同目录 tmp 原子晋升（L009）+ LRU 4GB/trim 90%/每 16 写 + 内存 LRU 6 + in-flight 合并 + shared holder 单例（m-9）+ 损坏重建/降级直解码/禁用中性 | +7（IOP，累计 15） |
| T3 | `4ad37204` | SmartPreviewRender 共享解码腿（RAWDecoder 之上零签名改，档位 2560）+ 四门接线（①申报未接线——DECISIONS §1；②桥 RenderLeg 生产侧；③loader 腿；④CullingToolset 内部路由）+ 消费点负测（t3-grep.log） | +3（IOP，累计 18）+ App 全跑 974/6/0 |
| T4 | `6d49769e` | AppPhase.cull 第三 face（路由 tripwire 应答）+ CullViewLoader actor（2560 内嵌直读/full_size 判定随提取/全尺寸 LRU 2/±3 预读/生产门 cap 2 复用/回落腿）+ CullFaceModel/View（头栏/Pane/胶片条 96px/帮助行）+ 网格 onCull 缝 | CullFaceModelTests +8（APP；App 全跑 982/6/0） |
| T5 | `6e793532` | CullKeymap 键位表（G/D 钉死 + 0-5/P/X/U/6-9/A/C/F + Z 偏差申报）+ 评级写腿（setMetadataMarks 投影批写 + 本地 projection 刷新 + A 同步前进）+ 视图 KeyPress 路由 + xcstrings 10 键尾插（160 added/0 removed 纯插入证明）+ zh-audit 双 PASS | +6（APP，累计 14） |
| T6 | `1705531e` | 对比状态机（换候选/切侧/晋升/退出交接/单行拒入）+ 共享 zoom 单源（sync_zoom 结构化）+ 100% 腿（全尺寸平面 + 显示面插值占位）+ 组跳（前跳落组首/后跳落前组首/端点钳）+ 胶片条 n/m + best 徽章 + 提示条映射 + 分析插队（service.prioritize + 分区纯函数 + wiring 缝 + 模型 ±(-2..+6) 窗） | +8（APP，累计 22）+ LIB +1（分区）+ App 全跑 996/6/0 |
| T7 | （本 commit） | Settings 容量行（previews.cacheMB 阶梯 0/1/2/4/8/16/32GB + live setLimit）+ Project.swift 两行正式注册 + BUNDLE-MAP 两行 + tuist generate 批末位 + docs + xcstrings 5 键 | — |

## ΔN 终账（T7 末轮机检值）

- 计划带 **+14..18**；实账 **+41**（IOP 753→771 = +18；App 974→996 = +22；
  Library 775→776 = +1）——**越带 +23，申报正本 = DECISIONS §9**（每条 SC
  子句一测纪律 + loader 高状态面各族独立确定性方法 + LIB 分区测试寄生
  既有文件）。
- **T7 末轮定向（正式注册后全量）**：`--bundle IOP` **771/5/0**、
  `--bundle App` **996/6/0**、`--bundle Library` **776/4/0**——全绿零回归
  （skip = 既有家族：IOP 5 / App 6 / Library 4，本批零新增 skip；t7-*.log）。
- 全套 `--all` 不在本批（orchestrator 批准制）——**归 Plan C 收口轮统一
  对账**；全套终值带按 +41 修正（A 终态 + 41 邻域，以运行期 Executed 为准）。

## 验收判定（机检汇总）

- 构建：全部任务 TEST BUILD SUCCEEDED；tuist generate = T7 注册批末位一次。
- 定向：T7 末轮 IOP 771/5/0 + App 996/6/0 + Library 776/4/0 全绿（t7-*.log）。
- golden 面：float16 round-trip 逐位 + <0.05% 相对误差（双源）；quantize
  幂等；消费级命中/未命中逐位（冷店 disk hit == miss == quantize(decode)）；
  禁用中性（原解码逐字节直通）。
- 红线核：PixelPipe / RAWDecoder 签名 / EditorState / PipeCoordinator /
  McpServerController / CullingView / SessionThumbnailProvider /
  LightamerSidecar / HistoryStack 全程零 diff（t3-grep.log + 逐 commit
  git 面核）；xcstrings 两批尾插（160+8 added / 0 removed）；zh-audit
  `--check` + `--self-test` 双 PASS（1712 source / 2031 catalog）；
  L009 同目录 tmp 原子晋升；L041 批末位 generate；UserDefaults 恰一键
  `previews.cacheMB`（全仓字面量恰一处 = Core 常量，t2 commit grep 在案）。
- 键族登记：`cull_advance_label / cull_back_label / cull_compare_label /
  cull_face_empty / cull_help_row / cull_hint_best / cull_hint_blurry /
  cull_hint_eyes_closed / cull_hint_sharpness / library_grid_cull /
  settings_previews_hint / settings_previews_limit / settings_previews_mb /
  settings_previews_off / settings_previews_section`（15 键，两批尾插）；
  **UserDefaults 恰一键 `previews.cacheMB`**（Int 默认 4096，0 = 关；typed
  读 + 注入式 + body 零直读——AppPreferences alias + Settings 行）。

## 裁定与偏差指针

- 正本 = 同目录 `LUMEN-B-DECISIONS.md`：gate ① 未接线申报（H-LU3 第二臂
  结构性）+ 平面档位 2560 + zlib level-1 意图等价 + shared holder 形 +
  mtime ns + 弃层申报（2560 JPEG 层 / 320 thumbs 层）+ 消费级量化边界
  （disabled = 原始直通）+ 测试源替代 + 评级写腿投影面折衷 + Z 键可加 +
  ΔN 越带 + 重开探针 skip 族 + 磁盘压力处置记录。

## 证据指针

- 构建/测试日志：`.work/gsd/phases/lumen-culling/evidence/lumenb/`
  （t1-iop / t2-iop / t3-iop / t3-app / t3-grep / t4-app / t4-grep /
  t5-app / t5-zhaudit / t6-app / t6-zhaudit / t6-app-full / t7-iop /
  t7-app / t7-library；.work evidence 目录按仓策略 gitignored，正本在
  工作树）。
- GUI 走查：选片评级流（G/D/P/X/A 全键位）+ C 对比缩放同步 + 重开命中
  探针（≤100ms 级）= **computer-use 通道职责**（validate 道；本批执行道
  为纯文本 agent，无 GUI 走查产物）——清单见
  `.work/gui-acceptance/lumen-b/MANIFEST.md`，与重开探针同挂 C 收口轮。

## C 档停位

本 plan 执行 + 验收闭环 = **停**。LUMEN-C（MaskRefine + refine_masks，
ΔN +6..7）待用户确认后起跑（C 与 A/B 无依赖可换序——D-LU-9）。
