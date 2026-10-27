# M9-2 SUMMARY — 黑白族 + 滤色镜光谱延展(执行摘要)

> 前任 T1 已收口(`af446612` 资产 + `ca263596` evidence/BUNDLE-MAP);
> 本批 = 接续 executor:T2..T5。基线带式(任务书)= 4328/33/0 ⊕ T1
> 已计部分(BWProfileAssetsTests 6 已随 af446612 入 Layers)。

## 逐任务记账

### T2 谱面消费 + 相纸 grade(与 T3 合并提交,见 DECISIONS §4)

- FilmRecord `cameraFilter/paperGrade` 两 additive 字段(CodingKeys/
  decode/encode 三面同批,MIN-6;stableHash 自动含——grade/filter 变
  → recordHash 变,SidecarV12Tests 钉)。
- **sidecar v12 单 bump**(首例封存面豁免,DECISIONS §1;两键经
  filmRecord Codable 携带,nil 恒缺席——v11 零漂移负测绿)。
- FilmMaterialStore 多目录(CC + BW 双目录一索引,duplicate-id 跨联
  合 fail-closed)+ LightamerShell 双目录组装。
- PaperGradeTable(计算件:我方谱链拟合 Multigrade grade → m/y/EV;
  ISO R datasheet 目标 + 仿射校准层)+ paper_grades.json 持久记录
  (round-trip 钉)。
- 消费缝:grade preset 钉 build Parameters.printCC(tc HIT + print/scan
  miss 的分槽);grade EV 走 solve gain 消费层(不入任何缓存键)。
- 面板:BW 分节 stock picker + grade picker(None + 00..5 verbatim)+
  isPristine 手扩(MIN-5);导出链 legTags 递缝(enqueueExportM2 →
  ExportQueue per-job → TaskLocal)。
- **BWSpectralGoldenTests 真渲染门**:中性门(五色块 × 4 卷 × 3
  grade,三通道散 ≤2e-3 结构性中立)+ 阶调门(00<2<5 密度跨度单调 +
  5>1.3×00 + 18% 灰 0.55-0.95 带)+ grade-seam 键断言(tc bit 恒等 +
  print/scan 移动)。
- T1 数据修正:multigrade density_curves 恒值→三通道 member 曲线
  (assemble_profiles.py 同步,MANIFEST 重对账 8/8)。

### T3 滤色镜 + bake 三槽键(主门)

- CameraFilterTable(透射表加载/81 点对齐/typed 拒绝/双源 note)。
- SpectralBuildEngine 乘法缝(Parameters.cameraFilter additive;sensW
  窗口段后、tc 循环前;绿通道整卷 factor 归一锚 18% 灰;nil 恒等
  分支)。
- **FilmPrintBake 三槽键折入(返工后终式)**:tcKey = fold(pair,
  filter?);print/scan = fold(tcKey, grade?);absent ≡ 裸 pairHash ≡
  M8。solveSpectral modeTag 同步折(grade/filter 后缀,absent 恒等)。
- materialPairHash fold 对齐(消费集三键 + 预折一键,两类理由分开;
  全量 pair 一次冷 miss 窗口登记)。
- 面板 SHOOT 节(filter picker 9 档 + caption + w58 双源注记行)。
- **FilterBakeKeyTests 负测组 ①-⑦ 全落**(⑧ 数值对拍偏差见
  DECISIONS §2——发表值不在仓,改独立复算+单调+注记在册)。

### T4 granularity 标定层

- GrainCalibration(LightamerIOP/Grain;表 + 纯映射 + 单调前提)。
- 探针(PERF_PROBE 门控)曲线:boxRMS ≈ 0.662×strength + 0.62;
  推荐值 Tri-X 25.64 / T-Max 12.21 / Acros 10.71;HP5 null=诚实降级。
- 面板 readout 行(发表 RMS · 推荐 strength)+ 一键应用(既有
  instance commit 通道,零 GrainModule 语义变化;GrainModule.swift
  零 diff)。
- GrainCalibrationTests + GrainCalibrationSemanticsTests(语义门
  ±2.0 带实测绿)。

### T5 收口

- 定向快核(第三任,九类新测试全绿:5/4/2+1skip/4/4/2/3/5/6);
- **全套 `--all` 终值 = 4363/34/0**(第三任轮,guard + monitor 21600 伴跑
  + nohup disown;七 bundle 串行):

| bundle | executed/skipped/failed | 峰值 RSS |
|---|---|---|
| IOP | 798/1/0 | 6062MB |
| IOPParity | 540/10/0 | 5593MB |
| Layers | 528/5/0 | 1183MB |
| Library | 785/4/0 | 742MB |
| Sessions | 285/4/0 | 1204MB |
| Export | 385/4/0 | 4962MB |
| App | 1042/6/0(复验轮) | 2832MB |

- 首轮 App 域 2 fail(冻结清单缺 3 id + token 子串误中「surfaced」),
  收口批修复后复验 1042/6/0;终值 = 六 bundle 首轮绿逐值沿用 + App
  复验轮(红即修后单 bundle 复跑,DECISIONS §8)。
