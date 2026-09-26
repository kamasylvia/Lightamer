import AppKit
import LightamerCore
import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// PresetManagerWindow (Plan 12-4 T3; PRES-01/PRES-02) — the preset MANAGER
// (an independent app-level window; the Inspector panel is the apply face,
// this window is the CRUD/import/export face):
//
//   • list grouped by the free-form category key (未分类 last)
//   • create 「从当前图创建预设…」 — the CURRENT effective chain through the
//     copy path (skip set applied; PastePayload.compose 正本) → name +
//     category sheet → PresetsStore.create
//   • rename / category edit / delete (file-first removal)
//   • import (NSOpenPanel file copy → fresh stem) / export (NSSavePanel
//     byte-identical copy — PRES-02 zero format conversion)
//   • skipped-files footer (the self-heal's 标坏不崩 display: corrupt /
//     invalid files stay on disk, listed, never crash the library)
//
// Panel discipline: stable accessibility identifiers + a11y labels + zh
// catalog keys the same round (L025).
// ─────────────────────────────────────────────────────────────────────────────

internal struct PresetManagerWindow: View {

    @Environment(PresetsStore.self) private var presetsStore
    @Environment(PresetController.self) private var presetController

    // Create-from-current sheet.
    @State private var createPresented = false
    @State private var createName = ""
    @State private var createCategory = ""
    // Rename / category / delete alert states (presenting: id).
    @State private var renameTarget: StoredPreset?
    @State private var renameText = ""
    @State private var categoryTarget: StoredPreset?
    @State private var categoryText = ""
    @State private var deleteTarget: StoredPreset?
    // Import / export.
    @State private var importPresented = false
    @State private var failure: String?

    private var grouped: [(category: String?, presets: [StoredPreset])] {
        let all = presetsStore.presets()
        let byCategory = Dictionary(grouping: all) {
            $0.document.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var sections: [(String?, [StoredPreset])] = byCategory.keys
            .compactMap { $0 }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ($0, byCategory[$0] ?? []) }
        if let uncategorized = byCategory[nil] {
            sections.append((nil, uncategorized))
        }
        return sections
    }

    var body: some View {
        VStack(spacing: 0) {
            if presetsStore.presets().isEmpty {
                ContentUnavailableView {
                    Label("preset_no_presets", systemImage: "wand.and.stars")
                } description: {
                    Text("preset_manager_empty_body")
                }
            } else {
                presetList
            }
            if !presetsStore.skippedFiles.isEmpty {
                skippedFooter
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    createName = ""
                    createCategory = ""
                    createPresented = true
                } label: {
                    Label(
                        String(localized: "preset_create_from_current"),
                        systemImage: "plus.circle")
                }
                .accessibilityIdentifier("presets.manager.create")

                Button {
                    importPresented = true
                } label: {
                    Label(String(localized: "preset_import"), systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("presets.manager.import")
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importPresented },
                set: { importPresented = $0 }),
            allowedContentTypes: [PresetFilePanels.presetType],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importPreset(from: url)
        }
        .sheet(isPresented: $createPresented) {
            createSheet
        }
        .alert(
            String(localized: "preset_rename"),
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            ),
            presenting: renameTarget
        ) { preset in
            TextField(
                String(localized: "preset_name_label"),
                text: Binding(
                    get: { renameText },
                    set: { renameText = $0 }))
            Button(String(localized: "alert_ok")) { commitRename(preset) }
            Button(String(localized: "alert_cancel"), role: .cancel) { renameTarget = nil }
        } message: { _ in
            Text("preset_rename_message")
        }
        .alert(
            String(localized: "preset_category_edit"),
            isPresented: Binding(
                get: { categoryTarget != nil },
                set: { if !$0 { categoryTarget = nil } }
            ),
            presenting: categoryTarget
        ) { preset in
            TextField(
                String(localized: "preset_category_label"),
                text: Binding(
                    get: { categoryText },
                    set: { categoryText = $0 }))
            Button(String(localized: "alert_ok")) { commitCategory(preset) }
            Button(String(localized: "alert_cancel"), role: .cancel) { categoryTarget = nil }
        } message: { _ in
            Text("preset_category_message")
        }
        .alert(
            String(localized: "preset_delete_confirm_title"),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { preset in
            Button(String(localized: "preset_delete"), role: .destructive) {
                commitDelete(preset)
            }
            Button(String(localized: "alert_cancel"), role: .cancel) {}
        } message: { preset in
            Text(String(localized: "preset_delete_message") + " " + preset.document.name)
        }
        .alert(
            String(localized: "alert_preset_failed_title"),
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ),
            presenting: failure
        ) { _ in
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .accessibilityIdentifier("presets.manager")
    }

    // MARK: - The list

