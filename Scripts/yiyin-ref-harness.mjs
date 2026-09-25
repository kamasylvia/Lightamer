#!/usr/bin/env node
// Scripts/yiyin-ref-harness.mjs — Plan 08-01 T2: the yiyin layout reference
// harness (YIYIN-01 印框; the yiyin repo at
// /path/to/yiyin, v1.7.1, is the READ-ONLY
// spec source — nothing is written into it).
//
// What runs here (VERBATIM transcription, expression-by-expression, of the
// yiyin layout arithmetic — electron/src/modules/image-tool/index.ts):
//   init              :110-131  bg_rate aspect reset + landscape swap
//   clacBgImgSize     :472-506  canvas size (content-height driven; the
//                               width-rate growth)
//   calcContentHeight :508-546  content height (margin vs shadow; the
//                               empty-rows branch)
//   genBgImg          :209-210  main image centering
//   composite         :300-319  row stacking (+ the :543-545 last-row
//                               inflation — exercised only with rows)
// The genTextImg/genMainImgShadow legs need the Electron renderer queue
// (mainApp.win.webContents) and are NOT headless-runnable; the layout
// INTEGERS come from the pure arithmetic above, which Lightamer's
// YiyinLayout mirrors 1:1 (float64, Math.ceil → .rounded(.up)). The
// --measure leg additionally builds ONE representative case with sharp
// (yiyin's own dependency, resolved READ-ONLY from the yiyin repo) and
// MEASURES the composited PNG's non-white bounding box — a placement
// cross-check of the rounded integers against a real composite.
//
// Usage:
//   node Scripts/yiyin-ref-harness.mjs             # JSON case table → stdout
//   node Scripts/yiyin-ref-harness.mjs --measure   # + sharp placement probe
//
// The JSON output is the reference for Tests/LightamerTests/
// YiyinLayoutTests.swift (numbers embedded verbatim; regenerate + diff via
// this script — see 08-1-DECISIONS / input/golden/manifest.md).

