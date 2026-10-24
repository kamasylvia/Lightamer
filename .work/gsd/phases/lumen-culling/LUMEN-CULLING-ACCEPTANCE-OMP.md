# LUMEN-CULLING-ACCEPTANCE-OMP — 图库选片增强批（UQ-LU1..LU5）终审

> 终审轮：2026-10-24，终审人 = omp 独占终审眼（dual_acceptance 制度，computer-use 实机）。
> 对象 = `2b841916..01249a6f` 执行链（A 8 + badge 修复 2 + B 7 + C 5 + BC 综合验收 1）。
> 材料链已读：CONTEXT.md + LUMEN-A/B/C-PLAN.md + 四 SUMMARY + 四 DECISIONS +
> LUMEN-A-ACCEPTANCE.md + LUMEN-A-ACCEPTANCE-2ND.md + LUMEN-BC-ACCEPTANCE.md +
> LUMEN-CULLING-CHECKER.md + lumen-b/c MANIFEST。
> 零源码改动；唯一写产物 = 本报告 + 截图目录（不 commit）。
> 报告与截图落盘，不 commit。

## PASS / 0 blocking + 1 major + 4 minor + 8 obs

**判定：PASS（带 1 major 回注，LUMEN-CULLING 批放行；major 为既有域回归非本批引入，
修不修不拦本批定稿，但须挂账追踪）。**六抽验面 a/b/c/e/f 实机闭环（徽章/智能相册/
选片全键位/对比/组跳/Settings 双行/gamma 读出/主链回归/静置 CPU），d) 蒙版精细化
正路径因供件面无主体可检未能端到端触发——负路径（refine 按钮禁用态 + MCP typed 三臂）
实机闭环，正路径留待人工真机行（判 minor-1 观察项而非 blocking：单元/golden/编排
测试面已由执行批 + BC 独立验收覆盖，缺的只是 GUI 端到端样张行）。

---

## 一、抽验 a) 图库网格连拍徽章 —— ✓

探针集（8 TIFF，EXIF 机身 `Omprobe/Omprobe One/SER-OMP1`，A 组 10:00:01/02/03、
B 组 10:05:01/02/03、single-sharp 11:00、single-blur 12:00 σ8 高斯模糊）经 Copy
导入（Link 导入四连零行，见 §七 major-1）→ 重开触发分析趟 → ≤10s 内 8/8 stamp：

| 行 | sharpness | faces | eyes | signature |
|---|---|---|---|---|
| burst-a/b ×6 | 89.4 | 0 | 0 | 256B |
| single-blur | 15.8（<22 → blurry 注记） | 0 | 0 | 256B |
| single-sharp | 89.4 | 0 | 0 | 256B |

网格徽章（omp-01/02）：「连拍 1/3 ★」「连拍 2/3」「连拍 3/3」×2 组 + single-blur
「可能模糊」+ single-sharp 零徽章 —— 与 DB 产物逐位一致。best 星标落在组首帧
（组内 sharpness 全等 89.4 → 组内序稳定决胜，一路二路同表型）。

**分析趟触发面注记**（obs-1）：导入后同会话 60s+ 零 stamp（CPU 0.3% 闲置，
wiring 已装配「照片分析」条在屏），重开后 ≤10s 完成 8/8。触发条件非纯粹
projectChanged（导入会话内即应触发），疑似首刷/订阅窗与导入完成的竞态
（二路 obs-6 微窗的放大版）或导入完成事件未重 kick 趟。数据面零损失
（重开即愈），记 obs 不升 minor。

## 二、抽验 b) 智能相册四案 —— ✓

JSON 注入四案（验后删除还原），重启后边栏计数亲读：

