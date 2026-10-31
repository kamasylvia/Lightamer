# R8 DECISIONS(E-1 几何编辑即崩调查修复批;issue #16)

## D-R8-1 根因定罪:composite window 取了 entry 帧,不是协商帧

**机制(file:line)**:

- `PixelPipe.forwardWalk` 开头 `roi = entry`(walk 种子),**此后再无写入**——
  `self.roi` 恒保持 entry 值(注:run() 的 roiHint 交集也在 entry 语义上)。
- `LayerCompositeDriver.composite:261` 的 `let window = basePipe.roi` 取的就是
  这个 **entry 帧 ROI**,而非 forward walk 的**协商终帧**(`roiWalk`/walked)。
- base 链一含激活几何模块(SWAP_XY flip / 激活 crop / ashift AABB),walked ≠ entry:
  base 平面 = walked 形,window = entry 形。terminal/layer sub-run 以
  `inputROI = window` 起步,恒等协商链下 pos 0 的 `negotiatedIn` 保持 entry 形;
  sub-run base case 直返 accumulator(walked 形)→ pos 0 的逐像素
  negotiated-ROI precondition(`PixelPipe.swift:1676`)双值不匹配 → EXC_BREAKPOINT。

**两腿数值对齐**(omp 实测签名 ↔ 机制推演,逐位吻合):

| 腿 | omp 签名(upstream=accumulator) | 机制 |
|---|---|---|
| SWAP_XY(CW90) | `roiOut=1840x1227 neg=1840x1227 upstream=1227x1840` | flip.modifyROIOut 转置 walked;window 未转置 |
| crop(left=0.1) | `roiOut=1840x1227 neg=1840x1227 upstream=1656x1227` | crop.modifyROIOut 收缩 walked;window 未收缩 |

flipV/rot180/tint 存活的对照面也自洽(无 swapsXY/无收缩 → walked == entry)。

**引入 commit 判定**:

- 潜伏缺陷 = `9d1f4fa9`(06-01 T4,composite 骨架 + `window = basePipe.roi`
  语义错)——当时链上无激活几何模块,不可达。
- 暴露条件 = 几何模块激活;用户可达化 = M9-3 crop tool strip(90° 对/滑杆)。
- 故「嫌疑面按新近度」的 M9-3/M9-4 两条均**排除**:omp 双机实测(HEAD `a0206e83`
  + 基线 `f783f1c3` 同崩)已判非 R7 回归;本批源码亲核进一步判明 M9-3 只是
  「第一次让该缺陷用户可达」(UI 入口),非引入者。M9-3 upright op 默认中性、
  M9-4 prepareChain 折键与 ROI 协商正交——两条嫌疑线均与崩溃机制零交集。

## D-R8-2 修复:forwardWalk 末行发布协商终帧(封存面豁免申报)

**修法**(最小缝,1 行语义 + 注记):

```swift
// forwardWalk 末尾,return 前:
roi = roiWalk   // R8 fix: publish the negotiated final frame
```

- `roi` 属性语义从「entry」改为「协商后终帧」(`internal private(set)`),注释
  同批更新(属性 doc + forwardWalk 行内注记,PixelPipe.swift 共 2 hunk)。
- **封存面豁免申报**(M9-4 prepareChain 先例形):PixelPipe 在 M7-6 封存面清单。
  触面 = 本 2 hunk,零其它封存件;逐 hunk 见本文件 §D-R8-2 上述两段引文。

**影响面全查**(`.roi` 全仓消费点):

1. `LayerCompositeDriver.composite:261`(唯一外部消费)——即本修复目标。
2. `PixelPipe` 内部 4 处(runFilmLeg/runFilmDisplayReplayLeg 的 `xxxPipe.roi`):
   全部是恒等 ROI 的 tail 派生链(walked == entry),值零变化;且其返回 roi
   最终只流回 runTerminalTails 的局部变量,run()/runSub 调用侧均只取 texture
   不取 roi——零行为差。
3. App/IOP 侧零消费(全仓 grep 在案)。

**恒等链零漂移论证**:无激活几何模块时 `roiWalk == entry`(walk 逐级恒等),
`roi = roiWalk` 与旧值逐位相同——全套 4435+3 基线除新增 3 法外零预期漂移
(T4 实测佐证)。

## D-R8-3 回归策略:修前探针红 → 修后三绿

- 探针法(不触 precondition,可在修前跑):`pipe.roi` vs 输出平面逐维相等,
  swap-XY 与 crop 两腿。修前实测红(`roi=48x32 vs plane=32x48`,数值方向与
  机制推演一致);修后绿。
- 崩场景反演(修前会进程崩,修后跑):`testCompositeSurvivesActivatedRotationAndCrop`
  = rotCW90 + 激活 crop + terminal 尾 + 空层/identity 层双 composite,window==output
  契约 + identity 层零增量逐字节。
- 落域:LayerCompositeTests(LAYERS bundle,BUNDLE-MAP 行内计数 10→13 同批)。

## D-R8-4 G4 透明越门登记(非静默)

- guard 首判 BLOCK G4(Data 卷可用 7569MB<25GB,97% 满)。清理可安全再生面
  (/tmp 旧产物 970MB、`.build/acceptance-m2-9-03` 157MB、`.build/derived` 老构建
  残留 2.0GB)后 9.2-10GB,仍深于 M9-3 先例的贴线带(21.6-25.6GB)。
- 按 M9-3 §7/§9 先例**透明越门**继续:G1 heavy=0 / G2 free 内存健康 / 无 swap
  压力时 G4 防 swap 挤爆本意不成立;`machine-guard.sh --monitor` 全程伴跑
  (`/tmp/r8walk/monitor.log`,全套轮另有 all-runs 伴跑),零 RSS-KILL(走查轮
  机检在案)。
- 风险注记:增量 build 输出 <1GB、测试日志 <100MB,9GB 余量下磁盘压力可控;
  红即停线 = Data 卷 <2GB 或任一 MEMFAIL。

## D-R8-5 实机走查形态与降级(AX 层驱动)

- 用户恰在本机前活动(Ghostty 前台有真人输入)——**禁抢前台**:走查全走
  AX 层(swift AXUIElement walker + AXPress,不动 frontmost),截图走
  `screencapture -l <windowID>`(按窗口截,不截全屏)。
- 实测闭环:CW90×2 + CCW90(omp 崩矩阵 #1/#2)全部存活,渲染转置正确
  (横向街景→竖向,crop overlay 手柄框自适应转置后 frame——R7 T2「重拟窗
  不转置」联动面实机在位),sidecar 逐次落盘(items 4,label=旋转,op=flip)。
- 降级项:crop overlay 拖拽与 straighten 滑杆无 AX 面,合成拖拽(cliclick)
  需抢前台,与本机即时占用冲突 → **挂账 omp 复审**(GUI 互斥排程),其语义
  面由 unit 全链(flip+crop composite)与 R7 T2 既有验收承载。
- 「自动拉直」按钮在无导线态 disabled(AXError -25204 = ActionUnsupported,
  M9-3 by-design),非缺陷。
- 收工:GUI quit 干净(pgrep 零残留);探针临时项目删除;
  `library.recentProjects` defaults 污染清除;供件只读拷贝于 /tmp/r8walk/
  (不入库,未触个人肖像目录)。
