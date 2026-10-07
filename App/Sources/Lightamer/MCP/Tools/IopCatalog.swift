import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// IopCatalog (Plan 14-2 T3; §RQ-14-6) — the handwritten per-op params schema
// table: the runtime channel through which an MCP agent learns each iop's
// parameter keys (MCP-01「iop 参数 schema 元数据」字面).
//
// WHY HANDWRITTEN (the research ruling): Codable reflection can enumerate the
// KEYS, but not their SEMANTICS (slider ranges, enum domains, optionality).
// A generated table would be "键全对、语义全无" and still need a hand-written
// annotation layer — so the table IS handwritten, and reflection is used only
// as a GUARD (McpEditingToolsetTests): per op, the catalog key set must equal
// the module's canonical default-encoded key set (the wire truth — stronger
// than the CodingKeys declaration), and the catalog `version` must equal the
// module record's version (a params-shape migration flips the test red and
// forces a conscious catalog update — the agent cache-invalidation key).
//
// COVERAGE (execution decision D-14-2-T3-1): the EIGHTEEN tone/color grading
// ops with scalar/enum params — the set an agent meaningfully drives through
// apply_params. Payload/geometry modules (crop/flip/ashift/lens/liquify/
// borders/watermark/textOverlay), the denoise family and the remaining
// creative sliders are deliberately NOT cataloged: their params are complex
// nested payloads (full-JSON replace via apply_params still works — the
// catalog is the key REFERENCE, not a whitelist). Extend additively; the
// guard keeps every added op honest.
// ─────────────────────────────────────────────────────────────────────────────

enum IopCatalog {

    /// One parameter key's type face. The vocabulary is the research §RQ-14-6
    /// flat-table set; ranges/enums are annotated only where the source pins
    /// them verbatim (the guard does NOT police type strings — it polices
    /// KEYS and version).
    struct Param: Sendable {
        let name: String
        let type: String
        init(_ name: String, _ type: String) {
            self.name = name
            self.type = type
        }
    }

    /// One iop face.
    struct Op: Sendable {
        let opName: String
        let display: String
        /// The v50 order (drift-guarded against the module's real order).
        let iopOrder: Float
        /// The params-shape version (the agent cache-invalidation key).
        let version: Int
        /// The applicable source domain (all cataloged ops are tone/color
        /// post-decode stages → "both").
        let domain: String
        let params: [Param]
    }

