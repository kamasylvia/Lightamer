# M5-3-01 ACCEPTANCE — 全景数学核心批（wave 1）独立验收记录

> **双重验收制度**（config `dual_acceptance = true`）：本文件 = 两路结论正本。
> **第一路 = zcode 独立验收（本文件 §一..§六，2026-10-13 凌晨）：PASS / 0 error + 3 minor（全为账面/时序观察项，零代码修复）**。
> 第二路 = omp 二次验收（orchestrator 串行派遣，严禁并发；结论落 §七）。

---

## 一、亲跑对表（三 bundle，独立复跑，exit 0 全绿）

| bundle | 本轮（亲跑） | 申报 | 对表 | peak RSS | MEMFAIL |
|---|---|---|---|---|---|
| IOP | **642/1/0**（157s） | 642/1/0 | ✓ 逐位 | 7624MB | 0 |
| IOPParity | **456/3/0**（768s） | 456/3/0 | ✓ 逐位 | 6784MB | 0 |
| Library | **636/4/0**（79s） | 636/4/0 | ✓ 逐位 | 617MB | 0 |

- **增量对账亲证**：IOP 609+33=642（33 = Feature 9 + Match 9 + Camera 7 + MergeKind 8，六文件逐法点数与 BUNDLE-MAP 增行一致）；IOPParity 451+5=456（Golden 5 法点验：G1 两/四视图 + G2 恢复 + 连通性负测 + 低纹理负测）；Library 631+5=636（Provenance 5 法点验）。+43 法，估数 42..52 ✓。skip 合计 1+3+4=8，均为既有 skip，零新增。
- **二进制新鲜度亲证**：`LightamerTests*.xctest` 三二进制 mtime（10-12 23:19/23:27）晚于全部 tracked 源文件 mtime；`strings` 亲证 PanoGoldenTests 在 IOPParity bundle、四 pano 测试类在 IOP bundle、PanoProvenanceTests 在 Library bundle。
- **G1 bit-identity + G2 三门由本轮亲跑覆盖**（IOPParity 全绿含 PanoGoldenTests 5/5）——非转述执行方数字。

## 二、数学审计（独立复算，uv/Python/numpy，脚本与产线零共享代码）

复算面 = LCG 语义、Hartley DLT、focal 闭式两式、置信度公式与上界、自适应迭代表、wave correct 幂等/符号/方差、G2 fixture 几何全链（真值 H 互最近邻对应 → 自实现 RANSAC〔同 LCG 常数〕→ f 中位数 → initialRotation → 三门判定）。**18/18 PASS**：

| 审计项 | 结果 |
|---|---|
| PanoRNG LCG（MMIX 常数 + 种子 121）确定性 | PASS（双流逐位一致） |
| DLT 已知 H 精确恢复 | PASS（max\|ΔH\| = 4.09e-14，带 ≤1e-9 内） |
| f 闭式两式（f=800 已知 H） | PASS（800.0000000000002 / 799.9999999999965，≤1e-9 rel） |
| f 两式尺度不变性（H×7.3） | PASS |
| f(H=I) 无焦距信息 → nil 等价 | PASS |
| 置信度真值表 6 行（OpenCV 原形） | PASS（≤1e-12） |
| 置信度上界 → 10/3（m→∞） | PASS（3.333333） |
| `1−` 形不可能承载 10/3（sup=1） | PASS（D-1 勘误被迫成立） |
| 自适应迭代表 w=0.3/0.5/0.7/0.9 | PASS（N=850/108/26/7，Swift w<1 分支镜像） |
| wave correct ±20° roll：幂等 + Σx≥0 + x 最小方差 | PASS |
| G2 复刻（理想点对应 1200/对，RANSAC 同种子）f 门 ≤5% | PASS（0.00%） |
| G2 复刻 R 门 ≤2°（pre-BA 相对旋转直比） | PASS（0.0000°） |
| G2 复刻 inlier 门 ≥60% | PASS（100%/100%/100%） |

