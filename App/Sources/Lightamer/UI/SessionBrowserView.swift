import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SessionBrowserView (Plan 09-03 T5) — the GRID mode: a LazyVGrid of cells
// over the index-driven collection (RESEARCH §5.4).
//
// Cell four-piece contract: thumbnail (memory/disk/queued tiers through the
// provider; placeholder gradient until a thumb lands — progressive ingest
// rows show it FIRST), edited badge, orphan badge (placeholder cell, no
// thumbnail work — there is no original to decode), and the rating-star
// overlay (LAYOUT ONLY — Phase 12 (META-05) fills the data; pinned here so
// the layout ships ahead of the feature).
//
// L010: identifiers only — `browser.cell.<pathhash>` is the stable row id
// (FNV-1a hex via ThumbnailPath.hash, never an index); the four-piece
// anchors ride `.thumbnail/.edited/.orphan/.rating` suffixes. No container
// labels (the L010 swallow trap).
// ─────────────────────────────────────────────────────────────────────────────

internal struct SessionBrowserView: View {

    internal enum BrowserIdentifiers {
        static let grid = "browser.grid"
        static let modeGrid = "browser.mode.grid"
        static let modeSingle = "browser.mode.single"
        static let modeCulling = "browser.mode.culling"

        /// Stable per-row id (the ThumbnailPath hex — identical to the disk
        /// thumb's file stem; L010 stable id, never an index).
        static func cell(_ pathHash: String) -> String { "browser.cell.\(pathHash)" }
    }

    /// The collection model (rows + selection data face).
    let model: SessionBrowserModel
    /// The thumbnail provider (nil = no open session / not yet wired).
    let thumbnailProvider: SessionThumbnailProvider?
    /// Double-click: open the image in the SINGLE mode through the EXISTING
    /// `EditorState.load` chain (same window — L012). The mode flip is the
    /// caller's (ContentView owns the segmented state).
    let onOpenInEditor: (URL) -> Void
    /// The session root (cell URL assembly).
    let sessionRoot: URL?
    /// 13-3 T4 (SYS-04): the GRID drop target — files dropped here import
    /// (COPY by default) into the session's `Capture/`; `move` carries the
    /// Option-modifier explicit intent. Wired by ContentView to the
    /// coordinator's import seam.
    var onImportFiles: ((_ urls: [URL], _ move: Bool) -> Void)?

    /// 12-1 T6 (META-03): the multi-select append menu items raise these
    /// one-field alerts (the value routes through MetadataController —
    /// the MetadataService single write face).
    enum AppendTarget: String, Identifiable {
        case keywords
        case note
        var id: String { rawValue }
    }
    @State private var appendTarget: AppendTarget?
    @State private var appendText = ""
    @Environment(MetadataController.self) private var metadataController