| 案 | 条件 | 边栏计数 | 应用结果 |
|---|---|---|---|
| sharpness≥50 | `sharpness gte 50` | 7 | 网格「共 7 张照片」+ chip（omp-03），blur 行被滤除 |
| faces eq 0 | `faces eq 0` | 8 | （计数面验证，未逐一点应用） |
| eyesClosed eq 0 | `eyesClosed eq 0` | 8 | 同上 |
| hasBurst eq 1 | `hasBurst eq 1` | **计数缺席** | 单击：网格不动（仍 8 张）+ typed 无臂（omp-04） |

hasBurst 的「计数缺席 + 单击 typed 拒」= m-11 designed 降级面（二路 §二同表型），
非缺陷。SQL 直比三案计数与 DB 真值逐位一致（7/8/8）。

## 三、抽验 c) 快速选片视图 —— ✓（全键位 + 落库 + 对比 + 组跳）

入口：网格右键 → 「快速选片」（omp-05 上下文菜单五项：快速选片/AI 超分辨率/
AI 去杂色/转为堆栈/自动成堆叠——burst 行；非 burst 行无「转为堆栈」）。
第三 face 切入（`library.cull` AX 面在位）：头栏（文件名/2 / 8/Omprobe/
「清晰度 89 2/3」橙色提示条）+ 单 Pane + 胶片条（n/m + best 星标）+
帮助行全键位（omp-06）。

| 键 | 实测 |
|---|---|
| G 回图库 | ✓（cull 节点 8→0，grid 节点 0→11） |
| D 进编辑器 | ✓（NODES 163 编辑器面，omp-11） |
| 5 星级 | ✓（burst-a2 rating=5 落库，见下） |
| P 留用 | ✓（single-blur flag=1 落库；rating 列恒 NULL → SQL 覆盖写整行语义，见 obs-3） |
| ← 步进 | ✓（7/8 → 6/8） |
| C 对比 | ✓（左右双 Pane，左锐右糊；omp-08） |
| Tab 切侧 | ✓（header/胶片条 6/8 ↔ 候选交接） |
| ↑ 晋升（对比态） | ✓（候选 single-blur 晋升为选定 7/8） |
| C 退出交接 | ✓（右侧持键时候选成选定，单 Pane 7/8） |
| ↑↓ 组间跳 | ✓（7/8 ↑ → 6/8 burst-b3「3/3」= 前跳落前组首，omp-09） |
| Z 100% | ✓（滚动条出现 = 放大态；复位正常，omp-10） |
| A 评级后前进 |  checkbox 在位未勾选态亲见；同步前进语义由执行批测试覆盖，本轮未单测（obs-4） |
| F 人脸框 | 探针集 faces=0，无框可显；帮助行在位（obs-4 同款） |
| 空格/C 进出 | C 进出 ✓；空格 = 滚动语义（X7 词汇，Z 取代 Space 缩放），无进出绑定 —— 派单措辞「空格/C 进出」中的空格项不成立，属派单口径误（obs-5） |

评级落库（omp-15）：回图库后 burst-a2 现 ★★★★★ + 边栏「按色标 five-star=1」+
智能相册「高分组=1」—— 投影列即时面 + SQL 面双闭环。DB 终态：
`burst-a2 rating=5 / single-blur flag=1`，其余 NULL。

## 四、抽验 d) 蒙版精细化 —— △（负路径闭环，正路径缺供件）

- 调整层创建 ✓（「添加图层」→ 调整 1 选中）→ 主体蒙版生成 → toast
  「未检测到主体——未生成蒙版」（omp-13，夜景无显著主体，诚实 typed 面）→
  sidecar 恒 1 item（仅「新建图层」）→ **refine 按钮 `精细化蒙版边缘`
  AXEnabled=False**（无 AI 蒙版层禁用态，C MANIFEST A3 后半 ✓）。
- 人物实例臂同结果（noSubject，无 picker 无置换）。
- MCP `refine_masks`（33 工具闭集在册 ✓）：无控制权 → typed
  `[controlNotHeld]` ✓；acquire 后缺参 → typed `[invalidParams] relPath
  required` ✓；release 往返干净 ✓。B2/B3 的 unknown-id/live-image 两臂因无
  AI 蒙版会话未能实调（参数形先决于会话面）。