- **复算侧注记（诚实登记）**：审计脚本首三轮 FAIL 全部为**脚本自身 bug**（①我的 Rodrigues 漏 −I 项〔产线 `rotation(fromAxisAngle:)` 为正确形 cI+sK+(1−c)kkᵀ，已逐行核对〕②G2 段误用闭式段全局 K(f=800) 污染 fixture〔golden 真值 f=500〕③R 门对比式多锚一次 gauge〔H₀ₖ 本身已编码相对旋转〕）——三处修正后 18/18。三个 bug 恰好从反面佐证产线三项 D-裁决（约定敏感性与 D-4/D-6/D-7 的探针动机）。
- **G2 对应段换轨申报判定（§3）＝ 合理**：合成点阵 12 尺寸类 × 100 全同副本，同尺寸圆盘描述子近简并（旋转不变），knn 跨视图同尺寸错误排序是 fixture 域结构性歧义；换轨保留门命名对象（相机数学）经几何对应隔离，硬上限 5%/2°/60% 未动，匹配质量由判别性测试 + G1 分担钉住，产线腿真实摄影内容 + typed 三态兜底。**非「调 golden 凑带」**。
- **置信度公式勘误判定（D-1）＝ 成立**：merge.py:225-226 注释自证「bounded by 10/3」；`1−` 形上界 1 数学不可达 10/3，且 `confidence > .6` 保留门唯「越高越好」语义可解。OpenCV detail 原形 `inliers/(8+0.3·matches)` 为唯一自洽形。

## 三、红线机检（亲跑命令，非转述）

```
grep -rnE "SystemRandomNumberGenerator|srand|arc4random|\.random\(" LightamerCore/Sources/Stack/Pano*.swift
  → 0 命中（含 Double.random/Float.random 底层形态；exit 1 = PASS）
git diff c38eef3..HEAD -- LightamerIOP/                                → 0 行
git diff c38eef3..HEAD -- LightamerCore/Sources/Sidecar/               → 0 行
git diff c38eef3..HEAD -- LightamerCore/Sources/Pipe/                  → 0 行
git diff c38eef3..HEAD -- LightamerCore/Sources/Graph/                 → 0 行
git diff c38eef3..HEAD -- '*.metal'                                    → 0 行
git diff c38eef3..HEAD -- '*ExifPrecheck.swift'                        → 0 行
git diff c38eef3..HEAD -- Project.swift → 6 行全为测试登记，dependencies 块零 diff
```

- **PanoRNG 读码**：`state = state &* 6364136223846793005 &+ 1442695040888963407`（MMIX），`defaultSeed = 121`；RANSAC 采样 + 自适应迭代全程唯一流（`rng: inout PanoRNG`）——KD-3 读码亲证。
- Lumen MIT 锚亲证：merge.py:62 `ransacReprojThreshold=3,maxIters=3000`、:215 `small(im,1200)`、:219 `nfeatures=6000`、:220 `setRNGSeed(121)`、:223-224 <10 特征、:231-233 `confidence>.6 ∧ num_inliers>=10`、:243-245 refinement mask、:251 中位数锚——三文件头 MIT 归属注记齐备，OpenCV 零符号入仓（零新 SPM 由 Project.swift diff 亲证）。

## 四、additive / typed / 词汇核验（读码 + 测试代码点验）