import { createRequire } from 'node:module'
import { writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

// yiyin's field names verbatim (IConfig['options']) so the mapping to
// BordersModule.Params is auditable line-by-line.
const CASES = [
  // id, image w×h, opts overrides (defaults: rate 90, margin 0, no bg_rate,
  // no landscape, radius/shadow off — the 08-1 empty-rows face)
  { id: 'landscape_default', w: 4000, h: 3000, opts: {} },
  { id: 'portrait_default', w: 3000, h: 4000, opts: {} },
  { id: 'square_default', w: 3000, h: 3000, opts: {} },
  { id: 'landscape_aspect_1_1', w: 4000, h: 3000, opts: { bg_rate: { w: 1, h: 1 } } },
  { id: 'portrait_aspect_1_1', w: 3000, h: 4000, opts: { bg_rate: { w: 1, h: 1 } } },
  { id: 'landscape_aspect_3_2', w: 4000, h: 3000, opts: { bg_rate: { w: 3, h: 2 } } },
  { id: 'portrait_landscape_swap', w: 3000, h: 4000, opts: { landscape: true } },
  { id: 'landscape_margin5_shadow6', w: 4000, h: 3000, opts: { mini_top_bottom_margin: 5, shadow: 6 } },
  { id: 'landscape_rate50', w: 4000, h: 3000, opts: { main_img_w_rate: 50 } },
  { id: 'portrait_aspect_3_4_margin2_shadow3', w: 3000, h: 4000, opts: { bg_rate: { w: 3, h: 4 }, mini_top_bottom_margin: 2, shadow: 3 } },
  { id: 'square_rate100_neutral', w: 3000, h: 3000, opts: { main_img_w_rate: 100 } },
  { id: 'tiny_ceil_quirk_58x7', w: 58, h: 7, opts: { main_img_w_rate: 100 } },
  // rows leg (08-2 preview — the joint-layout seam's consumption shape)
  { id: 'landscape_with_rows', w: 4000, h: 3000,
    opts: { rows: [{ w: 500, h: 40 }, { w: 600, h: 30 }] } },
]

// ── VERBATIM yiyin arithmetic (electron/src/modules/image-tool/index.ts) ──

function yiyinLayout(w, h, opts) {
  // init :100-106
  const sizeInfo = { w, h, resetW: w, resetH: h }

  // init :110-120 — 重置宽高比
  if (opts.bg_rate && opts.bg_rate.w && opts.bg_rate.h) {
    const rate = +opts.bg_rate.w / +opts.bg_rate.h
    if (sizeInfo.w >= sizeInfo.h) {
      sizeInfo.resetH = Math.round(sizeInfo.w / rate)
    } else {
      sizeInfo.resetW = Math.round(sizeInfo.h * rate)
    }
  }

  // init :122-131 — 横屏输出
  const width = opts.landscape && sizeInfo.resetW < sizeInfo.resetH
    ? sizeInfo.resetH
    : sizeInfo.resetW
  const height = opts.landscape && sizeInfo.resetW < sizeInfo.resetH
    ? sizeInfo.resetW
    : sizeInfo.resetH
  sizeInfo.resetW = width
  sizeInfo.resetH = height

  // clacBgImgSize :472-506
  function clacBgImgSize(heightArg = sizeInfo.h) {
    let resetHeight = sizeInfo.resetH
    let resetWidth = sizeInfo.resetW

    const whRate = resetWidth / resetHeight

    if (heightArg) {
      resetHeight = heightArg
      resetWidth = Math.ceil(resetHeight * whRate)
    } else {
      const validHeight = sizeInfo.h > resetHeight ? sizeInfo.h : resetHeight
      resetHeight = validHeight
      resetWidth = Math.ceil(resetHeight * whRate)
    }

    const mainImgWidthRate = (opts.main_img_w_rate || 90) / 100
    if (sizeInfo.w / resetWidth > mainImgWidthRate) {
      resetWidth = Math.ceil(sizeInfo.w / mainImgWidthRate)
      resetHeight = Math.ceil(resetWidth / whRate)
    }
    return { h: resetHeight, w: resetWidth }
  }

  // genWatermark step 2 — this.clacBgImgSize() (default height = sizeInfo.h)
  const bg1 = clacBgImgSize()

  // calcContentHeight :508-546 (empty text branch — 08-1 face)
  const bgHeight = bg1.h
  const mainImgTopOffset = bgHeight * ((opts.mini_top_bottom_margin ?? 0) / 100)
  const textButtomOffset = bgHeight * 0.027

  let contentTop = Math.ceil(mainImgTopOffset)
  let mainImgOffset = contentTop * 2

  if (opts.shadow != null) {
    const shadowHeight = Math.ceil(sizeInfo.h * ((opts.shadow || 0) / 100))
    contentTop = Math.max(contentTop, shadowHeight)
    mainImgOffset = contentTop * 2
  }

  // (rows leg — yiyin :526-545 — is 08-2; recorded for the mirror tests)
  const rows = opts.rows ?? []
  let mainImgOffsetText = mainImgOffset
  const textH = rows.reduce((n, i) => n + i.h, 0)
  if (rows.length) {
    mainImgOffsetText = mainImgOffsetText * (3 / 4)
    mainImgOffsetText += textButtomOffset
  }
  const contentH = Math.ceil(textH + sizeInfo.h + mainImgOffsetText)

  // genBgImg :197-211 — second clacBgImgSize(contentH) + centering
  const bg = clacBgImgSize(contentH)
  const mainLeft = Math.round((bg.w - sizeInfo.w) / 2)
  const mainTop = contentTop + Math.round((bg.h - contentH) / 2)

  // web/modules/image-tool/index.ts :50,63 — ceil BEFORE the percent
  const mainHCeiled = Math.ceil(sizeInfo.h)
  const cornerRadiusPx = opts.radius != null ? mainHCeiled * ((opts.radius || 2.1) / 100) : 0
  const shadowBlurPx = opts.shadow != null ? mainHCeiled * ((opts.shadow || 6) / 100) : 0

  // composite :300-319 with the :543-545 inflation (rows leg, 08-2)
  const placedRows = []
  if (rows.length) {
    const inflated = rows.map(r => ({ ...r }))
    inflated[inflated.length - 1].h += textButtomOffset
    let prevTop = 0
    for (let i = inflated.length - 1; i >= 0; i--) {
      const text = inflated[i]
      const left = Math.round((bg.w - text.w) / 2)
      const top = placedRows.length === 0
        ? Math.round(bg.h - text.h)
        : Math.round(prevTop - text.h)
      placedRows.push({ left, top, w: text.w, h: text.h })
      prevTop = top
    }
  }

  return {
    id: opts.id,
    imageSize: [w, h],
    canvas: [bg.w, bg.h],
    main: [mainLeft, mainTop],
    contentH,
    contentTop,
    cornerRadiusPx,
    shadowBlurPx,
    textBottomOffsetPx: textButtomOffset,
    rows: placedRows,
  }
}

const results = CASES.map(c => yiyinLayout(c.w, c.h, { ...c.opts, id: c.id }))

// ── --measure: sharp placement probe (one representative case) ──

async function measure() {
  let sharp
  try {
    sharp = createRequire('/path/to/yiyin/package.json')('sharp')
  } catch {
    console.error('# sharp unavailable — measure leg skipped')
    return null
  }
  const dir = mkdtempSync(join(tmpdir(), 'yiyin-harness-'))
  const c = yiyinLayout(4000, 3000, { main_img_w_rate: 50, id: 'measure' })
  const out = join(dir, 'composite.png')
  // The yiyin composite shape (:288-348): white bg canvas, main image at
  // (left, top). Sharp raw output → measure the non-white bounding box.
  const main = await sharp({
    create: { channels: 3, width: c.imageSize[0], height: c.imageSize[1],
      background: { r: 200, g: 30, b: 30 } },
  }).png().toBuffer()
  await sharp({
    create: { channels: 3, width: c.canvas[0], height: c.canvas[1],
      background: { r: 255, g: 255, b: 255 } },
  }).composite([{ input: main, top: c.main[1], left: c.main[0] }])
    .png().toFile(out)
  const { data, info } = await sharp(out).raw().toBuffer({ resolveWithObject: true })
  let minX = info.width, minY = info.height, maxX = -1, maxY = -1
  for (let y = 0; y < info.height; y++) {
    for (let x = 0; x < info.width; x++) {
      const o = (y * info.width + x) * info.channels
      if (data[o] !== 255 || data[o + 1] !== 255 || data[o + 2] !== 255) {
        if (x < minX) minX = x
        if (y < minY) minY = y
        if (x > maxX) maxX = x
        if (y > maxY) maxY = y
      }
    }
  }
  const measured = {
    bbox: [minX, minY, maxX - minX + 1, maxY - minY + 1],
    expected: [c.main[0], c.main[1], c.imageSize[0], c.imageSize[1]],
    canvas: c.canvas,
    pngFile: out,
  }
  return measured
}

if (process.argv.includes('--measure')) {
  const m = await measure()
  if (m) {
    results.push({ id: 'sharp_measure_probe', ...m })
    console.error(`# sharp probe bbox=${JSON.stringify(m.bbox)} expected=${JSON.stringify(m.expected)} png=${m.pngFile}`)
  }
}

// Machine-readable dump (also persisted to .work/plans/08-01/ by the caller
// — NOT committed; the numbers are embedded in YiyinLayoutTests).
writeFileSync('.work/plans/08-01/yiyin-layout-reference.json', JSON.stringify(results, null, 2) + '\n')
console.log(JSON.stringify(results, null, 2))
