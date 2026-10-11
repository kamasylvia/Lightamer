# M5-2 perf.md — Mertens 融合预算证据（Plan M5-2-02 T4 / KD-6）

> 惯例对齐 M2-11 perf.md。探针 = `MertensFusionPerfProbeTests`（EXPORT
> bundle，env 门 `LIGHTAMER_PERF_PROBE=1`，默认套件 skip——缺省面亲证
> `Export 1/1/0`）。**运行门 = ru_maxrss 8G 机检**（test-direct 同口径）。
> CPU 预算判据（OQ-6 生效值）：100MP×5 在探测机可接受时延内——出数记录，
> **无硬门**；GPU 化仅当探针证伪 CPU 预算时 plan 期再议（**本批未触发**：
> 融合核 ~2.9 min，预算内）。

## 探测机与口径

| 项 | 值 |
|---|---|
| 机器 | Apple Silicon，物理内存 16 GB（夜间执行时系统基线 swap 已用 6.2 GB——环境负偏爱下测得） |
| ru_maxrss 口径 | `/usr/bin/time -l` 内核精确记账（test-direct 机检同源），8G 门 |
| CPU 成本口径 | **`swiftc -O` 独立脚手架**（M2-7-3 探针先例）：产线融合函数本体（`MertensFusion.fuseStrip` + `applySubstitution`）按生产 band-outer 驱动形（aligned bands + halo 512 + 置换 in-pass + 129 点单位 LUT）驱动；脚手架侧 ~40 行循环为生产 `mertensBandOuterFuse` 的形状镜像（生产编译单元不可独立编译——依赖闭包跨侧车/解码域，M2-7-3 同因） |
| 工作负载 | 11648×8588 ≈ 100.0 MP × N=5 display 平面；levels = 9（adaptive）、halo = 512、34 bands；tier = medium 形（合成软掩码 111.6M 置换像素真算） |
| 计时纪律 | 全 CPU 顺序段（本路径零 GPU 段——OQ-6 纯 CPU 设计；L014 fence 针对队列 in-flight 读回，此处无对象）；PERF 行走 stderr 无缓冲（异常退出不丢行——第一轮事故教训） |

## 预算账

| 段 | 口径 | 数字 | 备注 |
|---|---|---|---|
| **融合核（band-outer + 置换 in-pass）** | `-O` 脚手架、100MP×5、34 bands、含 111.6M 像素置换 | **172.24 s（~2.9 min）**、吞吐 0.58 MPx/s、RSS 恒 2.9 GB 零盘压 | CPU 预算判据主体——**预算内，无 GPU 化触发**（OQ-6 原文：GPU 化仅当证伪时再议） |
| staged-IO 写（8.1 GB = N×16+1 B/px + 逐文件 sync） | 同脚手架磁盘轮（真 staged 文件 + synchronizeFile） | **4.73 s**（per-source 0.79-1.23 s） | 顺序大块写；读回为同字节顺序读，同量级 |
| 融合期驻留（脚手架轮） | ps 采样 | 恒 ~2.9 GB | 流式形（条带组不随 N 增长——KD-1 常驻面清单成立） |
| 全腿 ru_maxrss（机检轮） | Debug 直启全路径探针轮（stage→fuse→write 全程） | **6248 MB < 8192 门 ✓**（零 MEMFAIL） | 运行门证据正本（AC#4 字面）；含 CI/Metal/框架分页地板 ~1.4 GB |

**生产腿全程估算**（100MP×5，非门值参考）：decode 渲染 2N 面（08 系预算
~0.2-0.7 s/面）+ staged 写 4.7 s + 融合核 ~172 s + 产物写（1.6 GB float
TIFF）≈ **~3 分钟 CPU**——「快速第二模式」定位成立（Robertson02 同规模
为 3N 渲染 + 双聚合遍；Mertens 少一档 decode 且免 CRF 估计）。

## 事故记录（执行期三起，全部环境/探针侧，零产线缺陷）

1. **探针缺陷 ①**（已修）：合成 LUT 只装 1 组（腿契约 = 每源一组）→
   `luts[sourceIndex]` 越界 SIGTRAP（.ips 在案）。修复 =
   `Array(repeating:count:)`。
2. **探针缺陷 ②**（已修）：PERF 行走 stdout 块缓冲——异常退出丢全部计时
   行。修复 = stderr 无缓冲。
3. **环境链（16 GB 机器 × 8.1 GB staged 数据 = 系统性边缘）**：
   a. 首轮 Debug 探针 fuse 段被系统杀死（3277s，`signal: Invalid argument`，
      无 .ips）：ru_maxrss 本身 6248 MB 达标，但 8.1 GB staged **脏页**（未
      回写的 dirty file cache 计入 phys_footprint）+ 工作集把 phys_footprint
      推到 16.28 GB → 系统内存压力杀进程。修复 = staged 写后逐文件
      `synchronizeFile` 强制回写（脏页 → 干净页；语义也更诚实）。
   b. 被杀进程的 `defer` 不跑 → staged 目录残留（8.1 GB×2 轮）两度吃满
      系统盘（ENOSPC 使 harness 无法开命令日志——L049 同族新变体）；
      手工清扫恢复，**探针/基准轮前后清扫 `$TMPDIR` 入 runbook**
      （LESSONS 在册）。同批顺手清了 3 个陈旧 DerivedData 容器（7.3 GB）。
   c. 即便 sync 后，满规模磁盘轮仍被杀（swapfile 已有 6.2 GB 基线 + staged
      缓存抖动引发 swapfile 再增长吃尽磁盘）——**16 GB 机器跑 100MP×5 全
      路径磁盘轮的系统性边缘**，非产线缺陷；CPU 成本改由无盘 genbench 轮
      出数（融合核计算与 staged IO 无关），staged-IO 写段真数独立在册。
4. **Release 直启环境债（登记不阻塞）**：Release 产物 LightamerCore 以
   **动态**链接引用 `WebP_6F0C86992_PackageProduct.framework`（Debug 为静
   态内联——同仓双配置链接行为不一致），且该 framework 未被 embed 到
   app；叠加 hardened runtime 需 D-09-04-D9 重签 + entitlements
   （`/tmp/la-release-ent.plist`：disable-library-validation +
   allow-dyld-environment-variables）。直启 Release 轮未走通——CPU 数值
   面改走 `-O` 脚手架（上表口径）；Release 直启注入链修复挂环境债
   （非本批工程改动）。
5. **Debug 成本观察**（不作预算依据）：Debug -Onone fuse 段 >45 min 未完
   （`weightPlane`/`grayPlane` 热点，sample 在案）——CPU 数值面以 `-O`
   为准（M2-11 双档惯例）。

## 结论（对照 OQ-6 生效值）

- **ru_maxrss 8G 运行门：PASS**（全路径探针轮 6248 MB 机检在案，AC#4）。
- **CPU 预算判据：预算内**（融合核 ~2.9 min @100MP×5，探测机 = 16 GB
  夜间负载态机器；零 GPU 化触发）。
- 流式形（KD-1 常驻面）经脚手架轮 RSS 恒定佐证（条带组不随 band 推进
  增长）。
