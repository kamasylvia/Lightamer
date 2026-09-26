# Plan 11-05 SUMMARY — Phase 11 签核收口（W5：前置修复 + E2E 终验 + perf 记录 + VALIDATION + 移交 + 翻账）

> 执行：executor subagent worker（2026-09-26 上午轮）。config 开关全程 `auto=true / paused=false`，任务边界 ×8 复核。
> 提交链：`9439b59`(T0a) → `80fc0bb`(T0b) → `d9dfa9b`(T0c) → `8700b61`(T0d) → `065f367`(T1) → `efa3e5d`(T2) → `ed5003b`(T3) → 本翻账收口提交(T4)。未 push。
> **终轮全 suite：1258 tests / 6 skip / 0 fail**（touch + build-for-testing 重编复跑，449.8s）。
> **11-VALIDATION：`status: validated` + `nyquist_compliant: true`。**

## 战果总览

| 任务 | 交付 | Commit |
|---|---|---|
| T0a | flake 稳定化：4 态矩阵「双关==基线」byte-exact → 解码像素容差 1/255 + 尺寸相等 + sanity 错位红断言（真回归可检性保留） | `9439b59` |
| T0b | `Scripts/test-direct.sh` 退出码污染修复：判据 = Executed 行 + 失败行双见证，宿主退出态仅参考打印（RC 预置防 set -u） | `80fc0bb` |
| T0c | F-11-04-1：`ExportState.targetRelPaths` realpath(3) 双拼写匹配（L027 先例）+ `canExport` gate 改以实际 targets 判定 + `ExportTargetsTests` 4 | `d9dfa9b` |
| T0d | convertTexture L029 休眠镜像修复（`.downMirrored`）+ fast/fallback 双腿 parity 测试（ExportEncoderGoldenTests 16→17） | `8700b61` |
| T1 | `ExportPhaseE2ETests` 3：1 源×8 变体一次队列动作（六格式×三尺寸×四色域×五位深）全落盘逐文件对照 + R1/R5 探针终判 + 同目录二导不互覆 + 真队列有印框 round-trip + tmp 零残留；反模式扫描 Export 新面 13 文件零命中 | `065f367` |
| T2 | `ExportPerfProbeTests` 2 + `.work/11/perf.md` 计量总账（只记不设门）+ 模糊腿 Release 复测（08-3 遗留 #5 关闭） | `efa3e5d` |
| T3 | `11-VALIDATION.md`（SC#1-5 三列证据 + Per-Task Map + EXP 注记行 + Manual-Only 4 行 + status）+ 11-DISCUSSION-LOG 终节（Phase 12 移交清单五条 + 遗留对表 14 行） | `ed5003b` |
| T4 | 全套回归终轮 1258/6skip/0fail + REQUIREMENTS EXP-01..08 Delivered ×8 + TODO/GOAL-STATE 同批收口 + 本文档（C 档第 3 停执行） | 本提交 |

## 终轮计数与基线演变（分账）

1133（Phase 10 末）→ **+54** 11-01（1187）→ **+33** 11-02（1220）→ **+15** 11-03（1235）→ **+13** 11-04（1248）→ **+10** 11-05（**1258**：ExportPhaseE2ETests 3 + ExportTargetsTests 4 + ExportPerfProbeTests 2 + parity 1）。终轮 449.8s / 6 skip / **0 fail**。11-04 收尾轮唯一 fail（11-03 既有 flaky）经 T0a 稳定化后：单独跑三轮绿 + 终轮 0 fail。

## AC 自检（plan 验收标准逐条）

