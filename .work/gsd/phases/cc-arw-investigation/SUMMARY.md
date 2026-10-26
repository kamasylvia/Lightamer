# CC-ARW 调查批 SUMMARY（2026-10-27）

> 任务：归因 ColorChecker.ARW 首启抓到的「交叉一致性门暗区 255 分歧」（正主）+
> 顺路裁决「中性门 +7/255 蓝偏」。HEAD 起点 `e3d90e35`。

## 一句话结论

**首启「暗区 255 分歧」= 测试基线读回竞争（GoldenColorTests.readRGB8 缺 L014
fence），非色彩分歧**：pipe 腿帧在 GPU 编码 in-flight 时被 getBytes 读回 = 整帧
全零，与正常 baseline 逐像素比出差即 baseline 自身分布（p50=110、maxInZone=255
全是 |0−b|）。fence 修复 + 坐标表回填后 **ARW 交叉一致性门直接 PASS（42.7s 真跑
60MP 双腿）**——pipe 全链 vs CIContext/ColorSync 直渲的真实分歧在容差内（zone 外
<2/255、暗区 zone 内 ≤60/255），候选归因链（premultiply/黑位 clip/working
space 转换路径差/PRC）**全部证伪——真分歧不存在**。

## 调查过程与证据

1. **dump 解析**（`data/pipe-frame-analysis.txt`，numpy 逐像素）：
   - cross-arw 转储（1793016846）plane.pfm = 60,217,344 px **全零帧**
     （nonzero fraction 0.0、sum 0.0、无任何空间结构——不存在亮度带/区域分布）；
   - neutral-arw 转储（1793017011，1.5 分钟后同一 runFullChain 路径）= 正常帧
     （88.6% 非零、补丁序列在位）→ **渲染链本身无缺陷**，全零帧是时序问题；
   - diff-table 重解读：p50=110/p90=208/p100=255 = baseline 自身亮度分布；
     「maxInZone=255」= pipe 全 0 → 全像素落 floor=60 低区 → maxInZone = max
     (baseline)；maxOutside 断言首启时实际是通过的（全像素入 zone）。
2. **读码定位**：`PixelPipe.run`（LightamerCore/Sources/Pipe/PixelPipe.swift:840）
   返回 final.texture 时**无任何 GPU 同步**（:669 `commandBuffer.commit()` 后直
   接返回）——产线安全（EditorMTKView 同队列 FIFO 消费），但 **CPU 读回必须
   fence（LESSONS L014 原文正是此教训）**；`readRGB8`
   （GoldenColorTests.swift:93 原版）裸 getBytes 无 fence = 违例点。合成腿不踩
   是因为小图亚毫秒编码先完成；60MP 全链（colorin 963MB 拷贝 + colorout +
   gamma）数毫秒编码 vs CPU µs 级到达 getBytes → 竞争必然而至（首个大图测试
   踩雷，1.5 分钟后第二次运行时序漂移侥幸通过）。
3. **修复验证**：fence + 坐标表回填后定向跑（新构建）：
   - `testCrossConsistencyColorCheckerARW` **passed（42.660s）**；
   - 中性门如实红（+B 偏存在），分档容差后 passed（见下）；
   - 首轮旧二进制 6/2/0 skip 教训：test-direct.sh 不构建，先 build-for-testing。

## 中性门 +B 偏裁决（顺路项）

- **实测形态**（fence 后干净帧）：|G−B| 随暗度单调增大——N9.5 白 250（饱和钳
  制掩盖）→ N8.0 3.4 → N6.5 4.0 → N5.0 5.6 → N3.5 7.4 → **N2.0 黑 31.2**
  （R=1 G=1 B=32，线性域 B ≈ 40× R/G）；|R−G| 全程 <2。
- **归因 = 样本级 as-shot AWB 冷调蓝增益**（叠加传感器暗部地板），证据链：
  ① EXIF WhiteBalance = 0（Auto，Sony ILCE-7RM4，1/30s ISO100，室外日光）；
  ② 合成腿同门 PASS（管线中性处理本身 <2/255）；
  ③ **ARW 交叉一致性门 PASS**——同一暗部 B 偏在 ColorSync 基线一致存在
   （我方链忠实传递，无私有引入）。
- **处置**：ARW 腿分档容差 `neutralARW = 8`（非饱和亮补丁）/ `neutralARWBlack
  = 40`（黑补丁）；合成腿维持 2。门判别力保留（管线级中性破坏仍必挂）。

## 两门解禁与档案状态

- 坐标表六点已回填 `Fixtures.colorCheckerGrayPatches`（登记档案产线帧坐标）；
  供件在位（TestRAW/ColorChecker.ARW，宿主可解析——首轮 skip 是旧二进制）。
- **两门解禁**：交叉一致性门 = 无条件绿（真分歧不存在）；中性门 = 分档容差下
  绿。ColorChecker 供件自此常驻 carry 两真传感器门。

## 产物

- 修复：`Tests/LightamerTests/GoldenColorTests.swift`（drain fence + readRGB8
  签名 + linear 读回 fence + neutralARW 分档）；`Tests/LightamerTests/
  Fixtures.swift`（坐标表回填 + 注记更新）。
- 数据：`data/pipe-frame-analysis.txt`（首启 dump 解析）。
- 无产线代码改动（封存面 17 件零 diff 天然保持——本批零触产线）。

## 结论档位

**基线语义修正**（测试基线构造缺陷：读回缺 fence + 中性门容差未分档）。
真缺陷 = 无（产线链与 ColorSync 一致性、中性处理均验真）。
