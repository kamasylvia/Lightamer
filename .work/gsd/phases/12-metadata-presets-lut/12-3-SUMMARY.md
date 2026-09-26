# Plan 12-3 — Summary

**Date:** 2026-09-26
**Status:** Complete（执行申报，待验收；T5/T6 由续班 executor 收尾——前任死于配额中断，WIP 经 orchestrator 契约对齐修复后续接）
**Wave:** 2（与 12-2 并行，零交集；依赖 12-1 字段面）
**Requirements:** META-04（XMP 同步）、META-03（关键词层级）

## 交付面

| 任务 | 交付 | Commit | 证据 |
|---|---|---|---|
| T1 | XMPWriter 薄封装（F1 形态）：四字段面 + Bag 构造纪律 + lr namespace 注册前置 + 全空 nil + project 映射（reject→-1 / pick 无位） | `76dde86` | XMPWriterTests 8（字节 golden 结构/序 + round-trip 全字段 + Bag-vs-Seq 反例 + 全空 nil） |
| T2+T3 | 容器注入缝单 commit：JPEG APP1（64KB typed 上限）+ PNG iTXt（pre-IDAT 宿主事实位）+ TIFF tag 700（IFD 重组，风险预案未触发） | `e5e3a21` | XMPContainerInjectorTests 9（三格式正锚 + 宿主 round-trip + 上限/误用/双注入 typed + CRC32） |
| T4 | ExportChainBuilder.mountXMP 后置挂载（XMPMountOutcome 四态 tally，导出永不因 XMP 硬失败）+ 六格式矩阵 | `12c6afa` | XMPExportMatrixTests 5（三正锚 + 三反锚 byte-scan + reject=-1 + 空 sidecar skip + 注入失败降级不阻塞） |
| T5 | 第三方 .xmp 只读导入：XMPImport（Core 解析，typed 三错）+ MetadataService allowHierarchical 门 + GUI「导入 XMP…」菜单/对话框/alert + zh catalog 6 键 + PNG replace 语义契约修正 | `7c06fa2` | XMPImportTests 8（lr verbatim / dc-only 降级 / lr 胜出 / rating-reject 映射 / label 反查 / writer round-trip / typed 错误 / 文件只读零触碰）+ GUI 走查 4 证据 `12-3-01..04` |
| T6 | 全量回归终轮 + SUMMARY/DECISIONS/TODO/PROGRESS 收尾 | 本提交 | 1364/6skip/0fail（424.6s） |

## 测试演变

1334/6skip/0fail（12-2 收尾基线）→ **1364/6skip/0fail**（+30：XMPWriterTests 8 + XMPContainerInjectorTests 9 + XMPExportMatrixTests 5 + XMPImportTests 8）；终轮 424.6s（touch Tests + build-for-testing 重编复跑），0 fail、无 flake。

## AC 逐条自检

- [x] **XMPWriter 薄封装（F1）**：序列化端宿主事实（D1）裁定形态；四字段面 + Bag 纪律（`.arrayUnordered`，CFArray 直塞 Seq 反例钉死 D2）+ lr 注册前置 + 全空 nil；字节 golden（x:xmpmeta/rdf:RDF/Bag 结构与键序）+ round-trip 双向全绿。
- [x] **注入缝**：JPEG APP1/PNG iTXt 正锚字节 golden + 64KB typed 降级；**TIFF tag 700 正锚全绿**（D8，降级预案未触发，例外集零新增）；PNG pre-IDAT 宿主事实位（D6）+ replace 语义（D7）。
- [x] **六格式矩阵**：JPEG/TIFF/PNG 正锚 + HEIC/AVIF/WebP byte-scan 反锚（防宿主漂移）；reject → Rating -1、pick 无正位文档化（D4）；注入失败降级不阻塞导出（D9 四态 tally）。
- [x] **只读导入**：lr:hierarchicalSubject 全量 verbatim / 仅 dc:subject 升单级诚实降级 / lr 胜出（D13）；写入经 `MetadataService` 唯一入口（allowHierarchical 门 D12，`MetadataController.setImportedKeywords` 单 GUI 路由）；原 `.xmp` 只读零触碰（单测字节断言 + 走查 shasum/mtime 双证）；GUI 对话框走查（下节）。
- [x] **红线零触碰**：原片旁 `.xmp` 永不读写删——本 plan 全部写路径只落导出产物与用户显式导入的 sidecar（mountXMP 唯一写目标 = 导出目的地；XMPImport 全部入口只读）。
- [x] **收尾**：全 suite 0 fail（1364/6/0）；每任务独立提交 + 边界查 config 开关（T5/T6 各查，`auto=true`/`paused=false`）；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘。

