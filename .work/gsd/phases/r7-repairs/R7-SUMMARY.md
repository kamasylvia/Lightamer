# R7 SUMMARY（M9 站后尾项清偿修复批；issue #15）

- **基线**：HEAD `f783f1c3`，全套 4428/34/0。
- **终值**：全套 `--all` **4435/34/0**（= 4428 + Δ7，恰落任务书预估带 4431..4434 上沿
  +1——第 7 法为 T4⑤ 清键回归，任务书估算后追加），4081s，七 bundle 零 fail、
  零 MEMFAIL（峰值 RSS IOP 6521MB < 8192 运行门）。日志 = `all-runs/r7-all.log`。
- **拆分**：IOP 814/1/0 · IOPParity 565/10/0 · Layers 528/5/0 · Library 785/4/0 ·
  Sessions 285/4/0 · Export 385/4/0 · App 1073/6/0。

## 逐 T 战果

| T | 内容 | 产物 commit | 定向 |
|---|---|---|---|
| T1 | M9-3 N-1 端点拖拽 release 提交门（对称臂 + dragMoved 门） | `838314b2` | App UprightGuides 9/0/0（+1） |
| T2 | M9-3 N-2 SWAP_XY 桥转置重拟（镜像代数抵消，DECISIONS §2 证明） | `8211b86f` | App CropToolRotation 9/0/0（+2） |
| T3 | M2-6 纵深：obs-4 = raster seed 语义值（按设计）；m-1b = AX 合成伪影登记；读链/联动回归双向钉死 | `edd66755` | App DrtPanelModel 13/0/0（+2） |
| T4 | 卫生包五小件（清扫 API+接线 / 注释勘正 / vpError+midpoint 死码 / HP5 note+MANIFEST 9/9 / paper_grade 清键） | `082178f2` | App AdjustmentTransfer 10/0/0（+1）+ FilmPanelBW 6/0/0（+1）+ IOP 2/0/0 + IOPP 2/1/0 |
| T5 | 全套 --all + 本账 + 收口 | 本 commit | TOTAL 4435/34/0 |

## ΔN 明细（+7）

UprightGuidesInteractionTests 8→9 / CropToolRotationTests 7→9 / DrtPanelModelTests
11→13 / AdjustmentTransferTests 8→9 / FilmPanelBWTests 5→6。BUNDLE-MAP 同批登记
（`.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`）。

## 纪律面

- **封存面 17 件零 diff**：`git diff f783f1c3..HEAD --name-only` 对封存清单 grep
  交集 = 0（机检在案；T2 动的 with_angle 路径落 CropToolRotation/EditorAreaView，
  均非封存件，亲核一致）。
- **zh-audit**：`--check` PASS（1770 source keys / 2100 catalog keys，本批零新键）。
- **commit-per-task**：四产品 commit 各自洽（T1/T2/T3/T4），全部 `refs #15`；
  内部账本（本目录 + BUNDLE-MAP）随收口 commit 免关联。
- **observer 三件**：M9-2 grade 视口地板 / 旧档 hash 伪影（obs-omp4 实验伪影定性
  维持）/ M9-2 路 2 obs-4——纯观察登记（DECISIONS §3 尾），零动作。
- **G4 透明越门**：两轮越门追记于 DECISIONS §G4（清理尽人事后 23.4G/21.7G 仍
  <25G；free 内存 59-74%、无 swap 压力、`--monitor` 全程伴跑零 kill——monitor
  日志 `monitor-build.log`）。

## 遗留与边界（登记，不阻断）

1. T4①清扫的 MCP/外部源边界（DECISIONS §4.1）——系统性回收归 M11/M12
   reachability collector（RESEARCH.md:100 原规划）。
2. m-1a/m-1b 的 AX 合成事件通道伪影族——GUI 走查配方侧课题（SE 优先 /
   by-role+desc 断言），非产品缺陷面。
3. M9-3 §七.4 的探针 recentProjects 污染——探针侧卫生，另案。