- **MergeKind.pano additive 四臂**：`case pano = "pano-merge"` / `provenanceKind → .panoMerge` / `defaultTag "pano"` / `stepTotal 3N+6` / `runProductionMerge → runPanoLeg` 全在码；六既有 kind 全表快照负测在 PanoMergeKindTests（stepTotal/rawValue/tag 逐值）。
- **typed stub**：`runPanoLeg` = `throw AppError.invalidParameter("pano-merge production leg lands in M5-3-02")`，M5-2-01 KD-4 同形；测试断言 `.failed(.invalidParameter)` + 消息含 M5-3-02。
- **32 门 kind 条件式**：`if kind == .pano, sources.count > 32` 纯 additive if；反测 = `.hdrMerge` 33 张照常 enqueue（`33*2+3` HDR 公式原样）。
- **MergeParams 三字段**：init 尾参缺省 nil（既有调用点零改动）；旧档 7-key golden JSON 双向逐字节零漂移专测（PanoProvenanceTests）+ encodeIfPresent 单字段出现语义双文件钉死。
- **typed 三态词汇**：`FailurePrefix.alignment/disconnected/canvas` 三常量字面与 KD-4 逐字符一致（含尾随空格），测试断言前缀。
- **done==total 恒式**：合成腿 bump 2N+5 + failed settle 1 + decode N = 3N+6 收口测试在案。
- **Provenance 镜像**：两 Kind 枚举 raw 值全表逐一对齐断言 + 双常量（`"spherical-feature-panorama"` / `"1"`）与 HDR/Mertens 身份互异断言。

## 五、逐 commit 边界（七提交 vs front-matter 亲核）

| commit | 任务 | stat 亲核 | 判定 |
|---|---|---|---|
| `3fa930a` | T1 | PanoFeature + 测试 + Project.swift +1 + BUNDLE-MAP +9 | ✓ front-matter 为界 |
| `96056d7` | T2 | PanoMatch + 测试 + 登记 | ✓ |
| `c6f020b` | T3 | PanoCamera + 测试 + 登记 | ✓ |
| `8ec142e` | T4 | MergeKind/ProvenanceReplay/两测试文件 + 登记（+2/+2） | ✓（minor m-a 时序见 §六） |
| `e591c89` | T5 | PanoGoldenTests + PanoCamera 探针修复（115 行，front-matter 文件，SUMMARY T5 行已申报） | ✓（minor m-b 登记时序见 §六） |
| `e561395` | T6 收口 | SUMMARY/DECISIONS/GOAL-STATE/TODO + MertensMergeKindTests 6→7 | ✓ §5 申报在案 |
| `c0eb1f5` | T6 chore | PanoGoldenTests 登记（Project.swift +1 / BUNDLE-MAP +1） | ✓（m-b 本体） |

- 批间穿插三 docs 提交（67e2de0/c38c1c4/e40244e LightCraft research）与本批无关、零代码。
- **MertensMergeKindTests 6→7 连带最小必要申报判定 ＝ 合理**：第七 case 使 CaseIterable 计数钉必然翻转，属 additive 编译级语义连带；mirror 循环结构未动；§5 申报字面与 diff（8 行两处计数）一致。

## 六、发现（0 error + 3 minor，全为观察项，无需代码修复）

- **m-a（时序）**：MertensMergeKindTests 计数钉更新落在 `e561395`（收口 docs 批）而非 `8ec142e`（additive 落点）——`8ec142e..e561395` 窗口内两计数钉处于陈旧红态（该窗口无 bundle 全量轮声称，定向轮按类过滤不触）。内容正确、§5 已申报；后续 additive 批建议计数钉随 additive 同 commit 落地。
- **m-b（时序）**：PanoGoldenTests.swift 于 T5 `e591c89` 入库，Project.swift/BUNDLE-MAP 登记延至 `c0eb1f5`——「新测试文件随各自任务 commit 登记」（E2/L041）字面未满足；HEAD 内容完备、两登记 additive 单行、磁盘编辑先于 23:19/23:27 构建（二进制含 PanoGoldenTests 亲证），仅 commit 粒度错位。
- **m-c（cosmetic）**：SUMMARY 零 diff 自证节「Project.swift 5 行 diff 全为测试登记」实为 **6** 行（1+1+4）；dependencies 块零 diff 结论本身亲证无误。
- 工作树两 untracked（`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`、`.work/gsd/research/dt-clone-archive/`）与本批无关，原样留存待 orchestrator 处置。

## 七、omp 二次验收（占位，orchestrator 串行派遣后回填）

- [ ] omp 结论（PASS/FAIL + 证据）：**待派**。
- 两路 PASS → C 档第 2 停（战果汇报 + M5-3-02 摘要等用户确认）。