## GUI 走查记录（控制台解锁，2026-09-26 22:13-22:22；真实 app + `~/la-uat-session` + AX/cliclick/键盘驱动）

app = DerivedData 22:00 build-for-testing 产物（含 T5；任务书路径 `build/` 为 01:31 旧构建，详 DECISIONS D14）。fixture = `/tmp/la-uat-import.xmp`（第三方手写包：Rating 4 + Label Green + lr Bag `Nature|Flower|Rose`/`UAT|Import12-3`——非 XMPWriter 产物，验生态字节面）。

1. **12-3-01-session-open**：新实例打开 la-uat-session（3 图入网格；12-2 过滤栏同屏在位）
2. **12-3-02-import-menu**：网格选中 DSC00012.jpg → toolbar Import 菜单展开——「导入 XMP…」可用 + 「导入」（Phase 9 占位）禁用灰显，两态同框实证
3. **12-3-03-after-import**：fileImporter（.xmp UTType 过滤生效，类型列显示「XMP Sideca…」）选 /tmp/la-uat-import.xmp 打开 → **grid overlay 即时点亮**：DSC00012.jpg 左下 4 颗实星 + 右下绿色色点
4. **12-3-04-single-overlay**：单图态编辑器 + Inspector keywords 编辑行可见（导入字段的编辑面同链可达）

**sidecar 字段断言**（`~/la-uat-session/DSC00012.jpg.lra`，导入前四字段全 None 的干净基线）：`rating=4`（verbatim）、`colorLabel=3`（Green→绿，与 overlay 色点一致）、`keywords=['Nature|Flower|Rose','UAT|Import12-3']`（lr path verbatim，`|` 层级经 allowHierarchical 门直存）、`flag=nil`（包无 -1）——与 XMP 包四字段逐一对应。

**源文件零触碰**：`/tmp/la-uat-import.xmp` 导入后 667 字节 / mtime 22:14（导入动作 22:21）不变。

### Manual-Only 登记（合成驱动限制，人工确认项）

| # | 项 | 说明 | 覆盖状态 |
|---|---|---|---|
| F-12-3-1 | 多选批量导入的 GUI 合成 | fileImporter 选包时 ⇧ 多选图不可合成（12-1 F-12-1-1 同款）；多 relPath 一次调用语义已由 MetadataService 多目标用例 + setImportedKeywords 单测面钉死 | 服务面 ✅ / ⇧ 多选手势待人工 |
| F-12-3-2 | typed 错误 alert 三态观感 | unparsableXMP/noFields/unreadableFile 的 alert 呈现未逐一走查（本轮走查走 happy path）；三态路由代码同路径（`importXMP` 单 catch 逐 case），错误面文案 zh catalog 在（alert_xmp_unparsable/no_fields/unreadable） | 代码面 ✅ / alert 观感待人工 |

## 偏离与注记

1. **续班交接形态**：T1-T4 三提交（`76dde86`/`e5e3a21`/`12c6afa`）完成于配额中断前；T5 主体 WIP 由 orchestrator 完成契约对齐修复（4 处，D11）+ 全套验证门（1364/6/0）后，续班 executor 提交（`7c06fa2`）并收尾 T6。DECISIONS 的 T1-T4 段由续班依源码 + commit 考古 reconstruct（前任未落盘）。
2. **走查 app 来源偏离**（D14）：任务书 `build/Build/Products/Debug` 为 01:31 旧构建，改用 DerivedData 22:00 build-for-testing 产物（与全套验证同一二进制）。
3. **PNG 契约修正随 T5 提交**：`e5e3a21` 的 PNG refuse 语义与宿主自产 XMP 事实冲突（fresh encode 即带宿主 iTXt），T5 批改为 replace 语义（D7）——测试同步重写（`testPNGMisuseAndReplaceSemantics`）。
4. **走查环境残留处理**：接管时 19:02 旧实例挂着 09-UAT 的「部分粘贴调整」sheet（Esc 不可达）——AX 定位「全不选」→「好」以零字段安全关闭后退出换新实例；旧实例为前任/UAT 遗留，非本 plan 产物。
5. **合成键盘 IME 限制**（12-2 D14 同款）：NSOpenPanel Go-to-Folder 的 keystroke 被中文 IME 吞（「/甜品/拉-沙特-import。xmp」实证），改剪贴板粘贴绕过——走查方法学注记，非产品缺陷。
