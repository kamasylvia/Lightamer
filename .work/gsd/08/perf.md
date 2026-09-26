# Phase 8 性能落账（.work/08/perf.md — Plan 08-3 T5）

> **只记录不设门**（RESEARCH §5；ROADMAP §Phase 10 无性能 SC）。SC 门 = 真机拖动观感
> （GUI 验收轮已过：面板提交→视口即时重渲）。全部数字 = Debug 构建（PSO 冷/无优化）、
> 本机 M4。正式 Release benchmark 留 Phase 11 导出链接线时一并复测。

## PREVIEW 拖 yiyin 参数（命中面 = 终端段子 run，上游全 cache hit）

| 腿 | median | 样本 | 来源 |
|---|---|---|---|
| borders solid（rate 编辑热路径，全缓存命中） | **154.4 ms** | 探针 | BORDERS-PERF（YiyinBordersTests.testPreviewDragInitialTimingRecorded） |
| borders solid + radius + shadow | **361.4 ms** | 探针 | 同上 |
| borders blur + overlay（全链首渲） | **163.9 s** | 探针 | 同上——Debug + 21-pass 分解 + PSO 冷；模块腿 proxy+blur ≈ 7.3s @5.4Mpx 画布（08-1 记录）；**SC 门 = 观感，已过 GUI 轮**（真机首渲 ~2min 内、后续参数调全缓存命中） |
| watermark 参数拖动（两行 + SONY logo，全缓存命中面） | **800.8 / 814.0 ms** | 5 样本 773-943ms | WATERMARK-PREVIEW-DRAG（08-2 T7 / 08-3 T4 复测一致）——主嫌疑 CoreText 排版首 MISS + rgba8 上传 Debug 开销 |

## 文字冷排（CoreText）

- 逐行冷排 **ms 级**（08-2 T4 行盒公式交叉量测语境；排版缓存命中后 0 GPU 外开销）。
- 排版缓存键 = (模板串 ⊕ 字体属性 ⊕ 行高)——参数微调（opacity/lineSpacing 等）时
  行位图全 HIT（YiyinWatermarkTests.testRenderCacheMissHitAccounting 记账：1MISS→1HIT→3MISS）。
- EXIF 派生 slot 值折叠进缓存键（L013）——换图/换 EXIF 自动 MISS，无陈字风险。

## 批量吞吐估算（Phase 11 EXP-06 预算输入，非实测）

- 每图 yiyin 增量 ≈ 模糊腿（降采样 proxy + Deriche 多 pass + 上采）+ 文字冷排（~ms/行）
  + 2 个合成 dispatch——RESEARCH §5 估 **<200ms/图 @24MP（Release）**；Debug 实测不可比
  （模糊腿 163.9s 全链为 Debug+PSO 冷极值，模块腿 7.3s），维持估算、Phase 11 复测。
- 100MP FULL：画布扩展 ~1.23× 面积（rate 90）；窗口化照旧；yiyin 的 >10240px 遮罩
  降采样护轨不需要（恒窗口化渲染）。

## 关联档案

- 08-1 初测：`08-1-SUMMARY.md` 验证数字表（solid ≈250-270ms / radius+shadow ≈280-380ms / blur 腿分解）。
- 08-2 初测：`08-2-DECISIONS.md` 执行期实测备注（水印拖动 800.8ms）。
- GUI 真机：`.work/gui-acceptance/FINDINGS.md`「Plan 08-3 T5 GUI 验收轮」。