    private var presetList: some View {
        List {
            ForEach(grouped, id: \.category) { section in
                Section(section.category ?? String(localized: "preset_uncategorized")) {
                    ForEach(section.presets) { preset in
                        row(preset)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ preset: StoredPreset) -> some View {
        HStack {
            Image(systemName: preset.document.kind == .develop
                ? "slider.horizontal.3" : "square.and.arrow.up")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.document.name)
                if let category = preset.document.category,
                   !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(preset.document.kind == .develop
                ? String(localized: "preset_kind_develop")
                : String(localized: "preset_kind_export"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { applyPreset(preset) }
        .contextMenu {
            if preset.document.kind == .develop {
                Button(String(localized: "preset_apply") + " \(preset.document.name)") {
                    applyPreset(preset)
                }
            }
            Button(String(localized: "preset_rename")) {
                renameText = preset.document.name
                renameTarget = preset
            }
            Button(String(localized: "preset_category_edit")) {
                categoryText = preset.document.category ?? ""
                categoryTarget = preset
            }
            Button(String(localized: "preset_export")) {
                exportPreset(preset)
            }
            Divider()
            Button(String(localized: "preset_delete"), role: .destructive) {
                deleteTarget = preset
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(preset.document.name))
        .accessibilityIdentifier("presets.manager.row.\(preset.id)")
    }

    /// The self-heal's user-visible face: bad files stay on disk, listed
    /// here, never crash the library (标坏不崩).
    private var skippedFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("preset_skipped_title")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(presetsStore.skippedFiles, id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("presets.manager.skipped")
    }

    // MARK: - Create-from-current sheet

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("preset_create_title").font(.headline)
            TextField(
                String(localized: "preset_name_label"), text: $createName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("presets.create.name")
            TextField(
                String(localized: "preset_category_label"), text: $createCategory)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("presets.create.category")
            HStack {
                Spacer()
                Button(String(localized: "alert_cancel"), role: .cancel) {
                    createPresented = false
                }
                Button(String(localized: "preset_create_button")) {
                    commitCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(createName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("presets.create.commit")
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Verbs

    private func applyPreset(_ preset: StoredPreset) {
        let id = preset.id
        Task {
            let applied = await presetController.apply(presetID: id)
            if !applied {
                failure = String(localized: "preset_apply_no_target")
            }
        }
    }

    private func commitCreate() {
        let name = createName
        let category = createCategory
        createPresented = false
        Task {
            do {
                _ = try await presetController.createPresetFromCurrent(
                    name: name,
                    category: category.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : category)
            } catch {
                failure = Self.failureMessage(error)
            }
        }
    }

    private func commitRename(_ preset: StoredPreset) {
        let name = renameText
        renameTarget = nil
        do {
            try presetsStore.rename(id: preset.id, to: name)
        } catch {
            failure = Self.failureMessage(error)
        }
    }

    private func commitCategory(_ preset: StoredPreset) {
        let category = categoryText
        categoryTarget = nil
        do {
            try presetsStore.setCategory(id: preset.id, category: category)
        } catch {
            failure = Self.failureMessage(error)
        }
    }

    private func commitDelete(_ preset: StoredPreset) {
        deleteTarget = nil
        do {
            try presetsStore.remove(id: preset.id)
        } catch {
            failure = Self.failureMessage(error)
        }
    }

    private func importPreset(from url: URL) {
        do {
            _ = try presetsStore.importPreset(from: url)
        } catch {
            failure = Self.failureMessage(error)
        }
    }

    private func exportPreset(_ preset: StoredPreset) {
        guard let destination = PresetFilePanels.exportPanel(
            suggestedName: preset.document.name) else { return }
        do {
            try presetsStore.exportFile(id: preset.id, to: destination)
        } catch {
            failure = Self.failureMessage(error)
        }
    }

    /// The typed-error → user message mapping (the XMP-import alert shape).
    private static func failureMessage(_ error: Error) -> String {
        guard let presetError = error as? PresetError else {
            return error.localizedDescription
        }
        switch presetError {
        case .emptyName:
            return String(localized: "preset_error_empty_name")
        case .notFound:
            return String(localized: "preset_error_not_found")
        case .corruptPreset(let name):
            return String(localized: "preset_error_corrupt") + " " + name
        case .invalidPreset:
            return String(localized: "preset_error_invalid")
        case .invalidExportRecipe(let name):
            return String(localized: "preset_error_invalid_recipe") + " " + name
        case .unreadableFile(let name):
            return String(localized: "preset_error_unreadable") + " " + name
        case .emptyExportRecipe:
            return String(localized: "preset_error_empty_recipe")
        case .emptyComposition:
            return String(localized: "preset_error_empty_composition")
        }
    }
}

// MARK: - The file panels (PRES-02: the panels are HOSTS only — the store
// does the byte-level copy; zero format conversion on either side)

@MainActor
internal enum PresetFilePanels {

    /// The `.lightamer-preset` UT type (extension-based; a plain data
    /// conformance is all the copy needs).
    static var presetType: UTType {
        UTType(filenameExtension: PresetsStore.fileExtension) ?? .data
    }

    /// The import host (the store validates + copies under a fresh stem).
    static func importPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "preset_import")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [presetType]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// The export host (the store copies the file bytes verbatim).
    static func exportPanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = String(localized: "preset_export")
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [presetType]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