- [x] E2E：一源多规格一次队列动作全落 Output/、命名不互覆（`-1` 递增）、有印框全链 round-trip（SC#3/SC#4/SC#5 测试锚 = `ExportPhaseE2ETests` 三测）
- [x] R1/R5 探针终判落 DECISIONS↔VALIDATION（HEIC 10 / AVIF 10 / **12→10 降级锚**；XMP 六格式缺席 + properties EXIF 路径 + WebP RIFF 锚；奇数 33×17 + 257×171）
- [x] 反模式扫描（Export 新面 13 文件 + tmp 残留）零静默命中
- [x] `.work/11/perf.md` 计量总账齐（只记不设门 + Phase 15 清算注记七行 + 08-3 模糊腿遗留 Release 复测关闭）
- [x] `11-VALIDATION.md`：SC#1-5 三列证据（零无证据 ✅）+ Per-Task Map + Manual-Only 汇总 + status 判定（**SC#2 显式引用 priority API 事实修正，checker M3 可追溯**）
- [x] Phase 12 移交清单五条（recipe→preset / WebP mux / XMP 字段面 / yieldsToEditor+perf / 元数据汇合点）+ 遗留对表落 DISCUSSION-LOG
- [x] 全套回归终轮（touch 重编复跑）0 fail；基线 1133→1258 分账在案
- [x] REQUIREMENTS EXP-01..08 翻账 Delivered（含注记行）+ TODO/GOAL-STATE 同批收口（§3.1）；**C 档第 3 停已过（夜间授权先例 D-07-3-T5-1/D-09-05-T1-1，记录在 VALIDATION Sign-Off + DECISIONS）**；11-05-SUMMARY 落盘；无 /tmp 过程产物入工作区

## 证据清单（一手）

- E2E 落盘清单：`ExportPhaseE2ETests.testOneQueueActionLandsEveryVariantWithoutCollision` 断言集 = 名集合精确（`PHASE11_0001{,_jpeg.jpg,_512.png,_tiff.tif,_384.heic,_webp.webp,_256.avif,_257.tif,_avif.avif}`）+ 尺寸向量（1024×683 / 512×342 / 384×256 / 256×171 / 257×171）+ 位深（8/16/32/10/10/**10←12**/16/8）+ XMP 全缺 + ICC 载体。
- 反模式扫描：`grep -rn "TBD|FIXME|XXX|HACK|PLACEHOLDER|coming soon|notImplemented|unimplemented|// stub|fatalError|TODO"` 于 `LightamerCore/Sources/Export/`（10 文件）+ `App/Sources/Lightamer/Export/`（3 文件）= **零命中**；tmp 残留断言三测全绿。
- perf 数字：见 `.work/11/perf.md`（§1 分段 / §2 内存对账 / §3 32f 尺寸 / §4 编辑并发结构链 / §5 模糊腿 Release / §6 Phase 15 挂账）。
- Release 复测跑批：`build-for-testing -configuration Release`（默认容器）→ 直启宿主 + `-XCTest 'YiyinBordersTests/testPreviewDragInitialTimingRecorded'`，`PackageFrameworks` 显式入 DYLD 路径 + Lightamer Dev 重签（技巧入 DECISIONS D4）。

## 偏离之处

1. **plan 外前置任务（T0a-T0d）**：验收裁决与挂账处置（协调者指令 #1/#2）要求在 T1 前落地，按独立 fix 提交执行；`test-direct.sh` 退出码修复与 F-11-04-1 均为 11-04 验收移交项，属收口批义务（plan 纪律节已预写），非范围蔓延。
2. **F-11-04-1 修复位置**：GOAL-STATE 候选写「openSession 入口 resolvingSymlinksInPath」——实测 Foundation 不解析前缀链接（L027 在案），改走 SessionTreeScanner 同款 realpath(3) 双拼写匹配；修复点收敛在 ExportState 单函数（可单测），不动 SessionCoordinator。
3. **VALIDATION 的 SC#5「测试锚」列**：post-actions 无独立单测类，以「注入面自查实录（11-04）+ 队列 settle 语义单测」组合作为锚——证据为执行期实录而非测试文件，已在表内注明出处。
4. **模糊腿 Release 复测的数字解读**：blur+overlay Release ≈164s 与 Debug 首渲冷值同量级——代价主体是 21-pass 分解固有算力而非 PSO 冷启动；SC 门 = 观感（08-3 GUI 轮已过），本记录不设门，优化杠杆挂 Phase 15。
5. 终轮数字 1258 早于 VALIDATION 落盘预测，终轮实测一致（1248+10）；VALIDATION 内时间为实测回填。
