// Copyright (c) 2026 the Lightamer authors (GPL-3.0). Shape derived from
// SpektraLab RFC-026 (c) Hanze Qiu and contributors (GPL-3.0), upstream
// commit 85c9c16 — see NOTICE §V.
import Foundation
import LightamerCore
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────────
// UQ-S1 (MCP-UQ batch, SpektraLab RFC-026 AgentSchema 借鉴): the get_schema
// synthesis face — per editable op, every params field as {path, type,
// range, meaning, default}. The `list_iops` catalog (IopCatalog.swift) is
// the key REFERENCE; this is the field MEANING + range face ("read before
// editing" — the upstream get_schema summary line).
//
// SYNTHESIS SEAM (three sources, no duplication):
//   1. IopCatalog.ops — the op roster + per-key TYPE strings (the single
//      source for key sets; the T3 reflection guard polices those, KD-2
//      zero-change — this file consumes the table, never re-lists it).
//   2. The module's canonical default ENCODING (seed record paramsData,
//      GradeCatalog.identityJSON for seed-absent ops — the SAME two
//      sources the guard reads) — the per-key DEFAULT values.
//   3. The handwritten RANGE/MEANING table below — the ONLY new data:
//      per (op,key) the interface range + one-line meaning. Ranges are
//      the INTERFACE's (panel clamps), not the wire's — an agent asks
//      for out-of-range, the write faces refuse (the upstream parity
//      line: a person cannot drag these past the panel stops either).
//
// COVERAGE = IopCatalog.ops exactly (19 ops; the default-face narrowing
// rides the seams' face through defaultFaceOps, the list_iops KD-1
// precedent). Non-cataloged ops (payload/geometry/denoise) answer the
// honest "not cataloged" note — full-JSON replace via apply_params
// still works, same as the catalog's own COVERAGE note.
// ─────────────────────────────────────────────────────────────────────────────

enum McpSchemaCatalog {

    /// One field of one op — the get_schema row.
    struct Field: Sendable {
        /// `opName.key` (the apply_params params path).
        let path: String
        /// The IopCatalog type string verbatim (range:/enum:/array/…).
        let type: String
        /// The interface range, when the type string or panel pins one.
        let range: String?
        /// One-line meaning (en — the agent-facing semantic).
        let meaning: String
        /// The canonical default value (JSON scalar/array/object/null).
        let defaultValue: McpJSON
    }

    /// One op's face.
    struct OpSchema: Sendable {
        let opName: String
        let display: String
        let iopOrder: Float
        let version: Int
        let domain: String
        let fields: [Field]
    }

