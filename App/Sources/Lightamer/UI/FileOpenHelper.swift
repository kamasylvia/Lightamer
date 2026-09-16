import AppKit
import UniformTypeIdentifiers

/// Shared NSOpenPanel wrapper for the Phase 1 File → Open / toolbar / CTA hooks.
///
/// Panel copy comes from the String Catalog; results are handed back on the
/// MainActor so callers can route straight into `EditorState.load(url:)`.
@MainActor
internal enum FileOpener {

    /// Open a RAW/image file picker and load the chosen file.
    static func openImage(load: @MainActor @escaping (URL) -> Void) {
        let panel = makePanel(
            titleKey: "open_panel_title",
            messageKey: "open_panel_message",
            canChooseDirectories: false,
            types: [.rawImage, .image, .webP]
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }
    /// Pick a folder (or a file). Phase 1 fallback per UI-SPEC drag rule 2:
    /// folder → session is Phase 9, so opening a folder loads its first image.
    static func openFolder(load: @MainActor @escaping (URL) -> Void) {
        let panel = makePanel(
            titleKey: "open_panel_title",
            messageKey: "open_panel_message",
            canChooseDirectories: true,
            types: []
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentTypeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let firstImage = contents.first { item in
                (try? item.resourceValues(forKeys: [.contentTypeKey]))?
                    .contentType?.conforms(to: .image) ?? false
            }
            if let firstImage { load(firstImage) }
        } else {
            load(url)
        }
    }

    // MARK: - Helpers

    private static func makePanel(
        titleKey: String,
        messageKey: String,
        canChooseDirectories: Bool,
        types: [UTType]
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = String(localized: String.LocalizationValue(titleKey))
        panel.message = String(localized: String.LocalizationValue(messageKey))
        panel.canChooseFiles = true
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = types
        return panel
    }
}
