import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ExportNamingEditor (Plan M2-9-04 KD-3, OQ-9) — the file-name template
// editor inside the Inspector Export page (the Alcedo ExportNamingEditor
// face, RESEARCH §1.4):
//
//   • preset dropdown: the three BUILT-IN constants (the store's never-
//     persisted Alcedo QML spellings) + the user presets + a Custom tail;
//     selecting a preset fills the pattern;
//   • eleven token-insert buttons (`{source}` … `{sequence:0000}`) — the
//     INSERT lands at the pattern tail (the Alcedo cursor-position insert
//     simplified to an append; DECISIONS — a TextField selection handle
//     adds no value over the visible pattern here);
//   • the pattern text field + the TYPED parse feedback (an invalid
//     pattern paints the error and DISABLES the page's run/add actions —
//     the Alcedo QML:64 gate; the M2-9-01 engine's parse errors surface
//     localized + raw);
//   • the LIVE PREVIEW: the pattern rendered against a sample context
//     (queue-first stem / current-image stem; sequence = 1; absent capture
//     faces render empty — the engine's fallback face);
//   • save / rename / delete over the USER presets (built-ins are never
//     deletable — the store filters them by construction).
//
// State-layer testability: the parse/preview/token/deletable faces are
// static functions here — tests call them without mounting a view
// (KD-5: 纯状态层测).
// ─────────────────────────────────────────────────────────────────────────────

struct ExportNamingEditor: View {

    @Binding var pattern: String

    /// The live-preview sample stem: the queue's first row name when a
    /// queue exists, else the current image's stem (the page supplies it;
    /// nil → the engine's "image" fallback shows through an empty render).
    var sampleStem: String?

    /// The preset store (injected — the page owns one; tests pass an
    /// isolated-defaults store).
    var store: NamingTemplateStore

