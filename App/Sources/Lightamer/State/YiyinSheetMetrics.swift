import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// YiyinSheetMetrics (Plan M3-1-02, KD-4) — the yiyin sheet's two ratio memory
// keys, behind an INJECTED defaults face (the ExportState KD-4 same-shape:
// views never touch UserDefaults — M2-1 D-EXEC-1). Keys:
//   yiyin.sheet.widthRatio  /  yiyin.sheet.heightRatio   (Double 0...1)
// Typed read tolerance: absent / foreign-typed / non-finite / out-of-domain
// values degrade to nil = "key absent" = the shipped 420×560 look (KD-1).
// Writes happen ONLY at drag end (AC 3), with the 3-decimal quantized ratio.
// ─────────────────────────────────────────────────────────────────────────────

struct YiyinSheetMetrics {

    static let widthRatioKey = "yiyin.sheet.widthRatio"
    static let heightRatioKey = "yiyin.sheet.heightRatio"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Read faces (nil = key absent / unusable → the shipped look)

    func widthRatio() -> Double? {
        Self.readRatio(defaults, key: Self.widthRatioKey)
    }

    func heightRatio() -> Double? {
        Self.readRatio(defaults, key: Self.heightRatioKey)
    }

    // MARK: Write faces (drag end only — the model's …End is the sole caller)

    func storeWidthRatio(_ value: Double) {
        defaults.set(value, forKey: Self.widthRatioKey)
    }

    func storeHeightRatio(_ value: Double) {
        defaults.set(value, forKey: Self.heightRatioKey)
    }

    /// The typed read: the TYPED Double cast distinguishes unset, a stored
    /// 0.0/1.0, and garbage (a corrupt value never blocks the sheet — it
    /// just falls back to the shipped default).
    static func readRatio(
        _ defaults: UserDefaults, key: String
    ) -> Double? {
        guard let stored = defaults.object(forKey: key) as? Double else {
            return nil
        }
        guard stored.isFinite, (0...1).contains(stored) else { return nil }
        return stored
    }
}
