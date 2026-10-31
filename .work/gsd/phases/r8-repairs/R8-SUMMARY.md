# R8 SUMMARY(E-1 几何编辑即崩调查修复批;issue #16)

- **病灶**:几何编辑即崩——`PixelPipe.swift:1676` precondition
  `negotiated ROI violated at pos 0`(omp R7 终审 E-1,error 级;HEAD `a0206e83`
  与基线 `f783f1c3` 双崩 = 既有缺陷,阻塞一切几何编辑实机验证)。
- **根因**:`forwardWalk` 种下 `roi = entry` 后不再写,composite 的
  `window = basePipe.roi` 取到 entry 帧;激活几何模块(SWAP_XY flip / crop)下
  base 平面 = walked 形、window = entry 形 → terminal sub-run 协商错帧 →
  pos 0 逐像素断言双值不匹配。潜伏引入 = `9d1f4fa9`(09-23 T4 composite 骨架),
  用户可达化 = M9-3 crop tool strip(M9-3/M9-4 嫌疑线均排除,见 DECISIONS §D-R8-1)。
- **修法**:`forwardWalk` 末行 `roi = roiWalk`(发布协商终帧);恒等链零漂移。
  封存面豁免:PixelPipe 仅 2 hunk(属性 doc + walk 尾同步),M9-4 prepareChain
  先例形申报(DECISIONS §D-R8-2)。
- **修复 commit**:`a6b692bd`(`fixes #16`)。

## 逐 T 战果

| T | 内容 | 产物 | 证据 |
|---|---|---|---|
| T1 | 复现收窄:机制定罪(源码亲核 + git 考古),排除 M9-3/M9-4 | DECISIONS §D-R8-1 | 崩溃 ips 堆栈(5 层 sub-run + base case 直返帧)逐帧对上;omp 双机实测沿用 |
| T2 | 最小缝修复 + 回归 3 法(修前探针红 48x32-vs-32x48 / 修后三绿) | commit `a6b692bd` | LayerCompositeTests 531/5/0(LAYERS bundle 全量零回归) |
| T3 | 实机 AX 走查:CW90×2+CCW90 存活、转置渲染正确、crop overlay 自适应、sidecar 逐次落盘(items 4) | /tmp/r8walk/ 截图 5 张 | DECISIONS §D-R8-5;crop 拖拽/滑杆挂账 omp(GUI 占用降级) |
| T4 | 全套 --all(monitor 伴跑,G4 透明越门) | `all-runs/r8-all.log` | 终值见下 |
| T5 | 收口:issue #16 + 本账 + DECISIONS | — | — |

## T4 全套终值

**4438/34/0** = 基线 4435/34/0 ⊕ Δ+3(恰 = LayerCompositeTests 新增 3 法),
零 fail、零 MEMFAIL(峰值 RSS IOP 6141MB / Export 4621MB < 8192 运行门),
全套轮 4043s。

| bundle | 终值 | 对照 r7 |
|---|---|---|
| IOP | 814/1/0 | 同 |
| IOPParity | 565/10/0 | 同 |
| Layers | **531**/5/0 | 528 → +3(本批) |
| Library | 785/4/0 | 同 |
| Sessions | 285/4/0 | 同 |
| Export | 385/4/0 | 同 |
| App | 1073/6/0 | 同 |

**两轮环境型事故登记**(与修复零关系,处置留证 `all-runs/`):

1. 第一次全套(`r8-all.log`):IOP 814/1/**59**——全部
   `functionNotFound("default.metallib in LightamerIOP.framework")`。根因 =
   本批第一次 build-for-testing(修前探针轮,测试侧 `.texture` 笔误 52 error
   失败)留下半成品 metallib,后续两次成功 build 增量判定 up-to-date 未重做。
   处置:全量重建(metallib mtime 刷新 07:17:54)→ IOP bundle 单跑
   814/1/0 绿(`r8-iop-after-rebuild.log`)→ 重跑全套。
2. 第二次全套(`r8-all2.log`):App bundle no-total-line 截断(658s,前六
   bundle 连跑 3400s+ 后宿主环境劣化;VersionSwapTests 一法断言失败后宿主
   中途死亡,无 Suite 收尾行 = L055 截断签名)。处置:VersionSwapTests 单跑
   11/0/0 绿 → App bundle 单独净轮 **1073/6/0 绿**(`r8-app-rerun.log`,
   627s/2832MB)。终值采用「全套六 bundle + App 独立净轮」口径,逐 bundle
   与 r7 基线可对账(仅 Layers +3)。

## 纪律面

- 封存面:PixelPipe 2 hunk 豁免申报(唯一触面);其余封存件零 diff(commit 前
  diff 范围 = PixelPipe.swift + LayerCompositeTests.swift 亲核在案)。
- commit-per-task:修复独立 commit(`a6b692bd`),账本独立 commit(免 issue ref)。
- BUNDLE-MAP 行内计数 10→13 同批登记(LAYERS / LayerCompositeTests.swift)。
- G4 透明越门登记:DECISIONS §D-R8-4(非静默;monitor 伴跑零 RSS-KILL)。
- 实机走查未触个人肖像目录;供件只读拷贝于 /tmp/r8walk/(不入库);
  `library.recentProjects` defaults 探针污染已清。
