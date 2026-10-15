import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExportPresetStore — the M2 export page's NAMED PRESET layer (V2M-02 T5,
// EXPORT-PRESET-01; REQUIREMENTS :401 — the upstream 7052355 whole-option
// preset shape).
//
// Capture face (the :401 list, EXACTLY): format / quality / bit depths /
// sizing / metadata policy / ICC / naming template. Deliberately NOT in the
// capture face:
//   • the collision tier — the M3-1-03 KD-1 session-state ruling (the page
//     resets it on close); a preset carrying it would silently open the
//     cross-session memory the ruling declined (the M-5 pin);
//   • the gain-map flag and the destination/subfolder faces (not in the
//     :401 list; the destination memory key family is its own base);
//   • the DRT record / film carriers (document-state, rides the run
//     assembly, never the preset).
//
// Shape discipline (the NamingTemplateStore precedent, M2-9-01 KD-4):
//   • UserDefaults JSON array under `export.presets` (the registered
//     spelling — the ONLY new key; the six existing `export.*` keys stay
//     byte-untouched), full-replacement write-back;
//   • built-in presets live in CODE and are never persisted (a factory
//     reset is automatic; stored built-ins are filtered out on load);
//   • corrupt storage degrades to an EMPTY library (a bad blob never
//     blocks the panel);
//   • the store reads ONLY the injected UserDefaults (M2-1 D-EXEC-1);
//   • the APPLY projection is a pure function over a value face
//     (`PanelFace`) — the picker→fields path stays machine-checkable
//     (the M3-1-03 makeRunAssembly paradigm), with typed degrade for a
//     hanging naming-template reference and an out-of-domain variant.
// ─────────────────────────────────────────────────────────────────────────────

/// One named export preset. The variant carries the :401 capture face; the
/// naming pattern is the template STRING (the hanging-reference degrade
/// lives in the projection, not in storage).
struct ExportPreset: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var variant: ExportVariant
    var namingPattern: String
    /// `true` = a code built-in (never persisted, never deletable).
    var isBuiltIn: Bool

    /// The stored user presets carry ids from mint-time; the three built-ins
    /// keep stable per-process ids (the UI selection anchors).
    init(
        id: UUID = UUID(), name: String, variant: ExportVariant,
        namingPattern: String, isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.variant = variant
        self.namingPattern = namingPattern
        self.isBuiltIn = isBuiltIn
    }
}

/// The M2 panel's projectable value face — exactly the fields a preset
/// writes, nothing else. `collisionPolicy` and `gainMapHDR` are DELIBERATELY
/// absent (the M-5 pin and the :401 capture list); the projection cannot
/// touch what the face does not carry.
struct ExportPresetPanelFace: Equatable, Sendable {
    var formatKind: ExportM2FormatKind
    var jpegQuality: Double
    var heicQuality: Double
    var avifQuality: Double
    var webpQuality: Double
    var pngBitDepth: ExportFormatSpec.PNGBitDepth
    var tiffBitDepth: ExportFormatSpec.TIFFBitDepth
    var tiffCompression: ExportFormatSpec.TIFFCompression
    var heicBitDepth: ExportFormatSpec.HEICBitDepth
    var avifBitDepth: ExportFormatSpec.AVIFBitDepth
    var webpLossless: Bool
    var sizingMode: ExportM2PanelModel.SizingMode
    var longEdgePx: Int
    var boundsWidth: Int
    var boundsHeight: Int
    var physicalWidth: Double
    var physicalHeight: Double
    var physicalUnit: YiyinExportSettings.ExportPhysicalUnit
    var physicalDpi: Int
    var allowUpscale: Bool
    var maximumEdgePixels: Int
    var metadataOn: Bool
    var embedICC: Bool
    var namingPattern: String
}

// MARK: - The projection (the picker→fields path, pure)

enum ExportPresetProjector {