- 正路径（AI 蒙版 → 自动精细化 → 边缘改善 → 一步 undo）**未触发**：供件面
  无主体/人物可检，Vision 两臂均走 noSubject。判 **minor-1**（§八），
  非 blocking：算法 golden（mean 2.8e-3/max 6.4e-2）+ 编排七面 +
  MCP typed 五面已有执行批测试 + BC 独立验收 firsthand 复算覆盖；
  缺的是 GUI 端到端样张行（需一张有人物/显著主体 + 细边缘的供件）。

## 五、抽验 e) Settings 行 + gamma 读出 —— ✓

- Settings → 缓存页（omp-14）：「智能预览 / 缓存上限 4,096 MB」
  （`settings.cache.previewsLimit` PopUpButton）+ 「蒙版精细化 /
  自动精细化 AI 蒙版边缘」toggle ON（`settings.mask.fineAuto`
  CheckBox=1）+ 双说明文案，零裸键。
- fineAuto 双向拨动：OFF → `mask.fineAuto=0` 落盘，ON → =1；验后
  `defaults delete` 还原缺席态（默认 ON）。
- gamma RAW 读出（omp-12，RAW 解码 tab「输入色彩」）：配置文件 无标记 /
  来源 按 sRGB 假定 / 传递曲线 sRGB / 峰值 100 nits —— 全本地化文案，
  `rawdecode_*` 裸键零可见。
- 默认行为页「照片分析」节（A 批面）：本轮未重验（二路 acc2-settings-toggle
  已闭环，无回归面）。

## 六、抽验 f) 编辑器主链回归 + 静置 CPU —— ✓

- D 键进编辑器：画布渲染 + 直方图 + 调色 tab + 胶片条 8 行 + 蒙版工具栏
  全活（omp-11）；RAW 解码 tab 切换正常；图库/编辑往返无崩。
- 静置 CPU（PID 18133，图库面，settled）：0.8/0.8/0.7/0.7/0.7/0.6 六连平，
  RSS 267-310MB —— ~0% 门内。
- 全程零崩溃；`sample` 两轮（导入静默期 + 分析闲置期）均主线程 RunLoop
  闲置 + 工作线程 workq 挂起，无死锁/自旋。
- SmartPreview 缓存目录：80 entries/106KB 全为 10-23 旧键，
  **本轮 8 TIFF 零新键** —— 预期内（Tier A 内嵌直读 + cull 内嵌合格
  + has_edits 全 NULL → 三消费门均未击发；见 obs-6）。缓存命中/未命中
  逐位一致性由 T3 golden 背书，实机命中行需 has_edits 行或无内嵌源，
  本轮未造（obs-7）。

## 七、blocking/major 判定

**blocking（0）**——无。

**major（1）**：

1. **Link 模式导入四连零行（既有域回归，非本批引入）**：同一 fx 源，
   Link×4（omp-cull 整选误选 + fx 精选×3，含杀 stale 实例后的干净轮）
   全部 sheet 全流程走完（传输方式=链接 → 导入 → AI ask → 暂不）→
   `images COUNT(*)=0`；同源 Copy 首轮即 8/8（EXIF/serial/SubSec 全对）。
   - 非本批引入：`git log` 示 ImportService/ImageLinker/ImportFilter
     近改均为 M4-1-02（category mask）/ merge-stack 批，lumen-culling
     三 plan 零触导入面（BC 综合验收封存面清单亦无导入文件）。
   - 已排除：类别掩码（缺键=双开，对话框 TIFF 8 文件已勾选）、白名单（TIFF 硬编码集正交）、guard（`importProgress == nil`，
     串行单跑）、stale 双实例（干净轮单实例复现）、路径（kind1 volumeRelative/API 误用无证据——Copy 同盘同路径成功）。
   - 表型：静默零行（无 alert、无 watchdog 日志、无 lastError 面；
     `mcp-endpoint` 外无错误通道）。Link 腿 `executeLink→insertRow→
     fillMetadata` 任一环节 typed 吞错（`catch { outcome.failed += 1 }`
     无日志）均可致此；`link` 语义（S1 sidecar 留原位）与 category
     mask 的 M4-1-02 交互面为首要嫌疑域。
   - 处置：挂账 R13/导入专项（复现配方 = 本报告 fx 集 + Link 模式），
     不拦 lumen-culling 定稿（本批全部验收面经 Copy 导入闭环；
     Link 为 M2-2 既有能力）。

