# CC-ARW 调查批 DECISIONS（2026-10-27）

## D-1 「暗区 255 分歧」= 读回竞争（基线语义修正，非产线缺陷）

**裁决**：首启交叉一致性门红不是色彩分歧。`readRGB8` 的 `getBytes` 在 60MP
全链 GPU 编码 in-flight 时读回 gamma 尾纹理 = **整帧全零**（新建纹理零初始内
容）；逐像素 diff 全是 |0−baseline|。修复 = `drain(_:)` fence（AgXTests 同款
idiom：同队列空 command buffer commit + waitUntilCompleted）+ `readRGB8`
签名带 `metal`（4 调用点）+ linear 域裸 getBytes 同补。

**证据链**：
1. cross 转储全零帧 vs 1.5 分钟后中性转储正常帧（同一渲染路径）；
2. `PixelPipe.run` 无 GPU 同步即返回（产线同队列 FIFO 消费安全——**产线无缺陷，
   不改产线**；CPU 读回 fence 是 L014 既有纪律）；
3. fence 修复后交叉门 42.7s 真跑 PASS——zone 外 <2/255、暗区 ≤60/255。

**候选归因链处置**：premultiply/alpha（①）、黑位/线性低段 clip（②）、working
space 转换路径差（③）、PRC/半透明边缘（④）——**全部证伪**（两腿真实分歧在容差
内，无需继续排查）。

## D-2 中性门 +B 偏 = 样本级 as-shot AWB 表型，ARW 腿分档容差

**实测**：|G−B| 随暗度单调增（白端被 255 钳制掩盖 → N8.0 3.4 → N3.5 7.4 →
N2.0 31.2；N2.0 线性域 B ≈ 40× R/G）；|R−G| 恒 <2。
**归因**：EXIF WhiteBalance=0（Auto WB，日光）蓝增益 + 传感器暗部地板。合成腿
PASS（管线正确）+ 交叉一致性 PASS（ColorSync 基线同偏）双证非管线缺陷。
**处置**：`neutralARW = 8`（非黑补丁）/ `neutralARWBlack = 40`（黑补丁，按
patch.name.contains("black") 分档）；合成腿 2/255 不动。门判别力保留。

## D-3 两门解禁 + 供件常驻

`Fixtures.colorCheckerGrayPatches` 六点回填（登记档案产线帧坐标），供件
TestRAW/ColorChecker.ARW 常驻 → 两 ARW 门自此常跑（真传感器门），不再
XCTSkip。**运行代价**：IOPParity bundle 定向轮 GoldenColorTests 类 =
6 测试 ~50s（两 60MP 门各 ~30-43s，宿主峰 3232MB < 8G 门）。

## D-4 工程教训（记入 LESSONS 候选）

1. **test-direct.sh 不构建**——改测试/测试数据源后必须先
   `xcodebuild build-for-testing`，否则旧二进制假象（本批首轮 6/2/0 skip 即此）。
2. **L014 复发形态**：新写读回 helper 必须自带 fence；「小图从不踩」是幸存者
   偏差，首个 60MP 用例即踩（首启正是供件第一次把 60MP 帧带进该类）。
3. **dump 表象会撒谎**：diff-table 百分位「分布」实为单帧全零 × 正常帧的乘积
   ——先验两帧各自健康度再谈「分歧分布」。

## 全套预期

未跑（本批零产线改动；IOPParity 定向轮全绿 = 6/0/0 峰 3232MB）。全套预期
4295/35/0 不变（两 ARW 门从 skip 转执行：skip −2 / executed +2，net 总数不变；
若全 bundle 轮跑，IOPParity 460→460 executed/skip 3→1 ——见 SUMMARY D-3 代价
注记，**全套预期 4295/33/0**，供下轮全套批核对）。