    private static let columns = [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 10)]

    /// Plan 12-2 T4: the filter bar state (chips / Quick Filter / sort —
    /// the re-query orchestration lives in SessionState).
    @Environment(SessionState.self) private var sessionState

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 10) {
                ForEach(model.rows) { row in
                    SessionBrowserCell(
                        row: row,
                        thumbnailProvider: thumbnailProvider,
                        isSelected: model.selectedPaths.contains(row.relPath),
                        onClick: { command, shift in
                            model.handleClick(row.relPath, commandPressed: command, shiftPressed: shift)
                        },
                        onDoubleClick: {
                            guard !row.orphanSidecar, let root = sessionRoot else { return }
                            onOpenInEditor(root.appendingPathComponent(row.relPath))
                        }
                    )
                    .accessibilityIdentifier(BrowserIdentifiers.cell(row.pathHash))
                    .contextMenu {
                        // HIST-05 (9-4) menu stubs — the copy face lands
                        // with Phase 12-4; v1 keeps the shape.
                        Button(String(localized: "browser_menu_copy_adjustments")) {}
                            .disabled(true)
                        Button(String(localized: "browser_menu_paste")) {}
                            .disabled(true)
                        Button(String(localized: "browser_menu_paste_partial")) {}
                            .disabled(true)
                        Divider()
                        // 12-1 T6 (META-01/03): the flag + batch-append
                        // actions — targets = the selection (the right-
                        // clicked cell joins it when outside).
                        let targets = appendTargets(for: row.relPath)
                        Button(String(localized: "browser_menu_flag_pick")) {
                            Task { await metadataController.setFlag(1, relPaths: targets) }
                        }
                        Button(String(localized: "browser_menu_flag_reject")) {
                            Task { await metadataController.setFlag(2, relPaths: targets) }
                        }
                        Button(String(localized: "browser_menu_flag_clear")) {
                            Task { await metadataController.setFlag(nil, relPaths: targets) }
                        }
                        Divider()
                        Button(String(localized: "browser_menu_append_keywords")) {
                            pendingTargets = targets
                            appendText = ""
                            appendTarget = .keywords
                        }
                        Button(String(localized: "browser_menu_append_note")) {
                            pendingTargets = targets
                            appendText = ""
                            appendTarget = .note
                        }
                    }
                }
            }
            .padding(12)
        }
        .accessibilityIdentifier(BrowserIdentifiers.grid)
        // 13-3 T4: the drop affordance + the file-URL drop leg (COPY
        // default; Option = move — the modifier is read at drop time).
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        LightamerColors.accent.opacity(0.7),
                        lineWidth: 3)
                    .padding(4)
                    .accessibilityIdentifier("browser.drop.affordance")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard onImportFiles != nil else { return false }
            Self.loadDropURLs(providers: providers) { urls in
                guard !urls.isEmpty else { return }
                onImportFiles?(urls, NSEvent.modifierFlags.contains(.option))
            }
            return true
        }
        // Plan 12-2 T4: the filter row rides the grid's top inset (visually
        // adjacent to the window toolbar's BrowserMode segmented control).
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBarView()
        }
        // The empty-filter result face (a filtered collection legitimately
        // returns zero rows — the grid must say WHY, not show a void).
        .overlay {
            if model.rows.isEmpty, sessionState.hasActiveFilter {
                ContentUnavailableView {
                    Label("filter_empty_results", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("filter_empty_results_body")
                }
            }
        }
        .alert(
            appendTarget == .keywords
                ? String(localized: "browser_menu_append_keywords")
                : String(localized: "browser_menu_append_note"),
            isPresented: Binding(
                get: { appendTarget != nil },
                set: { if !$0 { appendTarget = nil } })
        ) {
            TextField(
                appendTarget == .keywords
                    ? String(localized: "append_keywords_placeholder")
                    : String(localized: "append_note_placeholder"),
                text: $appendText)
            Button(String(localized: "alert_ok")) {
                guard let target = appendTarget else { return }
                let targets = pendingTargets
                let text = appendText
                appendTarget = nil
                Task { await performAppend(target, text: text, targets: targets) }
            }
            Button(String(localized: "alert_cancel"), role: .cancel) {
                appendTarget = nil
            }
        }
    }

    // The right-clicked cell joins the selection when outside it — the
    // append actions are batch actions (META-03).
    private func appendTargets(for relPath: String) -> [String] {
        model.selectedOrderedPaths.contains(relPath)
            ? model.selectedOrderedPaths
            : [relPath]
    }

    /// The targets captured when the alert's OK is pressed (the closure
    /// re-derivation inside the alert would lose the right-click context).
    @State private var pendingTargets: [String] = []
    /// The drop-affordance face (13-3 T4).
    @State private var isDropTargeted = false

    /// Collect ALL dropped file-URLs (the loadObject completions arrive
    /// out of order — index-sorted). The EmptyStateView single-provider
    /// pattern extended to the batch (D-13-CONTEXT-7).
    static func loadDropURLs(
        providers: [NSItemProvider], completion: @escaping ([URL]) -> Void
    ) {
        let group = DispatchGroup()
        var results = [(index: Int, url: URL)]()
        let lock = NSLock()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    results.append((index, url))
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(results.sorted { $0.index < $1.index }.map(\.url))
        }
    }

    private func performAppend(_ target: AppendTarget, text: String, targets: [String]) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch target {
        case .keywords:
            // Entry convention: comma-separated levels (the `|` path
            // separator is TYPED-BANNED — MetadataService's typed error).
            let entries = trimmed.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            _ = await metadataController.appendKeywords(entries, relPaths: targets)
        case .note:
            _ = await metadataController.appendNote(trimmed, relPaths: targets)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The cell — thumbnail + edited/orphan badges + the rating overlay shell.
// ─────────────────────────────────────────────────────────────────────────────

private struct SessionBrowserCell: View {

    let row: SessionBrowserModel.Row
    let thumbnailProvider: SessionThumbnailProvider?
    let isSelected: Bool
    let onClick: (_ command: Bool, _ shift: Bool) -> Void
    let onDoubleClick: () -> Void

    /// The resolved thumb (nil = placeholder gradient).
    @State private var thumbnail: CGImage?
    /// The relPath this @State resolved for (row reuse in LazyVGrid swaps
    /// the row under a RECYCLED cell view — the fetch task must not paint
    /// the previous row's thumb).
    @State private var resolvedFor: String?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                } else if row.orphanSidecar {
                    // Orphan placeholder: a dashed void — there is NO
                    // original to decode (never enqueue thumbnail work).
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundColor(.orange.opacity(0.7))
                        .aspectRatio(3.0 / 2.0, contentMode: .fit)
                }
                VStack {
                    HStack(spacing: 4) {
                        if row.hasEdits {
                            badge("E", color: .blue, id: "edited")
                        }
                        if row.orphanSidecar {
                            badge("?", color: .orange, id: "orphan")
                        }
                        if row.dirty {
                            badge("…", color: .yellow, id: "dirty")
                        }
                        // 12-1 T6 (META-01): the culling flag badge —
                        // P(pick) / X(reject).
                        if row.flag == 1 {
                            badge("P", color: .green, id: "flag")
                        } else if row.flag == 2 {
                            badge("X", color: .red, id: "flag")
                        }
                        Spacer()
                    }
                    Spacer()
                    // The metadata overlay (12-1 T6 — the 09-3 layout shell
                    // now carries DATA): real star fills + the color-label
                    // dot, bottom-left. `.rating` identifier unchanged.
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { star in
                            Image(systemName: star < (row.rating.map(Int.init) ?? 0)
                                ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    star < (row.rating.map(Int.init) ?? 0)
                                        ? .white.opacity(0.95) : .white.opacity(0.35))
                        }
                        if let colorLabel = row.colorLabel {
                            Circle()
                                .fill(Self.colorLabelColor(colorLabel))
                                .frame(width: 8, height: 8)
                                .accessibilityIdentifier(cellIdentifier + ".colorlabel")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(cellIdentifier + ".rating")
                }
                .padding(6)
            }
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            Text(row.filename)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture {
            // The data face owns the semantics (model.handleClick); the
            // modifiers ride NSEvent's current flags (SwiftUI tap gestures
            // drop them).
            let flags = NSEvent.modifierFlags
            onClick(flags.contains(.command), flags.contains(.shift))
        }
        .task(id: row.relPath) {
            // LAZY fetch (visible: true — the visible cell jumps the queue).
            // Orphan rows NEVER enqueue work.
            guard !row.orphanSidecar else { return }
            if resolvedFor == row.relPath, thumbnail != nil { return }
            resolvedFor = row.relPath
            let image = await thumbnailProvider?.thumbnail(for: row.relPath, visible: true)
            // A stale answer (the row moved on / cancelled teardown) never
            // paints.
            if resolvedFor == row.relPath {
                withAnimation(.easeIn(duration: 0.15)) { thumbnail = image }
            }
        }
    }

    private var cellIdentifier: String {
        "browser.cell." + row.pathHash
    }

    /// The C1 seven-color mapping (12-1 execution decision, recorded in
    /// 12-1-DECISIONS): 0 red / 1 orange / 2 yellow / 3 green / 4 blue /
    /// 5 purple / 6 gray — out-of-range values fall back to gray.
    static func colorLabelColor(_ value: Int64) -> Color {
        switch value {
        case 0: .red
        case 1: .orange
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: .gray
        }
    }

    private func badge(_ text: String, color: Color, id: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color))
            .accessibilityIdentifier(cellIdentifier + "." + id)
    }
}