- ΔN 终账:executed 4363 vs 任务书基线 4328 差 +35 = 本批 +29(逐
  bundle 核:IOP+10/IOPParity+11/Library+3/App+5,零漂移)⊕ **+6 口径
  差**(任务书 4328 未含的存量法——归因候选 = m9-1 收口 commit
  `97cb3fc2` 注册面;登记待 orchestrator 复核,不冒领);skip 34 =
  33+1 探针 ✓。
- zh-audit 双 PASS(--check 1744 源键 2060 catalog 键 / --self-test
  V17 golden);红线机检族全零;走查配方
  `.work/gui-acceptance/m9-2/MANIFEST.md` 在库(收口批 force-add)。

## ΔN 对账

| 域 | 新测试 | ΔN |
|---|---|---|
| Layers | BWProfileAssetsTests(T1 已计) | 0(本批) |
| Library | SidecarV12Tests | +3 |
| IOP | PaperGradeTableTests / CameraFilterTests / GrainCalibrationTests | +4/+4/+2 |
| IOPParity | BWSpectralGoldenTests / FilterBakeKeyTests / GrainCalibrationSemanticsTests | +5/+4/+2(探针 1 skip-by-default) |
| App | FilmPanelBWTests | +5 |

合计 +29(其中 +1 常时 skip = 探针门控,有效 +28)。(第三任按实测法数
修正两格:CameraFilter +5→+4、FilterBakeKey +3→+4,合计不变;BUNDLE-MAP
三行同批修正。)越出 plan 预算
+15..20 的理由:(a) 前任在制品已按 4+5+3+3+3 起草(超预算的主因 =
T2 拆三域 + T3 双测试文件,plan 预算按合并文件估);(b) 接续返工补
真渲染中性/阶调门(+2)与 solve 键断言——R1 正确性风险主门的直接
覆盖;(c) 全部越带项均有验收语义(无空转计数)。C1/C2 翻新不增数
(原方法改造)。

## 全套带式表达式(对账申报)

全套 = 4328/33/0(任务书基线)⊕ +29(本批,IOPParity/App/IOP/
Library 定向实跑核;--all 归 orchestrator 批准轮)。
定向终值(见下)。

## 红线机检(T5)

- 双 .metal(FilmSubRunKernels/SpectralFilmKernels)零 diff ✓
- 封存面 17 件零 diff(例外:LightamerSidecar v12 显式 bump——首例
  豁免,plan 申报 + SUMMARY 登记)✓
- RenderProcess 零 diff / GrainModule 零 diff ✓
- FIX2③ LibraryProjectController + McpServerController 零 diff ✓
- Resources/FilmProfiles CC 包逐字节冻结 ✓(MANIFEST 对账不破)
- UserDefaults 零新键 ✓ / xcstrings 尾块纯插入(12 键)✓
- `String.LocalizationValue("…\(x)")` 禁形零命中 ✓
- tuist generate 各批末位 + BUNDLE-MAP 同 commit 登记 ✓

## 走查

配方 = `.work/gui-acceptance/m9-2/MANIFEST.md`(BW 分节/grade 切换/
SHOOT 节 w25 压暗方向/granularity readout 一键应用/w58 注记/色卷
零漂移旁证);实机走查归验收批。


## T5 收口节（2026-10-28 补录——orchestrator 代收口，两任中断后）

**中断叙事**：接续 executor（T2-T4 全实现 + 账本）先后遭 5h 限额（15:59）与进程意外终止两次打断；全套轮 nohup 脱离幸存，retro-commit `b807b1dd`（T2+T3+T4 合一，DECISIONS §5）与全套由 orchestrator 接力完成。BWDbgTests 调试脚手架已由收口者删除（正式化完成）。

**全套终值（2026-10-28 00:08-00:30 收尾）**：**4363/34/0**（七 bundle：IOP 798/1 · IOPParity 540/10 · Layers 528/5 · Library 785/4 · Sessions 285/4 · Export 385/4 · App 1042/6）——零失败零 crash 零 MEMFAIL；总时长 ~66 分钟（IOPParity 26 分钟含 28Profiles 双臂长测）。

**ΔN 对账（越带申报）**：Δexecuted **+35**（基线 4328/33/0 → 4363/34/0；总法数 +36，其中 1 法 skip）vs plan 带 +15..20——**越带 +15**。构成 = planner 低估：BWSpectralGolden 5 + CameraFilter 4 + FilmPanelBW 5 + PaperGradeTable 4 + SidecarV12 3 + FilterBakeKey 4 + GrainCalibration 2 = 新文件 27 法 + FilmProfileTests/BWProfileAssetsTests/SpectralBakeTests 扩容 ~9 法。全部对应 M9BW-01..03 验收形态的 golden/负测组完整清单（PLAN T2-T3 分解时各法预算 1-2，实际一法多断言未压缩）。越带申报：验收形态一一对应、无凑数法；D-DECISIONS §越带 留晨审。

**IOPParity skip 10** = M8 probe 族（probe4/probe5 等 LIGHTAMER_PERF_PROBE 门既知形态）+1 新 = 执行期新增 skip（探针门族），非失败。

**zh-audit**：--check PASS（1744 source / 2060 catalog）+ --self-test PASS。

**遗留移交**：m-1 类注释谓词名 / o-omp3 孤儿 png / bootstrap 补走查（沿 M9-1 尾项池）。
