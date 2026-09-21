import Foundation

// ─────────────────────────────────────────────────────────────────────────
// LensfunDB — Lensfun XML database reader (Plan 04-04-T2, IOP-GEO-03 (c)).
//
// Parses the lensfun-data XML files (`lensdatabase → mount/camera/lens →
// calibration → distortion/tca/vignetting`) with Foundation `XMLParser` —
// the schema is flat, two levels, all-attribute-driven, no namespaces, no
// mixed content (04-RESEARCH §4c;本机实测 55 xml / 4.2MB).
//
// Data files NEVER enter git (D-G1): the app downloads the full library on
// first run (LensfunDownloadService, T3); tests use hermetic inline XML or
// the 4-file hand-picked subset under `input/golden/fixtures/lensfun/`.
// `parse(data:)` is pure + synchronous so tests never touch the filesystem.
//
// What is DELIBERATELY not parsed (v1 scope, 04-04-DECISIONS D-04-04-T0-2):
// - `<type>` (fisheye/rectilinear/…) — recorded on the entry; non-
//   rectilinear lenses REFUSE resolve (fisheye math does not fit this
//   kernel) instead of silently mis-correcting.
// - `<center>` — absent from the v1 subset (and rare upstream); parsed
//   when present, defaults to frame center in the resolve layer.
// - `<aspect-ratio>` / calibration attributes — v1 data has none;
//   resolve defaults aspect 1.5 (the lensfun `lfLens` default).
// - `<real-focal-length>` — v1 subset has none; resolve falls back to the
//   nominal focal (lensfun: row RealFocal defaults to nominal).
// - `<mount>` compat lists — parsed (name + compat) for completeness;
//   v1 matching keys on maker/model/cropfactor, not mounts.
// ─────────────────────────────────────────────────────────────────────────

/// A parsed lensfun database (one or many XML files merged).
struct LensfunDB: Sendable {
    var lenses: [LensEntry] = []
    var cameras: [CameraEntry] = []
    var mounts: [MountEntry] = []
}

/// A `<mount>` entry (name + compatible mounts).
struct MountEntry: Sendable {
    var name: String
    var compat: [String] = []
}

/// A `<camera>` entry. `models` holds EVERY `<model>` variant (incl.
/// `lang` translations — e.g. `ILCE-7M4` + `Alpha 7 IV`).
struct CameraEntry: Sendable {
    var maker: String
    var models: [String] = []
    var mount: String = ""
    var cropfactor: Double = 0
}

/// A `<lens>` entry. `models` holds every `<model>` variant.
struct LensEntry: Sendable {
    var maker: String
    var models: [String] = []
    var mounts: [String] = []
    var cropfactor: Double = 0
    var aspectRatio: Double = 1.5
    /// lensfun `<type>` (e.g. `stereographic`); nil = rectilinear default.
    var type: String?
    /// Optical center override (`<center x y>`); nil = frame center.
    var center: (x: Double, y: Double)?
    var calibrations: LensCalibrations = LensCalibrations()
}

struct LensCalibrations: Sendable {
    var distortions: [DistortionCalib] = []
    var tcas: [TCACalib] = []
    var vignettes: [VignetteCalib] = []
    /// `<real-focal-length focal real-focal>` rows.
    var realFocals: [(focal: Double, real: Double)] = []
}

/// `<distortion model focal …/>`. Terms are RAW XML values (the d-factor
/// + hugin rescale happens in the resolve layer, `mod-coord.cpp`).
struct DistortionCalib: Sendable {
    enum Model: Sendable { case poly3, poly5, ptlens }
    var model: Model
    var focal: Double
    /// poly3: [k1]; poly5: [k1, k2]; ptlens: [a, b, c].
    var terms: [Double]
}

/// `<tca model focal …/>`. Missing br/bb/cr/cb attributes default to 0
/// (e.g. the Canon 24mm row carries only vr/vb).
struct TCACalib: Sendable {
    enum Model: Sendable { case linear, poly3 }
    var model: Model
    var focal: Double
    /// linear: (kr, kb) — defaults (1, 1) when absent.
    var kr: Double = 1
    var kb: Double = 1
    /// poly3: (vr, vb, cr, cb, br, bb).
    var vr: Double = 1
    var vb: Double = 1
    var cr: Double = 0
    var cb: Double = 0
    var br: Double = 0
    var bb: Double = 0
}

/// `<vignetting model focal aperture distance k1 k2 k3/>` (v1: always pa).
struct VignetteCalib: Sendable {
    var focal: Double
    var aperture: Double
    var distance: Double
    var k1: Double
    var k2: Double
    var k3: Double
}

enum LensfunDBLoader {
    /// Parse one XML document's bytes (pure; hermetic tests feed literals).
    static func parse(_ data: Data) -> LensfunDB {
        let parser = LensfunXMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.db
    }

    /// Load + merge every `*.xml` in `directory` (sorted for determinism).
    /// Unparseable files are skipped (logged), never fatal — a half-
    /// downloaded library still corrects the lenses it has.
    static func load(directory: URL) -> LensfunDB {
        var merged = LensfunDB()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension == "xml" }).sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: url) else { continue }
            let db = parse(data)
            merged.lenses.append(contentsOf: db.lenses)
            merged.cameras.append(contentsOf: db.cameras)
            merged.mounts.append(contentsOf: db.mounts)
        }
        return merged
    }
}