    static let ops: [Op] = [
        Op(
            opName: "temperature", display: "White Balance", iopOrder: 3.0,
            version: 1, domain: "both",
            params: [
                Param("red", "range:[0,8]"), Param("green", "range:[0,8]"),
                Param("blue", "range:[0,8]"),
                Param(
                    "preset",
                    "enum:unknown=-1,asShot=0,spot=1,user=2,d65=3,d65Late=4"),
            ]),
        Op(
            opName: "exposure", display: "Exposure", iopOrder: 21.0,
            version: 1, domain: "both",
            params: [
                Param("mode", "enum"),
                Param("black", "range:[-1,1]"),
                Param("exposure", "range:[-18,18] (EV)"),
                Param("deflickerPercentile", "range:[0,100]"),
                Param("deflickerTargetLevel", "range:[-18,18]"),
                Param("compensateExposureBias", "boolean"),
                Param("compensateHilitePres", "boolean"),
            ]),
        Op(
            opName: "toneequal", display: "Tone Equalizer", iopOrder: 24.0,
            version: 1, domain: "both",
            params: [
                Param("noise", "number"), Param("contrastBoost", "number"),
                Param("exposureBoost", "number"),
                Param("ultraDeepBlacks", "number"), Param("deepBlacks", "number"),
                Param("blacks", "number"), Param("shadows", "number"),
                Param("midtones", "number"), Param("highlights", "number"),
                Param("whites", "number"), Param("speculars", "number"),
                Param("blending", "number"), Param("smoothing", "number"),
                Param("feathering", "number"), Param("quantization", "number"),
                Param("details", "object"), Param("method", "enum"),
                Param("iterations", "integer"),
            ]),
        Op(
            opName: "equalizer", display: "Equalizer (contrast)", iopOrder: 27.0,
            version: 1, domain: "both",
            params: [
                Param("g0", "number"), Param("g1", "number"), Param("g2", "number"),
                Param("g3", "number"), Param("g4", "number"), Param("g5", "number"),
            ]),
        Op(
            opName: "channelmixerrgb", display: "Color Calibration",
            iopOrder: 28.5, version: 1, domain: "both",
            params: [
                Param("red", "array[4]"), Param("green", "array[4]"),
                Param("blue", "array[4]"), Param("saturation", "array[4]"),
                Param("lightness", "array[4]"), Param("grey", "array[4]"),
                Param("normalizeR", "boolean"), Param("normalizeG", "boolean"),
                Param("normalizeB", "boolean"), Param("normalizeSat", "boolean"),
                Param("normalizeLight", "boolean"), Param("normalizeGrey", "boolean"),
                Param("illuminant", "enum"), Param("illumFluo", "enum"),
                Param("illumLED", "enum"), Param("adaptation", "enum"),
                Param("x", "number"), Param("y", "number"),
                Param("temperature", "number"), Param("gamut", "number"),
                Param("clip", "boolean"), Param("version", "enum"),
            ]),
        Op(
            opName: "colorbalancergb", display: "Color Balance RGB",
            iopOrder: 41.5, version: 1, domain: "both",
            params: [
                Param("shadowsY", "number"), Param("shadowsC", "number"),
                Param("shadowsH", "number"),
                Param("midtonesY", "number"), Param("midtonesC", "number"),
                Param("midtonesH", "number"),
                Param("highlightsY", "number"), Param("highlightsC", "number"),
                Param("highlightsH", "number"),
                Param("globalY", "number"), Param("globalC", "number"),
                Param("globalH", "number"),
                Param("shadowsWeight", "number"), Param("highlightsWeight", "number"),
                Param("whiteFulcrum", "number"),
                Param("chromaShadows", "number"), Param("chromaMidtones", "number"),
                Param("chromaHighlights", "number"), Param("chromaGlobal", "number"),
                Param("saturationShadows", "number"), Param("saturationMidtones", "number"),
                Param("saturationHighlights", "number"), Param("saturationGlobal", "number"),
                Param("hueAngle", "number"),
                Param("brillianceShadows", "number"), Param("brillianceMidtones", "number"),
                Param("brillianceHighlights", "number"), Param("brillianceGlobal", "number"),
                Param("vibrance", "number"), Param("greyFulcrum", "number"),
                Param("maskGreyFulcrum", "number"),
                Param("contrast", "number"), Param("saturationFormula", "enum"),
            ]),
        Op(
            opName: "sigmoid", display: "Sigmoid", iopOrder: 45.3,
            version: 1, domain: "both",
            params: [
                Param("middleGreyContrast", "number"), Param("contrastSkewness", "number"),
                Param("displayWhiteTarget", "number"), Param("displayBlackTarget", "number"),
                Param("colorProcessing", "enum"), Param("huePreservation", "number"),
                Param("redInset", "number"), Param("redRotation", "number"),
                Param("greenInset", "number"), Param("greenRotation", "number"),
                Param("blueInset", "number"), Param("blueRotation", "number"),
                Param("purity", "number"), Param("basePrimaries", "enum"),
            ]),
        Op(
            opName: "agx", display: "AgX", iopOrder: 45.5,
            version: 1, domain: "both",
            params: [
                Param("lookLift", "number"), Param("lookSlope", "number"),
                Param("lookBrightness", "number"), Param("lookSaturation", "number"),
                Param("lookOriginalHueMixRatio", "number"),
                Param("rangeBlackRelativeEv", "number"),
                Param("rangeWhiteRelativeEv", "number"),
                Param("dynamicRangeScaling", "number"),
                Param("curvePivotX", "number"), Param("curvePivotYLinearOutput", "number"),
                Param("curveContrastAroundPivot", "number"),
                Param("curveLinearRatioBelowPivot", "number"),
                Param("curveLinearRatioAbovePivot", "number"),
                Param("curveToePower", "number"), Param("curveShoulderPower", "number"),
                Param("curveGamma", "number"), Param("autoGamma", "boolean"),
                Param("curveTargetDisplayBlackRatio", "number"),
                Param("curveTargetDisplayWhiteRatio", "number"),
                Param("basePrimaries", "enum"),
                Param("disablePrimariesAdjustments", "boolean"),
                Param("redInset", "number"), Param("redRotation", "number"),
                Param("greenInset", "number"), Param("greenRotation", "number"),
                Param("blueInset", "number"), Param("blueRotation", "number"),
                Param("masterOutsetRatio", "number"), Param("masterUnrotationRatio", "number"),
                Param("redOutset", "number"), Param("redUnrotation", "number"),
                Param("greenOutset", "number"), Param("greenUnrotation", "number"),
                Param("blueOutset", "number"), Param("blueUnrotation", "number"),
                Param("completelyReversePrimaries", "boolean"),
            ]),
        Op(
            opName: "filmicrgb", display: "Filmic RGB", iopOrder: 46.0,
            version: 1, domain: "both",
            params: [
                Param("greyPointSource", "number"), Param("blackPointSource", "number"),
                Param("whitePointSource", "number"),
                Param("reconstructThreshold", "number"), Param("reconstructFeather", "number"),
                Param("reconstructBloomVsDetails", "number"),
                Param("reconstructGreyVsColor", "number"),
                Param("reconstructStructureVsTexture", "number"),
                Param("securityFactor", "number"),
                Param("greyPointTarget", "number"), Param("blackPointTarget", "number"),
                Param("whitePointTarget", "number"),
                Param("outputPower", "number"), Param("latitude", "number"),
                Param("contrast", "number"), Param("saturation", "number"),
                Param("balance", "number"), Param("noiseLevel", "number"),
                Param("preserveColor", "enum"), Param("version", "enum"),
                Param("autoHardness", "boolean"), Param("customGrey", "boolean"),
                Param("highQualityReconstruction", "integer"),
                Param("enableHighlightReconstruction", "boolean"),
                Param("shadows", "enum"), Param("highlights", "enum"),
                Param("compensateIccBlack", "boolean"),
                Param("splineVersion", "enum"),
            ]),
        Op(
            opName: "colisa", display: "Contrast Brightness Saturation",
            iopOrder: 47.0, version: 1, domain: "both",
            params: [
                Param("contrast", "range:[-1,1]"), Param("brightness", "range:[-1,1]"),
                Param("saturation", "range:[-1,1]"),
            ]),
        Op(
            opName: "tonecurve", display: "Tone Curve", iopOrder: 48.0,
            version: 1, domain: "both",
            params: [
                Param("curveL", "array"), Param("curveA", "array"),
                Param("curveB", "array"),
                Param("typeL", "enum"), Param("typeA", "enum"), Param("typeB", "enum"),
                Param("autoscaleAb", "enum"), Param("unboundAb", "boolean"),
                Param("preserveColors", "enum"),
            ]),
        Op(
            opName: "levels", display: "Levels", iopOrder: 49.0,
            version: 1, domain: "both",
            params: [
                Param("mode", "enum"), Param("black", "number"),
                Param("gray", "number"), Param("white", "number"),
                Param("levels", "array"),
            ]),
        Op(
            opName: "shadhi", display: "Shadows and Highlights", iopOrder: 50.0,
            version: 1, domain: "both",
            params: [
                Param("radius", "number"), Param("shadows", "number"),
                Param("whitepoint", "number"), Param("highlights", "number"),
                Param("compress", "number"), Param("shadowsCCorrect", "number"),
                Param("highlightsCCorrect", "number"), Param("lowApproximation", "number"),
                Param("unbound", "boolean"), Param("algo", "enum"),
            ]),
        Op(
            opName: "colorcontrast", display: "Color Contrast", iopOrder: 56.0,
            version: 1, domain: "both",
            params: [
                Param("aSteepness", "number"), Param("aOffset", "number"),
                Param("bSteepness", "number"), Param("bOffset", "number"),
                Param("unbound", "boolean"),
            ]),
        Op(
            opName: "velvia", display: "Velvia", iopOrder: 57.0,
            version: 1, domain: "both",
            params: [
                Param("strength", "number"), Param("bias", "number"),
            ]),
        Op(
            opName: "vibrance", display: "Vibrance", iopOrder: 58.0,
            version: 1, domain: "both",
            params: [
                Param("amount", "number"),
            ]),
        Op(
            opName: "colorzones", display: "Color Zones", iopOrder: 60.0,
            version: 1, domain: "both",
            params: [
                Param("channel", "enum"),
                Param("curveL", "array"), Param("curveC", "array"), Param("curveH", "array"),
                Param("typeL", "enum"), Param("typeC", "enum"), Param("typeH", "enum"),
                Param("strength", "number"), Param("mode", "enum"),
            ]),
        Op(
            opName: "monochrome", display: "Monochrome", iopOrder: 64.0,
            version: 1, domain: "both",
            params: [
                Param("a", "number"), Param("b", "number"),
                Param("size", "number"), Param("highlights", "number"),
            ]),
    ]

    /// The catalog face for `list_iops`: a JSON document of the full table.
    static func catalogJSON() throws -> String {
        let object: [String: Any] = [
            "ops": ops.map { op -> [String: Any] in
                [
                    "opName": op.opName,
                    "display": op.display,
                    "iopOrder": Float(op.iopOrder),
                    "version": op.version,
                    "domain": op.domain,
                    "params": Dictionary(
                        uniqueKeysWithValues: op.params.map { ($0.name, $0.type) }),
                ]
            },
            "note": "keys are the params JSON keys accepted by apply_params; the "
                + "handwritten table is guard-tested against each module's encoded "
                + "params (version pins the shape — refresh your cache when version "
                + "changes)",
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }
}
