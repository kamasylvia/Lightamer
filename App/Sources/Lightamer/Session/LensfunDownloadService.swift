import Foundation
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────
// LensfunDownloadService — first-run lensfun-data fetch (Plan 04-04-T3,
// D-G1 data distribution, 04-04-DECISIONS D-04-04-T0-1 + D9).
//
// Source: the `lensfun-data` GitHub repository master zip (≈4.2MB XML
// payload — 04-RESEARCH §4c measured). Destination:
// `Application Support/<bundle>/Lensfun/version_1/*.xml` (flat unzip via
// `/usr/bin/unzip -j '*.xml'`; non-sandboxed independent distribution per
// PROJECT constraints, so a `/usr/bin` Process launch is allowed).
//
// Override: `UserDefaults` `lensfun.customPath` — when set to an existing
// directory, it wins over the downloaded copy (user-supplied library).
//
// Failure contract: ANY failure (network / unzip / empty result) returns
// `.failed` and installs nothing — the (c) layer stays absent and the
// manual layer works (the downgrade path; the panel toasts, editing never
// blocks). No retry loop (the user re-taps the panel button).
// ─────────────────────────────────────────────────────────────────────────

/// Where the active Lensfun XML directory comes from.
enum LensfunDataLocation: Sendable, Equatable {
    /// User-supplied directory (`lensfun.customPath`).
    case custom(URL)
    /// First-run downloaded copy under Application Support.
    case downloaded(URL)
    /// No database on disk (the (c)-absent downgrade).
    case absent
}

enum LensfunDownloadService {
    /// The upstream zip (versioned branch pin — master tracks lensfun-data).
    static let sourceURL = URL(
        string: "https://github.com/lensfun/lensfun-data/archive/refs/heads/master.zip")!

    /// `UserDefaults` key for the user-supplied library path (D-04-04-T0-1).
    static let customPathKey = "lensfun.customPath"

    /// The stock download destination (…/Application Support/<bundle>/Lensfun).
    static func supportDirectory(bundleID: String = Bundle.main.bundleIdentifier ?? "com.kamasylvia.lightamer") -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Lensfun", isDirectory: true)
    }

    /// Resolve the ACTIVE database directory: custom path (when set +
    /// non-empty of XML) wins; else the downloaded copy; else nil.
    /// Installs the store as a side effect when a directory is found.
    @discardableResult
    static func resolveAndInstall() -> LensfunDataLocation {
        if let custom = UserDefaults.standard.string(forKey: customPathKey),
           !custom.isEmpty {
            let url = URL(fileURLWithPath: custom, isDirectory: true)
            if LensfunStore.install(directory: url) {
                return .custom(url)
            }
        }
        let dir = supportDirectory().appendingPathComponent("version_1", isDirectory: true)
        if LensfunStore.install(directory: dir) {
            return .downloaded(dir)
        }
        return .absent
    }

    /// Download + unpack + install. Returns the installed location, or
    /// `.absent` on ANY failure (downgrade — never throws to the panel).
    static func download() async -> LensfunDataLocation {
        let root = supportDirectory()
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let zip = staging.appendingPathComponent("lensfun-data.zip")
            let (tmpURL, _) = try await URLSession.shared.download(from: sourceURL)
            try FileManager.default.moveItem(at: tmpURL, to: zip)
            // Flat-extract the version_1 XML files (the zip nests them one
            // directory deep: lensfun-data-master/data/version_1/*.xml).
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-j", "-q", zip.path, "*.xml", "-d", staging.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return .absent }
            let xmls = (try? FileManager.default.contentsOfDirectory(
                at: staging, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "xml" } ?? []
            guard !xmls.isEmpty else { return .absent }
            let dest = root.appendingPathComponent("version_1", isDirectory: true)
            try FileManager.default.createDirectory(
                at: dest, withIntermediateDirectories: true)
            for xml in xmls {
                let target = dest.appendingPathComponent(xml.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: xml, to: target)
            }
            if LensfunStore.install(directory: dest) {
                return .downloaded(dest)
            }
            return .absent
        } catch {
            return .absent
        }
    }
}
