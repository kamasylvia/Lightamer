# 05-01-SUMMARY.md — Phase 5 基建执行总结（T1–T8）

> 全套绿 + 本文件落盘后收工；决策见 `05-01-DECISIONS.md`（D-05-01-T1..T7）。

## 任务表（8/8；每任务独立提交）

| 任务 | 内容 | commit |
|---|---|---|
| T1 | L021 toneequal/flip double-scale 审计还账 + 常驻回归 | `710e4e5` fix(flip,toneequal) |
| T2 | `IOPiece.iscale` 协议增量 + pipe stamp + 常驻断言 | `8252191` feat(pipe) |
| T3 | NoiseProfileStore 规范化转换 + 加载器 | `dc262e0` feat(denoise)（与 T4 同提交） |
| T4 | NoiseProfileStore 单测（手算向量/边界/generic） | `dc262e0`（同上） |
| T5 | gen_fixtures 加噪器 + 新 fixture + 剖面钉参配方 | `87bebdc` feat(golden) |
| T6 | executeTiledNegotiated 回归加固 + 四消费者预演 | `d149ff0` test(tiling) |
| T7 | BilateralGrid3D 共享件 + MSL + 参考实现 | `09b7076` feat(denoise) |
| T8 | 全量回归 + 账目闭合（本文件） | （本提交） |

## 证据指针

- T1：审计表 + pre-fix 红/post-fix 绿矩阵见 DECISIONS D-05-01-T1；
  `L021DoubleScaleAuditTests` 6/6（含非 1.0 scale 档 + compared>0）。
- T2：`IOPieceIscaleTests` 4/4（三档 stamp + 跨 piece 常量 + 强制分块不变性）；
  tile 唯一写点 `grep iscale PixelPipe.swift` = run 前向 walk。
- T3/T4：转换自校验（433 models + 8538 档守恒 + 3 model diff=0）；
  `NoiseProfileStoreTests` 5/5（ILCE-9M3 ISO 140 手算 + strstr/strcmp/skip +
  generic + bundle 31ms + 缓存）；LICENSE-NOTES + TODO 待用户知悉项（§Phase 5
  末行，本轮已存在——复核通过，不新增）。
- T5：加噪器统计（斜率≈a ±10%、截距数量级、均值无偏；flat_-8ev 暗端杠杆补入）；
  新 fixture 11 张（加噪 8 + hue/delta/torture 3；74 → 85 EXR）；
  11 blob 配方 `ALL BLOB RECIPES OK`；RESEARCH 勘误（v12 = 416B + ccmix
  format 类型修）见 D-05-01-T5。
- T6：`TileNegotiationRegressionTests` 5/5（分块==整幅 <1e-5 双门 + stamp
  不变性 + 记账契约 + 两极端 + 四消费者 grid sane：20/24/6/9 tiles，
  全 <3GB/tile）；halo≥side/2 反转边界钉住（不改 TilingPlan）。
- T7：`BilateralGrid3DTests` 5/5（grid_size 手算 5×5×5 + clamp + 平场守恒 +
  Lab 小图全链 + splat 守恒）；网格语义审计（加权计数非比值）见 D-05-01-T7；
  未接 IOP 模块（05-05 消费）。

## 防空转自检声明

每个比较测试的 compared 数字：

| 套件 | compared |
|---|---|
| L021DoubleScaleAuditTests（6） | hook 4 向量 + e2e 8 态全像素 + 逐字节 + halo 4 向量 + 恒等 1 |
| IOPieceIscaleTests（4） | 3 档 + 恒等 1 + 3 piece + tile 1（全 >0） |
| NoiseProfileStoreTests（5） | 逐通道 3 + 命中 6 + 边界 2 + generic 6（全 >0） |
| NoiseFixtureStatisticsTests（3） | staircase 12 阶×120 行×高（~10 万）+ exist 8 + content 全像素（全 >0） |
| TileNegotiationRegressionTests（5） | 分块全像素 + stamp 全像素 + grid 4/16 + 极端 + 消费者（全 >0） |
| BilateralGrid3DTests（5） | 平场 1024 + 小图 4096 + 守恒 cells（全 >0） |

无比较循环的"绿"恒真空转——本轮零容忍；全部测试含真实比较循环。

## 验收标准核对（plan §验收标准 8 条）

- [x] L021 审计：逐处结论落 DECISIONS（2 处命中修 + 4 处免疫证据），常驻回归含
  非 1.0 scale 档，TODO 行闭合（本轮 T8）。
- [x] `IOPiece.iscale` 三档 stamp + tile 不变性绿；`roi.scale ÷ iscale` 注释钉死。
- [x] 剖面管线：转换自校验（433 守恒 + diff=0）；插值/匹配/skip/generic 手算全绿
  （compared>0）；LICENSE-NOTES + TODO 待用户知悉项落账。
- [x] 加噪器统计过（斜率≈a、截距数量级、均值无偏）；新 fixture 入 manifest
  （本文件登记；regenerate.sh ① 自动携带——② 名单未动，canonical 不变）。
- [x] tile 回归网：强制分块==整幅（<1e-5 复核）+ dscIn/iscale 不变性 + 四消费者预演。
- [x] BilateralGrid3D：小图 Lab 全链有界/移动/确定性 + 平场守恒 + splat 守恒；
  未接 IOP 模块。
- [x] 全 suite 绿（0 fail）；每任务独立提交；SUMMARY + DECISIONS 落盘。
- [x] 剖面/参数 blob 配方齐备（05-02..08 可直接消费）；过程文件归 `.work/05-01/`
  （fixtures 工作拷贝 + 本文件草稿）；无 /tmp 落盘产物。

## 全量回归

终轮全 suite：**426 tests / 0 fail / 3 skip**（基线 398 → 本轮 426，+28：
L021 6 + iscale 4 + profile 5 + noise-stats 3 + tile-reg 5 + grid 5）。
3 skip 合规（既有）。MDB_MAP_FULL 杂音（TODO Phase 3 行）本轮多处复现，
不影响结果。

## 新教训候选（评估结论：不入 LESSONS）

- T5 截距门数量级论证（b~1e-9 外推标准误 ~1e-8）与 T7 网格语义审计（加权计数
  非比值）均为任务内已闭环的定位记录，无跨任务复用价值——不入 LESSONS。
- T1 flip `dscIn × scale` 坍缩的 GUI 影响（swap 预览右半黑）是 L021 已覆盖的
  同族表现——不另立 lesson。
- T6 halo≥side/2 反转边界是 03-05-T6 注释语义的回归钉住——不另立 lesson。
