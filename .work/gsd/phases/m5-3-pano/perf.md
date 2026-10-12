# M5-3-02 perf.md — pano 200MP×8 预算探针出数正本

> Plan M5-3-02 T5（KD-12）；惯例 = M2-11/M5-2 perf.md。探针 =
> `Tests/LightamerTests/PanoFusionPerfProbeTests`（EXPORT bundle，
> env 门 `LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless，缺省套件 skip 亲证
> 1/1/0）。真产线直驱 = `panoValidMask` / `PanoGain.samplePlane`+`gains`
> / `panoFuseRows` / `FloatTIFFWriter`（零探针侧重实现）。**NO GATE**
> （OQ-6 同款：数值记录，越门只立决策面，本 plan 零 Metal 面）。

## 批准轮实测（2026-10-13 夜，Debug 直启宿主，8G 门机检在册）

| 段 | 数值 | 备注 |
|---|---|---|
| 画布解析 | 42774×4599 = **196 MP**，scale 30000（初始=接受，本轮无收缩轮） | boundedCanvas 产线机制定输出尺寸（源 6144×4608×8 → 恰在帽下；上一轮 8192×6144 源触发收缩轮至 199MP，两轮均 <200MP ✓） |
| staged 写 | 8×2.9-3.1s = **24.4s**（3.6 GB） | L077 ①：逐文件 synchronizeFile 后进融合 |
| 几何 pass | **183.8s**（valid 196MP） | panoValidMask 纯几何（0 staged 读） |
| 增益段 | **1.07s**（sample 900×97，无 clip） | staged 采样面真读 |
| 融合+流写 | **895.4s**（193 MP，0.2 MPx/s，产物 3 101 321 140 B ≈ 3.1 GB） | 18 band × FloatTIFFWriter 逐带直写 |
| ru_maxrss（机检） | **3814 MB**（BUNDLE 行；`/usr/bin/time` 内核口径） | 8G 门内，零 MEMFAIL |
| phys_footprint 峰值 | 6757 MB（band 16 自报） | 融合段 +242MB/band 残余爬升，见事故节 |
| 磁盘预算 | free 20GB 开跑 → 14GB 收尾（Δ ≈ 6.8GB = staged 3.6 + 产物 3.1 + 杂项） | L077 ④：df+swap 预检行（swap 基线 6.1/7.2GB used，本机常态） |

对账：**CPU 预算未被证伪**——融合+流写 15 分钟级与 Mertens 同域先例
（172s@100MP×5）同量级外推（200MP×8 ≈ 3.2× 像素 × 1.6× 源数 ≈ 15min ✓），
无 GPU kernel 化触发（OQ-6 决策面保持关闭）。

## 内存账对照（KD-5 账面 vs 实测）

| KD-5 账面项 | 实测 |
|---|---|
| valid 掩码 200MB（1B/px @200MP） | ✓ 196MB（42774×4599） |
| tile accum/weight O(tile²) | ✓ 每 band 525MB（accum 3ch + weight 1ch + out 4ch @42732×256）band 级生灭 |
| staged IO 行带缓冲 | ✓ 8×band-span 条带（band×源联合 span，~30-60MB/源，grown-once 复用） |
| 预览域 <1GB | 本探针无预览段（几何已知真值直驱；腿内预览 ≤1200px 灰度 <2MB/图） |
| **全画布像素面（3.2GB）永不物化** | ✓ 结构性：融合行带直写 FloatTIFFWriter，无输出画布、无 memmap |

## 事故与定位（三轮探针；产线修复一道）

1. **第 1 轮（8192×6144 源）**：融合段被系统杀（`time: signal: Invalid
   argument`，footprint 24.0GB，无 .ips）——L077 同签名但 staged 已
   sync → 非 L077 ①脏页。
2. **定位**：footprint 自报（task_vm_info）逐 band 打点 → +2.5GB/band
   线性；三臂隔离（fuse-only / reads-only / write）**同斜率 +77MB/band**
   （小画布诊断）→ 增长 ∝ staged **读体量**，与融合/落盘无关。机理 =
   逐 tile×源 重读同一批源行（84 列 tile × 重复 span）+ freed-but-
   resident 大块（libmalloc 大块缓存/MADV_FREE_REUSABLE 页计账）。
3. **产线修复**：`panoFuseRows` 改 **band×源一次联合 span 读**（64×64
   strided 采样求 span + ±128 行 pad，8×grown-once 条带缓冲），读体量
   84× 降；修后 +242MB/band（残余 = 地图/accum/写块常规churn），
   peak footprint 6.8GB，**RSS 3.8GB 平稳**。PanoLegTests 双跑逐位
   8/0/0 复验（读边界变化不触位值——gather 只读 inside 邻域，联合
   span ⊇ 每 tile span）。
4. 源尺寸 8192×6144 → 6144×4608（staged 6.4→3.6GB）：首轮磁盘预算
   （自由 12-16GB 紧）+ 事故定位期减半缓存压力；画布仍 ≈200MP（测量
   对象不变）。DECISIONS 申报。

## 修复批重测轮（2026-10-13，E-omp-1 修复后——8/8 全源，本节为全源基线正本）

> E-omp-1（ACCEPTANCE-OMP §五）：band-span X 守卫漏 originX，批准轮实为
> **5/8 源融合**（src5/6/7 整源静默丢失）——上节批准轮的融合语义数字
> （吞吐/产物内容）不可引用为全源基线（墙钟量级结论方向不受影响）。
> 一行修复 + 非对称几何回归法后，同协议双跑（Debug 直启宿主，
> `/usr/bin/time -l` ru_maxrss 机检，probe 自带 10GB 磁盘预检）。
> 新增参与门 PERF 行：`pano-participation|<n>/8`（probe 侧以同一 rois+
> crop 复算守卫谓词，零重实现）。

| 段 | 修复后 R1 / R2 | 批准轮（5/8） | 备注 |
|---|---|---|---|
| 参与门 | **8/8 / 8/8**（sources=0..7） | （未测，事后复算 = 5/8） | E-omp-1 修复的直接门 |
| 画布/crop | 42774×4599 = 196MP / crop 42732×4536 at [42,42] | 同 | 几何 pass 与守卫无关，逐位复现 |
| staged 写 | 27.2s / 23.7s（3.6GB） | 24.4s | 同域 |
| 几何 pass | 184.8s / 185.6s | 183.8s | 同域 |
| 融合+流写 | **1630.9s / 1634.1s**（0.1 MPx/s，双跑 ±0.2%） | 895.4s（0.2 MPx/s） | **1.82×** = 3 个补回源的 span 读+gather 增量（m-omp-1 估 ~1.6× 同向）；仍 CPU 预算同量级，无 GPU 化触发 |
| 产物字节 | 3 101 321 140 / 3 101 321 140 | 3 101 321 140 | 逐位同（crop 尺寸决定；内容 = 8 源融合） |
| ru_maxrss（机检） | **5033 MB / 5653 MB** | 3814 MB | 8G 门内宽裕；3 条带/band 增量 |
| phys_footprint 峰值 | 8.67GB / 8.70GB（+388MB/band 爬升） | 6.76GB（+242MB/band） | freed-but-resident 计账同机理放大；RSS 口径健康 |
| 磁盘预算 | free 20GB 开跑 → 12GB 收尾（Δ≈8GB） | 20→14GB | L077 ④ 预检行在册 |

对账：**CPU 预算仍未证伪**（全源融合 27 分钟级 = 批准轮 15 分钟级 ×
1.82，同域外推成立）；遗留观察项 footprint 爬升斜率随源数放大
（+388 vs +242 MB/band），RSS/ru_maxrss 仍 8G 门内，挂账不变。

## 遗留观察项

- 融合段残余 footprint 爬升（批准轮 +242MB/band @5/8 源；修复批重测
  +388MB/band @8/8 源，band 18 达 8.67GB；RSS/ru_maxrss 口径均健康，
  8G 门内宽裕）：freed-but-resident 大块计账行为，斜率随每 band 条带
  数（参与源数）放大；若未来宿主 RAM 更紧，可再把 accum/out 改带间
  复用（挂 perf.md，不阻塞）。
- 融合吞吐 0.1-0.2 MPx/s（Debug 直启 `-Onone`；0.2 = 5/8 源批准轮，
  0.1 = 8/8 源修复批）：Release/`-O` 预计 3-5×；
  Mertens 先例（Release 链不可达时 swiftc -O 脚手架口径）——本批 NO
  GATE 不做 Release 复测，挂 M5-4 VALIDATION 可选项。
