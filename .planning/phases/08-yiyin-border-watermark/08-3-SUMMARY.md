# Plan 08-3 Summary — 集成、导出配置与签核

**Status:** Complete（T0-T6 全部执行；终轮全套 **973/6skip/0fail**，Phase 8 净增 109）
**Executed:** 2026-09-25（ZCode subagent worker）
**Commits:** T0 `49faec4` fix(iop): watermark row composite alpha factor → T1 `4d2bf6f` feat(app): yiyin borders section + dual-instance coordination → T2 `630f5fe` feat(core): capture-metadata walk six fields + orientation E2E → T3 `2de8645` feat(core): YiyinExportSettings + production joint-context wiring + preset face → T4 `3b4a6be` test(iop): yiyin E2E round-trip + four-state matrix → T5 `73e29e0` docs(work): GUI acceptance + perf ledger → T6（本提交：签核材料 + 移交 + 收口）。未 push（用户指令：本地 commit 即完成态）。

## 交付内容（对照 plan 验收标准）

- [x] **T0（08-2 验收必修）**：`yiyin_watermark_row` kernel alpha 因子修正——CG 8-bit sRGB
  premultipliedLast = 编码域预乘（探针实证：白字 r==a），kernel 改为编码域 un-premultiply +
  **线性 coverage** 因子（旧版把 coverage 二次过 EOTF，AA 边缘 0.5→0.214 文字偏瘦）；
  `testRowBitmapInk` 注释 + D-08-2-7 更正；golden 冻行位图不受影响（D-08-3-T0-1）。
- [x] **T1 印框节整合 + 双实例联动**：`YiyinPanelView` 双节完整（背景模式/颜色/模糊量/主图
  占比/最小边距/圆角 toggle+滑杆/投影 toggle+滑杆/宽高比 7 预设/竖转横/自适应蒙层——yiyin
  滑杆范围 1-100/0-100/0-50 verbatim）；**session sibling lookup**（`instanceRecord`/
  `siblingInstance`）两节各提交各实例（交错编辑恰各自 1 commit、⌘Z 独立还原——交错测试钉）；
  「应用默认印框」一键手动入口（D-08-CONTEXT-4）+ 缺记录铸造兜底；双 provider 注册同一视图；
  28 键 zh+en catalog（L025）。
- [x] **T2 CaptureMetadata decoder walk**：六字段（FocalLenIn35mmFilm/ExposureProgram/
  ExposureBiasValue/MeteringMode/WhiteBalance/LensMake）真实 RAW 接通——CR3/NEF/ARW 与独立
  ImageIO 读逐一对照 + EXIF 枚举值域方向断言；LensMake 字典更正（SDK 无 Aux 常量——
  D-08-3-T2-1）；旧档兼容 JSON 解码 + additive 往返；**orientation=6 端到端**：跨图 byte-exact
  （cross-graph maxDiff 0.0）+ 逐字节确定性 ×2 + band 白锚点探针。
- [x] **T3 YIYIN-08 导出配置模型**：`YiyinExportSettings`（Codable 独立值类型——mode 三态 +
  DPI + validate 边界 1...100_000px / 1...2400dpi + 纯 `targetSize` 数学永不放大）+ 与水印
  参数正交（EXP-07 多规格面，paramsHash 不动测试）+ `AppError.invalidParameter` additive；
  **版式分辨率无关**：`YiyinLayout.layout` PREVIEW(2560) vs 2× 全幅归一化记录相等（20+ 字段
  真比较 + 舍入带容差）；**预设捕获/应用渲染逐字节等价**（paramsData 捕获 → 新实例应用 →
  渲染 byte-equal，Phase 12 `.lightamer-preset` 接口面零新 API）；**生产联合上下文接线**
  （D-08-3-T3-2：renderCurrentChain 注入 captureExif/logo/联合记录——borders 生产预留水印
  band，08-2 移交义务闭环）；EXP-05/EXP-03 消费点注记落 DECISIONS + manifest。
- [x] **T4 E2E + sidecar round-trip**：开图→配印框→配水印→⌘Z 逐级（每步 byte-exact：
  #1==borders-only、#2==pristine）→ sidecar persist（flushNow）→ **跨重启活体**（fresh
  registry/cache/metal ×3 pass 逐字节）+ restore projection == live set + 无 drift/unknown op；
  **4 态矩阵**：仅框/仅水印/双开/双关——双关 == 无实例基线逐字节（禁用==无实例 E2E 面）、
  活动态两两互异（真比较）。
