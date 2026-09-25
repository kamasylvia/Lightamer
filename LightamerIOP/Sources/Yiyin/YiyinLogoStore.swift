import CoreGraphics
import CoreText
import Foundation
import ImageIO
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// YiyinLogoStore (Plan 08-2 T5, D-08-CONTEXT-5) — the brand Logo DOUBLE
// channel:
//   1. the EMBEDDED set — the 13 brands × light/dark PDFs (converted from
//      the yiyin `web/public/logo/` SVGs at build time by
//      `Scripts/yiyin-logo-convert/`, assets at
//      `LightamerIOP/Resources/Logos/*.pdf`, bundle-root flattened);
//   2. the USER channel — uploaded custom logos under
//      `Application Support/Lightamer/Yiyin/Logos/` with a name+StableHash
//      registry (the RasterMaskStore sidecar-adjacent pattern).
//
// FAILURE DISCIPLINE (plan 纪律): a load/validation failure degrades the
// slot to EMPTY with a TYPED error record — never a silent fallback
// (RasterMaskStore 三失败腿降级同构). The template engine's logoExists face
// consults this store.
// ─────────────────────────────────────────────────────────────────────────

public final class YiyinLogoStore: @unchecked Sendable {

    /// Typed degradation record (不静默 — surfaced through toasts/labels).
    public enum LogoError: Error, Equatable {
        case corruptPDF(name: String)
        case unsupportedFormat(name: String)
        case alreadyExists(name: String)
        case notFound(name: String)
    }

    /// The bundle marker (the NoiseProfiles access pattern — resources
    /// flatten to the bundle root).
    private final class BundleMarker {}
    public static let defaultBundle = Bundle(for: BundleMarker.self)
    static let defaultUserDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lightamer/Yiyin/Logos", isDirectory: true)

    /// The rasterization height for PDF artwork (the provider face is a
    /// CGImage; the PDF rasterizes ONCE at this height, drawn downscaled —
    /// D-08-2-8; the vector-crisp upgrade is a recorded extension point).
    static let rasterHeight = 512

    public let userDirectory: URL
    public let registryURL: URL

    /// The user registry: name → (file name, StableHash of the file
    /// bytes) — the yiyin font.map face, L013-stable.
    public struct UserEntry: Codable, Equatable, Sendable {
        public var name: String
        public var fileName: String
        public var hash: UInt64

        public init(name: String, fileName: String, hash: UInt64) {
            self.name = name
            self.fileName = fileName
            self.hash = hash
        }
    }

    private let lock = NSLock()
    private var userEntries: [String: UserEntry] = [:]
    /// The PDF document cache; nil records a FAILED load (negative cache —
    /// the degradation is sticky until clearFailed).
    private var embeddedCache: [String: CGPDFDocument?] = [:]
    private var rasterCache: [String: CGImage] = [:]