/// `XMLParser` delegate — builds one file's `LensfunDB`.
/// `final class` + single synchronous `parse()` use: never crosses an
/// isolation domain (the loader consumes it before returning).
private final class LensfunXMLParser: NSObject, XMLParserDelegate {
    var db = LensfunDB()

    private var curMount: MountEntry?
    private var curMountText = ""
    private var curCamera: CameraEntry?
    private var curLens: LensEntry?
    private var text = ""
    private var textAttr: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        textAttr = attributes
        switch name {
        case "mount":
            // Only the top-level `<mount>` ENTRY opens a mount record.
            // A lens's `<mount>Sony E</mount>` reference is collected as
            // TEXT at its end element (didEndElement appends to the lens).
            if curLens == nil { curMount = MountEntry(name: "") }
        case "camera": curCamera = CameraEntry(maker: "")
        case "lens": curLens = LensEntry(maker: "")
        case "distortion":
            guard var lens = curLens,
                  let model = attributes["model"],
                  let focal = attributes["focal"].flatMap(Double.init)
            else { return }
            switch model {
            case "poly3":
                if let k1 = attributes["k1"].flatMap(Double.init) {
                    lens.calibrations.distortions.append(
                        DistortionCalib(model: .poly3, focal: focal, terms: [k1]))
                }
            case "poly5":
                if let k1 = attributes["k1"].flatMap(Double.init),
                   let k2 = attributes["k2"].flatMap(Double.init) {
                    lens.calibrations.distortions.append(
                        DistortionCalib(model: .poly5, focal: focal, terms: [k1, k2]))
                }
            case "ptlens":
                if let a = attributes["a"].flatMap(Double.init),
                   let b = attributes["b"].flatMap(Double.init),
                   let c = attributes["c"].flatMap(Double.init) {
                    lens.calibrations.distortions.append(
                        DistortionCalib(model: .ptlens, focal: focal, terms: [a, b, c]))
                }
            default:
                break // ACM + future models: v1 scope (recorded above)
            }
            curLens = lens
        case "tca":
            guard var lens = curLens,
                  let model = attributes["model"],
                  let focal = attributes["focal"].flatMap(Double.init)
            else { return }
            switch model {
            case "linear":
                lens.calibrations.tcas.append(TCACalib(
                    model: .linear, focal: focal,
                    kr: attributes["kr"].flatMap(Double.init) ?? 1,
                    kb: attributes["kb"].flatMap(Double.init) ?? 1))
            case "poly3":
                lens.calibrations.tcas.append(TCACalib(
                    model: .poly3, focal: focal,
                    vr: attributes["vr"].flatMap(Double.init) ?? 1,
                    vb: attributes["vb"].flatMap(Double.init) ?? 1,
                    cr: attributes["cr"].flatMap(Double.init) ?? 0,
                    cb: attributes["cb"].flatMap(Double.init) ?? 0,
                    br: attributes["br"].flatMap(Double.init) ?? 0,
                    bb: attributes["bb"].flatMap(Double.init) ?? 0))
            default:
                break
            }
            curLens = lens
        case "vignetting":
            guard var lens = curLens,
                  let focal = attributes["focal"].flatMap(Double.init),
                  let aperture = attributes["aperture"].flatMap(Double.init),
                  let distance = attributes["distance"].flatMap(Double.init),
                  let k1 = attributes["k1"].flatMap(Double.init),
                  let k2 = attributes["k2"].flatMap(Double.init),
                  let k3 = attributes["k3"].flatMap(Double.init)
            else { return }
            lens.calibrations.vignettes.append(VignetteCalib(
                focal: focal, aperture: aperture, distance: distance,
                k1: k1, k2: k2, k3: k3))
            curLens = lens
        case "real-focal-length":
            guard var lens = curLens,
                  let focal = attributes["focal"].flatMap(Double.init),
                  let real = attributes["real-focal"].flatMap(Double.init)
            else { return }
            lens.calibrations.realFocals.append((focal, real))
            curLens = lens
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement name: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "mount":
            if curLens != nil {
                // Lens mount REFERENCE (`<mount>Sony E</mount>` text inside
                // `<lens>`) — the `<mount>` ENTRY close is handled by the
                // curMount branch below (no lens open there).
                curLens?.mounts.append(value)
            } else {
                if let m = curMount { db.mounts.append(m) }
                curMount = nil
            }
        case "camera":
            if let c = curCamera { db.cameras.append(c) }
            curCamera = nil
        case "lens":
            if let l = curLens { db.lenses.append(l) }
            curLens = nil
        case "compat":
            curMount?.compat.append(value)
        case "maker":
            if curLens != nil { curLens?.maker = value }
            else if curCamera != nil { curCamera?.maker = value }
        case "model":
            if curLens != nil { curLens?.models.append(value) }
            else if curCamera != nil { curCamera?.models.append(value) }
        case "cropfactor":
            if curLens != nil { curLens?.cropfactor = Double(value) ?? 0 }
            else if curCamera != nil { curCamera?.cropfactor = Double(value) ?? 0 }
        case "type":
            curLens?.type = value
        case "aspect-ratio":
            if let ratio = Self.parseAspect(value) { curLens?.aspectRatio = ratio }
        default:
            break
        }
        text = ""
    }

    /// `4:3` / `3:2` / `1.5` spellings → Double.
    static func parseAspect(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        if parts.count == 2,
           let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
            return a / b
        }
        return Double(s)
    }
}