    /// The selected preset anchor (nil = the Custom tail — a hand-edited
    /// or unsaved pattern). Selecting fills the pattern; editing the
    /// pattern by hand drops the anchor to Custom.
    @State private var selectedTemplateID: UUID?
    @State private var isSaveSheetPresented = false
    @State private var saveName = ""
    @State private var renameName = ""
    @State private var isRenaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            presetPicker
            patternField
            tokenButtons
            feedbackAndPreview
            presetActionRow
        }
        .sheet(isPresented: $isSaveSheetPresented) { saveSheet }
    }

    // MARK: - Faces

    private var templates: [NamingTemplate] { store.allTemplates() }

    private var presetPicker: some View {
        Picker(String(localized: "export_naming_preset_label"), selection: presetSelection) {
            ForEach(templates) { template in
                Text(verbatim: template.name).tag(Optional(template.id))
            }
            Text(String(localized: "export_naming_custom"))
                .tag(UUID?.none)
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("export.naming.preset")
    }

    /// The dropdown's selection binding: reading maps an unknown id to the
    /// Custom tail (nil); writing a preset id fills the pattern, and the
    /// Custom tail is a pure display face (no fill).
    private var presetSelection: Binding<UUID?> {
        Binding(
            get: {
                guard let id = selectedTemplateID,
                    templates.contains(where: { $0.id == id })
                else { return nil }
                return id
            },
            set: { id in
                selectedTemplateID = id
                if let id, let template = templates.first(where: { $0.id == id }) {
                    pattern = template.pattern
                }
            })
    }

    private var patternField: some View {
        TextField(String(localized: "export_naming_pattern_hint"), text: patternBinding)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityIdentifier("export.naming.pattern")
    }

    /// Hand edits drop the anchor to Custom (the pattern is then the only
    /// truth; the dropdown shows the tail until a preset is picked again).
    private var patternBinding: Binding<String> {
        Binding(
            get: { pattern },
            set: {
                pattern = $0
                if let id = selectedTemplateID,
                    templates.first(where: { $0.id == id })?.pattern != $0 {
                    selectedTemplateID = nil
                }
            })
    }

    private var tokenButtons: some View {
        // The 11 inserts (the Alcedo QML:56-67 face) — appending at the
        // tail (DECISIONS; the pattern stays visible right below).
        FlowOrWrap {
            ForEach(Self.tokenInserts, id: \.token) { insert in
                Button(insert.token) {
                    pattern += insert.token
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(.caption2, design: .monospaced))
                .accessibilityIdentifier("export.naming.token.\(insert.identifier)")
            }
        }
    }

    @ViewBuilder
    private var feedbackAndPreview: some View {
        if let error = Self.parseFeedback(pattern) {
            // The invalid face: localized reason + the raw engine message,
            // red — and the PAGE gates its run/add actions on this same
            // face (KD-3: 模板无效 = 该节红字 + startExport 禁用).
            Label {
                Text(String(localized: "export_naming_invalid"))
                Text(verbatim: "\(error)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            .font(.caption)
            .accessibilityIdentifier("export.naming.invalid")
        } else {
            HStack(spacing: 6) {
                Text(String(localized: "export_naming_preview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: Self.livePreview(pattern, sampleStem: sampleStem))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("export.naming.preview")
        }
    }

    @ViewBuilder
    private var presetActionRow: some View {
        HStack(spacing: 10) {
            Button(String(localized: "export_naming_save_preset")) {
                saveName = ""
                isSaveSheetPresented = true
            }
            .disabled(Self.parseFeedback(pattern) != nil)
            .accessibilityIdentifier("export.naming.save")

            if let selected = selectedUserTemplate {
                if isRenaming {
                    TextField(
                        String(localized: "preset_name_label"),
                        text: $renameName)
                        .onSubmit(commitRename)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("export.naming.rename_field")
                    Button(String(localized: "alert_ok"), action: commitRename)
                        .disabled(renameName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("export.naming.rename_commit")
                } else {
                    Button(String(localized: "export_naming_rename")) {
                        renameName = selected.name
                        isRenaming = true
                    }
                    .accessibilityIdentifier("export.naming.rename")
                }
                // Built-ins never reach here (the selected-USER face).
                Button(
                    String(localized: "export_naming_delete"),
                    role: .destructive
                ) {
                    store.remove(id: selected.id)
                    selectedTemplateID = nil
                }
                .accessibilityIdentifier("export.naming.delete")
            }
        }
        .font(.caption)
    }

    /// The selected USER preset (nil for built-ins/Custom — the rename and
    /// delete actions only exist for stored presets).
    private var selectedUserTemplate: NamingTemplate? {
        guard let id = selectedTemplateID else { return nil }
        return store.loadTemplates().first { $0.id == id }
    }

    private func commitRename() {
        guard let selected = selectedUserTemplate else {
            isRenaming = false
            return
        }
        let name = renameName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.rename(id: selected.id, to: name)
        isRenaming = false
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("export_naming_save_title").font(.headline)
            TextField(String(localized: "preset_name_label"), text: $saveName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("export.naming.save_name")
            HStack {
                Spacer()
                Button(String(localized: "alert_cancel"), role: .cancel) {
                    isSaveSheetPresented = false
                }
                Button(String(localized: "preset_create_button")) {
                    let name = saveName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let template = store.add(name: name, pattern: pattern)
                    selectedTemplateID = template.id
                    isSaveSheetPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("export.naming.save_commit")
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - The state-layer faces (KD-5: tests call these, no mounting)

    /// The typed parse feedback (nil = the pattern is valid). The single
    /// gate the page's run/add buttons consult.
    static func parseFeedback(_ pattern: String) -> ExportFileNameTemplateError? {
        switch ExportFileNameTemplate.parse(pattern) {
        case .success: return nil
        case .failure(let error): return error
        }
    }

    /// The live preview stem: render against the sample context (the
    /// sample stem; sequence = 1; absent capture faces render empty), then
    /// the engine's fallback keeps it non-empty (KD-3).
    static func livePreview(_ pattern: String, sampleStem: String?) -> String {
        let context = ExportFileNameContext(
            sourceStem: sampleStem ?? ExportFileNameTemplate.fallbackStem,
            sequence: 1)
        return ExportFileNameTemplate.resolvedStem(
            pattern: pattern, context: context)
    }

    /// Built-in presets are never deletable (the store would no-op anyway
    /// — this face keeps the UI honest).
    static func isDeletable(_ template: NamingTemplate) -> Bool {
        !template.isBuiltIn
    }

    /// The eleven token inserts (the Alcedo QML:56-67 set — the OQ-4
    /// grammar's named fields; sequence carries its all-zero width arg).
    static let tokenInserts: [(identifier: String, token: String)] = [
        ("source", "{source}"),
        ("date", "{date:yyyy MM dd}"),
        ("cameramake", "{cameramake}"),
        ("cameramodel", "{cameramodel}"),
        ("lens", "{lens}"),
        ("iso", "{iso}"),
        ("aperture", "{aperture}"),
        ("shutter", "{shutter}"),
        ("focal", "{focal}"),
        ("rating", "{rating}"),
        ("sequence", "{sequence:0000}"),
    ]
}

/// The token row's line-wrap face (a plain wrapping HStack — eleven small
/// buttons in a 240-460pt column).
private struct FlowOrWrap<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // LazyVGrid over a fixed small-chip width keeps the wraps
        // predictable across the inspector's width range without a custom
        // flow layout.
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.adaptive(minimum: 96), spacing: 4), count: 3),
            alignment: .leading,
            spacing: 4
        ) {
            content
        }
    }
}