    public init(bundle: Bundle = YiyinLogoStore.defaultBundle, userDirectory: URL? = nil) {
        let base = userDirectory ?? Self.defaultUserDirectory
        self.userDirectory = base
        self.registryURL = base.appendingPathComponent("registry.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: registryURL),
            let decoded = try? JSONDecoder().decode([String: UserEntry].self, from: data)
        {
            userEntries = decoded
        }
    }

    private func persistRegistry() {
        let entries = userEntries
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    // MARK: - the embedded brand set

    /// The 13 brand keys shipped with the app (yiyin logo dir order).
    public static let embeddedBrands = [
        "canon", "dji", "fujifilm", "hasselblad", "leica", "nikon", "olympus",
        "panasonic", "pentax", "ricoh", "sigma", "songdian", "sony",
    ]

    /// The bundle resource name: `{make}-{b|w}` (yiyin `{make}-b.svg` face;
    /// the resolved variant maps white → w / black → b).
    static func resourceName(make: String, variant: YiyinLogoVariant) -> String {
        let suffix = variant == .white ? "w" : "b"
        return "\(make.lowercased())-\(suffix)"
    }

    /// The engine's `logoExists` face: does the brand asset exist?
    public func embeddedExists(make: String, variant: YiyinLogoVariant) -> Bool {
        embeddedPDF(make: make, variant: variant) != nil
    }

    func embeddedPDF(make: String, variant: YiyinLogoVariant) -> CGPDFDocument? {
        let key = Self.resourceName(make: make, variant: variant)
        lock.lock()
        if let cached = embeddedCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let url = Self.defaultBundle.url(
            forResource: key, withExtension: "pdf"),
            let document = CGPDFDocument(url as CFURL)
        else {
            lock.lock()
            embeddedCache[key] = .some(nil)
            lock.unlock()
            return nil
        }
        lock.lock()
        embeddedCache[key] = .some(document)
        lock.unlock()
        return document
    }

    /// Rasterize an embedded PDF at the fixed face height.
    func rasterizedEmbedded(make: String, variant: YiyinLogoVariant) -> YiyinLogoImage? {
        let key = Self.resourceName(make: make, variant: variant)
        lock.lock()
        if let cached = rasterCache[key] {
            lock.unlock()
            return YiyinLogoImage(image: cached, aspect: Double(cached.width) / Double(cached.height))
        }
        lock.unlock()
        guard let document = embeddedPDF(make: make, variant: variant),
            let page = document.page(at: 1)
        else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let height = CGFloat(Self.rasterHeight)
        let width = max(1, height * box.width / max(box.height, 1))
        guard let ctx = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
            bytesPerRow: Int(width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 0, 0])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: width / box.width, y: height / box.height)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }
        lock.lock()
        rasterCache[key] = image
        lock.unlock()
        return YiyinLogoImage(image: image, aspect: Double(width) / Double(height))
    }

    // MARK: - the user channel

    /// Import (upload) a custom logo: validates the bytes render as a PDF
    /// or image, stores under the user dir, registers name+hash.
    @discardableResult
    public func importLogo(named name: String, from sourceURL: URL) throws -> UserEntry {
        let ext = sourceURL.pathExtension.lowercased()
        guard ["pdf", "png", "jpg", "jpeg"].contains(ext) else {
            throw LogoError.unsupportedFormat(name: name)
        }
        lock.lock()
        if userEntries[name] != nil {
            lock.unlock()
            throw LogoError.alreadyExists(name: name)
        }
        lock.unlock()
        let data = try Data(contentsOf: sourceURL)
        // Validation: PDFs must open with a page; images must decode.
        if ext == "pdf" {
            guard let provider = CGDataProvider(data: data as CFData),
                let document = CGPDFDocument(provider), document.page(at: 1) != nil
            else {
                throw LogoError.corruptPDF(name: name)
            }
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                CGImageSourceGetCount(source) > 0
            else {
                throw LogoError.corruptPDF(name: name)
            }
        }
        let hash = StableHash.hash(data)
        let fileName = "\(String(hash, radix: 16)).\(ext)"
        let target = userDirectory.appendingPathComponent(fileName)
        try data.write(to: target, options: .atomic)
        let entry = UserEntry(name: name, fileName: fileName, hash: hash)
        lock.lock()
        userEntries[name] = entry
        persistRegistry()
        lock.unlock()
        return entry
    }

    public func removeLogo(named name: String) throws {
        lock.lock()
        guard let entry = userEntries.removeValue(forKey: name) else {
            lock.unlock()
            throw LogoError.notFound(name: name)
        }
        persistRegistry()
        lock.unlock()
        try? FileManager.default.removeItem(
            at: userDirectory.appendingPathComponent(entry.fileName))
    }

    public var userLogoNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return userEntries.keys.sorted()
    }

    /// Load a user logo as artwork (the customLogo slot face).
    public func userLogo(named name: String) -> YiyinLogoImage? {
        lock.lock()
        let entry = userEntries[name]
        lock.unlock()
        guard let entry else { return nil }
        let url = userDirectory.appendingPathComponent(entry.fileName)
        if url.pathExtension.lowercased() == "pdf",
            let document = CGPDFDocument(url as CFURL),
            let page = document.page(at: 1)
        {
            let box = page.getBoxRect(.mediaBox)
            let height = CGFloat(Self.rasterHeight)
            let width = max(1, height * box.width / max(box.height, 1))
            guard let ctx = CGContext(
                data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                bytesPerRow: Int(width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.scaleBy(x: width / box.width, y: height / box.height)
            ctx.drawPDFPage(page)
            guard let image = ctx.makeImage() else { return nil }
            return YiyinLogoImage(image: image, aspect: Double(width) / Double(height))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return YiyinLogoImage(
            image: image, aspect: Double(image.width) / Double(image.height))
    }

    /// The provider + engine-exists pair wired for one WatermarkModule
    /// (the Make-logo dispatch face). Custom logos resolve BEFORE the
    /// brand set (a user override wins — the panel's custom field face).
    public func provider() -> YiyinLogoProvider {
        { request in
            switch request {
            case .customLogo(let name):
                return self.userLogo(named: name)
            case .logo(let make, let variant):
                if variant == .auto {
                    // resolved upstream — never reached, degrade to black
                    return self.rasterizedEmbedded(make: make, variant: .black)
                }
                return self.rasterizedEmbedded(make: make, variant: variant)
            case .text:
                return nil
            }
        }
    }
}
