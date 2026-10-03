import Foundation

/// Resolves model asset locations: bundled (app folder reference) and
/// installed (Application Support) roots.
///
/// Injectable by design (Core-level testability, ImportDefaults spirit):
/// both roots accept an override so tests point at temporary directories
/// without touching the real user tree. Production assembly passes nothing.
public struct ModelLocator: Sendable {

    /// Bundle subdirectory that carries the folder reference
    /// (`Resources/AIModels` at the repo root → `Bundle …/AIModels/`).
    public let bundledSubdirectory: String

    /// Test seam. nil = probe `Bundle.main` (the app bundle; under the
    /// direct-launch test host this is Lightamer.app — L019b).
    public let bundledRootOverride: URL?

    /// Test seam. nil = `~/Library/Application Support/Lightamer/models`.
    public let installationRootOverride: URL?

    public init(
        bundledSubdirectory: String = "AIModels",
        bundledRootOverride: URL? = nil,
        installationRootOverride: URL? = nil
    ) {
        self.bundledSubdirectory = bundledSubdirectory
        self.bundledRootOverride = bundledRootOverride
        self.installationRootOverride = installationRootOverride
    }

    // MARK: Bundled (folder reference)

    /// Root of the bundled AIModels folder reference, or nil when absent
    /// (no-model environments — consumers XCTSkip, resource-gate discipline).
    public func bundledRoot(in bundle: Bundle = .main) -> URL? {
        if let override = bundledRootOverride {
            return FileManager.default.fileExists(atPath: override.path) ? override : nil
        }
        // resourceURL + existence check: folder references keep their
        // hierarchy, so AIModels/ resolves as a plain subdirectory of the
        // bundle's Resources.
        guard let resources = bundle.resourceURL else { return nil }
        let root = resources.appendingPathComponent(bundledSubdirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return root
    }

    /// A profile directory inside the bundled folder reference.
    public func bundledProfileURL(_ profileID: String, in bundle: Bundle = .main) -> URL? {
        guard let root = bundledRoot(in: bundle) else { return nil }
        let profile = root.appendingPathComponent(profileID, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: profile.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return profile
    }

    /// A file inside a bundled profile directory.
    public func bundledAssetURL(
        _ fileName: String,
        profileID: String,
        in bundle: Bundle = .main
    ) -> URL? {
        guard let profile = bundledProfileURL(profileID, in: bundle) else { return nil }
        let file = profile.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    // MARK: Installed (Application Support)

    /// `~/Library/Application Support/Lightamer/models` (or the injected
    /// override). Created on demand.
    public func installationRoot() throws -> URL {
        if let override = installationRootOverride {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support
            .appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Final install directory of one profile:
    /// `<installationRoot>/<profile_id>/`.
    public func installedProfileURL(_ profileID: String) throws -> URL {
        let root = try installationRoot()
        let profile = root.appendingPathComponent(profileID, isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        return profile
    }

    /// Sibling scratch directory used during download:
    /// `<installationRoot>/<profile_id>.tmp/` (same-volume rename for the
    /// atomic promote; L009 — never /tmp across volumes).
    public func installedProfileTmpURL(_ profileID: String) throws -> URL {
        let root = try installationRoot()
        return root.appendingPathComponent("\(profileID).tmp", isDirectory: true)
    }
}
