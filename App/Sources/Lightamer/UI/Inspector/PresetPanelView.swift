import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// PresetPanelView (Plan 12-4 T3; PRES-01/PRES-04) — the Inspector's preset
// APPLY face (a fixed bottom zone beside the metadata rows, the 12-1
// MetadataInfoSection precedent).
//
// One develop preset menu (category-grouped) + two verbs per preset:
//   • 应用 — routes through PresetController: the browser/culling
//     selection when non-empty (BATCH, PRES-04), else the editor's
//     current image (live install, ONE ⌘Z).
//   • 部分应用 — reuses the 09-04 PastePartialDialog over the preset's
//     payload (the checked `InstanceKey` subset rides
//     `payload.filtered(by:)` inside the same apply path).
//
// Panel discipline (the 面板四件套): stable accessibility identifiers,
// a11y labels, the compact fixed-height zone, and zh catalog keys the
// same round (L025).
// ─────────────────────────────────────────────────────────────────────────────

internal struct PresetPanelView: View {

    @Environment(PresetsStore.self) private var presetsStore
    @Environment(PresetController.self) private var presetController

    /// The partial-apply sheet state (the preset id + its loaded payload).
    @State private var partialRequest: PartialRequest?

    /// Identifiable sheet carrier.
    internal struct PartialRequest: Identifiable {
        let id: String
        let name: String
        let payload: PastePayload
    }

    private var developPresets: [StoredPreset] {
        presetsStore.presets(kind: .develop)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("preset_panel_title")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if developPresets.isEmpty {
                Text("preset_no_presets")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                presetMenu
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(height: 32, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presets.panel")
        .sheet(item: $partialRequest) { request in
            PastePartialDialog(
                payload: request.payload,
                initialSelection: nil,
                onPaste: { selection, mode in
                    partialRequest = nil
                    let presetID = request.id
                    Task {
                        await presetController.apply(
                            presetID: presetID, selection: selection, mode: mode)
                    }
                },
                onCancel: { partialRequest = nil })
        }
    }

    /// The category-grouped preset menu (nested submenus per category;
    /// uncategorized presets sit at the top level).
    private var presetMenu: some View {
        Menu {
            ForEach(categorySections) { section in
                if let category = section.category {
                    Menu(category) {
                        ForEach(section.presets) { preset in
                            presetEntries(preset)
                        }
                    }
                } else {
                    ForEach(section.presets) { preset in
                        presetEntries(preset)
                    }
                }
            }
        } label: {
            Label(String(localized: "preset_apply_menu"), systemImage: "wand.and.stars")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("presets.apply.menu")
        .accessibilityLabel(Text("preset_apply_menu"))
    }

    @ViewBuilder
    private func presetEntries(_ preset: StoredPreset) -> some View {
        Button(String(localized: "preset_apply") + " \(preset.document.name)") {
            let id = preset.id
            Task { await presetController.apply(presetID: id) }
        }
        Button(String(localized: "preset_apply_partial")) {
            openPartial(preset)
        }
    }

    private func openPartial(_ preset: StoredPreset) {
        do {
            let document = try presetsStore.loadDocument(id: preset.id)
            let payload = PresetApplier.makePayload(
                from: document,
                copiedAt: PresetApplier.fileTime(store: presetsStore, presetID: preset.id))
            partialRequest = PartialRequest(
                id: preset.id, name: document.name, payload: payload)
        } catch {
            // The typed degrade face: a bad preset (corrupt / invalid)
            // never applies — the manager window lists it as skipped.
        }
    }

    // MARK: - Category grouping (the sidebar grouping key)

    private struct CategorySection: Identifiable {
        let category: String?
        let presets: [StoredPreset]
        var id: String { category ?? "" }
    }

    private var categorySections: [CategorySection] {
        let grouped = Dictionary(grouping: developPresets) { stored in
            stored.document.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var sections: [CategorySection] = grouped.keys
            .compactMap { $0 } // named categories first, sorted
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { CategorySection(category: $0, presets: grouped[$0] ?? []) }
        if let uncategorized = grouped[nil] {
            sections.append(CategorySection(category: nil, presets: uncategorized))
        }
        return sections
    }
}