- [x] **T5 GUI 验收轮（真机）+ perf 落账**：DSC00012.ARW 全程 AX 语义操作——应用默认印框
  （ΔR 31.15%）→ 水印行（SONY logo PDF + α 7rm5 归一化实机，ΔR 26.29%，band 墨迹 18.76%）
  → 模糊背景+自适应蒙层（27.79%）→ 菜单撤销 ×2 逐级还原（1.70%/1.65%）；**knownRegions
  证伪**（zh.lproj 全 699 键编译在案——08-2 备注误报，零修复）；Manual-Only 表 5 行；
  `.work/08/perf.md`（拖动 median：borders solid 154.4ms / radius+shadow 361.4ms /
  watermark 800.8-814ms；只记录不设门）。
- [x] **T6 Phase 8 签核 + 移交**：`08-VALIDATION.md`（SC#1-5 对照 + Per-Task Map 08-1/2/3
  全任务 + Manual-Only 汇总 + 遗留注记）；`08-DISCUSSION-LOG.md` 终节（SC 证据指针 +
  **Phase 9 移交清单**：EXP-05 消费点接口面 / YiyinExportSettings 应用缝 / YiyinLayout
  复用面 / 遗留对表）；REQUIREMENTS YIYIN-01..08 翻账 **Delivered ×8**（含 v1 口径注记）；
  manifest Phase 8 golden 总账节；TODO/GOAL-STATE 收口；C 档第 3 停执行记录（本节）。

## 验证数字

| 面 | 数字 |
|---|---|
| 终轮全套 | **973 tests / 6 skipped / 0 failed**（基线 960 → 973 +13：T1 +3 / T2 +3 / T3 +5 / T4 +2；T0/T5 零净增——修正与文档轮） |
| 每任务提交时全套 | 960/0（T0）→ 963/0（T1）→ 966/0（T2）→ 971/0（T3）→ 973/0（T4）→ 973/0（T5 复跑） |
| kernel alpha 修正 | 08-2 验收必修闭环；T0 双向归因（stash 对照 pre/post 均绿——GoldenColor flake 既有族非引入） |
| decoder walk | CR3/NEF/ARW 六字段 vs 独立 ImageIO 读逐一相等；orientation=6 cross-graph maxDiff **0.0**（byte-exact） |
| 导出模型 | 校验边界 12 断言 + targetSize 数学（fit/竖图/永不放大）+ 归一化布局 20+ 字段相等 + 预设渲染 byte-equal |
| E2E | ⌘Z 逐级每步 byte-exact；跨重启 ×3 全等；4 态矩阵双关==基线逐字节 |
| GUI ΔR | 31.15% / 26.29% / 18.76%（band 墨迹）/ 27.79%（模糊）/ 撤销 1.70%/1.65% |
| zh 编译 | 699 键 bundle 实证（knownRegions 误报证伪） |

## 遗留 / 风险（对表，正本 DISCUSSION-LOG 终节）

1. **zoom ROI 窗口化 × 联合布局**：尺寸卫兵优雅降级（band 预留缺失）——导出恒全帧不受
   影响（D-08-3-T3-2）；zoom 预览候选 v2。
2. **v2 旋转/自由拖拽**（YIYIN-03/04 完整深度）：`rotation?` 参数位预留。
3. **Manual-Only 5 行**：字体下拉手感 / Logo 视觉 / 蒙层观感 / 超长文本 / blur Debug 首渲
   延迟——人工终审随 verify-work。
4. **GoldenColor 既有 flake**（L018 族）：本轮 stash 双向归因非 yiyin 引入；既有行跟踪。
5. **模糊腿 Release 性能**：Debug 极值在案；Phase 11 导出腿复测。
6. **zh-Hans 空目录噪音**：无害，不清理（避免目录级 diff）。

## 关键文件

- `LightamerIOP/Sources/Yiyin/YiyinKernels.metal`（T0 alpha 修正）+
  `WatermarkModule.swift`（makeJointLayoutRecord 公共面）
- `App/Sources/Lightamer/Yiyin/YiyinPanelView.swift`（双节面板）+
  `State/PipeCoordinator.swift`（instanceRecord + injectYiyinRunContext）+
  `State/InspectorState.swift` + `UI/Inspector/IOPPanelProvider.swift`（sibling lookup）
- `LightamerCore/Sources/Decode/RAWDecoder.swift`（walk 六字段）+
  `Foundation/YiyinExportSettings.swift`（新）+ `Foundation/AppError.swift`（invalidParameter）
- `Tests/LightamerTests/{YiyinMetadataWalkTests,YiyinExportSettingsTests,YiyinE2ETests}.swift`（新）+
  `PanelWiringTests.swift`（+3）+ `YiyinWatermarkTests.swift`（注释更正）
- 签核材料：`08-VALIDATION.md` + `08-DISCUSSION-LOG.md`（新）+ `REQUIREMENTS.md` 翻账 +
  `input/golden/manifest.md` 总账节
- 决策正本：`08-3-DECISIONS.md`（D-08-3-T0-1/T1-1/T1-2/T2-1/T3-1/T3-2/T5-1 + 实测备注）