    /// The handwritten range/meaning table: opName → key → (range, meaning).
    /// Keys absent here fall back to (nil range, the type string as meaning
    /// seed) — the table grows additively; the coverage test pins the
    /// row count so silent fallback never hides a missing row.
    static let annotations: [String: [String: (range: String?, meaning: String)]] = [
        "temperature": [
            "red": ("[0,8]", "white-balance red channel gain multiplier"),
            "green": ("[0,8]", "white-balance green channel gain multiplier"),
            "blue": ("[0,8]", "white-balance blue channel gain multiplier"),
            "preset": (
                "unknown=-1,asShot=0,spot=1,user=2,d65=3,d65Late=4",
                "how the gains were derived (asShot = camera WB, user = manual)"),
        ],
        "exposure": [
            "mode": (nil, "exposure mode selector (auto/manual semantics)"),
            "black": ("[-1,1]", "black-point lift (scene-referred EV offset of black)"),
            "exposure": ("[-18,18] EV", "exposure compensation in EV stops"),
            "deflickerPercentile": ("[0,100]", "deflicker histogram percentile"),
            "deflickerTargetLevel": ("[-18,18]", "deflicker target level in EV"),
            "compensateExposureBias": (nil, "compensate the camera exposure bias"),
            "compensateHilitePres": (nil, "preserve highlights when compensating"),
        ],
        "toneequal": [
            "noise": (nil, "mask noise floor for the tone-equalizer mask"),
            "contrastBoost": (nil, "local contrast boost of the equalizer"),
            "exposureBoost": (nil, "global exposure offset applied inside the equalizer"),
            "ultraDeepBlacks": (nil, "EV shift of the ultra-deep-blacks band"),
            "deepBlacks": (nil, "EV shift of the deep-blacks band"),
            "blacks": (nil, "EV shift of the blacks band"),
            "shadows": (nil, "EV shift of the shadows band"),
            "midtones": (nil, "EV shift of the midtones band"),
            "highlights": (nil, "EV shift of the highlights band"),
            "whites": (nil, "EV shift of the whites band"),
            "speculars": (nil, "EV shift of the speculars band"),
            "blending": (nil, "mask edge blending amount"),
            "smoothing": (nil, "mask smoothing radius"),
            "feathering": (nil, "band-transition feathering"),
            "quantization": (nil, "mask quantization steps"),
            "details": (nil, "detail-preservation object (nested)"),
            "method": (nil, "mask computation method selector"),
            "iterations": (nil, "mask solver iteration count"),
        ],
        "equalizer": [
            "g0": (nil, "contrast gain of the coarsest wavelet scale"),
            "g1": (nil, "contrast gain of wavelet scale 1"),
            "g2": (nil, "contrast gain of wavelet scale 2"),
            "g3": (nil, "contrast gain of wavelet scale 3"),
            "g4": (nil, "contrast gain of wavelet scale 4"),
            "g5": (nil, "contrast gain of the finest wavelet scale"),
        ],
        "channelmixerrgb": [
            "red": (nil, "red output channel mix (4-vector)"),
            "green": (nil, "green output channel mix (4-vector)"),
            "blue": (nil, "blue output channel mix (4-vector)"),
            "saturation": (nil, "saturation channel mix (4-vector)"),
            "lightness": (nil, "lightness channel mix (4-vector)"),
            "grey": (nil, "grey channel mix (4-vector)"),
            "normalizeR": (nil, "normalize the red mix"),
            "normalizeG": (nil, "normalize the green mix"),
            "normalizeB": (nil, "normalize the blue mix"),
            "normalizeSat": (nil, "normalize the saturation mix"),
            "normalizeLight": (nil, "normalize the lightness mix"),
            "normalizeGrey": (nil, "normalize the grey mix"),
            "illuminant": (nil, "scene illuminant selector"),
            "illumFluo": (nil, "fluorescent illuminant variant"),
            "illumLED": (nil, "LED illuminant variant"),
            "adaptation": (nil, "chromatic-adaptation method selector"),
            "x": (nil, "custom white-point chromaticity x"),
            "y": (nil, "custom white-point chromaticity y"),
            "temperature": (nil, "custom white-point temperature in Kelvin"),
            "gamut": (nil, "output gamut compression amount"),
            "clip": (nil, "clip out-of-gamut colors"),
            "version": (nil, "color-calibration processing version"),
        ],
        "colorbalancergb": [
            "shadowsY": (nil, "shadows luminance lift"),
            "shadowsC": (nil, "shadows chroma shift"),
            "shadowsH": (nil, "shadows hue shift in degrees"),
            "midtonesY": (nil, "midtones luminance lift"),
            "midtonesC": (nil, "midtones chroma shift"),
            "midtonesH": (nil, "midtones hue shift in degrees"),
            "highlightsY": (nil, "highlights luminance lift"),
            "highlightsC": (nil, "highlights chroma shift"),
            "highlightsH": (nil, "highlights hue shift in degrees"),
            "globalY": (nil, "global luminance lift"),
            "globalC": (nil, "global chroma shift"),
            "globalH": (nil, "global hue shift in degrees"),
            "shadowsWeight": (nil, "shadows mask weight"),
            "highlightsWeight": (nil, "highlights mask weight"),
            "whiteFulcrum": (nil, "white fulcrum of the mask"),
            "chromaShadows": (nil, "chroma scaling in shadows"),
            "chromaMidtones": (nil, "chroma scaling in midtones"),
            "chromaHighlights": (nil, "chroma scaling in highlights"),
            "chromaGlobal": (nil, "global chroma scaling"),
            "saturationShadows": (nil, "saturation in shadows"),
            "saturationMidtones": (nil, "saturation in midtones"),
            "saturationHighlights": (nil, "saturation in highlights"),
            "saturationGlobal": (nil, "global saturation"),
            "hueAngle": (nil, "global hue rotation in degrees"),
            "brillianceShadows": (nil, "brilliance in shadows"),
            "brillianceMidtones": (nil, "brilliance in midtones"),
            "brillianceHighlights": (nil, "brilliance in highlights"),
            "brillianceGlobal": (nil, "global brilliance"),
            "vibrance": (nil, "vibrance amount"),
            "greyFulcrum": (nil, "grey fulcrum of the mask"),
            "maskGreyFulcrum": (nil, "mask grey fulcrum"),
            "contrast": (nil, "contrast fulcrum adjustment"),
            "saturationFormula": (nil, "saturation formula selector"),
        ],
        "sigmoid": [
            "middleGreyContrast": (nil, "contrast around middle grey"),
            "contrastSkewness": (nil, "contrast skew toward shadows/highlights"),
            "displayWhiteTarget": (nil, "display white target in nits"),
            "displayBlackTarget": (nil, "display black target in nits"),
            "colorProcessing": (nil, "color-processing mode selector"),
            "huePreservation": (nil, "hue-preservation strength"),
            "redInset": (nil, "red primary inset"),
            "redRotation": (nil, "red primary rotation"),
            "greenInset": (nil, "green primary inset"),
            "greenRotation": (nil, "green primary rotation"),
            "blueInset": (nil, "blue primary inset"),
            "blueRotation": (nil, "blue primary rotation"),
            "purity": (nil, "primary purity"),
            "basePrimaries": (nil, "base primaries selector"),
        ],
        "agx": [
            "lookLift": (nil, "AgX look lift"),
            "lookSlope": (nil, "AgX look slope"),
            "lookBrightness": (nil, "AgX look brightness"),
            "lookSaturation": (nil, "AgX look saturation"),
            "lookOriginalHueMixRatio": (nil, "original-hue mix ratio of the look"),
            "rangeBlackRelativeEv": (nil, "black point in EV relative to pivot"),
            "rangeWhiteRelativeEv": (nil, "white point in EV relative to pivot"),
            "dynamicRangeScaling": (nil, "dynamic-range scaling"),
            "curvePivotX": (nil, "curve pivot x"),
            "curvePivotYLinearOutput": (nil, "curve pivot linear output y"),
            "curveContrastAroundPivot": (nil, "curve contrast around pivot"),
            "curveLinearRatioBelowPivot": (nil, "linear ratio below pivot"),
            "curveLinearRatioAbovePivot": (nil, "linear ratio above pivot"),
            "curveToePower": (nil, "toe power"),
            "curveShoulderPower": (nil, "shoulder power"),
            "curveGamma": (nil, "curve gamma"),
            "autoGamma": (nil, "derive gamma automatically"),
            "curveTargetDisplayBlackRatio": (nil, "target display black ratio"),
            "curveTargetDisplayWhiteRatio": (nil, "target display white ratio"),
            "basePrimaries": (nil, "base primaries selector"),
            "disablePrimariesAdjustments": (nil, "disable primaries adjustments"),
            "redInset": (nil, "red primary inset"),
            "redRotation": (nil, "red primary rotation"),
            "greenInset": (nil, "green primary inset"),
            "greenRotation": (nil, "green primary rotation"),
            "blueInset": (nil, "blue primary inset"),
            "blueRotation": (nil, "blue primary rotation"),
            "masterOutsetRatio": (nil, "master outset ratio"),
            "masterUnrotationRatio": (nil, "master unrotation ratio"),
            "redOutset": (nil, "red outset"),
            "redUnrotation": (nil, "red unrotation"),
            "greenOutset": (nil, "green outset"),
            "greenUnrotation": (nil, "green unrotation"),
            "blueOutset": (nil, "blue outset"),
            "blueUnrotation": (nil, "blue unrotation"),
            "completelyReversePrimaries": (nil, "fully reverse the primaries"),
        ],
        "filmicrgb": [
            "greyPointSource": (nil, "source grey point in EV"),
            "blackPointSource": (nil, "source black point in EV"),
            "whitePointSource": (nil, "source white point in EV"),
            "reconstructThreshold": (nil, "highlight-reconstruction threshold"),
            "reconstructFeather": (nil, "reconstruction feathering"),
            "reconstructBloomVsDetails": (nil, "reconstruction bloom-vs-details balance"),
            "reconstructGreyVsColor": (nil, "reconstruction grey-vs-color balance"),
            "reconstructStructureVsTexture": (nil, "reconstruction structure-vs-texture balance"),
            "securityFactor": (nil, "reconstruction security factor"),
            "greyPointTarget": (nil, "target grey point in percent"),
            "blackPointTarget": (nil, "target black point in percent"),
            "whitePointTarget": (nil, "target white point in percent"),
            "outputPower": (nil, "output power (display gamma)"),
            "latitude": (nil, "latitude of the filmic spline in percent"),
            "contrast": (nil, "contrast of the filmic spline"),
            "saturation": (nil, "output saturation in percent"),
            "balance": (nil, "shadows/highlights balance in percent"),
            "noiseLevel": (nil, "noise level for the reconstruction"),
            "preserveColor": (nil, "chrominance-preservation mode selector"),
            "version": (nil, "filmic processing version"),
            "autoHardness": (nil, "automatic spline hardness"),
            "customGrey": (nil, "custom grey-point mode"),
            "highQualityReconstruction": (nil, "high-quality reconstruction iterations"),
            "enableHighlightReconstruction": (nil, "enable highlight reconstruction"),
            "shadows": (nil, "shadows handling mode"),
            "highlights": (nil, "highlights handling mode"),
            "compensateIccBlack": (nil, "compensate the ICC black point"),
            "splineVersion": (nil, "spline version selector"),
        ],
        "colisa": [
            "contrast": ("[-1,1]", "contrast amount (-1..1)"),
            "brightness": ("[-1,1]", "brightness amount (-1..1)"),
            "saturation": ("[-1,1]", "saturation amount (-1..1)"),
        ],
        "tonecurve": [
            "curveL": (nil, "L-channel curve nodes [[x,y],…]"),
            "curveA": (nil, "a-channel curve nodes [[x,y],…]"),
            "curveB": (nil, "b-channel curve nodes [[x,y],…]"),
            "typeL": (nil, "L-channel curve interpolation type"),
            "typeA": (nil, "a-channel curve interpolation type"),
            "typeB": (nil, "b-channel curve interpolation type"),
            "autoscaleAb": (nil, "chroma autoscale mode"),
            "unboundAb": (nil, "allow unbounded chroma"),
            "preserveColors": (nil, "chrominance-preservation mode selector"),
        ],
        "levels": [
            "mode": (nil, "levels mode selector (manual/automatic)"),
            "black": (nil, "black-point level"),
            "gray": (nil, "grey-point level"),
            "white": (nil, "white-point level"),
            "levels": (nil, "per-channel level triplets (nested array)"),
        ],
        "shadhi": [
            "radius": (nil, "bilateral radius of the shadows/highlights mask"),
            "shadows": (nil, "shadows lift amount"),
            "whitepoint": (nil, "white-point adaptation"),
            "highlights": (nil, "highlights compression amount"),
            "compress": (nil, "range compression"),
            "shadowsCCorrect": (nil, "shadows color correction"),
            "highlightsCCorrect": (nil, "highlights color correction"),
            "lowApproximation": (nil, "low-approximation quality factor"),
            "unbound": (nil, "allow unbounded values"),
            "algo": (nil, "algorithm selector"),
        ],
        "colorcontrast": [
            "aSteepness": (nil, "a-channel contrast steepness"),
            "aOffset": (nil, "a-channel offset"),
            "bSteepness": (nil, "b-channel contrast steepness"),
            "bOffset": (nil, "b-channel offset"),
            "unbound": (nil, "allow unbounded values"),
        ],
        "velvia": [
            "strength": (nil, "velvia effect strength"),
            "bias": (nil, "velvia color bias"),
        ],
        "vibrance": [
            "amount": (nil, "vibrance amount"),
        ],
        "colorzones": [
            "channel": (nil, "selector channel for the zones"),
            "curveL": (nil, "lightness curve nodes [[x,y],…]"),
            "curveC": (nil, "chroma curve nodes [[x,y],…]"),
            "curveH": (nil, "hue curve nodes [[x,y],…]"),
            "typeL": (nil, "lightness curve interpolation type"),
            "typeC": (nil, "chroma curve interpolation type"),
            "typeH": (nil, "hue curve interpolation type"),
            "strength": (nil, "overall effect strength"),
            "mode": (nil, "color-zones processing mode"),
        ],
        "monochrome": [
            "a": (nil, "red-green filter weight"),
            "b": (nil, "yellow-blue filter weight"),
            "size": (nil, "highlight size threshold"),
            "highlights": (nil, "highlight toning amount"),
        ],
        "colormatch": [
            "solver": (
                "gaussianOT=0,reinhard=1",
                "color-transfer solver (gaussianOT = the Oklab OT solve)"),
            "matrix": (nil, "row-major Oklab 3×3 transfer matrix (9 numbers)"),
            "offset": (nil, "Oklab translation vector (3 numbers)"),
            "strength": ("[0,1]", "solve/identity blend (0 = identity)"),
            "sourceStatsHash": (
                nil, "source-stats identity (decimal string, L013) or null"),
            "referenceStatsHash": (
                nil, "reference-stats identity (decimal string, L013) or null"),
            "effectiveSolver": (
                nil, "solver that produced the attached solve, or null"),
        ],
    ]