    /// Project a preset onto the face. Typed degrade arms:
    ///   • the naming pattern fails the page's parse gate → falls back to
    ///     the first built-in pattern (the NamingTemplateStore three-built-
    ///     ins + Custom fallback precedent — a hanging template reference
    ///     degrades, never blocks);
    ///   • the variant fails `validate()` (an out-of-domain quality, a bad
    ///     sizing field — corrupt or hand-edited storage) → the WHOLE face
    ///     falls back to `defaultFace` (a corrupt preset can never half-
    ///     land: partial application is the dishonest middle state).
    /// A valid variant's fields land verbatim.
    static func project(
        _ preset: ExportPreset, defaultFace: ExportPresetPanelFace
    ) -> ExportPresetPanelFace {
        guard (try? preset.variant.validate()) != nil else {
            var corrupted = defaultFace
            corrupted.namingPattern = NamingTemplateStore.builtIns[0].pattern
            return corrupted
        }
        var face = defaultFace
        face.namingPattern = Self.validPattern(
            preset.namingPattern, fallback: defaultFace.namingPattern)
        // Format + per-format knobs (the per-format knob split mirrors the
        // panel's own makeFormat() consumer face).
        switch preset.variant.format {
        case .jpeg(let quality):
            face.formatKind = .jpeg
            face.jpegQuality = quality
        case .png(let depth):
            face.formatKind = .png
            face.pngBitDepth = depth
        case .tiff(let depth, let compression):
            face.formatKind = .tiff
            face.tiffBitDepth = depth
            face.tiffCompression = compression
        case .heic(let quality, let depth):
            face.formatKind = .heic
            face.heicQuality = quality
            face.heicBitDepth = depth
        case .avif(let quality, let depth):
            face.formatKind = .avif
            face.avifQuality = quality
            face.avifBitDepth = depth
        case .webp(let quality, let lossless):
            face.formatKind = .webp
            face.webpQuality = quality
            face.webpLossless = lossless
        }
        // Sizing (the four modes; the yiyin-superset shortEdge/percent modes
        // cannot come from a preset — the panel cannot express them, and a
        // preset saved FROM the panel never carries them).
        let sizing = preset.variant.sizing
        switch sizing.mode {
        case .original:
            face.sizingMode = .original
        case .longEdge(let px):
            face.sizingMode = .longEdge
            face.longEdgePx = px
        case .bounds(let w, let h):
            face.sizingMode = .bounds
            face.boundsWidth = w
            face.boundsHeight = h
        case .physical(let width, let height, let unit, let dpi):
            face.sizingMode = .physical
            face.physicalWidth = width
            face.physicalHeight = height
            face.physicalUnit = unit
            face.physicalDpi = dpi
        default:
            break // shortEdge/percent: the legacy-sheet superset — keep face
        }
        face.allowUpscale = sizing.allowUpscale
        face.maximumEdgePixels = sizing.maximumEdgePixels ?? 0
        // Metadata + ICC (the :401 metadata-strategy / ICC legs).
        face.metadataOn = preset.variant.metadataPolicy == .standard
        face.embedICC = preset.variant.embedICC
        return face
    }

    /// The pattern gate: a pattern the page's parse accepts passes; anything
    /// else (a hanging template token, garbage) falls back.
    static func validPattern(_ pattern: String, fallback: String) -> String {
        ExportNamingEditor.parseFeedback(pattern) == nil ? pattern : fallback
    }