## 八、minor/obs 清单

**minor（4）**：

1. **d) 正路径缺 GUI 端到端行**：见 §四。补测配方：一张有人物/显著主体 +
   细边缘（发丝/枝叶）供件 → 主体蒙版 → 自动精细化（1.2s debounce +
   自愈链）→ overlay 对比 → ⌘Z 一步回快速蒙版。由人工走查轮或下批
   validate 道执行；本批测试面已覆盖算法/编排/MCP。
2. **承接 BC-1（C 批 xcstrings 台账数字失真）**：C-SUMMARY「三次尾插
   48/48/48」vs 实测两次 64+48 —— 本终审未独立复算行数，维持 BC 验收
   结论，修复 = 文档勘误随下批 docs 批。
3. **承接 BC-2（`MR_DEBUG` 调试残留）**：`MaskRefine.swift:138` env 门控
   stderr 钩子未申报 —— 本终审未读源码复核（computer-use 轮），维持
   BC 结论，建议随下批摘除或登记。
4. **承接 BC-3/BC-4（CullViewLoader 无内嵌边界 + T1 容错/度量形）**：
   同上维持，建议后批处理。另承接 A 批 minor-1..4（一路原样，
   二路复核确认）：SubSec 三位数假设/minor-1 谱系已锐化至 +250s 级、
   hasBurst 死拼写、MainActor 全量重算、任务条不回收（本轮实证：
   分析趟毕后「照片分析」条仍在屏，omp-01/15 均可见）——
   全部为后批打磨项，无一触及本批行为红线。

**obs（8）**：

1. 分析趟导入会话内不触发、重开 ≤10s 完成（§一）：疑似导入完成→趟
   kick 缺口或首刷/订阅竞态；数据零损失，重开即愈。
2. 导入面板 AX 驱动注记：NSOpenPanel 文件行须 `AXSelected` 直写
   （坐标点击恒 miss）；Go-to-Folder 须 System Events（CGEvent
   chord 被面板吞）；saveAsNameTextField 须剪贴板粘贴（AXValue 直写
   不落）。已沉淀为本轮 probe 脚本（`/tmp/omp-cull/*.py` 即弃，
   未入库）。
3. P 键 SQL 语义：`setMetadataMarks` 整行覆盖写（rating 5 → NULL，
   flag → 1）—— 执行批 DECISIONS §7 投影面折衷的实机对应，
   非缺陷，备查。
4. A 前进/F 人脸框未单测：A checkbox 在位；F 因 faces=0 无框可显。
   功能面由执行批测试覆盖。
5. 派单口径误：「空格/C 进出」中空格无进出绑定（Space=滚动，
   X7 词汇）；C 进出 ✓。派单措辞勘误。
6. 缓存零新键预期内（§六）：三消费门（档B has_edits/选片回落/MCP）
   本轮均未击发；命中一致性由 T3 golden 背书。
7. 实机缓存命中行缺席：需 has_edits 行或无内嵌 RAW 源 + 同图二次载入
   计时（≤100ms 级，fence）。挂 validate 道探针（MANIFEST B8/C1）。
