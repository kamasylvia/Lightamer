import CoreText
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// YiyinFontStore (Plan 08-2 T5, YIYIN-05) — the user font management: the
// system family enumeration + .ttf/.otf import (copy into
// `Application Support/Lightamer/Yiyin/Fonts/` + a name→file+StableHash
// registry, the yiyin font.map face, query.ts:36-62) + removal + TYPED
// failure errors (the plan 纪律: never a silent fallback).
//
// REGISTRATION (D-08-2-9): imported fonts register SESSION-ONLY
// (CTFontManagerRegisterGraphicsFont) and the store rescans the directory
// at init — uninstall semantics stay clean (research 推荐案).
// ─────────────────────────────────────────────────────────────────────────

public final class YiyinFontStore: @unchecked Sendable {

    public enum FontError: Error, Equatable {
        case unsupportedFormat(name: String)
        case corruptFont(name: String)
        case alreadyExists(name: String)
        case notFound(name: String)
    }

    /// One installed user font (the registry row).
    public struct InstalledFont: Codable, Equatable, Sendable {
        public var name: String
        public var fileName: String
        public var hash: UInt64

        public init(name: String, fileName: String, hash: UInt64) {
            self.name = name
            self.fileName = fileName
            self.hash = hash
        }
    }

    public static let supportedExtensions = ["ttf", "otf"]

    public let fontsDirectory: URL
    public let registryURL: URL

    private let lock = NSLock()
    private var installed: [String: InstalledFont] = [:]
    /// Session-registered CGFonts (for unregistration symmetry).
    private var registeredFonts: [String: CGFont] = [:]

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lightamer/Yiyin/Fonts", isDirectory: true)
        self.fontsDirectory = base
        self.registryURL = base.appendingPathComponent("registry.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: registryURL),
            let decoded = try? JSONDecoder().decode([String: InstalledFont].self, from: data)
        {
            installed = decoded
        }
        // Rescan: drop entries whose files vanished, re-register the rest
        // for THIS session.
        for (name, entry) in installed {
            let url = base.appendingPathComponent(entry.fileName)
            guard let data = try? Data(contentsOf: url),
                StableHash.hash(data) == entry.hash,
                let font = Self.font(fromData: data)
            else {
                installed.removeValue(forKey: name)
                continue
            }
            registeredFonts[name] = font
            CTFontManagerRegisterGraphicsFont(font, nil)
        }
        persistRegistry()
    }

    private func persistRegistry() {
        let entries = installed
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    /// The validation face: parse the bytes into a CGFont (nil = corrupt).
    static func font(fromData data: Data) -> CGFont? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGFont(provider)
    }

    /// The system families (the font-dialog list face; sorted, stable).
    public func availableSystemFontFamilies() -> [String] {
        (CTFontManagerCopyAvailableFontFamilyNames() as? [String])?
            .filter { !$0.hasPrefix(".") }
            .sorted() ?? []
    }

    public var installedNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return installed.keys.sorted()
    }

    public func entry(named name: String) -> InstalledFont? {
        lock.lock()
        defer { lock.unlock() }
        return installed[name]
    }

    /// Import a .ttf/.otf: validate, copy in (content-hash file name),
    /// register + record. Errors are TYPED.
    @discardableResult
    public func importFont(named name: String, from sourceURL: URL) throws -> InstalledFont {
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw FontError.unsupportedFormat(name: name)
        }
        lock.lock()
        defer { lock.unlock() }
        if installed[name] != nil {
            throw FontError.alreadyExists(name: name)
        }
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw FontError.corruptFont(name: name)
        }
        guard data.count > 0, let font = Self.font(fromData: data) else {
            throw FontError.corruptFont(name: name)
        }
        // Session register BEFORE the file write so a registration
        // failure surfaces as the typed error (no half-imported state).
        var errorRef: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterGraphicsFont(font, &errorRef)
        guard registered else {
            throw FontError.corruptFont(name: name)
        }
        let hash = StableHash.hash(data)
        let fileName = "\(String(hash, radix: 16)).\(ext)"
        try data.write(
            to: fontsDirectory.appendingPathComponent(fileName), options: .atomic)
        let entry = InstalledFont(name: name, fileName: fileName, hash: hash)
        installed[name] = entry
        registeredFonts[name] = font
        persistRegistry()
        return entry
    }

    /// Remove an installed font: unregister + delete the file + drop the
    /// registry row.
    public func removeFont(named name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = installed.removeValue(forKey: name) else {
            throw FontError.notFound(name: name)
        }
        if let font = registeredFonts.removeValue(forKey: name) {
            CTFontManagerUnregisterGraphicsFont(font, nil)
        }
        try? FileManager.default.removeItem(
            at: fontsDirectory.appendingPathComponent(entry.fileName))
        persistRegistry()
    }

    /// The CTFont for an installed font name (the FontSetting dropdown's
    /// resolution face). nil = unknown name.
    public func ctFont(named name: String, size: Double) -> CTFont? {
        lock.lock()
        let font = registeredFonts[name]
        lock.unlock()
        guard let font else { return nil }
        return CTFontCreateWithGraphicsFont(font, CGFloat(size), nil, nil)
    }
}