    /// The encoded-default lookup (the guard's two sources): the editing
    /// seed record's paramsData, else the GradeCatalog row's identityJSON.
    /// Returns nil for ops with neither (caller falls back to null
    /// defaults — the coverage test pins that this never happens for
    /// cataloged ops).
    static func encodedDefaults(
        for opName: String, seed: [ModuleInstance]
    ) -> [String: Any]? {
        if let record = seed.first(
            where: { $0.opName == opName && $0.multiPriority == 0 })
        {
            return (try? JSONSerialization.jsonObject(
                with: record.paramsData, options: [])) as? [String: Any]
        }
        if let row = GradeCatalog.item(opName: opName) {
            return (try? JSONSerialization.jsonObject(
                with: Data(row.identityJSON.utf8), options: [])) as? [String: Any]
        }
        return nil
    }

    /// Synthesize the op roster: catalog rows × encoded defaults × the
    /// annotation table. `ops` is the face roster (full `IopCatalog.ops`
    /// or `defaultFaceOps()` — the caller owns the face switch).
    static func synthesize(
        ops: [IopCatalog.Op], seed: [ModuleInstance]
    ) -> [OpSchema] {
        ops.map { op in
            let defaults = encodedDefaults(for: op.opName, seed: seed) ?? [:]
            let rows = annotations[op.opName] ?? [:]
            let fields = op.params.map { param -> Field in
                let row = rows[param.name]
                return Field(
                    path: "\(op.opName).\(param.name)",
                    type: param.type,
                    range: row?.range,
                    meaning: row?.meaning ?? param.type,
                    defaultValue: McpSchemaCatalog.jsonValue(
                        defaults[param.name]))
            }
            return OpSchema(
                opName: op.opName, display: op.display,
                iopOrder: op.iopOrder, version: op.version,
                domain: op.domain, fields: fields)
        }
    }