    /// Capture the CURRENT face into a preset (the save action). The face
    /// is the whole :401 capture; the collision tier and the gain-map flag
    /// are structurally absent from the face (the M-5 pin, compile-time).
    static func capture(
        name: String, from face: ExportPresetPanelFace
    ) -> ExportPreset {
        let mode: YiyinExportSettings.OutputMode
        switch face.sizingMode {
        case .original: mode = .original
        case .longEdge: mode = .longEdge(px: face.longEdgePx)
        case .bounds: mode = .bounds(w: face.boundsWidth, h: face.boundsHeight)
        case .physical:
            mode = .physical(
                width: face.physicalWidth, height: face.physicalHeight,
                unit: face.physicalUnit, dpi: face.physicalDpi)
        }
        let format: ExportFormatSpec
        switch face.formatKind {
        case .jpeg: format = .jpeg(quality: face.jpegQuality)
        case .png: format = .png(bitDepth: face.pngBitDepth)
        case .tiff:
            format = .tiff(bitDepth: face.tiffBitDepth, compression: face.tiffCompression)
        case .heic:
            format = .heic(quality: face.heicQuality, bitDepth: face.heicBitDepth)
        case .avif:
            format = .avif(quality: face.avifQuality, bitDepth: face.avifBitDepth)
        case .webp:
            format = .webp(quality: face.webpQuality, lossless: face.webpLossless)
        }
        let variant = ExportVariant(
            sizing: YiyinExportSettings(
                mode: mode, dpi: face.physicalDpi,
                allowUpscale: face.allowUpscale,
                maximumEdgePixels: face.maximumEdgePixels),
            format: format,
            metadataPolicy: face.metadataOn ? .standard : .none,
            embedICC: face.embedICC)
        return ExportPreset(
            name: name, variant: variant, namingPattern: face.namingPattern)
    }
}

// MARK: - The store (the NamingTemplateStore persistence discipline)

struct ExportPresetStore {

    /// The registered storage key (the ONLY spelling — the single new
    /// `export.*` key of the batch; AGENTS.md registers it).
    nonisolated static let storageKey = "export.presets"

    /// The code built-ins (NEVER persisted — the stored array filters them
    /// out on load, so a factory reset is automatic). Stable ids.
    nonisolated static let builtIns: [ExportPreset] = [
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!,
            name: "JPEG 90",
            variant: ExportVariant(
                sizing: YiyinExportSettings(mode: .original, dpi: 300),
                format: .jpeg(quality: 0.9)),
            namingPattern: NamingTemplateStore.builtIns[0].pattern,
            isBuiltIn: true),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!,
            name: "TIFF 16-bit",
            variant: ExportVariant(
                sizing: YiyinExportSettings(mode: .original, dpi: 300),
                format: .tiff(bitDepth: .sixteen, compression: .none)),
            namingPattern: NamingTemplateStore.builtIns[0].pattern,
            isBuiltIn: true),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a3")!,
            name: "WebP 85",
            variant: ExportVariant(
                sizing: YiyinExportSettings(mode: .original, dpi: 300),
                format: .webp(quality: 0.85, lossless: false)),
            namingPattern: NamingTemplateStore.builtIns[0].pattern,
            isBuiltIn: true),
    ]

    private let defaults: UserDefaults

    /// The app face passes `.standard`; tests pass an isolated suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored user presets (empty when the key is unset or UNPARSEABLE
    /// — a corrupt blob degrades, never blocks). Built-ins never persist;
    /// any sneaking in are filtered out on load.
    func loadPresets() -> [ExportPreset] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        guard let stored = try? JSONDecoder().decode([ExportPreset].self, from: data)
        else { return [] }
        return stored.filter { !$0.isBuiltIn }
    }

    /// The full UI list: the built-ins ahead of the stored user presets.
    func allPresets() -> [ExportPreset] {
        Self.builtIns + loadPresets()
    }

    /// Save (upsert by id) with full-replacement write-back.
    func save(_ preset: ExportPreset) {
        var stored = loadPresets()
        if let index = stored.firstIndex(where: { $0.id == preset.id }) {
            stored[index] = preset
        } else {
            stored.append(preset)
        }
        write(stored)
    }

    /// Remove by id. Built-in ids are a no-op (they are not in storage).
    func remove(id: UUID) {
        write(loadPresets().filter { $0.id != id })
    }

    /// Rename (the Alcedo replacedName semantics — in place).
    func rename(id: UUID, to name: String) {
        var stored = loadPresets()
        guard let index = stored.firstIndex(where: { $0.id == id }) else { return }
        stored[index].name = name
        write(stored)
    }

    private func write(_ presets: [ExportPreset]) {
        let data = (try? JSONEncoder().encode(presets)) ?? Data()
        defaults.set(data, forKey: Self.storageKey)
    }
}