8. 承接 BC obs-1..10 + A 二路 obs-6/7/10：全部打磨/口径级，
   本轮无翻案。`library.recentProjects` 的 Widget.lalb 死路径项为
   他方并行会话写入（沿二路 obs-10 口径），本轮验后还原为
   OMPCULL×2（本轮真实写入）。

## 九、证据清单

截图（`.work/gui-acceptance/lumen-culling/omp/`，16 幅）：

| # | 文件 | 内容 |
|---|---|---|
| 00 | omp-00-grid-prestamp.png | 导入后分析前：8 缩略图零徽章（默认中性面） |
| 01 | omp-01-badge-grid.png | a) 双连拍组 n/m + best 星 + 可能模糊 |
| 02 | omp-02-badge-zoom.png | a) 徽章区裁切 |
| 03 | omp-03-sharp-album7.png | b) sharpness≥50 → 7 张 + chip |
| 04 | omp-04-burst-nocount.png | b) hasBurst 计数缺席 + 单击网格不动 |
| 05 | omp-05-ctxmenu.png | c) 右键菜单五项（含快速选片/转为堆栈） |
| 06 | omp-06-cull-face.png | c) 选片 face 全貌（头栏/单 Pane/胶片条/帮助行） |
| 07 | omp-07-cull-blur.png | c) blur 行提示条「清晰度 16 可能模糊」 |
| 08 | omp-08-compare.png | c) C 并排对比（左锐右糊） |
| 09 | omp-09-grpjump.png | c) ↑ 组跳 → 前组首 burst-b3 |
| 10 | omp-10-zoom100.png | c) Z 100%（滚动条放大态） |
| 11 | omp-11-editor.png | c/f) D 进编辑器主链面 |
| 12 | omp-12-rawdecode.png | e) RAW 解码输入色彩四行读出 |
| 13 | omp-13-nosubject.png | d) 无主体 toast + refine 禁用 |
| 14 | omp-14-settings-cache.png | e) 缓存上限 + fineAuto 双行 |
| 15 | omp-15-grid-rating.png | c) 5 星落库 + 高分组=1 |

DB 读数（终态）：8 行 `analysis_version=1`，sharpness 89.4×7/15.8×1，
`burst-a2 rating=5`，`single-blur flag=1`，serial 全 SER-OMP1，
SubSec .100/.200/.300 全对。MCP：33 闭集 + controlNotHeld/invalidParams
typed + acquire/release 往返（stdout 行内证据）。

## 十、还原声明

- app 已退（PID 18133 自出，`kill` 后 pgrep 零残留）；caffeinate/
  xcodebuild 自出进程清零；stale 双实例（4648/9658，他方 `open -a`
  误起旧容器）已杀并在报告记因。
- UserDefaults：`mask.fineAuto` 还原缺席；`mcp_server_enabled`
  还原删除；`library.recentProjects` 还原 OMPCULL×2；
  `mcp-endpoint.json` 残留已清（lock 为既有物未触）。
- SmartAlbums 探针四 JSON 已删（还原用户原单一 UUID.json）。
- 跟踪面：跟踪面干净（截图目录 `.work/gui-acceptance/` 按仓策略 gitignored，正本在工作树——与 lumena/lumenb evidence 同口径）；本报告 untracked 落 `.work/`（不 commit）；零源码改动；HEAD `01249a6f` 未动。
- 探针工程 `/tmp/omp-cull/`（OMPCULL.lalb + fx/ + shot-*.png + *.py）
  与 `/tmp/omp-copy/` 留 `/tmp` 即弃，未入库。
- 构建：`-tuist` 容器增量至含 T4（07:21 后二进制，
  `settings_maskrefine` 6 命中亲证）；`-dgzsvdww` BUILD-HANDOFF 正本
  未触。
- 全套 `--all`：BC 独立验收已跑 4204/41/0（本终审为 GUI 轮，
  未重跑，机器级单重活纪律）。