    /// A JSONSerialization value → McpJSON (null for absent/foreign).
    static func jsonValue(_ value: Any?) -> McpJSON {
        guard let value else { return McpJSON.null }
        if value is NSNull { return McpJSON.null }
        if let b = value as? Bool { return McpJSON.bool(b) }
        if let n = value as? NSNumber {
            // Bool rides NSNumber too — the Bool check above caught real
            // booleans; what remains is numeric.
            let d = n.doubleValue
            if d == d.rounded(), abs(d) < 9e15 { return McpJSON.int(n.intValue) }
            return McpJSON.double(d)
        }
        if let s = value as? String { return McpJSON.string(s) }
        if let a = value as? [Any] {
            return McpJSON.array(a.map { jsonValue($0) })
        }
        if let o = value as? [String: Any] {
            return McpJSON.object(o.mapValues { jsonValue($0) })
        }
        return McpJSON.null
    }

    /// The get_schema JSON document: {ops:[{opName,display,iopOrder,
    /// version,domain,fields:[{path,type,range?,meaning,default}]}],
    /// count, note}. Deterministic (sorted keys + roster order).
    static func schemaJSON(
        defaultFace: Bool, seed: [ModuleInstance]
    ) throws -> String {
        let faceOps = defaultFace ? IopCatalog.defaultFaceOps() : IopCatalog.ops
        let schemas = synthesize(ops: faceOps, seed: seed)
        let object: [String: Any] = [
            "ops": schemas.map { schema -> [String: Any] in
                [
                    "opName": schema.opName,
                    "display": schema.display,
                    "iopOrder": Float(schema.iopOrder),
                    "version": schema.version,
                    "domain": schema.domain,
                    "fields": schema.fields.map { field -> [String: Any] in
                        var row: [String: Any] = [
                            "path": field.path,
                            "type": field.type,
                            "meaning": field.meaning,
                            "default": McpSchemaCatalog.plainValue(
                                field.defaultValue),
                        ]
                        if let range = field.range { row["range"] = range }
                        return row
                    },
                ]
            },
            "count": schemas.count,
            "note": "every editable field: its path in the apply_params params "
                + "object, type, interface range and meaning — read this before "
                + "editing. Ranges are the interface's (panel stops); out-of-range "
                + "writes are refused, not clamped. Ops absent from this document "
                + "accept full-JSON replace via apply_params without a field "
                + "reference (see list_iops).",
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }

    /// McpJSON → a JSONSerialization-compatible value.
    static func plainValue(_ value: McpJSON) -> Any {
        switch value {
        case .null: NSNull()
        case .bool(let b): b
        case .int(let i): i
        case .double(let d): d
        case .string(let s): s
        case .array(let items): items.map(plainValue)
        case .object(let members): members.mapValues(plainValue)
        }
    }
}
